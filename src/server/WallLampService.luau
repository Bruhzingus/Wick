--!strict
-- THE CAVE'S WALL LAMPS (Config/WallLamp, NewModelsAndObjects/WallLamp): who lit what, what is
-- currently burning, and the floor-wide answer the crowned lamp gives.
--
-- WHAT CHANGED, AND WHY THIS FILE EXISTS AT ALL. The lamps used to be a private field on the
-- extraction fixture — `BrazierService` held the list and lit all of them in one scripted sequence
-- when somebody cashed out. That made a floor's worth of objects into set dressing for a results
-- screen, and it meant the code that pays a player also owned the lighting of rooms they were not
-- standing in. Lighting the cave is a player VERB now, mid-run, with its own cost and its own
-- consequences, so it gets its own service and the Brazier goes back to owning exactly one thing.
--
-- THE SERVER OWNS THE CLOCK. A client asks to begin, and later claims to have finished; this file
-- stamps the start, refuses any completion that arrives sooner than the hold allows
-- (`Logic/WallLampRules.holdSatisfied`), and re-runs the full gate at the moment of the light rather
-- than trusting the one that passed at the beginning. A player who died, went out, cupped, walked
-- off or changed floor mid-hold lights nothing.
--
-- A LIT LAMP IS REAL LIGHT. `sources` is read every tick by `server/LightSources` and joins the same
-- field as flames, flares, decoys and remains, so a lit room pushes dark-hunters out and pulls the
-- Drawn in with no special case anywhere in perception. That is the whole cost model: lighting is
-- free in wax and expensive in attention.
--
-- IT IS NOT A CUTSCENE. When the crowned lamp catches, the rest of the floor answers room by room
-- while everybody keeps full control of their character. Nothing here freezes anybody, turns a
-- camera, or delays a results card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local WallLamp = require(ReplicatedStorage.Shared.NewModelsAndObjects.WallLamp)
local WallLampRules = require(ReplicatedStorage.Shared.Logic.WallLampRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local MovementService = require(script.Parent.MovementService)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)

local WallLampService = {}

type Lamp = {
	depth: number,
	built: WallLamp.BuiltWallLamp,
	position: Vector3,
	variant: WallLampRules.LampVariant,
}

type Floor = {
	depth: number,
	-- The crowned lamp in the room the floor ends in. Optional only because a pathological floor plan
	-- could fail to find a mountable wall; every ordinary floor has one.
	main: Lamp?,
	-- Every room lamp, ordered by distance from the crowned lamp. The cascade walks this list in
	-- order, so what a player hears is the light travelling toward them or away from them.
	lamps: { Lamp },
	cascadeRunning: boolean,
}

-- One player's hold in progress. At most one at a time: a second `begin` replaces the first, which
-- is what makes walking from one lamp to another during a hold behave sensibly instead of leaving a
-- ghost hold on the lamp behind you.
type Hold = {
	lamp: Lamp,
	startedAt: number,
	-- 0..1, eased up over `leanRiseSeconds` by `tick`. The candle bows into position rather than
	-- snapping there, and the same value unwinds it when the hold ends.
	leanProgress: number,
}

local floors: { [number]: Floor } = {}
-- Anchor part -> lamp. The client names a lamp by sending its anchor, and this is the only thing that
-- turns that instance back into something the server will act on: an anchor that is not a key here
-- is not a lamp, however convincing the part looks.
local lampsByAnchor: { [BasePart]: Lamp } = {}
local holds: { [Types.PlayerId]: Hold } = {}

local function config()
	return Config.WallLamp
end

-- The world direction from a player to the lamp they are lighting. Horizontal only: a candle bows
-- over toward a wall, it does not tip backward to reach something above it.
local function leanDirection(playerPosition: Vector3, lampPosition: Vector3): Vector3
	local flat = Vector3.new(lampPosition.X - playerPosition.X, 0, lampPosition.Z - playerPosition.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero
end

-- EVERY WAY A HOLD ENDS COMES THROUGH HERE: completion, cancel, death, expiry, teardown, a player
-- leaving. One exit means the candle can never be left bowed at a wall and a player can never be
-- left rooted by a lamp they are no longer lighting.
local function clearHold(playerId: Types.PlayerId)
	if holds[playerId] == nil then
		return
	end
	holds[playerId] = nil
	CharacterService.applyLean(playerId, 0, nil)
	local state = PlayerState.get(playerId)
	if state ~= nil and state.isLightingLamp then
		state.isLightingLamp = false
		MovementService.refresh(playerId)
	end
end

-- The full gate, assembled from live state and answered by the pure rules. Called on `begin` AND
-- again on `commit`: the two are seconds apart and everything in between can change.
local function evaluate(playerId: Types.PlayerId, lamp: Lamp): (boolean, WallLampRules.Refusal?)
	local state = PlayerState.get(playerId)
	if state == nil then
		return false, "notAlive"
	end
	return WallLampRules.canLight({
		lampLit = lamp.built.lit,
		lampDepth = lamp.depth,
		alive = state.alive,
		finished = state.finished,
		isLit = state.isLit,
		isCupping = state.isCupping,
		playerDepth = state.depth,
		distance = (state.position - lamp.position).Magnitude,
	})
end

-- ONE LAMP CATCHING. Everything that is true of a lit lamp becomes true here and nowhere else: the
-- prop, the light field (via `sources`, which reads `built.lit`), and the cue every nearby client
-- plays. `main` picks the deeper fixture cue for the crowned lamp and the small flame for a room
-- candle, which is the only difference in how the two are announced.
local function ignite(lamp: Lamp)
	if lamp.built.lit then
		return
	end
	WallLamp.setLit(lamp.built, true)
	Remotes.get("RunEvent"):FireAllClients("lampLit", {
		position = lamp.position,
		model = lamp.built.model,
		main = lamp.variant == "Main",
	})
end

-- THE FLOOR ANSWERING. Room by room, nearest to the crowned lamp first, compressed to fit inside the
-- cascade's budget however large the floor is.
--
-- IT LIGHTS EVERY LAMP, INCLUDING ROOMS NOBODY HAS ENTERED. That is the point of the crowned lamp:
-- the player who found the way down makes the WHOLE floor legible for the friends still in it, not
-- just the parts of it somebody already walked. A cascade that retraced the party's route would
-- light nothing at all on the floor where one member rushed ahead — which is exactly the floor where
-- somebody needs the help.
--
-- Already-lit lamps are skipped rather than replayed: a player who lit their own way here does not
-- get their work announced back at them.
local function cascade(floor: Floor)
	if floor.cascadeRunning then
		return
	end
	floor.cascadeRunning = true
	task.spawn(function()
		local pending: { Lamp } = {}
		for _, lamp in floor.lamps do
			if not lamp.built.lit then
				table.insert(pending, lamp)
			end
		end
		local step = WallLampRules.cascadeStepSeconds(#pending)
		task.wait(WallLampRules.cascadeLeadSeconds())
		for _, lamp in pending do
			-- The floor can retire underneath the cascade (a restart, a teardown, the party descending
			-- past the retention window). Both checks matter: the registry entry going stale and the
			-- model leaving the world are different failures with the same correct response.
			if floors[floor.depth] ~= floor or lamp.built.model.Parent == nil then
				break
			end
			ignite(lamp)
			task.wait(step)
		end
		floor.cascadeRunning = false
	end)
end

local function beginHold(player: Player, lamp: Lamp)
	local allowed, refusal = evaluate(player.UserId, lamp)
	-- The client starts drawing its ring the instant the key goes down, so a refusal has to come back
	-- as an explicit answer; silence would leave a completion circle filling up for an action that was
	-- never going to happen.
	Remotes.get("RunEvent"):FireClient(player, "lampHold", {
		accepted = allowed,
		lamp = lamp.built.anchor,
		holdSeconds = WallLampRules.holdSecondsFor(lamp.variant),
		reason = refusal,
	})
	if not allowed then
		clearHold(player.UserId)
		return
	end
	holds[player.UserId] = {
		lamp = lamp,
		startedAt = os.clock(),
		leanProgress = 0,
	}
	-- ROOTED FOR THE DURATION, server-side. The client also stops asking to move, but the authority is
	-- here: `MovementService` decides speed from state alone, and this is the third flag in that family
	-- (`isSwinging`, `isHeldByEnemy`, `trippedUntil`).
	local state = PlayerState.get(player.UserId)
	if state ~= nil then
		state.isLightingLamp = true
		MovementService.refresh(player.UserId)
	end
end

local function commitHold(player: Player, lamp: Lamp)
	local hold = holds[player.UserId]
	-- A commit for a lamp this player never began, or began and then abandoned for another, is not an
	-- error worth answering — it is a client that got ahead of itself or one that is lying. Both get
	-- the same nothing.
	if hold == nil or hold.lamp ~= lamp then
		return
	end
	if not WallLampRules.holdSatisfied(lamp.variant, hold.startedAt, os.clock()) then
		return
	end
	local allowed = evaluate(player.UserId, lamp)
	clearHold(player.UserId)
	if not allowed then
		return
	end

	ignite(lamp)
	Telemetry.event("wall_lamp_lit", player.UserId, {
		depth = lamp.depth,
		variant = lamp.variant,
	})

	-- THE CROWNED LAMP ANSWERS THE FLOOR. Every other lamp is an ordinary room lamp and answers
	-- nothing: what one player lit stays one room, which is what makes lighting the way back a real
	-- piece of work rather than a formality.
	if lamp.variant == "Main" then
		local floor = floors[lamp.depth]
		if floor ~= nil then
			cascade(floor)
		end
	end
end

local function onAction(player: Player, action: unknown, target: unknown)
	if not WallLampRules.isEnabled() or not RequestGuard.allow(player, "LampAction") then
		return
	end
	if action == "cancel" then
		clearHold(player.UserId)
		return
	end
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
		return
	end
	local lamp = lampsByAnchor[target :: BasePart]
	if lamp == nil then
		return
	end
	if action == "begin" then
		beginHold(player, lamp)
	elseif action == "commit" then
		commitHold(player, lamp)
	end
end

-- EVERY LIT LAMP IN THE WORLD, as light-field sources. Read once per tick by `server/LightSources`
-- and joined to the same list flames, flares, decoys and remains are on — that shared list is why
-- the lamps needed no change anywhere in threat perception to become real.
--
-- Deliberately unfiltered by floor: `LightSources` builds one field for the whole server and every
-- consumer already judges by distance, so a lamp two floors up contributes exactly nothing to a
-- query down here without anybody having to remember to exclude it.
function WallLampService.sources(): { Types.LightSource }
	local sources: { Types.LightSource } = {}
	if not WallLampRules.isEnabled() then
		return sources
	end
	for _, floor in floors do
		for _, lamp in floor.lamps do
			if lamp.built.lit then
				table.insert(sources, WallLampRules.lightSource(lamp.variant, lamp.position))
			end
		end
		local main = floor.main
		if main ~= nil and main.built.lit then
			table.insert(sources, WallLampRules.lightSource(main.variant, main.position))
		end
	end
	return sources
end

-- Advances the bow and drops holds nobody is coming back to.
--
-- THE LEAN IS EASED HERE RATHER THAN SPAWNED PER HOLD. A `task.spawn` per lighting player would be a
-- coroutine per interaction whose only job is to interpolate one number; this service already ticks,
-- and at most a handful of holds can be live at once.
function WallLampService.tick(dt: number)
	local now = os.clock()
	local rise = math.max(config().interaction.leanRiseSeconds, 0.001)
	local maximumLean = math.rad(config().interaction.leanDegrees)
	for playerId, hold in holds do
		if WallLampRules.holdExpired(hold.startedAt, now) then
			-- Nobody sent a cancel: they disconnected, died, or their client stopped talking. The
			-- candle stands back up on its own rather than staying bowed at a wall until teardown.
			clearHold(playerId)
			continue
		end
		local state = PlayerState.get(playerId)
		if state == nil or not state.alive or state.finished then
			clearHold(playerId)
			continue
		end
		hold.leanProgress = math.min(hold.leanProgress + dt / rise, 1)
		-- Ease-out: the candle tips quickly and settles, which reads as somebody reaching rather than
		-- as a hinge opening at a constant rate.
		local eased = 1 - (1 - hold.leanProgress) ^ 2
		CharacterService.applyLean(playerId, maximumLean * eased, leanDirection(state.position, hold.lamp.position))
	end
end

-- The fixtures are built by `FloorBuilder` and handed over already cold. This service adds nothing to
-- the world; it only learns what exists and takes ownership of what happens to it.
function WallLampService.registerFloor(
	depth: number,
	runtime: {
		main: WallLamp.BuiltWallLamp?,
		lamps: { WallLamp.BuiltWallLamp },
	}
)
	if not WallLampRules.isEnabled() then
		return
	end
	local floor: Floor = {
		depth = depth,
		main = nil,
		lamps = {},
		cascadeRunning = false,
	}

	local function adopt(built: WallLamp.BuiltWallLamp): Lamp
		local lamp: Lamp = {
			depth = depth,
			built = built,
			position = built.flamePosition,
			variant = built.variant,
		}
		built.anchor:SetAttribute(config().depthAttribute, depth)
		lampsByAnchor[built.anchor] = lamp
		return lamp
	end

	if runtime.main ~= nil then
		floor.main = adopt(runtime.main :: WallLamp.BuiltWallLamp)
	end
	for _, built in runtime.lamps do
		table.insert(floor.lamps, adopt(built))
	end
	floors[depth] = floor
end

function WallLampService.clearDepth(depth: number)
	local floor = floors[depth]
	if floor == nil then
		return
	end
	-- The anchors die with the floor's model, but the lookup table is this service's own and would
	-- otherwise hold a reference to every part of every floor the party has ever left behind.
	for _, lamp in floor.lamps do
		lampsByAnchor[lamp.built.anchor] = nil
	end
	local main = floor.main
	if main ~= nil then
		lampsByAnchor[main.built.anchor] = nil
	end
	for playerId, hold in holds do
		if hold.lamp.depth == depth then
			clearHold(playerId)
		end
	end
	floors[depth] = nil
end

function WallLampService.reset()
	for playerId in holds do
		clearHold(playerId)
	end
	table.clear(floors)
	table.clear(lampsByAnchor)
	table.clear(holds)
end

function WallLampService.init()
	Remotes.get("LampAction").OnServerEvent:Connect(function(player: Player, action: unknown, target: unknown)
		onAction(player, action, target)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		clearHold(player.UserId)
	end)
end

return WallLampService
