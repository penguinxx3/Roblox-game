-- Smoothness benchmark (P1.2): how settings that shape motion change response, overshoot,
-- wobble and jerk of player-driven shape changes, and the tuck's spin gain.
-- Usage: lune run tools/smooth_bench.luau
--
-- Scenario A (air, zero gravity, no spin): input steps Neutral -> Tuck -> Neutral -> Arch -> Neutral,
-- 1.5 s each. For the hip and knee angles it measures:
--   response  slowest time to cover 63% of a target change (s)
--   overshoot largest excursion past the target (deg)
--   wobble    mean distance from the target 0.4-1.5 s after each input change (deg): the
--             lingering jiggle of the coupled limb springs
--   jerk      RMS of the third derivative of the joint angles sampled at 60 Hz (deg/s³), a
--             standard smoothness measure: lower = smoother, fewer snaps
-- Scenario B (air, spinning): tuck spin gain as in Tumble (reference ≈ 1.6×).
-- Scenario C (hanging): torso angular jerk while pumping with Arch/Tuck (RMS at 60 Hz, rad/s³).
require("./lune_mirror").build("build/lune")
local Sim = require("../build/lune/Gym/Sim")
local Rig = require("../build/lune/Gym/Rig")
local Input = require("../build/lune/Gym/Input")

local H = 1 / 240
local JOINTS = { "hip", "knee" }
local PHASE_STEPS = 360 -- 1.5 s per input phase
local FRAME = 4 -- jerk is measured on 60 Hz samples (what is rendered)

local function measure(over)
	-- gravity effectively off (strength kept at Earth values), body still: pure shape changes
	local o = table.clone(over)
	o.strengthGravityScaling = 0
	o.gravity = 5
	o.moonGravity = 1
	o.moonGravityScale = 0.05 -- 0.25 studs/s²: negligible over 5 s at this body size
	o.landingReflex = 0 -- slowly "falling" and upright would otherwise trigger it
	local sim = Sim.new(o, "Tumble", { control = "player" })
	for _, seg in sim.rig.segments do
		-- still, and high above the course so the slow residual fall never reaches the floor
		local b = seg.body
		b.vx, b.vy, b.w = 0, 0, 0
		b.y += 40
		b.prevY += 40
	end
	local inp = Input.new()
	local N, T, A = Rig.POSES.Neutral, Rig.POSES.Tuck, Rig.POSES.Arch
	local phases = { { 1, 0, T }, { 0, 0, N }, { 0, 1, A }, { 0, 0, N } }
	-- settle in Neutral first
	for _ = 1, 240 do
		Sim.setInput(sim, inp)
		Sim.stepOnce(sim)
	end
	local out = { response = 0, overshoot = 0, wobble = 0, jerk = 0 }
	local jerkSum, jerkN = 0, 0
	local wobbleSum, wobbleN = 0, 0
	local samples = {}
	for _, ph in phases do
		inp.tuck, inp.arch = ph[1], ph[2]
		local target = ph[3]
		local start = Rig.jointAnglesDeg(sim.rig)
		local reached, worstOver = {}, 0
		for i = 1, PHASE_STEPS do
			Sim.setInput(sim, inp)
			Sim.stepOnce(sim)
			local a = Rig.jointAnglesDeg(sim.rig)
			for _, j in JOINTS do
				local change = target[j] - start[j]
				if math.abs(change) > 20 then
					local progress = (a[j] - start[j]) / change
					if not reached[j] and progress >= 0.63 then
						reached[j] = i * H
					end
					worstOver = math.max(worstOver, (progress - 1) * math.abs(change))
				end
				if i * H >= 0.4 then
					wobbleSum += math.abs(a[j] - target[j])
					wobbleN += 1
				end
			end
			if i % FRAME == 0 then
				table.insert(samples, a)
			end
		end
		for _, j in JOINTS do
			if math.abs(target[j] - start[j]) > 20 then
				out.response = math.max(out.response, reached[j] or PHASE_STEPS * H)
			end
		end
		out.overshoot = math.max(out.overshoot, worstOver)
	end
	out.wobble = wobbleSum / wobbleN
	local dt = H * FRAME
	for k = 4, #samples do
		for _, j in JOINTS do
			local d3 = (samples[k][j] - 3 * samples[k - 1][j] + 3 * samples[k - 2][j] - samples[k - 3][j])
				/ (dt * dt * dt)
			jerkSum += d3 * d3
			jerkN += 1
		end
	end
	out.jerk = math.sqrt(jerkSum / jerkN)
	return out
end

local function tuckGain(over)
	local sim = Sim.new(over, "Tumble", { control = "player" })
	local inp = Input.new()
	local s0, best = nil, 0
	for i = 1, 240 * 1.2 do
		inp.tuck = if sim.time >= 0.15 then 1 else 0
		Sim.setInput(sim, inp)
		Sim.stepOnce(sim)
		local ms = Rig.massState(sim.rig)
		local sp = ms.angularMomentum / ms.inertia
		if i == 30 then
			s0 = sp
		end
		if sim.time > 0.45 and sim.controller.mode == "air" then
			best = math.max(best, sp)
		end
	end
	return best / s0
end

local function swingJerk(over)
	local sim = Sim.new(over, "Hang", { control = "player" })
	local inp = Input.new()
	local w1, w2 = 0, 0
	local sum, n = 0, 0
	for i = 1, 240 * 8 do
		local ms = Rig.massState(sim.rig)
		local rising = ms.cx * ms.vx > 0
		inp.tuck = if rising then 1 else 0
		inp.arch = if rising then 0 else 1
		Sim.setInput(sim, inp)
		Sim.stepOnce(sim)
		if i % FRAME == 0 then
			local w = sim.rig.torso.w
			if i > 2 * FRAME then
				local dt = H * FRAME
				local d2 = (w - 2 * w1 + w2) / (dt * dt)
				sum += d2 * d2
				n += 1
			end
			w2, w1 = w1, w
		end
	end
	return math.sqrt(sum / n)
end

local P11 = { motorDampingRatio = 0.8, shapeFreqClose = 30, shapeFreqOpen = 30, gripShoulderHertz = 6 }
local function with(base: { [string]: number }, extra: { [string]: number }): { [string]: number }
	local o = table.clone(base)
	for k, v in extra do
		o[k] = v
	end
	return o
end
local configs = {
	{ "P1.1 exactly", with(P11, { limbInertiaBoost = 0 }) },
	{ "P1.1 + limb inertia boost", P11 },
	{ "  + input smoothing 8/6 Hz", with(P11, { shapeFreqClose = 8, shapeFreqOpen = 6 }) },
	{ "P1.2 defaults (+ motor ζ 1.25, bar shoulder)", {} },
	{ "  ζ 1.0", { motorDampingRatio = 1.0 } },
	{ "  ζ 1.5", { motorDampingRatio = 1.5 } },
	{ "  motor 8 Hz", { motorHertz = 8 } },
	{ "  motor 8 Hz ζ 1.5", { motorHertz = 8, motorDampingRatio = 1.5 } },
	{ "  no input smoothing", { shapeFreqClose = 30, shapeFreqOpen = 30 } },
}

print(
	"config                                        | response s | overshoot ° | wobble ° | jerk °/s³ | tuck gain | swing jerk"
)
for _, c in configs do
	local m = measure(c[2])
	print(
		string.format(
			"%-45s |    %.2f    |    %5.1f    |   %4.1f   |  %7.0f  |   %.2f×   |  %6.0f",
			c[1],
			m.response,
			m.overshoot,
			m.wobble,
			m.jerk,
			tuckGain(c[2]),
			swingJerk(c[2])
		)
	)
end
