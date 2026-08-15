--!strict
-- Pure: threat decision-making. One brain for every threat row; the two categories differ only
-- in the SIGN of lightResponse (Drawn seek light sources, DarkHunters flee light and hunt the dim).
-- Adding a threat must never mean touching this file — only a Config/Threats row.

local Types = require(script.Parent.Parent.Types)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local LightField = require(script.Parent.LightField)
local SoundField = require(script.Parent.SoundField)
-- One-directional: ThreatRules reads only Types, so asking it to normalise a row's roof profile costs
-- no cycle.
local ThreatRules = require(script.Parent.ThreatRules)

-- What the brain knows about one player when deciding.
export type PlayerSnapshot = {
	playerId: number,
	position: Vector3,
	-- Server-observed horizontal body facing. Optional keeps synthetic/test snapshots conservative:
	-- without a trustworthy direction, a crawler holds its ordinary gap instead of claiming it is unseen.
	lookDirection: Vector3?,
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
	-- Live noise events this threat is allowed to perceive. Already filtered by the adapter for
	-- protected rooms, exactly like sources and trail. Empty for every deaf row.
	noises: { Types.NoiseEvent },
	now: number,
	rng: Random,
}

local ThreatBrain = {}

local function flatten(from: Vector3, to: Vector3): Vector3
	-- Threats move on the floor plane; never chase a target into the ceiling.
	return Vector3.new(to.X, from.Y, to.Z)
end

-- The floor-walking drift: one random point, held until reached (see `think`), which is what makes a
-- crawler's path across a room read as deliberate. Roof-bound rows do NOT use this — they fly a
-- circuit instead (`patrolTarget`), because a random point plus an arrival check is a body that stops
-- moving whenever it happens to reach one.
local function wanderTarget(ctx: ThinkContext): Vector3
	local behavior = ThreatsConfig.behavior
	local angle = ctx.rng:NextNumber() * 2 * math.pi
	local distance = ctx.rng:NextNumber() * behavior.wanderRadius
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

-- A stable per-body phase, so two flies sharing a corpse never circle in unison and a given creature
-- keeps flying the same circuit in the same direction for its whole life. Derived from the anchor it
-- was given rather than stored, which keeps the whole patrol pure and costs one multiply.
local function patrolPhase(home: Vector3): number
	return (home.X * 12.9898 + home.Z * 78.233) % (2 * math.pi)
end

-- WHERE A ROOF-BOUND BODY IS FLYING WHEN NOTHING HAS ITS ATTENTION.
--
-- This used to be `wanderTarget`: one random point in the patrol disc, held until reached and then
-- never re-rolled, because the ambusher's Wander branch (unlike the generic one below) had no arrival
-- check. The observable result was a creature that flew a few studs on spawn and then sat on one
-- stone for the entire floor — findable once and safe forever after.
--
-- It is now a genuine circuit: a slow orbit of the patrol radius, breathing in and out, around a
-- centre that itself drifts through the room left between `patrolRadius` and `territoryRadius`. Every
-- term is a function of `now`, so the target moves every think and the body is always travelling.
-- The drift is bounded by construction, which is what keeps the whole path inside the ceiling disc
-- FloorBuilder reserved from roof dressing.
local function patrolTarget(ctx: ThinkContext, roof: ThreatRules.RoofProfile): Vector3
	local phase = patrolPhase(ctx.state.homePosition)
	-- The sign of the phase term decides which way round it flies; nothing else depends on it.
	local direction = if phase > math.pi then -1 else 1
	local breath = math.clamp(roof.patrolRadiusBreath, 0, 1)

	local angle = phase + ctx.now * roof.patrolAngularSpeed * direction
	-- The circuit tightens and opens on its own slow cycle, so it is an orbit rather than a turntable.
	local breathing = 0.5 + 0.5 * math.sin(ctx.now * roof.patrolAngularSpeed * 0.37 + phase)
	local radius = roof.patrolRadius * (1 - breath + breath * breathing)
	-- Never past the territory: the slack the centre may use is exactly what the orbit does not.
	local driftRadius = math.max(0, roof.territoryRadius - roof.patrolRadius)
		* math.clamp(roof.patrolDriftFraction, 0, 1)
	local driftAngle = phase * 2 + ctx.now * roof.patrolDriftSpeed
	local center = ctx.state.homePosition
		+ Vector3.new(math.cos(driftAngle) * driftRadius, 0, math.sin(driftAngle) * driftRadius)
	return center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- What this body can hear right now, or nil for a deaf row — which is what every caller wants: a row
-- with no ears is never roused and never investigates.
local function currentlyAudible(ctx: ThinkContext): SoundField.Audible?
	local hearing = ctx.def.hearing
	if hearing == nil then
		return nil
	end
	return SoundField.audibleFor(ctx.state.position, ctx.noises, ctx.now, hearing)
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

-- THE CEILING AMBUSHER. Holds a patch, circles it, and commits to whoever walks underneath.
--
-- THE THREE WAYS OUT OF ITS ATTENTION ARE THE ONLY THREE, and each is a branch below: burn a FLARE,
-- stand next to a teammate, or get far enough away for long enough. Ordinary brightness is not one of
-- them and never has been (`lightResponse` is -1 and nothing here reads it), which is what makes this
-- creature a positioning problem instead of a dial problem.
local function thinkAmbusher(ctx: ThinkContext, next_: Types.ThreatState): Types.ThreatState
	local profile = ctx.def.ambush :: Types.AmbushProfile
	local roof = ThreatRules.roofProfile(ctx.def) :: ThreatRules.RoofProfile
	if ctx.now < ctx.state.retreatUntil then
		next_.mode = "Flee"
		next_.targetPosition = ctx.state.targetPosition or ctx.state.homePosition
		next_.retreatUntil = ctx.state.retreatUntil
		return next_
	end

	-- THE CLOCK RUNNING OUT IS A DECISION, not a fall-through. Without this branch a victim who was
	-- still standing underneath at the deadline would simply be re-acquired on the same think, and the
	-- harassment would have no end a player could survive their way to. It goes home and ignores prey
	-- for the recovery window, whoever is under it.
	if ctx.state.pursuitUntil > 0 and ctx.state.pursuitUntil <= ctx.now then
		next_.mode = "Flee"
		next_.targetPosition = ctx.state.homePosition
		next_.retreatUntil = ctx.now + profile.pursuitRecoverySeconds
		return next_
	end

	-- A live commitment reaches FURTHER than the patch. That single substitution is what stopped this
	-- creature giving up the moment its victim stepped off the tile it was hanging over: it keeps the
	-- player it already chose out to `pursuitRadius`, and only ordinary acquisition is still bounded
	-- by the territory.
	local committed = ctx.state.pursuitUntil > ctx.now
	local reach = if committed then profile.pursuitRadius else profile.territoryRadius
	-- Something audible under a fly widens the disc it will come down for. The rouse costs no state:
	-- noise events decay on their own, so the widened radius lasts exactly as long as the sound does.
	local heard = currentlyAudible(ctx)
	local roused = profile.rousedLoudness > 0 and heard ~= nil and heard.loudness >= profile.rousedLoudness
	local activation = profile.activationRadius * (if roused then profile.rousedActivationMultiplier else 1)
	local target = ambushTarget(ctx, reach, activation)
	if target == nil then
		-- Nobody in reach. A commitment that has just lost its victim ends here rather than surviving
		-- into the next one: `pursuitUntil` is left at zero by the state template below.
		if committed then
			next_.mode = "Flee"
			next_.targetPosition = ctx.state.homePosition
			next_.retreatUntil = ctx.now + profile.pursuitRecoverySeconds
			return next_
		end
		-- Curiosity, for a row with ears. It moves its own patrol over to the near side of the noise
		-- and never past the territory — being heard REPOSITIONS a fly on its patch, it does not lead
		-- one out of the room, and no branch here can ever set `targetPlayerId`.
		local hearing = ctx.def.hearing
		if hearing ~= nil and heard ~= nil then
			local fromHome = flatten(ctx.state.homePosition, heard.position) - ctx.state.homePosition
			local clamped = if fromHome.Magnitude > roof.territoryRadius
				then fromHome.Unit * roof.territoryRadius
				else fromHome
			next_.mode = "Investigate"
			next_.targetPosition = ctx.state.homePosition + clamped
			next_.investigateUntil = ctx.now + hearing.investigateSeconds
			next_.investigateLoudness = heard.loudness
			return next_
		end
		next_.mode = "Wander"
		next_.targetPosition = patrolTarget(ctx, roof)
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

	-- The clock runs from the FIRST think that acquired this victim and is not extended by anything it
	-- does afterwards, so the harassment has a fixed, learnable length: survive it and the fly breaks
	-- off and goes home, whatever it was in the middle of.
	if committed and ctx.state.targetPlayerId == target.playerId then
		next_.pursuitUntil = ctx.state.pursuitUntil
	else
		next_.pursuitUntil = ctx.now + profile.pursuitSeconds
	end

	next_.mode = "Seek"
	next_.targetPlayerId = target.playerId
	next_.targetPosition = flatten(ctx.state.position, target.position)
	return next_
end

-- CEILING STRIKER. A roof-bound row that never approaches and never contacts anybody: it holds its
-- patch and, when a candle crosses beneath it, commits to bringing down a formation that is already
-- hanging there. The server adapter owns the actual trigger (it is the only thing that can see the
-- floor's hazards); this decides only whether the creature has a reason to act.
--
-- IT NEVER MOVES TOWARD A PLAYER. `targetPosition` stays on its own territory in every branch, so
-- "Seek" here means "watching somebody below", not "closing". That distinction is the whole creature.
local function thinkCeilingStriker(ctx: ThinkContext, next_: Types.ThreatState): Types.ThreatState
	local profile = ctx.def.ceilingStrike :: Types.CeilingStrikeProfile
	next_.strikeReadyAt = ctx.state.strikeReadyAt

	-- A flare drives it off its patch like any other dark-hunter. The one counter to a creature that
	-- weaponises the ceiling is the same tool that answers everything else in the dark.
	if ctx.now < ctx.state.retreatUntil then
		next_.mode = "Flee"
		next_.targetPosition = ctx.state.targetPosition or ctx.state.homePosition
		next_.retreatUntil = ctx.state.retreatUntil
		return next_
	end

	local target = ambushTarget(ctx, profile.territoryRadius, profile.activationRadius)
	if target == nil then
		next_.mode = "Wander"
		next_.targetPosition = patrolTarget(ctx, ThreatRules.roofProfile(ctx.def) :: ThreatRules.RoofProfile)
		return next_
	end

	if target.repelsAmbusher then
		local away = ctx.state.position - flatten(ctx.state.position, target.position)
		local direction = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
		next_.mode = "Flee"
		next_.targetPosition = ctx.state.homePosition + direction * profile.retreatDistance
		next_.retreatUntil = ctx.now + profile.retreatSeconds
		return next_
	end

	-- Watching somebody it could act on. Note the target position: its OWN patch, not the player's.
	next_.mode = "Seek"
	next_.targetPlayerId = target.playerId
	next_.targetPosition = ctx.state.homePosition
	return next_
end

-- INTERCEPTION. Where a player is GOING, not where they are.
--
-- THREE THINGS MAKE THIS FAIR, and all three are visible from the player's side:
--
--   1. It commits. Once a prediction is made it is honoured for `commitmentSeconds` and cannot be
--      re-aimed, so turning around or taking another route always works — the creature is walking to
--      ground you have already had the chance to see it choose.
--   2. It predicts off the player's own OBSERVED FACING and nothing else — no velocity, no history,
--      no destination. A snapshot with no usable facing produces no prediction at all and the row
--      falls through to an ordinary chase. Facing is a deliberately blunt signal: it is exactly what
--      the player is broadcasting, so being read by it is never a surprise. (A stationary player
--      facing a doorway will be predicted toward it, which is correct — they are telegraphing.)
--   3. It aims ONE room ahead and no further. Two would be indistinguishable from knowing the
--      destination, which is a different and much worse creature.
--
-- The projected point is a POSITION, not a room id: the server's own room navigation walks the body
-- there through real doorways, so the creature genuinely takes a different route rather than teleporting
-- into the correct room.
local function interceptTarget(ctx: ThinkContext, target: PlayerSnapshot, next_: Types.ThreatState): Vector3?
	local profile = ctx.def.intercept :: Types.InterceptProfile

	-- An unexpired commitment is kept, whatever the player has done since. This is the branch that
	-- makes the creature beatable, so it comes first.
	local committed = ctx.state.interceptPosition
	if committed ~= nil and ctx.now < ctx.state.interceptUntil then
		next_.interceptUntil = ctx.state.interceptUntil
		next_.interceptPosition = committed
		return committed
	end

	local distance = (target.position - ctx.state.position).Magnitude
	if distance > profile.maximumPredictionDistance then
		return nil
	end

	local heading = target.lookDirection
	if heading == nil then
		return nil
	end
	local flat = Vector3.new(heading.X, 0, heading.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end

	local ahead = math.max(profile.projectionStuds, 1) * math.max(1, profile.roomsAhead)
	local projected = flatten(ctx.state.position, target.position + flat.Unit * ahead)
	next_.interceptUntil = ctx.now + profile.commitmentSeconds
	next_.interceptPosition = projected
	return projected
end

-- Curiosity. Ranks BELOW every real prey read and ABOVE a cold drip trail: something audible right
-- now is more compelling than evidence somebody passed through a while ago, but neither competes
-- with actually sensing a candle. Returns nil for deaf rows, which is every Drawn row, so nothing
-- about the moth-vs-hunter read changes. A territorial row hears through `thinkAmbusher` instead:
-- same field, same threshold, but the answer is a place on its own patch rather than a destination.
--
-- Note what this does NOT do: it never sets targetPlayerId, never shortens a retreat, and never
-- raises speed above `investigateSpeedFraction`. Being heard moves a threat to a PLACE.
local function thinkInvestigate(ctx: ThinkContext, next_: Types.ThreatState): Types.ThreatState?
	local hearing = ctx.def.hearing
	if hearing == nil then
		return nil
	end

	local heard = SoundField.audibleFor(ctx.state.position, ctx.noises, ctx.now, hearing)
	-- A noise at least as loud as the one it already committed to takes over. Requiring "at least as
	-- loud" is what stops a decaying tail from dragging it back and forth between two points.
	if heard ~= nil and heard.loudness >= ctx.state.investigateLoudness then
		next_.mode = "Investigate"
		next_.targetPosition = flatten(ctx.state.position, heard.position)
		next_.investigateUntil = ctx.now + hearing.investigateSeconds
		next_.investigateLoudness = heard.loudness
		return next_
	end

	-- Nothing new worth hearing. Keep walking to the last one until it arrives or its commitment
	-- lapses, so a threat that was lured does not simply stop the moment the cave goes quiet.
	local committed = ctx.state.targetPosition
	if ctx.state.mode == "Investigate" and ctx.now < ctx.state.investigateUntil and committed ~= nil then
		local arrived = (committed - ctx.state.position).Magnitude
			<= ThreatsConfig.behavior.investigateArrivalToleranceStuds
		if not arrived then
			next_.mode = "Investigate"
			next_.targetPosition = committed
			next_.investigateUntil = ctx.state.investigateUntil
			next_.investigateLoudness = ctx.state.investigateLoudness
			return next_
		end
	end
	return nil
end

-- THE ALARM. An explosive seam has gone up somewhere on this floor and every body on it — deaf or
-- otherwise, moth or hunter, on the ground or on the roof — is walking to the hole it left.
--
-- WHY IT IS CHECKED BEFORE EVERY OTHER BRANCH, including prey. This is the one authored moment in the
-- game where the cave stops reacting to the player and reacts to the floor instead, and the whole
-- point of the row that produces it (Config/Mining.explosive) is that it MOVES THINGS: a player who
-- lights one is buying a violent, temporary rearrangement of where everything is, whose value is
-- entirely in being able to predict it. A threat that ignored the summons because it happened to have
-- line of sight on somebody would make that prediction a lie, and a mechanic you cannot predict is
-- just a punishment.
--
-- IT ENDS ON ARRIVAL, not only on the clock, so the crowd disperses into ordinary behaviour from the
-- blast site rather than standing in it until the timer runs out. Both exits fall through to the
-- normal decision on the next think, because `alarmUntil` is only ever carried forward by this branch.
--
-- Nothing here targets a player, and the walk uses the ordinary Investigate speed: being summoned
-- moves a threat to a PLACE, exactly like being lured by noise. The difference is only who can hear.
local function thinkAlarm(ctx: ThinkContext, next_: Types.ThreatState): Types.ThreatState?
	local target = ctx.state.alarmPosition
	if target == nil or ctx.now >= ctx.state.alarmUntil then
		return nil
	end
	local destination = flatten(ctx.state.position, target)
	if (destination - ctx.state.position).Magnitude <= ThreatsConfig.behavior.investigateArrivalToleranceStuds then
		return nil
	end
	next_.mode = "Investigate"
	next_.targetPosition = destination
	next_.alarmUntil = ctx.state.alarmUntil
	next_.alarmPosition = target
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
		next_.targetPlayerId = dim.playerId
		-- AN INTERCEPTING ROW HEADS SOMEWHERE ELSE. Same read, same commitment to the same player —
		-- it just walks to where they are going instead of to where they are. Falls through to the
		-- ordinary chase whenever it has no usable prediction, so the creature is never inert.
		local intercept = if ctx.def.intercept ~= nil then interceptTarget(ctx, dim, next_) else nil
		next_.targetPosition = intercept or flatten(state.position, dim.position)
		return next_
	end
	if lit == nil then
		return nil
	end

	-- Medium light only protects the side of the candle the player is actually watching. An
	-- unwatched crawler closes in at stalk speed; looking back makes it return to the spacing ring
	-- on the next decision. The lowest light band above already commits regardless of facing.
	local flatPlayer = flatten(state.position, lit.position)
	local lookDirection = lit.lookDirection
	local playerToHunter = state.position - flatPlayer
	-- Missing facing fails toward safety: adapters should supply it, but a temporarily missing rig
	-- must not grant the crawler supernatural knowledge that the player is looking away.
	local isObserved = true
	if lookDirection ~= nil then
		local flatLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)
		local flatToHunter = Vector3.new(playerToHunter.X, 0, playerToHunter.Z)
		if flatLook.Magnitude > 0 and flatToHunter.Magnitude > 0 then
			isObserved = flatLook.Unit:Dot(flatToHunter.Unit) >= behavior.darkHunterObservedDotThreshold
		end
	end
	if lit.lightLevel * sensitivity < behavior.darkHunterSneakLightThreshold and not isObserved then
		next_.mode = "Stalk"
		next_.targetPosition = flatPlayer
		next_.targetPlayerId = lit.playerId
		return next_
	end

	-- A watched or bright crawler moves toward a point on the safe-radius ring: back away when too
	-- close, edge nearer when far, and stop once the spacing is reached.
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
		-- Sound memory defaults to CLEARED. Only the investigate branches carry it forward, so any
		-- other decision — sensing prey, fleeing panic light, giving up and drifting — forgets the
		-- noise. That is what makes real prey interrupt curiosity rather than queue behind it.
		investigateUntil = 0,
		investigateLoudness = 0,
		-- Interception memory defaults to CLEARED, exactly like sound memory: only the intercept
		-- branch carries a commitment forward, so losing the player drops the prediction rather than
		-- leaving the creature walking to a corner nobody is going to any more.
		interceptUntil = 0,
		interceptPosition = nil,
		-- The strike clock is the one thing that must SURVIVE every decision, or a creature that was
		-- interrupted mid-cooldown could act again immediately.
		strikeReadyAt = state.strikeReadyAt,
		-- Harassment memory defaults to CLEARED, exactly like sound and interception memory: only the
		-- branch that still has its victim carries the commitment forward, so being flared, being
		-- crowded off, or losing the player all end the pursuit rather than pausing it.
		pursuitUntil = 0,
		-- Alarm memory defaults to CLEARED like every other commitment, so the summons survives exactly
		-- as long as `thinkAlarm` keeps re-establishing it and not one think longer.
		alarmUntil = 0,
		alarmPosition = nil,
		-- THE ONE FIELD THAT IS NOT A COMMITMENT AND MUST NEVER BE CLEARED. Every value above is memory
		-- a decision is allowed to drop; this is an injury (Config/Dynamite). A body that took most of a
		-- stick has to still be hurt on its next think, or two half-strength blasts would accomplish
		-- nothing and the accumulate-damage rule would silently not exist.
		blastDamage = state.blastDamage,
	}
	-- BEFORE THE ROW'S OWN BRANCHES, so that the roof-bound and territorial rows — which never reach
	-- the ordinary decision below — answer the summons too. See `thinkAlarm`.
	local alarmed = thinkAlarm(ctx, next_)
	if alarmed ~= nil then
		return alarmed
	end
	if def.ceilingStrike ~= nil then
		return thinkCeilingStriker(ctx, next_)
	end
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
		-- No prey sensed: something audible outranks a cold trail. This is the entire reason mining
		-- is dangerous — the noise is checked before the breadcrumbs, so a working pick pulls a
		-- hunter toward the seam rather than along the path you walked in on.
		local investigation = thinkInvestigate(ctx, next_)
		if investigation ~= nil then
			return investigation
		end
		-- Nothing heard either: follow the freshest drip trail in range (DESIGN §8 — the trail exposes you).
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
	-- Investigating is a walk, not a charge: the row's own investigateSpeedFraction keeps a lured
	-- threat visibly slower than a hunt, so a player who hears one coming still has the option to
	-- abandon the seam and leave.
	local investigateFraction = if def.hearing ~= nil then def.hearing.investigateSpeedFraction else 1
	local speedFraction = if state.mode == "Wander"
		then ThreatsConfig.behavior.wanderSpeedFraction
		elseif state.mode == "Stalk" then ThreatsConfig.behavior.stalkSpeedFraction
		elseif state.mode == "Investigate" then investigateFraction
		else 1
	local ambush = def.ambush
	-- A COMMITTED DIVE IS THE ONE THING ON THIS ROW THAT MOVES FASTER THAN THE ROW. Without it a
	-- territorial ambusher is slower than a walk once its victim is heading away, which is why the
	-- creature read as giving up: it was not losing interest, it was losing a footrace at 9.8 studs/s.
	-- The multiplier is authored to stay under Config/Movement.runSpeed, so running still beats it.
	if ambush ~= nil and state.mode == "Seek" then
		speedFraction *= ambush.pursuitSpeedMultiplier
	end
	local speed = def.speed * speedFraction
	local offset = target - state.position
	local distance = offset.Magnitude
	if distance < 0.05 then
		return state.position
	end
	local stepped = state.position + offset.Unit * math.min(distance, speed * dt)
	if ambush ~= nil then
		-- The leash. Ordinarily the territory; a live dive may pay it out to the pursuit radius, which
		-- is what lets the creature follow somebody off its patch and what still guarantees it can
		-- never be led across the floor.
		local leash = if state.mode == "Seek" then ambush.pursuitRadius else ambush.territoryRadius
		local fromHome = stepped - state.homePosition
		local horizontalFromHome = Vector3.new(fromHome.X, 0, fromHome.Z)
		if horizontalFromHome.Magnitude > leash then
			local clamped = horizontalFromHome.Unit * leash
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

-- Pure sustained-contact rule for a Drain row that escalates (Types/Threat.SustainedContactProfile).
-- `elapsed` is how long this player has been in unbroken contact and `lastContactAt` when contact was
-- last observed; the adapter owns both and this decides only whether the clock carries, restarts, or
-- has run out.
--
-- A LAPSE SHORTER THAN THE GRACE WINDOW IS NOT AN ESCAPE. Contact is a radius test against a flying
-- body, so a moth mid-wingbeat crosses that radius constantly while sitting on the same player; if
-- every crossing reset the clock the mechanic would never fire against a player standing still,
-- which is the exact case it exists for. A real break — walking out, dropping the light, a decoy
-- pulling it off — is longer than a wingbeat and restarts the count from nothing.
--
-- `secondsToSnuff <= 0` means the row cannot snuff at this depth. The clock still accumulates, so
-- nothing has to special-case a shallow floor; it simply never reaches an outcome.
function ThreatBrain.advanceContactSeconds(
	elapsed: number,
	lastContactAt: number,
	now: number,
	dt: number,
	profile: Types.SustainedContactProfile
): (number, boolean)
	local carried = if now - lastContactAt > math.max(0, profile.graceSeconds) then 0 else math.max(0, elapsed)
	local nextElapsed = carried + math.max(0, dt)
	if profile.secondsToSnuff <= 0 then
		return nextElapsed, false
	end
	return nextElapsed, nextElapsed >= profile.secondsToSnuff
end

return ThreatBrain
