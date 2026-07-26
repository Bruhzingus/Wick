--!strict

local Harness = require(script.Parent.Harness)
local CharacterConfig = require(script.Parent.Parent.Config.Character)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local RunConfig = require(script.Parent.Parent.Config.RunSettings)
local EntrySpawnRules = require(script.Parent.Parent.Logic.EntrySpawnRules)

local suite: Harness.Suite = {
	name = "EntrySpawnRules",
	tests = {
		Harness.test("every party slot is distinct and collider-safe", function()
			local center = Vector3.new(120, -96, 240)
			local positions: { Vector3 } = {}
			local colliderRadius = CharacterConfig.bodyRadius * math.sqrt(2)
			local requiredSeparation = colliderRadius * 2 + RunConfig.entrySpawnClearance
			for slot = 1, RunConfig.partyCap do
				local position = EntrySpawnRules.positionForSlot(center, slot)
				Harness.near(position.Y, center.Y)
				for _, existing in positions do
					Harness.expect(
						(position - existing).Magnitude >= requiredSeparation - 1e-6,
						"entry slots must not overlap candle colliders"
					)
				end
				table.insert(positions, position)
			end
		end),

		Harness.test("every party slot stays inside the entry room safe centre", function()
			local center = Vector3.zero
			local safeRadius =
				math.min(FloorsConfig.groundField.centerPadRadius, FloorsConfig.terrain.specialRoomCenterClearance)
			local colliderRadius = CharacterConfig.bodyRadius * math.sqrt(2)
			for slot = 1, RunConfig.partyCap do
				local offset = EntrySpawnRules.positionForSlot(center, slot)
				local horizontalRadius = Vector3.new(offset.X, 0, offset.Z).Magnitude
				Harness.expect(
					horizontalRadius + colliderRadius <= safeRadius + 1e-6,
					"entry slot collider must remain in the guaranteed-clear footprint"
				)
			end
		end),

		Harness.test("the first slot remains at the authored entry centre", function()
			local center = Vector3.new(-80, -192, 80)
			Harness.vectorNear(EntrySpawnRules.positionForSlot(center, 1), center)
		end),
	},
}

return suite
