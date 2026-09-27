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
for _, name in { "InputBegan", "InputEnded", "InputChanged" } do
	roblox.implementProperty("UserInputService", name, function(inst)
		return signalFor(inst, name)
	end)
end
for _, name in { "InputBegan", "InputEnded" } do
	roblox.implementProperty("GuiObject", name, function(inst)
		return signalFor(inst, name)
	end)
end

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

-- pretend to be a touch device so the touch layout is built and can be driven
local uisInstance = game:GetService("UserInputService")
local okTouch = pcall(function()
	uisInstance.TouchEnabled = true
end)
if not okTouch then
	roblox.implementProperty("UserInputService", "TouchEnabled", function()
		return true
	end)
end

-- keyboard modifier state for IsKeyDown (the blind A/B reveal is Shift+B)
local shiftDown = false
roblox.implementMethod("UserInputService", "IsKeyDown", function(_, code)
	return shiftDown and code.Name == "LeftShift"
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
	-- the drawn body (Look): torso block, neck, head + per side 5 arm and 6 leg shapes
	return #parts == 25, `rig parts={#parts}`
end

local function press(buttonName)
	local gui = playerGui:FindFirstChild("GymDebugButtons")
	local row = gui and gui:FindFirstChildOfClass("Frame")
	local button = row and row:FindFirstChild(buttonName)
	assert(button, "button " .. buttonName)
	button.Activated:Fire()
end

local UIS = game:GetService("UserInputService")
local function key(code)
	UIS.InputBegan:Fire({ KeyCode = code, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
end
local function keyUp(code)
	UIS.InputEnded:Fire({ KeyCode = code, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
end
local function pad(event, code, z)
	UIS[event]:Fire({
		KeyCode = code,
		UserInputType = roblox.Enum.UserInputType.Gamepad1,
		Position = roblox.Vector3.new(0, 0, z or 1),
	}, false)
end
-- slow-motion speed indicator (P1.2 round 2): its text, or nil while hidden
local function speedText()
	local gui = playerGui:FindFirstChild("GymSpeed")
	local label = gui and gui:FindFirstChild("Speed")
	return if label and label.Visible then label.Text else nil
end
local function touchButton(name)
	local gui = playerGui:FindFirstChild("GymTouch")
	return gui and gui:FindFirstChild(name)
end
local function overlayField(pattern)
	return freshOverlay():match(pattern)
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
check(speedText() == nil, "slow-mo indicator hidden at normal speed (start)")
check(bulkMoves >= 240, "BulkMoveTo called every frame")
local camPos = camera.CFrame.Position
check(camPos.Z > 10 and camPos.Y == camPos.Y, `camera placed on the +Z side (pos {camPos})`)

for i, name in { "Hang", "Drop", "Tumble", "Wheel", "Stand" } do
	key(({
		roblox.Enum.KeyCode.One,
		roblox.Enum.KeyCode.Two,
		roblox.Enum.KeyCode.Three,
		roblox.Enum.KeyCode.Four,
		roblox.Enum.KeyCode.Five,
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
expectOverlay("button Pose (off -> Neutral)", "pose override=Neutral", true)
press("Slow")
frames(30)
expectOverlay("button Slow", "timeScale 0.50", true)
check(speedText() == "SLOW-MO 0.5×", `slow-mo indicator shows 0.5× ({tostring(speedText())})`)
press("Slow")
frames(30)
expectOverlay("button Slow x2", "timeScale 0.25", true)
check(speedText() == "SLOW-MO 0.25×", `slow-mo indicator shows 0.25× ({tostring(speedText())})`)
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
expectOverlay("key V (Neutral -> Tuck)", "pose override=Tuck", true)
for _ = 1, 5 do
	key(roblox.Enum.KeyCode.V)
end
frames(10)
expectOverlay("key V cycles back to player input", "player input", true)
key(roblox.Enum.KeyCode.G)
frames(10)
expectOverlay("key G (moon off)", "(moon)", false)
key(roblox.Enum.KeyCode.T)
frames(10)
expectOverlay("key T (0.25 -> 0.10)", "timeScale 0.10", true)
check(speedText() == "SLOW-MO 0.1×", `slow-mo indicator shows 0.1× ({tostring(speedText())})`)
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
check(speedText() == nil, "slow-mo indicator hidden at normal speed")

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

-- Blind A/B (P1.2 feedback): hidden labels, switch by key or button, reveal with Shift+B
do
	local E = roblox.Enum
	key(E.KeyCode.B)
	frames(5)
	local text = freshOverlay()
	check(text:find("blind A/B: now A", 1, true) ~= nil, "key B starts the blind A/B at A")
	check(text:find("motorHertz", 1, true) == nil, "the A/B label hides the value")
	press("A/B")
	frames(5)
	check(freshOverlay():find("blind A/B: now B", 1, true) ~= nil, "A/B button switches to B")
	shiftDown = true
	key(E.KeyCode.B)
	shiftDown = false
	frames(5)
	local a, b = freshOverlay():match("A = motorHertz (%d+), B = motorHertz (%d+)")
	check(
		(a == "6" and b == "8") or (a == "8" and b == "6"),
		`Shift+B reveals the mapping (A={tostring(a)}, B={tostring(b)})`
	)
	local revealed = freshOverlay()
	check(revealed:find("now B", 1, true) ~= nil, "reveal keeps the current variant (B)")
	check(
		revealed:find("played A %d+%.%d min, B %d+%.%d min, 2 switches") ~= nil,
		"reveal reports time on each variant and the number of switches"
	)
end

-- Gameplay input (P1.2): keyboard, gamepad and touch through InputRouter --------------------
local Enum = roblox.Enum
key(Enum.KeyCode.One) -- Hang
frames(30)
key(Enum.KeyCode.A)
frames(20)
expectOverlay("key A holds Arch", "arch 1.00", true)
keyUp(Enum.KeyCode.A)
frames(5)
expectOverlay("releasing A", "arch 0.00", true)
key(Enum.KeyCode.W)
frames(20)
expectOverlay("key W lets go of the bar", "mode=air", true)
expectOverlay("Let Go counted once", "letGo 1", true)

key(Enum.KeyCode.Five) -- Stand
frames(120)
expectOverlay("Stand scene is grounded", "mode=ground", true)
key(Enum.KeyCode.S)
frames(36)
check((tonumber(overlayField("crouch (%d%.%d+)")) or 0) > 0.5, "holding S crouches")
keyUp(Enum.KeyCode.S)
local sawAir, sawLanding = false, false
for _ = 1, 60 do
	frames(1)
	local text = freshOverlay()
	sawAir = sawAir or text:find("mode=air", 1, true) ~= nil
	sawLanding = sawLanding or (sawAir and text:find("mode=ground", 1, true) ~= nil)
	if sawLanding then
		break
	end
end
check(sawAir, "releasing S from a crouch jumps (airborne)")
check(sawLanding, "the jump lands back on the feet")

key(Enum.KeyCode.Three) -- Tumble: in the air, twist
frames(10)
key(Enum.KeyCode.E)
local prevPositions, worstJump, snapped = nil, 0, false
for _ = 1, 30 do
	frames(1)
	local positions = {}
	for _, p in workspace.GymView.Gymnast:GetChildren() do
		positions[p] = p.CFrame.Position
	end
	if prevPositions then
		for p, pos in positions do
			local before = prevPositions[p]
			if before then
				-- paired limbs may swap sides at the half-twist snap; compare against the nearest
				local best = (pos - before).Magnitude
				for q, other in prevPositions do
					if q.Name == p.Name then
						best = math.min(best, (pos - other).Magnitude)
					end
				end
				worstJump = math.max(worstJump, best)
			end
		end
	end
	prevPositions = positions
end
keyUp(Enum.KeyCode.E)
frames(5)
snapped = (tonumber(overlayField("%((%d+) half%)")) or 0) > 0
check(snapped, "holding E twists through a half twist")
check(worstJump < 2.5, `twisting body moves continuously on screen (largest per-frame part move {worstJump})`)
local twistDeg = tonumber(overlayField("twist%s+(%-?%d+%.%d)°"))
check(twistDeg ~= nil and math.abs(twistDeg) > 1, `twist angle shown and held after release ({twistDeg})`)

-- gamepad: analog trigger and a shoulder button
key(Enum.KeyCode.One)
frames(10)
pad("InputChanged", Enum.KeyCode.ButtonR2, 0.5)
frames(5)
expectOverlay("gamepad RT half-pressed = Tuck 0.50", "tuck 0.50", true)
pad("InputChanged", Enum.KeyCode.ButtonR2, 0)
pad("InputBegan", Enum.KeyCode.ButtonB)
frames(10)
expectOverlay("gamepad B lets go", "mode=air", true)

-- touch: buttons exist, react on touch-down, several at once
local names = { "Arch", "Tuck", "TwistLeft", "TwistRight", "LetGo", "Grab" }
local allThere = true
for _, n in names do
	allThere = allThere and touchButton(n) ~= nil
end
check(allThere, "touch layout has Arch, Tuck, Twist ◄/►, Let Go and Grab")
key(Enum.KeyCode.One)
frames(10)
local touchA = { UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown }
local touchB = { UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown }
touchButton("Tuck").InputBegan:Fire(touchA)
touchButton("Arch").InputBegan:Fire(touchB)
frames(5)
local text = freshOverlay()
check(
	text:find("tuck 1.00", 1, true) ~= nil and text:find("arch 1.00", 1, true) ~= nil,
	"two thumbs: Tuck + Arch held (pike)"
)
touchButton("Tuck").InputEnded:Fire(touchA)
touchButton("Arch").InputEnded:Fire(touchB)
frames(5)
expectOverlay("touch released", "tuck 0.00", true)
touchButton("LetGo").InputBegan:Fire(touchA)
frames(10)
expectOverlay("touch-down on LET GO releases the bar", "mode=air", true)
touchButton("LetGo").InputEnded:Fire(touchA)

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
