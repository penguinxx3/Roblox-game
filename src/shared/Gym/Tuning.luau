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
		default = 0.8,
		min = 0,
		max = 3,
		unit = "ζ",
		category = "Joints",
		desc = "Motor damping. Below 1 gives a lively overshoot.",
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
