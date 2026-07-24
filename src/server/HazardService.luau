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
export type Exposure = { inDraft: boolean, water: Types.WaterAssessment }

local draftZones: { [number]: { Zone } } = {} -- keyed by depth
local waterRegions: { [number]: { WaterRegion } } = {}

function HazardService.registerFloor(depth: number, drafts: { Zone }, waters: { WaterRegion })
	draftZones[depth] = drafts
	waterRegions[depth] = waters
end

local function insideXZ(point: Vector3, center: Vector3, size: Vector3): boolean
	return math.abs(point.X - center.X) <= size.X / 2 and math.abs(point.Z - center.Z) <= size.Z / 2
end

local function insideBox(point: Vector3, zone: Zone): boolean
	return insideXZ(point, zone.center, zone.size) and math.abs(point.Y - zone.center.Y) <= zone.size.Y / 2
end

-- What this candle is standing in right now. position = candle BASE; height = current body height.
function HazardService.exposureFor(depth: number, position: Vector3, height: number): Exposure
	local inDraft = false
	for _, zone in draftZones[depth] or {} do
		if insideBox(position, zone) then
			inDraft = true
			break
		end
	end

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

	return { inDraft = inDraft, water = water }
end

function HazardService.reset()
	table.clear(draftZones)
	table.clear(waterRegions)
end

return HazardService
