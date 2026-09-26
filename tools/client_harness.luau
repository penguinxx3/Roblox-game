-- Headless client harness (no Studio): runs the BUILT place's GymClient LocalScript in
-- Lune with a thin engine shim, then drives it frame by frame and through every debug
-- control. Instances, properties and enums are Lune's Roblox implementations (checked
-- against Roblox's API reflection data), so invalid property names or types fail here.
--
-- Shimmed (not real engine behaviour): RunService.BindToRenderStep (we call the callback),
-- Workspace:BulkMoveTo (sets CFrames), CurrentCamera, LocalPlayer, input/button/attribute
-- signals (we fire them). Rendering, real input and on-device performance are NOT tested.
--
-- Usage: lune run tools/client_harness.luau [build/BarGym.rbxl]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance
local path = process.args[1] or "build/BarGym.rbxl"

-- Signals -------------------------------------------------------------------------------
local signalStore = {}
local function signalFor(inst, name)
	local key = tostring(inst) .. ":" .. name .. ":" .. tostring(inst:GetFullName())
	local s = signalStore[key]
	if not s then
		s = { handlers = {} }
		function s:Connect(fn)
			table.insert(self.handlers, fn)
			return { Disconnect = function() end }
		end
		function s:Fire(...)
			for _, h in self.handlers do
				h(...)
			end
		end
		signalStore[key] = s
	end
	return s
end
roblox.implementProperty("GuiButton", "Activated", function(inst)
	return signalFor(inst, "Activated")
end)
roblox.implementProperty("Instance", "AttributeChanged", function(inst)
	return signalFor(inst, "AttributeChanged")
end)
roblox.implementProperty("UserInputService", "InputBegan", function(inst)
	return signalFor(inst, "InputBegan")
end)

-- Engine shims ---------------------------------------------------------------------------
roblox.implementMethod("Instance", "WaitForChild", function(inst, name, timeout)
	local child = inst:FindFirstChild(name)
	if child == nil and timeout == nil then
		error(`WaitForChild would yield forever: {inst:GetFullName()}.{name}`)
	end
	return child
end)
local game = roblox.deserializePlace(fs.readFile(path))
local workspace = game:GetService("Workspace")
local camera = Instance.new("Camera")
camera.Parent = workspace
local okCam = pcall(function()
	workspace.CurrentCamera = camera
end)
if not okCam or workspace.CurrentCamera ~= camera then
	roblox.implementProperty("Workspace", "CurrentCamera", function()
		return camera
	end)
end
local bulkMoves = 0
roblox.implementMethod("Workspace", "BulkMoveTo", function(_, parts, cframes, _mode)
	assert(#parts == #cframes, "BulkMoveTo: parts/cframes length mismatch")
	for i, p in parts do
		p.CFrame = cframes[i]
	end
	bulkMoves += 1
end)
local renderCallback = nil
roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, priority, fn)
	assert(type(name) == "string" and type(priority) == "number" and type(fn) == "function")
	renderCallback = fn
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)

local players = game:GetService("Players")
local player = Instance.new("Player")
player.Name = "HarnessPlayer"
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
player.Parent = players
-- LocalPlayer is a real (reflected) property, so set it instead of shimming it
local okLP = pcall(function()
	players.LocalPlayer = player
end)
if not okLP or players.LocalPlayer ~= player then
	roblox.implementProperty("Players", "LocalPlayer", function()
		return player
	end)
end

-- Script loader (instance-based require, as in Roblox) -------------------------------------
local noop = function() end
local warnings = {}
local cache = {}
local function load(scriptInst)
	local env
	env = {
		script = scriptInst,
		game = game,
		workspace = workspace,
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		task = task,
		warn = function(...)
			table.insert(warnings, table.concat({ ... }, " "))
			print("[warn]", ...)
		end,
		debug = { profilebegin = noop, profileend = noop, traceback = debug.traceback, info = debug.info },
		require = function(target)
			assert(typeof(target) == "Instance", "string require in Roblox code path")
			if cache[target] == nil then
				cache[target] = load(target)()
			end
			return cache[target]
		end,
	}
	return luau.load(
		scriptInst.Source,
		{ debugName = scriptInst:GetFullName(), environment = env, injectGlobals = true }
	)
end

-- Checks ---------------------------------------------------------------------------------
local failures = 0
local function check(cond, msg)
	if cond then
		print("PASS  " .. msg)
	else
		failures += 1
		print("FAIL  " .. msg)
	end
end

local function frames(n)
	local ok, err = pcall(function()
		for _ = 1, n do
			renderCallback(1 / 60)
		end
	end)
	return ok, err
end

local function overlayText()
	local gui = playerGui:FindFirstChild("GymDebug")
	local label = gui and gui:FindFirstChild("Readout")
	return label and label.Text or ""
end

local function freshOverlay()
	local t0 = os.clock()
	while os.clock() - t0 < 0.21 do
	end
	frames(1)
	return overlayText()
end

local function rigPartsOk()
	local view = workspace:FindFirstChild("GymView")
	local rig = view and view:FindFirstChild("Gymnast")
	if not rig then
		return false, "no Gymnast folder"
	end
	local parts = rig:GetChildren()
	for _, p in parts do
		local pos = p.CFrame.Position
		if pos.X ~= pos.X or pos.Y ~= pos.Y or math.abs(pos.X) > 500 or pos.Y < -20 or pos.Y > 500 then
			return false, `bad position {p.Name} {pos}`
		end
	end
	return #parts == 34, `rig parts={#parts}`
end

local function press(buttonName)
	local gui = playerGui:FindFirstChild("GymDebugButtons")
	local row = gui and gui:FindFirstChildOfClass("Frame")
	local button = row and row:FindFirstChild(buttonName)
	assert(button, "button " .. buttonName)
	button.Activated:Fire()
end

local function key(code)
	game:GetService("UserInputService").InputBegan
		:Fire({ KeyCode = code, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
end

-- Run -------------------------------------------------------------------------------------
local client = game:GetService("StarterPlayer").StarterPlayerScripts.GymClient
local okStart, errStart = pcall(function()
	load(client)()
end)
check(okStart, "GymClient starts without errors " .. (if okStart then "" else tostring(errStart)))
check(renderCallback ~= nil, "render step bound")
if not renderCallback then
	process.exit(1)
end

local ok, err = frames(240)
check(ok, "240 frames of Hang " .. (if ok then "" else tostring(err)))
local partsOk, partsInfo = rigPartsOk()
check(partsOk, "rig parts present and finite (" .. partsInfo .. ")")
check(overlayText():find("scene=Hang", 1, true) ~= nil, "overlay shows scene=Hang")
check(bulkMoves >= 240, "BulkMoveTo called every frame")
local camPos = camera.CFrame.Position
check(camPos.Z > 10 and camPos.Y == camPos.Y, `camera placed on the +Z side (pos {camPos})`)

for i, name in { "Hang", "Drop", "Tumble", "Wheel" } do
	key(({
		roblox.Enum.KeyCode.One,
		roblox.Enum.KeyCode.Two,
		roblox.Enum.KeyCode.Three,
		roblox.Enum.KeyCode.Four,
	})[i])
	ok, err = frames(300)
	check(ok, `key {i} -> {name}, 300 frames ` .. (if ok then "" else tostring(err)))
	check(freshOverlay():find("scene=" .. name, 1, true) ~= nil, `overlay shows scene={name}`)
	partsOk, partsInfo = rigPartsOk()
	check(partsOk, `rig parts ok in {name} ({partsInfo})`)
end

-- Buttons and keys: each debug control, checking its visible effect in the overlay
local function expectOverlay(action, needle, present)
	local text = freshOverlay()
	local found = text:find(needle, 1, true) ~= nil
	check(found == present, `{action}: overlay {if present then "shows" else "no longer shows"} '{needle}'`)
end
key(roblox.Enum.KeyCode.One)
frames(10)
press("Scene")
frames(30)
expectOverlay("button Scene", "scene=Drop", true)
press("Pose")
frames(30)
expectOverlay("button Pose (Crouch -> Limp)", "pose=Limp", true)
press("Slow")
frames(30)
expectOverlay("button Slow", "timeScale 0.50", true)
press("Slow")
frames(30)
expectOverlay("button Slow x2", "timeScale 0.25", true)
press("Moon")
frames(30)
expectOverlay("button Moon", "(moon)", true)
press("Pause")
frames(30)
expectOverlay("button Pause", "[PAUSED]", true)
local stepText = freshOverlay():match("step=(%d+)")
press("Step")
frames(5)
local stepText2 = freshOverlay():match("step=(%d+)")
check(
	tonumber(stepText2) == tonumber(stepText) + 1,
	`button Step advances exactly one step ({stepText} -> {stepText2})`
)
press("Pause")
frames(30)
expectOverlay("button Pause again", "[PAUSED]", false)
press("Info")
frames(5)
local gui = playerGui:FindFirstChild("GymDebug")
check(gui and gui.Readout.Visible == false, "button Info hides the overlay")
press("Info")
frames(5)
check(gui and gui.Readout.Visible == true, "button Info shows the overlay again")
press("Reset")
frames(30)
expectOverlay("button Reset", "step=", true)
key(roblox.Enum.KeyCode.V)
frames(10)
expectOverlay("key V", "pose=", true)
key(roblox.Enum.KeyCode.G)
frames(10)
expectOverlay("key G (moon off)", "(moon)", false)
key(roblox.Enum.KeyCode.T)
frames(10)
expectOverlay("key T (0.25 -> 0.10)", "timeScale 0.10", true)
key(roblox.Enum.KeyCode.P)
frames(10)
expectOverlay("key P", "[PAUSED]", true)
key(roblox.Enum.KeyCode.P)
frames(10)
key(roblox.Enum.KeyCode.C)
ok, err = frames(30)
check(ok, "key C (contact markers on) " .. (if ok then "" else tostring(err)))
local markers = 0
for _, p in workspace.GymView.Course:GetChildren() do
	if p.Name:match("^Contact") and p.Transparency == 0 then
		markers += 1
	end
end
key(roblox.Enum.KeyCode.Two) -- Drop scene: resting contacts
frames(400)
for _, p in workspace.GymView.Course:GetChildren() do
	if p.Name:match("^Contact") and p.Transparency == 0 then
		markers += 1
	end
end
check(markers > 0, `contact markers visible ({markers})`)
key(roblox.Enum.KeyCode.C)
key(roblox.Enum.KeyCode.R)
frames(10)
key(roblox.Enum.KeyCode.T) -- back to 1.0
frames(10)
expectOverlay("key T (0.10 -> 1.00)", "timeScale 1.00", true)

-- Live tuning through attributes (normal and reset-only params, plus an out-of-range value)
local tuning = game:GetService("ReplicatedStorage"):FindFirstChild("GymTuning")
check(tuning ~= nil, "GymTuning folder created")
if tuning then
	check(tuning:GetAttribute("gravity") == 35, "GymTuning mirrors defaults (gravity=35)")
	for keyName, value in { gravity = 60, motorHertz = 3, simHz = 120, friction = 99 } do
		tuning:SetAttribute(keyName, value)
		tuning.AttributeChanged:Fire(keyName)
	end
	check(tuning:GetAttribute("friction") == 2, "out-of-range attribute clamped back to max (friction=2)")
	press("Reset")
	ok, err = frames(240)
	check(ok, "240 frames after live tuning + reset " .. (if ok then "" else tostring(err)))
	check(
		freshOverlay():find("sim 120Hz", 1, true) ~= nil,
		"reset-only param (simHz=120) applied after Reset"
	)
end

-- Long run for stability of the presentation loop
local t0 = os.clock()
ok, err = frames(3600)
local per = (os.clock() - t0) / 3600 * 1000
check(ok, "3600 more frames (1 minute at 60 fps) " .. (if ok then "" else tostring(err)))
print(string.format("harness frame cost (Lune, unoptimized env): %.3f ms/frame", per))
check(#warnings == 0, `no warnings ({#warnings})`)

print(
	if failures == 0
		then "\nCLIENT HARNESS: ALL CHECKS PASSED"
		else `\nCLIENT HARNESS: {failures} CHECK(S) FAILED`
)
process.exit(if failures == 0 then 0 else 1)
