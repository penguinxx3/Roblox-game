--!strict
-- DebugControls: P1.1 test controls only (not gameplay input).
--
--   Keyboard: R reset · 1-4 scenario · V next pose · T cycle slow-mo · G moon gravity
--             P pause · N single step (while paused) · C contact markers · F2 overlay
--   Touch:    a compact button row (top-right) with the same actions.
--   Tuning:   every Tuning parameter is mirrored as an attribute on the client-side
--             folder ReplicatedStorage.GymTuning. Edit them live in Studio's
--             Properties panel during Play (client view). `reset` params apply on reset.
--
-- Gameplay input (Arch/Tuck/Let Go/Grab/Twist, touch-down buttons) is P1.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Gym = ReplicatedStorage:WaitForChild("Gym")
local Sim = require(Gym:WaitForChild("Sim"))
local Rig = require(Gym:WaitForChild("Rig"))
local Tuning = require(Gym:WaitForChild("Tuning"))
local Scenarios = require(Gym:WaitForChild("Scenarios"))

local DebugControls = {}

export type Actions = {
	reset: () -> (),
	scenario: (name: string) -> (),
	toggleOverlay: () -> (),
	toggleContacts: () -> (),
	stepOnce: () -> (),
}

local TIME_SCALES = { 1, 0.5, 0.25, 0.1 }

local function nextTimeScale(current: number): number
	for i, v in TIME_SCALES do
		if math.abs(v - current) < 1e-6 then
			return TIME_SCALES[i % #TIME_SCALES + 1]
		end
	end
	return 1
end

local function nextPose(current: string): string
	local order = Rig.POSE_ORDER
	local i = table.find(order, current) or 0
	return order[i % #order + 1]
end

function DebugControls.bind(sim: any, actions: Actions, playerGui: Instance): { note: string }
	local state = { note = "" }

	local function cycleScenario()
		local list = Scenarios.list
		local idx = 1
		for i, s in list do
			if s.name == sim.scenario then
				idx = i
			end
		end
		actions.scenario(list[idx % #list + 1].name)
	end

	local handlers: { [string]: () -> () } = {
		Reset = actions.reset,
		Scene = cycleScenario,
		Pose = function()
			Sim.setPose(sim, nextPose(sim.rig.pose))
		end,
		Slow = function()
			Sim.setParam(sim, "timeScale", nextTimeScale(sim.tuning.timeScale))
		end,
		Moon = function()
			Sim.setParam(sim, "moonGravity", if sim.tuning.moonGravity >= 0.5 then 0 else 1)
		end,
		Pause = function()
			sim.paused = not sim.paused
		end,
		Step = actions.stepOnce,
		Info = actions.toggleOverlay,
	}

	-- Keyboard (keyed by KeyCode name: robust and readable)
	local keyMap: { [string]: () -> () } = {
		R = handlers.Reset,
		V = handlers.Pose,
		T = handlers.Slow,
		G = handlers.Moon,
		P = handlers.Pause,
		N = handlers.Step,
		C = actions.toggleContacts,
		F2 = handlers.Info,
	}
	for i, keyName in { "One", "Two", "Three", "Four" } do
		local s = Scenarios.list[i]
		if s then
			keyMap[keyName] = function()
				actions.scenario(s.name)
			end
		end
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local fn = keyMap[input.KeyCode.Name]
		if fn then
			fn()
		end
	end)

	-- Touch / mouse button row
	local gui = Instance.new("ScreenGui")
	gui.Name = "GymDebugButtons"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(1, 0)
	row.Position = UDim2.new(1, -8, 0, 8)
	row.Size = UDim2.fromOffset(0, 36)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for i, name in { "Reset", "Scene", "Pose", "Slow", "Moon", "Pause", "Step", "Info" } do
		local b = Instance.new("TextButton")
		b.Name = name
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(58, 36)
		b.BackgroundColor3 = Color3.fromRGB(28, 34, 44)
		b.BackgroundTransparency = 0.2
		b.TextColor3 = Color3.fromRGB(235, 240, 245)
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 14
		b.Text = name
		b.AutoButtonColor = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = b
		b.Parent = row
		b.Activated:Connect(handlers[name])
	end

	-- Live tuning via attributes
	local folder = ReplicatedStorage:FindFirstChild("GymTuning") or Instance.new("Folder")
	folder.Name = "GymTuning"
	for _, p in Tuning.list do
		folder:SetAttribute(p.key, sim.tuning[p.key])
	end
	folder.Parent = ReplicatedStorage
	local syncing = false
	folder.AttributeChanged:Connect(function(key)
		if syncing then
			return
		end
		local p = Tuning.byKey[key]
		local value = folder:GetAttribute(key)
		if p and type(value) == "number" then
			local applied = Sim.setParam(sim, key, value)
			state.note = if p.reset
				then string.format("tuning: %s = %.4g (applies on Reset)", key, applied)
				else string.format("tuning: %s = %.4g", key, applied)
			if applied ~= value then
				syncing = true
				folder:SetAttribute(key, applied) -- show the clamped value
				syncing = false
			end
		end
	end)
	-- keep attributes in sync when buttons change values (slow-mo, moon)
	task.spawn(function()
		while folder.Parent do
			syncing = true
			for _, key in { "timeScale", "moonGravity" } do
				if folder:GetAttribute(key) ~= sim.tuning[key] then
					folder:SetAttribute(key, sim.tuning[key])
				end
			end
			syncing = false
			task.wait(0.25)
		end
	end)

	return state
end

return DebugControls
