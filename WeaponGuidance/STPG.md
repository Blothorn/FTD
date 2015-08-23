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
`WeaponSystems` is an array indexed by the weapon group number, entries in which contain information specific to the weapons in that group. This code assumes that all components in a system are practically homogenous; assign different types of weapons to different weapon groups. And for now, only put one group of weapons on each turret. Only missiles are presently supported.

### Basic settings
+ `Type`: 0 for lasers, 1 for cannon, 2 for missiles. For turreted weapons, use the weapon type on the turret.
+ `TargetList`: The virtual mainframe that will be used for targetting.

### Firing restrictions. Note that target list restrictions determine whether a weapon system attempts to engage a target, and the weapon system settings whether it actually fires. This allows actions such as pre-aiming weapons at out-of-range (but closing) targets.
+ `MinimumAltitude`: The minimum altitude of the aimpoint. Invalid aimpoints will be projected up to this altitude for missiles in flight.
+ `MaximumAltitude`: The maximum altitude of the aimpoint. Invalid aimpoints will be projected down to this altitude for missiles in flight.
+ `MinimumRange`: The minimum range to the target. Useful primarily for off-axis missiles.
+ `MaximumRange`: Maximum range to the intercept point.
+ `FiringAngle`: Maximum deviation at which to fire. Future plans to allow for a vector3 to better accomodate missiles on turrets with no/limited elevation.

### Missile settings. These help the target prediction AI.
+ `Speed`: Expected mean speed (disregarding launch delays). This is ignored if the missile is travelling faster, but avoids missiles taking excessive leads early in their flight. Important for missiles, as their `WeaponInfo.Speed` is a fixed and inaccurate 100.
+ `LaunchDelay`: Expected delay incurred (relative to a launch at `Speed`) during launch (added flat to ttt when calculating intercept position for aiming and range calculations).
+ `LaunchElevation`: Total elevation change during launch (for dropped missiles with a delay, or missiles with angled ejection).
+ `MinimumConvergenceSpeed`: A minimum convergence speed when calculating intercept points. Useful for getting missiles to follow a fast target in the hope that he will turn back in range (with higher values sticking closer to a pursuit course), but too high a value will lead to undercorrection in otherwise valid intercept solutions.
+ `ProxRadius`: The distance from the target at which a missile will be manually detonated.
+ `SecantInterval` (optional): `Time -> Int`. The number of ticks over which to average velocity as a function of the time to target. This should usually converge to (0,0); higher values provide more smoothing but are slower to react to changes in direction. Defaults to a sensible value if nil (`math.ceil(40*ttt)`).
+ `TransceiverIndices`: The indices of the attached Lua transceivers. These will be wrong if low indices are damaged, but until `GetLuaTransceiverInfo` is fixed I cannot do anything about that. nil controls none; `'all'` controls all extant transceivers.