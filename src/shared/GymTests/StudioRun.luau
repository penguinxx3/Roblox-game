--!strict
-- Runs the physics test specs inside Roblox (same specs as the headless Lune runner).
-- Usage (server or command bar):  require(game.ReplicatedStorage.GymTests.StudioRun)(quick)
--   quick = true  (default) skips the slow tests; false runs everything.
-- Results are printed with the "[GymSelfTest]" prefix and stored as attributes on this
-- module's parent folder.

local Runner = require(script.Parent.TestRunner)

return function(quick: boolean?)
	local folder = script.Parent
	local specs = {}
	for _, m in folder:GetChildren() do
		if m:IsA("ModuleScript") and string.match(m.Name, "%.spec$") then
			table.insert(specs, { name = m.Name, fn = (require :: any)(m) })
		end
	end
	table.sort(specs, function(a, b)
		return a.name < b.name
	end)
	folder:SetAttribute("SelfTestStatus", "running")
	local isQuick = quick ~= false
	local t0 = os.clock()
	local summary = Runner.run(specs, {
		quick = isQuick,
		print = function(line: string)
			print("[GymSelfTest] " .. line)
		end,
	})
	folder:SetAttribute("SelfTestPassed", summary.passed)
	folder:SetAttribute("SelfTestFailed", summary.failed)
	folder:SetAttribute("SelfTestSkipped", summary.skipped)
	folder:SetAttribute("SelfTestSeconds", os.clock() - t0)
	folder:SetAttribute("SelfTestMode", if isQuick then "quick" else "full")
	folder:SetAttribute("SelfTestStatus", if summary.failed == 0 then "passed" else "failed")
	return summary
end
