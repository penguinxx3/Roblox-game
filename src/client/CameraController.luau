--!strict
-- CameraController: calm side view of the motion plane.
--
-- Looks along -Z at the body's centre of mass, following it with frame-rate
-- independent exponential smoothing. No roll, no shake.

local CameraController = {}
CameraController.__index = CameraController

export type Settings = {
	distance: number,
	fov: number,
	height: number,
	followHertz: number,
	minFocusY: number,
}

CameraController.defaults = {
	distance = 24,
	fov = 50,
	height = 1.0,
	followHertz = 2.5,
	minFocusY = 3,
} :: Settings

export type CameraController = typeof(setmetatable(
	{} :: {
		camera: Camera,
		settings: Settings,
		focus: Vector3?,
	},
	CameraController
))

function CameraController.new(settings: Settings?): CameraController
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	return setmetatable({
		camera = camera,
		settings = settings or table.clone(CameraController.defaults),
		focus = nil,
	}, CameraController)
end

function CameraController.snap(self: CameraController, target: Vector3)
	self.focus = target
end

function CameraController.update(self: CameraController, target: Vector3, dt: number)
	local s = self.settings
	target = Vector3.new(target.X, math.max(target.Y, s.minFocusY), 0)
	local focus = self.focus
	if focus == nil then
		focus = target
	else
		local k = 1 - math.exp(-2 * math.pi * s.followHertz * math.max(dt, 0))
		focus = focus:Lerp(target, k)
	end
	self.focus = focus
	local cam = self.camera
	cam.FieldOfView = s.fov
	local eye = (focus :: Vector3) + Vector3.new(0, s.height, s.distance)
	cam.CFrame = CFrame.lookAt(eye, (focus :: Vector3) + Vector3.new(0, s.height * 0.5, 0))
end

return CameraController
