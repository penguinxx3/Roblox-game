-- Headless test entry point (Lune): `lune run tests/run.luau [--quick] [filter]`
local fs = require("@lune/fs")
local process = require("@lune/process")

local Mirror = require("../tools/lune_mirror")
Mirror.build("build/lune")
local Runner = require("../build/lune/GymTests/TestRunner")

local quick = false
local filter: string? = nil
for _, arg in process.args do
	if arg == "--quick" then
		quick = true
	else
		filter = arg
	end
end

local specs = {}
local names = fs.readDir("build/lune/GymTests")
table.sort(names)
for _, file in names do
	local base = file:match("^(.-%.spec)%.luau$")
	if base and (filter == nil or base:lower():find(filter:lower(), 1, true)) then
		table.insert(specs, { name = base, fn = require("../build/lune/GymTests/" .. base) })
	end
end

local summary = Runner.run(specs, { quick = quick })
process.exit(if summary.failed > 0 then 1 else 0)
