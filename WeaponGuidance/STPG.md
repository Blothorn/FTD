# Notes
This partially implements a comprehensive weapon system built around a target prediction algorithm using secant approximations to improve resolution of velocity predictions (at close range) and smoothing of erratic behaviour (at long range). It performs relatively poorly against targets turning steadily, such as orbiters; this can be mitigated with low secant width settings, and more precise solutions are under consideration.

Because the game scales the number of ticks per second when the game speed is changed, this calculates incorrect target velocities and thus intercept points when the game is slowed down manually (as opposed to simply lagging).

# Parameter documentation
## Globals
+ `TargetBufferSize`: The number of ticks of position information kept. Higher numbers allow greater smoothing (accompanied by slower response to manuevers) at the expense of memory use. 40 ticks = 1 second.
+ `AimPointMainframeIndex`: A mainframe using aimpoint.
+ `NonAimPointMainframeIndex`: A mainframe not using aimpoint.

## Target lists
To account for the target prioritization card's ambivalence to target direction, range, and altitude, weapons controlled by this code take their targets from filtered target lists. `TargetLists` is an array of such lists.
+ `MainframeIndex`: The preferred mainframe to use for target prioritization. Presently wrong if mainframes are damaged.
+ `MinimumSpeed`: The minimum speed of the target.
+ `MaximumSpeed`: The maximum speed of the target.
+ `MinimumAltitude`: The minimum altitude of the aimpoint.
+ `MaximumAltitude`: The maximum altitude of the aimpoint.
+ `MaximumRange`: The maximum range.
+ `TTT`: This flighttime will be used to calculate an intercept point and that checked against the maximum range; it should usually be based on the flight time to maximum range; setting it slightly high will do a better job of pre-aligning weapons so that they can fire when the target enters range (an increased `TTT` is preferred ot an increased `MaximumRange` for this use as the latter will also allow targets just outside true maximum range but not closing)
+ `Aimpoint`: Whether to use aimpoint. `0` will never use it, `1` will use it and select a different target if the present one violates the altitude restrictions. `2` will try both aimpoint and non-aimpoint mainframes for a valid target position.
+ `PresentTarget`: The index of the present target (set automatically).

## WeaponSystems
`WeaponSystems` is an array indexed by the weapon group number containing information specific to the weapons in that group. This code assumes that all components in a system are practically homogenous; assign different types of weapons to different weapon groups. And for now, only put one group of weapons on each turret. Only missiles and lasers are presently supported.

+ `Type`: 0 for lasers, 1 for cannon, 2 for missiles. For turreted weapons, use the weapon type on the turret.
+ `TargetList`: The virtual mainframe that will be used for targetting.
+ `MinimumAltitude`: The minimum altitude of the aimpoint. Invalid aimpoints will be projected up to this altitude.
+ `MaximumAltitude`: The maximum altitude of the aimpoint. Invalid aimpoints will be projected down to this altitude.
+ `MinimumRange`: The minimum range to the target. Useful primarily for off-axis missiles.
+ `MaximumRange`: Maximum range to the intercept point (calculated using speed/delay TTT).
+ `FiringAngle`: Maximum deviation at which to fire. Future plans to allow for a vector3 to better accomodate missiles on turrets with no/limited elevation.
+ `Speed`: Expected mean speed. Used for calculations before flight time is calculated. Important for missiles, as their `WeaponInfo.Speed` is a fixed and inaccurate 100.
+ `LaunchDelay`: Expected delay incurred (relative to a launch at `Speed`) during launch (added flat to ttt when calculating intercept position for aiming and range calculations).
+ `MinimumConvergenceSpeed`: A minimum convergence speed when calculating intercept points. Useful for getting missiles to follow a fast target in the hope that he will turn back in range (with higher values sticking closer to a pursuit course), but too high a value will lead to undercorrection in otherwise valid intercept solutions.
+ `ProxRadius`: The distance from the target at which a missile will be manually detonated.
+ `ProxAngle`: The angle to the aimpoint required for a proximity detonation (for narrow frags).
+ `SecantInterval`: `Time -> Int`. The number of ticks over which to average velocity as a function of the time to target. This should usually converge to (0,0); `math.ceil(40*ttt)` works well.
+ `CullSpeed`: The speed below which missiles will be manually detonated. Useful for preserving system resources (particularly with thumpers, which are of little use after slowing down).
+ `TransceiverIndices`: The indices of the controlled Lua missiles. These will be wrong if low indices are damaged, but until `GetLuaTransceiverInfo` is fixed I cannot do anything about that.
+ `TTTIterationThreshold`: If calculating an intercept point yields a proportional change in TT above this threshold, it will be recalculated with the new TTT.
+ `TTTMaxIterations`: The maximum number of iterations to converge on a TTT. 0 will use `TargetInfo.Velocity`. These are potentially expensive, so keep low.
+ `UseAimpointVelocity`: Whether to calculate the velocity from the aimpoint or the vehicle position. Aimpoint velocity is noisier but more precise, particularly when the aimpoint target is far from the vehicle position. It does jump noticeably whenever the aimpoint is destroyed; best used for weapons firing distinct volleys (travel time less than reload time).
