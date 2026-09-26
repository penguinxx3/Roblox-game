--!strict
-- GymServer: nothing gameplay-related runs on the server in P1.1 (each client simulates
-- and renders its own gymnast; multiplayer is designed for but not built yet).
--
-- In Studio, the quick physics self-test runs once when a playtest starts. Results are
-- printed to Output ("[GymSelfTest] ...") and stored as attributes on
-- ReplicatedStorage.GymTests (SelfTestStatus / SelfTestPassed / SelfTestFailed / SelfTestSkipped).
-- Disable by setting this script's `SelfTestOnPlay` attribute to false.
-- Full suite (including slow tests) from the command bar:
--   require(game.ReplicatedStorage.GymTests.StudioRun)(false)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if RunService:IsStudio() and script:GetAttribute("SelfTestOnPlay") ~= false then
	task.defer(function()
		local StudioRun = require(ReplicatedStorage.GymTests.StudioRun)
		StudioRun(true)
	end)
end
