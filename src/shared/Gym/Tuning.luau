--!strict
-- Tuning: every physics constant in one place.
--
-- Each entry has a default, a range, a unit and a description. The debug tools
-- (live attribute tuning in Studio, later the tuning panel) and the tests are
-- driven from this list, so adding a parameter here is all it takes to expose it.
--
-- Entries marked `reset = true` are read when the world is built and only take
-- effect on Reset (body sizes, masses, step rate).
--
-- Units: studs, seconds, degrees (converted to radians inside the core).
-- Torque unit for motors: "Mg·stud" = total body mass × gravity × 1 stud, so
-- motor strength scales automatically when gravity changes (e.g. moon gravity).

export type Param = {
	key: string,
	default: number,
	min: number,
	max: number,
	unit: string,
	category: string,
	desc: string,
	reset: boolean?,
}

export type Values = { [string]: number }

local Tuning = {}

local list: { Param } = {
	-- World and time -------------------------------------------------------
	{
		key = "gravity",
		default = 35,
		min = 5,
		max = 150,
		unit = "studs/s²",
		category = "World",
		desc = "Downward acceleration. 35 ≈ Earth gravity for this body size.",
	},
	{
		key = "moonGravityScale",
		default = 0.165,
		min = 0.05,
		max = 1,
		unit = "×",
		category = "World",
		desc = "Gravity multiplier while Moon gravity is on.",
	},
	{
		key = "moonGravity",
		default = 0,
		min = 0,
		max = 1,
		unit = "bool",
		category = "World",
		desc = "1 = Moon gravity on.",
	},
	{
		key = "timeScale",
		default = 1,
		min = 0,
		max = 2,
		unit = "×",
		category = "World",
		desc = "Simulation time per real second. 0.25 = slow motion. The physics code never sees it.",
	},
	{
		key = "simHz",
		default = 240,
		min = 60,
		max = 480,
		unit = "Hz",
		category = "Solver",
		reset = true,
		desc = "Fixed simulation step rate (collision, input and events run at this rate).",
	},
	{
		key = "substeps",
		default = 4,
		min = 1,
		max = 8,
		unit = "count",
		category = "Solver",
		desc = "Solver substeps per fixed step (each: integrate, solve, relax).",
	},
	{
		key = "relaxIterations",
		default = 1,
		min = 1,
		max = 4,
		unit = "count",
		category = "Solver",
		desc = "Relax passes per substep (removes position-correction velocity).",
	},
	{
		key = "maxStepsPerFrame",
		default = 16,
		min = 1,
		max = 64,
		unit = "steps",
		category = "Solver",
		desc = "Cap on fixed steps per rendered frame; excess time is dropped (slow-down instead of spiral).",
	},
	{
		key = "maxFrameDt",
		default = 0.1,
		min = 0.02,
		max = 0.5,
		unit = "s",
		category = "Solver",
		desc = "Longest real frame time accepted by the driver (hitches are clamped).",
	},
	{
		key = "linearDamping",
		default = 0,
		min = 0,
		max = 2,
		unit = "1/s",
		category = "World",
		desc = "Air-like linear velocity loss.",
	},
	{
		key = "angularDamping",
		default = 0.02,
		min = 0,
		max = 2,
		unit = "1/s",
		category = "World",
		desc = "Air-like angular velocity loss.",
	},
	{
		key = "maxLinearSpeed",
		default = 400,
		min = 50,
		max = 2000,
		unit = "studs/s",
		category = "Solver",
		desc = "Safety clamp on any body's speed.",
	},
	{
		key = "maxAngularSpeed",
		default = 120,
		min = 10,
		max = 500,
		unit = "rad/s",
		category = "Solver",
		desc = "Safety clamp on any body's spin rate.",
	},

	-- Contacts --------------------------------------------------------------
	{
		key = "contactHertz",
		default = 30,
		min = 5,
		max = 120,
		unit = "Hz",
		category = "Contacts",
		desc = "Stiffness of contact position correction.",
	},
	{
		key = "contactDampingRatio",
		default = 10,
		min = 0,
		max = 20,
		unit = "ζ",
		category = "Contacts",
		desc = "Damping of contact position correction (high = no bounce from overlap push-out).",
	},
	{
		key = "contactPushSpeed",
		default = 10,
		min = 0.5,
		max = 50,
		unit = "studs/s",
		category = "Contacts",
		desc = "Maximum speed used to push overlapping shapes apart.",
	},
	{
		key = "speculativeDistance",
		default = 0.12,
		min = 0,
		max = 1,
		unit = "studs",
		category = "Contacts",
		desc = "Contacts are created this far before touching (prevents tunneling).",
	},
	{
		key = "friction",
		default = 0.8,
		min = 0,
		max = 2,
		unit = "μ",
		category = "Contacts",
		desc = "Friction between the body and the world.",
	},
	{
		key = "handFriction",
		default = 1.0,
		min = 0,
		max = 2,
		unit = "μ",
		category = "Contacts",
		desc = "Friction for the forearm/hand shapes (hand plants).",
	},
	{
		key = "restitution",
		default = 0.05,
		min = 0,
		max = 0.9,
		unit = "e",
		category = "Contacts",
		desc = "Bounciness of body–world impacts.",
	},
	{
		key = "restitutionThreshold",
		default = 3,
		min = 0,
		max = 20,
		unit = "studs/s",
		category = "Contacts",
		desc = "Impacts slower than this never bounce.",
	},

	-- Joints ----------------------------------------------------------------
	{
		key = "jointHertz",
		default = 240,
		min = 5,
		max = 480,
		unit = "Hz",
		category = "Joints",
		desc = "Stiffness of joint position correction (keeps limbs attached).",
	},
	{
		key = "jointDampingRatio",
		default = 2,
		min = 0,
		max = 10,
		unit = "ζ",
		category = "Joints",
		desc = "Damping of joint position correction.",
	},
	{
		key = "motorHertz",
		default = 6,
		min = 0.5,
		max = 30,
		unit = "Hz",
		category = "Joints",
		desc = "Spring frequency of the joint motors (how fast a pose is reached).",
	},
	{
		key = "motorDampingRatio",
		default = 1.25,
		min = 0,
		max = 3,
		unit = "ζ",
		category = "Joints",
		desc = "Motor damping. P1.1 used 0.8 (lively overshoot, lingering wobble); 1.25 is smoother (tools/smooth_bench.luau).",
	},
	{
		key = "shoulderMaxTorque",
		default = 3.0,
		min = 0,
		max = 20,
		unit = "Mg·stud",
		category = "Joints",
		desc = "Strength of the shoulder motor. Lower = arms give more under load.",
	},
	{
		key = "elbowMaxTorque",
		default = 2.0,
		min = 0,
		max = 20,
		unit = "Mg·stud",
		category = "Joints",
		desc = "Strength of the elbow motor (keeps arms nearly straight).",
	},
	{
		key = "hipMaxTorque",
		default = 2.0,
		min = 0,
		max = 20,
		unit = "Mg·stud",
		category = "Joints",
		desc = "Strength of the hip motor.",
	},
	{
		key = "kneeMaxTorque",
		default = 1.0,
		min = 0,
		max = 20,
		unit = "Mg·stud",
		category = "Joints",
		desc = "Strength of the knee motor.",
	},
	{
		key = "ankleMaxTorque",
		default = 0.3,
		min = 0,
		max = 20,
		unit = "Mg·stud",
		category = "Joints",
		desc = "Strength of the ankle motor.",
	},
	{
		key = "strengthGravityScaling",
		default = 1,
		min = 0,
		max = 1,
		unit = "×",
		category = "Joints",
		desc = "How much muscle strength follows gravity. 1 = strength scales with gravity (moon: same jump height, slower). 0 = fixed strength (moon: real-world physics, ~6× higher jumps).",
	},

	-- Shape control (P1.2) -----------------------------------------------------
	{
		key = "shapeFreqClose",
		default = 8,
		min = 1,
		max = 30,
		unit = "Hz",
		category = "Shape",
		desc = "How fast the body's target shape moves when closing (tucking, piking, crouching). Smooths input changes before the motors see them; 30 = nearly instant.",
	},
	{
		key = "shapeFreqOpen",
		default = 6,
		min = 1,
		max = 30,
		unit = "Hz",
		category = "Shape",
		desc = "How fast the target shape moves when opening (kick-out, arch, standing up).",
	},

	{
		key = "tuckHertz",
		default = 10,
		min = 1,
		max = 30,
		unit = "Hz",
		category = "Shape",
		desc = "Motor frequency of shoulders, elbows, hips and knees while tucking or piking off the bar (an active squeeze: the tuck closes fast and holds against the spin). At or below motorHertz = no squeeze (6 = P1.2 as first tested).",
	},

	-- Ground: standing, balance, jumping, landing (P1.2) ---------------------------
	{
		key = "groundShapeHertz",
		default = 2,
		min = 0.5,
		max = 30,
		unit = "Hz",
		category = "Ground",
		desc = "How fast the target shape moves while standing (crouching, rising, reaching). Lower = more controlled.",
	},
	{
		key = "groundLegHertz",
		default = 8,
		min = 2,
		max = 60,
		unit = "Hz",
		category = "Ground",
		desc = "Motor frequency of hips and knees while standing (posture; the weight is carried by gravity compensation).",
	},
	{
		key = "groundLegDampingRatio",
		default = 1,
		min = 0,
		max = 3,
		unit = "ζ",
		category = "Ground",
		desc = "Damping of the standing leg motors (1 = no bounce).",
	},
	{
		key = "groundLegStrength",
		default = 1.5,
		min = 0.5,
		max = 5,
		unit = "×",
		category = "Ground",
		desc = "Leg motor strength multiplier while standing.",
	},
	{
		key = "jumpStrength",
		default = 1.5,
		min = 0,
		max = 6,
		unit = "body weights",
		category = "Ground",
		desc = "Upward push of the legs during a jump, on top of carrying the body. Rise ≈ this × the crouch depth (in studs).",
	},
	{
		key = "jumpLegStrength",
		default = 3,
		min = 0.5,
		max = 8,
		unit = "×",
		category = "Ground",
		desc = "Leg torque limit multiplier during the jump push.",
	},
	{
		key = "jumpTorsoHertz",
		default = 3,
		min = 0,
		max = 12,
		unit = "Hz",
		category = "Ground",
		desc = "How firmly the hips bring the trunk from the crouch's lean to upright during the push.",
	},
	{
		key = "jumpLockKnee",
		default = 10,
		min = 0,
		max = 60,
		unit = "°",
		category = "Ground",
		desc = "The push stops once the knees straighten past this angle (no toe-off kick).",
	},
	{
		key = "jumpSpinHertz",
		default = 4,
		min = 0,
		max = 20,
		unit = "Hz",
		category = "Ground",
		desc = "How firmly the feet steer the body's spin during the push (through where the ground pushes under the foot).",
	},
	{
		key = "jumpArchSpin",
		default = 0.8,
		min = 0,
		max = 3,
		unit = "rev/s",
		category = "Ground",
		desc = "Backward spin the push aims for while Arch is held (a back-flip takeoff; tuck in the air to spin faster). 0 = Arch has no effect on the push.",
	},
	{
		key = "jumpSpinAssist",
		default = 0,
		min = 0,
		max = 1,
		unit = "×",
		category = "Ground",
		desc = "Optional assist (not muscle): after an Arch push, the share of the back-flip spin the feet couldn't produce that is added over the first 0.1 s of flight. The feet alone reach about 0.4 rev/s (a standing back flip needs about 0.8); 1 = reach jumpArchSpin. 0 = pure physics.",
	},
	{
		key = "jumpHertz",
		default = 12,
		min = 2,
		max = 60,
		unit = "Hz",
		category = "Ground",
		desc = "Motor frequency of the arm swing during the jump push.",
	},
	{
		key = "jumpMinCrouch",
		default = 0.25,
		min = 0,
		max = 1,
		unit = "0..1",
		category = "Ground",
		desc = "Crouch depth needed for releasing Tuck to push off (shallower releases just stand up).",
	},
	{
		key = "jumpPushTime",
		default = 0.3,
		min = 0.05,
		max = 1,
		unit = "s",
		category = "Ground",
		desc = "Longest jump push before the legs return to standing (ends early at takeoff).",
	},
	{
		key = "footFlatHertz",
		default = 4,
		min = 0.5,
		max = 30,
		unit = "Hz",
		category = "Ground",
		desc = "Ankle spring that keeps the standing foot flat on the ground.",
	},
	{
		key = "gravityCompensation",
		default = 1,
		min = 0,
		max = 1.5,
		unit = "×",
		category = "Ground",
		desc = "Standing leg muscles carry this share of the body weight above each joint (1 = all of it; the pose springs only correct posture).",
	},
	{
		key = "balanceHertz",
		default = 1.5,
		min = 0,
		max = 6,
		unit = "Hz",
		category = "Ground",
		desc = "How fast the ankles steer the centre of mass back over the feet. 0 = no balance.",
	},
	{
		key = "balanceDampingRatio",
		default = 1,
		min = 0,
		max = 3,
		unit = "ζ",
		category = "Ground",
		desc = "Damping of the balance response (1 = no sway overshoot).",
	},
	{
		key = "balanceAssist",
		default = 1,
		min = 0,
		max = 5,
		unit = "Mg·stud (weight)",
		category = "Ground",
		desc = "Optional, capped correction that turns the body about its feet back over them while standing or landing (stands in for small foot adjustments; never in flight). 0 = pure muscle balance.",
	},
	{
		key = "landingReflex",
		default = 1,
		min = 0,
		max = 1,
		unit = "0..1",
		category = "Ground",
		desc = "Falling roughly upright with no shape input, the hips bring the legs under the body to land on the feet (internal motion). 0 = off.",
	},
	{
		key = "landingReflexTilt",
		default = 45,
		min = 5,
		max = 90,
		unit = "°",
		category = "Ground",
		desc = "The landing reflex works fully up to this trunk lean from upright and fades out by 1.5× it (no reflex mid-flip).",
	},
	{
		key = "landingHertz",
		default = 3,
		min = 0.5,
		max = 30,
		unit = "Hz",
		category = "Ground",
		desc = "Leg motor rate while absorbing a landing: with the targets following the body the motors act as dampers.",
	},
	{
		key = "landingDampingRatio",
		default = 2.5,
		min = 0,
		max = 6,
		unit = "ζ",
		category = "Ground",
		desc = "Leg motor damping while absorbing a landing (high = the legs soak up the impact).",
	},
	{
		key = "landingAbsorbTime",
		default = 0.5,
		min = 0,
		max = 1.5,
		unit = "s",
		category = "Ground",
		desc = "Longest time the legs yield after a landing before standing back up (they stand up as soon as the fall is stopped).",
	},
	{
		key = "groundGrace",
		default = 0.06,
		min = 0,
		max = 0.3,
		unit = "s",
		category = "Ground",
		desc = "Feet must be off the ground this long before the body counts as airborne (no flicker on bumps).",
	},
	{
		key = "fallTiltAngle",
		default = 75,
		min = 20,
		max = 90,
		unit = "°",
		category = "Ground",
		desc = "Torso lean from vertical beyond which a body on the ground counts as fallen (no standing control).",
	},

	-- Swing (P1.2) -------------------------------------------------------------
	{
		key = "gripFriction",
		default = 0.02,
		min = 0,
		max = 1,
		unit = "Mg·stud",
		category = "Swing",
		desc = "Friction torque at the grip (energy lost per swing).",
	},
	{
		key = "hangStartAngle",
		default = 60,
		min = 0,
		max = 170,
		unit = "deg",
		category = "Swing",
		desc = "Where the Hang scene starts, released from rest at this angle from vertical. 60 = a ready-made swing (the physics test setup); 0 = a still hang, to practise building a swing from nothing.",
		reset = true,
	},
	{
		key = "gripShoulderHertz",
		default = 18,
		min = 1,
		max = 60,
		unit = "Hz",
		category = "Swing",
		desc = "Shoulder and elbow motor frequency while gripping. The arms carry and turn the whole hanging body, so they need a stiffer spring than in the air (6 = P1.1: the shoulders barely follow Arch/Tuck on the bar, and soft elbows flex under the swing and drain it).",
	},
	{
		key = "gripHipHertz",
		default = 10,
		min = 1,
		max = 60,
		unit = "Hz",
		category = "Swing",
		desc = "Hip motor frequency while gripping (at least motorHertz). The hips hold the legs against the swing's pull: softer, a held Tuck or Pike sags at the bottom of each swing and springs back at the top, the reverse of pumping, so holding a shape drains the swing.",
	},
	{
		key = "swingAssist",
		default = 0,
		min = 0,
		max = 2,
		unit = "×",
		category = "Swing",
		desc = "Extra swing torque, only when the shape change is in phase (closing while swinging up). 0 = pure physics.",
	},
	{
		key = "maxSwingSpeed",
		default = 12,
		min = 4,
		max = 30,
		unit = "rad/s",
		category = "Swing",
		desc = "Energy cap on the swing: it can carry at most the energy of passing the bottom at this rotation speed about the grip.",
	},

	-- Release (P1.2) -----------------------------------------------------------
	{
		key = "releaseVelocityScale",
		default = 1,
		min = 0.5,
		max = 1.5,
		unit = "×",
		category = "Release",
		desc = "Centre-of-mass velocity multiplier at Let Go. 1 = pure physics.",
	},
	{
		key = "releaseSpinScale",
		default = 1,
		min = 0.5,
		max = 1.5,
		unit = "×",
		category = "Release",
		desc = "Rotation (about the centre of mass) multiplier at Let Go. 1 = pure physics.",
	},
	{
		key = "releasePop",
		default = 0,
		min = 0,
		max = 20,
		unit = "studs/s",
		category = "Release",
		desc = "Extra upward speed added at Let Go. 0 = pure physics.",
	},

	-- Twist (P1.2) -------------------------------------------------------------
	{
		key = "twistMode",
		default = 0,
		min = 0,
		max = 1,
		unit = "0/1",
		category = "Twist",
		desc = "0 = hold (spins while held, stops when released), 1 = momentum (a tap starts the spin, the opposite tap reverses, both stop).",
	},
	{
		key = "twistRate",
		default = 1.5,
		min = 0.5,
		max = 5,
		unit = "rev/s",
		category = "Twist",
		desc = "Top twist speed.",
	},
	{
		key = "twistAccel",
		default = 20,
		min = 2,
		max = 100,
		unit = "rev/s²",
		category = "Twist",
		desc = "How fast a twist spins up.",
	},
	{
		key = "twistStopAccel",
		default = 30,
		min = 2,
		max = 100,
		unit = "rev/s²",
		category = "Twist",
		desc = "How fast a twist stops (and holds its angle).",
	},
	{
		key = "twistSettleTime",
		default = 0.12,
		min = 0,
		max = 1,
		unit = "s",
		category = "Twist",
		desc = "Time for an unfinished twist to settle square to the camera after landing or gripping (visual).",
	},

	-- Body (reset) -----------------------------------------------------------
	{
		key = "bodyMass",
		default = 10,
		min = 1,
		max = 100,
		unit = "mass",
		category = "Body",
		reset = true,
		desc = "Total body mass. Only ratios matter for motion; kept at 10 for readable numbers.",
	},
	{
		key = "upperArmLength",
		default = 1.0,
		min = 0.5,
		max = 1.5,
		unit = "studs",
		category = "Body",
		reset = true,
		desc = "Shoulder to elbow.",
	},
	{
		key = "forearmLength",
		default = 1.0,
		min = 0.5,
		max = 1.5,
		unit = "studs",
		category = "Body",
		reset = true,
		desc = "Elbow to grip point (hand).",
	},
	{
		key = "trunkLength",
		default = 2.0,
		min = 1.5,
		max = 2.5,
		unit = "studs",
		category = "Body",
		reset = true,
		desc = "Shoulder line to hip joint.",
	},
	{
		key = "thighLength",
		default = 1.1,
		min = 0.7,
		max = 1.6,
		unit = "studs",
		category = "Body",
		reset = true,
		desc = "Hip to knee.",
	},
	{
		key = "shankLength",
		default = 1.1,
		min = 0.7,
		max = 1.6,
		unit = "studs",
		category = "Body",
		reset = true,
		desc = "Knee to ankle.",
	},
	{
		key = "footLength",
		default = 0.7,
		min = 0.4,
		max = 1.0,
		unit = "studs",
		category = "Body",
		reset = true,
		desc = "Ankle to toe.",
	},
	{
		key = "limbInertiaBoost",
		default = 1,
		min = 0,
		max = 1,
		unit = "×",
		category = "Body",
		reset = true,
		desc = "Extra rotational inertia for hands, feet and lower limbs (solver conditioning; see Rig.INERTIA_SCALE). 0 = uniform capsules.",
	},
}

local byKey: { [string]: Param } = {}
for _, p in list do
	byKey[p.key] = p
end

Tuning.list = list
Tuning.byKey = byKey

-- Returns a fresh table of default values.
function Tuning.defaults(): Values
	local v: Values = {}
	for _, p in list do
		v[p.key] = p.default
	end
	return v
end

-- Returns defaults with `overrides` applied (each clamped to its range).
-- Unknown keys raise an error so typos in tests or presets are caught.
function Tuning.new(overrides: Values?): Values
	local v = Tuning.defaults()
	if overrides then
		for key, value in overrides do
			Tuning.set(v, key, value)
		end
	end
	return v
end

-- Sets one value, clamped to its declared range. Non-finite values are rejected.
function Tuning.set(values: Values, key: string, value: number): number
	local p = byKey[key]
	if p == nil then
		error(`Tuning: unknown parameter '{key}'`, 2)
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return values[key]
	end
	local clamped = math.clamp(value, p.min, p.max)
	values[key] = clamped
	return clamped
end

-- Effective gravity (moon toggle applied).
function Tuning.effectiveGravity(values: Values): number
	local g = values.gravity
	if values.moonGravity >= 0.5 then
		g *= values.moonGravityScale
	end
	return g
end

return Tuning
