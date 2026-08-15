--!strict
-- Server authority for the Ashamed Lurker. It owns every state transition, the run trigger, the
-- delayed grab check, gaze validation, the wax it takes, and where a shamed creature reappears.
-- Clients only report their camera (Roblox does not replicate it) and build the body; nothing on
-- the wire can move, trigger, clear, or damage anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Rules = require(ReplicatedStorage.Shared.Logic.AshamedLurkerRules)
local Protocol = require(ReplicatedStorage.Shared.AshamedLurkerVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local WaxService = require(script.Parent.WaxService)
local RequestGuard = require(script.Parent.RequestGuard)
local FloorBuilder = require(script.Parent.FloorBuilder)
local Telemetry = require(script.Parent.Telemetry)

local AshamedLurkerService = {}

type GazeSample = {
	cameraPosition: Vector3,
	lookVector: Vector3,
	receivedAt: number,
}

type Runtime = {
	proxy: BasePart,
	sites: { FloorBuilder.LurkerSite },
	siteIndex: number,
	depth: number,
	state: string,
	stateEndsAt: number,
	lastTriggerAt: number,
	-- Bumped on every state change and relocation so a scheduled grab check belonging to an older
	-- lunge can never resolve against a newer one.
	generation: number,
	gazeProgress: { [Types.PlayerId]: number },
	gazeSamples: { [Types.PlayerId]: GazeSample },
}

local runtimesByDepth: { [number]: { Runtime } } = {}
local runtimesByProxy: { [BasePart]: Runtime } = {}
local triggerAccumulator = 0
local gazeAccumulator = 0

-- Stop every outstanding action owned by this runtime before dropping its indexes. The proxy is
-- builder-owned (normally by a floor model), so unregistering never destroys it; the caller that
-- owns the containing room remains responsible for the Instance lifecycle.
local function invalidateRuntime(runtime: Runtime)
	runtime.generation += 1
	table.clear(runtime.gazeProgress)
	table.clear(runtime.gazeSamples)
	if runtimesByProxy[runtime.proxy] == runtime then
		runtimesByProxy[runtime.proxy] = nil
	end
end

local function currentSite(runtime: Runtime): FloorBuilder.LurkerSite
	return runtime.sites[runtime.siteIndex]
end

local function setState(runtime: Runtime, state: string, duration: number)
	runtime.state = state
	runtime.stateEndsAt = os.clock() + math.max(0, duration)
	runtime.generation += 1
	if runtime.proxy.Parent == nil then
		return
	end
	runtime.proxy:SetAttribute(Protocol.attributes.stateStartedAt, Workspace:GetServerTimeNow())
	-- State is written last so a client's change signal always observes the matching timestamp.
	runtime.proxy:SetAttribute(Protocol.attributes.state, state)
end

-- Move to the next reserved arch on this floor. A creature never returns to the arch it was shamed
-- out of while it has anywhere else to go, so clearing one buys a route rather than resetting it.
local function relocate(runtime: Runtime)
	if #runtime.sites > 1 then
		runtime.siteIndex = runtime.siteIndex % #runtime.sites + 1
	end
	local site = currentSite(runtime)
	table.clear(runtime.gazeProgress)
	table.clear(runtime.gazeSamples)
	runtime.lastTriggerAt = -math.huge
	if runtime.proxy.Parent ~= nil then
		runtime.proxy.CFrame = site.cframe
		runtime.proxy:SetAttribute(Protocol.attributes.trapSide, site.trapSide)
		runtime.proxy:SetAttribute(Protocol.attributes.doorWidth, site.doorWidth)
		runtime.proxy:SetAttribute(Protocol.attributes.doorHeight, site.doorHeight)
		runtime.proxy:SetAttribute(Protocol.attributes.site, runtime.siteIndex)
	end
	setState(runtime, Protocol.states.dormant, 0)
end

local function isRunner(state: Types.PlayerRunState, depth: number): boolean
	return state.alive
		and not state.finished
		and state.snuffedAt == nil
		and state.depth == depth
		and not PlayerState.isThreatProtected(state.playerId)
end

local function grab(runtime: Runtime, playerId: Types.PlayerId)
	local site = currentSite(runtime)
	local state = PlayerState.get(playerId)
	if state == nil or not isRunner(state, runtime.depth) then
		return
	end
	-- The grab volume is only checked here, at the impact frame. Leaving the lane during the
	-- wind-up is a real escape and costs nothing.
	if not Rules.insideGrabVolume(site.cframe, state.position, site.doorWidth, site.trapSide) then
		return
	end

	-- No impact span: a grab is one standalone hit and costs a Candle Sleeve one whole charge.
	local lost = WaxService.drainExternal(
		playerId,
		state.wax.max * Config.AshamedLurker.trigger.waxLossFraction,
		"DamageThreat",
		"Something in the archway took the rest of your wax.",
		nil,
		"AshamedLurker"
	)
	Remotes.get("RunEvent"):FireAllClients("lurkerGrab", {
		position = runtime.proxy.Position,
		depth = runtime.depth,
		playerId = playerId,
	})
	Telemetry.event("lurker_grab", playerId, { depth = runtime.depth, waxLost = lost })

	-- A grab survived teaches the counterplay for next time; a grab that killed goes through the
	-- death-hint system instead (Config/Feel.deathHints), so this only ever needs to fire once ever
	-- per player — closer to `itemHints`' first-pickup shape than the six ordinary threats' repeat-
	-- with-cooldown one, since the Lurker cannot appear before floor 4 anyway (past `tutorialHints.
	-- maxDepth`), so it could never earn a slot in that depth-capped system regardless.
	if state.alive and Config.Feel.tutorialHints.enabled then
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil and Interfaces.Persistence.claimFirstSighting(playerId, "encounter.AshamedLurker") then
			Remotes.get("TutorialHint"):FireClient(player, "AshamedLurker")
		end
	end
end

local function processTrigger(runtime: Runtime)
	if runtime.state ~= Protocol.states.dormant then
		return
	end
	local now = os.clock()
	local trigger = Config.AshamedLurker.trigger
	if now - runtime.lastTriggerAt < trigger.rearmSeconds then
		return
	end
	local site = currentSite(runtime)

	for playerId, state in PlayerState.all() do
		if not isRunner(state, runtime.depth) then
			continue
		end
		-- Speed is MEASURED from the authoritative body, never claimed by the client.
		local speed = CharacterService.horizontalSpeed(playerId)
		if not Rules.qualifiesRunTrigger(site.cframe, state.position, speed, site.doorWidth, site.trapSide) then
			continue
		end

		runtime.lastTriggerAt = now
		setState(runtime, Protocol.states.triggered, Rules.triggeredStateSeconds())
		local generation = runtime.generation
		task.delay(trigger.grabCheckDelaySeconds, function()
			if runtime.generation == generation and runtime.proxy.Parent ~= nil then
				grab(runtime, playerId)
			end
		end)
		return
	end
end

-- Does the camera actually have the face in view, or is a wall between them? Player characters are
-- excluded so a teammate crossing the line cannot block someone else's stare; the creature's own
-- body only exists on clients, so anything hit here is genuine cave geometry.
local function hasLineOfSight(cameraPosition: Vector3, facePosition: Vector3): boolean
	local offset = facePosition - cameraPosition
	local distance = offset.Magnitude
	if distance <= 0.001 then
		return false
	end
	-- Stop short of the face. The head is embedded in the arch it clings to, so the rock immediately
	-- behind and around it is not an occluder — without this inset the creature's own doorway blocks
	-- every stare and it can never be shamed off.
	local inset = Config.AshamedLurker.gaze.losEndpointInset
	if distance <= inset then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(exclude, character)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = false
	return Workspace:Raycast(cameraPosition, offset.Unit * (distance - inset), params) == nil
end

local function processGaze(runtime: Runtime, dt: number)
	if runtime.state ~= Protocol.states.dormant then
		return
	end
	local gaze = Config.AshamedLurker.gaze
	local now = os.clock()
	local site = currentSite(runtime)
	local facePosition = Rules.facePosition(site.cframe, site.doorWidth, site.doorHeight, site.trapSide)

	for playerId, state in PlayerState.all() do
		local qualifies = false
		local sample = runtime.gazeSamples[playerId]
		if sample ~= nil and isRunner(state, runtime.depth) then
			local fresh = now - sample.receivedAt <= gaze.sampleTimeoutSeconds
			-- A camera far from the body is either a stale sample or a forged one.
			local plausible = (sample.cameraPosition - state.position).Magnitude <= gaze.maxCameraOffsetStuds
			-- It has to be able to SEE that it is being seen. Creeping past a dim candle is a real
			-- option; shaming it off costs you the brightness to do it.
			local bright = Rules.lightRevealsWatcher(
				state.isLit,
				state.isCupping,
				state.burnRate,
				state.flareEndsAt > now,
				state.modifiers.minBurnRate,
				state.modifiers.maxBurnRate
			)
			if fresh and plausible and bright then
				qualifies = Rules.gazeQualifies({
					facePosition = facePosition,
					cameraPosition = sample.cameraPosition,
					lookVector = sample.lookVector,
				}) and hasLineOfSight(sample.cameraPosition, facePosition)
			end
		end

		local progress = Rules.advanceGazeProgress(runtime.gazeProgress[playerId] or 0, dt, qualifies)
		runtime.gazeProgress[playerId] = progress
		if Rules.isGazeComplete(progress) then
			setState(runtime, Protocol.states.ashamed, Config.AshamedLurker.ashamedSeconds)
			table.clear(runtime.gazeProgress)
			table.clear(runtime.gazeSamples)
			Telemetry.event("lurker_shamed", playerId, { depth = runtime.depth })
			return
		end
	end
end

local function onGazeSample(player: Player, proxy: unknown, cameraPosition: unknown, lookVector: unknown)
	if not RequestGuard.allow(player, "LurkerGaze") then
		return
	end
	if typeof(proxy) ~= "Instance" or not proxy:IsA("BasePart") then
		return
	end
	if not RequestGuard.finiteVector3(cameraPosition) or not RequestGuard.finiteVector3(lookVector) then
		return
	end
	local runtime = runtimesByProxy[proxy :: BasePart]
	if runtime == nil or runtime.state ~= Protocol.states.dormant then
		return
	end
	local state = PlayerState.get(player.UserId)
	if state == nil or not isRunner(state, runtime.depth) then
		return
	end
	runtime.gazeSamples[player.UserId] = {
		cameraPosition = cameraPosition :: Vector3,
		lookVector = lookVector :: Vector3,
		receivedAt = os.clock(),
	}
end

function AshamedLurkerService.init()
	Remotes.get("LurkerGaze").OnServerEvent:Connect(onGazeSample)
	Players.PlayerRemoving:Connect(function(player)
		AshamedLurkerService.clearPlayer(player.UserId)
	end)
end

function AshamedLurkerService.clearPlayer(playerId: Types.PlayerId)
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			runtime.gazeProgress[playerId] = nil
			runtime.gazeSamples[playerId] = nil
		end
	end
end

-- Remove one registered creature without disturbing any other Lurker on the same virtual floor.
-- This is primarily useful to bounded developer rooms, but keeping it here prevents those rooms
-- from reaching into the service's private runtime maps.
function AshamedLurkerService.unregister(proxy: BasePart): boolean
	local runtime = runtimesByProxy[proxy]
	if runtime == nil then
		return false
	end
	invalidateRuntime(runtime)

	local floorRuntimes = runtimesByDepth[runtime.depth]
	if floorRuntimes ~= nil then
		local index = table.find(floorRuntimes, runtime)
		if index ~= nil then
			table.remove(floorRuntimes, index)
		end
		if #floorRuntimes == 0 then
			runtimesByDepth[runtime.depth] = nil
		end
	end
	return true
end

-- Registration is replace-by-depth. Clearing the reverse proxy index as well as the floor bucket
-- is the load-bearing part: a rebuilt developer bay must not leave an old proxy authorized to send
-- gaze samples or let one of its delayed grabs resolve after replacement.
function AshamedLurkerService.clearDepth(depth: number)
	local floorRuntimes = runtimesByDepth[depth]
	if floorRuntimes == nil then
		return
	end
	runtimesByDepth[depth] = nil
	for _, runtime in floorRuntimes do
		invalidateRuntime(runtime)
	end
end

-- Lighting a floor removes its enemies without retiring the floor itself. Unlike `clearDepth`, this
-- also destroys the builder-owned proxies so every client's tagged local body disappears at once.
function AshamedLurkerService.despawnDepth(depth: number): number
	local floorRuntimes = runtimesByDepth[depth]
	if floorRuntimes == nil then
		return 0
	end
	AshamedLurkerService.clearDepth(depth)
	local removed = 0
	for _, runtime in floorRuntimes do
		if runtime.proxy.Parent ~= nil then
			runtime.proxy:Destroy()
			removed += 1
		end
	end
	return removed
end

function AshamedLurkerService.registerFloor(depth: number, inputs: { FloorBuilder.LurkerRuntime })
	AshamedLurkerService.clearDepth(depth)
	local floorRuntimes: { Runtime } = {}
	for _, input in inputs do
		-- A proxy can only belong to one runtime. This also handles a developer fixture being moved to
		-- another virtual depth without requiring its caller to know the old one.
		AshamedLurkerService.unregister(input.proxy)
		local runtime: Runtime = {
			proxy = input.proxy,
			sites = input.sites,
			siteIndex = 1,
			depth = depth,
			state = Protocol.states.dormant,
			stateEndsAt = 0,
			lastTriggerAt = -math.huge,
			generation = 0,
			gazeProgress = {},
			gazeSamples = {},
		}
		table.insert(floorRuntimes, runtime)
		runtimesByProxy[input.proxy] = runtime
	end
	runtimesByDepth[depth] = floorRuntimes
end

function AshamedLurkerService.tick(dt: number)
	if not Config.AshamedLurker.enabled then
		return
	end
	local config = Config.AshamedLurker
	local now = os.clock()

	-- Lifecycle first, so a creature that finished its retreat this frame cannot also be triggered.
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			if runtime.proxy.Parent == nil or now < runtime.stateEndsAt then
				continue
			end
			if runtime.state == Protocol.states.triggered then
				setState(runtime, Protocol.states.dormant, 0)
			elseif runtime.state == Protocol.states.ashamed then
				setState(runtime, Protocol.states.hidden, config.hiddenSeconds)
			elseif runtime.state == Protocol.states.hidden then
				relocate(runtime)
			end
		end
	end

	triggerAccumulator += dt
	local triggerStep = 1 / math.max(config.trigger.sampleHz, 1)
	if triggerAccumulator >= triggerStep then
		triggerAccumulator = 0
		for _, floorRuntimes in runtimesByDepth do
			for _, runtime in floorRuntimes do
				if runtime.proxy.Parent ~= nil then
					processTrigger(runtime)
				end
			end
		end
	end

	gazeAccumulator += dt
	local gazeStep = 1 / math.max(config.gaze.sampleHz, 1)
	if gazeAccumulator >= gazeStep then
		local elapsed = gazeAccumulator
		gazeAccumulator = 0
		for _, floorRuntimes in runtimesByDepth do
			for _, runtime in floorRuntimes do
				if runtime.proxy.Parent ~= nil then
					processGaze(runtime, elapsed)
				end
			end
		end
	end
end

function AshamedLurkerService.reset()
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			invalidateRuntime(runtime)
		end
	end
	table.clear(runtimesByDepth)
	table.clear(runtimesByProxy)
	triggerAccumulator = 0
	gazeAccumulator = 0
end

return AshamedLurkerService
