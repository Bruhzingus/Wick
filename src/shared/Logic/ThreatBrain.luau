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
	burningAtMax: boolean, -- current burn rate has reached this candle's live cap
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
		if
			player.playerId ~= target.playerId
			and player.targetable
			and (player.position - target.position).Magnitude <= radius
		then
			return true
		end
	end
	return false
end

local function ambushTarget(ctx: ThinkContext, territoryRadius: number, activationRadius: number): PlayerSnapshot?
	if ctx.state.targetPlayerId ~= nil then
		for _, player in ctx.players do
			if
				player.playerId == ctx.state.targetPlayerId
				and player.targetable
				and (player.position - ctx.state.homePosition).Magnitude <= territoryRadius
			then
				return player
			end
		end
	end

	local nearest: PlayerSnapshot? = nil
	local nearestDistance = math.huge
	for _, player in ctx.players do
		local distance = (player.position - ctx.state.homePosition).Magnitude
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

	if target.burningAtMax or teammateIsClose(target, ctx.players, profile.teammateRepelRadius) then
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
		-- Dark-hunter: too bright here means retreat...
		local lightHere = LightField.intensityAt(state.position, ctx.sources)
		if lightHere * sensitivity > behavior.repelLightThreshold then
			local source = LightField.strongestSourceNear(state.position, ctx.sources, def.detectionRadius, false)
			if source ~= nil then
				local away = state.position - flatten(state.position, source.position)
				local direction = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
				next_.mode = "Flee"
				next_.targetPosition = state.position + direction * def.detectionRadius
				return next_
			end
		end
		-- ...otherwise hunt the dimmest thing in range that's dark enough to take.
		local bestPlayer: PlayerSnapshot? = nil
		local bestDistance = math.huge
		for _, player in ctx.players do
			if not player.targetable then
				continue
			end
			local distance = (player.position - state.position).Magnitude
			if distance <= def.detectionRadius and player.lightLevel * sensitivity < behavior.huntLightThreshold then
				if distance < bestDistance then
					bestDistance = distance
					bestPlayer = player
				end
			end
		end
		if bestPlayer ~= nil then
			next_.mode = "Seek"
			next_.targetPosition = flatten(state.position, bestPlayer.position)
			next_.targetPlayerId = bestPlayer.playerId
			return next_
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
	if state.mode ~= "Wander" or target == nil or (target - state.position).Magnitude < 2 then
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
	local speed = def.speed * (if state.mode == "Wander" then ThreatsConfig.behavior.wanderSpeedFraction else 1)
	local offset = target - state.position
	local distance = offset.Magnitude
	if distance < 0.05 then
		return state.position
	end
	local stepped = state.position + offset.Unit * math.min(distance, speed * dt)
	local ambush = def.ambush
	if ambush ~= nil then
		local fromHome = stepped - state.homePosition
		if fromHome.Magnitude > ambush.territoryRadius then
			return state.homePosition + fromHome.Unit * ambush.territoryRadius
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
