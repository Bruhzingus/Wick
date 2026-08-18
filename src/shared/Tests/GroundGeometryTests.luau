--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local GroundGeometry = require(script.Parent.Parent.Logic.GroundGeometry)
local RoomFootprint = require(script.Parent.Parent.Logic.RoomFootprint)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local MiningConfig = require(script.Parent.Parent.Config.Mining)

local function room(): Types.RoomPlacement
	return {
		moduleId = "Chamber",
		gridX = 3,
		gridZ = -2,
		doorways = {},
		ceilingHeight = 30,
		footprint = RoomFootprint.rectangle(),
	}
end

local function assertCircularSupport(
	field: GroundGeometry.Field,
	x: number,
	z: number,
	radius: number,
	wanted: number,
	message: string
)
	for step = 0, 7 do
		local angle = step * math.pi / 4
		Harness.near(
			GroundGeometry.offset(field, x + math.cos(angle) * radius, z + math.sin(angle) * radius),
			wanted,
			1e-6,
			message
		)
	end
end

local suite: Harness.Suite = {
	name = "GroundGeometry",
	tests = {
		Harness.test("placement shelf preserves its natural elevation and levels only its support disc", function()
			local placementX, placementZ = 18, 9
			local natural = GroundGeometry.fieldFor(room(), 5, false, {}, {}, {})
			local naturalHeight = GroundGeometry.offset(natural, placementX, placementZ)
			local shelf = GroundGeometry.fieldFor(room(), 5, false, {
				{ x = placementX, z = placementZ, r = 4, height = naturalHeight },
			}, {}, {})

			Harness.near(GroundGeometry.offset(shelf, placementX, placementZ), naturalHeight, 1e-6)
			Harness.near(GroundGeometry.offset(shelf, placementX + 3, placementZ), naturalHeight, 1e-6)
			Harness.near(
				GroundGeometry.offset(shelf, placementX + 12, placementZ),
				GroundGeometry.offset(natural, placementX + 12, placementZ),
				1e-6
			)
		end),

		Harness.test("structural flat spots retain their room-base behavior", function()
			local field = GroundGeometry.fieldFor(room(), 5, false, {
				{ x = 18, z = 9, r = 4 },
			}, {}, {})
			Harness.near(GroundGeometry.offset(field, 18, 9), 0, 1e-6)
		end),

		Harness.test("minimum placement spacing keeps neighbouring support rings level in either order", function()
			local probe = FloorsConfig.geometry.placementProbe
			local transition = probe.placementPadMarginStuds + probe.placementPadBlendStuds
			for _, case in
				{
					{
						name = "loot",
						support = LootConfig.placementFootprint / 2,
						minimumDistance = LootConfig.placementFootprint
							+ math.max(FloorsConfig.terrain.gameplaySpawnSeparation, transition),
					},
					{
						name = "deposit",
						support = MiningConfig.visual.surfaceProbeRadius,
						minimumDistance = math.max(
							MiningConfig.placement.footprint + MiningConfig.placement.standingClearance,
							MiningConfig.visual.surfaceProbeRadius * 2 + transition
						),
					},
				}
			do
				local support = case.support
				local distance = case.minimumDistance
				local firstX, secondX = -distance / 2, distance / 2
				local spots = {
					{
						x = firstX,
						z = 0,
						r = support + probe.placementPadMarginStuds,
						height = 0,
						blend = probe.placementPadBlendStuds,
					},
					{
						x = secondX,
						z = 0,
						r = support + probe.placementPadMarginStuds,
						height = 8,
						blend = probe.placementPadBlendStuds,
					},
				}
				for _, ordered in { spots, { spots[2], spots[1] } } do
					local field = GroundGeometry.fieldFor(room(), 5, false, ordered, {}, {})
					assertCircularSupport(field, firstX, 0, support, 0, case.name .. " first support moved")
					assertCircularSupport(field, secondX, 0, support, 8, case.name .. " second support moved")
				end
			end
		end),
	},
}

return suite
