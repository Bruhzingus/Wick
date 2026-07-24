--!strict
-- World-structure types (DESIGN §18-19). Floors are assembled procedurally from room modules.
-- Logic/FloorPlanner emits a FloorPlan (pure data); server FloorBuilder turns it into parts.

local Threat = require(script.Parent.Threat)
local Hazard = require(script.Parent.Hazard)
local Loot = require(script.Parent.Loot)

-- Identifier for a room module. Open string alias; add modules as Config/Floors rows.
-- The planner also emits the special id "Basin" for the per-floor safe room.
export type RoomModuleId = string

-- Static room-module definition. Pure data.
export type RoomModuleDef = {
	id: RoomModuleId,
	displayName: string,
	weight: number, -- relative likelihood in floor assembly; a tuning knob
	connections: number, -- max doorways this piece accepts during assembly
	allowedThreats: { Threat.ThreatId }, -- which threats may spawn here
	allowedHazards: { Hazard.HazardId }, -- which hazards may appear here
	waterDepth: number?, -- modules that always receive one recessed pool of this depth
}

-- Cardinal doorway directions on the assembly grid.
export type Direction = "N" | "S" | "E" | "W"

-- One placed room on a floor's grid.
export type RoomPlacement = {
	moduleId: RoomModuleId,
	gridX: number,
	gridZ: number,
	doorways: { Direction },
}

-- A broad, traversable rock swell embedded into the room floor. Unlike cosmetic dressing this is
-- planned data because its collision changes player movement and AI ground-following.
export type GroundPatch = {
	roomIndex: number,
	localOffset: Vector3,
	size: Vector3,
}

export type ThreatSpawn = {
	threatId: Threat.ThreatId,
	roomIndex: number, -- index into FloorPlan.rooms
}

export type LootSpawn = {
	lootId: Loot.LootId,
	roomIndex: number, -- index into FloorPlan.rooms
	offset: Vector3, -- deterministic local offset from the room centre
}

export type HazardPlacement = {
	hazardId: Hazard.HazardId,
	roomIndex: number,
	waterDepth: number?, -- Water only: surface height above the recessed pool bed
	localOffset: Vector3?, -- Draft/Water: deterministic room-local centre offset
	size: Vector3?, -- Draft zone or localized Water pool footprint
}

-- Complete pure description of one floor. Everything the builder needs; nothing it decides.
export type FloorPlan = {
	depth: number, -- 1-based floor number; drives Basin rate and Brazier multiplier
	rooms: { RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number, -- the safe room; also holds the descent to the next floor
	brazierRoomIndex: number,
	threatSpawns: { ThreatSpawn },
	lootSpawns: { LootSpawn },
	hazards: { HazardPlacement },
	groundPatches: { GroundPatch },
}

return {}
