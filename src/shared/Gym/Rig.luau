--!strict
-- Rig: the gymnast's physical body, built on Solver2D.
--
-- Six rigid bodies in the motion plane (left/right limbs are paired, as the
-- design specifies): torso+head, upper arms, forearms, thighs, shanks, feet.
-- Five revolute joints (shoulder, elbow, hip, knee, ankle), each with angle
-- limits and a torque-limited spring motor that pulls toward a pose.
--
-- Anatomical joint angles (degrees, 0 = straight body with arms overhead,
-- positive = flexion toward the front of the body):
--   shoulder  arms toward the chest (90 = arms forward, 180 = arms down)
--   elbow     forearm bends toward the front
--   hip       thighs toward the chest (pike/tuck)
--   knee      shank folds back
--   ankle     foot angle to the shank (90 = foot square to the leg)
--
-- The solver uses rel = bodyB.a - bodyA.a. Each joint maps anatomical <-> rel with
--   anatomical = sign * rel + offset

-- (Headless tests load a mirrored copy with these requires rewritten to file paths; see tools/lune_mirror.luau.)
local Solver2D = require(script.Parent.Solver2D)
local Tuning = require(script.Parent.Tuning)

local rad, deg = math.rad, math.deg
local cos, sin = math.cos, math.sin

local Rig = {}

-- Share of total body mass per paired segment (sums to 1).
Rig.MASS_FRACTION = {
	trunk = 0.43,
	head = 0.08,
	upperArm = 0.055,
	forearm = 0.045,
	thigh = 0.28,
	shank = 0.09,
	foot = 0.02,
}

-- Collision/visual radii (studs).
Rig.RADIUS = {
	trunk = 0.42,
	head = 0.45,
	upperArm = 0.17,
	forearm = 0.15,
	thigh = 0.23,
	shank = 0.18,
	foot = 0.12,
}

Rig.HEAD_OFFSET = 0.7 -- head centre above the shoulder line

-- Anatomical limits (degrees).
Rig.LIMITS = {
	shoulder = { -45, 180 },
	elbow = { -5, 150 },
	hip = { -40, 150 },
	knee = { -2, 150 },
	ankle = { 60, 120 },
}

-- Motor target poses (anatomical degrees). "Limp" turns the motors off.
Rig.POSES = {
	Neutral = { shoulder = 8, elbow = 5, hip = 8, knee = 5, ankle = 90 },
	Tuck = { shoulder = 25, elbow = 20, hip = 125, knee = 135, ankle = 90 },
	Pike = { shoulder = 15, elbow = 5, hip = 115, knee = 0, ankle = 100 },
	Arch = { shoulder = -25, elbow = 0, hip = -30, knee = 0, ankle = 100 },
	Crouch = { shoulder = 90, elbow = 10, hip = 70, knee = 90, ankle = 70 },
	Limp = {},
}
Rig.POSE_ORDER = { "Neutral", "Tuck", "Pike", "Arch", "Crouch", "Limp" }

local JOINT_ORDER = { "shoulder", "elbow", "hip", "knee", "ankle" }
Rig.JOINT_ORDER = JOINT_ORDER

local TORQUE_KEY = {
	shoulder = "shoulderMaxTorque",
	elbow = "elbowMaxTorque",
	hip = "hipMaxTorque",
	knee = "kneeMaxTorque",
	ankle = "ankleMaxTorque",
}

export type Segment = {
	name: string,
	body: Solver2D.Body,
	length: number,
	radius: number,
	paired: boolean, -- drawn as a left/right pair
	-- proximal and distal points in the body's local frame
	p0x: number,
	p0y: number,
	p1x: number,
	p1y: number,
}

export type RigJoint = {
	name: string,
	joint: Solver2D.Joint,
	sign: number,
	offset: number, -- radians
	torqueKey: string,
}

export type Rig = {
	segments: { Segment },
	segmentByName: { [string]: Segment },
	joints: { RigJoint },
	jointByName: { [string]: RigJoint },
	torso: Solver2D.Body,
	forearm: Solver2D.Body,
	headLocalX: number,
	pose: string,
	mass: number,
}

export type Placement = {
	pivot: string?, -- "hip" (default), "grip" or "com"
	x: number,
	y: number,
	rot: number?, -- rotation of the whole rig (radians, counter-clockwise)
	vx: number?,
	vy: number?,
	w: number?, -- initial spin about the rig's centre of mass
	pose: string?, -- initial joint configuration (defaults to straight)
}

-- Rig-space geometry: straight body standing upright, arms overhead, facing +x, hip at the origin.
local function rigPoints(t: Tuning.Values)
	local T, UA, FA, TH, SH, FL =
		t.trunkLength, t.upperArmLength, t.forearmLength, t.thighLength, t.shankLength, t.footLength
	return {
		hip = { 0, 0 },
		shoulder = { 0, T },
		elbow = { 0, T + UA },
		grip = { 0, T + UA + FA },
		knee = { 0, -TH },
		ankle = { 0, -TH - SH },
		toe = { FL, -TH - SH },
	}
end

-- Builds the rig into `world` at `placement`. Returns the rig.
function Rig.build(world: Solver2D.World, t: Tuning.Values, placement: Placement): Rig
	local M = t.bodyMass
	local F, R = Rig.MASS_FRACTION, Rig.RADIUS
	local P = rigPoints(t)
	local T = t.trunkLength

	-- 1. Segment definitions in rig space: start point, end point, mass, radius.
	--    Every segment body's local x-axis points from its proximal to its distal end.
	type Def = { name: string, a: { number }, b: { number }, mass: number, radius: number, paired: boolean }
	local defs: { Def } = {
		{
			name = "torso",
			a = P.hip,
			b = P.shoulder,
			mass = M * (F.trunk + F.head),
			radius = R.trunk,
			paired = false,
		},
		{
			name = "upperArm",
			a = P.shoulder,
			b = P.elbow,
			mass = M * F.upperArm,
			radius = R.upperArm,
			paired = true,
		},
		{
			name = "forearm",
			a = P.elbow,
			b = P.grip,
			mass = M * F.forearm,
			radius = R.forearm,
			paired = true,
		},
		{ name = "thigh", a = P.hip, b = P.knee, mass = M * F.thigh, radius = R.thigh, paired = true },
		{ name = "shank", a = P.knee, b = P.ankle, mass = M * F.shank, radius = R.shank, paired = true },
		{ name = "foot", a = P.ankle, b = P.toe, mass = M * F.foot, radius = R.foot, paired = true },
	}

	-- The rig is always built straight; the motors then pull it into `placement.pose`.

	-- 2. Compute each segment's centre of mass, angle and inertia in rig space.
	type Seg = {
		def: Def,
		cx: number,
		cy: number,
		angle: number,
		inertia: number,
		length: number,
		headLocalX: number?,
	}
	local segs: { Seg } = {}
	for _, d in defs do
		local ax, ay, bx, by = d.a[1], d.a[2], d.b[1], d.b[2]
		local dx, dy = bx - ax, by - ay
		local L = math.sqrt(dx * dx + dy * dy)
		local angle = math.atan2(dy, dx)
		local r = d.radius
		if d.name == "torso" then
			-- trunk rod + head, compound centre of mass along the torso axis
			local mt, mh = M * F.trunk, M * F.head
			local trunkC = T / 2
			local headC = T + Rig.HEAD_OFFSET
			local yc = (mt * trunkC + mh * headC) / (mt + mh)
			local I = mt * (T * T + 4 * r * r) / 12
				+ mt * (trunkC - yc) ^ 2
				+ mh * 0.5 * R.head * R.head
				+ mh * (headC - yc) ^ 2
			table.insert(segs, {
				def = d,
				cx = ax + dx / L * yc,
				cy = ay + dy / L * yc,
				angle = angle,
				inertia = I,
				length = L,
				headLocalX = headC - yc,
			})
		else
			table.insert(segs, {
				def = d,
				cx = (ax + bx) / 2,
				cy = (ay + by) / 2,
				angle = angle,
				inertia = d.mass * (L * L + 4 * r * r) / 12,
				length = L,
			})
		end
	end

	-- 3. Placement transform (rig space -> world).
	local rot = placement.rot or 0
	local cr, sr = cos(rot), sin(rot)
	local pivotX, pivotY = 0, 0
	local pivot = placement.pivot or "hip"
	if pivot == "grip" then
		pivotX, pivotY = P.grip[1], P.grip[2]
	elseif pivot == "com" then
		local mx, my, m = 0, 0, 0
		for _, s in segs do
			mx += s.def.mass * s.cx
			my += s.def.mass * s.cy
			m += s.def.mass
		end
		pivotX, pivotY = mx / m, my / m
	end
	local function toWorld(px: number, py: number): (number, number)
		local lx, ly = px - pivotX, py - pivotY
		return placement.x + cr * lx - sr * ly, placement.y + sr * lx + cr * ly
	end

	-- 4. Bodies and shapes.
	local rig: Rig = {
		segments = {},
		segmentByName = {},
		joints = {},
		jointByName = {},
		torso = nil :: any,
		forearm = nil :: any,
		headLocalX = 0,
		pose = placement.pose or "Neutral",
		mass = M,
	}
	local limbFriction = t.friction
	for _, s in segs do
		local d = s.def
		local wx, wy = toWorld(s.cx, s.cy)
		local body = Solver2D.addBody(world, {
			name = d.name,
			x = wx,
			y = wy,
			a = s.angle + rot,
			mass = d.mass,
			inertia = s.inertia,
		})
		-- local endpoints relative to the centre of mass along the local x-axis
		local ax, ay = d.a[1] - s.cx, d.a[2] - s.cy
		local bx, by = d.b[1] - s.cx, d.b[2] - s.cy
		local ca, sa = cos(-s.angle), sin(-s.angle)
		local p0x, p0y = ca * ax - sa * ay, sa * ax + ca * ay
		local p1x, p1y = ca * bx - sa * by, sa * bx + ca * by
		local friction = if d.name == "forearm" then t.handFriction else limbFriction
		local shapeDef = { friction = friction, restitution = t.restitution, tag = d.name }
		if d.name == "torso" then
			-- trunk capsule slightly shorter than hip->shoulder so it does not poke through the joints
			Solver2D.addCapsule(world, body, p0x + 0.15, p0y, p1x - 0.1, p1y, d.radius, shapeDef)
			Solver2D.addCircle(world, body, s.headLocalX :: number, 0, Rig.RADIUS.head, {
				friction = limbFriction,
				restitution = t.restitution,
				tag = "head",
			})
			rig.torso = body
			rig.headLocalX = s.headLocalX :: number
		else
			Solver2D.addCapsule(world, body, p0x, p0y, p1x, p1y, d.radius, shapeDef)
		end
		if d.name == "forearm" then
			rig.forearm = body
		end
		local seg: Segment = {
			name = d.name,
			body = body,
			length = s.length,
			radius = d.radius,
			paired = d.paired,
			p0x = p0x,
			p0y = p0y,
			p1x = p1x,
			p1y = p1y,
		}
		table.insert(rig.segments, seg)
		rig.segmentByName[d.name] = seg
	end

	-- 5. Joints at the shared points.
	local S = rig.segmentByName
	local jointSpecs = {
		{ name = "shoulder", A = S.torso, B = S.upperArm, at = P.shoulder, sign = -1, offset = 0 },
		{ name = "elbow", A = S.upperArm, B = S.forearm, at = P.elbow, sign = -1, offset = 0 },
		{ name = "hip", A = S.torso, B = S.thigh, at = P.hip, sign = 1, offset = math.pi },
		{ name = "knee", A = S.thigh, B = S.shank, at = P.knee, sign = -1, offset = 0 },
		{ name = "ankle", A = S.shank, B = S.foot, at = P.ankle, sign = 1, offset = 0 },
	}
	for _, js in jointSpecs do
		local wx, wy = toWorld(js.at[1], js.at[2])
		local lim = Rig.LIMITS[js.name]
		local r1 = (rad(lim[1]) - js.offset) * js.sign
		local r2 = (rad(lim[2]) - js.offset) * js.sign
		local joint = Solver2D.addRevolute(world, js.A.body, js.B.body, wx, wy, {
			name = js.name,
			enableLimit = true,
			lower = math.min(r1, r2),
			upper = math.max(r1, r2),
		})
		local rj: RigJoint = {
			name = js.name,
			joint = joint,
			sign = js.sign,
			offset = js.offset,
			torqueKey = TORQUE_KEY[js.name],
		}
		table.insert(rig.joints, rj)
		rig.jointByName[js.name] = rj
	end

	-- 6. Initial velocity: translation plus spin about the rig's centre of mass.
	local vx, vy, w = placement.vx or 0, placement.vy or 0, placement.w or 0
	if vx ~= 0 or vy ~= 0 or w ~= 0 then
		local cx, cy = Rig.centerOfMass(rig)
		for _, seg in rig.segments do
			local b = seg.body
			b.vx = vx - w * (b.y - cy)
			b.vy = vy + w * (b.x - cx)
			b.w = w
		end
	end

	Rig.applyMotors(rig, t)
	return rig
end

function Rig.centerOfMass(rig: Rig): (number, number)
	local mx, my, m = 0, 0, 0
	for _, seg in rig.segments do
		local b = seg.body
		mx += b.mass * b.x
		my += b.mass * b.y
		m += b.mass
	end
	return mx / m, my / m
end

-- Anatomical angle (radians) of a rig joint from the current body angles.
function Rig.jointAngle(rj: RigJoint): number
	local j = rj.joint
	return rj.sign * (j.bodyB.a - j.bodyA.a) + rj.offset
end

-- Pushes pose targets and motor strength/frequency into the solver joints.
-- Called every fixed step so live tuning and gravity changes apply immediately.
function Rig.applyMotors(rig: Rig, t: Tuning.Values)
	local pose = Rig.POSES[rig.pose] or Rig.POSES.Neutral
	local g = Tuning.effectiveGravity(t)
	local unitTorque = rig.mass * g -- Mg·stud
	for _, rj in rig.joints do
		local j = rj.joint
		local targetDeg = pose[rj.name]
		if targetDeg == nil then
			j.enableSpring = false
			j.maxTorque = 0
		else
			local lim = Rig.LIMITS[rj.name]
			local anat = rad(math.clamp(targetDeg, lim[1], lim[2]))
			j.enableSpring = true
			j.target = (anat - rj.offset) * rj.sign
			j.maxTorque = t[rj.torqueKey] * unitTorque
			j.springHertz = t.motorHertz
			j.springDampingRatio = t.motorDampingRatio
		end
	end
end

function Rig.setPose(rig: Rig, name: string)
	assert(Rig.POSES[name], `unknown pose '{name}'`)
	rig.pose = name
end

-- World position of the grip point (end of the forearms).
function Rig.gripPoint(rig: Rig): (number, number)
	local seg = rig.segmentByName.forearm
	return Solver2D.worldPoint(seg.body, seg.p1x, seg.p1y)
end

-- Anatomical angles in degrees (debug readout).
function Rig.jointAnglesDeg(rig: Rig): { [string]: number }
	local out = {}
	for _, rj in rig.joints do
		out[rj.name] = deg(Rig.jointAngle(rj))
	end
	return out
end

return Rig
