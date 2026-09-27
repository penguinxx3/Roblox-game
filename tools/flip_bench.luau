-- Flip and swing benchmark (P1.2 playtest feedback round): the numbers behind PLAYTEST_P1_2.md.
-- Usage: lune run tools/flip_bench.luau ['{"param": value, ...}']
--
--   A. Standing jumps: plain; Arch held through the release then Tuck in the air (default
--      takeoff spin, and pure physics with jumpSpinAssist 0). Earth, and moon.
--   B. Bar release flips: pump N seconds, let go on a front upswing at an angle, tuck.
--   C. Held shapes on the bar: swing lost per cycle from 90° (relaxed / Tuck / Arch / Pike).
--   D. Pumping from a still hang: time to 30/60/90° and over the top.
-- The pumping rhythm everywhere: Tuck while rising through the lower half of the swing, Arch
-- otherwise (judged by the swing angle and the direction of rotation about the bar).
local process = require("@lune/process")
local serde = require("@lune/serde")
require("./lune_mirror").build("build/lune")
local Sim = require("../build/lune/Gym/Sim")
local Rig = require("../build/lune/Gym/Rig")
local Input = require("../build/lune/Gym/Input")
local Scenarios = require("../build/lune/Gym/Scenarios")

local TAU = 2 * math.pi
local BAR = Scenarios.BAR_HEIGHT
local base = if process.args[1] then serde.decode("json", process.args[1]) else {}

local function with(extra: { [string]: number }): { [string]: number }
	local o = table.clone(base)
	for k, v in extra do
		o[k] = v
	end
	return o
end

-- swing angle (from hanging straight down) and angular momentum about the bar (x = 0)
local function swingState(sim: any): (number, number)
	local ms = Rig.massState(sim.rig)
	local L = 0
	for _, seg in sim.rig.segments do
		local b = seg.body
		L += b.inertia * b.w + b.mass * (b.x * b.vy - (b.y - BAR) * b.vx)
	end
	return math.atan2(ms.cx, BAR - ms.cy), L
end

local function pumpInput(sim: any, inp: any)
	local ang, L = swingState(sim)
	local rising = math.cos(ang) > 0 and ang * L > 0
	inp.tuck = if rising then 1 else 0
	inp.arch = 1 - inp.tuck
end

-- A. standing jump: crouch `hold` s, release (optionally with Arch), optionally tuck in the air
local function standingJump(over: { [string]: number }, hold: number, arch: boolean): string
	local sim = Sim.new(over, "Stand", { control = "player" })
	local inp = Input.new()
	local c = sim.controller
	local release = 1 + hold
	local takeoff, land, spin, turned, y0, top = nil, nil, 0, 0, 0, 0
	local prevA = sim.rig.torso.a
	for i = 1, 240 * 8 do
		local t = sim.time
		inp.tuck = if t >= 1 and t < release then 1 else 0
		inp.arch = if arch and t >= release - 0.05 and takeoff == nil then 1 else 0
		if arch and takeoff and not land then
			inp.tuck, inp.arch = 1, 0
		end
		Sim.setInput(sim, inp)
		Sim.stepOnce(sim)
		local ms = Rig.massState(sim.rig)
		if i == 200 then
			y0 = ms.cy
		end
		if c.mode == "air" and takeoff == nil and sim.time > release then
			takeoff = sim.time
			spin = sim.rig.facing * ms.angularMomentum / ms.inertia / TAU
		end
		if takeoff and not land then
			turned += (sim.rig.torso.a - prevA + math.pi) % TAU - math.pi
			top = math.max(top, ms.cy - y0)
			if c.mode ~= "air" then
				land = sim.time
			end
		end
		prevA = sim.rig.torso.a
		if land and sim.time > land + 0.3 then
			break
		end
	end
	return string.format(
		"rise %.2f  air %.2f s  takeoff spin %+.2f rev/s  rotation %+.2f rev  ends %s",
		top,
		(land or 0) - (takeoff or 0),
		spin,
		sim.rig.facing * turned / TAU,
		c.mode
	)
end

-- B. bar release: pump, let go on a front upswing at `angle`, tuck until touching down
local function barRelease(pumpSecs: number, angle: number): string
	local sim = Sim.new(base, "Hang", { control = "player" })
	local inp = Input.new()
	local c = sim.controller
	local released, relT, spin, turned, prevAng = false, 0, 0, 0, 0
	local prevA = sim.rig.torso.a
	for _ = 1, 240 * (pumpSecs + 8) do
		local ang, L = swingState(sim)
		if not released then
			pumpInput(sim, inp)
			local rising = math.cos(ang) > 0 and ang * L > 0
			local front = L * sim.rig.facing > 0
			local deg, prev = math.abs(math.deg(ang)), math.abs(math.deg(prevAng))
			if sim.time >= pumpSecs and rising and front and deg >= angle and prev < angle then
				inp.letGoPresses += 1
				released, relT = true, sim.time
				local ms = Rig.massState(sim.rig)
				spin = math.abs(ms.angularMomentum / ms.inertia / TAU)
			end
		else
			inp.tuck, inp.arch = 1, 0
		end
		prevAng = ang
		Sim.setInput(sim, inp)
		Sim.stepOnce(sim)
		if released and c.mode == "air" then
			turned += (sim.rig.torso.a - prevA + math.pi) % TAU - math.pi
		end
		prevA = sim.rig.torso.a
		if released and c.mode ~= "air" and c.mode ~= "grip" and sim.time > relT + 0.1 then
			break
		end
	end
	if not released then
		return string.format("%2d°: not reached", angle)
	end
	return string.format(
		"%2d°: spin %.2f rev/s, air %.2f s, %.2f rev (%s)",
		angle,
		spin,
		sim.time - relT,
		math.abs(turned) / TAU,
		c.mode
	)
end

-- C. held shape from 90°: loss per full cycle between half swings 2 and 6
local function heldLoss(arch: number, tuck: number): number
	local sim = Sim.new(with({ hangStartAngle = 90 }), "Hang", { control = "player" })
	local inp = Input.new()
	inp.arch, inp.tuck = arch, tuck
	local peaks, peak, lastSign = {}, 0, 0
	for _ = 1, 240 * 9 do
		Sim.setInput(sim, inp)
		Sim.stepOnce(sim)
		local ang, L = swingState(sim)
		peak = math.max(peak, math.abs(math.deg(ang)))
		local sign = if L > 0 then 1 else -1
		if lastSign ~= 0 and sign ~= lastSign then
			table.insert(peaks, peak)
			peak = 0
		end
		lastSign = sign
	end
	return (peaks[2] - peaks[6]) / 2
end

-- D. pumping from a still hang
local function fromStill(): string
	local sim = Sim.new(with({ hangStartAngle = 0 }), "Hang", { control = "player" })
	local inp = Input.new()
	local marks = { 30, 60, 90 }
	local reached: { [number]: number } = {}
	local over: number? = nil
	for _ = 1, 240 * 25 do
		pumpInput(sim, inp)
		Sim.setInput(sim, inp)
		Sim.stepOnce(sim)
		local deg = math.abs(math.deg((swingState(sim))))
		for _, m in marks do
			if deg >= m and reached[m] == nil then
				reached[m] = sim.time
			end
		end
		if deg >= 175 and over == nil then
			over = sim.time
		end
	end
	local parts = {}
	for _, m in marks do
		table.insert(
			parts,
			string.format("%d° %s", m, if reached[m] then string.format("%.1f s", reached[m]) else "-")
		)
	end
	table.insert(parts, "over the top " .. (if over then string.format("%.1f s", over) else "- (25 s)"))
	return table.concat(parts, ", ")
end

print("A. standing jumps (crouch 0.6 s; moon 1.4 s)")
print("   plain                          " .. standingJump(base, 0.6, false))
print("   Arch takeoff + tuck            " .. standingJump(base, 0.6, true))
print("   same, pure physics (assist 0)  " .. standingJump(with({ jumpSpinAssist = 0 }), 0.6, true))
print("   moon, Arch takeoff + tuck      " .. standingJump(with({ moonGravity = 1 }), 1.4, true))
print(
	"   moon, pure physics (assist 0)  "
		.. standingJump(with({ moonGravity = 1, jumpSpinAssist = 0 }), 1.4, true)
)
print("B. bar release flips (Hang, let go on a front upswing, then tuck)")
for _, secs in { 0, 4 } do
	local parts = {}
	for _, a in { 30, 50, 70 } do
		table.insert(parts, barRelease(secs, a))
	end
	print(string.format("   pump %d s: %s", secs, table.concat(parts, " | ")))
end
print("C. swing lost per cycle from 90° while holding a shape")
print(
	string.format(
		"   relaxed %.1f°  Tuck %.1f°  Arch %.1f°  Pike %.1f°",
		heldLoss(0, 0),
		heldLoss(0, 1),
		heldLoss(1, 0),
		heldLoss(1, 1)
	)
)
print("D. pumping from a still hang (hangStartAngle 0)")
print("   " .. fromStill())
