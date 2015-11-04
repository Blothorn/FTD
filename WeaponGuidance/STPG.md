# Notes
This partially implements a comprehensive weapon system built around a target prediction algorithm using secant approximations to improve resolution of velocity predictions (at close range) and smoothing of erratic behaviour (at long range). It performs relatively poorly against targets turning steadily, such as orbiters; this can be mitigated with low secant width settings, and more precise solutions are under consideration.

Warning: Do not use the stagger fire block or launch delays on guided missiles (unless you only have one group of Lua-controlled missiles); using those features causes miscorrelation of missiles and their weapon group. There is a Lua-side stagger, although to launch missiles individually it requires giving each missile its own controller.

For turret-mounted weapons, set the turret to the weapon group of the weapon you want to control the turret's aim (usually the least manueverable, if there is more than one), and set weapon controllers on the turret appropriately. This code will now appropriately stagger launches from multiple weapons on the same turret.

# Abbreviations/definitions
+ TTT: Time to target

# Parameter documentation
## Globals
+ `TargetBufferSize`: The number of ticks of position information kept. Higher numbers allow greater smoothing (accompanied by slower response to manuevers) at the expense of memory use. 40 ticks = 1 second.
+ `ConvergenceIterationThreshold`: The maximum time differential between the target's and missile's estimated time to the proposed intercept point for it to be accepted.
+ `ConvergenceMaxIterations`: The maximum number of such iterations to perform.

## WeaponSystems
`WeaponSystems` is an array indexed by the weapon group number, entries in which contain information specific to the weapons in that group. This code assumes that all components in a system are practically homogenous; assign different types of weapons to different weapon groups. And for now, only put one group of weapons on each turret. Only missiles are presently supported.

### Basic settings
+ `Type`: 0 for lasers, 1 for cannon, 2 for missiles. For turreted weapons, use the weapon type on the turret.
+ `MainframeIndex`: The preferred mainframe to use for target prioritization. Presently wrong if mainframes are damaged.
+ `Stagger`: Optional; defaults to 0. Minimum time between volleys firings. Applies per controller (and is thus completely separate from stagger among the missiles attached to a controller). Defaults to none.
+ `VolleySize`: Optional; defaults to 1. The number of missiles to fire each volley (separated by Stagger).
+ `SecantInterval` (optional): `Time -> Int`. The number of ticks over which to average velocity as a function of the time to target. This should usually converge to (0,0); higher values provide more smoothing but are slower to react to changes in direction. Defaults to a sensible value if nil (`math.ceil(40*ttt)`).
+ `AimPointProportion`: The proportion of shots aimed at the aimpoint, rather than a random block. Has no effect unless both `AimPointMainframeIndex` and `NonAimPointMainframeIndices` are accurately populated. What effect this has depends on the weapon system; presently only implemented for guided missiles.

### Firing restrictions.
Note that target list restrictions determine whether a weapon system attempts to engage a target, and the weapon system settings whether it actually fires. This allows actions such as pre-aiming weapons at out-of-range (but closing) targets. Note also that targets persist, so all restrictions only apply at time of launch.
+ `MinimumAltitude`: The minimum altitude of the aimpoint.
+ `MaximumAltitude`: The maximum altitude of the aimpoint.
+ `MinimumSpeed`: The minimum speed of the target.
+ `MaximumSpeed`: The maximum speed of the target.
+ `MinimumRange`: The minimum range to the target. Useful primarily for off-axis missiles.
+ `FiringAngle`: Maximum deviation at which to fire. Future plans to allow for a vector3 to better accomodate missiles on turrets with no/limited elevation.
+ `LaunchEndurance` (optional, defaults to `Endurance - 0.5`): The maximum estimated flight time for launch.
+ `TargetEndurance` (optional, defaults to LaunchEndurance): The maximum estimated flight time to enter a target on the list. Useful primarily for turreted missiles, to get the turret turning before the target is in range.

### Missile settings.
These help the target prediction AI.
+ `Speed`: Expected mean speed (disregarding launch delays). This is ignored if the missile is travelling faster, but avoids missiles taking excessive leads early in their flight. Important for missiles, as their `WeaponInfo.Speed` is a fixed and inaccurate 100.
+ `LaunchDelay`: Expected delay incurred (relative to a launch at `Speed`) during launch (added flat to ttt when calculating intercept position for aiming and range calculations).
+ `InheritedMovement`: Amount of movement inherited from launch vehicle, useful primarily for dumbfire rockets (where it should usually be 1/3). Expressed as seconds of launch vehicle velocity (applied as translation of launcher position)/
+ `MinimumConvergenceSpeed`: A minimum convergence speed when calculating intercept points. Useful for getting missiles to follow a fast target in the hope that he will turn back in range (with higher values sticking closer to a pursuit course), but too high a value will lead to undercorrection in otherwise valid intercept solutions.
+ `ProxRadius`: The distance from the target at which a missile will be manually detonated.
+ `ignoreSpeed`: The speed below which the missile will not be guided. Reduces lag if missiles are missing.
+ `MinumumCruiseAltitude`: The minimum altitude to travel at when more than 0.5s from the target.
+ `MissilesPerTarget` (optional): The number of missiles to fire at each eligible target.
+ `LimitFire`: Optional, defaults to false. Whether to restrict the number of missiles fired if `MissilesPerTarget` missiles have already been fired at each eligible target.
+ `DetonateOnCull`: Optional, defaults to false. Whether to detonate the missile when its endurance is exceeded (to reduce lag).
+ `Endurance`: The number of seconds the missile has propulsion. For submarines, add the maximum expected time to clear the water.
+ `CullTime` (optional, defaults to `Endurance + 0.5`): The time at which the missile will stop receiving guidance (and detonate, if DetonateOnCull is set).
+ `Direction` (optional, ignored by default): The mount direction for fixed missiles. Allows target selection to account for reduced range when firing off-bore.
+ `TurnSpeed`: The turn rate in degrees/second. Set high if you have no idea.

### Attack pattern settings (all optional, but required if `AttackPatterns` is defined).
Attack patterns have missiles spread and then converge to the target.
+ `AttackPatterns`: An array of vector offsets to the target position. These will be rotated so that the z axis is in a line from the missile to the intercept point and the y axis is vertical; I suggest keeping z == 0 so the offsets are in the normal plane to the missile's path. Pattern size is multiplied by (time to target) - PatternConvergeTime; in general, slower missiles will want smaller patterns.
+ `PatternConvergeTime`: The time to target by which the missile will be pointing directly at the target. Low values (how low depending on missile agility) will lead to missing the target completely, high values to smaller separation in flight.
+ `PatternTimeCap`: A cap on the value of ttt used to calculate pattern size. Prevents slow, long-range missiles from flying too far off course.

# Implementation notes
Target prediction uses secant approximations to estimate future target velocity and then uses the law of cosines to calculate an intercept point (finding the time that solves for a triangle given distance to target, angle (from the target's perspective) between the missile or launch point and the target's velocity, and target and projectile speeds).

The `flag` global variable  and the `.Flag` fields in `Targets` and `Missiles` implement a rudimentary tracing garbage collection.
A GC cycle includes missile targeting in one tick (setting the flag for living missiles and active missile targets), calculation of target list priority targets in the next generation (flagging those targets), and finishes with deleting entries whose flag has not been set that cycle and flipping the flag.
If replacing the missile guidance code, be sure to set the flag for whatever entries in those tables you want to persist.
