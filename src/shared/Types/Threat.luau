--!strict
-- Threat-domain types (DESIGN §9). Two categories exist so there is never a dominant brightness.

local Sound = require(script.Parent.Sound)

-- The two categories. Closed union — fixed by design.
export type ThreatCategory = "DarkHunter" | "Drawn"

-- Identifier for a specific threat. Open string alias: the content pool grows by adding Config rows,
-- not by editing this type (ARCHITECTURE: content is data, not classes).
export type ThreatId = string

-- What touching this threat does. "Drain" removes wax over time; "Snuff" extinguishes with wax
-- remaining (the revivable death state). Neither ever instant-kills (DESIGN §9).
export type ContactEffect = "Drain" | "Snuff"

-- Reusable content profiles. New rows select these profiles instead of adding per-enemy classes.
--
-- A STYLE NAMES A BODY, NEVER A BEHAVIOUR. `Default` renders the category silhouette (the gaunt
-- dark-hunter or the moth); the rest name a distinct procedural body under
-- Shared/NewModelsAndObjects. Every one of them still carries its category's readable tell — crimson
-- angled eye slits on a hunter, the warm yellow halo on a Drawn — because that tell is how a player
-- decides what to do about the thing in front of them, and it may never depend on knowing the row.
export type ThreatVisualStyle = "Default" | "Bug" | "Listener" | "Knotwalker" | "Calver"

-- INTERCEPTION. A row carrying this does not walk toward where a player IS; it walks toward where
-- they are GOING, one room ahead through the floor's own doorway graph.
--
-- WHY IT IS A PROFILE AND NOT A NEW BRAIN. Everything else about the row — light bands, retreat,
-- contact, roaming, hearing — is ordinary dark-hunter behaviour. Only the choice of destination
-- differs, so this replaces one decision inside Logic/ThreatBrain rather than adding a second brain
-- beside it.
--
-- IT MUST STAY BEATABLE BY A ROUTE CHANGE, which is what every number here protects: it commits to
-- ONE prediction and will not re-predict until that commitment lapses, so doubling back always works
-- and a player who changes their mind is never followed by something that changed its mind faster.
export type InterceptProfile = {
	-- How far along a player's heading the prediction lands, in studs. Authored rather than derived
	-- from anything, because it is the number that decides whether this creature reads as "cut off at
	-- the door" or as "waiting three rooms away", and that judgement should be visible in the config.
	projectionStuds: number,
	-- How long one prediction is honoured before a fresh one may be made. THE fairness number: while
	-- this runs the creature is committed to ground the player has already had a chance to see it
	-- take, and cannot re-aim at a player who dodged.
	commitmentSeconds: number,
	-- How far ahead through the room graph it aims. Deliberately ONE room in shipped content: two is
	-- indistinguishable from the creature knowing the destination.
	roomsAhead: number,
	-- It only predicts for a player it can actually place. Past this it goes back to ordinary roaming
	-- rather than tracking someone across a floor it cannot see.
	maximumPredictionDistance: number,
}

-- CEILING STRIKE. A row carrying this never touches a player: it clings to the roof and, when a
-- candle passes beneath, strikes the rock to bring down an unstable formation that was ALREADY
-- hanging there — the same trigger a player or a Warden crossing the disc causes.
--
-- IT ADDS NO NEW DANGER, AND THAT IS THE POINT. Everything it can drop was authored by the planner,
-- was inspectable from across the room, and gives its own full warning when it goes. What the row
-- changes is WHEN, so a player who read the ceiling and chose to cross under it anyway is the one
-- who gets hit. With nothing in range it only scrapes: loud, locatable, and harmless.
export type CeilingStrikeProfile = {
	-- Horizontal reach from the body to a formation it can set off.
	strikeRadius: number,
	-- Ground-level radius beneath it that a candle must enter before it will strike at all.
	activationRadius: number,
	-- Minimum gap between strikes, so one pass beneath it is one event.
	cooldownSeconds: number,
	-- Wind-up before the rock is struck. The player's warning that something above them is about to
	-- act, and it runs BEFORE the formation's own warning rather than instead of it.
	windUpSeconds: number,
	-- Roof-hugging geometry, matching the ambusher's own fields so the two read as one cave layer.
	maximumCeilingHeight: number,
	ceilingClearance: number,
	roofDecorationClearance: number,
	territoryRadius: number,
	patrolRadius: number,
	hoverHeight: number,
	-- A flare still drives it off its patch exactly like any other dark-hunter, so the counter to a
	-- creature that weaponises the ceiling is the same tool that answers everything else in the dark.
	retreatDistance: number,
	retreatSeconds: number,
}

export type AmbushProfile = {
	activationRadius: number,
	territoryRadius: number,
	patrolRadius: number,
	teammateRepelRadius: number,
	retreatDistance: number,
	retreatSeconds: number,
	maximumCeilingHeight: number, -- nominal room ceiling cap; keeps ceiling tells visible/audible
	ceilingClearance: number, -- root clearance below the sampled irregular roof while not diving
	roofDecorationClearance: number, -- extra dressing margin outside its territory
	hoverHeight: number, -- fallback above-ground height when no sampled roof surface is available
	attackHeight: number,
	diveSpeed: number, -- studs/sec toward attack height; prevents an instantaneous vertical snap
	returnSpeed: number, -- studs/sec back to the sampled roof after disengaging
	contactHeightTolerance: number, -- staged hits begin only once the body finishes its dive
}

-- Idle threats that settle onto cave walls instead of milling on the floor. Purely a Wander-mode
-- resting behaviour: any light the row can sense pulls it straight back off the wall.
export type PerchProfile = {
	searchRadius: number, -- studs outward from the wander point searched for a wall face
	searchDirections: number, -- evenly spaced horizontal probes cast per perch attempt
	minimumHeight: number, -- lowest a perch may sit above the ground below it
	maximumHeight: number,
	surfaceOffset: number, -- lift off the wall face so the body never embeds
	minimumDwellSeconds: number, -- how long it rests before roaming to a new wall
	maximumDwellSeconds: number,
	minimumWallSlopeDegrees: number, -- how far from horizontal a face must tilt to count as a wall
}

export type ContactAttackProfile = {
	cooldownSeconds: number,
	hitsToSnuff: number,
	waxDamagePerHit: number,
}

-- SUSTAINED CONTACT. A Drain row carrying this profile does not only cost wax: a player who never
-- breaks away is eventually put OUT, with wax still in the candle (the revivable snuffed state).
--
-- WHY THIS EXISTS RATHER THAN A SECOND ROW. Contact that extinguishes used to be its own threat with
-- its own stat block, which meant the whole mechanic rode on a spawn roll and rendered as the same
-- body as the row beside it. As a profile it is a property of the creature instead: the moth drains
-- you, and if you cannot get off it, it takes the flame. See Config/Threats.Moth.
export type SustainedContactProfile = {
	-- Seconds of unbroken contact before the candle goes out. 0 = never, matching the "0 means
	-- unavailable" convention `spawnWeightByDepth` already uses, so a depth curve can switch the
	-- mechanic on at a floor rather than gating it in code.
	secondsToSnuff: number,
	-- How long contact may lapse and still count as unbroken. Contact is sampled against a radius, and
	-- a body whose animation carries it a few tenths of a stud in and out of that radius has not let
	-- anybody escape; without this the mechanic would be defeated by standing still.
	graceSeconds: number,
}

-- DEPTH SCALING. One authored value per floor, exactly the shape of `spawnWeightByDepth`, sampled at
-- the floor's global depth and clamped at both ends. A field left out here keeps the row's flat value.
--
-- WHY THE ROSTER NEEDS THIS AT ALL. Difficulty used to ramp by COMPOSITION: three dark-hunter rows
-- with different stats and staggered spawn curves, so a deep floor drew the nastier ones more often.
-- Every one of those rows rendered as the same body and no label ever told them apart, so what the
-- player actually met was one creature whose stats changed with depth — this, written out honestly,
-- as a property of the single row rather than an emergent side effect of a spawn table.
export type ThreatHearingScaling = {
	sensitivity: { number }?,
	curiosityThreshold: { number }?,
	hearingRadius: { number }?,
	investigateSeconds: { number }?,
	investigateSpeedFraction: { number }?,
}

-- Deliberately a CLOSED set of the fields that carry difficulty. Body size, contact radius and the
-- perch profile are not scalable: they decide what a body looks like and how wide it reaches, and a
-- creature whose silhouette quietly grows with depth is one the player cannot learn to read.
export type ThreatDepthScaling = {
	speed: { number }?,
	detectionRadius: { number }?,
	lightResponse: { number }?,
	waxDamagePerSecond: { number }?,
	sustainedContactSecondsToSnuff: { number }?,
	hearing: ThreatHearingScaling?,
}

-- Static threat definition. Pure data (see Config/Threats). A new threat is a new row.
export type ThreatDef = {
	id: ThreatId,
	displayName: string,
	category: ThreatCategory,
	speed: number, -- studs/sec when seeking or fleeing; higher = harder
	detectionRadius: number, -- studs at which it senses players/light; higher = harder
	lightResponse: number, -- SIGN = reaction to light (DarkHunter < 0 repelled, Drawn > 0 attracted); magnitude = sensitivity
	waxDamagePerSecond: number, -- wax DRAINED while in contact (Drain effect); higher = harder
	contactEffect: ContactEffect,
	contactRadius: number, -- studs counting as contact
	bodySize: number, -- side length of the silhouette box (visual only)
	spawnWeightByDepth: { number }, -- relative spawn likelihood indexed by floor depth; 0 = unavailable
	visualStyle: ThreatVisualStyle?, -- nil/Default uses the category silhouette
	ambush: AmbushProfile?, -- fixed-territory wait/attack/retreat behaviour
	intercept: InterceptProfile?, -- heads for the room a player is walking TOWARD rather than the one they are in
	ceilingStrike: CeilingStrikeProfile?, -- clings to the roof and triggers an already-hanging formation
	perch: PerchProfile?, -- rests on cave walls while wandering instead of drifting across the floor
	contactAttack: ContactAttackProfile?, -- staged contact instead of continuous drain/immediate snuff
	sustainedContact: SustainedContactProfile?, -- unbroken drain contact eventually snuffs instead of only costing wax
	-- Per-floor overrides for the stats above. Resolved once per spawned body by Logic/ThreatRules,
	-- so everything downstream reads an ordinary ThreatDef and knows nothing about depth.
	depthScaling: ThreatDepthScaling?,
	-- Ears. Absent = deaf, which is every Drawn row: moth logic reads light and nothing else, so
	-- noise never blurs the category tell. See Types/Sound.
	hearing: Sound.HearingProfile?,
}

-- What a threat is currently doing. Decided by ThreatBrain, executed by the server adapter.
-- "Investigate" is a walk to a remembered NOISE POSITION, not a pursuit of a player: it ranks below
-- every real prey read and above Wander, and it ends on its own.
export type ThreatMode = "Wander" | "Stalk" | "Seek" | "Flee" | "Investigate"

-- Live runtime state of one threat instance. Not persisted.
export type ThreatState = {
	id: ThreatId,
	category: ThreatCategory,
	position: Vector3,
	-- Wander anchor. The spawn point to begin with, but the server adapter re-homes a drifting threat
	-- into a connected room when its roam dwell lapses (Config/Threats behavior.roam), so this moves
	-- over a run. A territorial row's anchor is fixed: it IS the territory.
	homePosition: Vector3,
	mode: ThreatMode,
	targetPosition: Vector3?, -- where it is heading, if anywhere
	targetPlayerId: number?, -- player being pursued, if any
	nextThinkAt: number, -- os.clock() time of the next decision
	retreatUntil: number, -- threats ignore prey until this time after being driven off
	-- Sound memory. `investigateUntil` is how long the current noise still holds its attention;
	-- `investigateLoudness` is what that noise scored when it committed, so a quieter follow-up
	-- cannot drag it off a louder one it is already walking to.
	investigateUntil: number,
	investigateLoudness: number,
	-- INTERCEPTION COMMITMENT (rows carrying `intercept`). `interceptUntil` is how long the current
	-- prediction is honoured; while it runs the creature will not re-aim, which is the guarantee that
	-- doubling back beats it. Zero means it is not currently predicting anything.
	interceptUntil: number,
	interceptPosition: Vector3?,
	-- CEILING-STRIKE COOLDOWN (rows carrying `ceilingStrike`). The clock a roof-bound striker may next
	-- act on; kept in state rather than on the adapter so one pass beneath one creature is one event
	-- however many players walk under it.
	strikeReadyAt: number,
}

return {}
