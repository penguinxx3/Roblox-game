--!strict
-- InputRouter: keyboard, gamepad and touch -> one device-independent Input.Frame per render
-- frame (GAME_PLAN §4). The simulation only ever sees the frame; nothing here knows physics.
--
--   Action        Keyboard      Gamepad        Touch (minimal layout, P1.2)
--   Arch (hold)   A  or  ←      LT (analog)    ARCH   (left thumb)
--   Tuck (hold)   S  or  ↓      RT (analog)    TUCK   (left thumb)
--   Let Go        W  or  ↑      B              LET GO (right thumb)
--   Grab          Space or J    A              GRAB   (right thumb; dimmed until P1.3 uses it)
--   Twist L / R   Q / E         LB / RB        ◄ / ►  (right thumb; both = hold the angle)
--   Reset         R (debug)     Y              (debug button row)
--
-- Presses are counted on key-down / touch-down (never on release) and are never dropped:
-- the simulation acts on every counter increase at its next fixed step. Held actions are
-- the maximum over devices, so thumbs, keys and triggers can be mixed freely.
--
-- The touch layout is a functional placeholder, not the mobile UI: plain buttons that react
-- on touch-down, support several simultaneous touches and also accept mouse clicks (for
-- testing in Studio). Each button has a short hint under its name. Shown on touch devices,
-- or on any device with `showTouch`.
--
-- `device` is the kind of input used last ("keyboard" | "gamepad" | "touch"), so the help
-- panel can name the right keys; NAMES says what each action is called on each device.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Gym = ReplicatedStorage:WaitForChild("Gym")
local Input = require(Gym:WaitForChild("Input"))

local InputRouter = {}
InputRouter.__index = InputRouter

type Held = { arch: number, tuck: number, twistLeft: boolean, twistRight: boolean }

export type Device = "keyboard" | "gamepad" | "touch"

-- What each action is called on screen, per device (keep in step with the bindings below)
InputRouter.NAMES = {
	keyboard = { arch = "A", tuck = "S", letGo = "W", twist = "Q / E", grab = "Space", reset = "R" },
	gamepad = { arch = "LT", tuck = "RT", letGo = "B", twist = "LB / RB", grab = "A", reset = "Y" },
	touch = {
		arch = "ARCH",
		tuck = "TUCK",
		letGo = "LET GO",
		twist = "◄ ►",
		grab = "GRAB",
		reset = "Reset",
	},
}

export type Router = typeof(setmetatable(
	{} :: {
		frame: Input.Frame,
		keyboard: Held,
		gamepad: Held,
		touch: Held,
		touchGui: ScreenGui?,
		onReset: (() -> ())?,
		device: Device,
	},
	InputRouter
))

local function blankHeld(): Held
	return { arch = 0, tuck = 0, twistLeft = false, twistRight = false }
end

-- Keyboard bindings by KeyCode name (robust against enum identity differences).
local KEY_HOLD: { [string]: string } = {
	A = "arch",
	Left = "arch",
	S = "tuck",
	Down = "tuck",
	Q = "twistLeft",
	E = "twistRight",
}
local KEY_PRESS: { [string]: string } = {
	W = "letGoPresses",
	Up = "letGoPresses",
	Space = "grabPresses",
	J = "grabPresses",
}
local PAD_HOLD: { [string]: string } = {
	ButtonL2 = "arch",
	ButtonR2 = "tuck",
	ButtonL1 = "twistLeft",
	ButtonR1 = "twistRight",
}
local PAD_PRESS: { [string]: string } = {
	ButtonB = "letGoPresses",
	ButtonA = "grabPresses",
}

local function setHeld(held: Held, action: string, down: boolean, level: number?)
	if action == "arch" or action == "tuck" then
		(held :: any)[action] = if down then (level or 1) else 0
	else
		(held :: any)[action] = down
	end
end

function InputRouter.new(playerGui: Instance, options: { showTouch: boolean?, onReset: (() -> ())? }?): Router
	local self = setmetatable({
		frame = Input.new(),
		keyboard = blankHeld(),
		gamepad = blankHeld(),
		touch = blankHeld(),
		touchGui = nil,
		onReset = options and options.onReset,
		device = (if UserInputService.TouchEnabled then "touch" else "keyboard") :: Device,
	}, InputRouter)

	local function isGamepad(inputType: Enum.UserInputType): boolean
		return inputType.Name:match("^Gamepad") ~= nil
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local keyName = input.KeyCode.Name
		local kind = input.UserInputType.Name
		if kind == "Touch" then
			self.device = "touch"
		elseif kind == "Keyboard" then
			self.device = "keyboard"
		end
		if isGamepad(input.UserInputType) then
			self.device = "gamepad"
			local hold = PAD_HOLD[keyName]
			if hold then
				setHeld(self.gamepad, hold, true)
			end
			local pressKey = PAD_PRESS[keyName]
			if pressKey then
				(self.frame :: any)[pressKey] += 1
			end
			if keyName == "ButtonL1" then
				self.frame.twistLeftPresses += 1
			elseif keyName == "ButtonR1" then
				self.frame.twistRightPresses += 1
			elseif keyName == "ButtonY" and self.onReset then
				self.onReset()
			end
			return
		end
		if processed then
			return -- typing in a text box, etc.
		end
		local hold = KEY_HOLD[keyName]
		if hold then
			setHeld(self.keyboard, hold, true)
		end
		local pressKey = KEY_PRESS[keyName]
		if pressKey then
			(self.frame :: any)[pressKey] += 1
		end
		-- twist keys are holds, and also count as taps for the momentum twist mode
		if keyName == "Q" then
			self.frame.twistLeftPresses += 1
		elseif keyName == "E" then
			self.frame.twistRightPresses += 1
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local keyName = input.KeyCode.Name
		if isGamepad(input.UserInputType) then
			local hold = PAD_HOLD[keyName]
			if hold then
				setHeld(self.gamepad, hold, false)
			end
			return
		end
		local hold = KEY_HOLD[keyName]
		if hold then
			setHeld(self.keyboard, hold, false)
		end
	end)

	-- analog triggers
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not isGamepad(input.UserInputType) then
			return
		end
		local keyName = input.KeyCode.Name
		if keyName == "ButtonL2" or keyName == "ButtonR2" then
			local level = math.clamp(input.Position.Z, 0, 1)
			if level > 0.02 then
				self.device = "gamepad"
			end
			local action = PAD_HOLD[keyName]
			setHeld(self.gamepad, action, level > 0.02, level)
		end
	end)

	if UserInputService.TouchEnabled or (options and options.showTouch) then
		self:buildTouch(playerGui)
	end
	return self
end

-- Minimal touch layout A (GAME_PLAN §4): left thumb ARCH / TUCK, right thumb twist, LET GO, GRAB.
function InputRouter.buildTouch(self: Router, playerGui: Instance)
	if self.touchGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GymTouch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	self.touchGui = gui

	-- a text line inside a button; not Active, so touches still reach the button
	local function text(parent: Instance, name: string, value: string, y: number, h: number, font: Enum.Font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Active = false
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0.08, 0, y, 0)
		l.Size = UDim2.new(0.84, 0, h, 0)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(240, 244, 248)
		l.Text = value
		l.Parent = parent
		return l
	end

	-- a button: the action's name, and under it a short hint of what it does
	local function button(
		name: string,
		label: string,
		hint: string,
		anchor: Vector2,
		pos: UDim2,
		size: number
	)
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = anchor
		b.Position = pos
		b.Size = UDim2.new(size, 0, size, 0)
		b.BackgroundColor3 = Color3.fromRGB(28, 34, 44)
		b.BackgroundTransparency = 0.45
		b.Text = ""
		b.AutoButtonColor = false
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.DominantAxis = Enum.DominantAxis.Height
		aspect.Parent = b
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = b
		text(b, "Label", label, 0.2, 0.36, Enum.Font.GothamBold)
		local h = text(b, "Hint", hint, 0.62, 0.18, Enum.Font.GothamMedium)
		h.TextTransparency = 0.2
		b.Parent = gui
		return b
	end

	-- sizes are fractions of the screen height (landscape phones)
	local holds: { [string]: string } = {
		Arch = "arch",
		Tuck = "tuck",
		TwistLeft = "twistLeft",
		TwistRight = "twistRight",
	}
	local presses: { [string]: string } = {
		LetGo = "letGoPresses",
		Grab = "grabPresses",
		TwistLeft = "twistLeftPresses",
		TwistRight = "twistRightPresses",
	}
	local buttons = {
		button("Arch", "ARCH", "open · reach", Vector2.new(0, 1), UDim2.new(0.03, 0, 0.62, 0), 0.24),
		button("Tuck", "TUCK", "curl · crouch", Vector2.new(0, 1), UDim2.new(0.03, 0, 0.94, 0), 0.24),
		button("TwistLeft", "◄", "twist", Vector2.new(1, 1), UDim2.new(0.84, 0, 0.56, 0), 0.18),
		button("TwistRight", "►", "twist", Vector2.new(1, 1), UDim2.new(0.97, 0, 0.56, 0), 0.18),
		button("LetGo", "LET GO", "drop the bar", Vector2.new(1, 1), UDim2.new(0.80, 0, 0.94, 0), 0.22),
		button("Grab", "GRAB", "next update", Vector2.new(1, 1), UDim2.new(0.97, 0, 0.94, 0), 0.28),
	}
	-- Grab has no effect until catching arrives (P1.3): shown dimmed so it isn't mistaken
	-- for a working button
	local grab = buttons[6]
	for _, l in grab:GetChildren() do
		if l:IsA("TextLabel") then
			l.TextTransparency = 0.55
		end
	end
	for _, b in buttons do
		local active: { [any]: boolean } = {}
		local idle = if b == grab then 0.7 else 0.45
		b.BackgroundTransparency = idle
		local function refresh()
			local down = next(active) ~= nil
			local hold = holds[b.Name]
			if hold then
				setHeld(self.touch, hold, down)
			end
			b.BackgroundTransparency = if down then 0.15 else idle
		end
		b.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType.Name
			if t == "Touch" or t == "MouseButton1" then
				if t == "Touch" then
					self.device = "touch"
				end
				active[input] = true
				local pressKey = presses[b.Name]
				if pressKey then
					(self.frame :: any)[pressKey] += 1
				end
				refresh()
			end
		end)
		b.InputEnded:Connect(function(input: InputObject)
			if active[input] then
				active[input] = nil
				refresh()
			end
		end)
	end
end

-- The input for this frame: held levels combined across devices, press counters as counted.
function InputRouter.sample(self: Router): Input.Frame
	local f = self.frame
	local k, g, t = self.keyboard, self.gamepad, self.touch
	f.arch = math.max(k.arch, g.arch, t.arch)
	f.tuck = math.max(k.tuck, g.tuck, t.tuck)
	f.twistLeft = k.twistLeft or g.twistLeft or t.twistLeft
	f.twistRight = k.twistRight or g.twistRight or t.twistRight
	return f
end

return InputRouter
