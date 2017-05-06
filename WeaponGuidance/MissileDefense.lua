--[[
Missile defense AI, version 0.0.0.0
https://github.com/Blothorn/FTD for further documentation and license.
--]]

-------------------------------------------------------------------------------
-- Configuration settings

-- Mainframe index to use for missile warnings
WarningMainframe = 0

-- The launch angles at which to launch interceptors. Use {180} to provide 360
-- degree coverage with a single battery, {45, 135} to try to use one on the
-- same face and then an adjacent face but to never launch one from the
-- opposite face, etc.
InterceptorLaunchAngles = {180}

-- The weapon group of guided interceptors
InterceptorGroup = 4

-- The weapon group of unguided interceptor grenades (turret and missile controller)
GrenadeGroup = 5

-- The maximum TTT of missiles to engage
LaunchTTT = 5

-- The maximum angle from the estimated interception point for a hostile
-- missile to be considered a threat
DangerAngle = 30

-- The maximum range (to the estimated interception point) at which to launch interceptors
InterceptorLaunchRange = 900

-- The flight time of interceptors. Used to calculate whether they can engage
-- a further target; may benefit from being very slightly high.
InterceptorEndurance = 6

-- The normal flight speed of interceptors
InterceptorSpeed = 150

-- The approximate time an interceptor will take to turn 90 degrees after launch
InterceptorTurnTime = 1

-- The maximum turn radius for an interceptor to claim a following missile
InterceptorTurnRadius = 50

-- The maximum range at which to use interceptor grenades
GrenadeLaunchRange = 150

-- The average speed of grenades (to GrenadeLaunchRange)
GrenadeSpeed = 125

-- The number of grenades on each turret
GrenadeTubes = 2

-- The traverse speed of grenade turrets (degrees/second)
GrenadeTraverse = 360

-- End configuration
-------------------------------------------------------------------------------

-- For garbage collection
Flag = 0

-- Active interceptors. Id = { Target, Flag }
Interceptors = {}

-- Number of turrets (to see when their indices need recalculation due to damage)
NumTurrets = 0
-- Grenade launchers. { Index, Target, ReloadTimes }
Grenades = {}

-- List of threats with an assigned interceptor. Id = Flag
Claimed = {}

function FindConvergence(I, tPos, tVel, wPos, wSpeed, delay, minConv)
   local relativePosition = wPos - tPos
   local distance = Vector3.Magnitude(relativePosition)
   local targetAngle = I:Maths_AngleBetweenVectors(relativePosition, tVel)
   local tSpeed = Vector3.Magnitude(tVel)

   local a = tSpeed^2 - wSpeed^2
   local b = -2 * tSpeed * distance * math.cos(math.rad(targetAngle))
   local c = distance^2
   local det = math.sqrt(b^2-4*a*c)
   local ttt = distance / minConv

   if det > 0 then
      local root1 = math.min((-b + det)/(2*a), (-b - det)/(2*a))
      local root2 = math.max((-b + det)/(2*a), (-b - det)/(2*a))
      ttt = (root1 > 0 and root1) or (root2 > 0 and root2) or ttt
   end
   return ttt
end

function IdentifyTurrets(I)
  local grenades = {}
  for wi = 0, I:GetWeaponCount() - 1 do
    local w = I:GetWeaponInfo(wi)
    if w.WeaponSlot == GrenadeGroup and w.WeaponType == 4 then
      table.insert(grenades, {Index = wi, ReloadTimes = {}})
    end
  end
  if #Grenades ~= #grenades then
    Grenades = grenades
  end
end

function Clean(gameTime)
  for k, v in pairs(Interceptors) do
    if v.Flag ~= Flag then
      Claimed[v.Target] = nil
      Interceptors[k] = nil
    end
  end
  for k, v in pairs(Claimed) do
    if v ~= Flag then
      Claimed[k] = nil
    end
  end
  for k, v in pairs(Grenades) do
    if v.ReloadTimes[1] and v.ReloadTimes[1] <= gameTime then
      table.remove(v.ReloadTimes, 1)
    end
  end
  Flag = Flag + 1
end

function TrackThreats(I)
  local ownPosition = I:GetConstructCenterOfMass()
  local ownVelocity = I:GetVelocityVector()
  local hostiles = {}
  local targets = {}
  for wi = 0, I:GetNumberOfWarnings(WarningMainframe) - 1 do
    local w = I:GetMissileWarning(WarningMainframe, wi)
    local distance = Vector3.Distance(w.Position, ownPosition)
    local convergenceSpeed = Vector3.Distance(w.Velocity, ownVelocity)
    local ttt = distance / convergenceSpeed
    local angle = I:Maths_AngleBetweenVectors(w.Position - ownPosition,
                                              ownVelocity - w.Velocity)
    if ttt > 0 and ttt < LaunchTTT and angle < DangerAngle then
      hostiles[w.Id] = w
      if Claimed[w.Id] then
        Claimed[w.Id] = Flag
      else
        table.insert(targets, {Id = w.Id, TTT = ttt})
      end
    end
  end
  table.sort(targets, function(a,b) return a.TTT < b.TTT end)

  return hostiles, targets
end

function FireGrenade(I, g, hostiles, targets, gameTime)
  local w = I:GetWeaponInfo(g.Index)
  local nextFire = (#g.ReloadTimes < GrenadeTubes and gameTime)
                   or g.ReloadTimes[1]
  if (not g.Target or not hostiles[g.Target]) and nextFire < gameTime + 1 then
    for k, t in ipairs(targets) do
      if gameTime + t.TTT - 0.75 > nextFire then
        local m = hostiles[t.Id]
        local ttt = FindConvergence(I, m.Position, m.Velocity,
                                    w.GlobalPosition, GrenadeSpeed, 0, 1)
        local v = (m.Position + m.Velocity * ttt) - w.GlobalPosition
        local angle = I:Maths_AngleBetweenVectors(w.CurrentDirection, v)
        if gameTime + ttt - 0.75 > gameTime + angle/GrenadeTraverse then
          g.Target = t.Id
          table.remove(targets, k)
        end
      end
    end
  end

  if g.Target and hostiles[g.Target] then
    local m = hostiles[g.Target]
    local ttt = FindConvergence(I, m.Position, m.Velocity, w.GlobalPosition,
                                GrenadeSpeed, 0, 1)
    local tPos = m.Position + m.Velocity * ttt
    local v = Vector3.Normalize(tPos - w.GlobalPosition)
    v.y = v.y + 0.05
    I:AimWeaponInDirection(g.Index, v.x, v.y, v.z, GrenadeGroup)
    if Vector3.Distance(w.GlobalPosition, tPos) < GrenadeLaunchRange
       and I:Maths_AngleBetweenVectors(w.CurrentDirection, v) < 3 then
      for wi = 0, I:GetWeaponCountOnTurretOrSpinner(g.Index) - 1 do
        if I:FireWeaponOnTurretOrSpinner(g.Index, wi, GrenadeGroup) then
          table.insert(g.ReloadTimes, I:GetTime() + 2.55)
          g.Target = nil
          break
        end
      end
    end
  end
end

function FireInterceptor(I, wi, hostiles, targets, gameTime, maxAngle)
  local w = I:GetWeaponInfo(wi)
  for k, t in ipairs(targets) do
    local m = hostiles[t.Id]
    local ttt = FindConvergence(I, m.Position, m.Velocity,
                                w.GlobalPosition, GrenadeSpeed, 0, 1)
    local v = (m.Position + m.Velocity * ttt) - w.GlobalPosition
    local angle = I:Maths_AngleBetweenVectors(w.CurrentDirection, v)
    if angle < maxAngle then
      I:AimWeaponInDirection(wi, v.x, v.y, v.z, InterceptorGroup)
      local fired = I:FireWeapon(wi, InterceptorGroup)
      if fired then
        Claimed[t.Id] = Flag
        return t.Id
      end
    end
  end
end

function GuideInterceptor(I, ti, mi, hostiles, gameTime, target)
  local mInfo = I:GetLuaControlledMissileInfo(ti, mi)
  if not Interceptors[mInfo.Id] then
    Interceptors[mInfo.Id] = { Target = target }
--    I:SetLuaControlledMissileInterceptorStandardGuidanceOnOff(ti, mi, false)
  end
  local i = Interceptors[mInfo.Id]
  i.Flag = Flag
  local m = hostiles[i.Target]
  if m then
    local speed = math.max(InterceptorSpeed, Vector3.Magnitude(mInfo.Velocity))
    local ttt = FindConvergence(I, m.Position, m.Velocity,
                                mInfo.Position, speed, 0.75*speed, 1)
    local tPos = m.Position + m.Velocity * ttt * 1.1
    I:SetLuaControlledMissileAimPoint(ti, mi, tPos.x, tPos.y,tPos.z)
  end
end

function Update(I)
  I:ClearLogs()
  local gameTime = I:GetTimeSinceSpawn()
  if I:GetTurretSpinnerCount() ~= NumTurrets then
    IdentifyTurrets(I)
    NumTurrets = I:GetTurretSpinnerCount()
  end

  local hostiles, targets = TrackThreats(I)
  for k, g in ipairs(Grenades) do
    FireGrenade(I, g, hostiles, targets, gameTime)
  end

  local target
  for k, angle in ipairs(InterceptorLaunchAngles) do
    if target then break end
    for wi = 0, I:GetWeaponCount() - 1 do
      if I:GetWeaponInfo(wi).WeaponSlot == InterceptorGroup then
        target = FireInterceptor(I, wi, hostiles, targets, gameTime, angle)
        if target then break end
      end
    end
  end

  for ti = 0, I:GetLuaTransceiverCount() - 1 do
    for mi = 0, I:GetLuaControlledMissileCount(ti) - 1 do
      if I:IsLuaControlledMissileAnInterceptor(ti,mi) then
        GuideInterceptor(I, ti, mi, hostiles, gameTime, target)
      end
    end
  end

  Clean(gameTime)
end
