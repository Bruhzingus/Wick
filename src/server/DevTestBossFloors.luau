--!strict
-- THE TWO AUTHORED BOSS FLOORS, BUILT FOR REAL, BESIDE THE DEVELOPER LABORATORY.
--
-- WHAT THIS REPLACED. The laboratory used to reach two hand-built boxes: a 96-cube for the Grub Queen
-- and a 64-cube for Unlittius, each with a Part floor, four Part walls and four ceiling lights, with
-- the encounter's own fixtures dropped in at their authored offsets. They tested the FIGHT honestly
-- and they were not the floors. No wax wing and no dynamite wing on hers; no vigils and no way down on
-- his; on both, no carved ground to walk over, no rock relief, no wall lamps, no brazier, no dripstone
-- and a flat ceiling at a height nobody had chosen. A designer standing in one of them was looking at
-- a room the game does not build, and every measurement they took off it was a measurement of the box.
--
-- WHAT THIS IS. `Logic/BossFloorPlan.plan` and `Logic/UnlittiusFloorPlan.plan` — the same two calls
-- RunOrchestrator makes on floors 10 and 20 — through `server/FloorBuilder.build`, the same builder
-- every floor of every expedition goes through. Five carved rooms each, real Terrain, real ground
-- fields, the authored ceiling heights, the doorway minimums, the formations, the lamps, the brazier
-- and the ladder. Then the real encounter services on top: `BossEncounterService.spawnFloor` for her
-- and `UnlittiusEncounterService.spawn` for him, both reading the carved surface exactly as a live
-- floor's would. Nothing here approximates anything.
--
-- THE THREE THINGS THAT ARE DELIBERATELY NOT THE SAME AS A LIVE FLOOR, and why each:
--
--   1. IT IS BUILT AT THE LABORATORY'S OWN HEIGHT (`Types/World.FloorPlan.floorY`) rather than stacked
--      by its depth key. The laboratory's scope depth is 610 — a key, not an ordinal — and stacking a
--      floor by it would put the room fifty-eight thousand studs under the world. Beside the
--      laboratory and on the level is what lets a tester WALK to it, which is the whole point.
--
--   2. IT IS ENTERED THROUGH ONE DOORWAY THE PLAN DOES NOT DECLARE. A shipped boss floor has no
--      outside; you arrive down a ladder into its entry room. This cuts one extra opening into that
--      same entry room so the walk in crosses the same threshold in the same direction, rather than
--      teleporting a tester into the middle of a chamber. See `Logic/DevTestBossApproach`.
--
--   3. THE LADDER IS INERT AND THE BASIN IS NOT. `FloorBuilder` builds both because both are part of
--      what the room LOOKS like. The ladder is left unregistered — it is run progression and there is
--      no run, so a tester can stand on the pad and read the cage but cannot ride it out of the
--      laboratory. The Basin IS registered, and boosted exactly as the live one is
--      (`Config.Basin.bossFloorGrantMultiplier`), because it is now the only fuel on either floor and
--      a boss floor tested without it is a boss floor tested without its economy.
--
-- BOTH FLOORS SHARE THE LABORATORY'S DEPTH KEY, and that is load-bearing rather than lazy. Every
-- service in the game scopes by depth and so does the tester's own `PlayerState.depth`: loot pickups,
-- seams, dripstone, threat perception and the boss's own targeting all compare the two. Giving the
-- floors their own keys would have built two rooms full of content that could not see the player
-- standing in it. The cost is that the per-depth registrations which REPLACE rather than append —
-- dripstone and the lamp network — have to be merged across both floors by the one caller that owns
-- them, which `DevTestRoomService` does explicitly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local UnlittiusFloorPlan = require(ReplicatedStorage.Shared.Logic.UnlittiusFloorPlan)
local WallLamp = require(ReplicatedStorage.Shared.NewModelsAndObjects.WallLamp)
local DevTestBossApproach = require(ReplicatedStorage.Shared.Logic.DevTestBossApproach)

local FloorBuilder = require(script.Parent.FloorBuilder)
local BossEncounterService = require(script.Parent.BossEncounterService)
local UnlittiusEncounterService = require(script.Parent.UnlittiusEncounterService)
local EnemyService = require(script.Parent.EnemyService)
local LootService = require(script.Parent.LootService)
local MiningService = require(script.Parent.MiningService)
local BasinService = require(script.Parent.BasinService)

local DevTestBossFloors = {}

export type Definition = DevTestBossApproach.Definition

export type BuiltFloor = {
	id: string,
	bossId: string,
	displayName: string,
	plan: Types.FloorPlan,
	runtime: FloorBuilder.FloorRuntime,
	approach: DevTestBossApproach.Approach,
	-- One box per carved cell, for the laboratory's containment check.
	roomBoxes: { { center: Vector3, size: Vector3 } },
}

-- Carve one floor and seat the content that is not the encounter.
--
-- WHAT IS POPULATED AND WHAT IS NOT. Loot and deposits are seated because they are the wings: her wax
-- arm and her dynamite arm and his two vigils are ROOMS FULL OF SUPPLY, and a wing with no supply in
-- it is a corridor with a name. Both services append to their depth rather than replacing it, so both
-- floors and the laboratory can share one key. Threats and the ordinary roster are skipped because
-- neither plan has any — a boss floor's creatures are the encounter's.
function DevTestBossFloors.carve(
	definition: Definition,
	plan: Types.FloorPlan,
	approach: DevTestBossApproach.Approach,
	floorY: number,
	parent: Instance
): BuiltFloor
	local runtime = FloorBuilder.build(plan)
	runtime.model.Name = "DevBossFloor_" .. definition.id
	runtime.model.Parent = parent

	-- SEATED AGAINST REAL TERRAIN, which is the whole reason this room is worth building. The
	-- laboratory's own floor is a Part and every placement in it needs `EnemyService.setGroundFallback`
	-- to seat at all; here the probes find carved ground and answer with the height a player will
	-- actually stand at.
	local ok, err = pcall(function()
		LootService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	end)
	if not ok then
		warn(string.format("[WICK] dev boss floor %q loot failed: %s", definition.id, tostring(err)))
	end
	ok, err = pcall(function()
		MiningService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	end)
	if not ok then
		warn(string.format("[WICK] dev boss floor %q deposits failed: %s", definition.id, tostring(err)))
	end

	-- EVERY WALL CANDLE ON A BOSS FLOOR IS ALREADY BURNING, and it is the one presentation decision
	-- this room makes that a live floor does not.
	--
	-- WHAT WENT WRONG WITHOUT IT. A shipped floor arrives cold and its lamps are something a player
	-- lights on the way through; that is the lamp network and it is right for an ordinary floor. On a
	-- BOSS floor it produced two bad readings at once. The chamber was pitch dark except for whatever
	-- the party was carrying, so the thing the room exists for — a twenty-four-stud crawler, a boulder
	-- crossing forty studs of floor, a marked circle before the ceiling comes down — happened in the
	-- dark and could not be read at all. And the lamps themselves, being lightable, read as an
	-- OBJECTIVE: the first thing a tester did on Unlittius' floor was light one and assume it was one
	-- of his eight shrine candles, which is a different boss's entire mechanic.
	--
	-- Lit here, they are exactly what was asked for and nothing more: a few subtle candles, diegetic,
	-- one per room, that make the fight legible without lighting it like a stage. They are still
	-- registered with `WallLampService` afterwards — see `DevTestRoomService` — so they are real
	-- entries in the light-perception field rather than decoration a creature cannot see.
	for _, lamp in runtime.lamps.lamps do
		WallLamp.setLit(lamp, true)
	end
	local crowned = runtime.lamps.main
	if crowned ~= nil then
		WallLamp.setLit(crowned, true)
	end

	-- THE BASIN, BOOSTED, exactly as the live floor's is. Both floors now carry no wax and no seams on
	-- the ground, so this pool is the only fuel on either of them — and the laboratory hands out an
	-- infinite candle, which makes it the one fixture here whose NUMBERS a tester cannot check by
	-- playing. Registering it at least means the offers are real and the prompt works.
	ok, err = pcall(function()
		BasinService.registerFloor(plan.depth, runtime.basinPosition, runtime.model, true)
	end)
	if not ok then
		warn(string.format("[WICK] dev boss floor %q basin failed: %s", definition.id, tostring(err)))
	end

	return {
		id = definition.id,
		bossId = definition.bossId,
		displayName = definition.displayName,
		plan = plan,
		runtime = runtime,
		approach = approach,
		roomBoxes = DevTestBossApproach.roomBoxes(plan, floorY),
	}
end

-- Start (or restart) the encounter this floor was built for, through the same service a live floor
-- uses. Returns success and the line the console prints.
function DevTestBossFloors.startEncounter(built: BuiltFloor, depth: number): (boolean, string)
	DevTestBossFloors.clearEncounter(built, depth)
	if built.bossId == "GrubQueen" then
		local started = BossEncounterService.spawnFloor(
			built.plan,
			built.runtime.roomCenters,
			built.runtime.roomSurfaces,
			built.runtime.model
		)
		if not started then
			return false, "the encounter refused to build."
		end
		return true, "Grub Queen encounter started. She and both guards are in their authored posts."
	end
	if built.bossId == "Unlittius" then
		local chamber = UnlittiusFloorPlan.CENTER_ROOM
		local center = built.runtime.roomCenters[chamber]
		if center == nil then
			return false, "the shrine chamber is missing."
		end
		local started = UnlittiusEncounterService.spawn({
			depth = depth,
			center = center + UnlittiusFloorPlan.fixtures().shrineOffset,
			familyId = built.plan.familyId,
			seed = built.plan.globalDepth * 6421,
			parent = built.runtime.model,
			surface = built.runtime.roomSurfaces[chamber],
			chamberRadius = UnlittiusFloorPlan.chamberRadius(),
			ceilingHeight = UnlittiusFloorPlan.CENTER_CEILING,
		})
		if not started then
			return false, "the shrine refused to build."
		end
		return true,
			string.format(
				"Unlittius encounter started. Light all %d candles to banish him.",
				Config.Unlittius.encounter.candleCount
			)
	end
	return false, "there is no encounter for this floor."
end

-- Tear down whatever the last attempt left standing, so a restart is a restart and not a second copy.
--
-- THE SUMMONED AND THE BORN GO TOO. Her brood and his Gnawers belong to THAT attempt; leaving them
-- would start the next fight already at its active cap, in a room the tester has not re-entered.
function DevTestBossFloors.clearEncounter(built: BuiltFloor, depth: number)
	if built.bossId == "GrubQueen" then
		-- `BossEncounterService.clearDepth` only forgets the record — on a real floor the BODIES go with
		-- the floor when `EnemyService.clearDepth` retires it, and nothing retires here. So all three
		-- kinds the encounter owns are named explicitly: her, the brood she birthed, and both guards.
		--
		-- THIS ALSO TAKES A LONGARM OR A QUEEN SPAWNED FROM THE CONSOLE, and it has to. The laboratory
		-- and both boss floors share one depth key (see the header), so "every Longarm at this depth" is
		-- the only handle there is; a guard left over from the last attempt would join the next fight,
		-- which is an encounter nobody authored. The console can put another one back in one press.
		BossEncounterService.clearDepth(depth)
		EnemyService.clearKindAtDepth(depth, "GrubQueen")
		EnemyService.clearKindAtDepth(depth, "WaxGrub")
		EnemyService.clearKindAtDepth(depth, "Longarm")
	elseif built.bossId == "Unlittius" then
		UnlittiusEncounterService.clearDepth(depth)
		EnemyService.clearKindAtDepth(depth, "Unlittius")
		EnemyService.clearKindAtDepth(depth, "StoneGnawer")
	end
end

-- Everything one built floor owns, in the one order that is safe: the encounter first, while the
-- bodies it owns are still parented, then the floor model, then the rock it was carved from.
function DevTestBossFloors.destroy(built: BuiltFloor, depth: number)
	DevTestBossFloors.clearEncounter(built, depth)
	built.runtime.model:Destroy()
	-- Exactly the regions this floor wrote, recorded at carve time. The laboratory itself is a Part
	-- room and writes no Terrain, so nothing here can eat into it.
	local terrain = workspace.Terrain
	for _, region in built.runtime.terrainRegions do
		terrain:FillRegion(region, 4, Enum.Material.Air)
	end
end

return DevTestBossFloors
