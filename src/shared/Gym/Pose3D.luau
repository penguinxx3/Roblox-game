--!strict
-- Pose3D: the 2.5D presentation math shared by the renderer and the tests (no Roblox types).
--
-- The simulation is planar: (u, v) in the motion plane. The renderer places it in 3D with
-- depth z (paired limbs at ±pairDepth, everything else at 0) and turns the whole body by the
-- twist angle psi about its long axis: the line through the centre of mass along the torso.
-- Rotation follows the right-hand rule about the torso direction (head-ward), so +psi turns
-- the chest from the plane toward +z.
--
-- When |psi| passes 90° the controller mirrors the planar body across that same line and
-- shifts psi by 180° (Controller.updateTwist). Rotating a mirrored body by psi - 180° puts
-- every point where the unmirrored body rotated by psi would be, except that the left and
-- right copies of the paired limbs trade places, which is invisible because they are drawn
-- alike. The Twist tests check this continuity on the actual rendered points.

local Pose3D = {}

-- Turns the point (u, v, z) by psi about the axis through (cu, cv, 0) with in-plane
-- direction angle `axisAngle`. Returns the turned (u, v, z).
function Pose3D.twist(
	u: number,
	v: number,
	z: number,
	cu: number,
	cv: number,
	axisAngle: number,
	psi: number
): (number, number, number)
	if psi == 0 then
		return u, v, z
	end
	local ax, ay = math.cos(axisAngle), math.sin(axisAngle)
	local du, dv = u - cu, v - cv
	local along = du * ax + dv * ay
	local across = -du * ay + dv * ax -- component along n = (-ay, ax)
	local c, s = math.cos(psi), math.sin(psi)
	local across2 = across * c - z * s
	local z2 = across * s + z * c
	return cu + along * ax - across2 * ay, cv + along * ay + across2 * ax, z2
end

export type Frame = {
	psi: number,
	cu: number, -- centre of mass (interpolated)
	cv: number,
	axisAngle: number, -- torso direction (interpolated)
}

-- The twist frame for drawing `sim` at interpolation `alpha` (between the last two steps).
-- `bodyPose(body, alpha)` returns the interpolated (u, v, angle) of a body.
function Pose3D.frame(
	rig: any,
	psi: number,
	alpha: number,
	bodyPose: (any, number) -> (number, number, number)
): Frame
	local m, mu, mv = 0, 0, 0
	for _, seg in rig.segments do
		local b = seg.body
		local u, v = bodyPose(b, alpha)
		m += b.mass
		mu += b.mass * u
		mv += b.mass * v
	end
	local _, _, a = bodyPose(rig.torso, alpha)
	return { psi = psi, cu = mu / m, cv = mv / m, axisAngle = a }
end

export type Point = { name: string, side: number, u: number, v: number, z: number }

-- Every drawn segment end point in 3D (twist applied), for tests and debug drawing.
-- `side` is -1 / +1 for the far / near copy of a paired limb, 0 otherwise.
function Pose3D.points(
	rig: any,
	f: Frame,
	alpha: number,
	pairDepth: number,
	bodyPose: (any, number) -> (number, number, number)
): { Point }
	local out: { Point } = {}
	for _, seg in rig.segments do
		local x, y, a = bodyPose(seg.body, alpha)
		local c, s = math.cos(a), math.sin(a)
		local sides: { number } = if seg.paired then { -1, 1 } else { 0 }
		for _, side in sides do
			local ends: { { number } } = { { seg.p0x, seg.p0y }, { seg.p1x, seg.p1y } }
			for k, p in ends do
				local u = x + c * p[1] - s * p[2]
				local v = y + s * p[1] + c * p[2]
				local tu, tv, tz = Pose3D.twist(u, v, side * pairDepth, f.cu, f.cv, f.axisAngle, f.psi)
				table.insert(out, { name = `{seg.name}{k - 1}`, side = side, u = tu, v = tv, z = tz })
			end
		end
	end
	return out
end

return Pose3D
