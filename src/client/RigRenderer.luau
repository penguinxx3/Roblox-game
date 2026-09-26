--!strict
-- RigRenderer: draws the simulated body as a stickman made of anchored parts.
--
-- Presentation only: it reads body poses (interpolated between fixed steps) and
-- never writes to the simulation. All parts move in one BulkMoveTo call per frame.
--
-- Look: our own style (not the reference's): rounded white limbs, a teal torso,
-- far-side limbs slightly darker for depth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gym = ReplicatedStorage:WaitForChild("Gym")
local Sim = require(Gym:WaitForChild("Sim"))
local Plane = require(script.Parent:WaitForChild("Plane"))

local RigRenderer = {}
RigRenderer.__index = RigRenderer

local NEAR_COLOR = Color3.fromRGB(245, 244, 238)
local FAR_COLOR = Color3.fromRGB(196, 198, 204)
local TORSO_COLOR = Color3.fromRGB(38, 178, 164)
local HEAD_COLOR = Color3.fromRGB(245, 244, 238)

type Item = {
	part: Part,
	body: any,
	kind: string, -- "cylinder" | "cap0" | "cap1" | "head"
	seg: any,
	depth: number,
}

export type RigRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		items: { Item },
		parts: { Part },
		cframes: { CFrame },
		headLocalX: number,
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
	p.Material = Enum.Material.SmoothPlastic
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
		headLocalX = sim.rig.headLocalX,
	}, RigRenderer)

	local function addCapsule(seg: any, depth: number, color: Color3)
		local d = seg.radius * 2
		local cyl = makePart(Enum.PartType.Cylinder, color, folder)
		cyl.Size = Vector3.new(seg.length, d, d)
		cyl.Name = seg.name
		table.insert(self.items, { part = cyl, body = seg.body, kind = "cylinder", seg = seg, depth = depth })
		for _, kind in { "cap0", "cap1" } do
			local cap = makePart(Enum.PartType.Ball, color, folder)
			cap.Size = Vector3.new(d, d, d)
			cap.Name = seg.name .. "Cap"
			table.insert(self.items, { part = cap, body = seg.body, kind = kind, seg = seg, depth = depth })
		end
	end

	for _, seg in sim.rig.segments do
		if seg.name == "torso" then
			addCapsule(seg, 0, TORSO_COLOR)
			local head = makePart(Enum.PartType.Ball, HEAD_COLOR, folder)
			local d = 2 * 0.45
			head.Size = Vector3.new(d, d, d)
			head.Name = "head"
			table.insert(self.items, { part = head, body = seg.body, kind = "head", seg = seg, depth = 0 })
		elseif seg.paired then
			addCapsule(seg, -Plane.PAIR_DEPTH, FAR_COLOR)
			addCapsule(seg, Plane.PAIR_DEPTH, NEAR_COLOR)
		else
			addCapsule(seg, 0, NEAR_COLOR)
		end
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
		local body = item.body
		local pose = cache[body]
		if pose == nil then
			local x, y, a = Sim.bodyPose(body, alpha)
			pose = { x, y, a, math.cos(a), math.sin(a) }
			cache[body] = pose
		end
		local x, y, a, c, s = pose[1], pose[2], pose[3], pose[4], pose[5]
		local seg = item.seg
		local kind = item.kind
		if kind == "cylinder" then
			local mx, my = (seg.p0x + seg.p1x) / 2, (seg.p0y + seg.p1y) / 2
			local sa = math.atan2(seg.p1y - seg.p0y, seg.p1x - seg.p0x)
			cframes[i] = Plane.along(x + c * mx - s * my, y + s * mx + c * my, a + sa, item.depth)
		elseif kind == "cap0" then
			cframes[i] = CFrame.new(x + c * seg.p0x - s * seg.p0y, y + s * seg.p0x + c * seg.p0y, item.depth)
		elseif kind == "cap1" then
			cframes[i] = CFrame.new(x + c * seg.p1x - s * seg.p1y, y + s * seg.p1x + c * seg.p1y, item.depth)
		else -- head
			local hx = self.headLocalX
			cframes[i] = CFrame.new(x + c * hx, y + s * hx, item.depth)
		end
	end
	workspace:BulkMoveTo(self.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function RigRenderer.destroy(self: RigRenderer)
	self.folder:Destroy()
end

return RigRenderer
