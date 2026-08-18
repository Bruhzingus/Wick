--!strict
-- Server-authoritative adapter for config-planned in-run loot. Pickups either add a roguelike
-- modifier to the candle the player already has or add free activations consumed by ToolService;
-- there is no parallel inventory and no second resource.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local CandleModifiers = require(ReplicatedStorage.Shared.Logic.CandleModifiers)
local LootRules = require(ReplicatedStorage.Shared.Logic.LootRules)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local LootPickup = require(ReplicatedStorage.Shared.NewModelsAndObjects.LootPickup)
local PlayerState = require(script.Parent.PlayerState)
local SurfaceProbe = require(script.Parent.SurfaceProbe)

local LootService = {}

type RoomGroundSurface = SurfaceProbe.RoomGroundSurface

type ActivePickup = {
	model: Model,
	root: BasePart,
	depth: number,
	-- RESPAWNING PICKUPS, and today only the Grub Queen's chamber uses them
	-- (Logic/BossFloorPlan). Nil everywhere else, which is what keeps ordinary loot exactly as
	-- one-shot as it has always been: a cave you can farm by walking a lap is not this game.
	--
	-- The boss floor needs them because the fight is a resource race with no exit — the player cannot
	-- leave to restock, so a chamber whose supplies ran out would simply stall until they died. The
	-- respawn is the encounter's clock, not a generosity.
	respawnSeconds: number?,
	-- Set while a respawning pickup is spent and waiting. The model is kept and hidden rather than
	-- rebuilt, so its seating on the rock — which was probed once, at floor build — is never
	-- re-derived and can never drift into a wall on the second appearance.
	hiddenUntil: number?,
	prompt: ProximityPrompt?,
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

-- Hide a spent pickup without destroying it, and remember when it comes back. Transparency and the
-- prompt are the whole of it: the model stays exactly where the floor build seated it.
local function hidePickup(pickup: ActivePickup, seconds: number)
	pickup.hiddenUntil = os.clock() + math.max(seconds, 0)
	local prompt = pickup.prompt
	if prompt ~= nil then
		prompt.Enabled = false
	end
	for _, part in pickup.model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("WickLootTransparency", part.Transparency)
			part.Transparency = 1
		elseif part:IsA("Light") then
			part.Enabled = false
		end
	end
end

local function showPickup(pickup: ActivePickup)
	pickup.hiddenUntil = nil
	local prompt = pickup.prompt
	if prompt ~= nil then
		prompt.Enabled = true
	end
	for _, part in pickup.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = tonumber(part:GetAttribute("WickLootTransparency")) or 0
		elseif part:IsA("Light") then
			part.Enabled = true
		end
	end
end

local function removePickup(pickup: ActivePickup)
	-- A respawning pickup is never consumed, only spent. It goes quiet for its interval and comes
	-- back in the same place.
	local respawn = pickup.respawnSeconds
	if respawn ~= nil and pickup.model.Parent ~= nil then
		hidePickup(pickup, respawn)
		return
	end
	for index = #activePickups, 1, -1 do
		if activePickups[index] == pickup then
			table.remove(activePickups, index)
			break
		end
	end
	pickup.model:Destroy()
end

local function collect(player: Player, depth: number, def: Types.LootDef, pickup: ActivePickup)
	if pickup.model.Parent == nil or pickup.hiddenUntil ~= nil then
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
		dynamiteCharges = state.dynamiteCharges,
		maxWax = state.wax.max,
		roll = collectRandom:NextNumber(),
	}, def)
	if applied == nil then
		return
	end
	state.candle = applied.candle
	state.freeToolCharges = applied.freeToolCharges
	state.matchCharges = applied.matchCharges
	state.dynamiteCharges = applied.dynamiteCharges

	local message: string
	local outcome = applied.outcome
	local dynamiteTaken = applied.dynamiteTaken
	if outcome ~= nil then
		message = describeModifier(def, outcome)
	elseif dynamiteTaken ~= nil then
		-- Says what is in the bag NOW, not what was on the floor. A crate that hit the carry cap has to
		-- report the smaller truth, or a player walks away believing they are holding three.
		message = ("%s: %d stick%s taken (%d carried)."):format(
			def.displayName,
			dynamiteTaken,
			if dynamiteTaken == 1 then "" else "s",
			applied.dynamiteCharges
		)
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
): (number, number, number, number)
	local builtCount = 0
	local relocatedCount = 0
	local refusedCount = 0
	local supportWarningCount = 0
	for _, spawn in plan.lootSpawns do
		local def = Config.Loot.definitions[spawn.lootId]
		local roomCenter = roomCenters[spawn.roomIndex]
		local roomSurface = roomSurfaces[spawn.roomIndex]
		if def == nil or roomCenter == nil or roomSurface == nil then
			refusedCount += 1
			warn(
				string.format(
					"[WICK] refused planned loot %q on floor %d room %d: missing %s",
					spawn.lootId,
					plan.depth,
					spawn.roomIndex,
					if def == nil then "definition" else "room surface"
				)
			)
			continue
		end

		-- X/Z belongs to the planner: it is already random, open, dry, and reserved from every other
		-- placement. Runtime may reconcile only Y and the tangent normal. Moving a failed pickup to a
		-- different shelf discarded those guarantees and caused both centre clustering and overlaps.
		local resolved =
			SurfaceProbe.resolvePlannedPosition(roomSurface, spawn.offset, Config.Loot.placementFootprint / 2)
		if resolved.failed then
			refusedCount += 1
			warn(
				string.format(
					"[WICK] refused loot %q on floor %d room %d: planned footprint has no complete Terrain support",
					def.id,
					plan.depth,
					spawn.roomIndex
				)
			)
			continue
		end
		local built = LootPickup.build(def, Config.Loot.visualSize, Config.Loot.promptHeight)
		SurfaceProbe.seat(built.model, resolved.position, roomCenter, Config.Loot.surfaceClearance, resolved.normal)

		-- DID THAT ACTUALLY LAND ON THE FLOOR? Measured from the built silhouette, independently of the
		-- probe that chose the spot — a probe fooled by the geometry will happily agree with itself, so
		-- the only check worth anything is one that looks at the finished object.
		--
		-- This audit is intentionally diagnostic. Its averaged X/Z can be wrong for asymmetric art, so
		-- the complete support probe above is the hard gate and this check may not erase valid content.
		local gap = SurfaceProbe.groundGapStuds(built.model)
		if gap == nil or math.abs(gap) > Config.Floors.geometry.placementProbe.maxSeatedGapStuds then
			supportWarningCount += 1
			warn(
				string.format(
					"[WICK] loot %q on floor %d room %d has a suspicious support gap: %s",
					def.id,
					plan.depth,
					spawn.roomIndex,
					if gap == nil then "no terrain below" else string.format("%.2f studs", gap)
				)
			)
		end
		built.model.Parent = parent
		built.model:SetAttribute(Config.Diagnostics.itemNameAttribute, def.displayName)
		CollectionService:AddTag(built.model, Config.Diagnostics.itemTag)
		local pickup: ActivePickup = {
			model = built.model,
			root = built.root,
			depth = plan.depth,
			respawnSeconds = spawn.respawnSeconds,
			hiddenUntil = nil,
			prompt = nil,
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
		pickup.prompt = prompt

		table.insert(activePickups, pickup)
		builtCount += 1
	end
	return builtCount, relocatedCount, refusedCount, supportWarningCount
end

-- Brings spent respawning pickups back. Cheap enough to run every tick: the list is short and the
-- common case is that nothing on it is hidden at all.
function LootService.tick()
	local now = os.clock()
	for _, pickup in activePickups do
		local hiddenUntil = pickup.hiddenUntil
		if hiddenUntil ~= nil and now >= hiddenUntil and pickup.model.Parent ~= nil then
			showPickup(pickup)
		end
	end
end

function LootService.clearDepth(depth: number)
	for index = #activePickups, 1, -1 do
		local pickup = activePickups[index]
		if pickup.depth == depth then
			pickup.model:Destroy()
			table.remove(activePickups, index)
		end
	end
end

function LootService.reset()
	for _, pickup in activePickups do
		pickup.model:Destroy()
	end
	table.clear(activePickups)
end

return LootService
