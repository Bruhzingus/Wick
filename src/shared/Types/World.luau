--!strict
-- World-structure types (DESIGN §18-19). Floors are assembled procedurally from room modules.
-- Logic/FloorPlanner emits a FloorPlan (pure data); server FloorBuilder turns it into parts.

local Threat = require(script.Parent.Threat)
local Hazard = require(script.Parent.Hazard)
local Loot = require(script.Parent.Loot)
local Dynamite = require(script.Parent.Dynamite)

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

-- One planned room footprint (Logic/RoomFootprint). Describes the OPEN INTERIOR of the room cell;
-- the cell itself is unchanged and still owns indexing, adjacency, doorway anchors and cleanup.
export type RoomFootprintShape = {
	kind: string,
	rotation: number,
	centerX: number,
	centerZ: number,
	primaryX: number,
	primaryZ: number,
	secondaryX: number,
	secondaryZ: number,
	lobeOffset: number,
	roughness: number,
	roughPhase: number,
}

-- One placed room on a floor's grid.
export type RoomPlacement = {
	moduleId: RoomModuleId,
	gridX: number,
	gridZ: number,
	doorways: { Direction },
	-- Planned (not cosmetic): the ceiling height drives how the room reads AND which threats favour
	-- it — tall caverns draw the light-seeking moth family, tight low rooms host ceiling-diving flies.
	ceilingHeight: number,
	-- The room's outer footprint. Rolled by the planner once its doorways are final and validated
	-- before it is recorded, so the builder reproduces exactly the shape every placement on this floor
	-- was checked against. Entry, Basin, completion and Warden rooms are always the full rectangle.
	footprint: RoomFootprintShape,
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

-- A WICK-PACK BODY the planner has decided a floor should carry (shared/Enemies).
--
-- SEPARATE FROM `ThreatSpawn` ON PURPOSE. A ThreatSpawn names a Config/Threats row that ThreatService
-- resolves against depth and drives with the shared brain; these four are bespoke bodies with their
-- own behaviour modules and their own lifecycle owner (server/EnemyService), so folding them into the
-- same list would mean every consumer of `threatSpawns` — the roof-dressing reservation, the
-- double-jeopardy rule, the visual proxy — having to learn which entries it must skip.
--
-- `seed` IS PART OF THE PLAN. The pack rolls colour jitter, decoration and the elder chance from a
-- seed, so carrying one here is what makes a floor's creatures reproducible from the floor seed
-- rather than re-rolled every time the floor is built.
export type EnemySpawn = {
	-- "WaxGrub" | "StoneGnawer" | "Longarm". The Grub Queen is never planned this way — she belongs to
	-- an authored boss chamber, not to the ordinary per-floor budget.
	enemyId: string,
	roomIndex: number, -- index into FloorPlan.rooms
	offset: Vector3, -- deterministic local offset from the room centre
	seed: number,
}

export type LootSpawn = {
	lootId: Loot.LootId,
	-- Seconds until a taken pickup returns to the same spot, or nil for the ordinary one-shot pickup
	-- every generated floor uses. Only the Grub Queen's authored chamber sets it (Logic/BossFloorPlan):
	-- her fight has no exit to restock through, so a chamber whose supplies ran dry would stall rather
	-- than resolve. Deliberately NOT available to the planner — a rolled floor must never be farmable.
	respawnSeconds: number?,
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

-- One optional doorway barrier, with its family-authored vine/icicle style stamped into the plan.
-- Recorded from ONE side only; the planner guarantees the doorway is redundant and off the
-- guaranteed entry -> Basin route.
export type VinePlacement = {
	roomIndex: number,
	direction: Direction,
	visualSeed: number,
	style: "Vines" | "Icicles",
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

-- One node of flammable vegetation inside a cluster (Config/MossFire). `kindId` is what it IS, and
-- it is the ONLY thing that decides whether it burns — flammability is never inferred from a colour
-- or a material at runtime, so a future dressing pass cannot accidentally become fuel.
export type MossFireNode = {
	localOffset: Vector3,
	kindId: string,
}

-- One tagged cluster of dry growth. The connectivity graph is PLANNED, not discovered at runtime:
-- what can carry fire is decided before a single Instance exists, which is what makes spread
-- deterministic and testable cold, and what stops fire ever jumping to a wet wall or to unrelated
-- dressing.
--
-- Never in the entry, Basin or completion room; never on the guaranteed route; never across a
-- doorway lane, a spawn clearance, or a required item or threat footprint. `obstructs` marks a
-- cluster that also forms a collidable mass burning clears — safe by construction, because none of
-- the above are places a cluster may be.
export type MossFireCluster = {
	roomIndex: number,
	localOffset: Vector3,
	nodes: { MossFireNode },
	-- Undirected, 1-based node indices. Guaranteed connected (Logic/MossFireRules.isConnectedGraph).
	edges: { { a: number, b: number } },
	obstructs: boolean,
	visualSeed: number,
}

-- A rare planner-owned Stone Warden encounter. The dedicated room is ordinary cave construction,
-- but these reserved offsets guarantee the dormant body, guarded wax, and hazards remain usable.
export type WardenPlacement = {
	roomIndex: number,
	-- Which side of the room cell the Warden sleeps in, as a wall. Always a doorless side, and the
	-- anchor for the whole encounter: the other three offsets are laid out from it, and the server
	-- turns it into the direction the body faces and steps out toward.
	wallDirection: Direction,
	pileOffset: Vector3,
	waxOffset: Vector3,
	counterDripstoneOffset: Vector3,
	-- Extra inspectable formations committed by the third wax pickup. The Heavy Crown counter above
	-- is deliberately not in this list, so the opening collapse cannot spend the encounter's answer.
	collapseDripstoneOffsets: { Vector3 },
	visualSeed: number,
}

-- A rare deep-floor tableau: a burned-out candle with its owner's haul still on the ground and a nest
-- of ceiling flies living on it (Config/DeadCandle, Logic/DeadCandleRules).
--
-- ONLY THE CORPSE IS RECORDED HERE. Its loot and its flies are emitted into the plan's ordinary
-- `lootSpawns` and `threatSpawns` by the planner, so every downstream system — pickup building, roof
-- dressing reservation, the double-jeopardy rule that keeps falling stone out of a fly's room — treats
-- them exactly as it treats any other pickup or creature, with no knowledge that this encounter exists.
export type DeadCandlePlacement = {
	roomIndex: number,
	localOffset: Vector3,
	visualSeed: number,
}

-- ONE SEALED BLAST VAULT (Config/Dynamite.vault). A dead-end side room attached after the loop pass,
-- so it is a leaf by construction and can never be on a route to anything: what is behind the door is
-- always optional, and blowing it open never opens a way forward.
--
-- The door is recorded from the VAULT side of the shared opening, exactly as a vine curtain is. The
-- room itself is guaranteed to hold deposits and to hold no threat spawn — the second is the reason a
-- player is willing to spend a stick on the first.
export type BlastVaultPlacement = {
	roomIndex: number, -- the sealed room
	direction: Direction, -- which of ITS walls the door fills, pointing back at the room it hangs off
	-- Where the charge pocket sits across the door's face, as a 0..1 fraction of the opening width.
	-- Rolled rather than centred so two doors on one floor are not the same object twice.
	socketFraction: number,
	socketHeightFraction: number,
	visualSeed: number,
	style: Dynamite.BlastDoorStyle,
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
	-- WHAT the rock is, as opposed to how it is worked. Resolved from the cave family's own
	-- availability curve (Logic/OreRules) and deliberately independent of `rowId`: a Twin Seam of
	-- Tier 1 and a Twin Seam of Tier 3 take the same swings and are worth different amounts. No
	-- interaction reads this yet; what a tier is worth is a later task.
	oreTier: number,
}

-- Complete pure description of one floor. Everything the builder needs; nothing it decides.
export type FloorPlan = {
	-- This expedition's own 1-based floor ordinal. World stacking, floor keys, and the on-screen
	-- floor number only. It is NOT a difficulty input.
	depth: number,
	-- The canonical difficulty depth (Logic/DepthRules): startDepth + depth - 1. Every content
	-- curve, budget, reward multiplier, and deterministic geometry seed reads this one.
	globalDepth: number,
	-- Which cave family produced this floor (Config/CaveFamilies). The builder reads it for palette,
	-- dressing and threat-variant presentation; nothing may branch on it for gameplay, which is
	-- resolved through Logic/CaveFamilyRules instead.
	familyId: string,
	-- World-space X/Z origin of this floor's local grid. Floor one starts at zero; every successor
	-- starts directly beneath the previous floor's Descent Ladder. Room grid coordinates remain local
	-- so deterministic topology and doorway profiles do not change when the cave bends between floors.
	worldOrigin: Vector3,
	-- THE WORLD Y THIS FLOOR'S ROOM FLOORS SIT AT, when it is not the one its ordinal implies.
	--
	-- Every floor in an expedition leaves this nil and is stacked by `FloorBuilder.baseY(depth)`: the
	-- run descends, so a floor's ordinal IS its height and deriving one from the other is what keeps
	-- the two callers that need it (the carve, and the engine's fallen-parts plane) from ever
	-- disagreeing.
	--
	-- IT EXISTS FOR THE DEVELOPER LABORATORY, which builds both authored boss floors for real
	-- (server/DevTestBossFloors) so a designer can walk the shipped geometry instead of a box that
	-- approximates it. Those two are not part of any descent: they sit beside the laboratory at its
	-- own floor height, keyed by the lab's own depth, and stacking them by that key would put them
	-- fifty-eight thousand studs below the world. A floor that says where it is, is the honest way to
	-- express that — the alternative was a builder that quietly reinterprets `depth` for one caller.
	floorY: number?,
	-- Generation counters for the floor-spawn audit. Diagnostics only: no rule reads these.
	diagnostics: {
		shapedRooms: number, -- ordinary rooms that ended up non-rectangular
		shapeFallbacks: number, -- rooms whose every candidate shape was refused
		shapeRejections: number, -- individual candidate parameter sets refused
	},
	rooms: { RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number, -- completion chamber; also holds the descent to the next floor
	brazierRoomIndex: number,
	threatSpawns: { ThreatSpawn },
	-- Wick-pack bodies for this floor. Empty on floors whose depth carries none, and empty on the
	-- boss floor, whose creatures are placed by the encounter rather than by the budget.
	enemySpawns: { EnemySpawn },
	lootSpawns: { LootSpawn },
	hazards: { HazardPlacement },
	dripstones: { DripstonePlacement },
	vines: { VinePlacement },
	lurkers: { LurkerPlacement },
	warden: WardenPlacement?,
	-- The floor's dead candle, if it rolled one. Its pickups and its flies are already in `lootSpawns`
	-- and `threatSpawns`; this is only where the body itself lies.
	deadCandle: DeadCandlePlacement?,
	deposits: { DepositPlacement },
	-- Sealed dead-end vaults behind a breakable door (Config/Dynamite.vault). Empty on most floors.
	blastVaults: { BlastVaultPlacement },
	-- Tagged flammable vegetation. Empty in every family that does not grow it.
	mossFire: { MossFireCluster },
	groundPatches: { GroundPatch },
	-- TRUE ONLY ON THE GRUB QUEEN'S AUTHORED FLOOR (Logic/BossFloorPlan). Nothing generated ever sets
	-- it. It exists because two systems downstream need to know they are looking at the boss floor
	-- without either of them learning what a boss is: the builder holds every doorway open wider, and
	-- the orchestrator raises the encounter after the ordinary content passes. An explicit flag rather
	-- than inferring it from the room shape, because inference would silently start being true the
	-- first time a generated floor happened to produce five rooms in a plus.
	bossEncounter: boolean?,
	-- The dead-end side room sealed behind its own vine curtain, if this floor has one
	-- (Config/LampNetwork.generation.lockedStore). Guaranteed to hold a deposit and a loot pickup, and
	-- guaranteed to carry nobody toward the next floor — see Logic/VineRules.roomMayBeSealed.
	lockedStoreRoomIndex: number?,
}

return {}
