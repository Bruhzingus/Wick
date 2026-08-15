--!strict
-- Server authority for burning Moss vegetation. A tagged cluster of dry growth catches when a
-- qualifying flame is held against it, then carries fire along its OWN planned connectivity graph
-- until it burns out. While it burns it is a real light in the shared light field and a real heat
-- source that costs Living Wax.
--
-- ENTIRELY SERVER-COMPUTED, and structurally so: there is no remote, no request, and no client input
-- anywhere in this file. Ignition is derived from positions and flame state the server already owns
-- (PlayerState, ToolService), which is why "duplicate request resistance" is not a check here — a
-- client cannot ask for anything, so there is nothing to replay. Every rule it applies lives in
-- Logic/MossFireRules, so what a cold test asserts and what a live server charges are one function.
--
-- FOUR THINGS IT MAY NEVER DO, all enforced below rather than by convention:
--   * light anything that is not a planned cluster node — fire cannot reach a wet wall, unrelated
--     dressing, or another cluster, because spread only ever walks the planned edge list;
--   * behave like a Flare — its light enters the shared list as ordinary environmental light with
--     `forcesDarkHunterRetreat = false`, so it attracts Drawn and affects ordinary hunt/stalk logic
--     and can never force the panic retreat only a real Flare causes;
--   * introduce a second resource — heat is spent Living Wax under one centralized reason;
--   * outlive its floor — everything is torn down on floor cleanup and on run reset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local MossFireRules = require(ReplicatedStorage.Shared.Logic.MossFireRules)
local PlayerState = require(script.Parent.PlayerState)
local FloorBuilder = require(script.Parent.FloorBuilder)
local ToolService = require(script.Parent.ToolService)
local WaxService = require(script.Parent.WaxService)
local Telemetry = require(script.Parent.Telemetry)

local MossFireService = {}

type NodeState = {
	part: BasePart,
	position: Vector3,
	kindId: string,
	alight: boolean,
	spent: boolean,
	ignitedAt: number,
	duration: number,
	nextSpreadAt: number,
	fire: Fire?,
}

type Runtime = {
	model: Model,
	depth: number,
	position: Vector3,
	obstruction: BasePart?,
	nodes: { NodeState },
	edges: { { a: number, b: number } },
	-- 0..1 ignition progress. Rises while a qualifying source is in range and decays once every
	-- source has left, so a half-lit cluster is not a trap left armed for whoever comes next.
	progress: number,
	caught: boolean,
	finished: boolean,
}

local runtimesByDepth: { [number]: { Runtime } } = {}

local function isEnabled(): boolean
	return Config.MossFire.enabled
end

-- How many clusters are alight anywhere on the expedition right now. The per-floor cap is applied
-- against this rather than against a per-floor tally, because a party spread across two floors can
-- have fires on both and the cost is paid by one server either way.
local function activeCount(): number
	local count = 0
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			if runtime.caught and not runtime.finished then
				count += 1
			end
		end
	end
	return count
end

local function igniteNode(runtime: Runtime, nodeIndex: number, now: number, rng: Random)
	local node = runtime.nodes[nodeIndex]
	if node == nil or node.alight or node.spent then
		return
	end
	local kind = MossFireRules.resolveKind(node.kindId)
	node.alight = true
	node.ignitedAt = now
	node.duration = MossFireRules.burnSeconds(kind, rng:NextNumber())
	node.nextSpreadAt = now + MossFireRules.spreadInterval(kind)

	-- One Fire per node, created once when it catches and destroyed when it dies. Never per frame:
	-- the whole point of a bounded node count is that the particle cost of a burning cluster is known
	-- before it starts.
	local fire = Instance.new("Fire")
	fire.Heat = 8
	fire.Size = 4
	fire.Color = Config.MossFire.visual.emberPalette[1]
	fire.SecondaryColor = Config.MossFire.visual.emberPalette[#Config.MossFire.visual.emberPalette]
	fire.Parent = node.part
	node.fire = fire
end

local function extinguishNode(node: NodeState)
	node.alight = false
	node.spent = true
	if node.fire ~= nil then
		node.fire:Destroy()
		node.fire = nil
	end
	node.part.Transparency = 1
	node.part.CanCollide = false
end

-- The cluster's own ignition sources this tick: every player flame in range that qualifies, plus
-- every burning Decoy. Returns the summed progress rate, whether a Flare is among them, and the
-- position of the nearest source (so the fire starts where it was lit rather than at node 1).
local function gatherIgnition(runtime: Runtime, now: number): (number, boolean, Vector3?)
	local range = MossFireRules.ignitionRange()
	local total = 0
	local flare = false
	local nearest: Vector3? = nil
	local nearestDistance = math.huge

	local function consider(position: Vector3, rate: number)
		local distance = (position - runtime.position).Magnitude
		if distance > range then
			return
		end
		total += rate
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = position
		end
	end

	for _, state in PlayerState.all() do
		if not state.alive or state.finished then
			continue
		end
		-- A FLARE IS INSTANT, and it is checked before the dial: a Flare is a burst of panic light and
		-- against dry growth there is no meaningful "how long".
		if state.flareEndsAt > now then
			local distance = (state.position - runtime.position).Magnitude
			if distance <= range then
				flare = true
				if distance < nearestDistance then
					nearestDistance = distance
					nearest = state.position
				end
			end
		end
		-- SNUFF contributes nothing because an unlit candle is not a flame, and CUP contributes
		-- exactly zero however high the dial underneath it reads — both fall out of this one call.
		local rate = MossFireRules.flameProgressPerSecond(
			state.isLit,
			state.isCupping,
			state.burnRate,
			state.modifiers.maxBurnRate
		)
		if rate > 0 then
			consider(state.position, rate)
		end
	end

	for _, source in ToolService.decoySources() do
		consider(source.position, MossFireRules.decoyProgressPerSecond())
	end

	return total, flare, nearest
end

local function nearestNodeTo(runtime: Runtime, position: Vector3?): number
	if position == nil then
		return 1
	end
	local bestIndex, bestDistance = 1, math.huge
	for index, node in runtime.nodes do
		if node.spent then
			continue
		end
		local distance = (node.position - (position :: Vector3)).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestIndex = index
		end
	end
	return bestIndex
end

-- Heat, charged per player per cluster. Living Wax under one centralized reason and no second meter.
local function applyHeat(runtime: Runtime, dt: number)
	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished then
			continue
		end
		local perCluster: { number } = {}
		for _, node in runtime.nodes do
			if node.alight then
				table.insert(perCluster, (node.position - state.position).Magnitude)
			end
		end
		if #perCluster == 0 then
			continue
		end
		local rate = MossFireRules.clusterHeatPerSecond(perCluster)
		if rate <= 0 then
			continue
		end
		WaxService.drainExternal(
			playerId,
			rate * dt,
			MossFireRules.waxReason() :: Types.WaxSource,
			"The fire burned through the last of your wax.",
			-- Standing in heat, not being struck: a Candle Sleeve is spent by the second here.
			{ kind = "Continuous", seconds = dt },
			"MossFire"
		)
	end
end

function MossFireService.registerFloor(depth: number, inputs: { FloorBuilder.MossFireRuntime })
	if not isEnabled() then
		return
	end
	local floorRuntimes: { Runtime } = {}
	for _, input in inputs do
		local nodes: { NodeState } = {}
		for _, node in input.nodes do
			table.insert(nodes, {
				part = node.part,
				position = node.part.Position,
				kindId = node.kindId,
				alight = false,
				spent = false,
				ignitedAt = 0,
				duration = 0,
				nextSpreadAt = 0,
				fire = nil,
			})
		end
		table.insert(floorRuntimes, {
			model = input.model,
			depth = input.depth,
			position = input.position,
			obstruction = input.obstruction,
			nodes = nodes,
			edges = input.edges,
			progress = 0,
			caught = false,
			finished = false,
		})
	end
	runtimesByDepth[depth] = floorRuntimes
end

function MossFireService.tick(dt: number)
	if not isEnabled() then
		return
	end
	local now = os.clock()
	local maxActive = MossFireRules.maxActivePerFloor()

	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			if runtime.finished or runtime.model.Parent == nil then
				continue
			end

			if not runtime.caught then
				local rate, flare, source = gatherIgnition(runtime, now)
				runtime.progress = MossFireRules.stepIgnition(runtime.progress, dt, rate, flare)
				if MossFireRules.hasCaught(runtime.progress) then
					-- AT THE CAP THE CLUSTER WAITS RATHER THAN LOSING ITS PROGRESS. Refusing outright
					-- would make a player's deliberate, expensive act silently do nothing; holding it
					-- means the fire starts the moment another one dies, and the floor's particle,
					-- light and audio cost stays bounded either way.
					if activeCount() < maxActive then
						runtime.caught = true
						igniteNode(
							runtime,
							nearestNodeTo(runtime, source),
							now,
							Random.new(runtime.depth * 7919 + #runtime.nodes)
						)
						-- The obstruction stops obstructing the instant the cluster catches: the player
						-- has committed and paid for it, and making them wait out the burn to walk
						-- through would turn a decision into a queue.
						local obstruction = runtime.obstruction
						if obstruction ~= nil then
							obstruction.CanCollide = false
							obstruction.Transparency = 1
						end
						Telemetry.event("moss_fire_ignited", nil, { depth = runtime.depth, flare = flare })
					end
				end
				continue
			end

			-- Alight. From here it needs nobody present: fire finishes the cluster on its own.
			local rng = Random.new(math.floor(now * 1000) % 2_147_483_647 + runtime.depth)
			local anyAlight = false
			for index, node in runtime.nodes do
				if not node.alight then
					continue
				end
				anyAlight = true
				if now - node.ignitedAt >= node.duration then
					extinguishNode(node)
					continue
				end
				if now < node.nextSpreadAt then
					continue
				end
				local kind = MossFireRules.resolveKind(node.kindId)
				node.nextSpreadAt = now + MossFireRules.spreadInterval(kind)
				-- CONNECTED NODES ONLY. This is the single place fire chooses where to go, and it can
				-- only ever read the planned edge list — which is why fire can never reach a wet wall,
				-- unrelated dressing, or a second cluster across the room.
				for _, neighbour in MossFireRules.neighbours(runtime.edges, index) do
					igniteNode(runtime, neighbour, now, rng)
				end
			end

			applyHeat(runtime, dt)

			if not anyAlight then
				runtime.finished = true
				runtime.model:Destroy()
				Telemetry.event("moss_fire_burned_out", nil, { depth = runtime.depth })
			end
		end
	end
end

-- Burning vegetation as ORDINARY environmental light, merged into the one shared list every threat
-- reads (server/LightSources). It attracts Drawn exactly as a candle does and affects ordinary
-- dark-hunter hunt and stalk logic exactly as a candle does; `forcesDarkHunterRetreat` is false
-- because that is the property only a real Flare has, and a fire that could clear a room of
-- dark-hunters would be a better Flare than the Flare.
function MossFireService.sources(): { Types.LightSource }
	local sources: { Types.LightSource } = {}
	if not isEnabled() then
		return sources
	end
	local now = os.clock()
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			if not runtime.caught or runtime.finished then
				continue
			end
			local total = Vector3.zero
			local count = 0
			local brightest = 0
			for _, node in runtime.nodes do
				if not node.alight then
					continue
				end
				count += 1
				total += node.position
				brightest = math.max(brightest, MossFireRules.lightFraction(now - node.ignitedAt, node.duration))
			end
			if count == 0 or brightest <= 0 then
				continue
			end
			table.insert(sources, {
				kind = "Decoy" :: Types.LightSourceKind,
				position = total / count,
				intensity = MossFireRules.lightIntensity(brightest),
				range = MossFireRules.lightRange(brightest),
				attractsDrawn = true,
				repelsDarkHunters = true,
				forcesDarkHunterRetreat = false,
				ownerId = nil,
			})
		end
	end
	return sources
end

local function destroyRuntimeFires(floorRuntimes: { Runtime })
	for _, runtime in floorRuntimes do
		for _, node in runtime.nodes do
			if node.fire ~= nil then
				node.fire:Destroy()
				node.fire = nil
			end
		end
	end
end

function MossFireService.clearDepth(depth: number)
	local floorRuntimes = runtimesByDepth[depth]
	if floorRuntimes == nil then
		return
	end
	runtimesByDepth[depth] = nil
	destroyRuntimeFires(floorRuntimes)
end

function MossFireService.reset()
	for _, floorRuntimes in runtimesByDepth do
		destroyRuntimeFires(floorRuntimes)
	end
	table.clear(runtimesByDepth)
end

return MossFireService
