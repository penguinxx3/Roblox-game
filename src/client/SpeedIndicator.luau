--!strict
-- SpeedIndicator: shows the slow-motion speed (e.g. "SLOW-MO 0.25×") at the top of the screen
-- while the simulation runs slower than real time; hidden at normal speed. Display only: it
-- reads the time scale and never changes it (P1.2 playtest round 2).

local SpeedIndicator = {}
SpeedIndicator.__index = SpeedIndicator

export type SpeedIndicator = typeof(setmetatable(
	{} :: {
		label: TextLabel,
		shown: number, -- the time scale the label currently shows (1 = hidden)
	},
	SpeedIndicator
))

function SpeedIndicator.new(playerGui: Instance): SpeedIndicator
	local gui = Instance.new("ScreenGui")
	gui.Name = "GymSpeed"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	local label = Instance.new("TextLabel")
	label.Name = "Speed"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 8)
	label.Size = UDim2.fromOffset(0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(255, 214, 102)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Text = ""
	label.Visible = false
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	label.Parent = gui
	return setmetatable({ label = label, shown = 1 }, SpeedIndicator)
end

-- Call every frame; only touches the label when the speed changes.
function SpeedIndicator.update(self: SpeedIndicator, timeScale: number)
	if timeScale == self.shown then
		return
	end
	self.shown = timeScale
	local slowed = timeScale < 0.999
	self.label.Visible = slowed
	if slowed then
		self.label.Text = string.format("SLOW-MO %g×", timeScale)
	end
end

return SpeedIndicator
