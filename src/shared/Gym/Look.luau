--!strict
-- Look: the drawn body's proportions (presentation only; no Roblox types).
--
-- The physics body (Rig) is six planar bodies with rounded collision shapes. Until P1.2 round 3
-- the renderer drew those collision shapes one-to-one: a round capsule torso whose end caps
-- swallowed the shoulders and hips, thick limbs, a stub foot, and a head that overlapped the
-- torso and, in depth, the arms. This module gives the drawing its own proportions:
--   * a flat chest block and a narrower pelvis block ending at the shoulder and hip lines
--   * a smaller head on a neck, its top where the physics head's top is
--   * slimmer limbs with joint balls and hands
--   * arms beside the chest in depth, legs at hip width: arms can't pass through the head
--   * box feet whose sole is the physics foot's sole
-- Every shape stays inside its body's collision shapes (Look.spec checks this), so contacts
-- still look right. The simulation never reads this module: physics is unchanged.

local Rig = require(script.Parent.Rig)

local Look = {}

-- Depth (z) of the left/right copies of the paired limbs
Look.ARM_DEPTH = 0.64 -- beside the chest, clear of the head (shoulder width ≈ 1.3)
Look.LEG_DEPTH = 0.24 -- hip width

-- Torso: two blocks along the hip -> shoulder line (fractions of that length), a neck, a head
Look.CHEST = { from = 0.47, to = 1.0, thick = 0.8, width = 1.0 }
Look.PELVIS = { from = -0.02, to = 0.5, thick = 0.72, width = 0.82 }
Look.NECK = { from = -0.05, to = 0.45, radius = 0.1 } -- studs past the shoulder line
Look.HEAD_RADIUS = 0.36

-- Limb radii
Look.RADIUS = {
	upperArm = 0.12,
	forearm = 0.105,
	thigh = 0.165,
	shank = 0.12, -- its end reaches the ankle, inside the foot's collision shape
}
Look.JOINT_RADIUS = {
	shoulder = 0.135,
	elbow = 0.12,
	hand = 0.13,
	hip = 0.165,
	knee = 0.155,
	ankle = 0.115,
}

-- Foot: a block from just behind the heel to just past the toe; its thickness is the physics
-- foot capsule's, so its sole lies exactly on the physics sole.
Look.FOOT = { heelExtra = 0.05, toeExtra = 0.06, width = 0.26 }

export type Prim = {
	name: string,
	seg: Rig.Segment, -- the segment whose body carries this shape
	kind: string, -- "ball" | "rod" | "box"
	side: number, -- -1 far copy, +1 near copy, 0 on the centre plane
	depth: number, -- z of the shape's centre
	role: string, -- colour role: "torso" | "pelvis" | "skin" | "limb" | "foot"
	-- body-local geometry: ball / box centre (ax, ay); rod from (ax, ay) to (bx, by)
	ax: number,
	ay: number,
	bx: number,
	by: number,
	r: number, -- ball / rod radius
	len: number, -- box size along the body's local x axis
	thick: number, -- box size across, in the plane
	width: number, -- box size in depth
}

local function prim(
	name: string,
	seg: Rig.Segment,
	kind: string,
	side: number,
	depth: number,
	role: string
): Prim
	return {
		name = name,
		seg = seg,
		kind = kind,
		side = side,
		depth = depth,
		role = role,
		ax = 0,
		ay = 0,
		bx = 0,
		by = 0,
		r = 0,
		len = 0,
		thick = 0,
		width = 0,
	}
end

local function ball(
	name: string,
	seg: Rig.Segment,
	side: number,
	depth: number,
	role: string,
	x: number,
	r: number
): Prim
	local p = prim(name, seg, "ball", side, depth, role)
	p.ax, p.ay, p.r = x, seg.p0y, r
	return p
end

local function rod(
	name: string,
	seg: Rig.Segment,
	side: number,
	depth: number,
	x0: number,
	x1: number,
	r: number
): Prim
	local p = prim(name, seg, "rod", side, depth, "limb")
	p.ax, p.ay, p.bx, p.by, p.r = x0, seg.p0y, x1, seg.p1y, r
	return p
end

local function box(
	name: string,
	seg: Rig.Segment,
	side: number,
	depth: number,
	role: string,
	x0: number,
	x1: number,
	thick: number,
	width: number
): Prim
	local p = prim(name, seg, "box", side, depth, role)
	p.ax, p.ay = (x0 + x1) / 2, seg.p0y
	p.len, p.thick, p.width = x1 - x0, thick, width
	return p
end

-- The drawn shapes of `rig`, in each body's local frame (build once per rig). Segment local
-- frames run along the segment from its proximal point p0 to its distal point p1.
function Look.build(rig: Rig.Rig): { Prim }
	local out: { Prim } = {}
	for _, seg in rig.segments do
		local x0, x1 = seg.p0x, seg.p1x
		local name = seg.name
		if name == "torso" then
			local L = x1 - x0 -- hip -> shoulder
			local C, P, N = Look.CHEST, Look.PELVIS, Look.NECK
			table.insert(
				out,
				box("chest", seg, 0, 0, "torso", x0 + C.from * L, x0 + C.to * L, C.thick, C.width)
			)
			table.insert(
				out,
				box("pelvis", seg, 0, 0, "pelvis", x0 + P.from * L, x0 + P.to * L, P.thick, P.width)
			)
			table.insert(out, rod("neck", seg, 0, 0, x1 + N.from, x1 + N.to, N.radius))
			out[#out].role = "skin"
			-- the head's top stays where the physics head's top is; the smaller head sits
			-- further from the shoulders, leaving room for the neck and the arms
			local headX = rig.headLocalX + Rig.RADIUS.head - Look.HEAD_RADIUS
			table.insert(out, ball("head", seg, 0, 0, "skin", headX, Look.HEAD_RADIUS))
		elseif seg.paired then
			for _, side in { -1, 1 } do
				local J = Look.JOINT_RADIUS
				if name == "upperArm" then
					local z = side * Look.ARM_DEPTH
					table.insert(out, ball("shoulder", seg, side, z, "limb", x0, J.shoulder))
					table.insert(out, rod("upperArm", seg, side, z, x0, x1, Look.RADIUS.upperArm))
					table.insert(out, ball("elbow", seg, side, z, "limb", x1, J.elbow))
				elseif name == "forearm" then
					local z = side * Look.ARM_DEPTH
					table.insert(out, rod("forearm", seg, side, z, x0, x1, Look.RADIUS.forearm))
					table.insert(out, ball("hand", seg, side, z, "limb", x1, J.hand))
				elseif name == "thigh" then
					local z = side * Look.LEG_DEPTH
					table.insert(out, ball("hip", seg, side, z, "limb", x0, J.hip))
					table.insert(out, rod("thigh", seg, side, z, x0, x1, Look.RADIUS.thigh))
					table.insert(out, ball("knee", seg, side, z, "limb", x1, J.knee))
				elseif name == "shank" then
					-- the collision shape stops short of the ankle; the drawing reaches it
					local z = side * Look.LEG_DEPTH
					local ankle = x1 + Rig.SHANK_TRIM
					table.insert(out, rod("shank", seg, side, z, x0, ankle, Look.RADIUS.shank))
					table.insert(out, ball("ankle", seg, side, z, "limb", ankle, J.ankle))
				elseif name == "foot" then
					local z = side * Look.LEG_DEPTH
					local F = Look.FOOT
					local thick = 2 * Rig.RADIUS.foot
					table.insert(
						out,
						box("foot", seg, side, z, "foot", x0 - F.heelExtra, x1 + F.toeExtra, thick, F.width)
					)
				end
			end
		end
	end
	return out
end

-- Where a shape is in the motion plane for a body at (x, y) turned by `a`: its centre (u, v)
-- and the in-plane angle of its local x axis. For rods, also the length between the ends.
function Look.place(p: Prim, x: number, y: number, a: number): (number, number, number, number)
	local c, s = math.cos(a), math.sin(a)
	if p.kind == "rod" then
		local mx, my = (p.ax + p.bx) / 2, (p.ay + p.by) / 2
		local dx, dy = p.bx - p.ax, p.by - p.ay
		return x + c * mx - s * my, y + s * mx + c * my, a + math.atan2(dy, dx), math.sqrt(dx * dx + dy * dy)
	end
	return x + c * p.ax - s * p.ay, y + s * p.ax + c * p.ay, a, 0
end

return Look
