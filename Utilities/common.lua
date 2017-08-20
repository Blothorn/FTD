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

PID.New = function(self, parameters, defaults)
  local new = {}
  new.kP_ = parameters.kP or defaults.kP
  new.kI_ = parameters.kI or defaults.kI
  new.kD_ = parameters.kD or defaults.kD
  new.integralMin_ = parameters.integralMin or defaults.integralMin
  new.integralMax_ = parameters.integralMax or defaults.integralMax
  new.outMin_ = parameters.outMin or defaults.outMin
  new.outMax_ = parameters.outMax or defaults.outMax
  new.integral_ = 0
  new.lastError_ = 0
  -- Hack since FTD does not have setmetatable
  new.Step = self.Step_
  return new
end

-- Iterative convergence finder for non-linear flight paths.

-- The maximum number of iterations, regardless of convergence.
kConvergenceMaxIterations = 20
-- The maximum error in estimated time-to-target accepted.
kConvergenceIterationThreshold = 0.005

-- Returns the convergence position and time-to-target for the provided
-- parameters using Newton's method.
-- function(number time)->Vector3 targetPosition: A callback that computes the
--   estimated target position given a time.
-- function(Vector3 target)->number flightTime: A callback that computes the
--   estimated flight time to reach a target position.
-- number? guess: an estimated convergence time, used as a starting point for
--   speed and to increase the probability of converging to the best solution
--   when there are alternatives.
function FindConvergence(targetPosition, flightTime, guess)
  local guess = guess or 0
  local x0
  local fx0
  for i = 1, kConvergenceMaxIterations do
    local estimatedTime = flightTime(targetPosition(guess))

    local x1 = guess
    local fx1 = guess - estimatedTime
    if i == 1 then
      guess = estimatedTime
    else
      guess = x1 - fx1 * (x1 - x0) / (fx1 - fx0)
    end
    x0 = x1
    fx0 = fx1
  end

  I:Log('Falling through to direct pursuit')
  return targetPosition(0), 0
end

-- Helper function that creates a position estimate for linear velocity.
function linearVelocityPredictor(position, velocity)
	return function(time) return position + velocity * time end
end

-- Helper function that creates a time-to-target estimate using constant speed.
function constantSpeedPredictor(position, speed)
	return function(targetPosition)
		return Vector3.Magnitude(targetPosition - position) / speed
	end
end
