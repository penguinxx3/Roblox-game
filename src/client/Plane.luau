--!strict
-- Plane: maps the simulation's 2D motion plane into the 3D world.
--
-- Simulation (u, v) -> world (X = u, Y = v, Z = depth). The camera looks along -Z,
-- so +u is screen-right and +v is screen-up. Paired limbs are drawn at ±PAIR_DEPTH.

local Plane = {}

Plane.PAIR_DEPTH = 0.32
Plane.NEAR = 1 -- near-side limb (closer to the camera)
Plane.FAR = -1

function Plane.point(u: number, v: number, depth: number?): Vector3
	return Vector3.new(u, v, depth or 0)
end

-- CFrame whose X axis points along angle `a` in the plane (for cylinders along X).
function Plane.along(u: number, v: number, a: number, depth: number?): CFrame
	return CFrame.new(u, v, depth or 0) * CFrame.Angles(0, 0, a)
end

return Plane
