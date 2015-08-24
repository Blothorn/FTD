# Notes
This partially implements a comprehensive weapon system built around a target prediction algorithm using secant approximations to improve resolution of velocity predictions (at close range) and smoothing of erratic behaviour (at long range). It performs relatively poorly against targets turning steadily, such as orbiters; this can be mitigated with low secant width settings, and more precise solutions are under consideration.

Because the game scales the number of ticks per second when the game speed is changed, this calculates incorrect target velocities and thus intercept points when the game is slowed down manually (as opposed to simply lagging).

# Parameter documentation
## Globals
+ `TargetBufferSize`: The number of ticks of position information kept. Higher numbers allow greater smoothing (accompanied by slower response to manuevers) at the expense of memory use. 40 ticks = 1 second.
+ `AimPointMainframeIndex`: A mainframe using aimpoint.
+ `NonAimPointMainframeIndex`: A mainframe not using aimpoint.
+ `TTTIterationThreshold`: Since secant width depends on time to target, and TTT on the estimated velocity, this code recalculates the TTT and velocity if the previous update changed velocity by more than `TTTIterationThreshold`.
+ `TTTMaxIterations`: The maximum number of such iterations to perform.

## Target lists
To account for the target prioritization card's ambivalence to target direction, range, and altitude, weapons controlled by this code take their targets from filtered target lists. `TargetLists` is an array of such lists.
+ `MainframeIndex`: The preferred mainframe to use for target prioritization. Presently wrong if mainframes are damaged.
+ `MinimumSpeed`: The minimum speed of the target.
+ `MaximumSpeed`: The maximum speed of the target.
+ `MinimumAltitude`: The minimum altitude of the aimpoint.
+ `MaximumAltitude`: The maximum altitude of the aimpoint.
+ `MaximumRange`: The maximum range.
+ `TTT`: This flighttime will be used to calculate an intercept point and that checked against the maximum range; it should usually be based on the flight time to maximum range; setting it slightly high will do a better job of pre-aligning weapons so that they can fire when the target enters range (an increased `TTT` is preferred ot an increased `MaximumRange` for this use as the latter will also allow targets just outside true maximum range but not closing)

## WeaponSystems
`WeaponSystems` is an array indexed by the weapon group number, entries in which contain information specific to the weapons in that group. This code assumes that all components in a system are practically homogenous; assign different types of weapons to different weapon groups. And for now, only put one group of weapons on each turret. Only missiles are presently supported.

### Basic settings
+ `Type`: 0 for lasers, 1 for cannon, 2 for missiles. For turreted weapons, use the weapon type on the turret.
+ `TargetList`: The virtual mainframe that will be used for targetting.
+ `Stagger`: Minimum time between consecutive firings. Applies per controller (and is thus completely seperate from stagger among the missiles attached to a controller). Defaults to none.
+ `SecantInterval` (optional): `Time -> Int`. The number of ticks over which to average velocity as a function of the time to target. This should usually converge to (0,0); higher values provide more smoothing but are slower to react to changes in direction. Defaults to a sensible value if nil (`math.ceil(40*ttt)`).

### Firing restrictions.
Note that target list restrictions determine whether a weapon system attempts to engage a target, and the weapon system settings whether it actually fires. This allows actions such as pre-aiming weapons at out-of-range (but closing) targets.
+ `MinimumAltitude`: The minimum altitude of the aimpoint. Invalid aimpoints will be projected up to this altitude for missiles in flight.
+ `MaximumAltitude`: The maximum altitude of the aimpoint. Invalid aimpoints will be projected down to this altitude for missiles in flight.
+ `MinimumRange`: The minimum range to the target. Useful primarily for off-axis missiles.
+ `MaximumRange`: Maximum range to the intercept point.
+ `FiringAngle`: Maximum deviation at which to fire. Future plans to allow for a vector3 to better accomodate missiles on turrets with no/limited elevation.

### Missile settings.
These help the target prediction AI.
+ `Speed`: Expected mean speed (disregarding launch delays). This is ignored if the missile is travelling faster, but avoids missiles taking excessive leads early in their flight. Important for missiles, as their `WeaponInfo.Speed` is a fixed and inaccurate 100.
+ `LaunchDelay`: Expected delay incurred (relative to a launch at `Speed`) during launch (added flat to ttt when calculating intercept position for aiming and range calculations).
+ `InheritedMovement`: Amount of movement inherited from launch vehicle, useful primarily for dumbfire rockets (where it should usually be 1/3). Expressed as seconds of launch vehicle velocity (applied as translation of launcher position)/
+ `MinimumConvergenceSpeed`: A minimum convergence speed when calculating intercept points. Useful for getting missiles to follow a fast target in the hope that he will turn back in range (with higher values sticking closer to a pursuit course), but too high a value will lead to undercorrection in otherwise valid intercept solutions.
+ `ProxRadius`: The distance from the target at which a missile will be manually detonated.
+ `TransceiverIndices`: The indices of the attached Lua transceivers. These will be wrong if low indices are damaged, but until `GetLuaTransceiverInfo` is fixed I cannot do anything about that. nil controls none; `'all'` controls all extant transceivers.

# Implementation notes
Target prediction uses secant approximations to estimate future target velocity and then uses the law of cosines to calculate an intercept point (finding the time that solves for a triangle given distance to target, angle (from the target's perspective) between the missile or launch point and the target's velocity, and target and projectile speeds).

The `flag` global variable  and the `.Flag` fields in `Targets` and `Missiles` implement a rudimentary tracing garbage collection.
A GC cycle includes missile targeting in one tick (setting the flag for living missiles and active missile targets), calculation of target list priority targets in the next generation (flagging those targets), and finishes with deleting entries whose flag has not been set that cycle and flipping the flag.
If replacing the missile guidance code, be sure to set the flag for whatever entries in those tables you want to persist.
