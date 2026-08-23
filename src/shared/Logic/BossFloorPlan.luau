--!strict
-- THE GRUB QUEEN'S FLOOR, authored rather than generated.
--
-- WHY THIS IS HAND-BUILT WHEN EVERY OTHER FLOOR IS ROLLED. The encounter is a resource race with a
-- specific shape — wax on one side, dynamite on the other, the Queen between them, and the way down
-- behind her — and that shape is the fight. A procedural floor cannot be asked for it: FloorPlanner
-- rolls topology, room sizes and doorway widths independently, and any one of those landing badly
-- (the wax wing three rooms from the dynamite wing, a tight opening onto the chamber) would quietly
-- produce an encounter that no longer works. So this returns a complete `FloorPlan` by construction
-- and hands it to the ordinary builder, which means the boss floor still gets real carved Terrain,
-- real ground fields, real walls and real doorways — everything downstream is unchanged and none of
-- it knows this floor was authored.
--
-- THE LAYOUT, five rooms in a plus:
--
--                      [ N ]  DYNAMITE WING
--                        |
--     DECOYS    [ W ] — [ C ] — [ E ]  THE WAY DOWN
--                        |      (descent ladder)
--                      [ S ]  ENTRY
--
-- EVERY ROUTE CROSSES THE CENTRE, and that is the whole design rather than a convenience. The player
-- arrives at S, needs dynamite from N to kill her and decoys from W to buy the room to place it, and
-- the ladder at E is behind her — so she is not a wall across a corridor, she is the room you cannot
-- stop walking through. The two supplies sit on OPPOSITE arms so killing faster and surviving longer
-- are different journeys, which is the choice ENCOUNTERS.md says the fight is made of.
--
-- THE WAX AND THE ORE ARE BOTH GONE, deliberately, and the wings are the better for it. See the
-- `deposits` and `lootSpawns` comments in `plan`: a boss chamber already at capacity did not need two
-- mining minigames and a wax round in it, and what was billed as a second axis of pressure read on the
-- floor as things to walk past.
--
-- SHE DOES NOT BLOCK THE WAY DOWN BY STANDING ON IT. The ladder is a room away and reachable on foot;
-- what stops a player taking it is `Config/GrubQueen.requiresKillToDescend`, checked in
-- RunOrchestrator's descent guard. The geometry expresses the idea and the rule enforces it, rather
-- than the geometry trying to be the rule — a player who could physically reach the cage but is
-- refused gets a clear answer, where a cage walled off behind a creature reads as a bug.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local BossRotation = require(script.Parent.BossRotation)
local RoomFootprint = require(script.Parent.RoomFootprint)

local BossFloorPlan = {}

-- Room order in the returned plan. Fixed and indexed by name below, because the encounter service
-- reads these by meaning ("the dynamite wing") and must never depend on ordering.
local CENTER, ENTRY, TOOL_WING, DYNAMITE_WING, DESCENT = 1, 2, 3, 4, 5

BossFloorPlan.CENTER_ROOM = CENTER
BossFloorPlan.ENTRY_ROOM = ENTRY
BossFloorPlan.TOOL_ROOM = TOOL_WING
BossFloorPlan.DYNAMITE_ROOM = DYNAMITE_WING
BossFloorPlan.DESCENT_ROOM = DESCENT

-- Her chamber is the tallest room the game builds. She is enormous, her ovipositor vent is the only
-- timer the player gets, and a low ceiling would put it out of sight from across the room.
local CENTER_CEILING = 46
local WING_CEILING = 34
local ENTRY_CEILING = 30

-- Openings on this floor are held at least this large (Logic/DoorwayGeometry.profile). Comfortably
-- above `doorwayMinWidth` (8) so no arm of the plus can roll a crevice, and tall enough that nothing
-- in the encounter has to duck.
BossFloorPlan.DOORWAY_MINIMUM = { minimumWidth = 26, minimumHeight = 14 }

-- The owner asked for roughly a minute on the dynamite. Decoys return faster because one only buys a
-- few seconds of her attention.
BossFloorPlan.DYNAMITE_RESPAWN_SECONDS = 60
BossFloorPlan.DECOY_RESPAWN_SECONDS = 34

-- WHETHER THIS DEPTH IS HERS. Delegated to `Logic/BossRotation`, which is now the only thing in the
-- game that decides what a boss floor is.
--
-- IT USED TO BE DECIDED HERE, by walking a 10-15 floor interval deterministically from the run seed.
-- That was the right shape while she was the only boss: an interval a player cannot count down to,
-- with a guarantee that two never landed back to back. A second boss (DESIGN §9b) changed what the
-- schedule has to promise — alternation rather than surprise — and a random interval can only ever
-- promise an average. The seed argument is kept so the call site reads the same and so a future
-- rotation that wants variance again has somewhere to take it from.
function BossFloorPlan.isBossDepth(globalDepth: number, runSeed: number): boolean
	local _ = runSeed
	return BossRotation.bossAt(globalDepth) == "GrubQueen"
end

local function room(
	moduleId: string,
	gridX: number,
	gridZ: number,
	doorways: { Types.Direction },
	ceilingHeight: number
): Types.RoomPlacement
	return {
		moduleId = moduleId :: any,
		gridX = gridX,
		gridZ = gridZ,
		doorways = doorways,
		ceilingHeight = ceilingHeight,
		-- FULL RECTANGLES, every one. Shapes exist to make ordinary caves feel irregular; here every
		-- square stud is encounter space that the player, the brood and two guards are all circulating
		-- through, and a capsule or a twin-lobe would create exactly the pinch points this floor is
		-- built to avoid.
		footprint = RoomFootprint.rectangle(),
	}
end

-- The complete authored plan for one Queen floor.
function BossFloorPlan.plan(
	globalDepth: number,
	localFloor: number,
	familyId: string,
	worldOrigin: Vector3
): Types.FloorPlan
	local rooms: { Types.RoomPlacement } = {}
	-- N is -Z and S is +Z (Logic/DoorwayGeometry.NORMAL), so the entry sits at +Z and the dynamite
	-- wing at -Z. Every arm carries exactly the one doorway that faces the centre.
	rooms[CENTER] = room("Chamber", 0, 0, { "N", "S", "E", "W" }, CENTER_CEILING)
	rooms[ENTRY] = room("Chamber", 0, 1, { "N" }, ENTRY_CEILING)
	rooms[TOOL_WING] = room("Chamber", -1, 0, { "E" }, WING_CEILING)
	rooms[DYNAMITE_WING] = room("Chamber", 0, -1, { "S" }, WING_CEILING)
	rooms[DESCENT] = room("Chamber", 1, 0, { "W" }, WING_CEILING)

	local cell = FloorsConfig.geometry.cellSize

	-- FALLING STONE, AND A LOT OF IT. The owner asked for more dripstone here than an ordinary floor
	-- carries, and it is the one hazard that works with the encounter rather than against it: the
	-- Queen's call brings the room down on whoever is standing under it, and a player circling for
	-- supplies is repeatedly crossing open ground they cannot watch the ceiling from.
	--
	-- NONE IN THE ENTRY. A player arriving on the floor gets one room to read the situation before the
	-- ceiling becomes their problem too.
	local dripstones: { Types.DripstonePlacement } = {}
	local variants = { "Spire", "Lance", "Mass", "Fork" }
	local function addDripstone(roomIndex: number, x: number, z: number)
		local index = #dripstones
		table.insert(dripstones, {
			roomIndex = roomIndex,
			localOffset = Vector3.new(x, 0, z),
			-- Cycled rather than rolled: this floor is authored, so its formations should be the same
			-- formations every time a player meets it, and the mix reads as variety either way.
			variantId = variants[(index % #variants) + 1],
			visualSeed = globalDepth * 7919 + index * 104_729,
		})
	end
	local ring = cell * 0.28
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		addDripstone(CENTER, corner[1] * ring, corner[2] * ring)
	end
	addDripstone(CENTER, 0, ring * 1.3)
	addDripstone(CENTER, 0, -ring * 1.3)
	addDripstone(TOOL_WING, ring * 0.6, 0)
	addDripstone(TOOL_WING, -ring * 0.7, ring * 0.5)
	addDripstone(DYNAMITE_WING, 0, ring * 0.6)
	addDripstone(DYNAMITE_WING, ring * 0.7, -ring * 0.5)
	addDripstone(DESCENT, -ring * 0.6, 0)

	local fixtures = BossFloorPlan.fixtures()

	-- NO SEAMS ON THIS FLOOR, AND THAT IS A REVERSAL. Two sealed wax caches used to sit at the far edge
	-- of each wing, and the argument for them was good on paper: supplies under rock that has to be
	-- mined free mid-fight are the only reason to stand still, and standing still with your back to the
	-- room is a real decision.
	--
	-- IN THE ROOM IT READ AS CLUTTER. A boss chamber is already carrying her, two Longarms, a brood at
	-- its cap and a ceiling that keeps coming down; adding two mining minigames to that did not create a
	-- decision, it created two more glowing things to walk past. What the fight is made of is dynamite
	-- and floor space, and everything on this floor that is not one of those two was noise.
	local deposits: { Types.DepositPlacement } = {}

	-- DYNAMITE, AND TWO DECOYS. Nothing else.
	--
	-- THE WAX IS GONE TOO. Her wing used to carry three Life Wax on a 38-second respawn, which made the
	-- fight a resource race on two axes at once — stay alit AND kill her — and in practice the wax was
	-- just something you hoovered up on the way through. What actually kills a party here is running out
	-- of dynamite or running out of room, and the floor should say so by only offering the answer to one
	-- of them. A party arrives on this floor with the candle they brought.
	local lootSpawns: { Types.LootSpawn } = {}
	for _, offset in fixtures.decoyOffsets do
		table.insert(lootSpawns, {
			lootId = "DecoyCharge" :: any,
			roomIndex = TOOL_WING,
			offset = offset,
			respawnSeconds = BossFloorPlan.DECOY_RESPAWN_SECONDS,
		})
	end
	for _, offset in fixtures.dynamiteOffsets do
		table.insert(lootSpawns, {
			lootId = "DynamiteStick" :: any,
			roomIndex = DYNAMITE_WING,
			offset = offset,
			respawnSeconds = BossFloorPlan.DYNAMITE_RESPAWN_SECONDS,
		})
	end

	return {
		depth = localFloor,
		globalDepth = globalDepth,
		familyId = familyId,
		worldOrigin = worldOrigin,
		diagnostics = { shapedRooms = 0, shapeFallbacks = 0, shapeRejections = 0 },
		rooms = rooms,
		entryRoomIndex = ENTRY,
		-- The descent room. `FloorStacking.descentOrigin` puts the cage a quarter-cell off this room's
		-- centre, and the next floor is stacked directly beneath it.
		basinRoomIndex = DESCENT,
		-- The Gas Lantern, and deliberately in the ENTRY. Extraction has to remain possible on this
		-- floor: killing her is required to go DOWN, never to leave the cave, and a party whose candle is
		-- failing with dynamite still in hand must be able to see the way out and choose it. That matters
		-- more now than it used to: this floor no longer hands out any wax at all.
		brazierRoomIndex = ENTRY,
		-- NO ORDINARY ROSTER AND NO ORDINARY LOOT. Everything on this floor is placed by
		-- `server/BossEncounterService`: its creatures are the Queen, her brood and her two guards, and
		-- its supplies are the authored wax and dynamite caches. A wandering Knotwalker would be noise
		-- in a fight that is already at capacity.
		threatSpawns = {},
		enemySpawns = {},
		-- THE SUPPLY, and the reason the wings exist. Wax on one arm, dynamite on the other, both
		-- respawning so the fight cannot dead-end — see `Types/World.LootSpawn.respawnSeconds` for why
		-- that is the encounter's clock rather than a generosity.
		--
		-- DYNAMITE COMES BACK SLOWER THAN WAX. Wax buys you time and dynamite ends the fight, so the
		-- resource that ends it is the scarcer one; a player who wants to kill her faster has to keep
		-- coming back to the same room rather than clearing it once.
		lootSpawns = lootSpawns,
		hazards = {},
		dripstones = dripstones,
		vines = {},
		lurkers = {},
		warden = nil,
		deadCandle = nil,
		-- THE SEALED CACHES. Ordinary mining deposits, authored rather than rolled, one at the far edge
		-- of each wing.
		--
		-- THEY ARE THE ONLY REASON TO STAND STILL IN THIS FIGHT, which is what makes them interesting:
		-- circling for pickups is a route, but committing to a seam is a decision — back to the room,
		-- swinging a pick, while grubs close and a guard crosses the chamber behind you. `Rich` rather
		-- than `Standard` so the reward is worth that, and `Deep` on the dynamite side because the arm
		-- the fight is won from should cost the most to work.
		deposits = deposits,
		blastVaults = {},
		mossFire = {},
		groundPatches = {},
		bossEncounter = true,
		lockedStoreRoomIndex = nil,
	}
end

-- Whether a plan is this floor. One field read, so a caller never has to guess from the shape.
function BossFloorPlan.isBossPlan(plan: Types.FloorPlan): boolean
	return plan.bossEncounter == true
end

-- Where the encounter's own fixtures go, in room-local offsets. Kept beside the layout rather than in
-- the service, because these positions and the room shapes are one design: moving a wing means moving
-- what is in it, and the two disagreeing is how a cache ends up inside a wall.
function BossFloorPlan.fixtures()
	local cell = FloorsConfig.geometry.cellSize
	return {
		-- She sits slightly back from the centre so the player entering from the south sees her whole
		-- silhouette against the far wall rather than arriving on top of her.
		queenOffset = Vector3.new(0, 0, -cell * 0.16),
		-- The guards start on the flanks of her chamber and are leashed to it. Chained to her, not to
		-- the player: they patrol the room the fight happens in and never follow anybody out of it.
		guardOffsets = {
			Vector3.new(-cell * 0.3, 0, cell * 0.18),
			Vector3.new(cell * 0.3, 0, cell * 0.18),
		},
		-- CHAINED TO THE CHAMBER, AND THE CHAMBER IS ONE CELL. This was `cell * 1.1` — a 70-stud leash
		-- on a room whose floor only reaches 30 studs from the centre, which meant "chained to her
		-- chamber" let a guard follow somebody out of a doorway and most of the way down an arm. It is
		-- now just over half a cell: the whole chamber and its thresholds, and not a stud more.
		guardLeashRadius = cell * 0.53,
		-- TWO DECOYS, on their own arm, and the only tool on the floor besides the dynamite.
		--
		-- A DECOY IS THE ONE THING THAT ANSWERS HER DIRECTLY. She crawls at 1.8 and turns at 24 degrees
		-- a second, so what she takes from a party is the ability to stand still — and a decoy is a
		-- place to stand still that is not where you are. Two, not three, and far enough apart that
		-- collecting both is a lap of the room rather than a stoop.
		decoyOffsets = {
			Vector3.new(-cell * 0.2, 0, -cell * 0.2),
			Vector3.new(cell * 0.14, 0, cell * 0.22),
		},
		-- DYNAMITE, on the opposite arm and deliberately more scattered than the wax: the player is
		-- meant to spend longer here, under pressure, than they do topping up.
		dynamiteOffsets = {
			Vector3.new(0, 0, -cell * 0.22),
			Vector3.new(-cell * 0.26, 0, cell * 0.04),
			Vector3.new(cell * 0.26, 0, cell * 0.04),
			Vector3.new(0, 0, cell * 0.24),
		},
	}
end

return BossFloorPlan
