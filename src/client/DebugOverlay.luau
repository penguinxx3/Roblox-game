--!strict
-- DebugOverlay: text readout of the simulation (timing, energy, momentum, joints,
-- contacts, events). Refreshed a few times per second to keep string churn low.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gym = ReplicatedStorage:WaitForChild("Gym")
local Sim = require(Gym:WaitForChild("Sim"))
local Rig = require(Gym:WaitForChild("Rig"))
local Tuning = require(Gym:WaitForChild("Tuning"))

local DebugOverlay = {}
DebugOverlay.__index = DebugOverlay

export type Stats = {
	frameMs: number,
	simMs: number,
	renderMs: number,
	steps: number,
	fps: number,
	invalidEvents: number,
	outOfBoundsEvents: number,
	note: string,
}

export type DebugOverlay = typeof(setmetatable(
	{} :: {
		label: TextLabel,
		gui: ScreenGui,
		nextRefresh: number,
		visible: boolean,
	},
	DebugOverlay
))

function DebugOverlay.new(playerGui: Instance): DebugOverlay
	local gui = Instance.new("ScreenGui")
	gui.Name = "GymDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui
	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(230, 236, 240)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Position = UDim2.fromOffset(8, 8)
	label.Size = UDim2.fromOffset(0, 0)
	label.Text = ""
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = label
	label.Parent = gui
	return setmetatable({ label = label, gui = gui, nextRefresh = 0, visible = true }, DebugOverlay)
end

function DebugOverlay.setVisible(self: DebugOverlay, visible: boolean)
	self.visible = visible
	self.label.Visible = visible
end

function DebugOverlay.update(self: DebugOverlay, sim: any, stats: Stats)
	if not self.visible then
		return
	end
	local now = os.clock()
	if now < self.nextRefresh then
		return
	end
	self.nextRefresh = now + 0.2
	local t = sim.tuning
	local m = Sim.metrics(sim)
	local a = Rig.jointAnglesDeg(sim.rig)
	local g = Tuning.effectiveGravity(t)
	local gripErr = if sim.grip then string.format("%.4f", sim.grip.error) else "-"
	local lines = {
		string.format(
			"BAR GYM  P1.1 physics foundation   scene=%s  pose=%s%s",
			sim.scenario,
			sim.rig.pose,
			if sim.paused then "  [PAUSED]" else ""
		),
		string.format(
			"fps %5.1f  frame %5.2f ms  sim %5.3f ms (%d steps)  render %5.3f ms",
			stats.fps,
			stats.frameMs,
			stats.simMs,
			stats.steps,
			stats.renderMs
		),
		string.format(
			"sim %dHz x%d substeps   timeScale %.2f   gravity %.1f%s   t=%.2fs  step=%d",
			t.simHz // 1,
			t.substeps // 1,
			t.timeScale,
			g,
			if t.moonGravity >= 0.5 then " (moon)" else "",
			sim.time,
			sim.stepCount
		),
		string.format(
			"energy  KE %8.1f  PE %8.1f  total %8.1f",
			m.kinetic,
			m.potential,
			m.kinetic + m.potential
		),
		string.format(
			"momentum  p=(%7.2f, %7.2f)  L_com %8.2f   max speed %6.2f",
			m.momentumX,
			m.momentumY,
			m.angularMomentum,
			m.maxSpeed
		),
		string.format(
			"joints  max err %.4f  grip err %s   contacts %d",
			m.maxJointError,
			gripErr,
			m.contactCount
		),
		string.format(
			"angles  sh %6.1f  el %6.1f  hip %6.1f  knee %6.1f  ank %6.1f",
			a.shoulder,
			a.elbow,
			a.hip,
			a.knee,
			a.ankle
		),
		string.format(
			"events  invalid %d  outOfBounds %d   dropped %.3fs",
			stats.invalidEvents,
			stats.outOfBoundsEvents,
			sim.droppedTime
		),
	}
	if stats.note ~= "" then
		table.insert(lines, stats.note)
	end
	table.insert(
		lines,
		"keys: R reset  1-4 scene  V pose  T slow-mo  G moon  P pause  N step  C contacts  F2 hide"
	)
	self.label.Text = table.concat(lines, "\n")
end

return DebugOverlay
