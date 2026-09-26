--!strict
-- Controller: turns player input into muscle commands, and tracks movement states (P1.2).
--
-- Everything the player does goes through the body's joint motors (internal torques)
-- or, for Let Go, through removing the grip joint. There are no scripted animations:
-- the controller only chooses motor targets, stiffness and strength, and the solver
-- produces the motion. Optional assists are separate knobs: swingAssist and release shaping
-- default to pure physics; balanceAssist (ground only, never in flight) is on by default
-- because a planar pair of feet can't take a step to catch itself.
--
-- Modes (derived each step from the grip joint and the contacts of the previous step):
--   grip    hanging from a grip joint: Arch/Tuck/Pike shape the swing, Let Go releases
--   air     no grip, no ground support: Arch/Tuck/Pike shape the flight, Twist spins
--   ground  standing on the feet: stand/crouch/reach with balance; releasing Tuck from a
--           crouch pushes off (a physical jump); landings are absorbed by the legs
--   fallen  touching the world with anything but the feet, or tipped over: shape control
--           only (the body stays physical); Reset puts it back
--
-- Twist is a render-level rotation `psi` about the body's long axis. The planar body
-- never leaves the plane; when |psi| passes 90° the body is mirrored in the plane
-- (Rig.mirror, which conserves momentum, angular momentum and energy exactly) and psi
-- jumps by 180°, which is visually continuous (PHYSICS_DESIGN §6.3).
--
-- Input presses are counters (see Input.luau): every increase since the last step is
-- acted on at the next step, so presses are never lost in slow motion or at any frame rate.

local Solver2D = require(script.Parent.Solver2D)
local Tuning = require(script.Parent.Tuning)
local Rig = require(script.Parent.Rig)
local Input = require(script.Parent.Input)

local Controller = {}

local pi = math.pi
local TAU = 2 * pi
local exp = math.exp
local abs = math.abs
local min, max = math.min, math.max

local JOINTS = Rig.JOINT_ORDER
local LEG: { [string]: boolean } = { hip = true, knee = true, ankle = true }
local LEG_JOINTS = { "ankle", "knee", "hip" }
local YIELD_JOINTS = { "knee", "ankle" } -- give way when absorbing a landing

export type State = {
	mode: string,
	consumed: { letGo: number, grab: number, twistLeft: number, twistRight: number },
	-- smoothed shape targets (anatomical degrees) and their rates (deg/s)
	shape: { [string]: number },
	shapeRate: { [string]: number },
	targets: { [string]: number }, -- last targets sent to the motors (debug readout)
	-- twist (render rotation about the long axis, radians)
	psi: number,
	prevPsi: number,
	psiRate: number,
	twistSpin: number, -- momentum mode: commanded direction (-1, 0, 1)
	halfTwists: number, -- half twists since the last takeoff or release
	-- ground
	footContacts: number,
	bodyContact: boolean,
	supportX: number,
	supportY: number, -- ground height under the feet
	footMinX: number, -- horizontal extent of the foot (heel to toe)
	footMaxX: number,
	lastSupportTime: number,
	crouchDepth: number, -- 0 = standing, 1 = full crouch (measured from the knee angle)
	wasTucking: boolean,
	pushTimer: number, -- > 0 while a jump push is running
	pushLean: number, -- trunk's forward lean when the push started (radians, per unit crouch depth)
	absorbing: boolean, -- landing: the legs yield (pure damping) until the fall is stopped
	absorbTimer: number, -- longest remaining absorb time
	prevComVY: number,
	-- swing
	gripInertia: number,
	prevGripInertia: number,
	swingRate: number, -- rotation rate about the grip (rad/s)
	swingAssistTorque: number, -- last assist/cap torque about the grip (debug)
	-- timeline (simulation time, s)
	modeTime: number, -- time spent in the current mode
	lastEvent: string,
	debugCop: number,
	debugMoment: number,
}

local function blank(): { [string]: number }
	local t = {}
	for _, name in JOINTS do
		t[name] = 0
	end
	return t
end

-- New controller state for `sim` (call after the world is built). Press counters are
-- synced to the current input, so a press made before a reset can't fire after it.
function Controller.new(sim: any): State
	local rig: Rig.Rig = sim.rig
	local input: Input.Frame = sim.input
	local st: State = {
		mode = if sim.grip then "grip" else "air",
		consumed = {
			letGo = input.letGoPresses,
			grab = input.grabPresses,
			twistLeft = input.twistLeftPresses,
			twistRight = input.twistRightPresses,
		},
		shape = blank(),
		shapeRate = blank(),
		targets = blank(),
		psi = 0,
		prevPsi = 0,
		psiRate = 0,
		twistSpin = 0,
		halfTwists = 0,
		footContacts = 0,
		bodyContact = false,
		supportX = 0,
		supportY = 0,
		footMinX = 0,
		footMaxX = 0,
		lastSupportTime = -math.huge,
		crouchDepth = 0,
		wasTucking = false,
		pushTimer = 0,
		pushLean = 0,
		absorbing = false,
		absorbTimer = 0,
		prevComVY = 0,
		gripInertia = 0,
		prevGripInertia = 0,
		swingRate = 0,
		swingAssistTorque = 0,
		modeTime = 0,
		lastEvent = "",
		debugCop = 0,
		debugMoment = 0,
	}
	-- start the smoothed targets at the body's current angles: no jump on the first step
	local angles = Rig.jointAnglesDeg(rig)
	for _, name in JOINTS do
		st.shape[name] = angles[name]
		st.targets[name] = angles[name]
	end
	return st
end

local function event(sim: any, st: State, kind: string, detail: string?)
	table.insert(sim.events, { kind = kind, step = sim.stepCount, detail = detail })
	st.lastEvent = kind
end

local function setMode(sim: any, st: State, mode: string)
	if st.mode ~= mode then
		st.mode = mode
		st.modeTime = 0
	end
end

-- Signed torso lean from vertical (radians), wrapped to (-pi, pi].
local function torsoTilt(rig: Rig.Rig): number
	local d = (rig.torso.a - pi / 2) % TAU
	if d > pi then
		d -= TAU
	end
	return d
end

-- Feet and body contacts from the last step's contact list. Shank contacts right at the
-- ankle (a steep landing on the heel) also count as foot support.
local HEEL_RANGE = 0.35 -- studs from the ankle
local STAND_COM_HEIGHT = 2.7 -- centre of mass above the feet when standing (studs)
local REFLEX_KNEE = 15 -- soft knees for landing (degrees)
local CAPTURE_LEAD = 0.5 -- share of the pendulum capture-point lead used to place the feet
local SWING_CAP_RATE = 20 -- how fast swing energy above the cap is removed (1/s)
local SWING_CAP_MAX = 2 -- largest braking torque of the swing cap (Mg·stud)
local LANDED_SPEED = 0.3 -- a landing is absorbed once the fall has slowed below this (studs/s)
local MIRROR_CLEARANCE = 0.05 -- a half-twist snap needs this much room around the mirrored body (studs)
local function scanContacts(sim: any, st: State)
	local rig: Rig.Rig = sim.rig
	local ankle = rig.jointByName.ankle.joint
	local ankleX, ankleY = Solver2D.worldPoint(ankle.bodyA, ankle.lax, ankle.lay)
	local feet, body, lowY = 0, false, math.huge
	for _, c: Solver2D.ContactPoint in sim.world.contacts do
		if c.normalImpulse <= 0 and c.separation > 0.005 then
			continue -- speculative (not touching yet)
		end
		local tag = c.shapeA.tag
		local wx, wy = Solver2D.worldPoint(c.bodyA, c.lax, c.lay)
		local isFoot = tag == "foot"
			or (tag == "shank" and (wx - ankleX) ^ 2 + (wy - ankleY) ^ 2 < HEEL_RANGE * HEEL_RANGE)
		if isFoot and -c.ny > 0.5 then
			feet += 1
			lowY = min(lowY, wy)
		elseif not isFoot then
			body = true
		end
	end
	st.footContacts = feet
	st.bodyContact = body
	if feet > 0 then
		-- balance aims at the middle of the foot, whichever parts of it touch
		local foot = rig.segmentByName.foot
		local hx = Solver2D.worldPoint(foot.body, foot.p0x, foot.p0y)
		local tx = Solver2D.worldPoint(foot.body, foot.p1x, foot.p1y)
		st.supportX = (hx + tx) / 2
		st.supportY = lowY
		st.footMinX, st.footMaxX = min(hx, tx), max(hx, tx)
	end
end

-- Ground control rates follow gravity: a body can't crouch faster than it can fall, and
-- balance works on the time scale of a falling pendulum (sqrt(length / g)). With lower
-- gravity (moon) standing, crouching, balancing and the standing posture springs play out
-- proportionally slower, the same way everything else gravity-driven does. Muscle strength
-- (the push, holding a tuck against a fast spin) is set separately by strengthGravityScaling.
-- Ground timers (push, landing bend, grace) and landing speeds are scaled the same way.
local function groundTimeScale(t: Tuning.Values): number
	return math.sqrt(Tuning.effectiveGravity(t) / t.gravity)
end

----------------------------------------------------------------------------------------------------
-- Shape targets
----------------------------------------------------------------------------------------------------

local POSES = Rig.POSES
local standingMuscles: (sim: any, st: State, t: Tuning.Values) -> ()
local balanceAssist: (sim: any, st: State, t: Tuning.Values) -> ()

-- Air / grip shape: Neutral blended toward Tuck, Arch and Pike (PHYSICS_DESIGN §3).
local function airTargets(input: Input.Frame, out: { [string]: number })
	local tW, aW, pW = Input.shapeWeights(input)
	local N, T, A, P = POSES.Neutral, POSES.Tuck, POSES.Arch, POSES.Pike
	for _, name in JOINTS do
		local n = N[name]
		out[name] = n + tW * (T[name] - n) + aW * (A[name] - n) + pW * (P[name] - n)
	end
end

-- Ground shape: stand blended toward crouch (Tuck or Pike) and reach (Arch).
local function groundTargets(input: Input.Frame, out: { [string]: number })
	local tW, aW, pW = Input.shapeWeights(input)
	local crouchW = min(tW + pW, 1)
	aW = min(aW, 1 - crouchW)
	local S, C, R = POSES.GroundStand, POSES.GroundCrouch, POSES.GroundReach
	for _, name in JOINTS do
		local s = S[name]
		out[name] = s + crouchW * (C[name] - s) + aW * (R[name] - s)
	end
end

-- Critically damped second-order filter toward `goal` (exact update, stable for any step).
-- Closing (flexing) and opening use separate frequencies.
local function smoothShape(
	st: State,
	goal: { [string]: number },
	t: Tuning.Values,
	h: number,
	fixedHertz: number?
)
	for _, name in JOINTS do
		local x, v = st.shape[name], st.shapeRate[name]
		local g = goal[name]
		local w = TAU * (fixedHertz or (if g > x then t.shapeFreqClose else t.shapeFreqOpen))
		local e = x - g
		local k = v + w * e
		local decay = exp(-w * h)
		st.shape[name] = g + (e + k * h) * decay
		st.shapeRate[name] = (v - w * k * h) * decay
	end
end

----------------------------------------------------------------------------------------------------
-- Whole-body torque about a point (assists and caps)
----------------------------------------------------------------------------------------------------

-- Applies external forces that give every rig body the same angular acceleration about
-- (px, py): a pure rotation of the whole body about that point with total torque `tau`.
local function applyTorqueAbout(rig: Rig.Rig, px: number, py: number, inertia: number, tau: number)
	if tau == 0 or inertia <= 0 then
		return
	end
	local alpha = tau / inertia
	for _, seg in rig.segments do
		local b = seg.body
		local rx, ry = b.x - px, b.y - py
		Solver2D.applyForce(b, -alpha * b.mass * ry, alpha * b.mass * rx)
		Solver2D.applyTorque(b, alpha * b.inertia)
	end
end

----------------------------------------------------------------------------------------------------
-- Mode handlers
----------------------------------------------------------------------------------------------------

local function updateSwing(sim: any, st: State, t: Tuning.Values, unitTorque: number, h: number)
	local grip: Solver2D.Joint = sim.grip
	grip.frictionTorque = t.gripFriction * unitTorque
	local rig: Rig.Rig = sim.rig
	local anchor = grip.bodyA
	local px, py = Solver2D.worldPoint(anchor, grip.lax, grip.lay)
	local avx, avy = Solver2D.pointVelocity(anchor, px, py)
	local I, L, comVY, m, mx, my = 0, 0, 0, 0, 0, 0
	for _, seg in rig.segments do
		local b = seg.body
		local rx, ry = b.x - px, b.y - py
		I += b.inertia + b.mass * (rx * rx + ry * ry)
		L += b.inertia * b.w + b.mass * (rx * (b.vy - avy) - ry * (b.vx - avx))
		comVY += b.mass * (b.vy - avy)
		m += b.mass
		mx += b.mass * rx
		my += b.mass * ry
	end
	comVY /= m
	mx /= m
	my /= m
	local omega = L / I
	st.prevGripInertia = if st.gripInertia > 0 then st.gripInertia else I
	st.gripInertia = I
	st.swingRate = omega
	-- energy cap: the swing may carry at most the energy of passing the bottom at
	-- maxSwingSpeed; any excess is braked away (quickly but smoothly)
	local g = Tuning.effectiveGravity(t)
	local energy = 0.5 * I * omega * omega + m * g * my
	local cap = 0.5 * I * t.maxSwingSpeed * t.maxSwingSpeed - m * g * math.sqrt(mx * mx + my * my)
	local excess = energy - cap
	local tau = 0
	if excess > 0 then
		local brake = excess * SWING_CAP_RATE / max(abs(omega), 1)
		tau -= (if omega > 0 then 1 else -1) * min(brake, SWING_CAP_MAX * unitTorque)
	else
		-- optional assist: only below the cap, and only while the shape change is in phase
		-- (closing while swinging up)
		local dI = (I - st.prevGripInertia) / h
		if t.swingAssist > 0 and dI < 0 and comVY > 0 then
			tau += t.swingAssist * -dI * omega
		end
	end
	st.swingAssistTorque = tau
	applyTorqueAbout(rig, px, py, I, tau)
end

-- Let Go: remove the grip joint. The bodies keep their velocities, so momentum is continuous
-- by construction. Optional shaping (defaults = pure physics) acts about the centre of mass.
local function release(sim: any, st: State, t: Tuning.Values)
	Solver2D.removeJoint(sim.world, sim.grip)
	sim.grip = nil
	local rig: Rig.Rig = sim.rig
	local sv, sw, pop = t.releaseVelocityScale, t.releaseSpinScale, t.releasePop
	if sv ~= 1 or sw ~= 1 or pop ~= 0 then
		local ms = Rig.massState(rig)
		local omega = ms.angularMomentum / ms.inertia
		for _, seg in rig.segments do
			local b = seg.body
			local rx, ry = b.x - ms.cx, b.y - ms.cy
			-- velocity = COM velocity + rigid rotation + internal motion
			local ux = b.vx - ms.vx + omega * ry
			local uy = b.vy - ms.vy - omega * rx
			local w2 = omega * sw
			b.vx = ms.vx * sv - w2 * ry + ux
			b.vy = ms.vy * sv + pop + w2 * rx + uy
			b.w = b.w - omega + w2
		end
	end
	st.halfTwists = 0
	setMode(sim, st, "air")
	event(sim, st, "release")
end

local function updateTwist(
	sim: any,
	st: State,
	input: Input.Frame,
	t: Tuning.Values,
	h: number,
	newL: number,
	newR: number
)
	st.prevPsi = st.psi
	if st.mode ~= "air" then
		st.psiRate = 0
		st.twistSpin = 0
		if t.twistSettleTime > 0 then
			st.psi *= exp(-h / t.twistSettleTime)
		else
			st.psi = 0
		end
		return
	end
	local rate = t.twistRate * TAU
	local desired
	if t.twistMode < 0.5 then
		desired = Input.twistAxis(input) * rate -- hold: spin while held; both = hold the angle
	else
		-- momentum: a tap starts or reverses the spin; holding both stops it
		if newR > 0 and newL == 0 then
			st.twistSpin = 1
		elseif newL > 0 and newR == 0 then
			st.twistSpin = -1
		end
		if input.twistLeft and input.twistRight then
			st.twistSpin = 0
		end
		desired = st.twistSpin * rate
	end
	local speedingUp = desired ~= 0
		and (st.psiRate == 0 or (desired > 0) == (st.psiRate > 0))
		and abs(desired) >= abs(st.psiRate)
	local accel = (if speedingUp then t.twistAccel else t.twistStopAccel) * TAU * h
	local d = desired - st.psiRate
	st.psiRate += math.clamp(d, -accel, accel)
	st.psi += st.psiRate * h
	-- half-twist mirror snap (continuous on screen; conserves momentum and energy). Mirroring
	-- moves limbs across the long axis, so it waits (side-on at 90°) until the mirrored body
	-- would be clear of the world.
	if st.psi > pi / 2 or st.psi < -pi / 2 then
		local s = if st.psi > 0 then 1 else -1
		if not Rig.mirrorClear(sim.rig, sim.world, MIRROR_CLEARANCE) then
			st.psi = s * pi / 2
			return
		end
		Rig.mirror(sim.rig)
		st.psi -= s * pi
		st.prevPsi -= s * pi
		-- the smoothed shape is in anatomical terms, so it carries over unchanged
		st.halfTwists += 1
		event(sim, st, "halfTwist")
	end
end

-- Internal joint torque (a muscle): +tau on body B, -tau on body A, so it raises the
-- joint's solver angle (rel = B.a - A.a). Momentum is conserved; only the ground pushes back.
local function jointTorque(rj: Rig.RigJoint, tau: number)
	Solver2D.applyTorque(rj.joint.bodyA, -tau)
	Solver2D.applyTorque(rj.joint.bodyB, tau)
end

-- Segments on the upper side of each leg joint (the part a standing leg joint holds up).
local ABOVE: { [string]: { string } } = {
	ankle = { "torso", "upperArm", "forearm", "thigh", "shank" },
	knee = { "torso", "upperArm", "forearm", "thigh" },
	hip = { "torso", "upperArm", "forearm" },
}

-- Standing muscles, on top of the pose springs:
--  1. gravity compensation: each leg joint carries the weight above it (what muscles do
--     statically), so the springs only correct posture instead of sagging under load;
--  2. balance: the ankles steer the centre of mass over the feet like a critically damped
--     spring at `balanceHertz` (a horizontal "virtual force" at the centre of mass).
-- All torques are internal and clamped to the legs' strength; the ground supplies the reaction.
function standingMuscles(sim: any, st: State, t: Tuning.Values)
	local rig: Rig.Rig = sim.rig
	local g = Tuning.effectiveGravity(t)
	local unit = Rig.torqueUnit(rig, t)
	local S = rig.segmentByName
	local ms = Rig.massState(rig)
	local w = TAU * t.balanceHertz * groundTimeScale(t)
	local fx = -ms.mass * (w * w * (ms.cx - st.supportX) + 2 * t.balanceDampingRatio * w * ms.vx)
	for name, set in ABOVE do
		local rj = rig.jointByName[name]
		local jx, jy = Solver2D.worldPoint(rj.joint.bodyA, rj.joint.lax, rj.joint.lay)
		local tau, m, my = 0, 0, 0
		for _, segName in set do
			local b = S[segName].body
			tau -= g * b.mass * (b.x - jx) * t.gravityCompensation
			m += b.mass
			my += b.mass * b.y
		end
		if name == "ankle" then
			-- the virtual force acts at the centre of mass of everything above the ankle
			tau += (my / m - jy) * fx
		end
		local cap = t[rj.torqueKey] * unit * t.groundLegStrength
		jointTorque(rj, math.clamp(tau, -cap, cap))
	end
end

-- Jump push (stance-leg control through the ground reaction force). The controller picks
-- the force the ground should push with (the body's weight plus `jumpStrength` body weights
-- upward) and where under the feet it acts (the centre of pressure). Where it acts sets the
-- moment about the centre of mass, which is the only thing that changes the body's spin:
-- it is placed to steer the spin to zero for a plain jump, or to `jumpArchSpin` backward
-- while Arch is held (a back-flip takeoff), limited to what the feet can physically do.
-- The hips also steer the trunk from the crouch's lean to upright (internal: it moves spin
-- between trunk and legs, never adds any). Each leg joint produces the torque that ground
-- force needs about it, tau_j = -((c - p_j) × F). All torques are internal and capped.
local function pushMuscles(sim: any, st: State, t: Tuning.Values, archW: number)
	local rig: Rig.Rig = sim.rig
	local g = Tuning.effectiveGravity(t)
	local unit = Rig.torqueUnit(rig, t)
	local ms = Rig.massState(rig)
	local fy = ms.mass * g + t.jumpStrength * unit -- unit torque per stud = body weight (strength-scaled)
	local gs = groundTimeScale(t)
	local fx = -ms.mass * TAU * t.balanceHertz * gs * 2 * t.balanceDampingRatio * ms.vx
	-- trunk posture: from the crouch's forward lean to upright as the legs extend
	local torso = rig.torso
	local wt = TAU * t.jumpTorsoHertz * gs
	local lean = st.pushLean * st.crouchDepth -- + = forward
	local targetA = pi / 2 - rig.facing * lean
	local torsoTorque = torso.inertia * (wt * wt * (targetA - torso.a) - 2 * wt * torso.w)
	-- spin: moment needed about the centre of mass, and the centre of pressure that gives it
	local spinTarget = rig.facing * archW * t.jumpArchSpin * TAU -- + = counter-clockwise
	local moment = (ms.inertia * spinTarget - ms.angularMomentum) * TAU * t.jumpSpinHertz * gs
	local cy = st.supportY
	local cx = ms.cx + (moment + (cy - ms.cy) * fx) / fy
	cx = math.clamp(cx, st.footMinX, st.footMaxX)
	st.debugCop = cx
	st.debugMoment = moment
	for _, name in LEG_JOINTS do
		local rj = rig.jointByName[name]
		local jx, jy = Solver2D.worldPoint(rj.joint.bodyA, rj.joint.lax, rj.joint.lay)
		local rx, ry = cx - jx, cy - jy
		-- the trunk steering is internal to the hip (it redistributes spin, never adds any)
		local tau = -(rx * fy - ry * fx) - (if name == "hip" then torsoTorque else 0)
		local cap = t[rj.torqueKey] * unit * t.jumpLegStrength
		jointTorque(rj, math.clamp(tau, -cap, cap))
	end
end

-- Optional balance assist (a separate knob, off in flight). A single planar pair of feet
-- can't take a step, so after a landing or a shove the ankles alone often can't bring the
-- body back over its feet. This stands in for small foot adjustments: a capped correction
-- that rotates the whole body about its feet, back toward having the centre of mass over
-- the middle of the feet, like a critically damped spring at `balanceHertz`.
function balanceAssist(sim: any, st: State, t: Tuning.Values)
	local rig: Rig.Rig = sim.rig
	local px, py = st.supportX, st.supportY
	local I, L, mx, my, m = 0, 0, 0, 0, 0
	for _, seg in rig.segments do
		local b = seg.body
		local rx, ry = b.x - px, b.y - py
		I += b.inertia + b.mass * (rx * rx + ry * ry)
		L += b.inertia * b.w + b.mass * (rx * b.vy - ry * b.vx)
		mx += b.mass * rx
		my += b.mass * ry
		m += b.mass
	end
	mx /= m
	my /= m
	-- lean of the centre of mass from vertical above the feet (+ = counter-clockwise)
	local lean = math.atan2(-mx, my)
	local w = TAU * t.balanceHertz * groundTimeScale(t)
	local tau = I * (-w * w * lean - 2 * w * L / I)
	-- capped relative to the body's weight (it stands in for foot adjustments, not muscle)
	local cap = t.balanceAssist * m * Tuning.effectiveGravity(t)
	applyTorqueAbout(rig, px, py, I, math.clamp(tau, -cap, cap))
end

local function driveGround(sim: any, st: State, input: Input.Frame, t: Tuning.Values, h: number)
	local rig: Rig.Rig = sim.rig
	local facing = rig.facing
	local goal = {}
	local tW, _, pW = Input.shapeWeights(input)
	local tucking = tW + pW >= 0.5

	-- crouch depth from the actual knee angle
	local knee = math.deg(Rig.jointAngle(rig.jointByName.knee, facing))
	local S, C = POSES.GroundStand, POSES.GroundCrouch
	st.crouchDepth = math.clamp((knee - S.knee) / (C.knee - S.knee), 0, 1)

	-- releasing Tuck from a crouch pushes off
	if st.wasTucking and not tucking and st.crouchDepth >= t.jumpMinCrouch and not st.absorbing then
		st.pushTimer = t.jumpPushTime / groundTimeScale(t)
		st.pushLean = -facing * torsoTilt(rig) / max(st.crouchDepth, 0.1)
		event(sim, st, "push", string.format("%.2f", st.crouchDepth))
	end
	st.wasTucking = tucking

	-- landing: absorb until the fall is stopped (or the time runs out), then stand up
	if st.absorbing then
		st.absorbTimer -= h
		if st.absorbTimer <= 0 or Rig.massState(rig).vy > -LANDED_SPEED * groundTimeScale(t) then
			st.absorbing = false
		end
	end

	if st.pushTimer > 0 then
		st.pushTimer = max(0, st.pushTimer - h)
		-- feet off the ground: the push is over (the ankles keep pushing after the knees lock)
		if st.footContacts == 0 then
			st.pushTimer = 0
		end
	end

	if st.pushTimer > 0 then
		-- jump push: legs by the torques in pushMuscles, arms swing up
		for _, name in JOINTS do
			goal[name] = POSES.GroundReach[name]
		end
		smoothShape(st, goal, t, h, t.jumpHertz)
		local _, archW, _ = Input.shapeWeights(input)
		-- once the knees are straight the body is already rising: no toe-off kick (it
		-- would add uncontrolled spin and drift); the feet simply leave the ground
		if math.deg(Rig.jointAngle(rig.jointByName.knee, facing)) > t.jumpLockKnee then
			pushMuscles(sim, st, t, archW)
		end
		local targets = { shoulder = goal.shoulder, elbow = goal.elbow }
		for _, name in JOINTS do
			st.targets[name] = targets[name] or st.shape[name]
		end
		Rig.drive(rig, t, targets, { hertz = { shoulder = t.jumpHertz, elbow = t.jumpHertz } })
		return
	end

	-- standing: shape springs (stand / crouch / reach), muscles, balance
	local gs = groundTimeScale(t)
	-- rise (or crouch, reach) smoothly from wherever the body is
	groundTargets(input, goal)
	smoothShape(st, goal, t, h, t.groundShapeHertz * gs)
	if st.absorbing then
		-- the knees and ankles yield: their targets follow the body, so their motors only damp
		-- (no spring push-back); the hips keep holding the trunk
		local angles = Rig.jointAnglesDeg(rig)
		for _, name in YIELD_JOINTS do
			st.shape[name] = angles[name]
			st.shapeRate[name] = 0
		end
	end
	local strength: { [string]: number } = {}
	local hertz: { [string]: number } = {}
	for name in LEG do
		hertz[name] = t.groundLegHertz * gs
		strength[name] = t.groundLegStrength
	end
	if st.absorbing then
		hertz.knee = t.landingHertz * gs
	end
	local legDamping = if st.absorbing then t.landingDampingRatio else t.groundLegDampingRatio
	if st.footContacts > 0 then
		standingMuscles(sim, st, t)
		if t.balanceAssist > 0 then
			balanceAssist(sim, st, t)
		end
	end
	-- ankle: the balance torque steers the body; a soft spring keeps the foot flat on the
	-- ground (a heel-first landing rolls onto the whole foot)
	for _, name in JOINTS do
		st.targets[name] = st.shape[name]
	end
	local shankA = rig.segmentByName.shank.body.a
	local flatA = if facing > 0 then 0 else pi
	st.targets.ankle = math.deg(facing * ((flatA - shankA + pi) % TAU - pi))
	hertz.ankle = t.footFlatHertz * gs
	Rig.drive(rig, t, st.targets, {
		strength = strength,
		hertz = hertz,
		dampingRatio = legDamping,
	})
end

local function driveShape(sim: any, st: State, input: Input.Frame, t: Tuning.Values, h: number)
	local goal = {}
	airTargets(input, goal)
	-- landing reflex: falling roughly upright with no shape input, the hips swing the legs
	-- under the centre of mass (internal motion only), so a jump or drop lands on the feet
	if st.mode == "air" and t.landingReflex > 0 and input.arch == 0 and input.tuck == 0 then
		local rig: Rig.Rig = sim.rig
		local tilt = torsoTilt(rig)
		local limit = math.rad(t.landingReflexTilt)
		local ms = Rig.massState(rig)
		if abs(tilt) < 1.5 * limit and ms.vy < 0 then
			-- full strength up to the tilt limit, fading out by 1.5x the limit
			local w = t.landingReflex * math.clamp(3 - 2 * abs(tilt) / limit, 0, 1)
			-- aim the ankles so the middle of the feet lands at the capture point (where the feet
			-- must land to stop the drift)
			local g = Tuning.effectiveGravity(t)
			-- (the ankle sits behind the middle of the foot)
			local midFoot = (t.footLength - Rig.FOOT_HEEL) / 2
			local captureX = ms.cx
				+ ms.vx * CAPTURE_LEAD * math.sqrt(STAND_COM_HEIGHT / g)
				- rig.facing * midFoot
			local hip = rig.jointByName.hip.joint
			local hx = Solver2D.worldPoint(hip.bodyA, hip.lax, hip.lay)
			-- two-link leg with soft knees: hip-to-ankle length, and how far the bent knee
			-- swings the ankle behind the thigh line
			local T, S, kappa = t.thighLength, t.shankLength, math.rad(REFLEX_KNEE)
			local reach = math.sqrt(T * T + S * S + 2 * T * S * math.cos(kappa))
			local behind = math.atan2(S * math.sin(kappa), T + S * math.cos(kappa))
			local lean = math.asin(math.clamp((captureX - hx) / reach, -0.4, 0.4))
			local thighA = -pi / 2 + lean + rig.facing * behind
			local hipDown = math.deg(rig.facing * (thighA - rig.torso.a)) + 180
			hipDown = (hipDown + 180) % 360 - 180
			goal.hip += (hipDown - goal.hip) * w
			goal.knee += (REFLEX_KNEE - goal.knee) * w
			-- and level feet, so they land flat instead of slapping down heel- or toe-first
			local flatA = if rig.facing > 0 then 0 else pi
			local shankA = rig.segmentByName.shank.body.a
			local ankleFlat = math.deg(rig.facing * ((flatA - shankA + pi) % TAU - pi))
			goal.ankle += (ankleFlat - goal.ankle) * w
		end
	end
	smoothShape(st, goal, t, h)
	for _, name in JOINTS do
		st.targets[name] = st.shape[name]
	end
	-- on the bar the shoulders turn the whole hanging body, far more load than their own
	-- segments: they get a stiffer spring there (motor springs scale with segment inertia)
	local hertz = if st.mode == "grip" then { shoulder = t.gripShoulderHertz } else nil
	Rig.drive(sim.rig, t, st.targets, { hertz = hertz })
end

----------------------------------------------------------------------------------------------------
-- Step
----------------------------------------------------------------------------------------------------

-- Runs once per fixed step, before the solver. `sim.poseOverride` (debug) replaces the
-- motor targets with a named pose but keeps the states running.
function Controller.step(sim: any, st: State, input: Input.Frame, h: number)
	local t: Tuning.Values = sim.tuning
	local rig: Rig.Rig = sim.rig
	st.modeTime += h

	-- presses since the last step
	local newLetGo = input.letGoPresses - st.consumed.letGo
	local newL = input.twistLeftPresses - st.consumed.twistLeft
	local newR = input.twistRightPresses - st.consumed.twistRight
	st.consumed.letGo = input.letGoPresses
	st.consumed.grab = input.grabPresses -- Grab is consumed but has no effect until P1.3
	st.consumed.twistLeft = input.twistLeftPresses
	st.consumed.twistRight = input.twistRightPresses

	-- derived state
	local ms = Rig.massState(rig)
	if sim.grip then
		setMode(sim, st, "grip")
		if newLetGo > 0 then
			release(sim, st, t)
		end
	else
		scanContacts(sim, st)
		local upright = abs(torsoTilt(rig)) < math.rad(t.fallTiltAngle)
		local supported = st.footContacts > 0 and not st.bodyContact and upright
		if supported then
			st.lastSupportTime = sim.time
			if st.mode ~= "ground" then
				local impact = max(0, -min(st.prevComVY, ms.vy))
				setMode(sim, st, "ground")
				st.pushTimer = 0
				st.wasTucking = false
				local gs = groundTimeScale(t)
				st.absorbing = impact > LANDED_SPEED * gs and t.landingAbsorbTime > 0
				st.absorbTimer = t.landingAbsorbTime / gs
				-- the legs start from where they are: no spring kick at touchdown
				local angles = Rig.jointAnglesDeg(rig)
				for _, name in JOINTS do
					st.shape[name] = angles[name]
					st.shapeRate[name] = 0
				end
				st.halfTwists = 0
				event(sim, st, "landing", string.format("%.2f", impact))
			end
		elseif st.mode == "ground" then
			if st.bodyContact or not upright then
				setMode(sim, st, "fallen")
				event(sim, st, "fall")
			elseif sim.time - st.lastSupportTime > t.groundGrace / groundTimeScale(t) then
				setMode(sim, st, "air")
				st.halfTwists = 0
				event(sim, st, "takeoff")
			end
		elseif st.bodyContact or (st.footContacts > 0 and not upright) then
			if st.mode ~= "fallen" then
				setMode(sim, st, "fallen")
				event(sim, st, "fall")
			end
		elseif st.mode == "fallen" and #sim.world.contacts == 0 then
			setMode(sim, st, "air")
		elseif st.mode == "grip" then
			setMode(sim, st, "air") -- grip removed from outside (e.g. debug)
		end
	end
	st.prevComVY = ms.vy

	updateTwist(sim, st, input, t, h, newL, newR)

	-- muscles
	if st.mode == "ground" then
		driveGround(sim, st, input, t, h)
	else
		st.pushTimer = 0
		driveShape(sim, st, input, t, h)
		if st.mode == "grip" and sim.grip then
			updateSwing(sim, st, t, Rig.torqueUnit(rig, t), h)
		end
	end
	if sim.poseOverride then
		Rig.drive(rig, t, Rig.POSES[sim.poseOverride] or Rig.POSES.Neutral)
	end
end

-- Interpolated twist angle for rendering (matches Sim.alpha).
function Controller.renderPsi(st: State, alpha: number): number
	return st.prevPsi + (st.psi - st.prevPsi) * alpha
end

return Controller
