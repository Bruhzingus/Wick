--!strict
-- THE GRUB QUEEN'S ENCOUNTER: her, her two chained guards, and the sealed caches.
--
-- WHAT THIS OWNS AND WHAT IT DOES NOT. The floor's SHAPE is authored in `Logic/BossFloorPlan` and
-- carved by the ordinary builder; its wax and dynamite are ordinary respawning `lootSpawns` handled
-- by `LootService`. What is left — and all this file does — is the three things that have no
-- equivalent on a generated floor: the Queen, the two Longarms leashed to her chamber, and the
-- supplies buried under rock that has to be mined free while the fight is running.
--
-- THE SEALED CACHES ARE THE ONE NEW IDEA HERE, and they exist because the fight otherwise has a hole
-- in it: circling for pickups is a route, not a decision. A cache is a real choice — standing still,
-- back to the room, swinging a pick while grubs close and a Longarm crosses the chamber behind you.
-- They are ordinary mining deposits (`MiningService`), so the interaction is one the player already
-- knows and the noise a pick makes is the same noise it always makes.
--
-- SHE IS NOT A THREAT ROW AND NOT AN `EnemySpawn`. She belongs to this authored floor, so she is
-- placed here rather than budgeted; `EnemyService.spawnQueen` still owns her lifecycle, and her death
-- is what unlocks the ladder through `QueenRegistry`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local BossFloorPlan = require(ReplicatedStorage.Shared.Logic.BossFloorPlan)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local EnemyService = require(script.Parent.EnemyService)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local Telemetry = require(script.Parent.Telemetry)

local BossEncounterService = {}

type Encounter = {
	depth: number,
	queen: any,
	guards: { any },
	resolved: boolean,
}

local encounters: { [number]: Encounter } = {}

-- Seat an authored room-local offset on the Terrain that was actually carved, or nil if there is
-- nothing under it. Authored offsets are chosen against a full rectangular room, so a miss here means
-- the carve disagreed with the plan rather than that the designer aimed badly — worth a warning.
local function seatedPosition(
	roomCenter: Vector3,
	surface: any,
	offset: Vector3,
	footprintRadius: number,
	label: string,
	depth: number
): Vector3?
	local resolved = SurfaceProbe.resolvePlannedPosition(surface, offset, footprintRadius)
	if resolved.failed then
		warn(string.format("[WICK] boss floor %d: no Terrain support for %s", depth, label))
		return nil
	end
	local _ = roomCenter
	return resolved.position
end

-- Build the whole encounter on a freshly carved boss floor.
function BossEncounterService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: any }
): boolean
	if encounters[plan.depth] ~= nil then
		return false
	end
	local fixtures = BossFloorPlan.fixtures()
	local centerRoom = BossFloorPlan.CENTER_ROOM
	local center = roomCenters[centerRoom]
	local centerSurface = roomSurfaces[centerRoom]
	if center == nil or centerSurface == nil then
		warn(string.format("[WICK] boss floor %d has no centre room; encounter not built", plan.depth))
		return false
	end

	local queenPosition = seatedPosition(center, centerSurface, fixtures.queenOffset, 6, "the Grub Queen", plan.depth)
	if queenPosition == nil then
		return false
	end
	local queen = EnemyService.spawnQueen(plan.depth, queenPosition, plan.familyId, plan.globalDepth * 7919)
	if queen == nil then
		warn(string.format("[WICK] boss floor %d: the Queen refused to seat", plan.depth))
		return false
	end

	-- SHE IS CHAINED TO HER OWN CHAMBER, on the same radius as her guards. She crawls now, and while
	-- 1.8 studs a second could never follow anybody anywhere, a Queen with no leash would still spend
	-- a long fight slowly relocating out of the room the pickups, the caches and the guards were all
	-- placed around — and the encounter is the room, not just her.
	queen:setLeash(center, fixtures.guardLeashRadius)

	local encounter: Encounter = {
		depth = plan.depth,
		queen = queen,
		guards = {},
		resolved = false,
	}

	-- HER DEATH IS THE FLOOR'S STATE CHANGE. The ladder gate reads `QueenRegistry` directly, so nothing
	-- here has to unlock anything; this is the announcement and the telemetry, which are the parts a
	-- registry cannot do.
	queen.onDeath = function()
		if encounter.resolved then
			return
		end
		encounter.resolved = true
		Remotes.get("RunEvent"):FireAllClients("bossDefeated", {
			depth = plan.depth,
			position = queenPosition,
		})
		Telemetry.event("boss_defeated", 0, { depth = plan.depth, globalDepth = plan.globalDepth })
	end

	-- TWO GUARDS, CHAINED TO THE CHAMBER. Leashed rather than free so they are pressure inside the
	-- fight instead of a pursuit that follows a fleeing player onto the stairs — the encounter is
	-- meant to be survivable by leaving the room, and guards that leave with you delete that.
	for index, guardOffset in fixtures.guardOffsets do
		local guardPosition =
			seatedPosition(center, centerSurface, guardOffset, 3, string.format("Longarm guard %d", index), plan.depth)
		if guardPosition ~= nil then
			local guard = EnemyService.spawnLongarm(
				plan.depth,
				guardPosition,
				plan.familyId,
				plan.globalDepth * 104_729 + index,
				center,
				fixtures.guardLeashRadius
			)
			if guard ~= nil then
				table.insert(encounter.guards, guard)
			end
		end
	end

	-- THE SEALED CACHES ARE NOT BUILT HERE. They are ordinary `plan.deposits` entries authored by
	-- `BossFloorPlan`, so `MiningService.spawnFloor` raises them exactly as it raises every other seam
	-- in the game — same probe, same seating, same interaction. There is deliberately no bespoke
	-- "boss cache" object: what makes them part of the encounter is where they are and when the player
	-- has to work them, not what they are made of.

	encounters[plan.depth] = encounter
	return true
end

function BossEncounterService.isActiveAtDepth(depth: number): boolean
	local encounter = encounters[depth]
	return encounter ~= nil and not encounter.resolved
end

function BossEncounterService.clearDepth(depth: number)
	-- The bodies themselves belong to EnemyService and are torn down with the floor there; this only
	-- forgets the encounter, so a rebuilt floor can raise a fresh one.
	encounters[depth] = nil
end

function BossEncounterService.reset()
	table.clear(encounters)
end

-- Config is read for the encounter's own gating; referenced so the dependency is explicit.
function BossEncounterService.requiresKillToDescend(): boolean
	return Config.GrubQueen.requiresKillToDescend
end

return BossEncounterService
