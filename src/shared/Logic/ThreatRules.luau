--!strict
-- Pure: resolving an authored threat row against the floor it is about to stand on.
--
-- WHY THIS MODULE EXISTS. Difficulty used to ramp by composition — several near-identical rows with
-- staggered spawn tables, so a deep floor drew the nastier ones more often. That only ever worked
-- because the rows were invisible to the player; the moment they were collapsed into the one creature
-- they always rendered as, the ramp had to become something a row can carry on its own. It is
-- `Config/Threats.<row>.depthScaling`: one authored value per floor, and this module reads it.
--
-- THE CONTRACT. `atDepth` is called ONCE per spawned body (server/ThreatService.spawnFloor) and
-- returns an ordinary ThreatDef. Nothing downstream — the brain, the contact rules, the visual
-- proxy, the client — knows depth exists or that scaling happened. That is deliberate: a stat is
-- resolved in exactly one place, and every consumer keeps reading a plain row.
--
-- WHAT IS NOT SCALED, and why it is a closed list rather than a convention. Body size, contact
-- radius and the perch profile decide what a creature LOOKS like and how far it reaches. A player
-- learns a threat by its silhouette and by the gap it can close; a body that silently grew with
-- depth would be one they could never finish learning. Spawn weights are not scaled here either —
-- they are the planner's business, and Logic/CaveFamilyRules already samples them per family.

local Types = require(script.Parent.Parent.Types)

local ThreatRules = {}

-- Sampling matches Config's own convention everywhere else: the table is indexed by floor and
-- clamped at both ends, so floors past the last authored entry hold the deepest value rather than
-- falling off to zero. Never interpolates — an authored table IS the curve.
local function valueAtDepth(values: { number }?, depth: number, fallback: number): number
	if values == nil or #values == 0 then
		return fallback
	end
	local index = math.clamp(math.floor(depth), 1, #values)
	local value = values[index]
	if value == nil or value ~= value then
		return fallback
	end
	return value
end

local function scaledHearing(
	base: Types.HearingProfile?,
	scaling: Types.ThreatDepthScaling?,
	depth: number
): Types.HearingProfile?
	if base == nil then
		return nil
	end
	local hearing = if scaling ~= nil then scaling.hearing else nil
	if hearing == nil then
		return base
	end
	return {
		sensitivity = math.max(0, valueAtDepth(hearing.sensitivity, depth, base.sensitivity)),
		curiosityThreshold = math.max(0, valueAtDepth(hearing.curiosityThreshold, depth, base.curiosityThreshold)),
		hearingRadius = math.max(0, valueAtDepth(hearing.hearingRadius, depth, base.hearingRadius)),
		investigateSeconds = math.max(0, valueAtDepth(hearing.investigateSeconds, depth, base.investigateSeconds)),
		investigateSpeedFraction = math.max(
			0,
			valueAtDepth(hearing.investigateSpeedFraction, depth, base.investigateSpeedFraction)
		),
	}
end

local function scaledSustainedContact(
	base: Types.SustainedContactProfile?,
	scaling: Types.ThreatDepthScaling?,
	depth: number
): Types.SustainedContactProfile?
	if base == nil then
		return nil
	end
	local seconds = if scaling ~= nil
		then valueAtDepth(scaling.sustainedContactSecondsToSnuff, depth, base.secondsToSnuff)
		else base.secondsToSnuff
	return {
		-- Clamped at zero rather than erroring: zero is the authored way to say "not at this depth",
		-- and a negative would otherwise read as an instant snuff on first touch.
		secondsToSnuff = math.max(0, seconds),
		graceSeconds = math.max(0, base.graceSeconds),
	}
end

-- The row as it exists on THIS floor. Returns the authored table untouched when there is nothing to
-- scale, so the common case allocates nothing and identity comparisons against Config still hold.
function ThreatRules.atDepth(def: Types.ThreatDef, globalDepth: number): Types.ThreatDef
	local scaling = def.depthScaling
	if scaling == nil then
		return def
	end
	local depth = if globalDepth == globalDepth then math.max(1, math.floor(globalDepth)) else 1

	local resolved: Types.ThreatDef = {
		id = def.id,
		displayName = def.displayName,
		category = def.category,
		speed = math.max(0, valueAtDepth(scaling.speed, depth, def.speed)),
		detectionRadius = math.max(0, valueAtDepth(scaling.detectionRadius, depth, def.detectionRadius)),
		-- NOT clamped to a sign. The sign IS the category (DarkHunter repelled, Drawn attracted), and
		-- a curve that crossed zero would turn a creature into the other kind halfway down the cave;
		-- `validate` below rejects that at the config, which is where it can actually be fixed.
		lightResponse = valueAtDepth(scaling.lightResponse, depth, def.lightResponse),
		waxDamagePerSecond = math.max(0, valueAtDepth(scaling.waxDamagePerSecond, depth, def.waxDamagePerSecond)),
		contactEffect = def.contactEffect,
		contactRadius = def.contactRadius,
		bodySize = def.bodySize,
		spawnWeightByDepth = def.spawnWeightByDepth,
		visualStyle = def.visualStyle,
		ambush = def.ambush,
		perch = def.perch,
		contactAttack = def.contactAttack,
		sustainedContact = scaledSustainedContact(def.sustainedContact, scaling, depth),
		-- Carried through so a resolved row still reports what it was authored from; nothing reads it
		-- after resolution, and re-resolving a resolved row is a no-op that lands on the same value.
		depthScaling = scaling,
		hearing = scaledHearing(def.hearing, scaling, depth),
	}
	return resolved
end

-- Whether contact with this row can put a candle out at all, however it gets there: immediately,
-- after staged hits, or after unbroken contact. Callers that care about "can this end my run without
-- draining me first" ask this instead of testing `contactEffect`, so a row that gains a new route to
-- the snuffed state is covered without them being edited.
function ThreatRules.canSnuff(def: Types.ThreatDef): boolean
	if def.contactEffect == "Snuff" then
		return true
	end
	local sustained = def.sustainedContact
	return sustained ~= nil and sustained.secondsToSnuff > 0
end

-- Whether contact with this row snuffs with NO window to react — the player is out on the touch, or
-- on a fixed count of touches they cannot interrupt. This is the property the planner protects a
-- room for (Logic/FloorPlanner.roomHasCeilingThreat): stacking an unavoidable extinguish under
-- falling stone is the double-jeopardy DESIGN §9 forbids. A sustained-contact row is deliberately
-- NOT this — its snuff takes seconds of unbroken contact and can be walked out of.
function ThreatRules.snuffsWithoutWarning(def: Types.ThreatDef): boolean
	return def.contactEffect == "Snuff"
end

export type ValidationIssue = { threatId: string, field: string, message: string }

-- Properties a row may never violate. Returns issues rather than erroring, matching
-- Logic/CaveFamilyRules.validate: a bad row is a failing test, not a server that will not boot.
function ThreatRules.validate(definitions: { [Types.ThreatId]: Types.ThreatDef }): (boolean, { ValidationIssue })
	local issues: { ValidationIssue } = {}
	local function fail(threatId: string, field: string, message: string)
		table.insert(issues, { threatId = threatId, field = field, message = message })
	end

	for id, def in definitions do
		if def.id ~= id then
			fail(tostring(id), "id", "row is keyed as " .. tostring(id) .. " but calls itself " .. tostring(def.id))
		end
		-- The sign of lightResponse is the category. Crossing zero at any depth would mean a creature
		-- that flees light in the shallows and chases it deeper down.
		local wantsPositive = def.category == "Drawn"
		local scaling = def.depthScaling
		local curve = if scaling ~= nil then scaling.lightResponse else nil
		local samples: { number } = if curve ~= nil and #curve > 0 then curve else { def.lightResponse }
		for _, value in samples do
			if (value > 0) ~= wantsPositive or value == 0 then
				fail(id, "lightResponse", "sign must match the category at every depth")
				break
			end
		end

		local sustained = def.sustainedContact
		if sustained ~= nil then
			if def.contactEffect ~= "Drain" then
				fail(id, "sustainedContact", "only a Drain row can escalate to a snuff; this one already snuffs")
			end
			if sustained.graceSeconds < 0 then
				fail(id, "sustainedContact.graceSeconds", "must not be negative")
			end
		end
		if scaling ~= nil and scaling.sustainedContactSecondsToSnuff ~= nil and sustained == nil then
			fail(id, "depthScaling", "scales a sustained-contact clock the row does not have")
		end
	end

	return #issues == 0, issues
end

return ThreatRules
