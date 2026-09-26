--!strict
-- Sim/driver and scenario integration tests: frame-rate independence, time scale,
-- determinism, reset, step cap, recovery, scenario sanity, soak and throughput.

return function(T: any)
	local Sim = T.gym("Sim")
	local Rig = T.gym("Rig")
	local Solver2D = T.gym("Solver2D")
	local Tuning = T.gym("Tuning")
	local Scenarios = T.gym("Scenarios")

	-- deterministic pseudo-random numbers (LCG), no global RNG state
	local function lcg(seed: number)
		local state = seed
		return function(): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	-- Drives `sim` with a frame-time generator until step `target`; returns the checksum taken at that step.
	local function checksumAtStep(sim: any, target: number, nextDt: () -> number): string
		local captured: string? = nil
		sim.onStep = function(s)
			if s.stepCount == target then
				captured = Sim.checksum(s)
			end
		end
		local guard = 0
		while captured == nil do
			Sim.advance(sim, nextDt())
			guard += 1
			assert(guard < 100000, "did not reach target step")
		end
		sim.onStep = nil
		return captured :: string
	end

	T.test("frame-rate independence: 30/60/144/240 fps and jittery frames give identical states", function()
		local target = 600
		local results = {}
		local rnd = lcg(7)
		local function fixed(dt: number): () -> number
			return function()
				return dt
			end
		end
		local patterns: { { name: string, dt: () -> number } } = {
			{ name = "30fps", dt = fixed(1 / 30) },
			{ name = "60fps", dt = fixed(1 / 60) },
			{ name = "144fps", dt = fixed(1 / 144) },
			{ name = "240fps", dt = fixed(1 / 240) },
			{
				name = "jitter",
				dt = function()
					return 1 / 200 + rnd() * (1 / 20 - 1 / 200)
				end,
			},
		}
		for _, p in patterns do
			local sim = Sim.new(nil, "Tumble")
			results[p.name] = checksumAtStep(sim, target, p.dt)
		end
		for name, sum in results do
			T.expect(sum == results["60fps"], `state at step {target} differs for {name}`)
		end
	end)

	T.test("slow motion (timeScale 0.25) gives identical steps and takes 4x real time", function()
		local normal = Sim.new(nil, "Hang")
		local slow = Sim.new({ timeScale = 0.25 }, "Hang")
		local realNormal, realSlow = 0, 0
		local sumNormal = checksumAtStep(normal, 480, function()
			realNormal += 1 / 60
			return 1 / 60
		end)
		local sumSlow = checksumAtStep(slow, 480, function()
			realSlow += 1 / 60
			return 1 / 60
		end)
		T.expect(sumNormal == sumSlow, "slow-motion trajectory differs")
		T.note("realTimeRatio", realSlow / realNormal)
		T.near(realSlow / realNormal, 4, 0.05, "real time ratio")
	end)

	T.test("determinism: the same run twice is bit-identical", function()
		local a = Sim.new(nil, "Tumble")
		local b = Sim.new(nil, "Tumble")
		for _ = 1, 1200 do
			Sim.stepOnce(a)
			Sim.stepOnce(b)
		end
		T.expect(Sim.checksum(a) == Sim.checksum(b), "runs diverged")
	end)

	T.test("reset restores exactly the initial state", function()
		local fresh = Sim.new(nil, "Drop")
		local initial = Sim.checksum(fresh)
		local sim = Sim.new(nil, "Drop")
		for _ = 1, 700 do
			Sim.stepOnce(sim)
		end
		Sim.setPose(sim, "Limp")
		Sim.reset(sim)
		T.expect(Sim.checksum(sim) == initial, "reset state differs")
		T.expect(sim.stepCount == 0 and sim.time == 0 and sim.acc == 0, "counters not reset")
		T.expect(sim.rig.pose == Scenarios.get("Drop").pose, "pose not reset to the scenario default")
		Sim.reset(sim, "Wheel")
		T.expect(sim.scenario == "Wheel" and sim.grip ~= nil, "scenario switch")
	end)

	T.test("huge frame time is capped (no spiral of death) and pause stops stepping", function()
		local sim = Sim.new(nil, "Hang")
		local steps = Sim.advance(sim, 5)
		T.below(steps, sim.tuning.maxStepsPerFrame, "steps in one frame")
		T.expect(sim.acc < sim.h, "accumulator left over")
		sim.paused = true
		T.expect(Sim.advance(sim, 1 / 60) == 0, "stepped while paused")
		sim.paused = false
		T.expect(Sim.advance(sim, 0 / 0) == 0, "NaN frame time accepted")
		T.expect(Sim.advance(sim, -1) == 0, "negative frame time accepted")
		sim.tuning.timeScale = 0
		T.expect(Sim.advance(sim, 1 / 60) == 0, "stepped at timeScale 0")
	end)

	T.test("invalid numerical state is detected, reported and recovered", function()
		local sim = Sim.new(nil, "Hang")
		for _ = 1, 10 do
			Sim.stepOnce(sim)
		end
		sim.rig.torso.vx = 0 / 0
		Sim.stepOnce(sim)
		local events = Sim.drainEvents(sim)
		local found = false
		for _, e in events do
			if e.kind == "invalid" then
				found = true
			end
		end
		T.expect(found, "no invalid event")
		T.expect(not Solver2D.hasInvalidState(sim.world), "state still invalid")
	end)

	T.test("tuning values are clamped and validated", function()
		local t = Tuning.new()
		T.near(Tuning.set(t, "gravity", 1e9), 150, 0, "clamped to max")
		T.near(Tuning.set(t, "gravity", 0 / 0), 150, 0, "NaN rejected")
		local ok = pcall(function()
			Tuning.set(t, "notAParameter", 1)
		end)
		T.expect(not ok, "unknown parameter accepted")
		for _, p in Tuning.list do
			T.expect(p.default >= p.min and p.default <= p.max, `default out of range: {p.key}`)
		end
	end)

	-- Scenario sanity: every scenario runs 10 s without failures; bodies stay above the floor.
	for _, scenario in Scenarios.list do
		T.test(`scenario {scenario.name}: 10 s stable, joints attached, nothing below the floor`, function()
			local sim = Sim.new(nil, scenario.name)
			local maxJointErr, lowest = 0, math.huge
			for _ = 1, 2400 do
				Sim.stepOnce(sim)
				local m = Sim.metrics(sim)
				maxJointErr = math.max(maxJointErr, m.maxJointError)
				for _, shape in sim.world.bodyShapes do
					lowest = math.min(lowest, math.min(shape.ay, shape.by) - shape.radius)
				end
			end
			for _, e in Sim.drainEvents(sim) do
				T.expect(e.kind ~= "invalid", "invalid state during run")
			end
			T.note("maxJointError", maxJointErr)
			T.note("lowestSurface", lowest)
			T.below(maxJointErr, 0.12, "joint separation")
			T.above(lowest, -0.08, "penetration into the floor")
		end)
	end

	T.test("Hang: total energy never increases (springs and damping only remove energy)", function()
		local sim = Sim.new({ angularDamping = 0 }, "Hang")
		local m0 = Sim.metrics(sim)
		local E0 = m0.kinetic + m0.potential
		local maxGain = 0
		local lastE = E0
		for _ = 1, 240 * 20 do
			Sim.stepOnce(sim)
			local m = Sim.metrics(sim)
			lastE = m.kinetic + m.potential
			maxGain = math.max(maxGain, lastE - E0)
		end
		local scale = sim.tuning.bodyMass * Tuning.effectiveGravity(sim.tuning) * 6
		T.note("maxGain%", maxGain / scale * 100)
		T.note("lossAfter20s%", (E0 - lastE) / scale * 100)
		T.below(maxGain / scale, 0.005, "energy gain")
	end, { slow = true })

	T.test("Hang: joints hold at giant-swing speed", function()
		local sim = Sim.new(nil, "Hang")
		-- relaunch from inverted with a push: a full rotation around the grip
		Sim.reset(sim)
		for _, seg in sim.rig.segments do
			local b = seg.body
			local rx, ry = b.x - 0, b.y - 10
			b.vx = -6 * ry
			b.vy = 6 * rx
			b.w = 6
		end
		local maxErr, maxGripErr, maxW = 0, 0, 0
		for _ = 1, 240 * 6 do
			Sim.stepOnce(sim)
			for _, rj in sim.rig.joints do
				maxErr = math.max(maxErr, rj.joint.error)
			end
			maxGripErr = math.max(maxGripErr, (sim.grip :: any).error)
			maxW = math.max(maxW, math.abs(sim.rig.torso.w))
		end
		T.note("maxTorsoSpin(rad/s)", maxW)
		T.note("maxJointError", maxErr)
		T.note("maxGripError", maxGripErr)
		T.below(maxErr, 0.06, "body joints")
		T.below(maxGripErr, 0.06, "grip")
	end)

	T.test("Wheel: the grip stays attached through a full revolution of the moving anchor", function()
		local sim = Sim.new(nil, "Wheel")
		local maxGripErr = 0
		for _ = 1, 240 * 6 do
			Sim.stepOnce(sim)
			maxGripErr = math.max(maxGripErr, (sim.grip :: any).error)
		end
		T.note("maxGripError", maxGripErr)
		T.below(maxGripErr, 0.06, "grip error on the moving anchor")
		local wheel = (sim.grip :: any).bodyA
		T.near(wheel.a, 1.2 * sim.time, 1e-6, "wheel angle")
	end)

	T.test("Drop: lands physically and comes to rest (not a crash reset)", function()
		local sim = Sim.new(nil, "Drop")
		for _ = 1, 240 * 6 do
			Sim.stepOnce(sim)
		end
		local m = Sim.metrics(sim)
		T.note("finalMaxSpeed", m.maxSpeed)
		T.note("contacts", m.contactCount)
		T.note("comHeight", m.comY)
		T.below(m.maxSpeed, 0.2, "still moving")
		T.above(m.contactCount, 2, "resting contacts")
		T.expect(#Sim.drainEvents(sim) == 0, "unexpected events (reset/invalid)")
	end)

	T.test(
		"stability soak: random poses and violent shoves across gravity and solver-rate settings",
		function()
			-- (simHz, substeps): the default plus the lower and higher solver rates we support
			local rates: { { hz: number, sub: number, isDefault: boolean } } = {
				{ hz = 240, sub = 4, isDefault = true },
				{ hz = 240, sub = 2, isDefault = false },
				{ hz = 120, sub = 4, isDefault = false },
				{ hz = 480, sub = 2, isDefault = false },
			}
			local FLOOR_HALF_WIDTH = 80 -- the test course floor spans x = -80..80
			local report = {}
			for _, moon in { 0, 1 } do
				for _, rate in rates do
					local hz, sub, isDefault = rate.hz, rate.sub, rate.isDefault
					for _, scenarioName in { "Hang", "Tumble" } do
						local sim = Sim.new({ moonGravity = moon, simHz = hz, substeps = sub }, scenarioName)
						local rnd = lcg(hz * 13 + sub * 7 + moon * 3 + #scenarioName)
						local every = (0.25 * hz) // 1
						local worstJoint, worstLimit, tunnel = 0, 0, 0
						for i = 1, 60 * hz do -- 60 s
							if i % every == 0 then
								Sim.setPose(sim, Rig.POSE_ORDER[1 + (rnd() * #Rig.POSE_ORDER) // 1])
								if rnd() < 0.3 then
									-- instant ±15 studs/s kick to one limb (far harsher than any gameplay force)
									local b = sim.rig.segments[1 + (rnd() * #sim.rig.segments) // 1].body
									b.vx += (rnd() - 0.5) * 30
									b.vy += (rnd() - 0.5) * 30
								end
							end
							Sim.stepOnce(sim)
							for _, rj in sim.rig.joints do
								worstJoint = math.max(worstJoint, rj.joint.error)
								local lim = Rig.LIMITS[rj.name]
								local a = math.deg(Rig.jointAngle(rj))
								worstLimit = math.max(worstLimit, lim[1] - a, a - lim[2])
							end
							for _, shape in sim.world.bodyShapes do
								local cx = (shape.ax + shape.bx) / 2
								if math.abs(cx) < FLOOR_HALF_WIDTH - 1 then
									local low = math.min(shape.ay, shape.by) - shape.radius
									tunnel = math.max(tunnel, -low)
								end
							end
						end
						local label = `moon={moon} {hz}Hz×{sub} {scenarioName}`
						for _, e in Sim.drainEvents(sim) do
							T.expect(e.kind ~= "invalid", `invalid state: {label}`)
						end
						T.below(tunnel, 0.3, `penetration while over the floor: {label}`)
						if isDefault then
							T.below(worstJoint, 0.05, `joint separation (default settings): {label}`)
							T.below(worstLimit, 8, `limit violation (default settings): {label}`)
						else
							T.below(worstJoint, 0.15, `joint separation: {label}`)
							T.below(worstLimit, 25, `limit violation: {label}`)
						end
						table.insert(
							report,
							string.format(
								"%s j=%.3f lim=%.1f pen=%.2f",
								label,
								worstJoint,
								worstLimit,
								tunnel
							)
						)
					end
				end
			end
			for _, line in report do
				T.note("run", line)
			end
		end,
		{ slow = true }
	)

	T.test("throughput: steps per second (informational, with a sanity floor)", function()
		for _, name in { "Hang", "Tumble" } do
			local sim = Sim.new(nil, name)
			local t0 = os.clock()
			local n = 240 * 10
			for _ = 1, n do
				Sim.stepOnce(sim)
			end
			local dt = os.clock() - t0
			T.note(`{name} µs/step`, dt / n * 1e6)
			T.note(`{name} ms per 60fps frame (4 steps)`, dt / n * 4 * 1000)
			T.below(dt / n, 500e-6, `{name} step cost`)
		end
	end)
end
