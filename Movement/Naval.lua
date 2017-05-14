--[[
  Naval AI, version 0.0.0
  https://github.com/Blothorn/FTD for further documentation and license.
--]]

-- User settings.

-- Course is updated only every kCourseUpdatePeriod seconds, except when
-- crossing max/min broadside range or approaching shallows; those conditions
-- are checked every kConditionCheckPeriod seconds.
kCourseUpdatePeriod = 30  -- Seconds.
kConditionCheckPeriod = 1  -- Seconds.

-- The range the AI will seek to maintain.
kPreferredRange = 4200

-- Beyond this range the AI attempts an intercept course (ignoring broadside
-- angles).
kMaxBroadsideRange = 7000

-- Within this range the AI turns directly away.
kMinBroadsideRange = 1000

-- When broadsiding, the AI will attempt to keep the target at least this far
-- behind the bow.
kMinBroadsideAngle = 45

-- When broadsiding, the AI will attempt to keep the target ahead of this
-- angle from the bow.
kMaxBroadsideAngle = 135

-- PID settings for rudder control.
kRudderPidSettings = {kP = 0.01, kI = 0.001, kD = 0.04, integralMin = -100,
                      integralMax = 100, outMin = -1, outMax = 1}

-- The local coordinates of rudder spinblocks. If nil, this uses the default
-- steering commands.
kRudderSpinnerPositions = nil

-- Maximum deflection for spinblock rudders.
kMaxRudderDeflection = 45

----- Terrain avoidance settings -----
-- The minimum depth to seek when avoiding terrain. This is polled sparsely, so
-- leave a generous margin to allow for bumps.
kMinDepth = 15

-- How far ahead to look for terrain collisions. This should be at least the
-- vessel's turning radius.
kTerrainLookaheadDistance = 750

-------------------------------------------------------------------------------
-- Default constants. Only adjust these if you know what you are doing.
kTerrainLookaheadIncrement = 50
kTerrainAvoidanceScanIncrement = 30

-------------------------------------------------------------------------------
-- Common utilities library (pasted)

-- Returns x clamped to [min, max], and whether the clamp was binding.
function Clamp(x, min, max)
  if x <= min then
    return min, true
  elseif x >= max then
    return max, true
  else
    return x, false
  end
end

-- Returns the normalized projection of a vector onto the horizontal plane.
function Horizontal(v)
  local newV = v
  newV.y = 0
  return newV.normalized
end

-- Returns the reciprocal angle in (-180,180].
function ReciprocalAngle(angle)
  return ((angle + 360) % 360) - 180
end

-- PID controller, with integral windup protection.
-- Interface:
--   controller = PID:New()
--   control = controller:Step(setpoint, state)
PID = {}
PID.Step_ = function(self, setpoint, state)
  local error = setpoint - state
  local p = self.kP_ * error
  local i = self.kI_ * (self.integral_ + error)
  local d = self.kD_ * (error - self.lastError_)

  output, binding = Clamp(p + i + d, self.outMin_, self.outMax_)

  -- Do not add to the integral if the constraint is binding to avoid windup
  -- after setpoint changes.
  -- TODO: Investigate the risk of loss of convergence when the integral
  --       drives the binding.
  if not binding then
    self.integral_ = Clamp(self.integral_ + error, self.integralMin_,
                          self.integralMax_)
  end

  self.lastError_ = error

  return output
end

PID.New = function(self, kP, kI, kD, integralMin, integralMax, outMin, outMax)
  local new = {}
  new.kP_ = kP
  new.kI_ = kI
  new.kD_ = kD
  new.integralMin_ = integralMin
  new.integralMax_ = integralMax
  new.outMin_ = outMin
  new.outMax_ = outMax
  new.integral_ = 0
  new.lastError_ = 0
  -- Hack since FTD does not have setmetatable
  new.Step = self.Step_
  return new
end

-------------------------------------------------------------------------------
-- Internal settings--you probably do not need to change these.

-- Initialization
STATE = {}
STATE.lastCourseOffset = nil
STATE.lastCourseTarget = nil
STATE.nextCourseChangeTime = -math.huge
STATE.nextConditionCheckTime = -math.huge
STATE.lastTargetId = nil
STATE.mode = "idle"  -- idle, close, broadside, retreat, terrain
STATE.rudderController = PID:New(kRudderPidSettings.kP or 0,
                                 kRudderPidSettings.kI or 0,
                                 kRudderPidSettings.kD or 0,
                                 kRudderPidSettings.integralMin or -math.huge,
                                 kRudderPidSettings.integralMax or math.huge,
                                 kRudderPidSettings.outMin or -45,
                                 kRudderPidSettings.outMax or 45)
STATE.courseController = PID:New(0.1, 0, 0.05, 0, 0, kMinBroadsideAngle - 90,
                                 kMaxBroadsideAngle - 90)
STATE.rudderSpinnerIndices = {}
STATE.lastSpinnerCount = 0

function IdentifyRudderSpinners(I)
  local indices = {}
  local count = I:GetSpinnerCount()
  for i=0, count - 1 do
    local position = I:GetSpinnerInfo(i).LocalPosition
    for _, p in ipairs(kRudderSpinnerPositions) do
      if (position.x == p.x and position.y == p.y and position.z == p.z) then
        table.insert(indices, i)
      end
    end
  end
  I:Log(string.format('controlling %d rudders', #indices))
  STATE.lastSpinnerCount = count
  return indices
end

-- Returns a course toward/away from the target if it is within minimum or
-- outside maximum range, and null otherwise.
function CheckExtremeRange(targetPosition)
  if targetPosition.Range > kMaxBroadsideRange then
    return -targetPosition.Azimuth
  elseif targetPosition.Range < kMinBroadsideRange then
    return -ReciprocalAngle(targetPosition.Azimuth)
  end
end

function BroadsideCourse(I, targetPosition)
  -- The angle off the beam at which we want to hold the target (not signed for
  -- the correct side). Negative means toward the bow.
  local desiredAngleOffBeam =
      STATE.courseController:Step(kPreferredRange, targetPosition.Range)
  -- The negative is because targetPosition.Azimuth signs its left/right side
  -- opposite of everything else.
  local side = targetPosition.Azimuth / math.abs(targetPosition.Azimuth)
  -- The desired angle at which we want to hold the target from the bow in
  -- (-180,180]
  local desiredAngleOffBow = side * (desiredAngleOffBeam + 90)
  return desiredAngleOffBow - targetPosition.Azimuth
end

-- Returns the distance to the first point at which the terrain height is above
-- MinDepth in 'direction' from 'position', or nil if none is found within
--  kTerrainLookaheadDistance. 'direction' should be a normalized Vector3 in
-- the horizontal plane.
function SafeDistanceInDirection(I, position, direction)
  for distance = kTerrainLookaheadIncrement,
                 kTerrainLookaheadDistance,
                 kTerrainLookaheadIncrement do
    local samplePosition = position + direction * distance
    if I:GetTerrainAltitudeForPosition(samplePosition) > -kMinDepth then
      return distance
    end
  end
end

-- Returns the closest course to 'course' thought to satisfy terrain avoidance
-- constraints.
function SafeCourse(I, course)
  local forward = Quaternion.Euler(0, course, 0)
                  * Horizontal(I:GetConstructForwardVector())
  local position = I:GetConstructPosition()
  if (not SafeDistanceInDirection(I, position, forward)) then
    return course
  end
  
  local bestCourse = course
  local bestDistance = -1
  for angle = kTerrainAvoidanceScanIncrement, 179,
              kTerrainAvoidanceScanIncrement do
    local leftDirection = Quaternion.Euler(0, -angle, 0) * forward
    local leftDistance = SafeDistanceInDirection(I, position, leftDirection)
    if (not leftDistance) then
      return -angle
    end
    if (leftDistance > bestDistance) then
      bestCourse = course - angle
      bestDistance = leftDistance
    end
    
    local rightDirection = Quaternion.Euler(0, angle, 0) * forward
    local rightDistance = SafeDistanceInDirection(I, position, rightDirection)
    if (not rightDistance) then
      return angle
    end
    if (rightDistance > bestDistance) then
      bestCourse = course + angle
      bestDistance = rightDistance
    end 
  end
  return bestCourse
end


function SetRudder(I, course)
  local rudder = STATE.rudderController:Step(course, 0)
  if kMaxRudderDeflection then
    -- Use spinblock rudder
    for _, rudderIndex in ipairs(STATE.rudderSpinnerIndices) do
      I:SetSpinnerRotationAngle(rudderIndex, rudder * kMaxRudderDeflection)
    end
  else
    -- Use stock rudder
    if rudder < -0.1 then
      I:RequestControl(0, 0, -rudder)
    elseif rudder > 0.1 then
      I:RequestControl(0, 1, rudder)
    end
  end
end

function Update(I)
  -- Desired course, relative to present course. (For some reason the builtins
  -- prefer relative to absolute azimuths.)
  local course = nil

  if I:GetNumberOfMainframes() <= 0 or I:GetNumberOfTargets(0) <= 0 then
    course = 0
  end

  if (kRudderSpinnerPositions and
      I:GetSpinnerCount() ~= STATE.lastSpinnerCount) then
    STATE.rudderSpinnerIndices = IdentifyRudderSpinners(I);
  end

  local now = I:GetTime()
  local targetInfo = I:GetTargetInfo(0, 0)

  if now > STATE.nextConditionCheckTime then
    local targetPosition = I:GetTargetPositionInfo(0, 0)
    STATE.nextConditionCheckTime = now + kConditionCheckPeriod
    course = CheckExtremeRange(targetPosition)
    if not course and
       (now > STATE.nextCourseChangeTime or
        targetInfo.Id ~= STATE.lastTargetId) then
      STATE.nextCourseChangeTime = now + kCourseUpdatePeriod
      course = BroadsideCourse(I, targetPosition)
    end
    if course then
      STATE.lastCourseOffset = course
      STATE.lastCourseTargetPosition =
          I:GetConstructPosition() + I:GetConstructForwardVector() * 1000000
    end
  end

  if not course then
    local lastCourseTarget =
        I:GetTargetPositionInfoForPosition(0,
                                           STATE.lastCourseTargetPosition.x,
                                           STATE.lastCourseTargetPosition.y,
                                           STATE.lastCourseTargetPosition.z)
    course = -lastCourseTarget.Azimuth + STATE.lastCourseOffset
  end

  I:RequestControl(0, 8, 1)
  SetRudder(I, SafeCourse(I, course))

  STATE.lastCourse = course
  STATE.lastTargetId = targetInfo.Id
end