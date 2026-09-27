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
--   anatomical = facing * sign * rel + offset
-- `facing` (+1 / -1) is which way the chest faces in the plane. A half twist mirrors
-- the body in the plane and flips `facing` (see Rig.mirror), so anatomical angles,
-- limits and pose targets keep their meaning whichever way the body faces.

-- (Headless tests load a mirrored copy with these requires rewritten to file paths; see tools/lune_mirror.luau.)
local Solver2D = require(script.Parent.Solver2D)
local Collide2D = require(script.Parent.Collide2D)
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

-- Foot geometry (P1.2). The foot capsule reaches FOOT_HEEL behind the ankle, so the feet
-- can push the body both forward and back when standing (a heel lever). The shank's
-- rounded lower end stops SHANK_TRIM short of the ankle (collision and drawing), so it
-- doesn't prop the heel off a flat foot. Both stay on the body axes (Rig.mirror needs that).
Rig.FOOT_HEEL = 0.15
Rig.SHANK_TRIM = 0.1

-- Extra rotational inertia for the light distal segments (mass and length unchanged).
-- Solver conditioning: a 0.2-mass foot or 0.45-mass forearm carrying the whole body's load
-- (landing on a foot, hanging from a forearm) is a large mass ratio for an iterative solver,
-- and violent impacts could push those joints up to ~15° past their limits. With these
-- factors the worst overshoot in the stability soak drops to under 3° (TESTING.md, P1.2).
-- Whole-body inertia changes by about 1%, so spin rates are unaffected.
-- Blended by `limbInertiaBoost` (0 = uniform capsules as in P1.1, 1 = this profile).
Rig.INERTIA_SCALE = { torso = 1, upperArm = 2, forearm = 4, thigh = 1, shank = 2, foot = 8 }

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
	-- Tuck off the bar (P1.2 feedback): the arms come in, hands toward the shins (compact).
	-- Under a spin the springs settle ~20-25° short of this, arms up by the chest (P1.2 round 2);
	-- aiming further in fixes the look but speeds the tuck and over-rotates backflip landings
	AirTuck = { shoulder = 110, elbow = 60, hip = 125, knee = 135, ankle = 90 },
	Pike = { shoulder = 15, elbow = 5, hip = 115, knee = 0, ankle = 100 },
	Arch = { shoulder = -25, elbow = 0, hip = -30, knee = 0, ankle = 100 },
	Crouch = { shoulder = 90, elbow = 10, hip = 70, knee = 90, ankle = 70 },
	Limp = {},
	-- Ground poses (P1.2 movement controller). Ankle > 90 = shank leaning forward over a
	-- flat foot (dorsiflexion); < 90 = pointing the toes (plantarflexion).
	GroundStand = { shoulder = 150, elbow = 15, hip = 8, knee = 10, ankle = 95 },
	GroundCrouch = { shoulder = 70, elbow = 15, hip = 107, knee = 100, ankle = 118 },
	GroundReach = { shoulder = -10, elbow = 0, hip = -8, knee = 0, ankle = 62 },
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
	facing: number, -- +1 or -1: which way the chest faces in the plane
	-- the straight body hanging from its hands: inertia about the grip, and how far below the
	-- grip its centre of mass is (the swing energy cap's reference, see Controller)
	hangInertia: number,
	hangRadius: number,
}

export type Placement = {
	pivot: string?, -- "hip" (default), "grip", "com" or "sole" (bottom of the foot)
	x: number,
	y: number,
	rot: number?, -- rotation of the whole rig (radians, counter-clockwise)
	vx: number?,
	vy: number?,
	w: number?, -- initial spin about the rig's centre of mass
	pose: string?, -- motor target pose after building (P1.1 scenarios)
	buildPose: string?, -- joint configuration to build in (default: straight, arms overhead)
	footFlat: boolean?, -- rotate the whole rig so the foot lies flat (overrides `rot`)
}

local function relFromAnatomical(anatRad: number, sign: number, offset: number, facing: number): number
	return facing * sign * (anatRad - offset)
end

local JOINT_SIGN = { shoulder = -1, elbow = -1, hip = 1, knee = -1, ankle = 1 }
local JOINT_OFFSET = { shoulder = 0, elbow = 0, hip = math.pi, knee = 0, ankle = 0 }

-- Rig-space geometry by forward kinematics: torso upright, facing +x, hip at the origin.
-- `pose` gives anatomical angles (degrees); missing joints use the straight body
-- (arms overhead, ankle 90). Returns joint points and each segment's (unwrapped) angle.
local function rigPoints(t: Tuning.Values, pose: { [string]: number }?)
	local T, UA, FA, TH, SH, FL =
		t.trunkLength, t.upperArmLength, t.forearmLength, t.thighLength, t.shankLength, t.footLength
	local function rel(name: string): number
		local default = if name == "ankle" then 90 else 0
		local anat = if pose and pose[name] then pose[name] else default
		return relFromAnatomical(rad(anat), JOINT_SIGN[name], JOINT_OFFSET[name], 1)
	end
	local aTorso = math.pi / 2
	local aUpper = aTorso + rel("shoulder")
	local aFore = aUpper + rel("elbow")
	local aThigh = aTorso + rel("hip")
	local aShank = aThigh + rel("knee")
	local aFoot = aShank + rel("ankle")
	local function add(p: { number }, len: number, a: number): { number }
		return { p[1] + len * cos(a), p[2] + len * sin(a) }
	end
	local hip = { 0, 0 }
	local shoulder = add(hip, T, aTorso)
	local elbow = add(shoulder, UA, aUpper)
	local grip = add(elbow, FA, aFore)
	local knee = add(hip, TH, aThigh)
	local ankle = add(knee, SH, aShank)
	local toe = add(ankle, FL, aFoot)
	local heel = add(ankle, -Rig.FOOT_HEEL, aFoot)
	return {
		heel = heel,
		hip = hip,
		shoulder = shoulder,
		elbow = elbow,
		grip = grip,
		knee = knee,
		ankle = ankle,
		toe = toe,
	}, {
		torso = aTorso,
		upperArm = aUpper,
		forearm = aFore,
		thigh = aThigh,
		shank = aShank,
		foot = aFoot,
	}
end

-- Builds the rig into `world` at `placement`. Returns the rig.
function Rig.build(world: Solver2D.World, t: Tuning.Values, placement: Placement): Rig
	local M = t.bodyMass
	local F, R = Rig.MASS_FRACTION, Rig.RADIUS
	local P, ANG = rigPoints(t, if placement.buildPose then Rig.POSES[placement.buildPose] else nil)
	local T = t.trunkLength

	-- 1. Segment definitions in rig space: start point, end point, mass, radius.
	--    Every segment body's local x-axis points from its proximal to its distal end.
	type Def = {
		name: string,
		a: { number },
		b: { number },
		mass: number,
		radius: number,
		paired: boolean,
		trimB: number?, -- shapes and drawing stop this far short of b
	}
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
		{
			name = "shank",
			a = P.knee,
			b = P.ankle,
			mass = M * F.shank,
			radius = R.shank,
			paired = true,
			trimB = Rig.SHANK_TRIM,
		},
		{ name = "foot", a = P.heel, b = P.toe, mass = M * F.foot, radius = R.foot, paired = true },
	}

	-- Built in `placement.buildPose` (default straight); the motors then pull it into `placement.pose`.

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
		local angle = ANG[d.name] -- unwrapped, so relative joint angles stay continuous
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
	local rot = if placement.footFlat then -ANG.foot else placement.rot or 0
	local cr, sr = cos(rot), sin(rot)
	local pivotX, pivotY = 0, 0
	local pivot = placement.pivot or "hip"
	if pivot == "grip" then
		pivotX, pivotY = P.grip[1], P.grip[2]
	elseif pivot == "sole" then
		-- lowest point of the foot capsule, below the middle of the foot
		pivotX = (P.heel[1] + P.toe[1]) / 2
		pivotY = math.min(P.heel[2], P.toe[2]) - R.foot
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
		facing = 1,
		hangInertia = 0,
		hangRadius = 0,
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
			inertia = s.inertia * (1 + ((Rig.INERTIA_SCALE[d.name] or 1) - 1) * t.limbInertiaBoost),
		})
		-- local endpoints relative to the centre of mass along the local x-axis
		local ax, ay = d.a[1] - s.cx, d.a[2] - s.cy
		local bx, by = d.b[1] - s.cx, d.b[2] - s.cy
		local ca, sa = cos(-s.angle), sin(-s.angle)
		local p0x, p0y = ca * ax - sa * ay, sa * ax + ca * ay
		local p1x, p1y = ca * bx - sa * by, sa * bx + ca * by
		local length = s.length
		if d.trimB then
			-- local x-axis runs from a to b, so trimming moves p1 back along it
			p1x -= d.trimB
			length -= d.trimB
		end
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
			length = length,
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
		{ name = "shoulder", A = S.torso, B = S.upperArm, at = P.shoulder },
		{ name = "elbow", A = S.upperArm, B = S.forearm, at = P.elbow },
		{ name = "hip", A = S.torso, B = S.thigh, at = P.hip },
		{ name = "knee", A = S.thigh, B = S.shank, at = P.knee },
		{ name = "ankle", A = S.shank, B = S.foot, at = P.ankle },
	}
	for _, js in jointSpecs do
		local wx, wy = toWorld(js.at[1], js.at[2])
		local joint = Solver2D.addRevolute(world, js.A.body, js.B.body, wx, wy, {
			name = js.name,
			enableLimit = true,
		})
		local rj: RigJoint = {
			name = js.name,
			joint = joint,
			sign = JOINT_SIGN[js.name],
			offset = JOINT_OFFSET[js.name],
			torqueKey = TORQUE_KEY[js.name],
		}
		table.insert(rig.joints, rj)
		rig.jointByName[js.name] = rj
	end
	Rig.setFacing(rig, 1)

	-- 6. The straight hang (arms overhead, as rigPoints builds with no pose), whatever the
	--    build pose: each segment's centre of mass sits at its start point minus its local offset.
	local SP, SANG = rigPoints(t, nil)
	local START = {
		torso = "hip",
		upperArm = "shoulder",
		forearm = "elbow",
		thigh = "hip",
		shank = "knee",
		foot = "heel",
	}
	local hI, hx, hy = 0, 0, 0
	for _, seg in rig.segments do
		local a, ang = SP[START[seg.name]], SANG[seg.name]
		local c, s = cos(ang), sin(ang)
		local dx = a[1] - (c * seg.p0x - s * seg.p0y) - SP.grip[1]
		local dy = a[2] - (s * seg.p0x + c * seg.p0y) - SP.grip[2]
		local b = seg.body
		hI += b.inertia + b.mass * (dx * dx + dy * dy)
		hx += b.mass * dx
		hy += b.mass * dy
	end
	rig.hangInertia = hI
	rig.hangRadius = math.sqrt(hx * hx + hy * hy) / M

	-- 7. Initial velocity: translation plus spin about the rig's centre of mass.
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
function Rig.jointAngle(rj: RigJoint, facing: number?): number
	local j = rj.joint
	return (facing or 1) * rj.sign * (j.bodyB.a - j.bodyA.a) + rj.offset
end

-- Sets which way the body faces and re-derives every joint's limits in solver terms.
function Rig.setFacing(rig: Rig, facing: number)
	rig.facing = if facing < 0 then -1 else 1
	for _, rj in rig.joints do
		local lim = Rig.LIMITS[rj.name]
		local r1 = relFromAnatomical(rad(lim[1]), rj.sign, rj.offset, rig.facing)
		local r2 = relFromAnatomical(rad(lim[2]), rj.sign, rj.offset, rig.facing)
		rj.joint.lower = math.min(r1, r2)
		rj.joint.upper = math.max(r1, r2)
	end
end

-- Unit of motor torque ("Mg·stud"): total mass x gravity x 1 stud, blended toward
-- normal gravity by `strengthGravityScaling` (1 = strength follows gravity, 0 = fixed).
function Rig.torqueUnit(rig: Rig, t: Tuning.Values): number
	local g = Tuning.effectiveGravity(t)
	local k = t.strengthGravityScaling
	return rig.mass * (g * k + t.gravity * (1 - k))
end

export type DriveOptions = {
	strength: { [string]: number }?, -- per-joint multiplier on the tuned max torque
	hertz: { [string]: number }?, -- per-joint spring frequency override
	dampingRatio: number?,
}

-- Drives every joint toward anatomical targets (degrees; nil = motor off).
function Rig.drive(rig: Rig, t: Tuning.Values, targets: { [string]: number }, options: DriveOptions?)
	local unitTorque = Rig.torqueUnit(rig, t)
	local strength = options and options.strength
	local hertz = options and options.hertz
	local zeta = (options and options.dampingRatio) or t.motorDampingRatio
	for _, rj in rig.joints do
		local j = rj.joint
		local targetDeg = targets[rj.name]
		if targetDeg == nil then
			j.enableSpring = false
			j.maxTorque = 0
		else
			local lim = Rig.LIMITS[rj.name]
			local anat = rad(math.clamp(targetDeg, lim[1], lim[2]))
			j.enableSpring = true
			j.target = relFromAnatomical(anat, rj.sign, rj.offset, rig.facing)
			j.maxTorque = t[rj.torqueKey] * unitTorque * ((strength and strength[rj.name]) or 1)
			j.springHertz = (hertz and hertz[rj.name]) or t.motorHertz
			j.springDampingRatio = zeta
		end
	end
end

-- Pushes the named pose (`rig.pose`) into the joints: the P1.1 / debug path.
-- Called every fixed step so live tuning and gravity changes apply immediately.
function Rig.applyMotors(rig: Rig, t: Tuning.Values)
	Rig.drive(rig, t, Rig.POSES[rig.pose] or Rig.POSES.Neutral)
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
		out[rj.name] = deg(Rig.jointAngle(rj, rig.facing))
	end
	return out
end

export type MassState = {
	mass: number,
	cx: number,
	cy: number,
	vx: number,
	vy: number,
	angularMomentum: number, -- about the centre of mass
	inertia: number, -- about the centre of mass
}

-- Whole-body centre of mass, momentum and inertia.
function Rig.massState(rig: Rig): MassState
	local m, mx, my, px, py = 0, 0, 0, 0, 0
	for _, seg in rig.segments do
		local b = seg.body
		m += b.mass
		mx += b.mass * b.x
		my += b.mass * b.y
		px += b.mass * b.vx
		py += b.mass * b.vy
	end
	local cx, cy, vx, vy = mx / m, my / m, px / m, py / m
	local L, I = 0, 0
	for _, seg in rig.segments do
		local b = seg.body
		local rx, ry = b.x - cx, b.y - cy
		L += b.inertia * b.w + b.mass * (rx * (b.vy - vy) - ry * (b.vx - vx))
		I += b.inertia + b.mass * (rx * rx + ry * ry)
	end
	return { mass = m, cx = cx, cy = cy, vx = vx, vy = vy, angularMomentum = L, inertia = I }
end

-- Whether the mirrored body (see Rig.mirror) would be clear of the world by `margin`.
-- Mirroring moves limbs across the long axis; near the ground or a block that could put
-- them inside it, so the controller only snaps when this is true.
function Rig.mirrorClear(rig: Rig, world: Solver2D.World, margin: number): boolean
	local ms = Rig.massState(rig)
	local axisA = rig.torso.a
	local ax, ay = cos(axisA), sin(axisA)
	local function reflect(x: number, y: number): (number, number)
		local rx, ry = x - ms.cx, y - ms.cy
		local d = ax * rx + ay * ry
		return ms.cx + 2 * d * ax - rx, ms.cy + 2 * d * ay - ry
	end
	for _, shape in world.bodyShapes do
		local b = shape.body
		local x0, y0 = Solver2D.worldPoint(b, shape.lax, shape.lay)
		local x1, y1 = Solver2D.worldPoint(b, shape.lbx, shape.lby)
		x0, y0 = reflect(x0, y0)
		x1, y1 = reflect(x1, y1)
		for _, ws in world.worldShapes do
			local poly = ws.polygon
			if poly then
				local n = Collide2D.capsulePolygon(x0, y0, x1, y1, shape.radius, poly, margin)
				for i = 1, n do
					if Collide2D.sep[i] < margin then
						return false
					end
				end
			end
		end
	end
	return true
end

-- Half-twist "mirror snap" (PHYSICS_DESIGN §6.3). Reflects the body's in-plane shape across
-- the line through its centre of mass along the torso axis and flips `facing`.
-- Conserves exactly: centre of mass, linear momentum, angular momentum and kinetic
-- energy (hence total energy). Joints stay attached (all anchors lie on body axes).
-- The world rotation continues in the same direction; only the shape is mirrored.
-- Intended for airborne use; the previous-step pose is mirrored too so rendering
-- interpolation stays consistent.
function Rig.mirror(rig: Rig)
	local ms = Rig.massState(rig)
	local cx, cy = ms.cx, ms.cy
	local omega = ms.angularMomentum / ms.inertia -- average (rigid) rotation rate
	local axisA = rig.torso.a
	local ax, ay = cos(axisA), sin(axisA)
	-- reflection across direction (ax, ay): r' = 2 (a·r) a - r
	local function reflect(rx: number, ry: number): (number, number)
		local d = ax * rx + ay * ry
		return 2 * d * ax - rx, 2 * d * ay - ry
	end
	local prevA = rig.torso.prevA
	for _, seg in rig.segments do
		local b = seg.body
		local rx, ry = b.x - cx, b.y - cy
		-- internal (shape) velocity: remove the common translation and rigid rotation
		local ux = b.vx - ms.vx + omega * ry
		local uy = b.vy - ms.vy - omega * rx
		local spin = b.w - omega
		local nrx, nry = reflect(rx, ry)
		local nux, nuy = reflect(ux, uy)
		b.x, b.y = cx + nrx, cy + nry
		b.a = 2 * axisA - b.a
		b.c, b.s = cos(b.a), sin(b.a)
		b.vx = ms.vx - omega * nry + nux
		b.vy = ms.vy + omega * nrx + nuy
		b.w = omega - spin
		-- previous-step pose (interpolation): mirror across the previous torso axis line
		local pax, pay = cos(prevA), sin(prevA)
		local prx, pry = b.prevX - cx, b.prevY - cy
		local pd = pax * prx + pay * pry
		b.prevX, b.prevY = cx + 2 * pd * pax - prx, cy + 2 * pd * pay - pry
		b.prevA = 2 * prevA - b.prevA
	end
	-- joints: limits follow the new facing; warm-start impulses are mirrored
	Rig.setFacing(rig, -rig.facing)
	for _, rj in rig.joints do
		local j = rj.joint
		j.impulseX, j.impulseY = reflect(j.impulseX, j.impulseY)
		j.springImpulse = -j.springImpulse
		j.frictionImpulse = -j.frictionImpulse
		j.lowerImpulse, j.upperImpulse = j.upperImpulse, j.lowerImpulse
	end
end

return Rig
