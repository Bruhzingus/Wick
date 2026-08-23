--!strict
-- UNLITTIUS' ENCOUNTER: the dais he floats over, the eight shrine candles that ring it, and the count
-- that is the only score in the fight (Config/Unlittius, Logic/UnlittiusRules, DESIGN §9b).
--
-- WHAT THIS OWNS AND WHAT IT DOES NOT. The boss's body, his attacks and every hit he lands belong to
-- `EnemySystem/UnlittiusBehavior`; the floor's SHAPE is authored in `Logic/UnlittiusFloorPlan` and
-- carved by the ordinary builder. What is left — and all this file does — is the objective: build the
-- shrine, own who has lit what, refuse a light that should not count, and hand the authoritative
-- total to whoever is floating over the dais.
--
-- THE CANDLE IS THE WHOLE ENCOUNTER, so the gate on lighting one is the most load-bearing code here:
--
--   * IT IS SERVER-AUTHORITATIVE AND COUNTS EXACTLY ONCE. A candle flips from unlit to lit in one
--     place, behind an already-lit check, so two players finishing their holds on the same frame
--     produce one increment and one recoil rather than two of each.
--   * YOU LIGHT IT OFF YOUR OWN FLAME (`Logic/UnlittiusRules.canLightCandle`), which is the same
--     contract lighting a cave wall lamp has always had: alive, lit, not cupping, on this floor, in
--     range. A party that has gone dark cannot rush the last candle, and that is the fight's real
--     pressure — the resource you spend to win is the resource you need to survive.
--   * THE FULL GATE IS RE-RUN AT THE MOMENT OF THE LIGHT, not when the hold began. Two seconds is
--     long enough to die in, be knocked out of range in, or be snuffed in, and every one of those
--     must lose the candle.
--
-- A LIT CANDLE IS REAL LIGHT. Each one is published to `UnlittiusRegistry`, which `server/LightSources`
-- reads into the same field flames, flares, wall lamps and burning moss are on — so a chamber the
-- party has lit really is lit: dark-hunters are pushed out of it and the Drawn are pulled in, with no
-- special case anywhere in perception. That is the cost model of the whole encounter: the light you
-- need to win is the light that makes the room more dangerous while you win it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UnlittiusRules = require(ReplicatedStorage.Shared.Logic.UnlittiusRules)
local UnlittiusCandle = require(ReplicatedStorage.Shared.NewModelsAndObjects.UnlittiusCandle)
local UnlittiusFloorPlan = require(ReplicatedStorage.Shared.Logic.UnlittiusFloorPlan)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local EnemyService = require(script.Parent.EnemyService)
local LootService = require(script.Parent.LootService)
local UnlittiusRegistry = require(script.Parent.UnlittiusRegistry)
local PlayerState = require(script.Parent.PlayerState)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local NoiseService = require(script.Parent.NoiseService)
local Telemetry = require(script.Parent.Telemetry)

local UnlittiusEncounterService = {}

type Candle = {
	built: UnlittiusCandle.BuiltCandle,
	prompt: ProximityPrompt,
	depth: number,
}

type Encounter = {
	depth: number,
	center: Vector3,
	boss: any,
	candles: { Candle },
	candlesLit: number,
	-- HOW MANY CANDLES THIS CHAMBER ACTUALLY GOT. Normally the configured eight; less if a post could
	-- not be seated on real Terrain. The encounter completes at THIS number rather than at the
	-- configured one, because his floor gates the descent ladder and a seven-candle chamber that still
	-- demanded eight would dead-end the run on a bug no party could route around.
	candleTarget: number,
	complete: boolean,
	dais: Model?,
	colonnade: Model?,
}

local encounters: { [number]: Encounter } = {}

local function config()
	return Config.Unlittius
end

--------------------------------------------------------------------------------
-- The shrine
--------------------------------------------------------------------------------

-- THE DAIS. A low carved disc with a rune ring cut into it, built rather than carved into Terrain
-- because it has to be identical on a generated boss floor and in the developer laboratory — and
-- because a raised platform is what makes "he is suspended above it" legible from the doorway.
local function buildDais(center: Vector3, parent: Instance): Model
	local dais = Instance.new("Model")
	dais.Name = "UnlittiusDais"
	local radius = config().encounter.daisRadius

	local function disc(name: string, r: number, height: number, y: number, color: Color3, material: Enum.Material)
		local step = Instance.new("Part")
		step.Name = name
		step.Shape = Enum.PartType.Cylinder
		step.Size = Vector3.new(height, r * 2, r * 2)
		step.CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90))
		step.Color = color
		step.Material = material
		step.Anchored = true
		step.CanCollide = true
		step.CanQuery = true
		step.CanTouch = false
		step.TopSurface = Enum.SurfaceType.Smooth
		step.BottomSurface = Enum.SurfaceType.Smooth
		step.Parent = dais
		return step
	end

	-- Two courses, the upper one inset: a step up onto the shrine rather than a slab on the floor.
	disc("DaisBase", radius, 0.7, 0.35, Color3.fromRGB(66, 61, 56), Enum.Material.Slate)
	disc("DaisStep", radius * 0.82, 0.5, 0.9, Color3.fromRGB(78, 72, 66), Enum.Material.Slate)
	-- The rune ring. Violet and dim: it is his mark on the floor, and it is the reason the dais reads
	-- as a place something is bound to rather than as decoration.
	local ring = disc("DaisRune", radius * 0.62, 0.12, 1.16, config().body.runeColor, Enum.Material.Neon)
	ring.Transparency = 0.62
	ring.CanCollide = false
	ring.CanQuery = false

	-- Broken pedestal stumps around the rim: the shrine his own base shattered off.
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2 + 0.4
		local stump = Instance.new("Part")
		stump.Name = "PedestalStump"
		stump.Size = Vector3.new(1.1, 1.6 + (index % 3) * 0.5, 1.1)
		stump.CFrame = CFrame.new(
			center + Vector3.new(math.cos(angle) * radius * 0.88, 0.9, math.sin(angle) * radius * 0.88)
		) * CFrame.Angles(math.rad((index % 2) * 6 - 3), angle, math.rad(4))
		stump.Color = Color3.fromRGB(58, 54, 50)
		stump.Material = Enum.Material.Slate
		stump.Anchored = true
		stump.CanCollide = false
		stump.CanQuery = false
		stump.CanTouch = false
		stump.Parent = dais
	end

	-- THE PROCESSIONAL SPOKES. A carved band running from the dais out toward each candle post, which
	-- does two things at once: it tells a player arriving in the dark that the eight things on the ring
	-- are connected to the thing in the middle, and it gives the floor a direction so the chamber reads
	-- as built rather than as a round room with objects in it.
	for index, offset in UnlittiusRules.candleOffsets() do
		local bearing = math.atan2(offset.Z, offset.X)
		local inner = config().encounter.daisRadius
		local outer = config().encounter.candleRingRadius - 2
		local length = outer - inner
		local midpoint = inner + length * 0.5
		local spoke = Instance.new("Part")
		spoke.Name = "ShrineSpoke" .. index
		spoke.Size = Vector3.new(length, 0.14, 1.5)
		spoke.CFrame = CFrame.new(
			center + Vector3.new(math.cos(bearing) * midpoint, 0.07, math.sin(bearing) * midpoint)
		) * CFrame.Angles(0, -bearing, 0)
		spoke.Color = Color3.fromRGB(54, 50, 46)
		spoke.Material = Enum.Material.Slate
		spoke.Anchored = true
		spoke.CanCollide = false
		spoke.CanQuery = false
		spoke.CanTouch = false
		spoke.Parent = dais
	end

	dais.Parent = parent
	return dais
end

-- THE BROKEN COLONNADE AND ITS RUBBLE. What makes this a shrine chamber rather than a round room with
-- a boss in it — and, more importantly, what makes the fight have geometry.
--
-- THE COLUMNS ARE COVER AND THAT IS THEIR WHOLE JOB. Without them a Boulder Burst can only be answered
-- by running, and his mobility has nothing to be for: he moves precisely because somebody has put a
-- column between them and he has to slide for an angle. Four of them, on every other candle bearing,
-- so half the shrine's candles are shielded and half are in the open — which is the decision the lap
-- around the ring is made of.
--
-- THEY ARE OFF EVERY CARDINAL BY 22.5 DEGREES, inherited from the candle ring's own rotation, so a
-- column can never stand in one of the chamber's four doorway lanes.
--
-- SEEDED, NOT ROLLED FRESH. Two players on the same floor must see the same ruin, and a rebuilt floor
-- must reproduce it.
local function buildColonnade(center: Vector3, seed: number, parent: Instance): Model
	local encounter = config().encounter
	local rng = Random.new(seed)
	local colonnade = Instance.new("Model")
	colonnade.Name = "UnlittiusColonnade"

	local function stone(name: string, size: Vector3, cframe: CFrame, color: Color3, collide: boolean): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = Enum.Material.Slate
		part.Anchored = true
		part.CanCollide = collide
		part.CanQuery = collide
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = colonnade
		return part
	end

	local offsets = UnlittiusRules.candleOffsets()
	local step = math.max(math.floor(#offsets / math.max(encounter.columnCount, 1)), 1)
	for index = 1, encounter.columnCount do
		local offset = offsets[((index - 1) * step) % #offsets + 1]
		local bearing = math.atan2(offset.Z, offset.X)
		local base = center
			+ Vector3.new(math.cos(bearing) * encounter.columnRadius, 0, math.sin(bearing) * encounter.columnRadius)
		local height = encounter.columnHeightMin
			+ rng:NextNumber() * (encounter.columnHeightMax - encounter.columnHeightMin)
		-- A plinth, two drums and a snapped top: a column that was broken rather than built short.
		stone(
			"ColumnPlinth",
			Vector3.new(encounter.columnThickness * 1.5, 0.7, encounter.columnThickness * 1.5),
			CFrame.new(base + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, -bearing, 0),
			Color3.fromRGB(64, 59, 54),
			true
		)
		local drums = math.max(math.floor(height / 2.4), 1)
		for drum = 1, drums do
			local drumHeight = height / drums
			local lean = math.rad((rng:NextNumber() - 0.5) * 3)
			stone(
				"ColumnDrum",
				Vector3.new(encounter.columnThickness, drumHeight, encounter.columnThickness),
				CFrame.new(base + Vector3.new(0, 0.7 + (drum - 0.5) * drumHeight, 0))
					* CFrame.Angles(lean, -bearing + rng:NextNumber() * 0.3, lean),
				Color3.fromRGB(72, 66, 60),
				true
			)
		end
		-- The break. A wedge off the top so no two columns end the same way.
		local cap = Instance.new("WedgePart")
		cap.Name = "ColumnBreak"
		cap.Size = Vector3.new(encounter.columnThickness, 1.1 + rng:NextNumber(), encounter.columnThickness * 0.9)
		cap.CFrame = CFrame.new(base + Vector3.new(0, 0.7 + height + 0.5, 0))
			* CFrame.Angles(0, rng:NextNumber() * 6.28, math.rad((rng:NextNumber() - 0.5) * 14))
		cap.Color = Color3.fromRGB(68, 63, 58)
		cap.Material = Enum.Material.Slate
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanQuery = false
		cap.CanTouch = false
		cap.Parent = colonnade
	end

	-- TOPPLED DRUMS from the columns that are already gone. Low enough to run over, scattered on the
	-- ring rather than in it, and never inside the dais or on a doorway bearing.
	for index = 1, encounter.rubbleCount do
		local bearing = rng:NextNumber() * math.pi * 2
		local distance = encounter.daisRadius + 2 + rng:NextNumber() * (encounter.columnRadius - encounter.daisRadius)
		local drum = stone(
			"FallenDrum",
			Vector3.new(encounter.columnThickness * 0.9, encounter.columnThickness * 0.8, 1.6 + rng:NextNumber() * 1.4),
			CFrame.new(center + Vector3.new(math.cos(bearing) * distance, 0.6, math.sin(bearing) * distance))
				* CFrame.Angles(math.rad(90), rng:NextNumber() * 6.28, 0),
			Color3.fromRGB(60, 56, 52),
			false
		)
		local _ = index
		local _ = drum
	end

	colonnade.Parent = parent
	return colonnade
end

--------------------------------------------------------------------------------
-- Lighting a candle
--------------------------------------------------------------------------------

local function refusalMessage(refusal: UnlittiusRules.CandleRefusal?): string
	if refusal == "notLit" then
		return "Your candle is out. You cannot light his shrine with nothing."
	elseif refusal == "cupping" then
		return "Uncup your flame to light it."
	elseif refusal == "alreadyLit" then
		return "That one is already burning."
	elseif refusal == "tooFar" then
		return "Get closer to the shrine."
	end
	return "You cannot light that right now."
end

-- ONE CANDLE CATCHES. The single state change the whole encounter is made of, and the only place the
-- count moves.
local function lightCandle(encounter: Encounter, candle: Candle, player: Player)
	local playerId = player.UserId
	local state = PlayerState.get(playerId)
	if state == nil then
		return
	end
	local allowed, refusal = UnlittiusRules.canLightCandle({
		candleLit = candle.built.lit,
		candleDepth = candle.depth,
		alive = state.alive,
		finished = state.finished,
		isLit = state.isLit,
		isCupping = state.isCupping,
		playerDepth = state.depth,
		distance = (state.position - candle.built.flamePosition).Magnitude,
	})
	if not allowed then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = refusalMessage(refusal) })
		return
	end
	-- THE ONE-WAY DOOR. Everything below runs exactly once per candle per encounter, because the gate
	-- above reads `built.lit` and this is the line that sets it.
	UnlittiusCandle.setLit(candle.built, true, workspace:GetServerTimeNow())
	candle.prompt.Enabled = false
	encounter.candlesLit += 1

	local total = encounter.candlesLit
	Remotes.get("RunEvent"):FireAllClients("unlittiusProgress", {
		depth = encounter.depth,
		candlesLit = total,
		total = encounter.candleTarget,
		position = candle.built.flamePosition,
	})
	-- Striking a light in his shrine is not quiet. Everything on the floor that can hear gets one.
	NoiseService.emit("DripstoneImpact", candle.built.flamePosition, playerId)
	Telemetry.event("unlittius_candle_lit", playerId, {
		depth = encounter.depth,
		candlesLit = total,
		index = candle.built.index,
	})

	-- THE BOSS IS TOLD THE TOTAL, NOT AN INCREMENT (`UnlittiusRegistry`), so two candles lit on the
	-- same frame cannot dim him twice, un-dim him, or start two banishes.
	for _, boss in UnlittiusRegistry.atDepth(encounter.depth) do
		boss.candleLit(total)
	end

	if UnlittiusRules.isComplete(total, encounter.candleTarget) and not encounter.complete then
		encounter.complete = true
		for _, boss in UnlittiusRegistry.atDepth(encounter.depth) do
			boss.banish()
		end
		Remotes.get("RunEvent"):FireAllClients("bossDefeated", {
			depth = encounter.depth,
			position = encounter.center,
			boss = "Unlittius",
		})
		Telemetry.event("boss_defeated", playerId, { depth = encounter.depth, boss = "Unlittius" })
	end
end

local function buildCandles(encounter: Encounter, surface: any?, parent: Instance)
	local encounterConfig = config().encounter
	for index, offset in UnlittiusRules.candleOffsets() do
		local planned = encounter.center + offset
		-- Seat on the Terrain that was actually carved, or on this floor's registered flat fallback
		-- (the laboratory). A candle that cannot be seated is skipped rather than dropped into rock —
		-- and the encounter says so loudly, because seven candles is an unwinnable fight.
		local groundYValue: number? = nil
		if surface ~= nil then
			local resolved = SurfaceProbe.resolvePlannedPosition(surface, offset, 2)
			if not resolved.failed then
				groundYValue = resolved.position.Y
			end
		end
		if groundYValue == nil then
			groundYValue = SurfaceProbe.tryGroundY(encounter.center.Y, planned.X, planned.Z, 1)
		end
		if groundYValue == nil then
			groundYValue = EnemyService.groundFallback(encounter.depth)
		end
		if groundYValue == nil then
			warn(
				string.format(
					"[WICK] Unlittius floor %d: candle %d has no ground under it; the encounter is short one candle",
					encounter.depth,
					index
				)
			)
			continue
		end

		local base = Vector3.new(planned.X, groundYValue, planned.Z)
		local built = UnlittiusCandle.build(index, base, encounter.center, encounter.depth)
		built.model.Parent = parent

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UnlittiusCandlePrompt"
		prompt.ActionText = "Light"
		prompt.ObjectText = string.format("Shrine Candle %d/%d", index, encounterConfig.candleCount)
		prompt.HoldDuration = encounterConfig.candleHoldSeconds
		prompt.MaxActivationDistance = encounterConfig.candlePromptRange
		-- Every diegetic prompt in this game turns line of sight off, and this one has a reason of its
		-- own: the fight fills the room with falling stone and boulders, and a prompt that vanished
		-- because a boulder crossed in front of it would be lost at exactly the wrong moment.
		prompt.RequiresLineOfSight = false
		prompt.Parent = built.anchor

		local candle: Candle = { built = built, prompt = prompt, depth = encounter.depth }
		prompt.Triggered:Connect(function(player: Player)
			lightCandle(encounter, candle, player)
		end)
		table.insert(encounter.candles, candle)
		-- PUBLISHED TO THE REGISTRY, which is what makes a lit candle real light. `server/LightSources`
		-- reads it from there rather than from this service, because this service reaches `EnemyService`
		-- and from there `ThreatService`, which requires `LightSources` straight back — see the note on
		-- `UnlittiusRegistry.Candle` for the full loop.
		UnlittiusRegistry.registerCandle({
			depth = encounter.depth,
			position = built.flamePosition,
			lit = function(): boolean
				return built.lit
			end,
		})
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

export type SpawnRequest = {
	depth: number,
	center: Vector3,
	familyId: string?,
	seed: number,
	parent: Instance,
	-- The carved room's ground field, when there is one. Absent in the laboratory, which has no
	-- Terrain and registers a flat fallback instead.
	surface: any?,
	chamberRadius: number,
	ceilingHeight: number,
}

-- Build the whole encounter: dais, eight candles, and the god above them.
function UnlittiusEncounterService.spawn(request: SpawnRequest): boolean
	if encounters[request.depth] ~= nil then
		return false
	end
	local encounter: Encounter = {
		depth = request.depth,
		center = request.center,
		boss = nil,
		candles = {},
		candlesLit = 0,
		candleTarget = config().encounter.candleCount,
		complete = false,
		dais = nil,
		colonnade = nil,
	}

	encounter.dais = buildDais(request.center, request.parent)
	encounter.colonnade = buildColonnade(request.center, request.seed, request.parent)
	buildCandles(encounter, request.surface, request.parent)
	-- THE ENCOUNTER COMPLETES AT WHAT IT BUILT. A chamber that seated seven posts is a worse encounter
	-- and still a finishable one; a chamber that seated seven and demanded eight is a locked floor.
	encounter.candleTarget = #encounter.candles
	if encounter.candleTarget < config().encounter.candleCount then
		warn(
			string.format(
				"[WICK] Unlittius floor %d seated %d of %d candles; the encounter completes at %d",
				request.depth,
				encounter.candleTarget,
				config().encounter.candleCount,
				encounter.candleTarget
			)
		)
	end
	-- NOT ONE CANDLE SEATED. There is no encounter to have: building him anyway would put an
	-- unbanishable boss on a floor whose ladder he locks. Refuse, and the floor is an ordinary one.
	if encounter.candleTarget == 0 then
		warn(string.format("[WICK] Unlittius floor %d seated no candles at all; encounter refused", request.depth))
		UnlittiusEncounterService.clearDepth(request.depth)
		return false
	end

	-- HE STANDS ON THE DAIS, NOT ON THE FLOOR. The dais top is what the behaviour treats as its ground
	-- plane, so his hover, his dripstone seating and his banish rise are all measured from the shrine
	-- rather than from whatever the cave floor happened to do under it.
	local daisTop = request.center + Vector3.new(0, 1.16, 0)
	local boss = EnemyService.spawnUnlittius(
		request.depth,
		daisTop,
		request.familyId,
		request.seed,
		request.chamberRadius,
		request.ceilingHeight
	)
	if boss == nil then
		warn(string.format("[WICK] Unlittius floor %d: he refused to seat over his own dais", request.depth))
		UnlittiusEncounterService.clearDepth(request.depth)
		return false
	end
	encounter.boss = boss
	-- He dims against the shrine that was really built, not the one the config describes.
	boss:setCandleTarget(encounter.candleTarget)
	-- WHAT BANISHING HIM IS WORTH. The same reward her death pays and for the same reason: his floor
	-- carries no wax and no seams on the ground, so the fight's payout IS the fight's payout — a pile
	-- of Raw Wax per surviving miner, dropped on the dais he was pulled off.
	--
	-- ON THE BANISH RATHER THAN ON THE EIGHTH CANDLE. The candles are the fight; the banish is the end
	-- of it, and a reward that landed while he was still being dragged into the ceiling would be paid
	-- before the encounter had actually finished.
	boss.onBanished = function()
		LootService.dropBossReward(request.depth, request.center, request.parent, request.surface)
	end
	encounters[request.depth] = encounter
	Telemetry.event("unlittius_encounter_built", nil, {
		depth = request.depth,
		candles = #encounter.candles,
	})
	return true
end

-- Every lit candle in this encounter reaches the light field through `UnlittiusRegistry`
-- (registered above, read by `server/LightSources`). There is deliberately no `sources` function on
-- this service: a second path to the same list is a second thing to forget to clear.

function UnlittiusEncounterService.candlesLitAtDepth(depth: number): number
	local encounter = encounters[depth]
	return if encounter ~= nil then encounter.candlesLit else 0
end

-- Whether an unbanished Unlittius still holds this floor. RunOrchestrator's descent guard reads this
-- through `EnemyService`, exactly as it reads the Queen's registry.
function UnlittiusEncounterService.isActiveAtDepth(depth: number): boolean
	return UnlittiusRegistry.activeAtDepth(depth)
end

function UnlittiusEncounterService.clearDepth(depth: number)
	local encounter = encounters[depth]
	if encounter == nil then
		return
	end
	-- THE BODIES BELONG TO `EnemyService` and are torn down with the floor there. What is owned here
	-- is the shrine: the prompts have to be disconnected explicitly because a ProximityPrompt whose
	-- model is destroyed while a player is mid-hold fires nothing, and a candle that is destroyed
	-- while a hold is running must not be able to complete against a dead encounter.
	for _, candle in encounter.candles do
		candle.prompt.Enabled = false
		candle.prompt:Destroy()
		if candle.built.model.Parent ~= nil then
			candle.built.model:Destroy()
		end
	end
	for _, built in { encounter.dais, encounter.colonnade } do
		if built ~= nil and built.Parent ~= nil then
			built:Destroy()
		end
	end
	encounters[depth] = nil
	UnlittiusRegistry.clearDepth(depth)
end

function UnlittiusEncounterService.reset()
	for depth in encounters do
		UnlittiusEncounterService.clearDepth(depth)
	end
	table.clear(encounters)
	UnlittiusRegistry.reset()
end

-- Config and the floor plan are read for the encounter's own gating; referenced so the dependency is
-- explicit for anybody retuning it.
function UnlittiusEncounterService.requiresBanishToDescend(): boolean
	return config().encounter.requiresBanishToDescend
end

function UnlittiusEncounterService.chamberRoom(): number
	return UnlittiusFloorPlan.CENTER_ROOM
end

return UnlittiusEncounterService
