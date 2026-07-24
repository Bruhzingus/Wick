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
	local distance = ctx.rng:NextNumber() * behavior.wanderRadius
	return ctx.state.homePosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
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
	}

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
	return state.position + offset.Unit * math.min(distance, speed * dt)
end

return ThreatBrain
