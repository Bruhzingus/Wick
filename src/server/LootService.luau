--!strict
-- Server-authoritative adapter for config-planned in-run loot. Pickups either add a roguelike
-- modifier to the candle the player already has or add free activations consumed by ToolService;
-- there is no parallel inventory and no second resource.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local CandleModifiers = require(ReplicatedStorage.Shared.Logic.CandleModifiers)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local LootRules = require(ReplicatedStorage.Shared.Logic.LootRules)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local LootPickup = require(ReplicatedStorage.Shared.NewModelsAndObjects.LootPickup)
local PlayerState = require(script.Parent.PlayerState)
local SurfaceProbe = require(script.Parent.SurfaceProbe)

local LootService = {}

type RoomGroundSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
}

type ActivePickup = {
	model: Model,
	root: BasePart,
}

local activePickups: { ActivePickup } = {}

-- The one Random this service owns. Rows with a rolled magnitude (Extra Wicks' 1-3 wicks) draw from
-- it and hand the value to the pure rule, so the randomness sits here and the rule stays testable.
-- Deliberately NOT the floor's seeded planner stream: how many wicks a bundle turns out to have is
-- a moment in a run, not part of the cave's identity, and two players opening the same cache should
-- not have been able to look it up.
local collectRandom = Random.new()

-- Human-readable summary of what a modifier pickup actually did. Formatted HERE rather than in the
-- rule module: the numbers are the rule's, the sentence is presentation.
local function describeModifier(def: Types.LootDef, outcome: CandleModifiers.PickupOutcome): string
	local id = outcome.modifierId
	if id == "LifeWax" then
		return ("%s: burn rate down %d%% (%d held)."):format(
			def.displayName,
			math.floor(outcome.drainReduction * 100 + 0.5),
			outcome.lifeWax
		)
	elseif id == "BrightWax" then
		return ("%s: brightness up %d%% (%d held)."):format(
			def.displayName,
			math.floor(outcome.brightnessBonus * 100 + 0.5),
			outcome.brightWax
		)
	elseif id == "ExtraWicks" then
		return ("%s: %d extra wick%s lit for about %d seconds. Brighter, for no extra wax."):format(
			def.displayName,
			outcome.wicks,
			if outcome.wicks == 1 then "" else "s",
			math.floor(outcome.wickSeconds + 0.5)
		)
	elseif id == "FrozenWax" then
		return ("%s: it melts into your candle only while you burn at maximum."):format(def.displayName)
	end
	return ("%s: %d%% less damage, for the next %d hits."):format(
		def.displayName,
		math.floor(Config.CandleModifiers.sleeve.damageReduction * 100 + 0.5),
		math.floor(outcome.sleeveCharges + 0.5)
	)
end

local function removePickup(pickup: ActivePickup)
	for index = #activePickups, 1, -1 do
		if activePickups[index] == pickup then
			table.remove(activePickups, index)
			break
		end
	end
	pickup.model:Destroy()
end

local function collect(player: Player, depth: number, def: Types.LootDef, pickup: ActivePickup)
	if pickup.model.Parent == nil then
		return
	end
	local state = PlayerState.get(player.UserId)
	if
		state == nil
		or not state.alive
		or state.finished
		or state.snuffedAt ~= nil
		or state.depth ~= depth
		or (state.position - pickup.root.Position).Magnitude > Config.Loot.pickupRange
	then
		return
	end

	local applied = LootRules.apply({
		candle = state.candle,
		freeToolCharges = state.freeToolCharges,
		matchCharges = state.matchCharges,
		maxWax = state.wax.max,
		roll = collectRandom:NextNumber(),
	}, def)
	if applied == nil then
		return
	end
	state.candle = applied.candle
	state.freeToolCharges = applied.freeToolCharges
	state.matchCharges = applied.matchCharges

	local message: string
	local outcome = applied.outcome
	if outcome ~= nil then
		message = describeModifier(def, outcome)
	elseif def.kind == "ToolCharge" then
		local freeCharges = math.floor(def.freeCharges or 0)
		message = ("%s: %d free activation%s ready."):format(
			def.displayName,
			freeCharges,
			if freeCharges == 1 then "" else "s"
		)
	else
		message = "Match found: relight yourself after one solo snuff."
	end
	Remotes.get("RunEvent"):FireClient(player, "message", { text = message })

	-- THE FIRST ONE YOU EVER PICK UP EXPLAINS ITSELF. The short message above is the numeric readout
	-- ("Life Wax: burn rate down 3%, 2 held") and it fires every time; this is the sentence that says
	-- what the item actually does, and it fires once per player for the rest of their life.
	--
	-- `claimFirstSighting` is a test-and-set on the profile, so the check and the record are the same
	-- call and two pickups collected in the same instant cannot both come back "first". A row with no
	-- authored hint simply never claims one.
	if Config.Feel.itemHints.enabled and Config.Feel.itemHints.messages[def.id] ~= nil then
		if Interfaces.Persistence.claimFirstSighting(player.UserId, "item." .. def.id) then
			Remotes.get("TutorialHint"):FireClient(player, def.id)
		end
	end

	removePickup(pickup)
end

function LootService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomGroundSurface },
	parent: Instance
): (number, number, number)
	local builtCount = 0
	local relocatedCount = 0
	local emergencyCount = 0
	for spawnIndex, spawn in plan.lootSpawns do
		local def = Config.Loot.definitions[spawn.lootId]
		local roomCenter = roomCenters[spawn.roomIndex]
		local roomSurface = roomSurfaces[spawn.roomIndex]
		if def == nil or roomCenter == nil or roomSurface == nil then
			continue
		end

		-- The pure field plans the intended surface, but Terrain is voxelized and cave dressing can
		-- occupy that exact shelf. A failed preferred point sweeps OTHER SHELVES at the same distance
		-- from the room centre before it concedes any ground toward the middle, and only falls back to
		-- the guaranteed navigation hub if the whole periphery is solid — so a pickup can be badly
		-- placed but can never be deleted, buried, or dropped under the map. The slot index keeps
		-- multiple repairs in one room from converging on the same shelf.
		local resolved = SurfaceProbe.resolvePeripheralPosition(
			roomSurface,
			spawn.offset,
			Config.Loot.placementFootprint / 2,
			spawnIndex,
			{
				samples = Config.Loot.fallbackRingSamples,
				rings = Config.Loot.fallbackRings,
				minimumRadiusStuds = Config.Loot.minimumCenterDistance,
			}
		)
		if resolved.relocated then
			relocatedCount += 1
		end
		if resolved.emergency then
			emergencyCount += 1
		end
		local built = LootPickup.build(def, Config.Loot.visualSize, Config.Loot.promptHeight)
		SurfaceProbe.seat(built.model, resolved.position, roomCenter, Config.Loot.surfaceClearance)
		built.model.Parent = parent
		local pickup: ActivePickup = {
			model = built.model,
			root = built.root,
		}

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take"
		prompt.ObjectText = def.displayName
		prompt.HoldDuration = Config.Loot.pickupHoldSeconds
		prompt.MaxActivationDistance = Config.Loot.pickupRange
		prompt.RequiresLineOfSight = true
		prompt.Triggered:Connect(function(player: Player)
			collect(player, plan.depth, def, pickup)
		end)
		prompt.Parent = built.promptAttachment

		table.insert(activePickups, pickup)
		builtCount += 1
	end
	return builtCount, relocatedCount, emergencyCount
end

function LootService.reset()
	for _, pickup in activePickups do
		pickup.model:Destroy()
	end
	table.clear(activePickups)
end

return LootService
