--!strict
-- Tiny test harness shared by the headless runner (Lune) and the in-Studio self-test.
--
-- A spec module returns `function(T)` and registers tests with `T.test(name, fn, opts)`.
-- Inside a test, use T.expect / T.near / T.note. `T.gym(name)` returns a core module
-- (Solver2D, Sim, ...) in either environment.

local Runner = {}

export type Result = {
	spec: string,
	name: string,
	ok: boolean,
	message: string?,
	notes: { string },
	ms: number,
	skipped: boolean,
}

local function gym(name: string): any
	if script ~= nil then
		local folder = (script :: any).Parent.Parent:WaitForChild("Gym")
		return (require :: any)(folder:WaitForChild(name))
	end
	return (require :: any)("../Gym/" .. name)
end

local function fmt(v: any): string
	if type(v) == "number" then
		return string.format("%.6g", v)
	end
	return tostring(v)
end

-- Runs `specs` ({ { name = string, fn = function(T) } }). Options:
--   quick = true   skip tests registered with { slow = true }
--   print = fn     output function (default print)
function Runner.run(
	specs: { { name: string, fn: (any) -> () } },
	options: { quick: boolean?, print: ((string) -> ())? }?
)
	local opts: { quick: boolean?, print: ((string) -> ())? } = options or {}
	local out: (string) -> () = opts.print or function(line: string)
		print(line)
	end
	local results: { Result } = {}
	local clock = os.clock

	for _, spec in specs do
		local tests = {}
		local T = {}
		T.gym = gym
		function T.test(name: string, fn: () -> (), topts: { slow: boolean? }?)
			table.insert(tests, { name = name, fn = fn, slow = topts and topts.slow or false })
		end
		spec.fn(T)

		for _, test in tests do
			local notes: { string } = {}
			local result: Result = {
				spec = spec.name,
				name = test.name,
				ok = true,
				message = nil,
				notes = notes,
				ms = 0,
				skipped = false,
			}
			if opts.quick and test.slow then
				result.skipped = true
				table.insert(results, result)
				out(string.format("SKIP  %s :: %s (slow; quick mode)", spec.name, test.name))
				continue
			end
			T.note = function(label: string, value: any)
				table.insert(notes, `{label}={fmt(value)}`)
			end
			T.expect = function(cond: any, message: string?)
				if not cond then
					error(message or "expectation failed", 2)
				end
			end
			T.near = function(actual: number, expected: number, tolerance: number, label: string?)
				if not (math.abs(actual - expected) <= tolerance) then
					error(
						string.format(
							"%s: expected %s ± %s, got %s",
							label or "value",
							fmt(expected),
							fmt(tolerance),
							fmt(actual)
						),
						2
					)
				end
			end
			T.below = function(actual: number, limit: number, label: string?)
				if not (actual <= limit) then
					error(
						string.format(
							"%s: expected ≤ %s, got %s",
							label or "value",
							fmt(limit),
							fmt(actual)
						),
						2
					)
				end
			end
			T.above = function(actual: number, limit: number, label: string?)
				if not (actual >= limit) then
					error(
						string.format(
							"%s: expected ≥ %s, got %s",
							label or "value",
							fmt(limit),
							fmt(actual)
						),
						2
					)
				end
			end
			local t0 = clock()
			local ok: boolean, err: any = pcall(test.fn)
			result.ms = (clock() - t0) * 1000
			result.ok = ok
			if not ok then
				result.message = tostring(err)
			end
			table.insert(results, result)
			local noteText = if #notes > 0 then "  [" .. table.concat(notes, ", ") .. "]" else ""
			if ok then
				out(string.format("PASS  %s :: %s (%.0f ms)%s", spec.name, test.name, result.ms, noteText))
			else
				out(
					string.format(
						"FAIL  %s :: %s (%.0f ms)%s\n      %s",
						spec.name,
						test.name,
						result.ms,
						noteText,
						result.message or ""
					)
				)
			end
		end
	end

	local passed, failed, skipped = 0, 0, 0
	for _, r in results do
		if r.skipped then
			skipped += 1
		elseif r.ok then
			passed += 1
		else
			failed += 1
		end
	end
	out(string.format("\n%d passed, %d failed, %d skipped", passed, failed, skipped))
	return { results = results, passed = passed, failed = failed, skipped = skipped }
end

return Runner
