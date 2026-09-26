--!strict
-- Rig tests: construction, joint conventions, motors, angular momentum, limits.

return function(T: any)
	local Solver2D = T.gym("Solver2D")
	local Rig = T.gym("Rig")
	local Tuning = T.gym("Tuning")

	local H = 1 / 240

	local function flightWorld(g: number)
		local p = Solver2D.defaultParams()
		p.gravityY = -g
		p.angularDamping = 0
		return Solver2D.newWorld(p)
	end

	local function stepRig(w: any, rig: any, t: any, n: number, each: ((number) -> ())?)
		for i = 1, n do
			Rig.applyMotors(rig, t)
			Solver2D.step(w, H)
			if each then
				each(i)
			end
		end
	end

	T.test("builds with the configured mass and straight joint angles", function()
		local t = Tuning.new()
		local w = flightWorld(35)
		local rig = Rig.build(w, t, { x = 0, y = 5 })
		local m = 0
		for _, seg in rig.segments do
			m += seg.body.mass
		end
		T.near(m, t.bodyMass, 1e-9, "total mass")
		T.expect(#rig.segments == 6 and #rig.joints == 5, "segment/joint count")
		local a = Rig.jointAnglesDeg(rig)
		T.near(a.shoulder, 0, 1e-9, "shoulder")
		T.near(a.elbow, 0, 1e-9, "elbow")
		T.near(a.hip, 0, 1e-9, "hip")
		T.near(a.knee, 0, 1e-9, "knee")
		T.near(a.ankle, 90, 1e-9, "ankle")
		for _, rj in rig.joints do
			T.near(rj.joint.error, 0, 1e-9, rj.name .. " anchor mismatch at build")
		end
		-- grip point sits above the shoulder by the arm length
		local gx, gy = Rig.gripPoint(rig)
		T.near(gx, 0, 1e-9, "grip x")
		T.near(gy, 5 + t.trunkLength + t.upperArmLength + t.forearmLength, 1e-9, "grip y")
	end)

	T.test("motors pull the body into each pose and settle (zero gravity)", function()
		local t = Tuning.new()
		for _, pose in { "Tuck", "Pike", "Arch", "Crouch" } do
			local w = flightWorld(0)
			local rig = Rig.build(w, t, { x = 0, y = 5, pose = pose })
			-- time until every joint stays within 3° of its target (coupled springs wobble first)
			local settled = -1
			local maxErrDeg = 0
			stepRig(w, rig, t, 240 * 5, function(i)
				local a = Rig.jointAnglesDeg(rig)
				local worst = 0
				for name, target in Rig.POSES[pose] do
					local lim = Rig.LIMITS[name]
					worst = math.max(worst, math.abs(a[name] - math.clamp(target, lim[1], lim[2])))
				end
				if worst > 3 then
					settled = -1
				elseif settled < 0 then
					settled = i / 240
				end
				maxErrDeg = worst
			end)
			T.note(`{pose} settleTime(s)`, settled)
			T.expect(settled > 0, `{pose} never settled within 3°`)
			T.below(maxErrDeg, 1, `{pose} final joint error (deg)`)
		end
	end)

	T.test("free flight: tucking conserves angular momentum and spins faster", function()
		local t = Tuning.new()
		local w = flightWorld(35)
		local rig = Rig.build(w, t, { pivot = "com", x = 0, y = 50, w = 4, pose = "Neutral" })
		-- settle the neutral pose for 0.5 s, measure spin, then tuck
		stepRig(w, rig, t, 120)
		local L0 = Solver2D.metrics(w, 35).angularMomentum
		local function spin(): number
			local a0 = rig.torso.a
			stepRig(w, rig, t, 60)
			return (rig.torso.a - a0) / (60 * H)
		end
		local wOpen = spin()
		Rig.setPose(rig, "Tuck")
		stepRig(w, rig, t, 240)
		local wTuck = spin()
		local L1 = Solver2D.metrics(w, 35).angularMomentum
		local ratio = wTuck / wOpen
		T.note("spinOpen(rev/s)", wOpen / (2 * math.pi))
		T.note("spinTuck(rev/s)", wTuck / (2 * math.pi))
		T.note("ratio", ratio)
		T.note("angularMomentumDrift%", math.abs(L1 - L0) / math.abs(L0) * 100)
		T.near(L1, L0, math.abs(L0) * 0.005, "angular momentum about the centre of mass")
		T.above(ratio, 1.5, "tuck spin ratio")
	end)

	T.test("free flight: centre of mass follows the ballistic path while the body changes shape", function()
		local t = Tuning.new()
		local w = flightWorld(35)
		local rig = Rig.build(w, t, { pivot = "com", x = 0, y = 20, vx = 4, vy = 12, w = 3, pose = "Tuck" })
		local m0 = Solver2D.metrics(w, 35)
		local substeps = w.params.substeps
		local hs = H / substeps
		local maxDev, maxParabola = 0, 0
		local n = 0
		stepRig(w, rig, t, 480, function(i)
			n = i
			if i == 120 then
				Rig.setPose(rig, "Arch")
			elseif i == 300 then
				Rig.setPose(rig, "Pike")
			end
			local m = Solver2D.metrics(w, 35)
			local tt = i * H
			local k = i * substeps
			-- internal joint forces must not move the centre of mass: it follows the
			-- integrator's own free-fall path exactly (semi-implicit Euler closed form)
			local ex = m0.comX + m0.comVX * tt
			local ey = m0.comY + m0.comVY * tt - 35 * hs * hs * k * (k + 1) / 2
			maxDev = math.max(maxDev, math.sqrt((m.comX - ex) ^ 2 + (m.comY - ey) ^ 2))
			local py = m0.comY + m0.comVY * tt - 0.5 * 35 * tt * tt
			maxParabola = math.max(maxParabola, math.abs(m.comY - py))
		end)
		T.note("maxDeviationFromIntegratorPath", maxDev)
		T.note("maxDeviationFromExactParabola", maxParabola)
		T.below(maxDev, 1e-6, "internal forces moved the centre of mass")
		T.below(maxParabola, 0.5 * 35 * hs * 2 + 1e-6, "parabola error beyond the integrator bound")
		T.expect(n == 480)
	end)

	T.test("limp body respects joint limits when dropped", function()
		local t = Tuning.new()
		local p = Solver2D.defaultParams()
		p.gravityY = -35
		local w = Solver2D.newWorld(p)
		local Collide2D = T.gym("Collide2D")
		Solver2D.addPolygon(w, w.ground, Collide2D.newBox(50, 2, 0, -2), { friction = 1 })
		local rig = Rig.build(w, t, { x = 0, y = 6, rot = 0.4, w = 3, pose = "Limp" })
		local worst = 0
		stepRig(w, rig, t, 240 * 4, function()
			for _, rj in rig.joints do
				local lim = Rig.LIMITS[rj.name]
				local a = math.deg(Rig.jointAngle(rj))
				local over = math.max(lim[1] - a, a - lim[2], 0)
				worst = math.max(worst, over)
			end
		end)
		T.note("worstLimitViolationDeg", worst)
		T.below(worst, 5, "limit violation")
	end)

	T.test("motor strength scales with gravity (moon gravity keeps the same pose behavior)", function()
		local t = Tuning.new({ moonGravity = 1 })
		local w = flightWorld(0)
		local rig = Rig.build(w, t, { x = 0, y = 5, pose = "Tuck" })
		Rig.applyMotors(rig, t)
		local g = Tuning.effectiveGravity(t)
		T.near(rig.jointByName.hip.joint.maxTorque, t.hipMaxTorque * t.bodyMass * g, 1e-9, "hip torque")
		T.near(g, t.gravity * t.moonGravityScale, 1e-12, "moon gravity")
	end)
end
