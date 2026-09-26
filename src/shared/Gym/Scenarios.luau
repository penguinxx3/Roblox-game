--!strict
-- Scenarios: small, deterministic test setups for the physics foundation (P1.1).
--
-- Each scenario builds the same static test course (floor, two blocks, a ramp) and
-- places the rig in a different starting situation. They exist to exercise and
-- inspect the solver (hanging, landing, tumbling, moving anchors); they are not
-- gameplay and contain no automatic tricks.

-- (Headless tests load a mirrored copy with these requires rewritten to file paths; see tools/lune_mirror.luau.)
local Solver2D = require(script.Parent.Solver2D)
local Collide2D = require(script.Parent.Collide2D)
local Rig = require(script.Parent.Rig)
local Tuning = require(script.Parent.Tuning)

export type Visual = {
	kind: string, -- "floor" | "block" | "ramp" | "anchor" | "wheel"
	shape: Solver2D.Shape?,
	body: Solver2D.Body?,
	x: number?,
	y: number?,
	radius: number?,
	spokes: number?,
}

export type Built = {
	rig: Rig.Rig,
	grip: Solver2D.Joint?,
	visuals: { Visual },
}

export type Scenario = {
	name: string,
	description: string,
	pose: string,
	build: (world: Solver2D.World, t: Tuning.Values) -> Built,
}

local Scenarios = {}

Scenarios.BAR_HEIGHT = 10

-- Static test course shared by every scenario. Coordinates: u (right), v (up); floor top at v = 0.
local function buildCourse(world: Solver2D.World, t: Tuning.Values): { Visual }
	local visuals: { Visual } = {}
	local function add(kind: string, poly: Collide2D.Polygon)
		local shape =
			Solver2D.addPolygon(world, world.ground, poly, { friction = 1, restitution = 0, tag = kind })
		table.insert(visuals, { kind = kind, shape = shape })
	end
	add("floor", Collide2D.newBox(80, 2, 0, -2))
	add("block", Collide2D.newBox(1.5, 0.75, 7, 0.75))
	add("block", Collide2D.newBox(1.2, 1.5, -8, 1.5))
	add("ramp", Collide2D.newPolygon({ 11, 0, 17, 0, 17, 2.5 }))
	return visuals
end

local function gripJoint(world: Solver2D.World, anchor: Solver2D.Body, rig: Rig.Rig): Solver2D.Joint
	local gx, gy = Rig.gripPoint(rig)
	return Solver2D.addRevolute(world, anchor, rig.forearm, gx, gy, { name = "grip" })
end

local list: { Scenario } = {
	{
		name = "Hang",
		description = "Hanging from a fixed grip, released 60° from vertical. Tests swinging, joints and energy.",
		pose = "Neutral",
		build = function(world, t)
			local visuals = buildCourse(world, t)
			local bar = Scenarios.BAR_HEIGHT
			local rig =
				Rig.build(world, t, { pivot = "grip", x = 0, y = bar, rot = math.rad(60), pose = "Neutral" })
			local grip = gripJoint(world, world.ground, rig)
			table.insert(visuals, { kind = "anchor", x = 0, y = bar, radius = 0.12 })
			return { rig = rig, grip = grip, visuals = visuals }
		end,
	},
	{
		name = "Drop",
		description = "Falls from 4 studs, tilted, onto the floor next to a block. Tests landing contacts and springy joints.",
		pose = "Crouch",
		build = function(world, t)
			local visuals = buildCourse(world, t)
			local rig = Rig.build(
				world,
				t,
				{ pivot = "hip", x = 4.2, y = 6.5, rot = math.rad(-12), w = 0.6, pose = "Crouch" }
			)
			return { rig = rig, visuals = visuals }
		end,
	},
	{
		name = "Tumble",
		description = "Thrown up and forward with backward spin in a tuck. Tests flight, rotation and messy landings.",
		pose = "Tuck",
		build = function(world, t)
			local visuals = buildCourse(world, t)
			local rig = Rig.build(world, t, {
				pivot = "com",
				x = -4,
				y = 4,
				rot = 0,
				vx = 5,
				vy = 16,
				w = 7,
				pose = "Tuck",
			})
			return { rig = rig, visuals = visuals }
		end,
	},
	{
		name = "Wheel",
		description = "Hanging from a spoke of a rotating wheel (kinematic, moving anchor).",
		pose = "Neutral",
		build = function(world, t)
			local visuals = buildCourse(world, t)
			local cx, cy, radius = 0, 13, 3
			local wheel = Solver2D.addBody(
				world,
				{ name = "wheel", kind = Solver2D.KINEMATIC, x = cx, y = cy, w = 1.2 }
			)
			local rig =
				Rig.build(world, t, { pivot = "grip", x = cx + radius, y = cy, rot = 0, pose = "Neutral" })
			local grip = gripJoint(world, wheel, rig)
			table.insert(visuals, { kind = "wheel", body = wheel, radius = radius, spokes = 4 })
			return { rig = rig, grip = grip, visuals = visuals }
		end,
	},
}

local byName: { [string]: Scenario } = {}
for _, s in list do
	byName[s.name] = s
end

Scenarios.list = list
Scenarios.byName = byName

function Scenarios.get(name: string): Scenario
	local s = byName[name]
	assert(s, `unknown scenario '{name}'`)
	return s
end

return Scenarios
