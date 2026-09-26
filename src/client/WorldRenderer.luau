--!strict
-- WorldRenderer: draws the simulation's world geometry (floor, blocks, ramps, grip
-- anchors, moving equipment). What you see is exactly what the solver collides with:
-- every visual is generated from the simulation's own shapes.
--
-- Palette is our own (warm grey floor, slate blocks, steel bar, amber wheel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Plane = require(script.Parent:WaitForChild("Plane"))
local Sim = require(ReplicatedStorage:WaitForChild("Gym"):WaitForChild("Sim"))

local WorldRenderer = {}
WorldRenderer.__index = WorldRenderer

local DEPTH = 16 -- visual extrusion of the 2D world along Z
local FLOOR_COLOR = Color3.fromRGB(206, 201, 191)
local BLOCK_COLOR = Color3.fromRGB(92, 108, 128)
local STEEL_COLOR = Color3.fromRGB(170, 176, 184)
local WHEEL_COLOR = Color3.fromRGB(232, 168, 56)

export type WorldRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		moving: { { part: Part, body: any, offset: CFrame } },
		contactParts: { Part },
	},
	WorldRenderer
))

local function style(p: BasePart, color: Color3, material: Enum.Material?)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

-- Extruded triangle prism (two wedges), for any triangle in the plane.
local function triangle(a: Vector3, b: Vector3, c: Vector3, depth: number, color: Color3, parent: Instance)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local w1 = Instance.new("WedgePart")
	w1.Size = Vector3.new(depth, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	style(w1, color)
	w1.Parent = parent
	local w2 = Instance.new("WedgePart")
	w2.Size = Vector3.new(depth, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	style(w2, color)
	w2.Parent = parent
end

function WorldRenderer.new(sim: any, parent: Instance): WorldRenderer
	local folder = Instance.new("Folder")
	folder.Name = "Course"
	folder.Parent = parent
	local self = setmetatable({ folder = folder, moving = {}, contactParts = {} }, WorldRenderer)

	for _, visual in sim.visuals do
		local kind = visual.kind
		if visual.shape and visual.shape.polygon then
			local poly = visual.shape.polygon
			local color = if kind == "floor" then FLOOR_COLOR else BLOCK_COLOR
			if
				poly.count == 4
				and math.abs(poly.y[1] - poly.y[2]) < 1e-6
				and math.abs(poly.x[2] - poly.x[3]) < 1e-6
			then
				-- axis-aligned box
				local p = Instance.new("Part")
				p.Size = Vector3.new(
					poly.maxX - poly.minX,
					poly.maxY - poly.minY,
					if kind == "floor" then 80 else DEPTH
				)
				p.CFrame = CFrame.new((poly.minX + poly.maxX) / 2, (poly.minY + poly.maxY) / 2, 0)
				style(p, color, if kind == "floor" then Enum.Material.Concrete else nil)
				p.Name = kind
				p.Parent = folder
			else
				-- fan-triangulate the convex polygon
				for i = 2, poly.count - 1 do
					triangle(
						Plane.point(poly.x[1], poly.y[1]),
						Plane.point(poly.x[i], poly.y[i]),
						Plane.point(poly.x[i + 1], poly.y[i + 1]),
						DEPTH,
						color,
						folder
					)
				end
			end
		elseif kind == "anchor" then
			-- a bar crossing the motion plane, with two posts outside the plane
			local x, y = visual.x :: number, visual.y :: number
			local bar = Instance.new("Part")
			bar.Shape = Enum.PartType.Cylinder
			bar.Size = Vector3.new(4, 0.24, 0.24)
			bar.CFrame = CFrame.new(x, y, 0) * CFrame.Angles(0, math.pi / 2, 0)
			style(bar, STEEL_COLOR, Enum.Material.Metal)
			bar.Name = "Bar"
			bar.Parent = folder
			for _, z in { -2, 2 } do
				local post = Instance.new("Part")
				post.Size = Vector3.new(0.3, y, 0.3)
				post.CFrame = CFrame.new(x, y / 2, z)
				style(post, STEEL_COLOR, Enum.Material.Metal)
				post.Parent = folder
			end
		elseif kind == "wheel" then
			local body = visual.body
			local radius = visual.radius :: number
			local disc = Instance.new("Part")
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.6, 1.2, 1.2)
			style(disc, WHEEL_COLOR)
			disc.Name = "WheelHub"
			disc.Parent = folder
			table.insert(self.moving, {
				part = disc,
				body = body,
				offset = CFrame.new(0, 0, -0.6) * CFrame.Angles(0, math.pi / 2, 0),
			})
			local spokes = visual.spokes or 4
			for k = 0, spokes - 1 do
				local ang = k * 2 * math.pi / spokes
				local spoke = Instance.new("Part")
				spoke.Size = Vector3.new(radius, 0.18, 0.18)
				style(spoke, STEEL_COLOR, Enum.Material.Metal)
				spoke.Parent = folder
				table.insert(self.moving, {
					part = spoke,
					body = body,
					offset = CFrame.Angles(0, 0, ang) * CFrame.new(radius / 2, 0, -0.3),
				})
				local handle = Instance.new("Part")
				handle.Shape = Enum.PartType.Cylinder
				handle.Size = Vector3.new(1.4, 0.2, 0.2)
				style(handle, STEEL_COLOR, Enum.Material.Metal)
				handle.Parent = folder
				table.insert(self.moving, {
					part = handle,
					body = body,
					offset = CFrame.Angles(0, 0, ang)
						* CFrame.new(radius, 0, 0)
						* CFrame.Angles(0, math.pi / 2, 0),
				})
			end
		end
	end

	-- contact point markers (debug; hidden until enabled)
	for i = 1, 16 do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(0.18, 0.18, 0.18)
		style(p, Color3.fromRGB(255, 70, 70), Enum.Material.Neon)
		p.Transparency = 1
		p.Name = "Contact" .. i
		p.Parent = folder
		self.contactParts[i] = p
	end
	return self
end

function WorldRenderer.draw(self: WorldRenderer, alpha: number, sim: any, showContacts: boolean)
	for _, m in self.moving do
		local x, y, a = Sim.bodyPose(m.body, alpha)
		m.part.CFrame = Plane.along(x, y, a) * m.offset
	end
	local contacts = sim.world.contacts
	for i, p in self.contactParts do
		local cp = contacts[i]
		if showContacts and cp then
			local b = cp.bodyA
			local wx = b.x + b.c * cp.lax - b.s * cp.lay
			local wy = b.y + b.s * cp.lax + b.c * cp.lay
			p.CFrame = CFrame.new(wx, wy, 0.5)
			p.Transparency = 0
		elseif p.Transparency ~= 1 then
			p.Transparency = 1
		end
	end
end

function WorldRenderer.destroy(self: WorldRenderer)
	self.folder:Destroy()
end

return WorldRenderer
