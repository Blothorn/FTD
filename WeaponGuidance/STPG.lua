-- See Readme in git repository for parameter documentation
-- Globals
TargetBufferSize = 30
AimPointMainframeIndex = 0
NonAimPointMainframeIndex = nil

TargetLists = {
  AA = {
    MainframeIndex = 0,
      MinimumSpeed = 0,
      MaximumSpeed = 250,
      MinimumAltitude = -5,
      MaximumAltitude = 99999,
    MaximumRange = 1000,
    TTT = 2
  }
}

WeaponSystems = {}

-- Sample configuration (Dart AA thumpers)
WeaponSystems[1] = {
    Type = 2,
    TargetList = 'AA',
    MaximumAltitude = 99999,
    MinimumAltitude = -3,
    MaximumRange = 800,
    MinimumRange = 100,
    FiringAngle = 60,
    Speed = 150,
    LaunchDelay = 0.3,
    LaunchElevation = -15,
    MinimumConvergenceSpeed = 50,
    ProxRadius = nil,
    SecantInterval = function(ttt) return math.ceil(40*ttt/2) end,
    CullSpeed = 50,
    TransceiverIndices = {0,1},
    TTTIterationThreshold = 0.1,
    TTTMaxIterations = 3,
    SecantPoint = 'Position'
}

flag = 0

-- Target buffers
Targets = {}
Missiles = {}

function NewTarget(I, targetInfo)
  return {
    Position = { targetInfo.Position },
    AimPoint = { targetInfo.AimPointPosition },
    Index = 1,
    Wrapped = 0,
    Flag = flag,
    Velocity = targetInfo.Velocity
  }
end

function Length(vel)
  return math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
end

function UpdateTargets(I)
  -- Find priority targets
  local nmf = I:GetNumberOfMainframes()
  for tli, tl in pairs(TargetLists) do
    local m = 0
    if tl.MainframeIndex < nmf then
      m = tl.MainframeIndex
    end

    -- Find qualifying target
    tl.PresentTarget = nil
    for tInd = 0, I:GetNumberOfTargets(m) - 1 do
       local t = I:GetTargetInfo(m,tInd)
       local speed = Length(t.Velocity)
       local interceptPoint = t.Position + t.Velocity * tl.TTT
       if (t.AimPointPosition.y > tl.MinimumAltitude)
         and (t.AimPointPosition.y < tl.MaximumAltitude)
         and (speed > tl.MinimumSpeed)
         and (speed < tl.MaximumSpeed)
         and (Length(I:GetConstructPosition() - interceptPoint) < tl.MaximumRange) then
           tl.PresentTarget = t.Id
           if not (Targets[t.Id]) then
             Targets[t.Id] = NewTarget(I, t)
           end
           break
       end
    end
  end

  -- Cull unused targets
  for i, t in ipairs(Targets) do
    if t.Flag ~= flag then
      Targets[i] = nil
    end
  end
  for i, t in ipairs(Missiles) do
    if t.Flag ~= flag then
      Missiles[i] = nil
    end
  end
  flag = flag+1 % 2

  -- Update target info
  local ami = 0
  if AimPointMainframeIndex < nmf then
    ami = AimPointMainframeIndex
  end

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
        tar.Position[tar.Index] = t.Position
        tar.AimPoint[tar.Index] = t.AimPointPosition
      end
    end
  end
end

-- I -> Position -> Time -> Velocity
function PredictVelocity(I, target, aimpoint, interval)
  local aimpoint = 'Position'
  -- Calculate the interval to use
  if target.Wrapped == 0 then
    interval = target.Index-1
  else
    interval = math.min(interval, TargetBufferSize-1)
  end

  local velocity = target.Velocity
  if interval > 0 then
    -- Use secant approximation to smooth
      local oldPos = target[aimpoint][((target.Index - interval) % TargetBufferSize) + 1]
      velocity = (target[aimpoint][target.Index] - oldPos) * (40 / interval)
   end
   return velocity
end

function FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
   -- Calculates a time at which the missiles potential sphere intersects the target's track
   local relativePosition = tPos - mPos
   local distance = Length(relativePosition)
   local targetAngle = I:Maths_AngleBetweenVectors(relativePosition, tVel)
   local targetSpeed = Length(tVel)

   -- Find time to earliest possible convergence point
   local a = targetSpeed^2 - mSpeed^2
   local b = 2 * targetSpeed * mSpeed * math.cos(math.rad(targetAngle))
   local c = distance^2
   local det = math.sqrt(b^2-4*a*c)
   local ttt = 0

   if det < 0 then
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

function PredictTarget(I, target, mPos, mSpeed, delay, Interval, minConv)
   tPos = target.Position[target.Index]
   tVel = target.Velocity
   aPos = target.AimPoint[target.Index]
   -- Find an initial ttt to find the secant width
   local ttt = FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
   -- Find the secant velocity
   local secantVelocity = PredictVelocity(I, target, aPos, Interval(ttt+delay))

   -- Use this to refine the TTT guess
   ttt = FindConvergence(I, tPos, secantVelocity, mPos, mSpeed, delay, minConv)
   secantVelocity = PredictVelocity(I, target, aPos, Interval(ttt+delay))
   return aPos + secantVelocity * (ttt+delay)
end

function Update(I)
  I:ClearLogs()
  UpdateTargets(I, target)

  -- Aim and fire
  for i = 0, I:GetWeaponCount() - 1 do
    local w = I:GetWeaponInfo(i)
    if WeaponSystems[w.WeaponSlot] then
      local ws = WeaponSystems[w.WeaponSlot]
      tIndex = TargetLists[ws.TargetList].PresentTarget
      if Targets[tIndex] then
        local tPos = PredictTarget(I, Targets[tIndex], w.GlobalPosition, ws.Speed, ws.LaunchDelay, ws.SecantInterval, ws.MinimumConvergenceSpeed)
        tPos.y = tPos.y - ws.LaunchElevation
        local vector = tPos - w.GlobalPosition
        vector = vector / Length(vector)
        I:AimWeaponInDirection(i, vector.x, vector.y, vector.z, w.WeaponSlot)

        local angle = I:Maths_AngleBetweenVectors(w.CurrentDirection, vector)
        if Length(w.GlobalPosition - tPos) < ws.MaximumRange and angle < ws.FiringAngle then
          I:FireWeapon(i, w.WeaponSlot)
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
            if Missiles[mInfo.Id] == nil or Targets[Missiles[mInfo.Id]] == nil then
              Missiles[mInfo.Id] = { Target = TargetLists[ws.TargetList].PresentTarget }
            end

            Missiles[mInfo.Id].Flag = flag
            local target = Targets[Missiles[mInfo.Id].Target]
            if target then
              target.Flag = flag

              if ws.ProxRadius and Length(target.AimPoint[target.Index] - mInfo.Position) < ws.ProxRadius then
                I:DetonateLuaControlledMissile(trans,m)
              end

              local mSpeed = math.max(Length(mInfo.Velocity), ws.Speed)
              tPos = PredictTarget(I, target, mInfo.Position, ws.Speed, 0, ws.SecantInterval, ws.MinimumConvergenceSpeed)
              tPos.y = math.min(ws.MaximumAltitude, math.max(tPos.y, ws.MinimumAltitude))
              I:SetLuaControlledMissileAimPoint(trans, mi, tPos.x, tPos.y,tPos.z)
            end
          end
        end
      end
    end
  end
end
