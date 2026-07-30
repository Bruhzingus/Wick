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
	allowedHazards: { Hazard.StaticHazardId }, -- static zone hazards which may appear here
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
	-- Planned (not cosmetic): the ceiling height drives how the room reads AND which threats favour
	-- it — tall caverns draw the light-seeking moth family, tight low rooms host ceiling-diving flies.
	ceilingHeight: number,
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
	offset: Vector3, -- deterministic local offset from the room centre
}

export type LootSpawn = {
	lootId: Loot.LootId,
	roomIndex: number, -- index into FloorPlan.rooms
	offset: Vector3, -- deterministic local offset from the room centre
}

export type HazardPlacement = {
	hazardId: Hazard.StaticHazardId,
	roomIndex: number,
	waterDepth: number?, -- Water only: waterline height above the pool bed = the wading depth
	-- Water only: how far below the room's flat base plane the pool bed sits. Chosen from the room's
	-- real height field so the bed is never raised above the natural recess it settles into, which
	-- is why a pool reads as a puddle in an existing dip rather than a crater.
	bedDepth: number?,
	localOffset: Vector3?, -- Water: deterministic room-local centre offset
	size: Vector3?, -- Localized Water pool footprint
}

-- A planned one-shot unstable ceiling formation. FloorBuilder resolves the exact roof/landing Y
-- from the deterministic terrain fields; the planner owns every choice that affects gameplay.
export type DripstonePlacement = {
	roomIndex: number,
	localOffset: Vector3,
	variantId: string,
	visualSeed: number,
}

-- A burnable vine curtain filling one shared doorway. Recorded from ONE side only; the opening is
-- shared, so the builder seals it once. The planner guarantees the doorway is redundant (every room
-- stays reachable without it) and off the guaranteed entry -> Basin route.
export type VinePlacement = {
	roomIndex: number,
	direction: Direction,
	visualSeed: number,
}

-- One arch an Ashamed Lurker may occupy, recorded from ONE side of the shared opening. `trapSide`
-- is which half of that opening its arm crosses, in the doorway's own local X (see
-- Logic/AshamedLurkerRules for the frame convention).
export type LurkerSite = {
	roomIndex: number,
	direction: Direction,
	trapSide: "Left" | "Right",
}

-- One creature and the arches it owns on this floor. `sites[1]` is where it starts; the rest are
-- where it reappears after being shamed off, in order. Sites are never shared between creatures.
export type LurkerPlacement = {
	sites: { LurkerSite },
	visualSeed: number,
}

-- A rare planner-owned Stone Warden encounter. The dedicated room is ordinary cave construction,
-- but these reserved offsets guarantee the dormant body, relic, and counter-hazard remain usable.
export type WardenPlacement = {
	roomIndex: number,
	pileOffset: Vector3,
	relicOffset: Vector3,
	counterDripstoneOffset: Vector3,
	visualSeed: number,
}

-- One planned Raw Wax deposit. A floor may carry several, but the planner takes at most one from
-- each optional off-route room and never uses the guaranteed entry -> Brazier -> Basin route:
-- mining remains a set of chosen detours, never something the floor walks the party into.
export type DepositPlacement = {
	roomIndex: number,
	localOffset: Vector3,
	visualSeed: number,
	-- Chosen by the planner from the rows the PARTY between them has unlocked, so a floor is one
	-- deterministic function of its seed plus that unlock set (Logic/MiningRules.selectRow).
	rowId: string,
}

-- Complete pure description of one floor. Everything the builder needs; nothing it decides.
export type FloorPlan = {
	-- This expedition's own 1-based floor ordinal. World stacking, floor keys, and the on-screen
	-- floor number only. It is NOT a difficulty input.
	depth: number,
	-- The canonical difficulty depth (Logic/DepthRules): startDepth + depth - 1. Every content
	-- curve, budget, reward multiplier, and deterministic geometry seed reads this one.
	globalDepth: number,
	rooms: { RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number, -- the safe room; also holds the descent to the next floor
	brazierRoomIndex: number,
	threatSpawns: { ThreatSpawn },
	lootSpawns: { LootSpawn },
	hazards: { HazardPlacement },
	dripstones: { DripstonePlacement },
	vines: { VinePlacement },
	lurkers: { LurkerPlacement },
	warden: WardenPlacement?,
	deposits: { DepositPlacement },
	groundPatches: { GroundPatch },
	-- The dead-end side room sealed behind its own vine curtain, if this floor has one
	-- (Config/LampNetwork.generation.lockedStore). Guaranteed to hold a deposit and a loot pickup, and
	-- guaranteed to carry nobody toward the next floor — see Logic/VineRules.roomMayBeSealed.
	lockedStoreRoomIndex: number?,
}

return {}
