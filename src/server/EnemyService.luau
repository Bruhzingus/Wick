--!strict
-- Owns every wick-pack body on every floor: spawning them, stepping them, and taking them down with
-- the floor they belong to.
--
-- ONE TICK FOR ALL OF THEM. Each behaviour module is a plain object with a `step(dt, now)`, and this
-- is the only thing that calls it. That matters for the same reason `ThreatService` batches its own
-- roster: a brood plus two Longarms plus a Gnawer is a lot of bodies, and one loop that samples the
-- clock once and walks a flat array is measurably cheaper than nine independent Heartbeat connections
-- each doing their own bookkeeping.
--
-- SPAWNING IS DELIBERATELY NOT DECIDED HERE. This service is handed positions — by the floor planner
-- for ordinary floors, by the boss encounter for the Queen's chamber — and never rolls its own. That
-- keeps placement reproducible from a floor seed and keeps this file about lifecycle.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local EnemyMover = require(script.Parent.EnemySystem.EnemyMover)
local WaxGrubBehavior = require(script.Parent.EnemySystem.WaxGrubBehavior)
local StoneGnawerBehavior = require(script.Parent.EnemySystem.StoneGnawerBehavior)
local LongarmBehavior = require(script.Parent.EnemySystem.LongarmBehavior)
local GrubQueenBehavior = require(script.Parent.EnemySystem.GrubQueenBehavior)

local EnemyService = {}

type Entry = {
	depth: number,
	kind: string,
	behavior: any,
}

local entries: { Entry } = {}
local enemyFolder: Folder? = nil

local function ensureFolder(): Folder
	local current = enemyFolder
	if current ~= nil and current.Parent ~= nil then
		return current
	end
	local folder = Instance.new("Folder")
	folder.Name = "WickEnemies"
	folder.Parent = workspace
	enemyFolder = folder
	return folder
end

-- A FLAT FLOOR HEIGHT TO FALL BACK ON, per floor, or nil for every ordinary cave.
--
-- `SurfaceProbe` measures TERRAIN and nothing else, which is correct for a generated cave and wrong
-- for exactly one place: the developer laboratory is built on a collidable Part floor, so every probe
-- there misses and every spawn would silently refuse. `ThreatService` already carries the same escape
-- hatch under the name `allowAnalyticGroundFallback`; this is that idea keyed by depth, because a
-- fallback is a property of the FLOOR rather than of each individual spawn.
--
-- REGISTERED, NEVER INFERRED. Production floors never call `setGroundFallback`, so they keep failing
-- closed — a body seated on a height nothing measured is a body standing inside a wall, and that must
-- stay the default. Only a caller that KNOWS its room is flat and part-floored may opt in.
local groundFallbackByDepth: { [number]: number } = {}

function EnemyService.setGroundFallback(depth: number, y: number?)
	groundFallbackByDepth[depth] = y
end

function EnemyService.groundFallback(depth: number): number?
	return groundFallbackByDepth[depth]
end

-- Seat a proposed spawn point on real Terrain, or on this floor's registered flat fallback, or refuse.
local function groundedCFrame(position: Vector3, footprint: number, depth: number): CFrame?
	local grounded = EnemyMover.groundedSpawn(position, footprint)
	if grounded ~= nil then
		return CFrame.new(grounded)
	end
	local fallback = groundFallbackByDepth[depth]
	if fallback ~= nil then
		return CFrame.new(Vector3.new(position.X, fallback, position.Z))
	end
	return nil
end

-- DID THAT BODY ACTUALLY LAND ON THE FLOOR? Measured from the finished silhouette, independently of
-- the probe that chose the spot — the same audit `LootService` and `MiningService` run on their own
-- placements, and for the same reason: a probe fooled by the geometry will happily agree with itself,
-- so the only check worth anything looks at the built model.
--
-- This exists because every creature-in-the-rock report so far has come from somebody noticing one in
-- a screenshot. A spawner that measures its own result reports the failure with a kind, a floor and a
-- number instead. Diagnostic only — a warned body is still a live body, exactly as loot is.
local function auditSeating(kind: string, depth: number, model: Model)
	local gap = SurfaceProbe.groundGapStuds(model)
	if gap == nil or math.abs(gap) > Config.Floors.geometry.placementProbe.maxSeatedGapStuds then
		warn(
			string.format(
				"[WICK] %s on floor %d has a suspicious ground gap: %s",
				kind,
				depth,
				if gap == nil then "no terrain below" else string.format("%.2f studs", gap)
			)
		)
	end
end

local function track(depth: number, kind: string, behavior: any)
	table.insert(entries, { depth = depth, kind = kind, behavior = behavior })
	local model = behavior.body and behavior.body.model
	if model ~= nil then
		model.Parent = ensureFolder()
		auditSeating(kind, depth, model)
		-- THE F8 OVERLAY'S HANDLE ON THIS BODY (client/DevDiagnosticsController).
		--
		-- Tagged HERE rather than in each behaviour's constructor because this is the one chokepoint
		-- every spawn path already goes through — the floor budget, the boss encounter, the Queen's own
		-- brood and the developer laboratory all reach the world through `track`. Tagging per
		-- constructor would have been four places to forget, and the failure mode is silent: the
		-- creature works perfectly and simply never appears in the debug view.
		--
		-- Server-side, so it replicates to every client. The tag rides the model, so destroying the body
		-- fires the overlay's own removal signal and the marker cleans itself up.
		CollectionService:AddTag(model, Config.Diagnostics.packEnemyTag)
	end
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

-- A brood of 2-5 grubs scattered around one anchor. The count is rolled from the supplied RNG so a
-- floor seed reproduces the same brood, and each grub gets its own seed so they are individuals.
function EnemyService.spawnBrood(depth: number, anchor: Vector3, familyId: string?, rng: Random): number
	local grubConfig = Config.WaxGrub
	local count = rng:NextInteger(grubConfig.broodMin, grubConfig.broodMax)
	local built = 0
	for index = 1, count do
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber() * 6
		local proposed = anchor + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local cframe = groundedCFrame(proposed, 1.0, depth)
		if cframe == nil then
			continue
		end
		local grub =
			WaxGrubBehavior.new(cframe, depth, familyId, rng:NextInteger(1, 2 ^ 30), groundFallbackByDepth[depth])
		track(depth, "WaxGrub", grub)
		built += 1
		local _ = index
	end
	return built
end

function EnemyService.spawnGnawer(depth: number, position: Vector3, familyId: string?, seed: number?): boolean
	local cframe = groundedCFrame(position, 3.0, depth)
	if cframe == nil then
		return false
	end
	local gnawer = StoneGnawerBehavior.new(cframe, depth, familyId, seed)
	if gnawer == nil then
		return false
	end
	track(depth, "StoneGnawer", gnawer)
	return true
end

function EnemyService.spawnLongarm(
	depth: number,
	position: Vector3,
	familyId: string?,
	seed: number?,
	leashCenter: Vector3?,
	leashRadius: number?
): LongarmBehavior.Longarm?
	local cframe = groundedCFrame(position, 2.5, depth)
	if cframe == nil then
		return nil
	end
	local longarm = LongarmBehavior.new(cframe, depth, familyId, seed)
	if leashCenter ~= nil and leashRadius ~= nil then
		longarm:setLeash(leashCenter, leashRadius)
	end
	track(depth, "Longarm", longarm)
	return longarm
end

function EnemyService.spawnQueen(
	depth: number,
	position: Vector3,
	familyId: string?,
	seed: number?
): GrubQueenBehavior.Queen?
	local cframe = groundedCFrame(position, 6.0, depth)
	if cframe == nil then
		return nil
	end
	local queen = GrubQueenBehavior.new(cframe, depth, familyId, seed)
	-- SHE CRAWLS NOW, so she needs the same flat-floor fallback the grub does: both are CFrame-driven
	-- and both measure the ground under every step, and the developer laboratory has no Terrain to
	-- measure. Without it she seats once at spawn and then refuses every step she tries to take.
	queen:setGroundFallback(groundFallbackByDepth[depth])

	-- HER BROOD IS SPAWNED THROUGH THIS SERVICE, so newborn grubs are ordinary tracked bodies with the
	-- same lifecycle, the same dynamite vulnerability and the same teardown as any other. The count she
	-- believes is alive is corrected as each one dies, which is what keeps her cap honest.
	queen.onBirth = function(birthCFrame: CFrame)
		local grounded = groundedCFrame(birthCFrame.Position, 1.0, depth)
		if grounded == nil then
			return
		end
		local grub = WaxGrubBehavior.new(grounded, depth, familyId, nil, groundFallbackByDepth[depth])
		grub.onDied = function()
			queen:grubDied()
		end
		track(depth, "WaxGrub", grub)
	end

	track(depth, "GrubQueen", queen)
	return queen
end

-- Build every wick-pack body one floor plan asked for. Returns how many actually landed.
--
-- REFUSING IS NORMAL AND IS NOT AN ERROR. A planned offset is an analytic point on a room's floor
-- field, and the Terrain that was actually written may not agree with it — the same disagreement
-- ThreatService, the loot pass and every static fixture already handle by measuring and, on a miss,
-- declining to place. A creature that cannot be seated is skipped rather than dropped into rock.
function EnemyService.spawnFloor(plan: Types.FloorPlan, roomCenters: { Vector3 }): number
	local built = 0
	for _, spawn in plan.enemySpawns do
		local center = roomCenters[spawn.roomIndex]
		if center == nil then
			continue
		end
		local position = center + spawn.offset
		if spawn.enemyId == "WaxGrub" then
			-- One planned grub spawn is a BROOD anchor, not a single body: the pack is explicit that
			-- these appear in groups, and a lone grub reads as a stray rather than as an infestation.
			built += EnemyService.spawnBrood(plan.depth, position, plan.familyId, Random.new(spawn.seed))
		elseif spawn.enemyId == "StoneGnawer" then
			if EnemyService.spawnGnawer(plan.depth, position, plan.familyId, spawn.seed) then
				built += 1
			end
		elseif spawn.enemyId == "Longarm" then
			if EnemyService.spawnLongarm(plan.depth, position, plan.familyId, spawn.seed) ~= nil then
				built += 1
			end
		end
	end
	return built
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function EnemyService.tick(dt: number)
	if #entries == 0 then
		return
	end
	local now = os.clock()
	for index = #entries, 1, -1 do
		local entry = entries[index]
		local behavior = entry.behavior
		if behavior.destroyed then
			table.remove(entries, index)
			continue
		end
		behavior:step(dt, now)
	end
end

function EnemyService.countAtDepth(depth: number): number
	local count = 0
	for _, entry in entries do
		if entry.depth == depth and not entry.behavior.destroyed then
			count += 1
		end
	end
	return count
end

-- Whether a Grub Queen is still alive on this floor. RunOrchestrator's descent guard reads this.
function EnemyService.queenAliveAtDepth(depth: number): boolean
	return GrubQueenBehavior.aliveAtDepth(depth)
end

-- Every grub whose hitbox contains this point, for the stomp check. Returns behaviours rather than
-- models so the caller can scare them directly.
function EnemyService.grubsNear(depth: number, position: Vector3, radius: number): { any }
	local found: { any } = {}
	for _, entry in entries do
		if entry.depth ~= depth or entry.kind ~= "WaxGrub" or entry.behavior.destroyed then
			continue
		end
		local root = entry.behavior.body.root
		if root.Parent ~= nil and (root.Position - position).Magnitude <= radius then
			table.insert(found, entry.behavior)
		end
	end
	return found
end

-- Remove every body of ONE kind on one floor, leaving the rest of that floor alone.
--
-- Exists for the set pieces: a Grub Queen is an encounter with its own clocks rather than a body you
-- stack, so the developer laboratory replaces the live one instead of running two. Production has no
-- caller — a real boss floor builds exactly one and tears it down with the floor.
function EnemyService.clearKindAtDepth(depth: number, kind: string): number
	local removed = 0
	for index = #entries, 1, -1 do
		local entry = entries[index]
		if entry.depth == depth and entry.kind == kind then
			table.remove(entries, index)
			entry.behavior:destroy()
			removed += 1
		end
	end
	return removed
end

function EnemyService.clearDepth(depth: number)
	for index = #entries, 1, -1 do
		local entry = entries[index]
		if entry.depth == depth then
			table.remove(entries, index)
			entry.behavior:destroy()
		end
	end
end

function EnemyService.reset()
	for index = #entries, 1, -1 do
		local entry = entries[index]
		table.remove(entries, index)
		entry.behavior:destroy()
	end
	table.clear(entries)
	if enemyFolder ~= nil then
		enemyFolder:Destroy()
		enemyFolder = nil
	end
end

return EnemyService
