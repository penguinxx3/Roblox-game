--!strict
-- Solver2D unit tests: integration, gravity, joints, springs, limits, kinematic anchors.

return function(T: any)
	local Solver2D = T.gym("Solver2D")

	local H = 1 / 240

	local function world(g: number?, substeps: number?)
		local p = Solver2D.defaultParams()
		p.gravityY = -(g or 35)
		p.substeps = substeps or p.substeps
		p.angularDamping = 0
		p.linearDamping = 0
		return Solver2D.newWorld(p)
	end

	-- uniform rod of length L along its local x-axis, centred on its centre of mass
	local function rod(w: any, x: number, y: number, a: number, L: number, m: number)
		return Solver2D.addBody(w, { x = x, y = y, a = a, mass = m, inertia = m * L * L / 12 })
	end

	T.test("gravity: free body matches the substep integrator exactly and the parabola closely", function()
		local w = world(35)
		local b = Solver2D.addBody(w, { x = 0, y = 100, mass = 1, inertia = 1, vx = 3 })
		local n = 480 -- 2 s
		for _ = 1, n do
			Solver2D.step(w, H)
		end
		local S = w.params.substeps
		local hs = H / S
		local k = n * S
		local exactY = 100 - 35 * hs * hs * k * (k + 1) / 2 -- semi-implicit Euler closed form
		T.near(b.y, exactY, 1e-9, "y vs integrator closed form")
		T.near(b.vy, -35 * 2, 1e-9, "vy")
		T.expect(S >= 1)
		T.near(b.x, 3 * 2, 1e-9, "x (no horizontal force)")
		local parabola = 100 - 0.5 * 35 * 4
		T.near(
			b.y,
			parabola,
			0.5 * 35 * hs * 2 + 1e-9,
			"y vs analytic parabola (within integrator error bound)"
		)
		T.note("parabolaError", math.abs(b.y - parabola))
	end)

	T.test("step with zero or negative dt does nothing", function()
		local w = world()
		local b = Solver2D.addBody(w, { x = 1, y = 2, mass = 1, inertia = 1 })
		Solver2D.step(w, 0)
		Solver2D.step(w, -1)
		T.expect(b.x == 1 and b.y == 2 and b.vy == 0, "body moved")
		T.expect(w.stepIndex == 0, "step counted")
	end)

	T.test("pendulum (rigid rod on a pin) conserves energy over 60 s", function()
		local w = world(35)
		local L, m = 3, 2
		-- horizontal rod, pinned at its left end to the ground at (0, 10)
		local b = rod(w, L / 2, 10, 0, L, m)
		Solver2D.addRevolute(w, w.ground, b, 0, 10)
		local e0 = Solver2D.metrics(w, 35)
		local E0 = e0.kinetic + e0.potential
		local maxDev, maxErr = 0, 0
		for _ = 1, 240 * 60 do
			Solver2D.step(w, H)
			local e = Solver2D.metrics(w, 35)
			maxDev = math.max(maxDev, math.abs(e.kinetic + e.potential - E0))
			maxErr = math.max(maxErr, e.maxJointError)
		end
		-- energy scale: m g L (drop of the centre of mass from horizontal to bottom is m g L/2)
		local rel = maxDev / (m * 35 * L / 2)
		T.note("maxEnergyDeviation%", rel * 100)
		T.note("maxPinError", maxErr)
		T.below(rel, 0.01, "relative energy deviation")
		T.below(maxErr, 0.01, "pin separation")
	end, { slow = true })

	T.test("joint stays attached at high spin (30 rad/s)", function()
		local w = world(35)
		local b = rod(w, 1.5, 10, 0, 3, 1)
		b.vy = 30 * 1.5
		b.w = 30
		Solver2D.addRevolute(w, w.ground, b, 0, 10)
		local maxErr = 0
		for _ = 1, 240 * 5 do
			Solver2D.step(w, H)
			maxErr = math.max(maxErr, w.joints[1].error)
		end
		T.note("maxPinError", maxErr)
		T.below(maxErr, 0.02, "pin separation at 30 rad/s")
	end)

	T.test("spring motor reaches its target and settles (zero gravity)", function()
		local w = world(0)
		local b = rod(w, 1, 0, 0, 2, 1)
		local j = Solver2D.addRevolute(w, w.ground, b, 0, 0, {
			enableSpring = true,
			target = math.rad(90),
			maxTorque = 1000,
			springHertz = 4,
			springDampingRatio = 0.8,
		})
		local peak = 0
		local settledAt = -1
		for i = 1, 240 * 3 do
			Solver2D.step(w, H)
			local angle = b.a - w.ground.a
			peak = math.max(peak, angle)
			if settledAt < 0 and math.abs(angle - math.rad(90)) < math.rad(2) and math.abs(b.w) < 0.2 then
				settledAt = i * H
			end
		end
		T.note("overshootDeg", math.deg(peak) - 90)
		T.note("settleTime", settledAt)
		T.expect(settledAt > 0, "never settled within 2°")
		T.near(b.a, math.rad(90), math.rad(1), "final angle")
		T.expect(j.error < 1e-3, "joint separated")
	end)

	T.test("motor max torque limits strength (compliance under load)", function()
		-- horizontal rod held at its left end against gravity; holding needs m g L/2.
		-- A saturated motor has no damping left, so a weak one swings around its
		-- equilibrium (cos θ = τmax / (m g L/2)); measure the peak droop.
		local function droop(maxTorque: number): number
			local w = world(35, 4)
			local L, m = 2, 1
			local b = rod(w, L / 2, 10, 0, L, m)
			Solver2D.addRevolute(w, w.ground, b, 0, 10, {
				enableSpring = true,
				target = 0,
				maxTorque = maxTorque,
				springHertz = 8,
				springDampingRatio = 1,
			})
			local peak = 0
			for _ = 1, 240 * 3 do
				Solver2D.step(w, H)
				peak = math.max(peak, -math.deg(b.a))
			end
			return peak -- degrees below horizontal
		end
		local need = 1 * 35 * 2 / 2
		local strong = droop(need * 3)
		local weak = droop(need * 0.5)
		T.note("strongDroopDeg", strong)
		T.note("weakDroopDeg", weak)
		T.below(strong, 10, "strong motor holds near the target (spring deflection only)")
		T.above(weak, 45, "weak motor gives way under the load")
	end)

	T.test("angle limits hold against a motor pushing past them", function()
		local w = world(0)
		local b = rod(w, 1, 0, 0, 2, 1)
		Solver2D.addRevolute(w, w.ground, b, 0, 0, {
			enableLimit = true,
			lower = math.rad(-30),
			upper = math.rad(60),
			enableSpring = true,
			target = math.rad(170),
			maxTorque = 50,
			springHertz = 6,
			springDampingRatio = 0.5,
		})
		local maxAngle = -math.huge
		for _ = 1, 240 * 3 do
			Solver2D.step(w, H)
			maxAngle = math.max(maxAngle, b.a)
		end
		T.note("maxAngleDeg", math.deg(maxAngle))
		T.below(math.deg(maxAngle), 60 + 1.5, "upper limit")
	end)

	T.test("kinematic body moves exactly with its velocity and carries a pinned body", function()
		local w = world(35)
		local wheel = Solver2D.addBody(w, { kind = Solver2D.KINEMATIC, x = 0, y = 10, w = 1.5 })
		local b = rod(w, 3, 8.5, -math.pi / 2, 3, 1) -- hangs from the spoke tip at (3, 10)
		Solver2D.addRevolute(w, wheel, b, 3, 10)
		local maxErr = 0
		local n = 240 * 6 -- 9 rad > one revolution
		for _ = 1, n do
			Solver2D.step(w, H)
			maxErr = math.max(maxErr, w.joints[1].error)
		end
		T.near(wheel.a, 1.5 * n * H, 1e-9, "wheel angle = ω t")
		T.near(wheel.x, 0, 0, "wheel does not translate")
		T.note("maxPinError", maxErr)
		T.below(maxErr, 0.02, "pin to moving anchor")
	end)

	T.test("checksum and invalid-state detection", function()
		local w = world()
		local b = Solver2D.addBody(w, { x = 0, y = 0, mass = 1, inertia = 1 })
		T.expect(not Solver2D.hasInvalidState(w), "false positive")
		b.vx = 0 / 0
		T.expect(Solver2D.hasInvalidState(w), "NaN not detected")
	end)
end
