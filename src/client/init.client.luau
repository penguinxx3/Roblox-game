--!strict
-- GymClient: P1.2 movement prototype.
--
-- The client owns and steps its own simulation (the planar core in ReplicatedStorage.Gym)
-- and draws it. Order inside one render step keeps input-to-screen latency at one frame:
--   sample input -> advance the fixed-step simulation -> draw the body and world -> camera.
-- There is no Roblox character in this prototype.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- No Roblox character exists here; make sure default movement controls stay off.
-- (Off the startup path so a missing PlayerModule can never stall the viewer.)
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts", 10)
	local module = scripts and scripts:WaitForChild("PlayerModule", 10)
	if module then
		pcall(function()
			(require :: any)(module):GetControls():Disable()
		end)
	end
end)

local Gym = ReplicatedStorage:WaitForChild("Gym")
local Sim = require(Gym:WaitForChild("Sim"))

local RigRenderer = require(script:WaitForChild("RigRenderer"))
local WorldRenderer = require(script:WaitForChild("WorldRenderer"))
local CameraController = require(script:WaitForChild("CameraController"))
local DebugOverlay = require(script:WaitForChild("DebugOverlay"))
local DebugControls = require(script:WaitForChild("DebugControls"))
local InputRouter = require(script:WaitForChild("InputRouter"))

-- "player" control: Arch/Tuck/Let Go/Twist drive the body through the movement controller
local sim = Sim.new(nil, "Hang", { control = "player" })

local view = workspace:FindFirstChild("GymView") or Instance.new("Folder")
view.Name = "GymView"
view.Parent = workspace

local worldView = WorldRenderer.new(sim, view)
local rigView = RigRenderer.new(sim, view)
local camera = CameraController.new()
local overlay = DebugOverlay.new(playerGui)
local showContacts = false
local counters = { invalid = 0, outOfBounds = 0 }

-- Renderers hold references to bodies; rebuild them whenever the world is rebuilt.
local function rebuildViews()
	worldView:destroy()
	rigView:destroy()
	worldView = WorldRenderer.new(sim, view)
	rigView = RigRenderer.new(sim, view)
	local x, y = Sim.bodyPose(sim.rig.torso, 1)
	camera:snap(Vector3.new(x, y, 0))
end

local function resetScene()
	Sim.reset(sim)
	rebuildViews()
end

local input = InputRouter.new(playerGui, { onReset = resetScene })

local controls = DebugControls.bind(sim, {
	reset = resetScene,
	scenario = function(name: string)
		Sim.reset(sim, name)
		rebuildViews()
	end,
	toggleOverlay = function()
		overlay:setVisible(not overlay.visible)
	end,
	toggleContacts = function()
		showContacts = not showContacts
	end,
	stepOnce = function()
		if sim.paused then
			Sim.stepOnce(sim)
		end
	end,
}, playerGui)

-- Timing statistics (exponential moving averages).
local fps, simMs, renderMs, frameMs = 60, 0, 0, 16
local startClock = os.clock()
local smokeChecked = false

RunService:BindToRenderStep("GymSim", Enum.RenderPriority.Input.Value + 1, function(dt: number)
	local t0 = os.clock()
	debug.profilebegin("GymSim")
	Sim.setInput(sim, input:sample())
	local steps = Sim.advance(sim, dt)
	debug.profileend()
	local t1 = os.clock()

	for _, e in Sim.drainEvents(sim) do
		if e.kind == "invalid" then
			counters.invalid += 1
			warn(`[GymClient] simulation recovered from an invalid state at step {e.step}: {e.detail}`)
			rebuildViews()
		elseif e.kind == "outOfBounds" then
			counters.outOfBounds += 1
			rebuildViews()
		end
	end

	debug.profilebegin("GymRender")
	local alpha = Sim.alpha(sim)
	worldView:draw(alpha, sim, showContacts)
	rigView:draw(alpha)
	local x, y = Sim.bodyPose(sim.rig.torso, alpha)
	camera:update(Vector3.new(x, y, 0), dt)
	debug.profileend()
	local t2 = os.clock()

	local k = 0.05
	fps += (1 / math.max(dt, 1e-4) - fps) * k
	frameMs += (dt * 1000 - frameMs) * k
	simMs += ((t1 - t0) * 1000 - simMs) * k
	renderMs += ((t2 - t1) * 1000 - renderMs) * k
	overlay:update(sim, {
		frameMs = frameMs,
		simMs = simMs,
		renderMs = renderMs,
		steps = steps,
		fps = fps,
		invalidEvents = counters.invalid,
		outOfBoundsEvents = counters.outOfBounds,
		note = controls.note,
	})

	-- One-time runtime smoke check, visible in Studio's Output.
	if not smokeChecked and os.clock() - startClock > 3 then
		smokeChecked = true
		local ok = sim.stepCount > 0 and counters.invalid == 0 and x == x and y == y
		local msg = string.format(
			"[GymClient] runtime check %s: scene=%s steps=%d simTime=%.2fs avgSim=%.3fms avgRender=%.3fms fps=%.1f parts=%d",
			if ok then "OK" else "FAILED",
			sim.scenario,
			sim.stepCount,
			sim.time,
			simMs,
			renderMs,
			fps,
			#view:GetDescendants()
		)
		if ok then
			print(msg)
		else
			warn(msg)
		end
	end
end)

print(
	"[GymClient] P1.2 movement running. Play: A/← Arch, S/↓ Tuck (on the ground: crouch, release to jump), W/↑ Let Go, Q/E Twist. Debug: R reset, 1-5 scene, V pose override, T slow-mo, G moon, P pause, N step, C contacts, F2 overlay."
)
