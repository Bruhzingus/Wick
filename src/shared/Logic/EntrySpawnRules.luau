--!strict
-- Stable multiplayer entry slots. Runner one stays at the room centre; later slots are distributed
-- around it inside the entry room's guaranteed-flat, obstruction-free footprint.

local CharacterConfig = require(script.Parent.Parent.Config.Character)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local RunConfig = require(script.Parent.Parent.Config.RunSettings)

local EntrySpawnRules = {}

local function offsetForSlot(slot: number): Vector3
	if slot == 1 then
		return Vector3.zero
	end
	local ringSlots = RunConfig.partyCap - 1
	local angle = (slot - 2) * 2 * math.pi / ringSlots
	return Vector3.new(math.cos(angle) * RunConfig.entrySpawnRadius, 0, math.sin(angle) * RunConfig.entrySpawnRadius)
end

local function validateConfig()
	local radius = RunConfig.entrySpawnRadius
	assert(RunConfig.partyCap % 1 == 0 and RunConfig.partyCap >= 1, "party cap must be a positive integer")
	assert(radius >= 0 and RunConfig.entrySpawnClearance >= 0, "entry spawn spacing cannot be negative")
	local colliderRadius = CharacterConfig.bodyRadius * math.sqrt(2)
	local safeRadius = math.min(
		FloorsConfig.groundField.centerPadRadius,
		FloorsConfig.terrain.specialRoomCenterClearance
	) - colliderRadius
	assert(radius <= safeRadius, "entry spawn radius extends outside the guaranteed-clear entry footprint")

	local offsets: { Vector3 } = {}
	local requiredSeparation = colliderRadius * 2 + RunConfig.entrySpawnClearance
	for slot = 1, RunConfig.partyCap do
		local offset = offsetForSlot(slot)
		for _, existing in offsets do
			assert((offset - existing).Magnitude >= requiredSeparation, "entry spawn slots overlap candle colliders")
		end
		table.insert(offsets, offset)
	end
end

function EntrySpawnRules.positionForSlot(entryCenter: Vector3, slot: number): Vector3
	assert(slot % 1 == 0 and slot >= 1 and slot <= RunConfig.partyCap, "entry spawn slot is outside the party cap")
	validateConfig()
	if slot == 1 then
		return entryCenter
	end

	return entryCenter + offsetForSlot(slot)
end

return EntrySpawnRules
