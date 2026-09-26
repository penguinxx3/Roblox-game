-- Mirrors the shared Roblox-style source into build/lune/ for headless runs in Lune.
--
-- The core is written for Roblox (`require(script.Parent.X)`, fully typed in Studio).
-- Lune has no `script` global, so this copies src/shared/{Gym,GymTests} and rewrites
-- only those require lines to file requires (`require("./X")`). Nothing else changes.

local fs = require("@lune/fs")

local Mirror = {}

local FOLDERS = { "Gym", "GymTests" }

function Mirror.build(root: string?): string
	local out = (root or "build/lune")
	for _, folder in FOLDERS do
		local src = "src/shared/" .. folder
		local dst = out .. "/" .. folder
		if fs.isDir(dst) then
			fs.removeDir(dst)
		end
		fs.writeDir(dst)
		for _, name in fs.readDir(src) do
			if name:match("%.luau$") then
				local source = fs.readFile(src .. "/" .. name)
				local rewritten = source:gsub("require%(script%.Parent%.([%w_]+)%)", 'require("./%1")')
				fs.writeFile(dst .. "/" .. name, rewritten)
			end
		end
	end
	return out
end

return Mirror
