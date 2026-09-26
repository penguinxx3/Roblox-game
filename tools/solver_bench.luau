-- Solver settings benchmark: joint stretch, energy drift and cost across substeps / jointHertz.
-- Use when changing solver defaults. Usage: lune run tools/solver_bench.luau
require("./lune_mirror").build("build/lune")
local Sim = require("../build/lune/Gym/Sim")
local Solver2D = require("../build/lune/Gym/Solver2D")

local function pendulumDrift(substeps: number, jointHertz: number): number
	local p = Solver2D.defaultParams()
	p.gravityY, p.substeps, p.angularDamping, p.jointHertz = -35, substeps, 0, jointHertz
	local w = Solver2D.newWorld(p)
	local L, m = 3, 2
	local b = Solver2D.addBody(w, { x = L / 2, y = 10, mass = m, inertia = m * L * L / 12 })
	Solver2D.addRevolute(w, w.ground, b, 0, 10)
	local m0 = Solver2D.metrics(w, 35)
	local E0, worst = m0.kinetic + m0.potential, 0
	for _ = 1, 240 * 60 do
		Solver2D.step(w, 1 / 240)
		local e = Solver2D.metrics(w, 35)
		worst = math.max(worst, math.abs(e.kinetic + e.potential - E0))
	end
	return worst / (m * 35 * L / 2) * 100
end

local function giant(over): (number, number, number)
	local sim = Sim.new(over, "Hang")
	for _, seg in sim.rig.segments do
		local b = seg.body
		local rx, ry = b.x, b.y - 10
		b.vx, b.vy, b.w = -6 * ry, 6 * rx, 6
	end
	local maxErr, maxGrip = 0, 0
	local t0 = os.clock()
	for _ = 1, 240 * 6 do
		Sim.stepOnce(sim)
		for _, rj in sim.rig.joints do
			maxErr = math.max(maxErr, rj.joint.error)
		end
		maxGrip = math.max(maxGrip, (sim.grip :: any).error)
	end
	return maxErr, maxGrip, (os.clock() - t0) / (240 * 6) * 1e6
end

print("substeps jointHz | giant joint  grip  | 60s pendulum drift | µs/step")
for _, sub in { 2, 4, 8 } do
	for _, hz in { 60, 120, 240 } do
		local j, g, us = giant({ substeps = sub, jointHertz = hz })
		print(
			string.format(
				"   %d      %3d   |   %.4f   %.4f |      %.2f%%        | %.1f",
				sub,
				hz,
				j,
				g,
				pendulumDrift(sub, hz),
				us
			)
		)
	end
end
