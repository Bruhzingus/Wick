--!strict

local Harness = require(script.Parent.Harness)
local DepthConfig = require(script.Parent.Parent.Config.Depth)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local DepthRules = require(script.Parent.Parent.Logic.DepthRules)

local CEILING = DepthConfig.prototypeCeiling

local function rejects(fn: () -> ()): boolean
	return not (pcall(fn))
end

local suite: Harness.Suite = {
	name = "DepthRules",
	tests = {
		Harness.test("global depth is start depth plus completed local floors", function()
			Harness.equal(DepthRules.getGlobalDepth(1, 1), 1)
			Harness.equal(DepthRules.getGlobalDepth(1, 10), 10)
			Harness.equal(DepthRules.getGlobalDepth(5, 1), 5)
			Harness.equal(DepthRules.getGlobalDepth(5, 6), 10)
		end),

		Harness.test("invalid depth input is rejected, never silently repaired", function()
			local nan = 0 / 0
			for _, bad in { 0, -1, -12, 1.5, nan, math.huge, -math.huge } do
				Harness.expect(
					rejects(function()
						DepthRules.getGlobalDepth(bad, 1)
					end),
					"startDepth " .. tostring(bad) .. " should be rejected"
				)
				Harness.expect(
					rejects(function()
						DepthRules.getGlobalDepth(1, bad)
					end),
					"localFloor " .. tostring(bad) .. " should be rejected"
				)
				Harness.expect(not DepthRules.isValidFloorNumber(bad), tostring(bad) .. " is not a floor number")
				Harness.expect(not DepthRules.isSupportedDepth(bad), tostring(bad) .. " is not a supported depth")
			end
		end),

		Harness.test("depth past the technical ceiling is refused by every scaling function", function()
			local beyond = CEILING + 1
			Harness.expect(DepthRules.isSupportedDepth(CEILING), "the ceiling itself must be supported")
			Harness.expect(not DepthRules.isSupportedDepth(beyond), "past the ceiling must not be supported")
			local scalers: { (number) -> any } = {
				DepthRules.getDepthBand,
				DepthRules.getThreatBudgetMultiplier,
				DepthRules.getHazardBudgetMultiplier,
				DepthRules.getRoomCountTarget,
				DepthRules.getRewardDepthMultiplier,
			}
			for index, scaler in scalers do
				Harness.expect(
					rejects(function()
						scaler(beyond)
					end),
					"scaling function " .. index .. " accepted an unsupported depth"
				)
			end
		end),

		Harness.test("every band is named and the bands cover the supported range", function()
			for depth = 1, CEILING do
				local band = DepthRules.getDepthBand(depth)
				Harness.expect(type(band) == "string" and #band > 0, "depth " .. depth .. " has no band")
			end
			Harness.equal(DepthRules.getDepthBand(1), "Introduction")
			Harness.equal(DepthRules.getDepthBand(CEILING), DepthConfig.bands[#DepthConfig.bands].id)
		end),

		Harness.test("scaling stays finite, bounded, and monotonic across every supported depth", function()
			local previousThreat, previousHazard, previousRooms, previousReward = 0, 0, 0, 0
			for depth = 1, CEILING do
				local threat = DepthRules.getThreatBudgetMultiplier(depth)
				local hazard = DepthRules.getHazardBudgetMultiplier(depth)
				local rooms = DepthRules.getRoomCountTarget(depth)
				local reward = DepthRules.getRewardDepthMultiplier(depth)

				for _, value in { threat, hazard, rooms, reward } do
					Harness.expect(value == value and value < math.huge, "depth " .. depth .. " produced a bad value")
				end
				Harness.expect(threat >= 1 and threat <= DepthConfig.threatBudget.maximum, "threat multiplier escaped")
				Harness.expect(hazard >= 1 and hazard <= DepthConfig.hazardBudget.maximum, "hazard multiplier escaped")
				Harness.expect(
					rooms >= 1 and rooms <= DepthConfig.maxRoomsPerFloor and math.floor(rooms) == rooms,
					"room count escaped its bounds at depth " .. depth
				)
				Harness.expect(
					reward > 0 and reward <= DepthConfig.maxRewardDepthMultiplier,
					"reward multiplier escaped at depth " .. depth
				)

				-- Deeper is never accidentally easier or less rewarding.
				Harness.expect(threat >= previousThreat, "threat budget fell at depth " .. depth)
				Harness.expect(hazard >= previousHazard, "hazard budget fell at depth " .. depth)
				Harness.expect(reward >= previousReward, "reward fell at depth " .. depth)
				previousThreat, previousHazard, previousRooms, previousReward = threat, hazard, rooms, reward
			end
			Harness.expect(previousRooms > 0, "no room counts were evaluated")
		end),

		Harness.test("the authored range is left exactly as authored", function()
			for depth = 1, DepthConfig.authoredDepth do
				Harness.near(DepthRules.getThreatBudgetMultiplier(depth), 1, 1e-12, "depth " .. depth)
				Harness.near(DepthRules.getHazardBudgetMultiplier(depth), 1, 1e-12, "depth " .. depth)
			end
			for depth, authored in FloorsConfig.roomsPerFloor do
				Harness.equal(DepthRules.getRoomCountTarget(depth), authored, "room count changed at depth " .. depth)
			end
		end),

		Harness.test("run length is reduced, never extended past the ceiling", function()
			Harness.equal(DepthRules.floorCountForRun(1, 6), 6)
			Harness.equal(DepthRules.floorCountForRun(1, CEILING), CEILING)
			Harness.equal(DepthRules.floorCountForRun(1, CEILING + 50), CEILING)
			Harness.equal(DepthRules.floorCountForRun(CEILING, 10), 1)
			Harness.equal(DepthRules.floorCountForRun(CEILING + 1, 10), 0)
			Harness.equal(DepthRules.floorCountForRun(0, 10), 0)
		end),

		Harness.test("floor seeds are stable per depth and never shared between depths", function()
			local seen: { [number]: number } = {}
			for depth = 1, CEILING do
				local seed = DepthRules.getFloorSeed(1234, 2, depth)
				Harness.equal(seed, DepthRules.getFloorSeed(1234, 2, depth), "seed is not reproducible")
				Harness.expect(seed == math.floor(seed) and seed >= 0, "seed must be a non-negative integer")
				for otherDepth, otherSeed in seen do
					Harness.expect(otherSeed ~= seed, "depths " .. otherDepth .. " and " .. depth .. " share a seed")
				end
				seen[depth] = seed
			end
			-- The tier and the run seed are part of the derivation too.
			Harness.expect(DepthRules.getFloorSeed(1234, 1, 4) ~= DepthRules.getFloorSeed(1234, 2, 4), "tier ignored")
			Harness.expect(DepthRules.getFloorSeed(1, 1, 4) ~= DepthRules.getFloorSeed(2, 1, 4), "run seed ignored")
		end),
	},
}

return suite
