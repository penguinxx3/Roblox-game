--!strict
-- Sim: the fixed-step driver around the solver.
--
-- Owns the simulation state (world, rig, time) and turns variable real frame times
-- into fixed simulation steps:
--
--   acc += clamp(realDt, 0, maxFrameDt) * timeScale
--   run floor(acc / h) steps (capped at maxStepsPerFrame; excess time is dropped)
--   alpha = acc / h   (render interpolation between the previous and current step)
--
-- Nothing in here touches Roblox. Presentation reads body poses and `alpha`; player
-- input arrives as data (Input.Frame via Sim.setInput); networking (later) can send the
-- same input frames to a server running the same simulation.
--
-- Control modes:
--   "pose"   (default) the motors hold the named pose `rig.pose` (P1.1 scenes, tests)
--   "player" the movement Controller turns input frames into muscle commands (P1.2)

-- (Headless tests load a mirrored copy with these requires rewritten to file paths; see tools/lune_mirror.luau.)
local Solver2D = require(script.Parent.Solver2D)
local Tuning = require(script.Parent.Tuning)
local Rig = require(script.Parent.Rig)
local Scenarios = require(script.Parent.Scenarios)
local Input = require(script.Parent.Input)
local Controller = require(script.Parent.Controller)

local Sim = {}

Sim.OUT_OF_BOUNDS_Y = -50
Sim.OUT_OF_BOUNDS_X = 5000

export type Event = { kind: string, step: number, detail: string? }

export type Sim = {
	tuning: Tuning.Values,
	scenario: string,
	world: Solver2D.World,
	rig: Rig.Rig,
	grip: Solver2D.Joint?,
	visuals: { Scenarios.Visual },
	h: number, -- fixed step length (s)
	stepCount: number,
	time: number,
	acc: number,
	paused: boolean,
	lastFrameSteps: number,
	droppedTime: number,
	events: { Event },
	onStep: ((sim: Sim) -> ())?,
	control: string, -- "pose" or "player"
	input: Input.Frame, -- latest player input (read every fixed step)
	controller: Controller.State?, -- present in "player" control
	poseOverride: string?, -- debug: hold this pose instead of the controller's targets
}

export type Options = {
	control: string?, -- "pose" (default) or "player"
}

local function syncParams(sim: Sim)
	local t, p = sim.tuning, sim.world.params
	p.gravityX = 0
	p.gravityY = -Tuning.effectiveGravity(t)
	p.substeps = t.substeps // 1
	p.relaxIterations = t.relaxIterations // 1
	p.linearDamping = t.linearDamping
	p.angularDamping = t.angularDamping
	p.maxLinearSpeed = t.maxLinearSpeed
	p.maxAngularSpeed = t.maxAngularSpeed
	p.contactHertz = t.contactHertz
	p.contactDampingRatio = t.contactDampingRatio
	p.contactPushSpeed = t.contactPushSpeed
	p.speculativeDistance = t.speculativeDistance
	p.restitutionThreshold = t.restitutionThreshold
	p.jointHertz = t.jointHertz
	p.jointDampingRatio = t.jointDampingRatio
	-- per-shape material values that are live-tunable
	for _, shape in sim.world.bodyShapes do
		shape.friction = if shape.tag == "forearm" then t.handFriction else t.friction
		shape.restitution = t.restitution
	end
end

local function build(sim: Sim)
	local t = sim.tuning
	sim.world = Solver2D.newWorld()
	local scenario = Scenarios.get(sim.scenario)
	local built = scenario.build(sim.world, t)
	sim.rig = built.rig
	sim.grip = built.grip
	sim.visuals = built.visuals
	sim.h = 1 / (t.simHz // 1)
	sim.stepCount = 0
	sim.time = 0
	sim.acc = 0
	sim.lastFrameSteps = 0
	sim.droppedTime = 0
	syncParams(sim)
	sim.controller = if sim.control == "player" then Controller.new(sim) else nil
end

function Sim.new(overrides: Tuning.Values?, scenario: string?, options: Options?): Sim
	local control = (options and options.control) or "pose"
	assert(control == "pose" or control == "player", `unknown control mode '{control}'`)
	local sim: Sim = {
		tuning = Tuning.new(overrides),
		scenario = scenario or "Hang",
		world = nil :: any,
		rig = nil :: any,
		grip = nil,
		visuals = {},
		h = 1 / 240,
		stepCount = 0,
		time = 0,
		acc = 0,
		paused = false,
		lastFrameSteps = 0,
		droppedTime = 0,
		events = {},
		onStep = nil,
		control = control,
		input = Input.new(),
		controller = nil,
		poseOverride = nil,
	}
	build(sim)
	return sim
end

-- Rebuilds the world from scratch (deterministic). Optionally switches scenario.
function Sim.reset(sim: Sim, scenario: string?)
	if scenario then
		Scenarios.get(scenario) -- validates the name
		sim.scenario = scenario
	end
	build(sim)
	table.insert(sim.events, { kind = "reset", step = 0, detail = sim.scenario })
end

-- One fixed simulation step.
function Sim.stepOnce(sim: Sim)
	if Solver2D.hasInvalidState(sim.world) then
		-- state was corrupted from outside the solver (e.g. a bad external write)
		local at = sim.stepCount
		build(sim)
		table.insert(
			sim.events,
			{ kind = "invalid", step = at, detail = "non-finite state before step; world rebuilt" }
		)
		return
	end
	syncParams(sim)
	local controller = sim.controller
	if controller then
		Controller.step(sim, controller, sim.input, sim.h)
	else
		Rig.applyMotors(sim.rig, sim.tuning)
	end
	Solver2D.step(sim.world, sim.h)
	sim.stepCount += 1
	sim.time += sim.h
	if Solver2D.hasInvalidState(sim.world) then
		-- Never let a numerical failure propagate: record it and rebuild.
		local at = sim.stepCount
		build(sim)
		table.insert(sim.events, { kind = "invalid", step = at, detail = "non-finite state; world rebuilt" })
		return
	end
	local torso = sim.rig.torso
	if torso.y < Sim.OUT_OF_BOUNDS_Y or math.abs(torso.x) > Sim.OUT_OF_BOUNDS_X then
		local at = sim.stepCount
		build(sim)
		table.insert(sim.events, { kind = "outOfBounds", step = at, detail = "left the world; rebuilt" })
		return
	end
	if sim.onStep then
		sim.onStep(sim)
	end
end

-- Advances by a real frame time. Returns the number of fixed steps run.
function Sim.advance(sim: Sim, realDt: number): number
	sim.lastFrameSteps = 0
	if sim.paused or realDt ~= realDt or realDt <= 0 then
		return 0
	end
	local t = sim.tuning
	local dt = math.min(realDt, t.maxFrameDt) * t.timeScale
	sim.acc += dt
	local h = sim.h
	local steps = sim.acc // h
	local cap = t.maxStepsPerFrame // 1
	if steps > cap then
		sim.droppedTime += (steps - cap) * h
		sim.acc -= (steps - cap) * h
		steps = cap
	end
	for _ = 1, steps do
		sim.acc -= h
		Sim.stepOnce(sim)
	end
	if sim.acc < 0 then
		sim.acc = 0
	end
	sim.lastFrameSteps = steps
	return steps
end

-- Interpolation factor between the previous and the current step.
function Sim.alpha(sim: Sim): number
	return math.clamp(sim.acc / sim.h, 0, 1)
end

-- Interpolated pose of a body for rendering.
function Sim.bodyPose(body: Solver2D.Body, alpha: number): (number, number, number)
	local x = body.prevX + (body.x - body.prevX) * alpha
	local y = body.prevY + (body.y - body.prevY) * alpha
	local a = body.prevA + (body.a - body.prevA) * alpha
	return x, y, a
end

function Sim.setPose(sim: Sim, pose: string)
	Rig.setPose(sim.rig, pose)
end

-- Latest player input (copied; read at every following fixed step). Presses are counters,
-- so a press is acted on at the next step even if this frame runs no steps.
function Sim.setInput(sim: Sim, frame: Input.Frame)
	Input.sanitize(Input.copy(frame, sim.input))
end

-- Interpolated twist angle about the long axis (radians) for rendering; 0 in "pose" control.
function Sim.renderTwist(sim: Sim, alpha: number): number
	local c = sim.controller
	return if c then Controller.renderPsi(c, alpha) else 0
end

-- Sets a tuning value. Values marked `reset` take effect on the next reset.
function Sim.setParam(sim: Sim, key: string, value: number): number
	return Tuning.set(sim.tuning, key, value)
end

function Sim.metrics(sim: Sim): Solver2D.Metrics
	return Solver2D.metrics(sim.world, Tuning.effectiveGravity(sim.tuning))
end

function Sim.checksum(sim: Sim): string
	return Solver2D.checksum(sim.world)
end

function Sim.drainEvents(sim: Sim): { Event }
	local e = sim.events
	sim.events = {}
	return e
end

return Sim
