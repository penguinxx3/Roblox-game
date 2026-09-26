--!strict
-- Input: the device-independent player input the simulation consumes.
--
-- A Frame is plain data, the same for touch, keyboard and gamepad. The client's input
-- router fills one in from whatever devices are active; the simulation reads it once
-- per fixed step. Nothing here touches Roblox, so the same frames can later be recorded,
-- replayed, or sent to a server that runs the same simulation.
--
-- Held actions are levels (0..1, analog on gamepad triggers). Press actions are
-- cumulative counters: a press increments the counter, and the controller acts on any
-- increase since the last step it ran. A press can therefore never be lost, even when a
-- frame runs zero simulation steps (slow motion, high frame rates) or several presses
-- land in one frame. Timing stays in simulation steps, so it is frame-rate independent.

local Input = {}

export type Frame = {
	arch: number, -- 0..1 hold (both arch and tuck = pike)
	tuck: number, -- 0..1 hold
	twistLeft: boolean, -- hold
	twistRight: boolean, -- hold
	letGoPresses: number, -- press counter
	grabPresses: number, -- press counter (Grab: consumed from P1.3; counted already)
	twistLeftPresses: number, -- press counters (used by the "momentum" twist mode)
	twistRightPresses: number,
}

function Input.new(): Frame
	return {
		arch = 0,
		tuck = 0,
		twistLeft = false,
		twistRight = false,
		letGoPresses = 0,
		grabPresses = 0,
		twistLeftPresses = 0,
		twistRightPresses = 0,
	}
end

function Input.copy(from: Frame, into: Frame?): Frame
	local f = into or Input.new()
	f.arch = from.arch
	f.tuck = from.tuck
	f.twistLeft = from.twistLeft
	f.twistRight = from.twistRight
	f.letGoPresses = from.letGoPresses
	f.grabPresses = from.grabPresses
	f.twistLeftPresses = from.twistLeftPresses
	f.twistRightPresses = from.twistRightPresses
	return f
end

-- Clamps levels to [0, 1] and replaces non-finite values (defensive: frames may later
-- arrive over the network).
function Input.sanitize(f: Frame): Frame
	local function level(v: number): number
		if v ~= v then
			return 0
		end
		return math.clamp(v, 0, 1)
	end
	f.arch = level(f.arch)
	f.tuck = level(f.tuck)
	return f
end

-- Shape blend weights from the two shape levels (PHYSICS_DESIGN §3):
-- both held = pike. Returns (tuck, arch, pike) weights, each in [0, 1], summing to ≤ 1.
function Input.shapeWeights(f: Frame): (number, number, number)
	local p = math.min(f.tuck, f.arch)
	return f.tuck - p, f.arch - p, p
end

-- Twist direction from the held buttons: -1 left, +1 right, 0 none or both.
function Input.twistAxis(f: Frame): number
	local l = if f.twistLeft then 1 else 0
	local r = if f.twistRight then 1 else 0
	return r - l
end

return Input
