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
