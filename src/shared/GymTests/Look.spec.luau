--!strict
-- Look tests (P1.2 round 3): the drawn body's proportions are presentation only, stay inside
-- the physics collision shapes (so contacts still look right), and don't intersect themselves;
-- the torso is one block, and every shape's colour is in each hex palette.

return function(T: any)
	local Sim = T.gym("Sim")
	local Rig = T.gym("Rig")
	local Input = T.gym("Input")
	local Look = T.gym("Look")

	-- In-plane outline points of a drawn shape, in its body's local frame.
	local function outline(p: any): { { number } }
		local pts: { { number } } = {}
		if p.kind == "ball" then
			for k = 0, 23 do
				local a = k / 24 * 2 * math.pi
				table.insert(pts, { p.ax + p.r * math.cos(a), p.ay + p.r * math.sin(a) })
			end
		elseif p.kind == "rod" then
			for _, e in { { p.ax, p.ay }, { p.bx, p.by } } do
				for k = 0, 23 do
					local a = k / 24 * 2 * math.pi
					table.insert(pts, { e[1] + p.r * math.cos(a), e[2] + p.r * math.sin(a) })
				end
			end
		else
			local hx, hy = p.len / 2, p.thick / 2
			for _, c in
				{ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
			do
				table.insert(pts, { p.ax + c[1] * hx, p.ay + c[2] * hy })
			end
		end
		return pts
	end

	-- How far a world point sticks out of the rig's collision shapes (<= 0 = inside).
	local function outside(sim: any, x: number, y: number): number
		local best = math.huge
		for _, sh in sim.world.bodyShapes do
			-- world ends from the body's current pose (the shapes' world cache is refreshed
			-- inside the solver step, one substep behind)
			local b = sh.body
			local c, s = math.cos(b.a), math.sin(b.a)
			local ax, ay = b.x + c * sh.lax - s * sh.lay, b.y + s * sh.lax + c * sh.lay
			local bx, by = b.x + c * sh.lbx - s * sh.lby, b.y + s * sh.lbx + c * sh.lby
			local dx, dy = bx - ax, by - ay
			local L2 = dx * dx + dy * dy
			local t = if L2 > 0 then math.clamp(((x - ax) * dx + (y - ay) * dy) / L2, 0, 1) else 0
			local px, py = ax + t * dx - x, ay + t * dy - y
			best = math.min(best, math.sqrt(px * px + py * py) - sh.radius)
		end
		return best
	end

	T.test(
		"the drawn body stays inside the physics collision shapes (standing, crouch, tuck, arch, hang)",
		function()
			local worst, worstName = -math.huge, ""
			local function check(sim: any, label: string)
				for _, p in Look.build(sim.rig) do
					local b = p.seg.body
					local c, s = math.cos(b.a), math.sin(b.a)
					for _, pt in outline(p) do
						local x = b.x + c * pt[1] - s * pt[2]
						local y = b.y + s * pt[1] + c * pt[2]
						local d = outside(sim, x, y)
						if d > worst then
							worst, worstName = d, `{p.name} ({label})`
						end
					end
				end
			end
			local function posed(scene: string, tuck: number, arch: number, secs: number, label: string)
				local sim = Sim.new(nil, scene, { control = "player" })
				local inp = Input.new()
				inp.tuck, inp.arch = tuck, arch
				for _ = 1, math.floor(secs * 240) do
					Sim.setInput(sim, inp)
					Sim.stepOnce(sim)
				end
				check(sim, label)
			end
			posed("Stand", 0, 0, 1, "standing")
			posed("Stand", 1, 0, 1, "crouch")
			posed("Tumble", 1, 0, 0.5, "tuck")
			posed("Tumble", 0, 1, 0.5, "arch")
			posed("Hang", 1, 1, 0.8, "pike on the bar")
			posed("Hang", 0, 0, 0.5, "hang")
			T.note("farthest a drawn shape sticks out (studs)", string.format("%.3f (%s)", worst, worstName))
			-- only the foot's square corners pass the rounded capsule ends, by a hair
			T.below(worst, 0.04, "drawn shape outside the collision shapes")
		end
	)

	T.test("feet: the drawn sole is the physics sole", function()
		local sim = Sim.new(nil, "Stand", { control = "player" })
		local feet = 0
		for _, p in Look.build(sim.rig) do
			if p.kind == "box" and p.role == "foot" then
				feet += 1
				-- the physics foot is a capsule along the local x axis; its sole is radius below it
				T.near(p.thick / 2, Rig.RADIUS.foot, 1e-12, "foot half-thickness = physics foot radius")
				T.near(p.ay, 0, 1e-9, "foot centred on the physics foot's axis")
				T.above(p.len, sim.rig.segmentByName.foot.length, "foot at least heel-to-toe long")
			end
		end
		T.expect(feet == 2, `two feet drawn ({feet})`)
		-- standing: the lowest drawn point of each foot is on the floor like the physics shape
		for _ = 1, 480 do
			Sim.setInput(sim, Input.new())
			Sim.stepOnce(sim)
		end
		local lowestPhysics, lowestDrawn = math.huge, math.huge
		for _, sh in sim.world.bodyShapes do
			if sh.tag == "foot" then
				lowestPhysics = math.min(lowestPhysics, math.min(sh.ay, sh.by) - sh.radius)
			end
		end
		for _, p in Look.build(sim.rig) do
			if p.role == "foot" then
				local b = p.seg.body
				local _u, v, a = Look.place(p, b.x, b.y, b.a)
				local c, s = math.cos(a), math.sin(a)
				for _, k in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
					local lx, ly = k[1] * p.len / 2, k[2] * p.thick / 2
					lowestDrawn = math.min(lowestDrawn, v + s * lx + c * ly)
				end
			end
		end
		T.note(
			"lowest point standing: physics / drawn",
			string.format("%.3f / %.3f", lowestPhysics, lowestDrawn)
		)
		T.near(lowestDrawn, lowestPhysics, 0.02, "drawn feet stand on the floor")
	end)

	T.test("the drawn body doesn't intersect itself in depth (head, arms, legs, torso)", function()
		local sim = Sim.new(nil, "Hang", { control = "player" })
		local head, block = nil :: any, nil :: any
		local armR, legR = 0, 0
		for _, p in Look.build(sim.rig) do
			if p.name == "head" then
				head = p
			elseif p.name == "torso" then
				block = p
			elseif
				p.name == "shoulder"
				or p.name == "upperArm"
				or p.name == "elbow"
				or p.name == "forearm"
				or p.name == "hand"
			then
				armR = math.max(armR, p.r)
			elseif
				p.name == "hip"
				or p.name == "thigh"
				or p.name == "knee"
				or p.name == "shank"
				or p.name == "ankle"
			then
				legR = math.max(legR, p.r)
			end
		end
		-- every arm shape lies in its own depth plane at ±ARM_DEPTH: in any pose it clears the
		-- head (a sphere on the centre plane) and the torso block beside it
		local headGap = Look.ARM_DEPTH - armR - head.r
		local torsoGap = Look.ARM_DEPTH - armR - block.width / 2
		local legGap = 2 * (Look.LEG_DEPTH - legR)
		local armLegGap = (Look.ARM_DEPTH - armR) - (Look.LEG_DEPTH + legR)
		T.note(
			"depth gaps: head-arm / torso-arm / leg-leg / arm-leg",
			string.format("%.2f / %.2f / %.2f / %.2f", headGap, torsoGap, legGap, armLegGap)
		)
		T.above(headGap, 0.05, "arms clear the head")
		T.above(torsoGap, 0, "arms clear the torso block")
		T.above(legGap, 0.1, "legs clear each other")
		T.above(armLegGap, 0.05, "arms clear the legs")
		T.below(Look.LEG_DEPTH + legR, block.width / 2 + 0.01, "hips within the torso block's width")
		-- the head sits apart from the shoulders (a neck), not buried in the chest
		local torso = sim.rig.segmentByName.torso
		T.above(head.ax - head.r - torso.p1x, 0.3, "gap between the shoulder line and the head")
		T.below(
			head.ax + head.r,
			sim.rig.headLocalX + Rig.RADIUS.head + 1e-9,
			"head top within the physics head"
		)
	end)

	T.test("slimmer than the collision shapes; building the look doesn't touch the simulation", function()
		local sim = Sim.new(nil, "Tumble", { control = "player" })
		local twin = Sim.new(nil, "Tumble", { control = "player" })
		local prims = Look.build(sim.rig)
		for _, p in prims do
			if p.kind == "rod" and p.role == "limb" then
				T.below(p.r, p.seg.radius, `{p.name} drawn thinner than its collision shape`)
			end
		end
		local blocks = 0
		for _, p in prims do
			if p.seg.name == "torso" and p.kind == "box" then
				blocks += 1
				T.below(
					p.thick,
					2 * Rig.RADIUS.trunk,
					"torso block thinner in the plane than the collision torso"
				)
			end
		end
		T.expect(blocks == 1, `the torso is one block ({blocks})`)
		T.near(Rig.RADIUS.thigh, 0.23, 1e-12, "physics thigh radius unchanged")
		T.near(Rig.RADIUS.trunk, 0.42, 1e-12, "physics trunk radius unchanged")
		for _ = 1, 240 do
			Look.build(sim.rig)
			Sim.stepOnce(sim)
			Sim.stepOnce(twin)
		end
		T.expect(Sim.checksum(sim) == Sim.checksum(twin), "building the look changed the simulation")
	end)

	T.test("every drawn shape has a colour in every palette, written as hex codes", function()
		local sim = Sim.new(nil, "Stand", { control = "player" })
		local prims = Look.build(sim.rig)
		local P: { [string]: { [string]: string } } = Look.PALETTES :: any
		for _, name in Look.PALETTE_ORDER do
			local palette = P[name]
			T.expect(palette ~= nil, `palette "{name}" exists`)
			for key, hex in palette do
				T.expect(string.match(hex, "^#%x%x%x%x%x%x$") ~= nil, `{name}.{key} = "{hex}" is "#RRGGBB"`)
			end
			for _, p in prims do
				T.expect(palette[p.role] ~= nil, `{name}: colour role "{p.role}" ({p.name}) in the palette`)
			end
		end
	end)
end
