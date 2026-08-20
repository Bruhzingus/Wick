--!strict
-- The Unlittius encounter's decisions, as pure functions (Config/Unlittius).
--
-- EVERYTHING THE FIGHT DECIDES LIVES HERE AND TOUCHES NO INSTANCE: which attack he picks, how long he
-- waits, where a dripstone zone lands, where a boulder is aimed, whether a claw reached somebody, and
-- whether a candle may be lit. `server/EnemySystem/UnlittiusBehavior` is the adapter that hands these
-- functions the live world and applies what they return.
--
-- WHY THAT SPLIT MATTERS ON THIS ENCOUNTER PARTICULARLY. A boss is the one place a project accretes
-- untestable code: timing, geometry and randomness braided into instance manipulation until nothing
-- can be checked except by standing in the room. Every rule below is deterministic given its inputs,
-- so the whole fight can be interrogated from `Tests/UnlittiusRulesTests` — including the ones that
-- are otherwise only observable by getting hit.

local Vector3Type = Vector3

local UnlittiusConfig = require(script.Parent.Parent.Config.Unlittius)

local UnlittiusRules = {}

export type ActionId = "Dripstone" | "BoulderBurst" | "SummonGnawers" | "Melee"

-- Why a candle refused to light. Mirrors `Logic/WallLampRules.Refusal` deliberately: it is the same
-- verb with the same gate, so a player who learns why a wall lamp refused already knows this one.
export type CandleRefusal = "alreadyLit" | "notAlive" | "finished" | "notLit" | "cupping" | "wrongFloor" | "tooFar"

export type CandleRequest = {
	candleLit: boolean,
	candleDepth: number,
	alive: boolean,
	finished: boolean,
	isLit: boolean,
	isCupping: boolean,
	playerDepth: number,
	distance: number,
}

local function config()
	return UnlittiusConfig
end

--------------------------------------------------------------------------------
-- PROGRESSION
--------------------------------------------------------------------------------

-- HOW MUCH OF HIM IS LEFT, 0..1. The single number every visual, every audio layer and every cadence
-- band in the encounter reads: `1 - lit/8`. It is the closest thing he has to a health bar and it is
-- deliberately not shown as one — the player reads it off his eyes and the room's warmth.
function UnlittiusRules.power(candlesLit: number, total: number?): number
	local count = math.max(total or config().encounter.candleCount, 1)
	return math.clamp(1 - candlesLit / count, 0, 1)
end

-- Rune / eye brightness at this candle count. Never reaches zero before the banish: a boss who has
-- already gone dark at seven candles has nothing left to take away at eight.
function UnlittiusRules.runeBrightness(candlesLit: number, total: number?): number
	local body = config().body
	local count = math.max(total or config().encounter.candleCount, 1)
	local step = math.clamp(candlesLit / math.max(count - 1, 1), 0, 1)
	return body.runeBrightnessFull + (body.runeBrightnessLast - body.runeBrightnessFull) * step
end

-- The supernatural audio layer's gain. The package's mix progression (100% at 0, ~60% at 4, ~20% at
-- 7) is a curve rather than a line, so this squares the power: it stays loud while he is winning and
-- collapses over the last three candles, which is when the player needs to hear that it is working.
function UnlittiusRules.supernaturalGain(candlesLit: number, total: number?): number
	local power = UnlittiusRules.power(candlesLit, total)
	return power * power
end

-- HOW MANY CANDLES THIS ENCOUNTER ACTUALLY HAS. Normally eight, and `total` is normally nil — but a
-- chamber where one post could not be seated on real Terrain builds seven, and an encounter that
-- still demanded eight would be UNWINNABLE: he could never be banished, and his floor gates the
-- descent ladder, so the run would dead-end on a bug nobody could route around. The encounter passes
-- the count it actually built and the fight is completable either way.
function UnlittiusRules.isComplete(candlesLit: number, total: number?): boolean
	return candlesLit >= math.max(total or config().encounter.candleCount, 1)
end

--------------------------------------------------------------------------------
-- HIS VOICE
--------------------------------------------------------------------------------

-- HOW LOUD AND HOW LOW HE IS SPEAKING, given how many candles are lit. Both fall as he is put out:
-- the muttering is the most direct read the player has on whether the plan is working, because unlike
-- his rune it is audible from behind cover and with your back to him.
function UnlittiusRules.voiceGain(candlesLit: number, total: number?): number
	local voice = config().voice
	local power = UnlittiusRules.power(candlesLit, total)
	return voice.gainAtLastCandle + (voice.gainAtFullPower - voice.gainAtLastCandle) * power
end

function UnlittiusRules.voicePitch(candlesLit: number, total: number?): number
	local voice = config().voice
	local power = UnlittiusRules.power(candlesLit, total)
	return voice.pitchAtLastCandle + (voice.pitchAtFullPower - voice.pitchAtLastCandle) * power
end

-- A SHUFFLED BAG OF EVERY UTTERANCE HE HAS. Returned as an order to walk, not as a random pick.
--
-- WHY A BAG RATHER THAN A ROLL. Rolling `1..12` each time feels random and is not: across a fight it
-- serves the same line twice in a row about one time in twelve, and a player hears that immediately —
-- the repetition is the only thing about a muttering boss that can break the illusion. Emptying a
-- shuffled bag guarantees all twelve are heard before any of them comes round again.
--
-- `avoidFirst` is the line that played last, so a fresh bag never opens with the utterance the
-- previous one closed on — the one case a per-bag shuffle can still produce a back-to-back repeat.
function UnlittiusRules.shuffledVoiceBag(rng: Random, avoidFirst: number?): { number }
	local bag: { number } = {}
	for index = 1, math.max(math.floor(config().voice.lineCount), 1) do
		table.insert(bag, index)
	end
	-- Fisher-Yates, from the encounter's own seeded stream so a replayed floor mutters the same way.
	for index = #bag, 2, -1 do
		local swap = rng:NextInteger(1, index)
		bag[index], bag[swap] = bag[swap], bag[index]
	end
	if avoidFirst ~= nil and #bag > 1 and bag[1] == avoidFirst then
		bag[1], bag[#bag] = bag[#bag], bag[1]
	end
	return bag
end

-- Seconds until his next mutter.
function UnlittiusRules.nextVoiceDelay(roll: number): number
	local voice = config().voice
	return voice.minIntervalSeconds + math.clamp(roll, 0, 1) * (voice.maxIntervalSeconds - voice.minIntervalSeconds)
end

-- MAY HE MUTTER RIGHT NOW? He does not talk over his own attacks, and he never mutters during the
-- banish.
--
-- THAT IS NOT THE SAME AS THE BANISH BEING SILENT. The sequence fires two SCRIPTED utterances of its
-- own — the cry as the rune comes apart and the last word the stone cuts off (`Config.Unlittius.banish
-- .cryAt` / `.lastWordAt`) — and they are beats on the banish's clock rather than anything this
-- function governs. What is suppressed here is the ambient muttering, which would otherwise wander
-- into the middle of his own death.
function UnlittiusRules.canSpeak(action: string, secondsSinceActionStarted: number): boolean
	if action == "Banish" then
		return false
	end
	if action ~= "Idle" then
		return false
	end
	return secondsSinceActionStarted >= config().voice.quietAfterActionSeconds
end

--------------------------------------------------------------------------------
-- THE DIRECTOR
--------------------------------------------------------------------------------

-- Seconds of downtime after an action, by progress. Telegraphs never shorten (Config/Unlittius);
-- only this does.
function UnlittiusRules.downtimeSeconds(candlesLit: number, roll: number): number
	local downtime = config().director.downtime
	local band = if candlesLit <= 2 then downtime.early elseif candlesLit <= 5 then downtime.mid else downtime.late
	return band.min + math.clamp(roll, 0, 1) * (band.max - band.min)
end

-- Has this action been taken `repeatLimit` times in a row? `recent` is most-recent-first.
function UnlittiusRules.isRepeatExhausted(recent: { ActionId }, action: ActionId): boolean
	local limit = math.max(config().director.repeatLimit, 1)
	if #recent < limit then
		return false
	end
	for index = 1, limit do
		if recent[index] ~= action then
			return false
		end
	end
	return true
end

export type ActionContext = {
	-- Somebody is inside `melee.triggerRadius` and in front of him.
	meleeCandidate: boolean,
	meleeReady: boolean,
	-- The summon is off cooldown AND under its live cap.
	summonEligible: boolean,
	candlesLit: number,
	recent: { ActionId },
	roll: number,
}

-- WHICH ATTACK, IN THE PACKAGE'S OWN DECISION ORDER. Melee is a condition rather than a weight: if
-- somebody is standing under him and the rake is off cooldown, that is what happens, because the
-- entire purpose of the rake is that the dais is not a place to stand. Everything else is a weighted
-- roll with the repeat limit applied by zeroing exhausted options rather than by re-rolling, so the
-- distribution stays honest instead of quietly favouring whatever is checked first.
function UnlittiusRules.chooseAction(context: ActionContext): ActionId
	if context.meleeCandidate and context.meleeReady then
		return "Melee"
	end

	local weights = config().director.weights
	local options: { { id: ActionId, weight: number } } = {}
	local total = 0
	for _, id in { "Dripstone" :: ActionId, "BoulderBurst" :: ActionId, "SummonGnawers" :: ActionId } do
		if id == "SummonGnawers" and not context.summonEligible then
			continue
		end
		if UnlittiusRules.isRepeatExhausted(context.recent, id) then
			continue
		end
		local weight = weights[id] or 0
		if weight <= 0 then
			continue
		end
		total += weight
		table.insert(options, { id = id, weight = weight })
	end

	-- EVERYTHING WAS EXHAUSTED, which is reachable: two dripstones in a row with the summon capped
	-- and the boulder weight zeroed by a retune. Falling through to the arena-control option is the
	-- right answer — it is the one attack that is always fair and always says something.
	if total <= 0 then
		return "Dripstone"
	end

	local target = math.clamp(context.roll, 0, 0.999999) * total
	local walked = 0
	for _, option in options do
		walked += option.weight
		if target < walked then
			return option.id
		end
	end
	return options[#options].id
end

--------------------------------------------------------------------------------
-- SCALING BY PARTY
--------------------------------------------------------------------------------

local function byPartySize(playerCount: number, solo: number, duo: number, party: number): number
	if playerCount <= 1 then
		return solo
	elseif playerCount == 2 then
		return duo
	end
	return party
end

function UnlittiusRules.dripstoneZoneCount(playerCount: number): number
	local dripstone = config().dripstone
	return byPartySize(playerCount, dripstone.zonesSolo, dripstone.zonesDuo, dripstone.zonesParty)
end

function UnlittiusRules.summonCount(playerCount: number, activeGnawers: number): number
	local summon = config().summon
	local wanted = byPartySize(playerCount, summon.countSolo, summon.countDuo, summon.countParty)
	return math.max(0, math.min(wanted, summon.activeCap - activeGnawers))
end

function UnlittiusRules.summonEligible(activeGnawers: number, now: number, nextSummonAt: number): boolean
	return activeGnawers < config().summon.activeCap and now >= nextSummonAt
end

--------------------------------------------------------------------------------
-- GEOMETRY
--------------------------------------------------------------------------------

local function flat(vector: Vector3): Vector3
	return Vector3Type.new(vector.X, 0, vector.Z)
end

-- Is this point inside the arc a claw can reach? Flat, because his root hovers and a player's does
-- not: a reach measured as a diagonal would shrink or grow with how high he happens to be bobbing.
function UnlittiusRules.insideArc(origin: Vector3, facing: Vector3, point: Vector3, arcDot: number): boolean
	local offset = flat(point - origin)
	if offset.Magnitude < 0.01 then
		return true
	end
	local forward = flat(facing)
	if forward.Magnitude < 0.01 then
		return false
	end
	return forward.Unit:Dot(offset.Unit) >= arcDot
end

function UnlittiusRules.flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

-- WHERE A BOULDER IS AIMED. A modest lead on the target's own horizontal velocity, clamped so that a
-- player being flung by something else is not answered with a shot into the far wall. After this
-- point the projectile never turns again — the package is explicit that there is no homing, and that
-- is what makes a boulder something a player can beat by moving.
function UnlittiusRules.leadTarget(position: Vector3, velocity: Vector3): Vector3
	local boulder = config().boulder
	local horizontal = flat(velocity)
	if horizontal.Magnitude > boulder.predictionMaxSpeed then
		horizontal = horizontal.Unit * boulder.predictionMaxSpeed
	end
	return position + horizontal * boulder.predictionSeconds
end

-- The direction one shot travels, from its own spawn attachment rather than from his root: the
-- stones materialise outboard of each shoulder, and aiming from the body's centre is exactly how a
-- projectile ends up clipping through the torso it was supposed to miss.
function UnlittiusRules.boulderDirection(origin: Vector3, aimPoint: Vector3): Vector3
	local delta = aimPoint - origin
	if delta.Magnitude < 0.001 then
		return Vector3Type.new(0, 0, 1)
	end
	return delta.Unit
end

--------------------------------------------------------------------------------
-- MOVEMENT
--------------------------------------------------------------------------------

export type DriftIntent = "Hold" | "Withdraw" | "Reposition" | "Recenter"

export type DriftContext = {
	-- Flat distance to the nearest participant, or nil for an empty room.
	nearestDistance: number?,
	-- Whether he can currently SEE the player he would throw at. False means a pillar, a formation or
	-- a fallen stone is between them — the one condition his mobility exists to answer.
	hasLineOfSight: boolean,
	-- How far he has drifted from his own shrine.
	distanceFromHome: number,
}

-- WHAT HE WANTS TO DO WITH HIS POSITION THIS FRAME. Four intents, no pathfinding, and — importantly —
-- NO APPROACH. He is bound to his shrine and slides around it; he never crosses the room after
-- anybody, because distance is the player's to choose and this encounter is the room rather than a
-- pursuit across it.
--
-- The order is the priority order:
--
--   * RECENTER first, unconditionally. He has drifted to the edge of his leash and the shrine pulls
--     him back; nothing else he might want matters more than staying bound to it.
--   * WITHDRAW when somebody is crowding him. A boulder needs room to be read, and a boss standing on
--     top of a player is a boss whose telegraphs arrive already resolved.
--   * REPOSITION when he cannot see the player he wants to throw at. This is the whole reason he moves
--     at all: cover should cost him an angle and a couple of seconds, not switch the fight off.
--   * HOLD otherwise — which is most of the time. He hangs over his own dais and lets them come.
function UnlittiusRules.driftIntent(context: DriftContext): DriftIntent
	local movement = config().movement
	-- The SOFT edge, inside the hard clamp. He notices he has drifted and comes back on his own; the
	-- clamp behind it exists so that nothing — a knockback, a bad frame, a retune — can ever put him
	-- outside the room, and in normal play it never has to.
	if context.distanceFromHome > movement.homeRadius * movement.recenterFraction then
		return "Recenter"
	end
	local nearest = context.nearestDistance
	if nearest == nil then
		return "Hold"
	end
	if nearest < movement.minimumRange then
		return "Withdraw"
	end
	if not context.hasLineOfSight then
		return "Reposition"
	end
	return "Hold"
end

-- The direction he wants to travel, as a flat unit vector (or zero for "stay put"). `lateralSign` is
-- held for `lateralHoldSeconds` by the caller, so a sidestep reads as a decision rather than as
-- indecision.
function UnlittiusRules.driftDirection(
	intent: DriftIntent,
	origin: Vector3,
	target: Vector3?,
	home: Vector3,
	lateralSign: number
): Vector3
	if intent == "Hold" then
		return Vector3Type.zero
	end

	if intent == "Recenter" then
		local back = flat(home - origin)
		return if back.Magnitude < 0.01 then Vector3Type.zero else back.Unit
	end

	if target == nil then
		return Vector3Type.zero
	end
	local toTarget = flat(target - origin)
	if toTarget.Magnitude < 0.01 then
		return Vector3Type.zero
	end
	local forward = toTarget.Unit

	if intent == "Withdraw" then
		-- BACK OFF, BUT TOWARD HIS OWN SHRINE where the two agree. Backing off in a straight line from
		-- a player standing between him and the dais would walk him to the end of his leash and strand
		-- him there for the rest of the fight.
		local homeward = flat(home - origin)
		if homeward.Magnitude > 0.01 then
			return (-forward * 0.7 + homeward.Unit * 0.3).Unit
		end
		return -forward
	end

	-- REPOSITION: strictly perpendicular. He slides ACROSS their line rather than along it, which is
	-- what changes the angle without changing the range — the distance between them stays the
	-- player's decision even while he is working around their cover.
	local side = Vector3Type.new(-forward.Z, 0, forward.X) * (if lateralSign < 0 then -1 else 1)
	return side.Unit
end

-- How fast that intent is worth travelling at. Only the hunt for an angle has any urgency in it.
function UnlittiusRules.driftSpeed(intent: DriftIntent): number
	local movement = config().movement
	if intent == "Hold" then
		return 0
	elseif intent == "Reposition" then
		return movement.repositionSpeed
	end
	return movement.driftSpeed
end

-- ONE STEP OF HEAVY ACCELERATION. Velocity is eased toward the desired vector rather than assigned, so
-- he can never snap between CFrames — the difference between a levitating body and a teleporting prop
-- is entirely in this function.
function UnlittiusRules.stepVelocity(current: Vector3, desired: Vector3, dt: number): Vector3
	local movement = config().movement
	local delta = desired - current
	local magnitude = delta.Magnitude
	if magnitude < 1e-4 then
		return desired
	end
	-- Slowing down is allowed to be brisker than speeding up: a mass this size stops by being let go
	-- of, and a boss who took as long to stop as to start would overshoot every position he chose.
	local rate = if desired.Magnitude < current.Magnitude then movement.deceleration else movement.acceleration
	local step = math.min(rate * dt, magnitude)
	return current + delta.Unit * step
end

-- KEEP HIM ON HIS SHRINE. Clamped to a disc rather than a box, because the leash is a radius and a
-- corner he could reach is a corner a boulder could be fired from through a wall.
--
-- TWO LIMITS, AND THE TIGHTER ONE WINS. `homeRadius` is the leash — the whole of his mobility — and
-- the chamber wall is the hard backstop behind it for a room smaller than the leash assumes. Returns
-- the corrected position and whether it had to be corrected.
function UnlittiusRules.clampToChamber(position: Vector3, center: Vector3, chamberRadius: number): (Vector3, boolean)
	local movement = config().movement
	local limit = math.min(movement.homeRadius, math.max(chamberRadius - movement.wallMargin, 1))
	local offset = flat(position - center)
	if offset.Magnitude <= limit then
		return position, false
	end
	local clamped = center + offset.Unit * limit
	return Vector3Type.new(clamped.X, position.Y, clamped.Z), true
end

-- WHICH SHOULDER A GIVEN SHOT LEAVES FROM, and the single most important geometric rule in the whole
-- encounter's presentation.
--
-- THE PACKAGE'S HARDEST REQUIREMENT IS THAT A CONJURED BOULDER NEVER PASSES THROUGH HIS TORSO, and the
-- naive implementation breaks it constantly: fire the left stone at a player standing to his right and
-- the flight path crosses his own chest. Firing from the shoulder on the target's OWN side makes the
-- path diverge from the body instead of crossing it, for every target angle in front of him — and for
-- targets behind him it is the shoulder that has to swing the least, which is also the one that keeps
-- the stone outboard while he is turning.
--
-- Returns -1 for the left shoulder and 1 for the right, in his own frame.
function UnlittiusRules.boulderSide(origin: Vector3, forward: Vector3, target: Vector3): number
	local flatForward = flat(forward)
	if flatForward.Magnitude < 0.01 then
		return -1
	end
	flatForward = flatForward.Unit
	local right = Vector3Type.new(-flatForward.Z, 0, flatForward.X)
	local toTarget = flat(target - origin)
	if toTarget.Magnitude < 0.01 then
		return -1
	end
	return if right:Dot(toTarget.Unit) >= 0 then 1 else -1
end

export type BoulderCandidate = { id: number, distance: number }

-- WHO THE TWO STONES ARE FOR. Solo: both at the one player. Otherwise the two nearest get one each,
-- so a burst is never entirely spent on somebody who is already being pressured — the package's own
-- multiplayer rule.
--
-- ANYBODY INSIDE `minimumEngagementRange` IS SKIPPED, and that is a geometry rule wearing a design
-- rule's clothes. A target six studs away and behind him cannot be hit from either shoulder without
-- the flight path crossing his own torso — no attachment offset fixes it, because at that range the
-- line between any point on his shoulders and any point that close passes through the middle of him.
-- The answer at that range is the claw rake, so the burst simply looks past them.
--
-- IT STILL FIRES IF EVERYBODY IS TOO CLOSE. An attack that silently did nothing would be worse than
-- an ugly one: the furthest available target is used, which is the least bad geometry on offer.
function UnlittiusRules.boulderTargets(candidates: { BoulderCandidate }): { number }
	local minimum = config().boulder.minimumEngagementRange
	local eligible: { BoulderCandidate } = {}
	for _, candidate in candidates do
		if candidate.distance >= minimum then
			table.insert(eligible, candidate)
		end
	end
	if #eligible == 0 then
		-- Nobody at a workable range. Take the furthest of whoever is here rather than skipping the
		-- attack outright.
		local furthest: BoulderCandidate? = nil
		for _, candidate in candidates do
			if furthest == nil or candidate.distance > furthest.distance then
				furthest = candidate
			end
		end
		if furthest == nil then
			return {}
		end
		return { furthest.id, furthest.id }
	end
	table.sort(eligible, function(a, b)
		return a.distance < b.distance
	end)
	if #eligible == 1 then
		return { eligible[1].id, eligible[1].id }
	end
	return { eligible[1].id, eligible[2].id }
end

-- DOES THIS SHOT'S PATH CLEAR HIS BODY? A pure test so the property can be swept over every target
-- angle in a test rather than discovered in a playtest. Measures the closest approach of the flight
-- segment to his centreline and compares it against the torso radius.
function UnlittiusRules.boulderPathClears(
	spawn: Vector3,
	direction: Vector3,
	bodyCenter: Vector3,
	bodyRadius: number,
	distance: number
): boolean
	local flatDirection = flat(direction)
	if flatDirection.Magnitude < 1e-4 then
		return false
	end
	flatDirection = flatDirection.Unit
	local toBody = flat(bodyCenter - spawn)
	-- How far along the flight the closest approach happens. Behind the muzzle means the stone is
	-- already travelling away from him and the path is clear by construction.
	local along = toBody:Dot(flatDirection)
	if along <= 0 then
		return true
	end
	local closest = flat(spawn) + flatDirection * math.min(along, distance)
	return (closest - flat(bodyCenter)).Magnitude >= bodyRadius
end

-- WHERE THE CEILING COMES DOWN. Zones are placed around the players rather than on them: a marker
-- centred on somebody standing still is not a decision, it is a tax on standing still. `spread` puts
-- each zone a few studs off a real position in a rolled direction, and anything landing on top of an
-- already-chosen zone is rejected so a volley can never wall a player in.
--
-- Deterministic given `rolls`, which is what lets the placement be tested rather than watched.
function UnlittiusRules.dripstoneZones(
	targets: { Vector3 },
	zoneCount: number,
	rolls: { number },
	center: Vector3,
	maximumRadius: number
): { Vector3 }
	local dripstone = config().dripstone
	local zones: { Vector3 } = {}
	if #targets == 0 or zoneCount <= 0 then
		return zones
	end

	local rollIndex = 0
	local function nextRoll(): number
		rollIndex += 1
		local value = rolls[((rollIndex - 1) % math.max(#rolls, 1)) + 1]
		return if typeof(value) == "number" then math.clamp(value, 0, 1) else 0.5
	end

	local attempts = 0
	while #zones < zoneCount and attempts < zoneCount * 8 do
		attempts += 1
		local target = targets[((#zones + attempts) % #targets) + 1]
		local angle = nextRoll() * math.pi * 2
		local spread = dripstone.aimSpreadMin + nextRoll() * (dripstone.aimSpreadMax - dripstone.aimSpreadMin)
		local candidate = flat(target) + Vector3Type.new(math.cos(angle) * spread, 0, math.sin(angle) * spread)
		candidate = Vector3Type.new(candidate.X, target.Y, candidate.Z)

		-- Inside the chamber. A zone outside the room would be a marker nobody can see resolving into
		-- damage nobody can be standing in — wasted, and it makes the volley read as smaller than it is.
		if UnlittiusRules.flatDistance(candidate, center) > maximumRadius then
			continue
		end
		local clear = true
		for _, existing in zones do
			if UnlittiusRules.flatDistance(candidate, existing) < dripstone.minimumZoneSeparation then
				clear = false
				break
			end
		end
		if clear then
			table.insert(zones, candidate)
		end
	end
	return zones
end

-- The eight candle posts, as offsets from the chamber centre. Evenly spaced and rotated off his
-- facing so no candle is directly in front of him at spawn — the first one a player reaches should
-- never be the one standing in his rake.
function UnlittiusRules.candleOffsets(): { Vector3 }
	local encounter = config().encounter
	local offsets: { Vector3 } = {}
	local count = math.max(math.floor(encounter.candleCount), 1)
	local base = math.rad(encounter.candleRingOffsetDegrees)
	for index = 0, count - 1 do
		local angle = base + index / count * math.pi * 2
		table.insert(
			offsets,
			Vector3Type.new(
				math.cos(angle) * encounter.candleRingRadius,
				0,
				math.sin(angle) * encounter.candleRingRadius
			)
		)
	end
	return offsets
end

-- Where one summoned Gnawer surfaces. A ring around the dais, walked by index so a summon of two
-- never puts both of them in the same place.
function UnlittiusRules.summonPoint(center: Vector3, index: number, total: number, roll: number): Vector3
	local summon = config().summon
	local angle = (index - 1) / math.max(total, 1) * math.pi * 2 + math.clamp(roll, 0, 1) * math.pi * 2
	local radius = summon.spawnRadiusMin + math.clamp(roll, 0, 1) * (summon.spawnRadiusMax - summon.spawnRadiusMin)
	return center + Vector3Type.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

--------------------------------------------------------------------------------
-- CANDLES
--------------------------------------------------------------------------------

-- MAY THIS PLAYER LIGHT THIS CANDLE? The order is deliberate and copied from `WallLampRules.canLight`:
-- the candle's own state first, then the player's, then geometry — so a dead player at an already-lit
-- candle is told the candle is lit, because that is the reason nothing would have happened anyway.
--
-- YOU LIGHT IT OFF YOUR OWN FLAME, which is why `isLit` and `isCupping` are in here. A snuffed player
-- cannot advance the encounter and a cupped one has nothing to light it with — the same contract
-- lighting the cave has always had, and the reason a party that is losing cannot simply rush the last
-- candle in the dark.
function UnlittiusRules.canLightCandle(request: CandleRequest): (boolean, CandleRefusal?)
	if request.candleLit then
		return false, "alreadyLit"
	end
	if not request.alive then
		return false, "notAlive"
	end
	if request.finished then
		return false, "finished"
	end
	if request.playerDepth ~= request.candleDepth then
		return false, "wrongFloor"
	end
	if not request.isLit then
		return false, "notLit"
	end
	if request.isCupping then
		return false, "cupping"
	end
	if request.distance > UnlittiusRules.candleServerRange() then
		return false, "tooFar"
	end
	return true, nil
end

-- The distance the SERVER accepts: the prompt's range plus the usual trust-boundary slack, exactly as
-- `WallLampRules.serverRange` computes it.
function UnlittiusRules.candleServerRange(): number
	local encounter = config().encounter
	return math.max(encounter.candlePromptRange + encounter.candlePositionToleranceStuds, 0)
end

-- WHAT A LIT SHRINE CANDLE IS TO A THREAT, and the function that makes the eight of them real rather
-- than decorative. Every field is load-bearing and every one of them matches `WallLampRules
-- .lightSource`, because a candle burning on his dais must be worth exactly what a candle burning
-- anywhere else in the cave is worth:
--
--   * `attractsDrawn` — it is fire in a dark room, and the Drawn come to fire. Winning this fight
--     makes the chamber busier, which is the cost the encounter is built on.
--   * `repelsDarkHunters` — the same push any flame gives, which is what makes lighting the ring a
--     real defensive gain as well as a score.
--   * `forcesDarkHunterRetreat = false` — only a Flare panics anything. A fixture that could do it
--     would make eight of them a permanent no-go zone for half the roster.
--   * `ownerId = nil` — nobody's light. A candle is not carried, cannot be filtered as somebody's,
--     and does not go out when the player who lit it dies.
function UnlittiusRules.candleLightSource(position: Vector3): {
	kind: string,
	position: Vector3,
	intensity: number,
	range: number,
	attractsDrawn: boolean,
	repelsDarkHunters: boolean,
	forcesDarkHunterRetreat: boolean,
	ownerId: number?,
}
	local encounter = config().encounter
	return {
		kind = "Flame",
		position = position,
		intensity = encounter.candleLightIntensity,
		range = encounter.candleLightRange,
		attractsDrawn = true,
		repelsDarkHunters = true,
		forcesDarkHunterRetreat = false,
		ownerId = nil,
	}
end

--------------------------------------------------------------------------------
-- TIMELINE
--------------------------------------------------------------------------------

-- Whether an action's authoritative beat has arrived. One function rather than a comparison scattered
-- through the behaviour, so every hit in the fight is resolved against the same clock and the same
-- rounding.
function UnlittiusRules.beatReached(elapsed: number, beatAt: number): boolean
	return elapsed >= beatAt
end

-- WHETHER A CANDLE MAY INTERRUPT WHAT HE IS DOING. Recoil takes priority over everything except the
-- banish — but a beat that has ALREADY fired is never rewound: a boulder in the air stays in the air
-- and a rake that landed stays landed. This returns whether the current action can be abandoned
-- cleanly, which is the only question the recoil actually needs answered.
function UnlittiusRules.canInterruptFor(action: string, elapsed: number): boolean
	if action == "Banish" or action == "Recoil" then
		return false
	end
	if action == "Idle" then
		return true
	end
	local timings = config().timings
	if action == "Dripstone" then
		return elapsed < timings.dripstoneSnapAt
	elseif action == "BoulderBurst" then
		return elapsed < timings.boulderConjureAt
	elseif action == "SummonGnawers" then
		return elapsed < timings.summonSpawnAt
	elseif action == "Melee" then
		return elapsed < timings.meleeHit1At
	end
	return true
end

return UnlittiusRules
