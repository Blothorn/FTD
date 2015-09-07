-- See Readme in git repository for parameter documentation
-- Globals
TargetBufferSize = 120
AimPointMainframeIndex = 0
NonAimPointMainframeIndices = nil
TTTIterationThreshold = 5
TTTMaxIterations = 4

TargetLists = {
  AA = {
    MainframeIndex = 0,
    MinimumSpeed = 0,
    MaximumSpeed = 350,
    MinimumAltitude = -5,
    MaximumAltitude = 99999,
    MaximumRange = 1200,
    TTT = 5,
    Depth = 2,
  }
}

WeaponSystems = {}

-- Sample configuration (Dart AA thumpers)
WeaponSystems[1] = {
  Type = 2,
  TargetList = 'AA',
  Stagger = 0.5,
  MaximumAltitude = 99999,
  MinimumAltitude = -3,
  MaximumRange = 800,
  MinimumRange = 100,
  FiringAngle = 60,
  Speed = 175,
  LaunchDelay = 0.3,
  MinimumConvergenceSpeed = 150,
  ProxRadius = nil,
  TransceiverIndices = 'all',
  AimPointProportion = 0.5,
  Endurance = 5,
  MinimumCruiseAltitude = 3,
  MissilesPerTarget = 1,
  MissilesPerLaunch = 1,
}

Flag = 0
normalized = false

DefaultSecantInterval = function(ttt) return math.min(math.ceil(40*ttt/2), 100) end

-- Target buffers
Targets = {}
Missiles = {}

-- Normalize weapon configuration
function Normalize(I)
  for i = 0, 5 do
    if WeaponSystems[i] then
      local ws = WeaponSystems[i]
      ws.LastFired = -9999
      if ws.AimPointProportion > 0 then
        ws.AimPointCounter = 1
      end
      if not ws.MissilesPerLaunch then ws.MissilesPerLaunch = 1 end
      if ws.TransceiverIndices == 'all' then
        ws.TransceiverIndices = {}
        for i = 0, I:GetLuaTransceiverCount() - 1 do
          table.insert(ws.TransceiverIndices, i)
        end
      end
    end
  end
  for k, tl in pairs(TargetLists) do
    if not tl.Depth then tl.Depth = 1 end
  end
end

function NewTarget(I)
  return {
    AimPoints = {},
    Index = 0,
    Wrapped = 0,
    AimPointIndex = 0,
    NumMissiles = 0,
    NumFired = 0,
  }
end

function UpdateTargets(I, gameTime)
  -- Find all target locations
  local nmf = I:GetNumberOfMainframes()
  local TargetLocations = {}
  local ami = 0
  if AimPointMainframeIndex < nmf then
    ami = AimPointMainframeIndex
  end

  -- Aimpoint locations
  for ti = 0, I:GetNumberOfTargets(ami) - 1 do
    local t = I:GetTargetInfo(ami,ti)
    TargetLocations[t.Id] = {t.AimPointPosition}
  end

  -- Non-aimpoint locations
  if NonAimPointMainframeIndices then
    for k, mfi in ipairs(NonAimPointMainframeIndices) do
      if mfi < nmf then
        for ti = 0, I:GetNumberOfTargets(mfi) do
          local t = I:GetTargetInfo(mfi,ti)
          if TargetLocations[t.Id] then
            table.insert(TargetLocations[t.Id], t.AimPointPosition)
          end
        end
      end
    end
  end

  -- Find priority targets
  for tli, tl in pairs(TargetLists) do
    local m = 0
    if tl.MainframeIndex < nmf then
      m = tl.MainframeIndex
    end

    -- Find qualifying target
    tl.PresentTarget = {}
    local num = 1
    for tInd = 0, I:GetNumberOfTargets(m) - 1 do
       local t = I:GetTargetInfo(m,tInd)
       local speed = Vector3.Magnitude(t.Velocity)
       local interceptPoint = t.Position + t.Velocity * tl.TTT
       if t.Protected
         and (speed >= tl.MinimumSpeed) and (speed < tl.MaximumSpeed)
         and (Vector3.Distance(I:GetConstructPosition(), interceptPoint) < tl.MaximumRange) then
        local found = false
        for k, p in ipairs(TargetLocations[t.Id]) do
          if (p.y > tl.MinimumAltitude) and (p.y < tl.MaximumAltitude) then
            found = true
            break
          end
        end
        if found then
          tl.PresentTarget[num] = t.Id
          if not Targets[t.Id] then
            Targets[t.Id] = NewTarget(I)
          end
          Targets[t.Id].Flag = Flag
          num = num + 1
          if num > tl.Depth then break end
        end
      end
    end
  end

  -- Cull unused targets
  for i, t in pairs(Targets) do
    if t.Flag ~= Flag then
      Targets[i] = nil
    else
      t.NumFired = 0
    end
  end
  for i, m in pairs(Missiles) do
    if m.Flag ~= Flag then
      if Targets[m.Target] then
        Targets[m.Target].NumMissiles = Targets[m.Target].NumMissiles - 1
      end
      Missiles[i] = nil
    end
  end
  Flag = (Flag+1) % 2

  -- Update target info
  for tInd = 0, I:GetNumberOfTargets(ami) - 1 do
    local t = I:GetTargetInfo(ami, tInd)
    if Targets[t.Id] then
      if not t.Protected then
        Targets[t.Id] = nil
      else
        local tar = Targets[t.Id]

        if tar.Index <= TargetBufferSize then
          tar.Index = tar.Index + 1
        else
          tar.Index = 1
          tar.Wrapped = 1
        end

        tar.Velocity = t.Velocity
        tar[tar.Index] = t.Position
        tar.AimPoints = TargetLocations[t.Id]
      end
    end
  end
end

-- I -> Position -> Time -> Velocity
function PredictVelocity(I, target, interval)
  -- Calculate the interval to use
  if target.Wrapped == 0 then
    interval = target.Index-1
  else
    interval = math.min(interval, TargetBufferSize-1)
  end

  local velocity = target.Velocity
  if interval > 0 then
    -- Use secant approximation to smooth
      local oldPos = target[((target.Index - interval) % TargetBufferSize) + 1]
      velocity = (target[target.Index] - oldPos) * (40 / interval)
   end
   return velocity
end

function FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
   -- Calculates a time at which the missiles potential sphere intersects the target's track
   local relativePosition = mPos - tPos
   local distance = Vector3.Magnitude(relativePosition)
   local targetAngle = I:Maths_AngleBetweenVectors(relativePosition, tVel)
   local targetSpeed = Vector3.Magnitude(tVel)

   -- Find time to earliest possible convergence point
   local a = targetSpeed^2 - mSpeed^2
   local b = -2 * targetSpeed * distance * math.cos(math.rad(targetAngle))
   local c = distance^2
   local det = math.sqrt(b^2-4*a*c)
   local ttt = distance / minConv

   if det > 0 then
      local root1 = math.min((-b + det)/(2*a), (-b - det)/(2*a))
      local root2 = math.max((-b + det)/(2*a), (-b - det)/(2*a))
      if root1 > 0 then
         ttt = root1
      elseif root2 > 0 then
         ttt = root2
      end
   end
   return ttt
end

function PredictTarget(I, tPos, target, mPos, mSpeed, delay, Interval, minConv)
   local tVel = target.Velocity
   -- Find an initial ttt to find the secant width
   local ttt
   if Vector3.Distance(mPos, tPos) / mSpeed < 0.75 then
     ttt = FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
   else
     ttt = 1/40
   end
   for i = 1, TTTMaxIterations do
     local oldVel = tVel
     tVel = PredictVelocity(I, target, Interval(ttt+delay))
     -- Use the secant velocity to refine the TTT guess
     ttt = FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
     if Vector3.Distance(oldVel, tVel) < TTTIterationThreshold then
       break
     end
   end
   return tPos + tVel * (ttt+delay), ttt
end

function Update(I)
  I:ClearLogs()
  if not normalized then
    Normalize(I)
    normalized = true
  end
  local gameTime = I:GetTime()

  UpdateTargets(I, gameTime)

  -- Aim and fire
  for i = 0, I:GetWeaponCount() - 1 do
    local w = I:GetWeaponInfo(i)
    if WeaponSystems[w.WeaponSlot] then
      local ws = WeaponSystems[w.WeaponSlot]
      local tIndex = nil
      for k, t in ipairs(TargetLists[ws.TargetList].PresentTarget) do
        if not ws.MissilesPerTarget
           or Targets[t].NumMissiles + Targets[t].NumFired < ws.MissilesPerTarget then
          tIndex = t
          break
        end
      end
      if tIndex and Targets[tIndex] then
        local selfPos = w.GlobalPosition
        if ws.InheritedMovement then
          selfPos = selfPos + I:GetVelocityVector() * ws.InheritedMovement
        end
        local tPos = PredictTarget(I, Targets[tIndex].AimPoints[1], Targets[tIndex], selfPos, ws.Speed,
                                   ws.LaunchDelay, ws.SecantInterval or DefaultSecantInterval,
                                   ws.MinimumConvergenceSpeed)

        local vector = Vector3.Normalize(tPos - w.GlobalPosition)
        I:AimWeaponInDirection(i, vector.x, vector.y, vector.z, w.WeaponSlot)

        local angle = I:Maths_AngleBetweenVectors(w.CurrentDirection, vector)
        local isDelayed = (ws.Stagger) and gameTime < ws.LastFired + ws.Stagger
        if Vector3.Distance(w.GlobalPosition, tPos) < ws.MaximumRange
           and angle < ws.FiringAngle and not isDelayed then
          local fired = I:FireWeapon(i, w.WeaponSlot)
          if fired then
            ws.LastFired = gameTime
            Targets[tIndex].NumFired = Targets[tIndex].NumFired + 1
          end
        end
      end
    end
  end

  -- Guide missiles
  for wsi = 0, 5 do
    local ws = WeaponSystems[wsi]
    if ws and ws.TransceiverIndices then
      for ind, trans in ipairs(ws.TransceiverIndices) do
        if I:GetLuaTransceiverInfo(trans).Valid then
          for mi = 0, I:GetLuaControlledMissileCount(trans) - 1 do
            local mInfo = I:GetLuaControlledMissileInfo(trans, mi)
            if mInfo.TimeSinceLaunch < ws.Endurance then
              if not Missiles[mInfo.Id] then
                Missiles[mInfo.Id] = { Flag = Flag }
              else
                Missiles[mInfo.Id].Flag = Flag
              end
              local m = Missiles[mInfo.Id]
              if m.Target == nil or Targets[m.Target] == nil then
                local best = 99999
                local bestIndex = 1
                local found = false
                for k, t in ipairs(TargetLists[ws.TargetList].PresentTarget) do
                  if Targets[t].NumMissiles < ws.MissilesPerTarget then
                    m.Target = t
                    found = true
                    break
                  else
                    if Targets[t].NumMissiles < best then
                      best = Targets[t].NumMissiles
                      bestIndex = t
                    end
                  end
                  if not found then
                    m.Target = bestIndex
                  end
                end
                if Targets[m.Target] then
                  Targets[m.Target].NumMissiles
                    = Targets[m.Target].NumMissiles + ws.MissilesPerLaunch
                end
              end

              local target = Targets[m.Target]
              if target then
                target.Flag = Flag

                local aimPoint = 0
                if not m.AimPointIndex or gameTime > m.ResetTime
                   or not target.AimPoints[m.AimPointIndex] then
                  local api = target.AimPointIndex + 2
                  local aps = Targets[m.Target].AimPoints
                  if target.AimPoints[m.AimPointIndex] then
                    api = m.AimPointIndex
                  elseif ws.AimPointCounter >= 1 then
                    api = 1
                    ws.AimPointCounter = ws.AimPointCounter - 1 + ws.AimPointProportion
                  else
                    target.AimPointIndex = (target.AimPointIndex + 1) % #aps
                    ws.AimPointCounter = ws.AimPointCounter + ws.AimPointProportion
                  end
                  local bestErr = 99999

                  for i = 0, #aps - 1 do
                    local api2 = ((api - 1 + i) % (#aps)) + 1
                    local candidate = aps[api2]
                    local err = 0
                    if candidate.y < ws.MaximumAltitude then
                      if candidate.y > ws.MinimumAltitude then
                        m.AimPointIndex = api2
                        break
                      elseif ws.MinimumAltitude - candidate.y < bestErr then
                        m.AimPointIndex = api2
                        bestErr = ws.MinimumAltitude - candidate.y
                      end
                    elseif candidate.y - ws.MinimumAltitude < bestErr then
                      m.AimPointIndex = api2
                      bestErr = candidate.y - ws.MinimumAltitude
                    end
                  end
                  m.ResetTime = gameTime + 0.25
                end

                local aimPoint = target.AimPoints[m.AimPointIndex]

                if ws.ProxRadius and Vector3.Distance(aimPoint, mInfo.Position) < ws.ProxRadius then
                  I:DetonateLuaControlledMissile(trans,mi)
                end

                local mSpeed = math.max(Vector3.Magnitude(mInfo.Velocity), ws.Speed)
                local tPos, ttt = PredictTarget(I, aimPoint, target, mInfo.Position, ws.Speed, 0,
                                                ws.SecantInterval or DefaultSecantInterval,
                                                ws.MinimumConvergenceSpeed)
                if ttt > 0.5 and mInfo.Position.y > 3*ws.MinimumCruiseAltitude then
                  tPos.y = math.max(tPos.y, ws.MinimumCruiseAltitude)
                end
                I:SetLuaControlledMissileAimPoint(trans, mi, tPos.x, tPos.y,tPos.z)
              end
            end
          end
        end
      end
    end
  end
end
