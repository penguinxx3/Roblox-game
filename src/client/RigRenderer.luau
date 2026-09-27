--!strict
-- RigRenderer: draws the simulated body as a stickman made of anchored parts.
--
-- Presentation only: it reads body poses (interpolated between fixed steps) and
-- never writes to the simulation. All parts move in one BulkMoveTo call per frame.
-- Twist (P1.2) turns the whole drawn body about its long axis through the centre of mass
-- (Pose3D), so the planar body can face toward or away from the camera mid-air.
--
-- Look: a wooden figure: one rectangular torso block, a head on a neck, slim limbs with
-- darker joint balls, darker feet, far-side limbs a shade darker for depth. The proportions and
-- the colours (Look.PALETTE, hex codes) come from Look (shared, presentation only); the physics
-- collision shapes are not drawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gym = ReplicatedStorage:WaitForChild("Gym")
local Sim = require(Gym:WaitForChild("Sim"))
local Pose3D = require(Gym:WaitForChild("Pose3D"))
local Look = require(Gym:WaitForChild("Look"))
local Plane = require(script.Parent:WaitForChild("Plane"))

local RigRenderer = {}
RigRenderer.__index = RigRenderer

local MATERIAL = Enum.Material.Wood -- SmoothPlastic for a plain finish

-- A shape's colour: its role's palette entry; the far copy of a limb uses "<role>Far" if set.
local function colorOf(p: Look.Prim): Color3
	local P: { [string]: string } = Look.PALETTE
	local hex = if p.side < 0 then P[p.role .. "Far"] or P[p.role] else P[p.role]
	return Color3.fromHex(hex)
end

type Item = {
	part: Part,
	prim: Look.Prim,
}

export type RigRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		items: { Item },
		parts: { Part },
		cframes: { CFrame },
		sim: any,
	},
	RigRenderer
))

local function makePart(shape: Enum.PartType, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Material = MATERIAL
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function RigRenderer.new(sim: any, parent: Instance): RigRenderer
	local folder = Instance.new("Folder")
	folder.Name = "Gymnast"
	folder.Parent = parent
	local self = setmetatable({
		folder = folder,
		items = {},
		parts = {},
		cframes = {},
		sim = sim,
	}, RigRenderer)

	for _, p in Look.build(sim.rig) do
		local color = colorOf(p)
		local part: Part
		if p.kind == "ball" then
			part = makePart(Enum.PartType.Ball, color, folder)
			part.Size = Vector3.new(2 * p.r, 2 * p.r, 2 * p.r)
		elseif p.kind == "rod" then
			-- a cylinder along its X axis; the joint balls round off the ends
			part = makePart(Enum.PartType.Cylinder, color, folder)
			local dx, dy = p.bx - p.ax, p.by - p.ay
			part.Size = Vector3.new(math.sqrt(dx * dx + dy * dy), 2 * p.r, 2 * p.r)
		else
			part = makePart(Enum.PartType.Block, color, folder)
			part.Size = Vector3.new(p.len, p.thick, p.width)
		end
		part.Name = p.name
		table.insert(self.items, { part = part, prim = p })
	end
	for i, item in self.items do
		self.parts[i] = item.part
		self.cframes[i] = CFrame.identity
	end
	return self
end

-- Positions every part from the interpolated simulation state.
function RigRenderer.draw(self: RigRenderer, alpha: number)
	local cframes = self.cframes
	local cache: { [any]: { number } } = {}
	for i, item in self.items do
		local p = item.prim
		local body = p.seg.body
		local pose = cache[body]
		if pose == nil then
			local x, y, a = Sim.bodyPose(body, alpha)
			pose = { x, y, a }
			cache[body] = pose
		end
		local u, v, angle = Look.place(p, pose[1], pose[2], pose[3])
		if p.kind == "ball" then
			cframes[i] = CFrame.new(u, v, p.depth)
		else
			cframes[i] = Plane.along(u, v, angle, p.depth)
		end
	end
	-- twist: turn everything about the long axis through the centre of mass
	local sim = self.sim
	local psi = Sim.renderTwist(sim, alpha)
	if psi ~= 0 then
		local f = Pose3D.frame(sim.rig, psi, alpha, Sim.bodyPose)
		local pivot = CFrame.new(f.cu, f.cv, 0)
		local axis = Vector3.new(math.cos(f.axisAngle), math.sin(f.axisAngle), 0)
		local twist = pivot * CFrame.fromAxisAngle(axis, psi) * pivot:Inverse()
		for i, cf in cframes do
			cframes[i] = twist * cf
		end
	end
	workspace:BulkMoveTo(self.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function RigRenderer.destroy(self: RigRenderer)
	self.folder:Destroy()
end

return RigRenderer
