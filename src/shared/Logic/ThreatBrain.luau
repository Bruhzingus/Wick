--!strict
-- Pure: threat decision-making. One brain for every threat row; the two categories differ only
-- in the SIGN of lightResponse (Drawn seek light sources, DarkHunters flee light and hunt the dim).
-- Adding a threat must never mean touching this file — only a Config/Threats row.

local Types = require(script.Parent.Parent.Types)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local LightField = require(script.Parent.LightField)

-- What the brain knows about one player when deciding.
export type PlayerSnapshot = {
	playerId: number,
	position: Vector3,
	lightLevel: number, -- light-field intensity at the player (includes their own flame)
	repelsAmbusher: boolean, -- a live Flare can force a ceiling ambusher off; the normal dial cannot
	targetable: boolean, -- alive, not finished, still on the board
}

export type ThinkContext = {
	def: Types.ThreatDef,
	state: Types.ThreatState,
	players: { PlayerSnapshot },
	sources: { Types.LightSource },
	trail: { Types.TrailPoint },
	now: number,
	rng: Random,
}

local ThreatBrain = {}

local function flatten(from: Vector3, to: Vector3): Vector3
	-- Threats move on the floor plane; never chase a target into the ceiling.
	return Vector3.new(to.X, from.Y, to.Z)
end

local function wanderTarget(ctx: ThinkContext): Vector3
	local behavior = ThreatsConfig.behavior
	local angle = ctx.rng:NextNumber() * 2 * math.pi
	local radius = if ctx.def.ambush ~= nil then ctx.def.ambush.patrolRadius else behavior.wanderRadius
	local distance = ctx.rng:NextNumber() * radius
	return ctx.state.homePosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function teammateIsClose(target: PlayerSnapshot, players: { PlayerSnapshot }, radius: number): boolean
	for _, player in players do
		local delta = player.position - target.position
		if
			player.playerId ~= target.playerId
			and player.targetable
			and Vector3.new(delta.X, 0, delta.Z).Magnitude <= radius
		then
			return true
		end
	end
	return false
end

local function ambushTarget(ctx: ThinkContext, territoryRadius: number, activationRadius: number): PlayerSnapshot?
	if ctx.state.targetPlayerId ~= nil then
		for _, player in ctx.players do
			local delta = player.position - ctx.state.homePosition
			if
				player.playerId == ctx.state.targetPlayerId
				and player.targetable
				and Vector3.new(delta.X, 0, delta.Z).Magnitude <= territoryRadius
			then
				return player
			end
		end
	end

	local nearest: PlayerSnapshot? = nil
	local nearestDistance = math.huge
	for _, player in ctx.players do
		local delta = player.position - ctx.state.homePosition
		local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
		if player.targetable and distance <= activationRadius and distance < nearestDistance then
			nearest = player
			nearestDistance = distance
		end
	end
	return nearest
end

local function thinkAmbusher(ctx: ThinkContext, next_: Types.ThreatState): Types.ThreatState
	local profile = ctx.def.ambush :: Types.AmbushProfile
	if ctx.now < ctx.state.retreatUntil then
		next_.mode = "Flee"
		next_.targetPosition = ctx.state.targetPosition or ctx.state.homePosition
		next_.retreatUntil = ctx.state.retreatUntil
		return next_
	end

	local target = ambushTarget(ctx, profile.territoryRadius, profile.activationRadius)
	if target == nil then
		next_.mode = "Wander"
		next_.targetPosition = if ctx.state.mode == "Wander" and ctx.state.targetPosition ~= nil
			then ctx.state.targetPosition
			else wanderTarget(ctx)
		return next_
	end

	if target.repelsAmbusher or teammateIsClose(target, ctx.players, profile.teammateRepelRadius) then
		local away = ctx.state.position - flatten(ctx.state.position, target.position)
		local direction = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
		next_.mode = "Flee"
		next_.targetPosition = ctx.state.homePosition + direction * profile.retreatDistance
		next_.retreatUntil = ctx.now + profile.retreatSeconds
		return next_
	end

	next_.mode = "Seek"
	next_.targetPlayerId = target.playerId
	next_.targetPosition = flatten(ctx.state.position, target.position)
	return next_
end

local function playerCandidates(ctx: ThinkContext, sensitivity: number): (PlayerSnapshot?, PlayerSnapshot?)
	local dim: PlayerSnapshot? = nil
	local dimDistance = math.huge
	local lit: PlayerSnapshot? = nil
	local litDistance = math.huge
	for _, player in ctx.players do
		local distance = (player.position - ctx.state.position).Magnitude
		if player.targetable and distance <= ctx.def.detectionRadius then
			if player.lightLevel * sensitivity < ThreatsConfig.behavior.huntLightThreshold then
				if distance < dimDistance then
					dim = player
					dimDistance = distance
				end
			elseif distance < litDistance then
				lit = player
				litDistance = distance
			end
		end
	end
	return dim, lit
end

local function thinkDarkHunter(ctx: ThinkContext, next_: Types.ThreatState, sensitivity: number): Types.ThreatState?
	local state = ctx.state
	local behavior = ThreatsConfig.behavior

	-- Once driven off, do not instantly reacquire when the Flare ends or moves away.
	if ctx.now < state.retreatUntil then
		next_.mode = "Flee"
		next_.targetPosition = state.targetPosition or state.homePosition
		next_.retreatUntil = state.retreatUntil
		return next_
	end

	local source = LightField.strongestRetreatSourceAt(state.position, ctx.sources)
	if
		source ~= nil
		and LightField.contributionOf(source, state.position) * sensitivity > behavior.repelLightThreshold
	then
		-- Panic light has a direction even when its centre sits beyond the hunter's ordinary
		-- player-detection radius. Ordinary dial light still controls hunt/stalk reads, never flee.
		if source ~= nil then
			local away = state.position - flatten(state.position, source.position)
			local direction = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
			next_.mode = "Flee"
			next_.targetPosition = state.position + direction * ctx.def.detectionRadius
			next_.retreatUntil = ctx.now + ctx.def.detectionRadius / ctx.def.speed + behavior.darkHunterBlindSeconds
			return next_
		end
	end

	local dim, lit = playerCandidates(ctx, sensitivity)
	if dim ~= nil then
		next_.mode = "Seek"
		next_.targetPosition = flatten(state.position, dim.position)
		next_.targetPlayerId = dim.playerId
		return next_
	end
	if lit == nil then
		return nil
	end

	-- Medium light is respected, not ignored. Move toward a point on the safe-radius ring:
	-- back away when too close, edge nearer when far, and stop once the spacing is reached.
	local flatPlayer = flatten(state.position, lit.position)
	local away = state.position - flatPlayer
	local direction = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
	next_.mode = "Stalk"
	next_.targetPosition = flatPlayer + direction * behavior.darkHunterKeepDistance
	next_.targetPlayerId = lit.playerId
	return next_
end

-- Decide what this threat does next. Returns a NEW ThreatState (pure).
function ThreatBrain.think(ctx: ThinkContext): Types.ThreatState
	local def, state = ctx.def, ctx.state
	local behavior = ThreatsConfig.behavior
	local sensitivity = math.abs(def.lightResponse)
	local next_: Types.ThreatState = {
		id = state.id,
		category = state.category,
		position = state.position,
		homePosition = state.homePosition,
		mode = "Wander",
		targetPosition = state.targetPosition,
		targetPlayerId = nil,
		nextThinkAt = ctx.now + behavior.repathIntervalSeconds,
		retreatUntil = state.retreatUntil,
	}
	if def.ambush ~= nil then
		return thinkAmbusher(ctx, next_)
	end

	if def.lightResponse > 0 then
		-- Drawn: head for the strongest attractor in range (flame, flare, decoy — brightest wins,
		-- which is exactly how decoys and flares divert them).
		local source = LightField.strongestSourceNear(state.position, ctx.sources, def.detectionRadius, true)
		if source ~= nil then
			next_.mode = "Seek"
			next_.targetPosition = flatten(state.position, source.position)
			next_.targetPlayerId = if source.kind == "Flame" then source.ownerId else nil
			return next_
		end
	else
		local darkHunterDecision = thinkDarkHunter(ctx, next_, sensitivity)
		if darkHunterDecision ~= nil then
			return darkHunterDecision
		end
		-- No prey sensed: follow the freshest drip trail in range (DESIGN §8 — the trail exposes you).
		local bestPoint: Types.TrailPoint? = nil
		for _, point in ctx.trail do
			if (point.position - state.position).Magnitude <= def.detectionRadius then
				if bestPoint == nil or point.createdAt > bestPoint.createdAt then
					bestPoint = point
				end
			end
		end
		if bestPoint ~= nil then
			next_.mode = "Seek"
			next_.targetPosition = flatten(state.position, bestPoint.position)
			return next_
		end
	end

	-- Nothing sensed: drift. Keep the previous wander target until reached so paths look intentional.
	local target = state.targetPosition
	if
		state.mode ~= "Wander"
		or target == nil
		or (target - state.position).Magnitude < ThreatsConfig.behavior.wanderArrivalToleranceStuds
	then
		next_.targetPosition = wanderTarget(ctx)
	end
	return next_
end

-- Advance position toward the current target. Returns the new position (pure; adapter moves the Part).
function ThreatBrain.step(state: Types.ThreatState, def: Types.ThreatDef, dt: number): Vector3
	local target = state.targetPosition
	if target == nil then
		return state.position
	end
	local speedFraction = if state.mode == "Wander"
		then ThreatsConfig.behavior.wanderSpeedFraction
		elseif state.mode == "Stalk" then ThreatsConfig.behavior.stalkSpeedFraction
		else 1
	local speed = def.speed * speedFraction
	local offset = target - state.position
	local distance = offset.Magnitude
	if distance < 0.05 then
		return state.position
	end
	local stepped = state.position + offset.Unit * math.min(distance, speed * dt)
	local ambush = def.ambush
	if ambush ~= nil then
		local fromHome = stepped - state.homePosition
		local horizontalFromHome = Vector3.new(fromHome.X, 0, fromHome.Z)
		if horizontalFromHome.Magnitude > ambush.territoryRadius then
			local clamped = horizontalFromHome.Unit * ambush.territoryRadius
			return Vector3.new(state.homePosition.X + clamped.X, stepped.Y, state.homePosition.Z + clamped.Z)
		end
	end
	return stepped
end

-- Pure staged-contact rule used by territorial threats. The adapter owns timestamps/Instances;
-- this decides only whether the configured attack count has reached a snuff.
function ThreatBrain.advanceContactHits(currentHits: number, hitsToSnuff: number): (number, boolean)
	local nextHits = currentHits + 1
	return nextHits, nextHits >= math.max(hitsToSnuff, 1)
end

return ThreatBrain
