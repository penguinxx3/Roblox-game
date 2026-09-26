-- Prints the game tree of a built place file and checks key settings.
-- Usage: lune run tools/inspect_place.luau build/BarGym.rbxl
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local path = process.args[1] or "build/BarGym.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local function walk(inst, depth)
	if depth > 4 then
		return
	end
	local extra = ""
	if inst:IsA("LuaSourceContainer") then
		extra = string.format(" (%d bytes)", #inst.Source)
	end
	print(string.rep("  ", depth) .. inst.ClassName .. " " .. inst.Name .. extra)
	for _, child in inst:GetChildren() do
		walk(child, depth + 1)
	end
end
for _, name in { "ReplicatedStorage", "ServerScriptService", "StarterPlayer" } do
	walk(game:GetService(name), 0)
end
local players = game:GetService("Players")
print("Players.CharacterAutoLoads =", players.CharacterAutoLoads)
