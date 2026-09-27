--!strict
-- Movement tests (P1.2): player input -> controller -> physics.
-- Shape control, tuck spin, pumping, Let Go, twist, standing, jumping, landing, moon gravity,
-- input timing (frame rate, slow motion, pause, reset), smoothing, determinism, and a
-- randomized input soak.

return function(T: any)
	local Sim = T.gym("Sim")
	local Rig = T.gym("Rig")
	local Input = T.gym("Input")
	local Solver2D = T.gym("Solver2D")
	local Tuning = T.gym("Tuning")
	local Pose3D = T.gym("Pose3D")
	local Scenarios = T.gym("Scenarios")

	local TAU = 2 * math.pi
	local BAR = Scenarios.BAR_HEIGHT

	local function player(scenario: string, overrides: { [string]: number }?): any
		return Sim.new(overrides, scenario, { control = "player" })
	end

	-- Steps `sim` for `seconds` of simulation time; `each(sim, input)` may edit the input first.
	local function run(sim: any, input: any, seconds: number, each: ((any, any) -> ())?)
		local n = math.floor(seconds / sim.h + 0.5)
		for _ = 1, n do
			if each then
				each(sim, input)
			end
			Sim.setInput(sim, input)
			Sim.stepOnce(sim)
		end
	end

	local function spinRev(sim: any): number
		local ms = Rig.massState(sim.rig)
		return ms.angularMomentum / ms.inertia / TAU
	end

	local function kinetic(rig: any): number
		local e = 0
		for _, seg in rig.segments do
			local b = seg.body
			e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy) + 0.5 * b.inertia * b.w * b.w
		end
		return e
	end

	local function lowestSurface(sim: any): number
		local low = math.huge
		for _, shape in sim.world.bodyShapes do
			low = math.min(low, math.min(shape.ay, shape.by) - shape.radius)
		end
		return low
	end

	local function kinds(events: { any }): string
		local out = {}
		for _, e in events do
			table.insert(out, e.kind)
		end
		return table.concat(out, ",")
	end

	-- A still body high in the air with (almost) no gravity and Earth-strength muscles:
	-- isolates pure shape control.
	local function stillInAir(overrides: { [string]: number }?): any
		local o: { [string]: number } = {
			strengthGravityScaling = 0,
			gravity = 5,
			moonGravity = 1,
			moonGravityScale = 0.05,
			landingReflex = 0,
		}
		for k, v in (overrides or {}) :: { [string]: number } do
			o[k] = v
		end
		local sim = player("Tumble", o)
		for _, seg in sim.rig.segments do
			local b = seg.body
			b.vx, b.vy, b.w = 0, 0, 0
			b.y += 40
			b.prevY += 40
		end
		return sim
	end

	-- Crouch for `hold` seconds and release (a jump). Returns a summary. `opts.arch`: hold Arch
	-- through the release (a back-flip takeoff); `opts.tuckInAir`: tuck from takeoff to landing.
	-- `opts.script(t, release, takeoff, landed)` returns (tuck, arch) after the release instead.
	type JumpOpts = {
		arch: boolean?,
		tuckInAir: boolean?,
		script: ((number, number, number?, boolean) -> (number, number))?,
	}
	local function jump(overrides: { [string]: number }?, hold: number, extra: number?, opts: JumpOpts?): any
		local o: JumpOpts = opts or {}
		local sim = player("Stand", overrides)
		local inp = Input.new()
		local r = {
			sim = sim,
			rise = 0,
			takeoffVX = 0,
			takeoffSpin = 0,
			airtime = 0,
			rotation = 0, -- trunk rotation from takeoff to landing (rev, + = counter-clockwise)
			lowest = math.huge,
			events = "",
			finalMode = "",
			finalCOMY = 0,
		}
		run(sim, inp, 1.0)
		Sim.drainEvents(sim)
		local c = sim.controller
		local y0 = Rig.massState(sim.rig).cy
		local maxY, takeoff, land = y0, nil :: number?, nil :: number?
		local total = 1.0 + hold + (extra or 3)
		local all = {}
		local prevA, turned = sim.rig.torso.a, 0
		run(sim, inp, total - 1.0, function(s, i)
			local release = 1.0 + hold
			i.tuck = if s.time < release then 1 else 0
			i.arch = if o.arch and s.time >= release - 0.05 and takeoff == nil then 1 else 0
			if o.tuckInAir and takeoff and not land then
				i.tuck, i.arch = 1, 0
			end
			if o.script and s.time >= release - 0.1 then
				local tuck, arch = o.script(s.time, release, takeoff, land ~= nil)
				i.tuck = if s.time < release then 1 else tuck
				i.arch = arch
			end
			local a = s.rig.torso.a
			if takeoff and not land then
				turned += (a - prevA + math.pi) % TAU - math.pi
			end
			prevA = a
			local ms = Rig.massState(s.rig)
			if c.mode == "air" and takeoff == nil then
				takeoff = s.time
				r.takeoffVX = ms.vx
				r.takeoffSpin = ms.angularMomentum / ms.inertia / TAU
			end
			if takeoff and not land and c.mode ~= "air" then
				land = s.time
			end
			if takeoff and not land then
				maxY = math.max(maxY, ms.cy)
			end
			r.lowest = math.min(r.lowest, lowestSurface(s))
			for _, e in Sim.drainEvents(s) do
				table.insert(all, e)
			end
		end)
		r.rise = maxY - y0
		r.rotation = turned / TAU
		r.airtime = if takeoff and land then land - takeoff else 0
		r.events = kinds(all)
		r.finalMode = c.mode
		r.finalCOMY = Rig.massState(sim.rig).cy
		return r
	end

	----------------------------------------------------------------------------------------------
	-- Shape control
	----------------------------------------------------------------------------------------------

	T.test("Arch, Tuck and Pike bend the body the intended way (air, bar, and after a half twist)", function()
		local function hold(sim: any, arch: number, tuck: number): { [string]: number }
			local inp = Input.new()
			inp.arch, inp.tuck = arch, tuck
			run(sim, inp, 0.8)
			return Rig.jointAnglesDeg(sim.rig)
		end
		for _, setup in { "air", "bar", "air mirrored" } do
			local function fresh(): any
				local sim = if setup == "bar" then player("Hang") else stillInAir()
				if setup == "air mirrored" then
					Rig.mirror(sim.rig)
				end
				return sim
			end
			local neutral = hold(fresh(), 0, 0)
			local arch = hold(fresh(), 1, 0)
			local tuck = hold(fresh(), 0, 1)
			local pike = hold(fresh(), 1, 1)
			T.note(
				`{setup} hip N/A/T/P`,
				string.format("%.0f/%.0f/%.0f/%.0f", neutral.hip, arch.hip, tuck.hip, pike.hip)
			)
			-- Arch opens the front of the body: shoulders and hips extend past straight.
			-- (On the bar the shoulders turn the whole hanging body; gripShoulderHertz stiffens them.)
			T.note(`{setup} shoulder N/A`, string.format("%.1f/%.1f", neutral.shoulder, arch.shoulder))
			T.below(arch.hip, neutral.hip - 20, `{setup}: arch hip`)
			T.below(arch.shoulder, neutral.shoulder - 15, `{setup}: arch shoulder`)
			-- Tuck closes it: hips and knees fold
			T.above(tuck.hip, neutral.hip + 70, `{setup}: tuck hip`)
			T.above(tuck.knee, neutral.knee + 70, `{setup}: tuck knee`)
			-- in the air the arms wrap in toward the shins (compact); on the bar they stay overhead
			T.note(`{setup} tuck shoulder/elbow`, string.format("%.0f/%.0f", tuck.shoulder, tuck.elbow))
			if setup == "bar" then
				T.below(tuck.shoulder, 45, "bar: the tuck keeps the arms overhead")
			else
				T.above(tuck.shoulder, 70, `{setup}: the air tuck brings the arms in`)
				T.above(tuck.elbow, 30, `{setup}: the air tuck bends the elbows`)
			end
			-- Pike: hips fold with straight knees
			T.above(pike.hip, neutral.hip + 60, `{setup}: pike hip`)
			T.below(pike.knee, 30, `{setup}: pike knee`)
		end
	end)

	T.test("Tuck spins the body faster than an open body; momentum is conserved", function()
		local sim = player("Tumble", { angularDamping = 0 })
		local inp = Input.new()
		run(sim, inp, 0.15)
		local open = spinRev(sim)
		local ms0 = Rig.massState(sim.rig)
		local t0 = sim.time
		local best, worstDrift, early = 0, 0, 0
		run(sim, inp, 0.5, function(s, i)
			i.tuck = 1
			local ms = Rig.massState(s.rig)
			if s.time - t0 <= 0.1 + 1e-9 then
				early = ms.angularMomentum / ms.inertia / TAU
			end
			best = math.max(best, ms.angularMomentum / ms.inertia / TAU)
			worstDrift = math.max(worstDrift, math.abs(ms.angularMomentum / ms0.angularMomentum - 1))
		end)
		local ms1 = Rig.massState(sim.rig)
		local g = Tuning.effectiveGravity(sim.tuning)
		T.note("openSpin(rev/s)", open)
		T.note("tuckedSpin(rev/s)", best)
		T.note("gain", best / open)
		T.note("gain 0.1 s after pressing", early / open)
		T.note("angularMomentumDrift%", worstDrift * 100)
		T.expect(sim.controller.mode == "air", "left the air during the test")
		-- a full, arms-in tuck: ≈2.2× (a real tight tuck from a straight body gives 2.5-3.5×;
		-- the reference clips showed 1.4-1.9×, with partial tucks)
		T.above(best / open, 1.4, "tuck spin gain")
		T.below(best / open, 3, "tuck spin gain (physically plausible)")
		-- responsive: most of the gain within 0.1 s (P1.1 1.48×; P1.2 as first tested 1.17×)
		T.above(early / open, 1.3, "tuck spin gain 0.1 s after pressing")
		T.below(worstDrift, 0.005, "angular momentum drift in flight")
		-- shape changes are internal: the centre of mass keeps its ballistic velocity
		T.near(ms1.vx, ms0.vx, 1e-6, "horizontal velocity")
		T.near(ms1.vy, ms0.vy - g * (sim.time - t0), 1e-6, "vertical velocity")
	end)

	T.test("pumping: Arch/Tuck in phase with the swing builds it, out of phase damps it", function()
		local function pump(policy: string): number
			local sim = player("Hang")
			local inp = Input.new()
			local peak = 0
			run(sim, inp, 15, function(s, i)
				local ms = Rig.massState(s.rig)
				local rising = ms.cx * ms.vx > 0 -- moving away from the bottom
				local closeNow = if policy == "in" then rising elseif policy == "out" then not rising else nil
				if closeNow == nil then
					i.tuck, i.arch = 0, 0
				else
					i.tuck = if closeNow then 1 else 0
					i.arch = if closeNow then 0 else 1
				end
				if s.time > 11 then
					local angle = math.deg(math.atan2(ms.cx, BAR - ms.cy))
					peak = math.max(peak, math.abs(angle))
				end
			end)
			return peak
		end
		local none, inPhase, outPhase = pump("none"), pump("in"), pump("out")
		T.note("peak angle, no input", none)
		T.note("peak angle, in phase", inPhase)
		T.note("peak angle, out of phase", outPhase)
		T.below(none, 60, "no input: the swing only decays")
		T.above(inPhase, none + 30, "in-phase pumping builds the swing")
		T.below(outPhase, none - 15, "out-of-phase pumping damps it")
	end)

	T.test("pumping: held shapes don't drain the swing; from a still hang pumping reaches a giant", function()
		-- swing angle and angular momentum about the grip (the bar is at x = 0)
		local function swingState(s: any): (number, number)
			local ms = Rig.massState(s.rig)
			local L = 0
			for _, seg in s.rig.segments do
				local b = seg.body
				L += b.inertia * b.w + b.mass * (b.x * b.vy - (b.y - BAR) * b.vx)
			end
			return math.atan2(ms.cx, BAR - ms.cy), L
		end
		-- holding a shape from 90°: loss per full cycle (degrees), from half swings 2 to 6 (the
		-- first includes the shape change itself). Soft hips sagged at the bottom of each swing
		-- and sprang back at the top, the reverse of pumping (P1.2 feedback)
		local function heldLoss(arch: number, tuck: number): number
			local sim = player("Hang", { hangStartAngle = 90 })
			local inp = Input.new()
			inp.arch, inp.tuck = arch, tuck
			local peaks, peak, lastSign = {}, 0, 0
			run(sim, inp, 9, function(s)
				local ang, L = swingState(s)
				peak = math.max(peak, math.abs(math.deg(ang)))
				local sign = if L > 0 then 1 else -1
				if lastSign ~= 0 and sign ~= lastSign then
					table.insert(peaks, peak)
					peak = 0
				end
				lastSign = sign
			end)
			return (peaks[2] - peaks[6]) / 2
		end
		local none, tuck, pike = heldLoss(0, 0), heldLoss(0, 1), heldLoss(1, 1)
		T.note(
			"loss per cycle at 90° (deg): relaxed/tuck/pike",
			string.format("%.1f/%.1f/%.1f", none, tuck, pike)
		)
		T.below(tuck - none, 4, "holding Tuck drains the swing")
		T.below(pike - none, 5, "holding Pike drains the swing")

		-- hangStartAngle 0: a still hang
		local still = player("Hang", { hangStartAngle = 0 })
		local stillPeak = 0
		run(still, Input.new(), 3, function(s)
			stillPeak = math.max(stillPeak, math.abs(math.deg((swingState(s)))))
		end)
		T.note("still hang: largest angle in 3 s", stillPeak)
		T.below(stillPeak, 5, "hangStartAngle 0 starts still")

		-- from the still hang, tuck while rising through the lower half and open otherwise:
		-- the swing must keep growing (no plateau short of a giant)
		local sim = player("Hang", { hangStartAngle = 0 })
		local reached90, overTop = nil :: number?, nil :: number?
		run(sim, Input.new(), 20, function(s, i)
			local ang, L = swingState(s)
			local rising = math.cos(ang) > 0 and ang * L > 0
			i.tuck = if rising then 1 else 0
			i.arch = 1 - i.tuck
			if math.abs(ang) > math.rad(90) and reached90 == nil then
				reached90 = s.time
			end
			if math.abs(ang) > math.rad(175) and overTop == nil then
				overTop = s.time
			end
		end)
		T.note("from a still hang: 90° at (s)", reached90 or -1)
		T.note("from a still hang: over the top at (s)", overTop or -1)
		T.expect(
			reached90 ~= nil and (reached90 :: number) < 15,
			"pumping from a still hang passes horizontal"
		)
		T.expect(overTop ~= nil, "pumping from a still hang reaches a giant swing within 20 s")
	end)

	T.test("swing limits: maxSwingSpeed caps the swing's energy; gripFriction removes energy", function()
		-- the cap: at most the energy of the straight body passing the bottom at maxSwingSpeed.
		-- Measured on the rigid swing about the grip, above the straight hang at rest. (A tucked
		-- body with that energy spins faster than maxSwingSpeed, as it should.)
		local function pumped(overrides: { [string]: number }, seconds: number): (number, number)
			local sim = player("Hang", overrides)
			local rig, t = sim.rig, sim.tuning
			local g = Tuning.effectiveGravity(t)
			local capEnergy = 0.5 * rig.hangInertia * t.maxSwingSpeed * t.maxSwingSpeed
			local inp = Input.new()
			local maxRate, worst = 0, 0
			run(sim, inp, seconds, function(s, i)
				local ms = Rig.massState(s.rig)
				local I, L = 0, 0
				for _, seg in s.rig.segments do
					local b = seg.body
					local rx, ry = b.x, b.y - BAR
					I += b.inertia + b.mass * (rx * rx + ry * ry)
					L += b.inertia * b.w + b.mass * (rx * b.vy - ry * b.vx)
				end
				-- pump by the swing angle and direction (works past horizontal and in giants):
				-- tuck while rising through the lower half, open otherwise
				local ang = math.atan2(ms.cx, BAR - ms.cy)
				local rising = math.cos(ang) > 0 and ang * L > 0
				i.tuck = if rising then 1 else 0
				i.arch = if rising then 0 else 1
				maxRate = math.max(maxRate, math.abs(s.controller.swingRate))
				local energy = 0.5 * L * L / I + rig.mass * g * (ms.cy - BAR + rig.hangRadius)
				worst = math.max(worst, energy / capEnergy)
			end)
			return worst, maxRate
		end
		local worst, rate = pumped({ swingAssist = 2, maxSwingSpeed = 6 }, 20)
		T.note("max swing energy / cap, cap 6 rad/s with assist", worst)
		T.note("max swing rate (rad/s)", rate)
		T.below(worst, 1.1, "swing energy above the cap")
		local worst2 = pumped({ maxSwingSpeed = 6 }, 20)
		T.note("max swing energy / cap, cap 6 rad/s, pumping alone", worst2)
		T.below(worst2, 1.1, "swing energy above the cap (pumping alone)")
		local function decay(friction: number): number
			local sim = player("Hang", { gripFriction = friction })
			local peak = 0
			run(sim, Input.new(), 12, function(s)
				if s.time > 8 then
					local ms = Rig.massState(s.rig)
					peak = math.max(peak, math.abs(math.deg(math.atan2(ms.cx, BAR - ms.cy))))
				end
			end)
			return peak
		end
		local low, high = decay(0), decay(0.2)
		T.note("peak after 8 s, gripFriction 0", low)
		T.note("peak after 8 s, gripFriction 0.2", high)
		T.below(high, low - 5, "grip friction should remove swing energy")
	end)

	----------------------------------------------------------------------------------------------
	-- Let Go and twist
	----------------------------------------------------------------------------------------------

	T.test(
		"Let Go keeps momentum exactly (defaults are pure physics); shaping knobs act as specified",
		function()
			local function releaseStep(overrides: { [string]: number }?, at: number?): (any, any, any)
				-- no air damping, so the check is exact: only gravity acts during the release step
				local o: { [string]: number } = { angularDamping = 0 }
				for k, v in (overrides or {}) :: { [string]: number } do
					o[k] = v
				end
				local sim = player("Hang", o)
				local inp = Input.new()
				run(sim, inp, at or 0.9)
				local before = Rig.massState(sim.rig)
				inp.letGoPresses += 1
				Sim.setInput(sim, inp)
				Sim.stepOnce(sim)
				return sim, before, Rig.massState(sim.rig)
			end
			local worstL = 0
			for _, at in { 0.5, 0.7, 0.9, 1.1, 1.3 } do
				local sim, b, a = releaseStep(nil, at)
				local g = Tuning.effectiveGravity(sim.tuning)
				if at == 0.9 then
					T.expect(
						sim.grip == nil and sim.controller.mode == "air",
						"should be released and airborne"
					)
					T.expect(kinds(Sim.drainEvents(sim)) == "release", "exactly one release event")
					T.note("releaseSpeed", math.sqrt(b.vx * b.vx + b.vy * b.vy))
				end
				-- the release step changes momentum only by gravity (and nothing about the centre of mass)
				T.near(a.vx, b.vx, 1e-9, "horizontal velocity at release")
				T.near(a.vy, b.vy - g * sim.h, 1e-9, "vertical velocity at release")
				-- internal joint impulses conserve angular momentum up to the solver's joint error:
				-- ~1e-8 per ordinary step, ~1e-6 on the release step, when the arm joints suddenly
				-- stop carrying the body (P1.2 feedback: 1e-6 was met only at some release times).
				-- Any release shaping would show at the 1e-1 level.
				worstL = math.max(
					worstL,
					math.abs(a.angularMomentum - b.angularMomentum) / math.abs(b.angularMomentum)
				)
			end
			T.note("worst relative angular momentum change at release", worstL)
			T.below(worstL, 1e-5, "angular momentum at release")
			local sim = player("Hang")
			local g = Tuning.effectiveGravity(sim.tuning)
			-- shaping (opt-in): velocity scale, upward pop and spin scale about the centre of mass
			local _, b2, a2 =
				releaseStep({ releaseVelocityScale = 1.2, releasePop = 5, releaseSpinScale = 1.5 })
			T.near(a2.vx, 1.2 * b2.vx, 1e-6, "scaled horizontal velocity")
			T.near(a2.vy, 1.2 * b2.vy + 5 - g * sim.h, 1e-6, "scaled vertical velocity plus pop")
			T.near(
				a2.angularMomentum,
				1.5 * b2.angularMomentum,
				1e-3 * math.abs(b2.angularMomentum),
				"scaled spin"
			)
			-- Let Go does nothing when not gripping; Grab does nothing in P1.2
			local air, twin = player("Tumble"), player("Tumble")
			local inp = Input.new()
			run(air, inp, 0.1)
			run(twin, Input.new(), 0.1)
			inp.letGoPresses += 3
			inp.grabPresses += 2
			run(air, inp, 0.5)
			run(twin, Input.new(), 0.5)
			T.expect(Sim.checksum(air) == Sim.checksum(twin), "presses without effect changed the motion")
		end
	)

	T.test(
		"Rig.mirror (half twist) conserves centre of mass, momentum, angular momentum and energy exactly",
		function()
			local sim = player("Tumble")
			local inp = Input.new()
			inp.tuck = 1
			run(sim, inp, 0.12) -- spinning and mid-shape-change: a demanding state
			local rig = sim.rig
			local b = Rig.massState(rig)
			local keB, anglesB = kinetic(rig), Rig.jointAnglesDeg(rig)
			Rig.mirror(rig)
			local a = Rig.massState(rig)
			local keA, anglesA = kinetic(rig), Rig.jointAnglesDeg(rig)
			T.near(a.cx, b.cx, 1e-9, "com x")
			T.near(a.cy, b.cy, 1e-9, "com y")
			T.near(a.vx, b.vx, 1e-9, "momentum x")
			T.near(a.vy, b.vy, 1e-9, "momentum y")
			T.near(
				a.angularMomentum,
				b.angularMomentum,
				1e-9 * math.abs(b.angularMomentum),
				"angular momentum"
			)
			T.near(keA, keB, 1e-9 * keB, "kinetic energy")
			T.expect(rig.facing == -1, "facing should flip")
			for name, v in anglesB do
				T.near(anglesA[name], v, 1e-6, `anatomical {name} angle`)
			end
			for _, rj in rig.joints do
				local j = rj.joint
				local ax, ay = Solver2D.worldPoint(j.bodyA, j.lax, j.lay)
				local bx, by = Solver2D.worldPoint(j.bodyB, j.lbx, j.lby)
				T.below(math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2), 0.02, `{rj.name} joint gap`)
			end
			-- the body carries on normally in the mirrored facing
			run(sim, inp, 1)
			for _, e in Sim.drainEvents(sim) do
				T.expect(e.kind ~= "invalid", "invalid state after mirroring")
			end
		end
	)

	T.test(
		"Twist turns the body about its long axis: stays planar, momentum kept, continuous on screen",
		function()
			local sim = player("Tumble", { angularDamping = 0 })
			local inp = Input.new()
			local c = sim.controller
			local PAIR = 0.32
			local snaps, worstJump, worstL = 0, 0, 0
			local L0 = Rig.massState(sim.rig).angularMomentum
			local prevPoints: { any }? = nil
			local steps = math.floor(0.7 / sim.h)
			for _ = 1, steps do
				inp.twistRight = sim.time < 0.5
				Sim.setInput(sim, inp)
				local halfBefore = c.halfTwists
				Sim.stepOnce(sim)
				-- rendered points at the start of this step (alpha 0) must equal those drawn at
				-- the end of the previous step (alpha 1), including across a mirror snap
				local f0 = Pose3D.frame(sim.rig, Sim.renderTwist(sim, 0), 0, Sim.bodyPose)
				local now = Pose3D.points(sim.rig, f0, 0, PAIR, Sim.bodyPose)
				if prevPoints then
					for i, p in now do
						-- paired limbs may trade sides at a snap: compare against the same point on either side
						local best = math.huge
						for _, q in prevPoints :: { any } do
							if q.name == p.name then
								best = math.min(
									best,
									math.sqrt((p.u - q.u) ^ 2 + (p.v - q.v) ^ 2 + (p.z - q.z) ^ 2)
								)
							end
						end
						worstJump = math.max(worstJump, best)
					end
				end
				local f1 = Pose3D.frame(sim.rig, Sim.renderTwist(sim, 1), 1, Sim.bodyPose)
				prevPoints = Pose3D.points(sim.rig, f1, 1, PAIR, Sim.bodyPose)
				if c.halfTwists > halfBefore then
					snaps += 1
				end
				worstL = math.max(worstL, math.abs(Rig.massState(sim.rig).angularMomentum / L0 - 1))
				-- the simulation itself stays planar and finite
				T.expect(not Solver2D.hasInvalidState(sim.world), "invalid state while twisting")
			end
			T.note("halfTwists", snaps)
			T.note("psiAtEnd(deg)", math.deg(c.psi))
			T.note("worstRenderJump(studs)", worstJump)
			T.note("angularMomentumDrift%", worstL * 100)
			T.above(snaps, 1, "twist should complete at least one half twist in 0.5 s")
			T.below(worstJump, 1e-6, "rendered body jumps on screen")
			T.below(worstL, 1e-3, "angular momentum changed by twisting")
			-- after release (hold mode) the twist stops and holds its angle
			T.near(c.psiRate, 0, 1e-9, "twist rate after release")
			local held = c.psi
			run(sim, inp, 0.2)
			T.near(c.psi, held, 1e-9, "twist angle held")
		end
	)

	T.test("twist modes: hold (both buttons hold the angle) and momentum (tap, reverse, stop)", function()
		-- hold mode: both held = no spin
		local sim = player("Tumble")
		local inp = Input.new()
		inp.twistLeft, inp.twistRight = true, true
		run(sim, inp, 0.3)
		T.near(sim.controller.psi, 0, 1e-9, "both held should not twist")
		-- momentum mode: a tap starts a spin that continues
		sim = player("Tumble", { twistMode = 1 })
		inp = Input.new()
		local c = sim.controller
		inp.twistRightPresses += 1
		run(sim, inp, 0.3)
		T.above(c.psiRate, 0.9 * sim.tuning.twistRate * TAU, "tap should start a right twist")
		inp.twistLeftPresses += 1
		run(sim, inp, 0.3)
		T.below(c.psiRate, -0.9 * sim.tuning.twistRate * TAU, "opposite tap should reverse it")
		inp.twistLeft, inp.twistRight = true, true
		run(sim, inp, 0.3)
		T.near(c.psiRate, 0, 1e-9, "both held should stop it")
		-- no twisting while gripping
		local bar = player("Hang")
		inp = Input.new()
		inp.twistRight = true
		run(bar, inp, 0.5)
		T.near(bar.controller.psi, 0, 1e-9, "twist while gripping")
	end)

	----------------------------------------------------------------------------------------------
	-- Ground
	----------------------------------------------------------------------------------------------

	T.test(
		"standing: holds still for 10 s, recovers from shoves, and stands on muscle alone when undisturbed",
		function()
			local sim = player("Stand")
			run(sim, Input.new(), 10)
			local c = sim.controller
			local ms = Rig.massState(sim.rig)
			T.note("offsetFromFeet", ms.cx - c.supportX)
			T.expect(c.mode == "ground", `mode {c.mode}`)
			T.expect(kinds(Sim.drainEvents(sim)) == "landing", "only the initial settle event")
			T.below(math.abs(ms.cx - c.supportX), 0.05, "centre of mass over the feet")
			T.below(math.sqrt(ms.vx ^ 2 + ms.vy ^ 2), 0.02, "standing still")
			for _, kick in { -3, 3 } do
				local s = player("Stand")
				run(s, Input.new(), 1)
				for _, seg in s.rig.segments do
					seg.body.vx += kick
				end
				run(s, Input.new(), 4)
				local m = Rig.massState(s.rig)
				T.expect(s.controller.mode == "ground", `shove {kick}: mode {s.controller.mode}`)
				T.below(math.abs(m.vx), 0.05, `shove {kick}: settled`)
			end
			local pure = player("Stand", { balanceAssist = 0 })
			run(pure, Input.new(), 10)
			T.expect(pure.controller.mode == "ground", "pure muscle standing fell")
		end
	)

	T.test(
		"jump: releasing Tuck from a crouch pushes straight up, lands on the feet and stands again",
		function()
			for _, hold in { 0.3, 0.8 } do
				local r = jump(nil, hold)
				T.note(`hold {hold}s rise`, r.rise)
				T.note(`hold {hold}s airtime`, r.airtime)
				T.note(`hold {hold}s takeoff spin (rev/s)`, r.takeoffSpin)
				T.note(`hold {hold}s takeoff vx`, r.takeoffVX)
				T.note(`hold {hold}s events`, r.events)
				T.expect(r.events == "push,takeoff,landing", `events: {r.events}`)
				T.above(r.rise, 1.0, "jump height")
				T.below(r.rise, 2.5, "jump height")
				T.below(math.abs(r.takeoffSpin), 0.2, "takeoff spin")
				T.below(math.abs(r.takeoffVX), 2, "takeoff drift")
				T.expect(r.finalMode == "ground", `ended {r.finalMode}`)
				T.above(r.finalCOMY, 2.5, "back up to standing height")
				T.above(r.lowest, -0.1, "body went into the floor")
			end
			-- a quick tap only dips: no push
			local tap = jump(nil, 0.08, 1.5)
			T.expect(not string.find(tap.events, "push"), `a tap should not jump: {tap.events}`)
		end
	)

	T.test("back-flip takeoff: Arch through the push spins backward without losing height", function()
		local plain = jump(nil, 0.6)
		local back = plain.sim.rig.facing -- backward spin is counter-clockwise when facing +x
		-- the feet alone (pure physics, jumpSpinAssist 0): full height, about half the spin a
		-- standing back flip needs. In the air, Arch can't create rotation.
		local feet = jump({ jumpSpinAssist = 0 }, 0.6, 3, { arch = true, tuckInAir = true })
		T.note("plain rise / arch rise", string.format("%.2f / %.2f", plain.rise, feet.rise))
		T.note("feet-only takeoff spin (rev/s, + = backward)", back * feet.takeoffSpin)
		T.note("feet-only rotation with a tuck (rev)", back * feet.rotation)
		-- pinned at the toe edge, the ankles tipped the body onto its toes and the knees stopped
		-- extending: the Arch jump lost a third of its height (P1.2 feedback)
		T.above(feet.rise, 0.85 * plain.rise, "an Arch takeoff keeps the jump height")
		T.above(back * feet.takeoffSpin, 0.3, "backward takeoff spin from the feet")
		-- default: the takeoff spin assist tops the takeoff up to jumpArchSpin (P1.2 round 2)
		local flip = jump(nil, 0.6, 3, { arch = true, tuckInAir = true })
		T.note(
			"default: rotation (rev) / rise / end",
			string.format("%.2f / %.2f / %s", back * flip.rotation, flip.rise, flip.finalMode)
		)
		T.above(back * flip.rotation, 0.75, "Arch takeoff + tuck: a standing back flip's rotation")
		T.above(flip.rise, 0.85 * plain.rise, "the takeoff spin keeps the jump height")
		-- players press A a moment after letting go of S: up to just after takeoff still counts
		local function lateArch(at: number): any
			return jump(nil, 0.6, 3, {
				script = function(
					t: number,
					release: number,
					takeoff: number?,
					landed: boolean
				): (number, number)
					if landed then
						return 0, 0
					end
					if takeoff and t >= takeoff + 0.15 then
						return 1, 0 -- tuck
					end
					return 0, if t >= release + at then 1 else 0
				end,
			})
		end
		local late = lateArch(0.2)
		local midAir = lateArch(0.5)
		T.note(
			"A pressed 0.2 s / 0.5 s after releasing S: rotation (rev)",
			string.format("%.2f / %.2f", back * late.rotation, back * midAir.rotation)
		)
		T.above(back * late.rotation, 0.7, "a slightly late Arch still makes a back flip")
		T.below(math.abs(midAir.rotation), 0.2, "Arch pressed mid-flight creates no rotation")
		-- landable: some timings of the tuck land the flip on the feet (pure physics: none)
		local landed, tries = 0, 0
		for _, delay in { 0.05, 0.1, 0.15 } do
			for _, tuckFor in { 0.3, 0.4, 0.5, 0.6, 0.7 } do
				local r = jump(nil, 0.6, 3, {
					script = function(
						t: number,
						release: number,
						takeoff: number?,
						landed: boolean
					): (number, number)
						if landed or t < release - 0.05 then
							return 0, 0
						end
						if takeoff and t >= takeoff + delay then
							return if t < takeoff + delay + tuckFor then 1 else 0, 0
						end
						return 0, 1
					end,
				})
				tries += 1
				if r.finalMode == "ground" and back * r.rotation >= 0.75 then
					landed += 1
				end
			end
		end
		T.note("back flips landed on the feet (tuck delay x tuck time grid)", `{landed}/{tries}`)
		T.above(landed, 1, "some back-flip timings land on the feet")
		-- plain jumps are untouched by the takeoff spin
		T.below(math.abs(plain.takeoffSpin), 0.2, "plain jump takeoff spin")
		T.expect(plain.finalMode == "ground", `plain jump ended {plain.finalMode}`)
	end)

	T.test("plain jumps land standing while holding Arch (Earth and moon)", function()
		-- round 1 narrowed the push's centre of pressure for every jump, not just the Arch push;
		-- plain jumps then took off slightly differently and landings holding Arch fell (P1.2 round 2).
		-- Arch pressed from `after` s past takeoff and held to landing.
		local function archLanding(o: { [string]: number }, hold: number, after: number): any
			return jump(o, hold, 4, {
				script = function(
					t: number,
					_release: number,
					takeoff: number?,
					landed: boolean
				): (number, number)
					return 0, if takeoff and t >= takeoff + after and not landed then 1 else 0
				end,
			})
		end
		-- the push and landing themselves (takeoff spin off: Arch at takeoff would start a back flip)
		for _, hold in { 0.35, 0.5, 0.7 } do
			local r = archLanding({ jumpSpinAssist = 0 }, hold, 0)
			T.expect(
				r.finalMode == "ground",
				`Earth, crouch {hold} s, Arch from takeoff: ended {r.finalMode}`
			)
		end
		for _, hold in { 0.35, 0.7 } do
			local r = archLanding({ jumpSpinAssist = 0, moonGravity = 1 }, hold * 2.46, 0)
			T.expect(
				r.finalMode == "ground",
				`moon, crouch {hold * 2.46} s, Arch from takeoff: ended {r.finalMode}`
			)
		end
		-- defaults: Arch pressed after the late back-flip window is just a shape change. (Arch
		-- pressed ~0.25 s in lands on the legs mid-swing and falls, in the playtested build too:
		-- a landing-reflex limit, PLAYTEST_P1_2.md round 2.)
		for _, after in { 0.2, 0.35 } do
			for _, hold in { 0.35, 0.5, 0.7 } do
				local r = archLanding({}, hold, after)
				T.expect(
					r.finalMode == "ground",
					`Earth, crouch {hold} s, Arch {after} s after takeoff: ended {r.finalMode}`
				)
				T.below(math.abs(r.rotation), 0.2, "Arch pressed mid-flight creates no rotation")
			end
		end
	end)

	T.test("ground/air transitions: no flicker standing, landing from a drop, or holding a crouch", function()
		-- lift a standing body 2 studs and let it drop onto its feet
		local sim = player("Stand")
		for _, seg in sim.rig.segments do
			seg.body.y += 2
			seg.body.prevY += 2
		end
		local inp = Input.new()
		local lowest = math.huge
		run(sim, inp, 4, function(s)
			lowest = math.min(lowest, lowestSurface(s))
		end)
		local ev = kinds(Sim.drainEvents(sim))
		T.note("drop events", ev)
		T.expect(ev == "landing", `drop: {ev}`)
		T.expect(sim.controller.mode == "ground", "drop should end standing")
		T.above(lowest, -0.1, "went into the floor on landing")
		-- a held crouch stays grounded
		run(sim, inp, 3, function(_, i)
			i.tuck = 1
		end)
		T.expect(#Sim.drainEvents(sim) == 0, "events while holding a crouch")
		T.expect(sim.controller.mode == "ground", "crouch left the ground")
	end)

	----------------------------------------------------------------------------------------------
	-- Timing, determinism, moon
	----------------------------------------------------------------------------------------------

	T.test(
		"jumping is identical at any frame rate (fixed step), and nearly so with per-frame input sampling",
		function()
			-- (a) input keyed to simulation time: bit-identical results for any frame timing
			local function byFrames(nextDt: () -> number, sampleByFrame: boolean): (string, number)
				local sim = player("Stand")
				local inp = Input.new()
				local maxY = 0
				local checksum = ""
				local target = math.floor(4.0 / sim.h)
				if not sampleByFrame then
					sim.onStep = function(s)
						if s.stepCount == target then
							checksum = Sim.checksum(s)
						end
					end
				end
				local realTime = 0
				while sim.stepCount < target do
					local dt = nextDt()
					realTime += dt
					-- (a) the scripted input is a function of simulation time at every step;
					-- (b) it is sampled once per frame from real time, as a device does
					if sampleByFrame then
						inp.tuck = if realTime >= 1.0 and realTime < 1.5 then 1 else 0
						Sim.setInput(sim, inp)
						Sim.advance(sim, dt)
					else
						local steps = 0
						sim.acc += dt
						while sim.acc >= sim.h and steps < 64 do
							sim.acc -= sim.h
							inp.tuck = if sim.time >= 1.0 and sim.time < 1.5 then 1 else 0
							Sim.setInput(sim, inp)
							Sim.stepOnce(sim)
							steps += 1
						end
					end
					maxY = math.max(maxY, Rig.massState(sim.rig).cy)
				end
				return checksum, maxY
			end
			local function fixed(fps: number): () -> number
				return function(): number
					return 1 / fps
				end
			end
			local function jittery(): () -> number
				local k = 0
				return function(): number
					k += 1
					return if k % 3 == 0 then 1 / 30 elseif k % 3 == 1 then 1 / 144 else 1 / 60
				end
			end
			local ref = byFrames(fixed(240), false)
			for _, gen in { fixed(30), fixed(60), fixed(144), jittery() } do
				local cs = byFrames(gen, false)
				T.expect(cs == ref, "jump differs with frame timing (sim-time input)")
			end
			-- (b) per-frame sampling: the release is quantized to a frame, so heights may differ slightly
			local _, apex240 = byFrames(fixed(240), true)
			for _, fps in { 30, 60, 144 } do
				local _, apex = byFrames(fixed(fps), true)
				T.note(`apex {fps} fps vs 240`, apex - apex240)
				T.below(math.abs(apex - apex240), 0.03 * apex240, `apex at {fps} fps`)
			end
		end
	)

	T.test(
		"presses are never lost or doubled: slow motion zero-step frames, several per frame, pause, reset",
		function()
			-- slow motion at 240 fps: three of every four frames run no simulation step
			local sim = player("Hang", { timeScale = 0.25 })
			local inp = Input.new()
			for _ = 1, 40 do
				Sim.setInput(sim, inp)
				Sim.advance(sim, 1 / 240)
			end
			-- find a frame that will run zero steps, press there
			local pressedOnZeroStepFrame = false
			for _ = 1, 8 do
				if sim.acc + 0.25 / 240 < sim.h then
					inp.letGoPresses += 1
					Sim.setInput(sim, inp)
					local steps = Sim.advance(sim, 1 / 240)
					T.expect(steps == 0, "expected a zero-step frame")
					pressedOnZeroStepFrame = true
					break
				end
				Sim.setInput(sim, inp)
				Sim.advance(sim, 1 / 240)
			end
			T.expect(pressedOnZeroStepFrame, "no zero-step frame found")
			T.expect(sim.grip ~= nil, "released before any step ran")
			local frames = 0
			while sim.grip ~= nil and frames < 10 do
				Sim.setInput(sim, inp)
				Sim.advance(sim, 1 / 240)
				frames += 1
			end
			T.expect(sim.grip == nil, "press on a zero-step frame was lost")
			T.expect(kinds(Sim.drainEvents(sim)) == "release", "release should happen exactly once")
			-- two presses within one frame still release once (and nothing else)
			local s2 = player("Hang")
			local i2 = Input.new()
			i2.letGoPresses += 2
			Sim.setInput(s2, i2)
			Sim.advance(s2, 1 / 30)
			T.expect(kinds(Sim.drainEvents(s2)) == "release", "double press")
			-- pressed while paused: applied on the first step after unpausing
			local s3 = player("Hang")
			local i3 = Input.new()
			s3.paused = true
			i3.letGoPresses += 1
			Sim.setInput(s3, i3)
			Sim.advance(s3, 1 / 60)
			T.expect(s3.grip ~= nil, "paused simulation released")
			s3.paused = false
			Sim.advance(s3, 1 / 60)
			T.expect(s3.grip == nil, "press made during pause was lost")
			-- a press made before a reset does not fire after it
			local s4 = player("Hang")
			local i4 = Input.new()
			i4.letGoPresses += 1
			Sim.setInput(s4, i4)
			Sim.reset(s4)
			Sim.advance(s4, 1 / 30)
			T.expect(s4.grip ~= nil, "stale press fired after reset")
			-- non-finite analog input is sanitized
			local s5 = player("Tumble")
			local i5 = Input.new()
			i5.tuck = 0 / 0
			i5.arch = math.huge
			Sim.setInput(s5, i5)
			T.expect(s5.input.tuck == 0 and s5.input.arch == 1, "input levels not sanitized")
		end
	)

	T.test("determinism: the same inputs give bit-identical results", function()
		local function script(): string
			local sim = player("Stand")
			local inp = Input.new()
			run(sim, inp, 4, function(s, i)
				local t = s.time
				i.tuck = if t > 0.5 and t < 1.0 then 1 else 0
				i.twistRight = t > 1.3 and t < 1.5
				i.arch = if t > 1.6 and t < 1.7 then 1 else 0
			end)
			return Sim.checksum(sim)
		end
		T.expect(script() == script(), "same input script gave different results")
	end)

	-- Moon gravity and slow motion were the playtester's favourite features (PLAYTEST_P1_2.md).
	-- These two tests guard their behaviour while the movement is tuned: changing it must be a
	-- deliberate decision, not a side effect.
	T.test(
		"slow motion keeps player movement identical: bar and ground, Earth and moon, 0.5 / 0.25 / 0.1",
		function()
			-- a scripted routine keyed to simulation time, run through Sim.advance at 60 fps
			local function routine(s: any, i: any)
				local t = s.time
				if s.scenario == "Hang" then
					local ms = Rig.massState(s.rig)
					local rising = ms.cx * ms.vx > 0
					if t < 3 then
						i.tuck = if rising then 1 else 0
						i.arch = 1 - i.tuck
					else
						if i.letGoPresses == 0 and rising then
							i.letGoPresses = 1
						end
						i.tuck, i.arch = if t < 3.6 then 1 else 0, 0
						i.twistRight = t > 3.3 and t < 3.8
					end
				else
					i.tuck = if t > 1 and t < 1.6 then 1 else 0
					i.arch = if t > 1.55 and t < 1.8 then 1 else 0
				end
			end
			local function play(scene: string, moon: number, scale: number): (string, number)
				local sim = player(scene, { moonGravity = moon, timeScale = scale })
				local inp = Input.new()
				local target = math.floor(5 / sim.h + 0.5)
				local sum = ""
				routine(sim, inp)
				Sim.setInput(sim, inp)
				sim.onStep = function(s)
					if s.stepCount == target then
						sum = Sim.checksum(s)
					end
					routine(s, inp)
					Sim.setInput(s, inp)
				end
				local frames = 0
				while sim.stepCount < target do
					Sim.advance(sim, 1 / 60)
					frames += 1
				end
				return sum, frames
			end
			for _, scene in { "Hang", "Stand" } do
				for _, moon in { 0, 1 } do
					local ref, refFrames = play(scene, moon, 1)
					for _, scale in { 0.5, 0.25, 0.1 } do
						local sum, frames = play(scene, moon, scale)
						local label = `{scene} moon={moon} timeScale {scale}`
						T.expect(sum == ref, `slow motion changed the movement: {label}`)
						T.near(frames / refFrames, 1 / scale, 0.02 / scale, `real time: {label}`)
					end
				end
			end
		end
	)

	T.test(
		"moon mode keeps its feel: same swing and jump, about 2.46× slower; settings survive Reset",
		function()
			-- defaults the feature is made of
			local d = Tuning.new()
			T.expect(d.moonGravity == 0 and d.moonGravityScale == 0.165, "moon defaults")
			T.expect(
				d.strengthGravityScaling == 1 and d.timeScale == 1,
				"strength follows gravity; normal speed"
			)
			-- the hanging swing: the same swing, played √(1/0.165) ≈ 2.46× slower
			local function passiveSwing(moon: number): (number, number)
				local sim = player("Hang", { moonGravity = moon })
				local inp = Input.new()
				local peaks, peak, last, crossings, t0, t3 = {}, 0, 0, 0, 0, 0
				while #peaks < 8 do
					Sim.setInput(sim, inp)
					Sim.stepOnce(sim)
					local ms = Rig.massState(sim.rig)
					peak = math.max(peak, math.abs(math.deg(math.atan2(ms.cx, BAR - ms.cy))))
					local sign = if ms.vx > 0 then 1 else -1
					if last ~= 0 and sign ~= last then
						crossings += 1
						table.insert(peaks, peak)
						peak = 0
						if crossings == 1 then
							t0 = sim.time
						elseif crossings == 4 then
							t3 = sim.time
						end
					end
					last = sign
				end
				return (t3 - t0) / 3, peaks[8]
			end
			local ePeriod, ePeak = passiveSwing(0)
			local mPeriod, mPeak = passiveSwing(1)
			T.note("half swing Earth / moon (s)", string.format("%.2f / %.2f", ePeriod, mPeriod))
			T.note("peak after 8 half swings Earth / moon", string.format("%.1f° / %.1f°", ePeak, mPeak))
			T.near(mPeriod / ePeriod, math.sqrt(1 / 0.165), 0.08, "moon swing period ratio")
			T.near(mPeak, ePeak, 3, "moon swing keeps its height (same decay per swing)")
			-- the jump: about the same height, much longer in the air, lands standing
			local e = jump(nil, 0.6)
			local m = jump({ moonGravity = 1 }, 1.4, 4)
			T.note("jump rise ratio moon/Earth", m.rise / e.rise)
			T.note("jump airtime ratio moon/Earth", m.airtime / e.airtime)
			T.near(m.rise / e.rise, 1.14, 0.12, "moon jump height (as playtested: 1.14× Earth)")
			T.near(m.airtime / e.airtime, 2.75, 0.3, "moon jump airtime (as playtested: ≈2.7× Earth)")
			T.expect(m.finalMode == "ground", `moon jump should land standing: {m.events}`)
			-- live settings survive Reset and scene changes (moon, slow motion, the blind A/B's motor)
			local sim = player("Hang")
			Sim.setParam(sim, "moonGravity", 1)
			Sim.setParam(sim, "timeScale", 0.25)
			Sim.setParam(sim, "motorHertz", 8)
			Sim.reset(sim)
			Sim.reset(sim, "Stand")
			T.expect(Tuning.effectiveGravity(sim.tuning) == 35 * 0.165, "moon kept after Reset")
			T.expect(sim.tuning.timeScale == 0.25, "slow motion kept after Reset")
			T.expect(sim.tuning.motorHertz == 8, "motor setting kept after Reset")
			T.expect(sim.world.params.gravityY == -35 * 0.165, "the rebuilt world uses moon gravity")
		end
	)

	T.test(
		"moon gravity: exact multiplier; ballistic heights ×6.06; muscle jumps follow strengthGravityScaling",
		function()
			local earth, moon = Tuning.new(), Tuning.new({ moonGravity = 1 })
			T.near(Tuning.effectiveGravity(moon), 35 * 0.165, 1e-12, "moon gravity")
			-- fixed launch (the Tumble scene): apex height scales exactly with 1/g
			local function apex(o: { [string]: number }): number
				local sim = Sim.new(o, "Tumble")
				local y0 = Rig.massState(sim.rig).cy
				local best = y0
				for _ = 1, 240 * 8 do
					Sim.stepOnce(sim)
					local ms = Rig.massState(sim.rig)
					best = math.max(best, ms.cy)
					if ms.vy < 0 then
						break
					end
				end
				return best - y0
			end
			local ratio = apex({ moonGravity = 1 }) / apex({})
			T.note("ballistic apex ratio moon/earth", ratio)
			T.near(ratio, 1 / 0.165, 0.02 / 0.165, "ballistic apex ratio")
			T.expect(Tuning.effectiveGravity(earth) == 35, "earth gravity")
			-- muscle jump: strength follows gravity (default) = same height, ~sqrt(6) longer airtime
			local e = jump(nil, 0.6)
			local m1 = jump({ moonGravity = 1 }, 1.4, 4)
			local m0 = jump({ moonGravity = 1, strengthGravityScaling = 0 }, 1.4, 6)
			T.note("earth rise/airtime", string.format("%.2f / %.2f", e.rise, e.airtime))
			T.note(
				"moon (strength follows g) rise/airtime",
				string.format("%.2f / %.2f", m1.rise, m1.airtime)
			)
			T.note("moon (fixed strength) rise/airtime", string.format("%.2f / %.2f", m0.rise, m0.airtime))
			T.above(m1.rise / e.rise, 0.7, "moon jump height (strength follows g)")
			T.below(m1.rise / e.rise, 1.4, "moon jump height (strength follows g)")
			T.above(m1.airtime / e.airtime, 2.0, "moon airtime ratio (√6.06 ≈ 2.46)")
			T.below(m1.airtime / e.airtime, 3.0, "moon airtime ratio (√6.06 ≈ 2.46)")
			T.above(m0.rise / e.rise, 3, "moon jump height (fixed strength)")
			T.expect(m1.finalMode == "ground", `moon jump should land standing: {m1.events}`)
		end
	)

	T.test("smoothing: motor targets move continuously when an input switches (no snaps)", function()
		local function worstTargetStep(overrides: { [string]: number }?): number
			local sim = stillInAir(overrides)
			local inp = Input.new()
			run(sim, inp, 0.5)
			local c = sim.controller
			local worst = 0
			for _, phase in { { 1, 0 }, { 0, 0 }, { 0, 1 }, { 0, 0 } } do
				inp.tuck, inp.arch = phase[1], phase[2]
				local prev = table.clone(c.targets)
				run(sim, inp, 0.6, function(s)
					for name, v in s.controller.targets do
						worst = math.max(worst, math.abs(v - prev[name]))
						prev[name] = v
					end
				end)
			end
			return worst
		end
		local smooth = worstTargetStep(nil)
		local raw = worstTargetStep({ shapeFreqClose = 30, shapeFreqOpen = 30 })
		T.note("worst target change per step (default)", smooth)
		T.note("worst target change per step (30 Hz, ~P1.1)", raw)
		T.below(smooth, 12, "target snaps with default smoothing")
		T.above(raw, 2 * smooth, "smoothing should be doing the work")
	end)

	----------------------------------------------------------------------------------------------
	-- Soak
	----------------------------------------------------------------------------------------------

	T.test(
		"player-input soak: random inputs and resets across all scenes and both gravities never break the body",
		function()
			local function lcg(seed: number): () -> number
				local state = seed
				return function(): number
					state = (state * 1103515245 + 12345) % 2147483648
					return state / 2147483648
				end
			end
			local FLOOR_HALF_WIDTH = 80
			local report = {}
			for _, moon in { 0, 1 } do
				for _, scenario in { "Hang", "Wheel", "Stand", "Tumble", "Drop" } do
					local sim = player(scenario, { moonGravity = moon })
					local rnd = lcg(#scenario * 97 + moon * 13 + 5)
					local inp = Input.new()
					local worstJoint, worstLimit, pen = 0, 0, 0
					local nextChange = 0
					run(sim, inp, 40, function(s, i)
						if s.time >= nextChange then
							nextChange = s.time + 0.05 + rnd() * 0.5
							i.arch = if rnd() < 0.35 then 1 else 0
							i.tuck = if rnd() < 0.35 then 1 else 0
							i.twistLeft = rnd() < 0.15
							i.twistRight = rnd() < 0.15
							if rnd() < 0.1 then
								i.letGoPresses += 1
							end
							if rnd() < 0.1 then
								i.twistRightPresses += 1
							end
							if rnd() < 0.03 then
								Sim.reset(s)
							end
						end
						for _, rj in s.rig.joints do
							worstJoint = math.max(worstJoint, rj.joint.error)
							local lim = Rig.LIMITS[rj.name]
							local a = math.deg(Rig.jointAngle(rj, s.rig.facing))
							worstLimit = math.max(worstLimit, lim[1] - a, a - lim[2])
						end
						for _, shape in s.world.bodyShapes do
							if math.abs((shape.ax + shape.bx) / 2) < FLOOR_HALF_WIDTH - 1 then
								pen = math.max(pen, -(math.min(shape.ay, shape.by) - shape.radius))
							end
						end
					end)
					local label = `moon={moon} {scenario}`
					for _, e in Sim.drainEvents(sim) do
						T.expect(e.kind ~= "invalid" and e.kind ~= "outOfBounds", `{e.kind}: {label}`)
					end
					T.below(worstJoint, 0.05, `joint separation: {label}`)
					T.below(worstLimit, 8, `limit violation: {label}`)
					T.below(pen, 0.3, `floor penetration: {label}`)
					table.insert(
						report,
						string.format("%s j=%.3f lim=%.1f pen=%.2f", label, worstJoint, worstLimit, pen)
					)
				end
			end
			for _, line in report do
				T.note("run", line)
			end
		end,
		{ slow = true }
	)
end
