--!strict
--!native
-- Solver2D: a small planar rigid-body solver for the gymnast and the equipment
-- it touches. Soft-step sequential impulses with warm starting, in the style of
-- Box2D v3:
--
--   per fixed step:   collide -> prepare contacts/joints
--   per substep:      integrate velocities -> warm start -> solve (with bias)
--                     -> integrate positions -> relax (without bias)
--   after substeps:   restitution -> keep impulses for the next step's warm start
--
-- Bodies are dynamic (simulated), kinematic (moved by their own velocity; infinite
-- mass) or static. Only dynamic-vs-(static|kinematic) shape pairs collide; the
-- body does not collide with itself (joint limits keep limbs plausible).
--
-- Pure Luau: no Roblox types, no clocks, no randomness. Same inputs -> same result.

-- (Headless tests load a mirrored copy with these requires rewritten to file paths; see tools/lune_mirror.luau.)
local Collide2D = require(script.Parent.Collide2D)

local sqrt, cos, sin, abs, min, max, pi = math.sqrt, math.cos, math.sin, math.abs, math.min, math.max, math.pi

local Solver2D = {}

local updateShapeWorld: (any) -> () -- defined in the Collision section

Solver2D.STATIC = 0
Solver2D.KINEMATIC = 1
Solver2D.DYNAMIC = 2

export type Body = {
	index: number,
	name: string,
	kind: number,
	x: number,
	y: number,
	a: number,
	c: number,
	s: number,
	vx: number,
	vy: number,
	w: number,
	mass: number,
	invMass: number,
	inertia: number,
	invI: number,
	-- previous-step pose for render interpolation
	prevX: number,
	prevY: number,
	prevA: number,
}

export type Shape = {
	index: number,
	body: Body,
	kind: string, -- "segment" (capsule/circle) or "polygon"
	-- rounded segment, local to the body's centre of mass
	lax: number,
	lay: number,
	lbx: number,
	lby: number,
	radius: number,
	-- world cache for rounded segments
	ax: number,
	ay: number,
	bx: number,
	by: number,
	polygon: Collide2D.Polygon?,
	friction: number,
	restitution: number,
	tag: string,
	extent: number, -- farthest shape point from the body's centre of mass (for motion bounds)
	minX: number,
	minY: number,
	maxX: number,
	maxY: number,
}

export type Joint = {
	index: number,
	name: string,
	bodyA: Body,
	bodyB: Body,
	-- anchors in each body's local frame (relative to its centre of mass)
	lax: number,
	lay: number,
	lbx: number,
	lby: number,
	-- relative angle convention: rel = bodyB.a - bodyA.a
	enableLimit: boolean,
	lower: number,
	upper: number,
	enableSpring: boolean,
	target: number,
	maxTorque: number,
	springHertz: number,
	springDampingRatio: number,
	-- accumulated impulses (warm started)
	impulseX: number,
	impulseY: number,
	springImpulse: number,
	lowerImpulse: number,
	upperImpulse: number,
	-- per-step cache
	axialMass: number,
	springBias: number,
	springMassScale: number,
	springImpulseScale: number,
	-- diagnostics
	error: number,
	enabled: boolean,
}

export type ContactPoint = {
	key: number,
	shapeA: Shape,
	shapeB: Shape,
	bodyA: Body,
	bodyB: Body,
	nx: number,
	ny: number,
	-- anchors in each body's local frame (point on A's surface, point on B's surface)
	lax: number,
	lay: number,
	lbx: number,
	lby: number,
	separation: number,
	normalImpulse: number,
	tangentImpulse: number,
	maxNormalImpulse: number,
	normalMass: number,
	tangentMass: number,
	relativeVelocity: number,
	friction: number,
	restitution: number,
	aliveStep: number,
}

export type Params = {
	gravityX: number,
	gravityY: number,
	substeps: number,
	relaxIterations: number,
	linearDamping: number,
	angularDamping: number,
	maxLinearSpeed: number,
	maxAngularSpeed: number,
	contactHertz: number,
	contactDampingRatio: number,
	contactPushSpeed: number,
	speculativeDistance: number,
	restitutionThreshold: number,
	jointHertz: number,
	jointDampingRatio: number,
}

export type World = {
	params: Params,
	bodies: { Body },
	ground: Body,
	bodyShapes: { Shape }, -- shapes on dynamic bodies
	worldShapes: { Shape }, -- shapes on static/kinematic bodies
	joints: { Joint },
	contacts: { ContactPoint },
	contactMap: { [number]: ContactPoint },
	stepIndex: number,
	time: number,
	nextShapeIndex: number,
	nextJointIndex: number,
}

function Solver2D.defaultParams(): Params
	return {
		gravityX = 0,
		gravityY = -35,
		substeps = 4,
		relaxIterations = 1,
		linearDamping = 0,
		angularDamping = 0,
		maxLinearSpeed = 400,
		maxAngularSpeed = 120,
		contactHertz = 30,
		contactDampingRatio = 10,
		contactPushSpeed = 10,
		speculativeDistance = 0.12,
		restitutionThreshold = 3,
		jointHertz = 240,
		jointDampingRatio = 2,
	}
end

local function newBody(index: number, name: string, kind: number): Body
	return {
		index = index,
		name = name,
		kind = kind,
		x = 0,
		y = 0,
		a = 0,
		c = 1,
		s = 0,
		vx = 0,
		vy = 0,
		w = 0,
		mass = 0,
		invMass = 0,
		inertia = 0,
		invI = 0,
		prevX = 0,
		prevY = 0,
		prevA = 0,
	}
end

function Solver2D.newWorld(params: Params?): World
	local ground = newBody(1, "ground", Solver2D.STATIC)
	return {
		params = params or Solver2D.defaultParams(),
		bodies = { ground },
		ground = ground,
		bodyShapes = {},
		worldShapes = {},
		joints = {},
		contacts = {},
		contactMap = {},
		stepIndex = 0,
		time = 0,
		nextShapeIndex = 1,
		nextJointIndex = 1,
	}
end

export type BodyDef = {
	name: string?,
	kind: number?,
	x: number?,
	y: number?,
	a: number?,
	vx: number?,
	vy: number?,
	w: number?,
	mass: number?,
	inertia: number?,
}

function Solver2D.addBody(world: World, def: BodyDef): Body
	local kind = def.kind or Solver2D.DYNAMIC
	local b = newBody(#world.bodies + 1, def.name or `body{#world.bodies + 1}`, kind)
	b.x, b.y, b.a = def.x or 0, def.y or 0, def.a or 0
	b.c, b.s = cos(b.a), sin(b.a)
	b.vx, b.vy, b.w = def.vx or 0, def.vy or 0, def.w or 0
	b.prevX, b.prevY, b.prevA = b.x, b.y, b.a
	if kind == Solver2D.DYNAMIC then
		local m = def.mass or 1
		local i = def.inertia or m * 0.1
		assert(m > 0 and i > 0, "dynamic bodies need positive mass and inertia")
		b.mass, b.invMass = m, 1 / m
		b.inertia, b.invI = i, 1 / i
	end
	table.insert(world.bodies, b)
	return b
end

export type ShapeDef = {
	friction: number?,
	restitution: number?,
	tag: string?,
}

local function newShape(world: World, body: Body, kind: string, def: ShapeDef?): Shape
	local shape: Shape = {
		index = world.nextShapeIndex,
		body = body,
		kind = kind,
		lax = 0,
		lay = 0,
		lbx = 0,
		lby = 0,
		radius = 0,
		ax = 0,
		ay = 0,
		bx = 0,
		by = 0,
		polygon = nil,
		friction = (def and def.friction) or 0.8,
		restitution = (def and def.restitution) or 0,
		tag = (def and def.tag) or "",
		extent = 0,
		minX = 0,
		minY = 0,
		maxX = 0,
		maxY = 0,
	}
	world.nextShapeIndex += 1
	if body.kind == Solver2D.DYNAMIC then
		table.insert(world.bodyShapes, shape)
	else
		table.insert(world.worldShapes, shape)
	end
	return shape
end

-- Rounded segment in the body's local frame (a circle when both ends coincide).
function Solver2D.addCapsule(
	world: World,
	body: Body,
	ax: number,
	ay: number,
	bx: number,
	by: number,
	radius: number,
	def: ShapeDef?
): Shape
	assert(body.kind == Solver2D.DYNAMIC, "rounded segments are for dynamic bodies in this solver")
	local shape = newShape(world, body, "segment", def)
	shape.lax, shape.lay, shape.lbx, shape.lby, shape.radius = ax, ay, bx, by, radius
	shape.extent = max(sqrt(ax * ax + ay * ay), sqrt(bx * bx + by * by)) + radius
	updateShapeWorld(shape) -- world cache valid immediately (readers before the first step)
	return shape
end

function Solver2D.addCircle(
	world: World,
	body: Body,
	cx: number,
	cy: number,
	radius: number,
	def: ShapeDef?
): Shape
	return Solver2D.addCapsule(world, body, cx, cy, cx, cy, radius, def)
end

-- Convex polygon (world geometry) on a static or kinematic body.
function Solver2D.addPolygon(world: World, body: Body, polygon: Collide2D.Polygon, def: ShapeDef?): Shape
	assert(body.kind ~= Solver2D.DYNAMIC, "polygons are world geometry (static or kinematic bodies)")
	local shape = newShape(world, body, "polygon", def)
	shape.polygon = polygon
	for i = 1, polygon.count do
		shape.extent = max(shape.extent, sqrt(polygon.lx[i] ^ 2 + polygon.ly[i] ^ 2))
	end
	Collide2D.updatePolygon(polygon, body.x, body.y, body.c, body.s)
	shape.minX, shape.minY, shape.maxX, shape.maxY = polygon.minX, polygon.minY, polygon.maxX, polygon.maxY
	return shape
end

export type JointDef = {
	name: string?,
	enableLimit: boolean?,
	lower: number?,
	upper: number?,
	enableSpring: boolean?,
	target: number?,
	maxTorque: number?,
	springHertz: number?,
	springDampingRatio: number?,
}

-- Revolute (pin) joint at a world point. Body A may be static or kinematic (a grip on
-- a fixed or moving anchor). Angles use rel = bodyB.a - bodyA.a.
function Solver2D.addRevolute(
	world: World,
	bodyA: Body,
	bodyB: Body,
	wx: number,
	wy: number,
	def: JointDef?
): Joint
	local d: JointDef = def or {}
	local rax, ray = wx - bodyA.x, wy - bodyA.y
	local rbx, rby = wx - bodyB.x, wy - bodyB.y
	local joint: Joint = {
		index = world.nextJointIndex,
		name = d.name or `joint{world.nextJointIndex}`,
		bodyA = bodyA,
		bodyB = bodyB,
		lax = bodyA.c * rax + bodyA.s * ray,
		lay = -bodyA.s * rax + bodyA.c * ray,
		lbx = bodyB.c * rbx + bodyB.s * rby,
		lby = -bodyB.s * rbx + bodyB.c * rby,
		enableLimit = d.enableLimit or false,
		lower = d.lower or 0,
		upper = d.upper or 0,
		enableSpring = d.enableSpring or false,
		target = d.target or 0,
		maxTorque = d.maxTorque or 0,
		springHertz = d.springHertz or 0,
		springDampingRatio = d.springDampingRatio or 1,
		impulseX = 0,
		impulseY = 0,
		springImpulse = 0,
		lowerImpulse = 0,
		upperImpulse = 0,
		axialMass = 0,
		springBias = 0,
		springMassScale = 1,
		springImpulseScale = 0,
		error = 0,
		enabled = true,
	}
	world.nextJointIndex += 1
	table.insert(world.joints, joint)
	return joint
end

function Solver2D.removeJoint(world: World, joint: Joint)
	local i = table.find(world.joints, joint)
	if i then
		table.remove(world.joints, i)
	end
end

-- Soft constraint coefficients (Box2D v3 "b2MakeSoft").
local function makeSoft(hertz: number, zeta: number, h: number): (number, number, number)
	if hertz <= 0 then
		return 0, 1, 0
	end
	local omega = 2 * pi * hertz
	local a1 = 2 * zeta + h * omega
	local a2 = h * omega * a1
	local a3 = 1 / (1 + a2)
	return omega / a1, a2 * a3, a3
end
Solver2D.makeSoft = makeSoft

----------------------------------------------------------------------------------------------------
-- Collision
----------------------------------------------------------------------------------------------------

function updateShapeWorld(shape: Shape)
	local b = shape.body
	if shape.kind == "segment" then
		local c, s = b.c, b.s
		local ax = b.x + c * shape.lax - s * shape.lay
		local ay = b.y + s * shape.lax + c * shape.lay
		local bx = b.x + c * shape.lbx - s * shape.lby
		local by = b.y + s * shape.lbx + c * shape.lby
		shape.ax, shape.ay, shape.bx, shape.by = ax, ay, bx, by
		local r = shape.radius
		shape.minX, shape.maxX = min(ax, bx) - r, max(ax, bx) + r
		shape.minY, shape.maxY = min(ay, by) - r, max(ay, by) + r
	else
		local poly = shape.polygon :: Collide2D.Polygon
		if b.kind == Solver2D.KINEMATIC then
			Collide2D.updatePolygon(poly, b.x, b.y, b.c, b.s)
		end
		shape.minX, shape.minY, shape.maxX, shape.maxY = poly.minX, poly.minY, poly.maxX, poly.maxY
	end
end

-- How far a shape can travel during `dt` (linear speed plus rotation at its farthest point).
local function motionBound(shape: Shape, dt: number): number
	local b = shape.body
	if b.kind == Solver2D.STATIC then
		return 0
	end
	return (sqrt(b.vx * b.vx + b.vy * b.vy) + abs(b.w) * shape.extent) * dt
end

local function collide(world: World, dt: number)
	local p = world.params
	local baseSpec = p.speculativeDistance
	local stepIndex = world.stepIndex
	local map = world.contactMap
	local contacts = world.contacts
	table.clear(contacts)

	for _, ws in world.worldShapes do
		updateShapeWorld(ws)
	end
	for _, bs in world.bodyShapes do
		updateShapeWorld(bs)
		local bodyMotion = motionBound(bs, dt)
		for _, ws in world.worldShapes do
			-- speculative margin covers this step's motion, so fast bodies cannot tunnel
			local spec = baseSpec + bodyMotion + motionBound(ws, dt)
			if
				bs.maxX + spec < ws.minX
				or bs.minX - spec > ws.maxX
				or bs.maxY + spec < ws.minY
				or bs.minY - spec > ws.maxY
			then
				continue
			end
			local count =
				Collide2D.capsulePolygon(bs.ax, bs.ay, bs.bx, bs.by, bs.radius, ws.polygon :: any, spec)
			if count == 0 then
				continue
			end
			local nx, ny = Collide2D.nx, Collide2D.ny
			local bodyA, bodyB = bs.body, ws.body
			for k = 1, count do
				local key = (bs.index * 4096 + ws.index) * 64 + Collide2D.id[k]
				local cp = map[key]
				if cp == nil then
					cp = {
						key = key,
						shapeA = bs,
						shapeB = ws,
						bodyA = bodyA,
						bodyB = bodyB,
						nx = 0,
						ny = 0,
						lax = 0,
						lay = 0,
						lbx = 0,
						lby = 0,
						separation = 0,
						normalImpulse = 0,
						tangentImpulse = 0,
						maxNormalImpulse = 0,
						normalMass = 0,
						tangentMass = 0,
						relativeVelocity = 0,
						friction = 0,
						restitution = 0,
						aliveStep = -1,
					}
					map[key] = cp
				elseif cp.aliveStep ~= stepIndex - 1 then
					-- stale point from an older touch: no warm start
					cp.normalImpulse, cp.tangentImpulse = 0, 0
				end
				local pax, pay = Collide2D.px[k], Collide2D.py[k]
				local sep = Collide2D.sep[k]
				local pbx, pby = pax + nx * sep, pay + ny * sep
				local rax, ray = pax - bodyA.x, pay - bodyA.y
				local rbx, rby = pbx - bodyB.x, pby - bodyB.y
				cp.nx, cp.ny = nx, ny
				cp.lax = bodyA.c * rax + bodyA.s * ray
				cp.lay = -bodyA.s * rax + bodyA.c * ray
				cp.lbx = bodyB.c * rbx + bodyB.s * rby
				cp.lby = -bodyB.s * rbx + bodyB.c * rby
				cp.separation = sep
				cp.friction = sqrt(bs.friction * ws.friction)
				cp.restitution = max(bs.restitution, ws.restitution)
				cp.aliveStep = stepIndex
				table.insert(contacts, cp)
			end
		end
	end

	-- forget points that did not touch this step
	for key, cp in map do
		if cp.aliveStep ~= stepIndex then
			map[key] = nil
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Contacts
----------------------------------------------------------------------------------------------------

local function prepareContacts(world: World)
	for _, cp in world.contacts do
		local A, B = cp.bodyA, cp.bodyB
		local rax = A.c * cp.lax - A.s * cp.lay
		local ray = A.s * cp.lax + A.c * cp.lay
		local rbx = B.c * cp.lbx - B.s * cp.lby
		local rby = B.s * cp.lbx + B.c * cp.lby
		local nx, ny = cp.nx, cp.ny
		local tx, ty = ny, -nx
		local mA, iA, mB, iB = A.invMass, A.invI, B.invMass, B.invI
		local rnA = rax * ny - ray * nx
		local rnB = rbx * ny - rby * nx
		local kN = mA + mB + iA * rnA * rnA + iB * rnB * rnB
		cp.normalMass = if kN > 0 then 1 / kN else 0
		local rtA = rax * ty - ray * tx
		local rtB = rbx * ty - rby * tx
		local kT = mA + mB + iA * rtA * rtA + iB * rtB * rtB
		cp.tangentMass = if kT > 0 then 1 / kT else 0
		-- relative normal velocity before solving (for restitution)
		local dvx = (B.vx - B.w * rby) - (A.vx - A.w * ray)
		local dvy = (B.vy + B.w * rbx) - (A.vy + A.w * rax)
		cp.relativeVelocity = dvx * nx + dvy * ny
		cp.maxNormalImpulse = 0
	end
end

local function warmStartContacts(world: World)
	for _, cp in world.contacts do
		local A, B = cp.bodyA, cp.bodyB
		local rax = A.c * cp.lax - A.s * cp.lay
		local ray = A.s * cp.lax + A.c * cp.lay
		local rbx = B.c * cp.lbx - B.s * cp.lby
		local rby = B.s * cp.lbx + B.c * cp.lby
		local nx, ny = cp.nx, cp.ny
		local Px = cp.normalImpulse * nx + cp.tangentImpulse * ny
		local Py = cp.normalImpulse * ny - cp.tangentImpulse * nx
		A.vx -= A.invMass * Px
		A.vy -= A.invMass * Py
		A.w -= A.invI * (rax * Py - ray * Px)
		B.vx += B.invMass * Px
		B.vy += B.invMass * Py
		B.w += B.invI * (rbx * Py - rby * Px)
	end
end

local function solveContacts(
	world: World,
	invH: number,
	useBias: boolean,
	biasRate: number,
	massScaleSoft: number,
	impulseScaleSoft: number
)
	local pushSpeed = world.params.contactPushSpeed
	for _, cp in world.contacts do
		local A, B = cp.bodyA, cp.bodyB
		local rax = A.c * cp.lax - A.s * cp.lay
		local ray = A.s * cp.lax + A.c * cp.lay
		local rbx = B.c * cp.lbx - B.s * cp.lby
		local rby = B.s * cp.lbx + B.c * cp.lby
		local nx, ny = cp.nx, cp.ny
		local mA, iA, mB, iB = A.invMass, A.invI, B.invMass, B.invI

		-- current separation from the anchored surface points
		local s = ((B.x + rbx) - (A.x + rax)) * nx + ((B.y + rby) - (A.y + ray)) * ny

		local bias, massScale, impulseScale = 0, 1, 0
		if s > 0 then
			bias = s * invH -- speculative: allow closing the gap this substep, no more
		elseif useBias then
			bias = max(biasRate * s, -pushSpeed)
			massScale = massScaleSoft
			impulseScale = impulseScaleSoft
		end

		-- normal
		local dvx = (B.vx - B.w * rby) - (A.vx - A.w * ray)
		local dvy = (B.vy + B.w * rbx) - (A.vy + A.w * rax)
		local vn = dvx * nx + dvy * ny
		local impulse = -cp.normalMass * massScale * (vn + bias) - impulseScale * cp.normalImpulse
		local newImpulse = max(cp.normalImpulse + impulse, 0)
		impulse = newImpulse - cp.normalImpulse
		cp.normalImpulse = newImpulse
		if newImpulse > cp.maxNormalImpulse then
			cp.maxNormalImpulse = newImpulse
		end
		local Px, Py = impulse * nx, impulse * ny
		A.vx -= mA * Px
		A.vy -= mA * Py
		A.w -= iA * (rax * Py - ray * Px)
		B.vx += mB * Px
		B.vy += mB * Py
		B.w += iB * (rbx * Py - rby * Px)

		-- friction
		local tx, ty = ny, -nx
		dvx = (B.vx - B.w * rby) - (A.vx - A.w * ray)
		dvy = (B.vy + B.w * rbx) - (A.vy + A.w * rax)
		local vt = dvx * tx + dvy * ty
		local fImpulse = -cp.tangentMass * vt
		local maxF = cp.friction * cp.normalImpulse
		local newF = min(max(cp.tangentImpulse + fImpulse, -maxF), maxF)
		fImpulse = newF - cp.tangentImpulse
		cp.tangentImpulse = newF
		Px, Py = fImpulse * tx, fImpulse * ty
		A.vx -= mA * Px
		A.vy -= mA * Py
		A.w -= iA * (rax * Py - ray * Px)
		B.vx += mB * Px
		B.vy += mB * Py
		B.w += iB * (rbx * Py - rby * Px)
	end
end

local function applyRestitution(world: World)
	local threshold = world.params.restitutionThreshold
	for _, cp in world.contacts do
		if cp.restitution == 0 or cp.relativeVelocity > -threshold or cp.maxNormalImpulse == 0 then
			continue
		end
		local A, B = cp.bodyA, cp.bodyB
		local rax = A.c * cp.lax - A.s * cp.lay
		local ray = A.s * cp.lax + A.c * cp.lay
		local rbx = B.c * cp.lbx - B.s * cp.lby
		local rby = B.s * cp.lbx + B.c * cp.lby
		local nx, ny = cp.nx, cp.ny
		local dvx = (B.vx - B.w * rby) - (A.vx - A.w * ray)
		local dvy = (B.vy + B.w * rbx) - (A.vy + A.w * rax)
		local vn = dvx * nx + dvy * ny
		local impulse = -cp.normalMass * (vn + cp.restitution * cp.relativeVelocity)
		local newImpulse = max(cp.normalImpulse + impulse, 0)
		impulse = newImpulse - cp.normalImpulse
		cp.normalImpulse = newImpulse
		local Px, Py = impulse * nx, impulse * ny
		A.vx -= A.invMass * Px
		A.vy -= A.invMass * Py
		A.w -= A.invI * (rax * Py - ray * Px)
		B.vx += B.invMass * Px
		B.vy += B.invMass * Py
		B.w += B.invI * (rbx * Py - rby * Px)
	end
end

----------------------------------------------------------------------------------------------------
-- Joints
----------------------------------------------------------------------------------------------------

local function prepareJoints(world: World, h: number, maxHertz: number)
	for _, j in world.joints do
		local k = j.bodyA.invI + j.bodyB.invI
		j.axialMass = if k > 0 then 1 / k else 0
		j.springBias, j.springMassScale, j.springImpulseScale =
			makeSoft(min(j.springHertz, maxHertz), j.springDampingRatio, h)
		-- motor strength may have changed since last step: keep the warm-start impulse within it
		local maxImpulse = j.maxTorque * h
		j.springImpulse = min(max(j.springImpulse, -maxImpulse), maxImpulse)
		if not j.enableSpring then
			j.springImpulse = 0
		end
		if not j.enableLimit then
			j.lowerImpulse, j.upperImpulse = 0, 0
		end
	end
end

local function warmStartJoints(world: World)
	for _, j in world.joints do
		local A, B = j.bodyA, j.bodyB
		local rax = A.c * j.lax - A.s * j.lay
		local ray = A.s * j.lax + A.c * j.lay
		local rbx = B.c * j.lbx - B.s * j.lby
		local rby = B.s * j.lbx + B.c * j.lby
		local axial = j.springImpulse + j.lowerImpulse - j.upperImpulse
		local Px, Py = j.impulseX, j.impulseY
		A.vx -= A.invMass * Px
		A.vy -= A.invMass * Py
		A.w -= A.invI * ((rax * Py - ray * Px) + axial)
		B.vx += B.invMass * Px
		B.vy += B.invMass * Py
		B.w += B.invI * ((rbx * Py - rby * Px) + axial)
	end
end

local function solveJoints(
	world: World,
	h: number,
	invH: number,
	useBias: boolean,
	biasRate: number,
	massScaleSoft: number,
	impulseScaleSoft: number
)
	for _, j in world.joints do
		local A, B = j.bodyA, j.bodyB
		local mA, iA, mB, iB = A.invMass, A.invI, B.invMass, B.invI
		local rel = B.a - A.a

		-- spring motor (torque limited): a physical spring-damper toward the target angle
		if j.enableSpring and j.maxTorque > 0 then
			local C = rel - j.target
			local Cdot = B.w - A.w
			local impulse = -j.springMassScale * j.axialMass * (Cdot + j.springBias * C)
				- j.springImpulseScale * j.springImpulse
			local maxImpulse = j.maxTorque * h
			local newImpulse = min(max(j.springImpulse + impulse, -maxImpulse), maxImpulse)
			impulse = newImpulse - j.springImpulse
			j.springImpulse = newImpulse
			A.w -= iA * impulse
			B.w += iB * impulse
		end

		-- angle limits
		if j.enableLimit then
			do -- lower: rel >= lower
				local C = rel - j.lower
				local bias, massScale, impulseScale = 0, 1, 0
				if C > 0 then
					bias = C * invH
				elseif useBias then
					bias = max(biasRate * C, -world.params.contactPushSpeed)
					massScale, impulseScale = massScaleSoft, impulseScaleSoft
				end
				local Cdot = B.w - A.w
				local impulse = -j.axialMass * massScale * (Cdot + bias) - impulseScale * j.lowerImpulse
				local newImpulse = max(j.lowerImpulse + impulse, 0)
				impulse = newImpulse - j.lowerImpulse
				j.lowerImpulse = newImpulse
				A.w -= iA * impulse
				B.w += iB * impulse
			end
			do -- upper: rel <= upper
				local C = j.upper - rel
				local bias, massScale, impulseScale = 0, 1, 0
				if C > 0 then
					bias = C * invH
				elseif useBias then
					bias = max(biasRate * C, -world.params.contactPushSpeed)
					massScale, impulseScale = massScaleSoft, impulseScaleSoft
				end
				local Cdot = A.w - B.w
				local impulse = -j.axialMass * massScale * (Cdot + bias) - impulseScale * j.upperImpulse
				local newImpulse = max(j.upperImpulse + impulse, 0)
				impulse = newImpulse - j.upperImpulse
				j.upperImpulse = newImpulse
				A.w += iA * impulse
				B.w -= iB * impulse
			end
		end

		-- point-to-point: anchors coincide
		local rax = A.c * j.lax - A.s * j.lay
		local ray = A.s * j.lax + A.c * j.lay
		local rbx = B.c * j.lbx - B.s * j.lby
		local rby = B.s * j.lbx + B.c * j.lby
		local sepX = (B.x + rbx) - (A.x + rax)
		local sepY = (B.y + rby) - (A.y + ray)
		local biasX, biasY, massScale, impulseScale = 0, 0, 1, 0
		if useBias then
			biasX, biasY = biasRate * sepX, biasRate * sepY
			massScale, impulseScale = massScaleSoft, impulseScaleSoft
		end
		local cdotX = (B.vx - B.w * rby) - (A.vx - A.w * ray)
		local cdotY = (B.vy + B.w * rbx) - (A.vy + A.w * rax)
		local k11 = mA + mB + ray * ray * iA + rby * rby * iB
		local k12 = -ray * rax * iA - rby * rbx * iB
		local k22 = mA + mB + rax * rax * iA + rbx * rbx * iB
		local det = k11 * k22 - k12 * k12
		if det ~= 0 then
			det = 1 / det
		end
		local vx, vy = cdotX + biasX, cdotY + biasY
		local bx = det * (k22 * vx - k12 * vy)
		local by = det * (k11 * vy - k12 * vx)
		local ix = -massScale * bx - impulseScale * j.impulseX
		local iy = -massScale * by - impulseScale * j.impulseY
		j.impulseX += ix
		j.impulseY += iy
		A.vx -= mA * ix
		A.vy -= mA * iy
		A.w -= iA * (rax * iy - ray * ix)
		B.vx += mB * ix
		B.vy += mB * iy
		B.w += iB * (rbx * iy - rby * ix)
	end
end

----------------------------------------------------------------------------------------------------
-- Integration
----------------------------------------------------------------------------------------------------

local function integrateVelocities(world: World, h: number)
	local p = world.params
	local gx, gy = p.gravityX, p.gravityY
	local linDamp = 1 / (1 + h * p.linearDamping)
	local angDamp = 1 / (1 + h * p.angularDamping)
	local maxV, maxW = p.maxLinearSpeed, p.maxAngularSpeed
	for _, b in world.bodies do
		if b.kind ~= Solver2D.DYNAMIC then
			continue
		end
		local vx = (b.vx + h * gx) * linDamp
		local vy = (b.vy + h * gy) * linDamp
		local w = b.w * angDamp
		local v2 = vx * vx + vy * vy
		if v2 > maxV * maxV then
			local k = maxV / sqrt(v2)
			vx *= k
			vy *= k
		end
		if w > maxW then
			w = maxW
		elseif w < -maxW then
			w = -maxW
		end
		b.vx, b.vy, b.w = vx, vy, w
	end
end

local function integratePositions(world: World, h: number)
	for _, b in world.bodies do
		if b.kind == Solver2D.STATIC then
			continue
		end
		b.x += h * b.vx
		b.y += h * b.vy
		b.a += h * b.w
		b.c = cos(b.a)
		b.s = sin(b.a)
	end
end

----------------------------------------------------------------------------------------------------
-- Step
----------------------------------------------------------------------------------------------------

function Solver2D.step(world: World, dt: number)
	if dt <= 0 then
		return
	end
	local p = world.params
	local substeps = max(1, p.substeps // 1)
	local relaxIterations = max(1, p.relaxIterations // 1)
	local h = dt / substeps
	local invH = 1 / h

	for _, b in world.bodies do
		b.prevX, b.prevY, b.prevA = b.x, b.y, b.a
	end

	-- Soft constraints stay stable while stiffness <= a quarter of the substep rate
	-- (h·ω <= π/2). Higher settings are capped rather than allowed to go unstable.
	local maxHertz = 0.25 / h

	collide(world, dt)
	prepareContacts(world)
	prepareJoints(world, h, maxHertz)

	local cBias, cMass, cImpulse = makeSoft(min(p.contactHertz, maxHertz), p.contactDampingRatio, h)
	local jBias, jMass, jImpulse = makeSoft(min(p.jointHertz, maxHertz), p.jointDampingRatio, h)

	for _ = 1, substeps do
		integrateVelocities(world, h)
		warmStartJoints(world)
		warmStartContacts(world)
		solveJoints(world, h, invH, true, jBias, jMass, jImpulse)
		solveContacts(world, invH, true, cBias, cMass, cImpulse)
		integratePositions(world, h)
		for _ = 1, relaxIterations do
			solveJoints(world, h, invH, false, jBias, jMass, jImpulse)
			solveContacts(world, invH, false, cBias, cMass, cImpulse)
		end
	end

	applyRestitution(world)

	-- joint error diagnostics (distance between the two anchor points)
	for _, j in world.joints do
		local A, B = j.bodyA, j.bodyB
		local ex = (B.x + B.c * j.lbx - B.s * j.lby) - (A.x + A.c * j.lax - A.s * j.lay)
		local ey = (B.y + B.s * j.lbx + B.c * j.lby) - (A.y + A.s * j.lax + A.c * j.lay)
		j.error = sqrt(ex * ex + ey * ey)
	end

	world.stepIndex += 1
	world.time += dt
end

----------------------------------------------------------------------------------------------------
-- Queries and diagnostics
----------------------------------------------------------------------------------------------------

-- World position of a point given in a body's local frame.
function Solver2D.worldPoint(b: Body, lx: number, ly: number): (number, number)
	return b.x + b.c * lx - b.s * ly, b.y + b.s * lx + b.c * ly
end

-- Velocity of a world point attached to a body.
function Solver2D.pointVelocity(b: Body, wx: number, wy: number): (number, number)
	return b.vx - b.w * (wy - b.y), b.vy + b.w * (wx - b.x)
end

export type Metrics = {
	mass: number,
	comX: number,
	comY: number,
	comVX: number,
	comVY: number,
	kinetic: number,
	potential: number,
	momentumX: number,
	momentumY: number,
	angularMomentum: number, -- about the dynamic bodies' centre of mass
	maxJointError: number,
	contactCount: number,
	maxSpeed: number,
}

-- Energy and momentum of the dynamic bodies. `g` is the gravity magnitude (potential uses y).
function Solver2D.metrics(world: World, g: number): Metrics
	local m, mx, my, px, py, ke, pe, maxSpeed = 0, 0, 0, 0, 0, 0, 0, 0
	for _, b in world.bodies do
		if b.kind ~= Solver2D.DYNAMIC then
			continue
		end
		m += b.mass
		mx += b.mass * b.x
		my += b.mass * b.y
		px += b.mass * b.vx
		py += b.mass * b.vy
		local v2 = b.vx * b.vx + b.vy * b.vy
		ke += 0.5 * (b.mass * v2 + b.inertia * b.w * b.w)
		pe += b.mass * g * b.y
		if v2 > maxSpeed * maxSpeed then
			maxSpeed = sqrt(v2)
		end
	end
	local cx, cy = if m > 0 then mx / m else 0, if m > 0 then my / m else 0
	local cvx, cvy = if m > 0 then px / m else 0, if m > 0 then py / m else 0
	local L = 0
	for _, b in world.bodies do
		if b.kind ~= Solver2D.DYNAMIC then
			continue
		end
		local rx, ry = b.x - cx, b.y - cy
		local vx, vy = b.vx - cvx, b.vy - cvy
		L += b.inertia * b.w + b.mass * (rx * vy - ry * vx)
	end
	local maxErr = 0
	for _, j in world.joints do
		if j.error > maxErr then
			maxErr = j.error
		end
	end
	return {
		mass = m,
		comX = cx,
		comY = cy,
		comVX = cvx,
		comVY = cvy,
		kinetic = ke,
		potential = pe,
		momentumX = px,
		momentumY = py,
		angularMomentum = L,
		maxJointError = maxErr,
		contactCount = #world.contacts,
		maxSpeed = maxSpeed,
	}
end

-- True if any dynamic body has a non-finite state.
function Solver2D.hasInvalidState(world: World): boolean
	for _, b in world.bodies do
		for _, v in { b.x, b.y, b.a, b.vx, b.vy, b.w } do
			if v ~= v or v == math.huge or v == -math.huge then
				return true
			end
		end
	end
	return false
end

-- Order-dependent hash of every body's state (used by determinism tests).
function Solver2D.checksum(world: World): string
	local parts = table.create(#world.bodies * 6)
	for _, b in world.bodies do
		table.insert(
			parts,
			string.format("%.17g,%.17g,%.17g,%.17g,%.17g,%.17g", b.x, b.y, b.a, b.vx, b.vy, b.w)
		)
	end
	return table.concat(parts, ";")
end

return Solver2D
