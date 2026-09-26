--!strict
-- Contact tests: resting, tunneling, friction, restitution, corners and slopes.

return function(T: any)
	local Solver2D = T.gym("Solver2D")
	local Collide2D = T.gym("Collide2D")

	local H = 1 / 240

	local function world(opts: { g: number?, floorFriction: number?, substeps: number? }?)
		local o: { g: number?, floorFriction: number?, substeps: number? } = opts or {}
		local p = Solver2D.defaultParams()
		p.gravityY = -(o.g or 35)
		p.substeps = o.substeps or p.substeps
		local w = Solver2D.newWorld(p)
		Solver2D.addPolygon(w, w.ground, Collide2D.newBox(50, 2, 0, -2), { friction = o.floorFriction or 1 })
		return w
	end

	T.test("circle comes to rest on the floor without jitter or sinking", function()
		local w = world()
		local b = Solver2D.addBody(w, { x = 0, y = 2, mass = 1, inertia = 0.1 })
		local s = Solver2D.addCircle(w, b, 0, 0, 0.5, { friction = 0.5 })
		local deepest = math.huge
		for _ = 1, 240 * 3 do
			Solver2D.step(w, H)
			deepest = math.min(deepest, b.y - 0.5)
		end
		local speed = math.sqrt(b.vx ^ 2 + b.vy ^ 2)
		T.note("restSpeed", speed)
		T.note("deepestPenetration", -deepest)
		T.below(speed, 0.01, "rest speed")
		T.above(deepest, -0.03, "penetration")
		T.near(b.y, 0.5, 0.03, "resting height")
		T.expect(s ~= nil)
	end)

	T.test("capsule lying flat gets a two-point contact and does not rock", function()
		local w = world()
		local b = Solver2D.addBody(w, { x = 0, y = 1, a = 0.05, mass = 1, inertia = 0.35 })
		Solver2D.addCapsule(w, b, -1, 0, 1, 0, 0.25, { friction = 0.8 })
		for _ = 1, 240 * 3 do
			Solver2D.step(w, H)
		end
		T.note("contactPoints", #w.contacts)
		T.note("finalAngleDeg", math.deg(b.a))
		T.expect(#w.contacts == 2, `expected 2 contact points, got {#w.contacts}`)
		T.below(math.abs(b.w), 0.01, "angular velocity at rest")
		T.below(math.abs(b.a), math.rad(0.5), "lies flat")
	end)

	T.test("no tunneling: fast small circle hitting the floor at 300 studs/s", function()
		local w = world()
		local b = Solver2D.addBody(w, { x = 0, y = 3, vy = -300, mass = 1, inertia = 0.01 })
		Solver2D.addCircle(w, b, 0, 0, 0.15, { friction = 0.5 })
		local lowest = math.huge
		for _ = 1, 240 do
			Solver2D.step(w, H)
			lowest = math.min(lowest, b.y - 0.15)
		end
		T.note("lowestSurfaceY", lowest)
		T.above(lowest, -0.1, "went through the floor")
	end)

	T.test("friction: sliding capsule decelerates at about μ·g", function()
		local mu = 0.5
		local w = world({ floorFriction = mu })
		local b = Solver2D.addBody(w, { x = 0, y = 0.25, vx = 12, mass = 1, inertia = 0.35 })
		Solver2D.addCapsule(w, b, -1, 0, 1, 0, 0.25, { friction = mu })
		-- let it settle onto the floor for a moment, then measure
		for _ = 1, 24 do
			Solver2D.step(w, H)
		end
		local v0, t0 = b.vx, 0
		for _ = 1, 120 do
			Solver2D.step(w, H)
			t0 += H
		end
		local decel = (v0 - b.vx) / t0
		T.note("measuredDecel", decel)
		T.note("expectedDecel", mu * 35)
		T.near(decel, mu * 35, mu * 35 * 0.1, "deceleration")
	end)

	T.test("restitution: e = 0.5 bounces to about e² of the drop height; e = 0.05 barely bounces", function()
		local function bounce(e: number): number
			local w = world()
			local b = Solver2D.addBody(w, { x = 0, y = 4.5, mass = 1, inertia = 0.1 })
			Solver2D.addCircle(w, b, 0, 0, 0.5, { friction = 0.5, restitution = e })
			local hitGround, apex = false, 0
			for _ = 1, 240 * 3 do
				Solver2D.step(w, H)
				if not hitGround and b.vy > 0 then
					hitGround = true
				end
				if hitGround then
					apex = math.max(apex, b.y - 0.5)
				end
			end
			return apex / 4.0
		end
		local r50 = bounce(0.5)
		local r05 = bounce(0.05)
		T.note("heightRatio(e=0.5)", r50)
		T.note("heightRatio(e=0.05)", r05)
		T.near(r50, 0.25, 0.05, "bounce ratio for e=0.5")
		T.below(r05, 0.02, "bounce ratio for e=0.05")
	end)

	T.test("capsule dropped on a block corner stays stable and slides off", function()
		local w = world()
		Solver2D.addPolygon(w, w.ground, Collide2D.newBox(1, 1, 0, 1), { friction = 0.6 })
		local b = Solver2D.addBody(w, { x = 0.9, y = 3.5, a = 0.3, mass = 1, inertia = 0.35 })
		Solver2D.addCapsule(w, b, -1, 0, 1, 0, 0.2, { friction = 0.6 })
		for _ = 1, 240 * 4 do
			Solver2D.step(w, H)
			T.expect(not Solver2D.hasInvalidState(w), "invalid state")
		end
		local speed = math.sqrt(b.vx ^ 2 + b.vy ^ 2)
		T.note("finalSpeed", speed)
		T.note("final", string.format("(%.2f, %.2f, %.1f°)", b.x, b.y, math.deg(b.a)))
		T.below(speed, 0.05, "comes to rest")
	end)

	T.test("slope: capsule holds with high friction and slides with low friction", function()
		local function run(mu: number): number
			local w = world({ floorFriction = mu })
			-- 20° slope
			local ang = math.rad(20)
			Solver2D.addPolygon(
				w,
				w.ground,
				Collide2D.newPolygon({ -10, 0, 10, 0, 10, 20 * math.tan(ang) }),
				{ friction = mu }
			)
			local x0 = 2
			local y0 = (x0 + 10) * math.tan(ang) + 0.25 / math.cos(ang) + 0.01
			local b = Solver2D.addBody(w, { x = x0, y = y0, a = ang, mass = 1, inertia = 0.35 })
			Solver2D.addCapsule(w, b, -0.8, 0, 0.8, 0, 0.25, { friction = mu })
			for _ = 1, 240 do
				Solver2D.step(w, H)
			end
			return math.sqrt((b.x - x0) ^ 2 + (b.y - y0) ^ 2)
		end
		local held = run(0.8) -- tan(20°) = 0.36 < 0.8
		local slid = run(0.05)
		T.note("displacement(μ=0.8)", held)
		T.note("displacement(μ=0.05)", slid)
		T.below(held, 0.05, "should hold")
		-- expected slide over 1 s: ½ g (sinθ - μ cosθ) t² ≈ 5.2 studs
		T.near(
			slid,
			0.5 * 35 * (math.sin(math.rad(20)) - 0.05 * math.cos(math.rad(20))),
			0.6,
			"slide distance"
		)
	end)

	T.test("collision routine: separated, touching and overlapping cases", function()
		local box = Collide2D.newBox(1, 1)
		-- circle well above: no contact
		T.expect(Collide2D.capsulePolygon(0, 3, 0, 3, 0.5, box, 0.1) == 0, "false contact")
		-- circle just resting: one point, normal pointing down into the box
		local n = Collide2D.capsulePolygon(0, 1.5, 0, 1.5, 0.5, box, 0.1)
		T.expect(n == 1, `expected 1 point, got {n}`)
		T.near(Collide2D.ny, -1, 1e-9, "normal y")
		T.near(Collide2D.sep[1], 0, 1e-9, "separation")
		-- horizontal capsule overlapping the top face: two points
		n = Collide2D.capsulePolygon(-0.5, 1.2, 0.5, 1.2, 0.3, box, 0.1)
		T.expect(n == 2, `expected 2 points, got {n}`)
		T.near(Collide2D.sep[1], -0.1, 1e-9, "overlap depth")
		-- corner region: circle diagonally off the corner
		n = Collide2D.capsulePolygon(1.3, 1.3, 1.3, 1.3, 0.5, box, 0.1)
		T.expect(n == 1, "corner contact")
		T.near(Collide2D.nx, -math.sqrt(0.5), 1e-9, "corner normal x")
		-- deep: capsule core inside the box
		n = Collide2D.capsulePolygon(-0.3, 0.8, 0.3, 0.8, 0.1, box, 0.1)
		T.expect(n >= 1, "deep contact")
		T.expect(Collide2D.sep[1] < 0, "deep separation negative")
	end)
end
