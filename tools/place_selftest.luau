-- Place-level self-test (no Studio needed): loads the BUILT place file, compiles every
-- script in it, and runs ReplicatedStorage.GymTests.StudioRun through the same
-- instance-based `require` path Roblox uses (script.Parent:FindFirstChild(...)),
-- i.e. the code exactly as it ships in the .rbxl.
--
-- It does NOT emulate the Roblox engine (rendering, input, RunService); client
-- scripts are compiled, not executed. Studio validation is still required for those.
--
-- Usage: lune run tools/place_selftest.luau [build/BarGym.rbxl] [--full]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = "build/BarGym.rbxl"
local full = false
for _, a in process.args do
	if a == "--full" then
		full = true
	else
		path = a
	end
end

-- Minimal engine polyfills needed by the shared code paths.
roblox.implementMethod("Instance", "WaitForChild", function(inst, name)
	local child = inst:FindFirstChild(name)
	assert(child, `WaitForChild: {inst:GetFullName()} has no child '{name}'`)
	return child
end)

local game = roblox.deserializePlace(fs.readFile(path))

-- 1. Compile every script in the place (syntax check).
local compiled, failures = 0, 0
for _, inst in game:GetDescendants() do
	if inst:IsA("LuaSourceContainer") then
		local ok, err = pcall(luau.compile, inst.Source)
		compiled += 1
		if not ok then
			failures += 1
			print("COMPILE ERROR", inst:GetFullName(), err)
		end
	end
end
print(string.format("compiled %d scripts, %d errors", compiled, failures))

-- 2. Instance-based require, as in Roblox.
local cache = {}
local function requireInstance(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local env = {
		script = module,
		game = game,
		workspace = game:GetService("Workspace"),
		require = function(target)
			if typeof(target) == "Instance" then
				return requireInstance(target)
			end
			error(
				`unexpected string require '{tostring(target)}' in Roblox code path ({module:GetFullName()})`,
				2
			)
		end,
	}
	local fn = luau.load(module.Source, {
		debugName = module:GetFullName(),
		environment = env,
		injectGlobals = true,
	})
	local result = fn()
	cache[module] = result
	return result
end

local studioRun = requireInstance(game:GetService("ReplicatedStorage").GymTests.StudioRun)
local summary = studioRun(not full)
local folder = game:GetService("ReplicatedStorage").GymTests
print(
	"attributes:",
	folder:GetAttribute("SelfTestStatus"),
	folder:GetAttribute("SelfTestPassed"),
	folder:GetAttribute("SelfTestFailed"),
	folder:GetAttribute("SelfTestSkipped")
)
process.exit(if summary.failed > 0 or failures > 0 then 1 else 0)
