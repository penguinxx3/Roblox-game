--!strict
-- HelpPanel: a short "what to do now" card at the bottom of the screen, between the thumb
-- buttons. It follows the body's situation (on the bar, in the air, on the feet, fallen) and
-- names the controls of the device used last (keys, gamepad buttons or the touch buttons).
-- Display only: it reads the simulation and never changes it. Hidden with the Help button / H.

local InputRouter = require(script.Parent:WaitForChild("InputRouter"))

local HelpPanel = {}
HelpPanel.__index = HelpPanel

export type HelpPanel = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		frame: Frame,
		title: TextLabel,
		body: TextLabel,
		footer: TextLabel,
		visible: boolean,
		shown: string, -- what the card currently shows (situation, device and note)
		touchShown: boolean,
		screen: Vector2, -- the screen size the card was last fitted to
	},
	HelpPanel
))

local KEY_COLOR = "#FFD666"

-- Each situation: a title and lines; {arch} etc. become the device's name for that action.
local CARDS: { [string]: { title: string, lines: { string } } } = {
	grip = {
		title = "ON THE BAR",
		lines = {
			"Swing higher: hold {tuck} going up, {arch} coming down.",
			"Press {letGo} on a forward upswing, then hold {tuck} to flip.",
		},
	},
	air = {
		title = "IN THE AIR",
		lines = {
			"Hold {tuck} to spin faster, {arch} to slow down, {twist} to twist.",
			"Open up before you land. Catching bars comes in the next update.",
		},
	},
	ground = {
		title = "ON YOUR FEET",
		lines = {
			"Jump: hold {tuck} to crouch, then let go of it.",
			"Backflip: hold {arch} as you let go of {tuck}.",
		},
	},
	fallen = {
		title = "YOU FELL",
		lines = {
			"Press {reset} to start again. Getting up comes in a later update.",
		},
	},
}

local FOOTERS: { [string]: string } = {
	keyboard = "{reset} start again · {1}–{5} other scenes · {H} hide help",
	gamepad = "{reset} start again",
	touch = "{reset} start again · {Scene} other places · {Help} hide this",
}

-- the action a key stands for, said after a key or gamepad button: "S (Tuck)"
local WORDS: { [string]: string } = { arch = "Arch", tuck = "Tuck", letGo = "Let Go", grab = "Grab" }

-- "{tuck}" -> the device's name for Tuck, highlighted; any other "{X}" -> X, highlighted
local function fill(template: string, device: string): string
	local names: { [string]: string } = (InputRouter.NAMES :: any)[device] or InputRouter.NAMES.keyboard
	return (
		string.gsub(template, "{(%w+)}", function(action: string): string
			local key = `<b><font color="{KEY_COLOR}">{names[action] or action}</font></b>`
			local word = WORDS[action]
			return if device ~= "touch" and word then `{key} ({word})` else key
		end)
	)
end

local function label(parent: Instance, name: string, order: number, size: number, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = order
	l.Active = false
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = font
	l.TextSize = size
	l.TextWrapped = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = Color3.fromRGB(240, 244, 248)
	l.Text = ""
	l.Parent = parent
	return l
end

-- `touchShown`: the touch buttons are on screen, so sit between the two thumb clusters.
function HelpPanel.new(playerGui: Instance, touchShown: boolean): HelpPanel
	local gui = Instance.new("ScreenGui")
	gui.Name = "GymHelp"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.Active = false
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(if touchShown then 0.42 else 0.5, 0, 1, -10)
	frame.Size = UDim2.new(0.4, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	frame.BackgroundTransparency = 0.3
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, math.huge)
	limit.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame
	local title = label(frame, "Title", 1, 17, Enum.Font.GothamBold)
	local body = label(frame, "Body", 2, 15, Enum.Font.GothamMedium)
	local footer = label(frame, "Footer", 3, 13, Enum.Font.Gotham)
	footer.TextTransparency = 0.3
	frame.Parent = gui
	return setmetatable({
		gui = gui,
		frame = frame,
		title = title,
		body = body,
		footer = footer,
		visible = true,
		shown = "",
		touchShown = touchShown,
		screen = Vector2.zero,
	}, HelpPanel)
end

function HelpPanel.setVisible(self: HelpPanel, visible: boolean)
	self.visible = visible
	self.frame.Visible = visible
end

-- With the touch buttons on screen, use the whole gap between the thumb clusters (the
-- button rectangles are InputRouter's: ARCH/TUCK end at 0.03 W + 0.24 H, LET GO starts at
-- 0.80 W - 0.22 H), so the card stays a few lines tall and clear of the body.
local function fit(self: HelpPanel)
	local size = self.gui.AbsoluteSize
	if size == self.screen or size.X < 1 or size.Y < 1 then
		return
	end
	self.screen = size
	local W, H = size.X, size.Y
	local left, right = 0.25 * W, 0.75 * W
	if self.touchShown then
		left, right = 0.03 * W + 0.24 * H + 12, 0.80 * W - 0.22 * H - 12
	end
	local width = math.clamp(right - left, 200, 520)
	self.frame.Size = UDim2.fromOffset(width, 0)
	-- small phones: a size smaller, so the card stays low
	local small = H < 400
	self.title.TextSize = if small then 15 else 17
	self.body.TextSize = if small then 14 else 15
	self.footer.TextSize = if small then 12 else 13
	self.frame.Position = UDim2.new(0, (left + right) / 2, 1, -10)
end

-- Call every frame; only rewrites the text when the situation, device or note changes.
function HelpPanel.update(self: HelpPanel, mode: string, device: string, note: string)
	if not self.visible then
		return
	end
	fit(self)
	local key = `{mode}|{device}|{note}`
	if key == self.shown then
		return
	end
	self.shown = key
	local card = CARDS[mode] or CARDS.air
	local lines = {}
	for _, line in card.lines do
		table.insert(lines, "• " .. fill(line, device))
	end
	if note ~= "" then
		table.insert(lines, `<i>{note}</i>`)
	end
	self.title.Text = card.title
	self.body.Text = table.concat(lines, "\n")
	self.footer.Text = fill(FOOTERS[device] or FOOTERS.keyboard, device)
end

return HelpPanel
