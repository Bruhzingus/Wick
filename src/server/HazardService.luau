--!strict
-- Hazard zone registry and exposure queries. Zones are plain data boxes registered at floor
-- build; exposure is pure math against them (no Touched events, no trigger volumes) so the
-- water rule stays a real height comparison.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local HazardRules = require(ReplicatedStorage.Shared.Logic.HazardRules)

local HazardService = {}

export type Zone = { center: Vector3, size: Vector3 }
export type WaterRegion = { surfaceY: number, center: Vector3, size: Vector3 }
export type Exposure = { water: Types.WaterAssessment }

local waterRegions: { [number]: { WaterRegion } } = {}

function HazardService.registerFloor(depth: number, waters: { WaterRegion })
	waterRegions[depth] = waters
end

local function insideXZ(point: Vector3, center: Vector3, size: Vector3): boolean
	return math.abs(point.X - center.X) <= size.X / 2 and math.abs(point.Z - center.Z) <= size.Z / 2
end

-- What this candle is standing in right now. position = candle BASE; height = current body height.
function HazardService.exposureFor(depth: number, position: Vector3, height: number): Exposure
	local water: Types.WaterAssessment = "None"
	for _, region in waterRegions[depth] or {} do
		if insideXZ(position, region.center, region.size) then
			local assessment = HazardRules.waterAssessment(region.surfaceY, position.Y, height)
			if assessment == "Lethal" then
				water = "Lethal"
				break
			elseif assessment == "Wading" then
				water = "Wading"
			end
		end
	end

	return { water = water }
end

function HazardService.reset()
	table.clear(waterRegions)
end

return HazardService
