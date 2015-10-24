--[[
Weapon guidance AI, version 2.0.1.0
https://github.com/Blothorn/FTD for further documentation and license.
--]]

-- Globals
TargetBufferSize = 120
ConvergenceIterationThreshold = 0.005
ConvergenceMaxIterations = 25

WeaponSystems = {}

-- Sample configuration
WeaponSystems[1] = {
  Type = 2,
  MainframeIndex = 0,
  MaximumAltitude = 99999,
  MinimumAltitude = -3,
  MinimumSpeed = 0,
  MaximumSpeed = 350,
  MinimumRange = 100,
  FiringAngle = 60,
  Speed = 250,
  LaunchDelay = 0.3,
  MinimumConvergenceSpeed = 150,
  Endurance = 3.33,
  MinimumCruiseAltitude = 5,
  MaximumCruiseAltitude = 9999,
  DetonateOnCull = true,
  MaximumTargets = 2,
  TurnSpeed = 100,
  Direction = 'Forward',
}

Flag = 0
Normalized = false

DefaultSecantInterval = function(ttt)
  return math.max(math.min(math.ceil(40*ttt/2), 100), 1)
end

-- Target buffers
Targets = {}
Missiles = {}

for i = 0, 5 do
  if WeaponSystems[i] and WeaponSystems[i].Type == 2 then
    DefaultMissileGroup = i
    break
  end
end

function Angle(a, b)
  return math.deg(math.acos(Vector3.Dot(a, b)
                            / (Vector3.Magnitude(a) * Vector3.Magnitude(b))))
end

function GroundDistance(a, b)
  return math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2)
end

-- Normalize weapon configuration
function Normalize(I)
  for i = 0, 5 do
    if WeaponSystems[i] then
      local ws = WeaponSystems[i]
      ws.NextFire = -9999
      if ws.AimPointProportion and ws.AimPointProportion > 0 then
        ws.AimPointCounter = 1
      end
      if ws.AttackPatterns then ws.AttackPatternIndex = 1 end
      if not ws.Stagger then ws.Stagger = 0 end
      ws.Fired = 0
      if not ws.VolleySize then ws.VolleySize = 1 end
      if not ws.MaximumTargets then ws.MaximumTargets = 1 end
      if not ws.LaunchEndurance then
        ws.LaunchEndurance = ws.Endurance - 0.5
      end
      if not ws.TargetEndurance then
        ws.TargetEndurance = ws.LaunchEndurance
      end
      if not ws.CullTime then
        ws.CullTime = ws.Endurance + 0.5
      end
      if not ws.SecantInterval then
        ws.SecantInterval = DefaultSecantInterval
      end
      if not ws.CruiseThreshold then
        ws.CruiseThreshold = 75
      end
    end
  end
end

function NewTarget(I, v)
  return {
    AimPoints = {},
    Index = 0,
    AimPointIndex = 0,
    NumMissiles = 0,
    NumFired = 0,
    Velocity = v,
  }
end

function Direction(d)
  if not Direction then
    return nil
  elseif Direction == 'Forward' then
    return I:GetConstructForwardVector()
  elseif Direction == 'Backward' then
    return -I:GetConstructForwardVector()
  elseif Direction == 'Up' then
    return I:GetconstructUpVector()
  elseif Direction == 'Down' then
    return -I:GetconstructUpVector()
  elseif Direction == 'Left' then
    return -I:GetconstructLeftVector()
  elseif Direction == 'Right' then
    return I:GetconstructRightVector()
  end
end

function UpdateTargets(I, gameTime)
  -- Find all target locations
  local nmf = I:GetNumberOfMainframes()
  local TargetLocations = {}

  -- Aimpoint locations
  for ti = 0, I:GetNumberOfTargets(0) - 1 do
    local t = I:GetTargetInfo(0,ti)
    TargetLocations[t.Id] = {t.AimPointPosition}
  end

  -- Non-aimpoint locations
  for mfi = 1, nmf - 1 do
    for ti = 0, I:GetNumberOfTargets(mfi) - 1 do
      local t = I:GetTargetInfo(mfi,ti)
      if TargetLocations[t.Id]
         and t.AimPointPosition ~= TargetLocations[t.Id][1] then
        table.insert(TargetLocations[t.Id], t.AimPointPosition)
      end
    end
  end

  local ownPos = I:GetConstructCenterOfMass()
  -- Find priority targets
  for wsi = 0, 5 do
    local ws = WeaponSystems[wsi]
    if ws then
      local m = (ws.MainframeIndex < nmf and ws.MainframeIndex) or 0

      -- Find qualifying target
      ws.PresentTargets = {}
      local num = 1
      for tInd = 0, I:GetNumberOfTargets(m) - 1 do
        local t = I:GetTargetInfo(m,tInd)
        local speed = Vector3.Magnitude(t.Velocity)
        local tPos, ttt =
          PredictTarget(I, 0, t.Position,
                        Targets[t.Id] or {Velocity = t.Velocity, Index = 0},
                        ownPos, ws.Speed, ws.LaunchDelay, ws.SecantInterval, 1,
                        Direction(ws.Angle), ws.TurnSpeed)
        if t.Protected and TargetLocations[t.Id]
           and (speed >= ws.MinimumSpeed) and (speed < ws.MaximumSpeed)
           and ttt < ws.TargetEndurance then
          local found = false
          for k, p in ipairs(TargetLocations[t.Id]) do
            if (p.y > ws.MinimumAltitude) and (p.y < ws.MaximumAltitude) then
              found = true
              break
            end
          end
          if found then
            ws.PresentTargets[num] = t.Id
            if not Targets[t.Id] then
              Targets[t.Id] = NewTarget(I, t.Velocity)
            end
            Targets[t.Id].Flag = Flag
            num = num + 1
            if num > ws.MaximumTargets then break end
          end
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
  Flag = Flag + 1

  -- Update target info
  for tInd = 0, I:GetNumberOfTargets(0) - 1 do
    local t = I:GetTargetInfo(0, tInd)
    if Targets[t.Id] then
      if not t.Protected then
        Targets[t.Id] = nil
      else
        local tar = Targets[t.Id]

        if tar.Index <= TargetBufferSize then
          tar.Index = tar.Index + 1
        else
          tar.Index = 1
          tar.Wrapped = true
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
  interval = math.min(interval, ((not target.Wrapped) and (target.Index - 1))
                                or TargetBufferSize - 1)
  if interval > 0 then
    -- Use secant approximation to smooth
      local oldPos = target[((target.Index - interval) % TargetBufferSize) + 1]
      return (target[target.Index] - oldPos) * (40 / interval)
   else
     return target.Velocity
  end
end

function PredictTarget(I, guess, tPos, target, wPos, wSpeed, delay, Interval,
           minConv, heading, turnSpeed)
  local relativePos = tPos - wPos
  local distance = Vector3.Magnitude(relativePos)
  local x0
  local fx0

  for i = 1, ConvergenceMaxIterations do
    local tVel = PredictVelocity(I, target, Interval(guess))
    local predictedPos = relativePos + tVel * guess
    local turnTime = (not heading and 0)
                     or Angle(heading, predictedPos) / turnSpeed
    local new = Vector3.Magnitude(predictedPos) / wSpeed + delay + turnTime
    if math.abs(new - guess) < ConvergenceIterationThreshold then
      guess = math.min(guess, distance / minConv)
      return tPos + tVel * guess, guess
    end
    local x1 = guess
    local fx1 = guess - new
    if i == 1 then
      local a = math.min(1, wSpeed / Vector3.Magnitude(tVel))
      guess = (a * new + (1-a) * guess);
    else
      guess = x1 - fx1 * (x1 - x0) / (fx1 - fx0)
    end
    x0 = x1
    fx0 = fx1
  end
  -- Fallthrough
  I:Log('Falling through')
  local guess = distance / minConv
  return tPos + PredictVelocity(I, target, Interval(guess)) * guess, guess
end

function FindAimpoint(aps, target, m, ws)
  local aps = Targets[m.Target].AimPoints
  if #aps == 1 then m.AimPointIndex = 1; return end
  local api
  if target.AimPoints[m.AimPointIndex] then
    api = m.AimPointIndex
  elseif ws.AimPointProportion then
    if ws.AimPointCounter >= 1 then
      api = 1
      ws.AimPointCounter = ws.AimPointCounter - 1 + ws.AimPointProportion
    else
      api = target.AimPointIndex + 2
      target.AimPointIndex = (target.AimPointIndex + 1) % (#aps - 1)
      ws.AimPointCounter = ws.AimPointCounter + ws.AimPointProportion
    end
  else
    api = target.AimPointIndex + 1
    target.AimPointIndex = (target.AimPointIndex + 1) % #aps
  end
  local bestErr = 99999

  for i = 0, #aps - 1 do
    local api2 = ((api - 1 + i) % (#aps)) + 1
    local candidate = aps[api2]
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
end

function AimFireWeapon(I, wi, ti, gameTime, groupFired)
  local w = (ti and I:GetWeaponInfoOnTurretOrSpinner(ti, wi)) or I:GetWeaponInfo(wi)
  if WeaponSystems[w.WeaponSlot] then
    local ws = WeaponSystems[w.WeaponSlot]
    if (groupFired and (ws.Type == 2 and w.WeaponSlot ~= groupFired))
       or (w.WeaponType ~= 4 and ws.Stagger and gameTime < ws.NextFire) then
      return
    end
    local tIndex = nil
    for k, t in ipairs(ws.PresentTargets) do
      if not (ws.LimitFire and ws.MissilesPerTarget)
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
      local tPos, ttt =
        PredictTarget(I, 0, Targets[tIndex].AimPoints[1], Targets[tIndex],
                      selfPos, ws.Speed, ws.LaunchDelay, ws.SecantInterval,
                      ws.MinimumConvergenceSpeed, w.CurrentDirection,
                      ws.TurnSpeed)
      local v = Vector3.Normalize(tPos - w.GlobalPosition)

      if ti then
        I:AimWeaponInDirectionOnTurretOrSpinner(ti, wi, v.x, v.y, v.z,
                                                w.WeaponSlot)
      else
        I:AimWeaponInDirection(wi, v.x, v.y, v.z, w.WeaponSlot)
      end

      if w.WeaponType ~= 4 then
        local delayed = ws.Stagger and gameTime < ws.NextFire
        if not delayed and ttt < ws.LaunchEndurance
           and Angle(w.CurrentDirection, v) < ws.FiringAngle then
          local fired =
            (ti and I:FireWeaponOnTurretOrSpinner(ti, wi, w.WeaponSlot))
            or I:FireWeapon(wi, w.WeaponSlot)
          if fired then
            if ws.Stagger then
              ws.Fired = ws.Fired + 1
              if ws.Fired >= ws.VolleySize then
                ws.NextFire = gameTime + ws.Stagger
                ws.Fired = 0
              end
            end
            Targets[tIndex].NumFired = Targets[tIndex].NumFired + 1
            groupFired = w.WeaponSlot
          end
        end
      end
    end
  end
  return groupFired
end

function GuideMissile(I, ti, mi, gameTime, groupFired)
  local mInfo = I:GetLuaControlledMissileInfo(ti, mi)
  if I:IsLuaControlledMissileAnInterceptor(ti,mi) then
    return
  end
  if not Missiles[mInfo.Id] then
    Missiles[mInfo.Id] = { Flag = Flag,
         Group = (groupFired or DefaultMissileGroup) }
    local ws = WeaponSystems[Missiles[mInfo.Id].Group]
    if ws.AttackPatterns then
      Missiles[mInfo.Id].AttackPattern =
  ws.AttackPatterns[ws.AttackPatternIndex]
      ws.AttackPatternIndex = (ws.AttackPatternIndex % #ws.AttackPatterns) + 1
    end
  else
    Missiles[mInfo.Id].Flag = Flag
  end
  local m = Missiles[mInfo.Id]
  local ws = WeaponSystems[m.Group]
  if mInfo.TimeSinceLaunch > ws.CullTime then
    if ws.DetonateOnCull then I:DetonateLuaControlledMissile(ti,mi) end
  else
    if m.Target == nil or Targets[m.Target] == nil then
      m.TTT = nil
      local best = 99999
      local bestIndex = 1
      for k, t in ipairs(ws.PresentTargets) do
        if not ws.MissilesPerTarget or Targets[t].NumMissiles < ws.MissilesPerTarget then
          bestIndex = t
          break
        else
          if Targets[t].NumMissiles < best then
            best = Targets[t].NumMissiles
            bestIndex = t
          end
        end
      end

      m.Target = bestIndex
      if Targets[m.Target] then
        Targets[m.Target].NumMissiles = Targets[m.Target].NumMissiles + 1
      end
    end

    local target = Targets[m.Target]
    if target then
      target.Flag = Flag
      if m.ResetTime and gameTime > m.ResetTime
         or not target.AimPoints[m.AimPointIndex] then
        FindAimpoint(Targets[m.Target].AimPoints, target, m, ws)
        m.ResetTime = gameTime + 0.25
      end

      local aimPoint = (m.AimPointIndex and target.AimPoints[m.AimPointIndex])
                       or target.AimPoints[1]

      if ws.ProxRadius
         and Vector3.Distance(aimPoint, mInfo.Position) < ws.ProxRadius then
        I:DetonateLuaControlledMissile(ti,mi)
        return
      end

      local mSpeed = math.max(Vector3.Magnitude(mInfo.Velocity), ws.Speed)
      local tPos, ttt =
        PredictTarget(I, m.TTT or 0, aimPoint, target, mInfo.Position, mSpeed,
                      0, ws.SecantInterval or DefaultSecantInterval,
                      ws.MinimumConvergenceSpeed, mInfo.Velocity, ws.TurnSpeed)
      m.TTT = ttt - 1/40
      if ttt < 1 then m.ResetTime = gameTime end
      local floor = false
      if GroundDistance(mInfo.Position, tPos)
         > 0.3 * math.abs(mInfo.Position.y - tPos.y) + ws.CruiseThreshold then
        tPos.y = math.min(math.max(tPos.y, ws.MinimumCruiseAltitude),
			                    ws.MaximumCruiseAltitude)
        floor = true
      end
      if m.AttackPattern then
        local tttAdj = m.TTTadj or ttt
        local q = Quaternion.LookRotation(tPos - mInfo.Position, Vector3(0,1,0))
        local v = m.AttackPattern
                  * math.min(math.max(0, tttAdj - ws.PatternConvergeTime),
                             ws.PatternTimeCap)
        tPos = tPos + q*v
        if floor then
          tPos.y = math.min(math.max(tPos.y, ws.MinimumCruiseAltitude),
			                      ws.MaximumCruiseAltitude)
        end
        m.TTTadj = Vector3.Distance(tPos, mInfo.Position) / mSpeed
      end
      I:SetLuaControlledMissileAimPoint(ti, mi, tPos.x, tPos.y,tPos.z)
    end
  end
end

LastUpdate = -999999

function Update(I)
  I:ClearLogs()
  if not Normalized then
    Normalize(I)
    Normalized = true
  end
  local gameTime = I:GetTime()
  if gameTime < LastUpdate + 0.024 then
    return
  else
    LastUpdate = gameTime
  end

  UpdateTargets(I, gameTime)

  local groupFired
  -- Aim and fire
  for wi = 0, I:GetWeaponCount() - 1 do
    groupFired = AimFireWeapon(I, wi, nil, gameTime, groupFired)
  end
  for ti = 0, I:GetTurretSpinnerCount() - 1 do
    for wi = 0, I:GetWeaponCountOnTurretOrSpinner(ti) - 1 do
      groupFired = AimFireWeapon(I, wi, ti, gameTime, groupFired)
    end
  end

  -- Guide missiles
  for ti = 0, I:GetLuaTransceiverCount() - 1 do
    for mi = 0, I:GetLuaControlledMissileCount(ti) - 1 do
      GuideMissile(I, ti, mi, gameTime, groupFired)
    end
  end
end
