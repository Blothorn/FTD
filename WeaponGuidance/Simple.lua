--[[
Weapon firing AI, version 0.1.0.0
https://github.com/Blothorn/FTD for further documentation and license.
Uses STPG.lua options (many disregarded).
--]]

TargetLists = {
  AA = {
    MainframeIndex = 0,
    MinimumSpeed = 0,
    MaximumSpeed = 350,
    MinimumAltitude = -5,
    MaximumAltitude = 99999,
    MaximumRange = 1200,
    TTT = 5,
  }
}

WeaponSystems = {}

WeaponSystems[1] = {
  Type = 2,
  TargetList = 'AA',
  MaximumAltitude = 99999,
  MinimumAltitude = -3,
  MaximumRange = 900,
  MinimumRange = 100,
  FiringAngle = 60,
  Speed = 175,
  LaunchDelay = 0.3,
  MinimumConvergenceSpeed = 150,
}

Normalized = false

-- Normalize weapon configuration
function Normalize(I)
  for i = 0, 5 do
    if WeaponSystems[i] then
      local ws = WeaponSystems[i]
      ws.NextFire = -9999
      if not ws.Stagger then ws.Stagger = 0 end
      ws.Fired = 0
      if not ws.VolleySize then ws.VolleySize = 1 end
    end
  end
end

function UpdateTargets(I, gameTime)
  -- Find all target locations
  local nmf = I:GetNumberOfMainframes()
  Targets = {}

  -- Find priority targets
  for tli, tl in pairs(TargetLists) do
    local m = (tl.MainframeIndex < nmf and tl.MainframeIndex) or 0

    -- Find qualifying target
    local num = 1
    for tInd = 0, I:GetNumberOfTargets(m) - 1 do
      local t = I:GetTargetInfo(m,tInd)
      local speed = Vector3.Magnitude(t.Velocity)
      local interceptPoint = t.Position + t.Velocity * tl.TTT
      if t.Protected
         and (speed >= tl.MinimumSpeed) and (speed < tl.MaximumSpeed)
         and (Vector3.Distance(I:GetConstructPosition(), interceptPoint) < tl.MaximumRange)
         and t.AimPointPosition.y > tl.MinimumAltitude
         and t.AimPointPosition.y < tl.MaximumAltitude then
        tl.PresentTarget = t.Id
        Targets[t.Id] = {Position = t.Position, Velocity = t.Velocity}
        break
      end
    end
  end
end

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

function PredictTarget(I, tPos, target, mPos, mSpeed, delay, Interval, minConv)
   local tVel = target.Velocity
   local ttt = FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
   return tPos + tVel * (ttt+delay), ttt
end

function AimFireWeapon(I, wi, ti, gameTime)
  local w = (ti and I:GetWeaponInfoOnTurretOrSpinner(ti, wi)) or I:GetWeaponInfo(wi)
  local ws = WeaponSystems[w.WeaponSlot]
  if ws then
    local tIndex = TargetLists[ws.TargetList].PresentTarget
    if tIndex and Targets[tIndex] then
      local selfPos = w.GlobalPosition
      if ws.InheritedMovement then
        selfPos = selfPos + I:GetVelocityVector() * ws.InheritedMovement
      end
      local tPos = PredictTarget(I, Targets[tIndex].Position, Targets[tIndex], selfPos, ws.Speed,
                                 ws.LaunchDelay, ws.SecantInterval or DefaultSecantInterval,
                                 ws.MinimumConvergenceSpeed)
      local v = Vector3.Normalize(tPos - w.GlobalPosition)

      if ti then
        I:AimWeaponInDirectionOnTurretOrSpinner(ti, wi, v.x, v.y, v.z, w.WeaponSlot)
      else
        I:AimWeaponInDirection(wi, v.x, v.y, v.z, w.WeaponSlot)
      end

      if ws.WeaponType ~= 4 then
        local delayed = ws.Stagger and gameTime < ws.NextFire
        if not delayed and Vector3.Distance(w.GlobalPosition, tPos) < ws.MaximumRange
           and I:Maths_AngleBetweenVectors(w.CurrentDirection, v) < ws.FiringAngle then
          local fired = (ti and I:FireWeaponOnTurretOrSpinner(ti, wi, w.WeaponSlot))
                        or I:FireWeapon(wi, w.WeaponSlot)
          if fired then
            if ws.Stagger then
              ws.Fired = ws.Fired + 1
              if ws.Fired >= ws.VolleySize then
                ws.NextFire = gameTime + ws.Stagger
                ws.Fired = 0
              end
            end
          end
        end
      end
    end
  end
end

function Update(I)
  I:ClearLogs()
  if not Normalized then
    Normalize(I)
    Normalized = true
  end
  local gameTime = I:GetTime()

  UpdateTargets(I, gameTime)

  -- Aim and fire
  for wi = 0, I:GetWeaponCount() - 1 do
    AimFireWeapon(I, wi, nil, gameTime)
  end
  for ti = 0, I:GetTurretSpinnerCount() - 1 do
    for wi = 0, I:GetWeaponCountOnTurretOrSpinner(ti) - 1 do
      AimFireWeapon(I, wi, ti, gameTime)
    end
  end
end
