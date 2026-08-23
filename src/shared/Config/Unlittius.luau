--!strict
-- UNLITTIUS — the cave deity boss, and the second authored boss floor (DESIGN §9b).
--
-- HE HAS NO HEALTH, AND THAT IS THE WHOLE ENCOUNTER. The Grub Queen is a resource race counted in
-- sticks of dynamite; Unlittius is counted in LIGHT. Eight dead shrine candles ring his dais, the
-- party lights them one at a time off their own flames, and the eighth banishes him into the ceiling.
-- Nothing a player carries can hurt him and nothing needs to: the fight asks whether you can cross
-- his floor eight times while he is trying to make crossing it expensive.
--
-- WHY THAT FITS A GAME WITH NO COMBAT BETTER THAN SHE DOES. DESIGN §9a had to carve dynamite an
-- exception to make the Queen killable at all. This encounter needs none: lighting a candle is the
-- verb the player has used since floor one (Config/WallLamp), the boss is never attacked, and the win
-- condition is the game's own resource pointed at a door instead of at survival.
--
-- DAMAGE IS IN CANDLES, NOT HIT POINTS. Every `damage` field here is a FRACTION of the player's
-- maximum wax, exactly as `Config.GrubQueen.biteDamage` (0.8) and the falling spire (0.55) are — the
-- handoff package's 0-100 numbers map one-to-one onto this scale (its "38 damage" is 0.38 of a
-- candle). Nothing in this file is an integer health pool; there is no such thing in this game.
--
-- HE LEVITATES, AND HE DOES NOT CHASE. There is no walk cycle, no feet, no Humanoid, no pathfinding and
-- no pursuit of any kind: he is BOUND TO HIS SHRINE and drifts inside an eleven-stud disc around it
-- (`movement.homeRadius`). What that mobility is FOR is angles — a party that puts a pillar between
-- themselves and him has bought cover, not immunity, and he slides until he can throw again. He also
-- backs off anybody who crowds him, because a boulder needs room to be read.
--
-- HE NEVER MOVES TOWARD A DISTANT PLAYER. There is deliberately no "approach" in his intent set:
-- distance is the player's to choose, exactly as it is with the Grub Queen, and the encounter is the
-- room rather than a pursuit across it.
--
-- OWNER DECISION, and a narrow, deliberate softening of the handoff package rather than a reversal of
-- it. The package says "stays centered/rooted over the boss dais" and "do not move the boss across the
-- arena"; the second of those is kept exactly — he never crosses the arena — and the first is relaxed
-- to "stays centred" rather than "welded". A perfectly static boss made cover free: stand behind one
-- column and the Boulder Burst could never answer you again. Eleven studs of slide fixes that without
-- turning him into a chase. Every OTHER movement rule in the package is untouched: no
-- locomotion cycle, mass lags the hands, the head arrives last, no spins, no strafing gait.

export type AttackId = "Dripstone" | "BoulderBurst" | "SummonGnawers" | "Melee"

export type UnlittiusConfig = {
	-- ENCOUNTER
	encounter: {
		-- Eight, and the count is structural rather than tuned: `Logic/UnlittiusRules.power` divides by
		-- it to produce the 0..1 dim step every visual, every audio layer and every cadence band reads.
		candleCount: number,
		-- Seconds a player must hold the prompt at a dead candle. Matched to the wall lamp's room
		-- candle (Config/WallLamp.interaction.roomHoldSeconds) so lighting one of these costs exactly
		-- what lighting the cave has always cost — under fire, which is the whole difference.
		candleHoldSeconds: number,
		-- Server-side acceptance range for a light, in studs. The prompt shows a shorter one; this is
		-- that plus the usual trust slack for a player who took a step during their own round trip.
		candlePromptRange: number,
		candlePositionToleranceStuds: number,
		-- The dais disc, in studs from his root. Nothing is placed inside it and the candles ring it.
		daisRadius: number,
		-- THE BROKEN COLONNADE. Four snapped shrine columns standing between the dais and half of the
		-- candles, at the same bearings as the candles they shield so they never sit in a doorway lane.
		--
		-- THEY ARE COVER, AND COVER IS THE POINT. A chamber with nothing in it makes the Boulder Burst
		-- unanswerable except by running, and makes his own mobility pointless — he only moves because
		-- somebody has put a column between them. Half the candles are shielded and half are in the
		-- open, so which one you go for next is a real decision rather than a lap.
		columnCount: number,
		columnRadius: number,
		columnThickness: number,
		-- The tallest and shortest a column may stand. Varied so the colonnade reads as ruined rather
		-- than installed, and so some of them break line of sight and some only break a boulder.
		columnHeightMin: number,
		columnHeightMax: number,
		-- Toppled drums from the columns that are already gone. Scenery, and a low step to run over.
		rubbleCount: number,
		-- Where the eight candles sit, as a radius from his root. Comfortably outside the dais so that
		-- standing at one is standing in the open, and inside the chamber so all eight are reachable.
		candleRingRadius: number,
		-- Rotation of the whole ring, in degrees, so no candle sits dead ahead of his facing.
		candleRingOffsetDegrees: number,
		-- How far a candle's own light reaches once lit, and how bright. These feed the SAME light
		-- field flames, flares and wall lamps do (server/LightSources), so a lit chamber is really lit:
		-- it pushes dark-hunters out and pulls the Drawn in with no special case in perception.
		candleLightRange: number,
		candleLightIntensity: number,
		-- How long after the eighth candle the encounter is considered complete. Covers the banish
		-- animation plus the relief settling.
		banishSeconds: number,
		-- Reaching the descent ladder requires banishing him, the same narrow exception
		-- `Config.GrubQueen.requiresKillToDescend` makes for her (DESIGN §9a/§9b).
		requiresBanishToDescend: boolean,
		-- How close a player must come before he is announced (EncounterHints) and before he wakes.
		sightingRadius: number,
	},

	-- MOVEMENT. He levitates; nothing here is a walk.
	movement: {
		-- Studs per second, both far under a walking player's 8. `drift` is the slow settle back over his
		-- own shrine; `reposition` is the sidestep he uses to open an angle on somebody who has put a
		-- pillar between them.
		driftSpeed: number,
		repositionSpeed: number,
		-- Studs per second squared. Low: a floating slab of rock does not change its mind quickly, and
		-- the lag between his intent and his motion is most of what sells the mass.
		acceleration: number,
		deceleration: number,
		-- How fast he comes about, in degrees per second. Slower than a player can circle him, which is
		-- what keeps "get behind him" a real answer to the rake exactly as it is for the Grub Queen.
		turnDegreesPerSecond: number,
		-- Inside this, he backs off to make room for a volley. There is deliberately no matching "too
		-- far" band: HE DOES NOT CLOSE ON ANYBODY. Distance is the player's to choose.
		minimumRange: number,
		-- HOW FAR FROM HIS SHRINE HE WILL EVER GO. The whole of his mobility lives inside this disc — he
		-- is bound to the dais and slides around it to get a shot, never across the room after somebody.
		-- Sized so he can see around the chamber pillars without ever arriving at the candle ring.
		homeRadius: number,
		-- Where he STARTS pulling himself back, as a fraction of the leash. The leash itself is a hard
		-- clamp and a clamp is a snap; this is the soft edge inside it where he decides to drift home
		-- under his own power, so in practice the hard clamp never fires and is left as the backstop it
		-- was meant to be.
		recenterFraction: number,
		-- Seconds between lateral drift direction changes, so he does not oscillate on the spot.
		lateralHoldSeconds: number,
		-- How far from the chamber centre he may ever be. Clamped to the room he was built in
		-- (`UnlittiusEncounterService` passes the real radius) less this margin, so he can never end up
		-- inside a wall or out over a doorway.
		wallMargin: number,
		-- He stops dead once an attack has committed. A boss who slid forward through his own telegraph
		-- would make every marked position a lie, and this is the flag that guarantees he cannot.
		freezeDuringAttacks: boolean,
		-- Degrees of torso lean into the direction of travel, at full speed. Small — he is stone.
		leanDegrees: number,
	},

	-- HIS VOICE. He mutters, in a language nobody speaks (owner decision — see the cue block in
	-- `Config/Audio`, which records what this overrides in the original sound brief).
	voice: {
		-- How many `UnlittiusVoiceN` rows exist in `Config/Audio`, and how many `UnlittiusIncantN`.
		-- The behaviour shuffles the first set into a bag and empties it before reshuffling, so every
		-- utterance is heard before any of them repeats.
		lineCount: number,
		incantationCount: number,
		-- Seconds between mutters. Wide, and deliberately not a metronome: a boss who speaks on a
		-- schedule reads as a machine, and the whole point of the muttering is that it sounds like
		-- something thinking rather than something announcing.
		minIntervalSeconds: number,
		maxIntervalSeconds: number,
		-- He does not mutter the instant a player walks in, and he does not mutter over his own
		-- attacks: this is the gap that has to have elapsed since his last action began.
		quietAfterActionSeconds: number,
		-- How far his voice carries relative to the cue's own rolloff, and how much of it survives as
		-- his candles are lit. At full power he is clearly audible across the chamber; by the seventh
		-- candle he is barely muttering at all.
		gainAtFullPower: number,
		gainAtLastCandle: number,
		-- His pitch drops as he weakens, on top of each row's own base speed. A voice that stayed at
		-- the same pitch while its owner was being put out would be the one part of him that never
		-- reacted to the candles.
		pitchAtFullPower: number,
		pitchAtLastCandle: number,
	},

	-- THE ATTACK DIRECTOR
	director: {
		-- Weights for the three ranged/arena options. Melee is deliberately absent: it is a CONDITION
		-- (somebody is inside `melee.triggerRadius`), never a roll.
		weights: { [string]: number },
		-- He will not pick the same major attack a third time running. Two is enough to feel like
		-- pressure; three reads as a broken scheduler.
		repeatLimit: number,
		-- Seconds of downtime between actions, by candles lit. Telegraphs never shorten — only the
		-- gaps between them do, which is the package's own rule and the right one: a faster fight that
		-- is still readable is harder, and a fight with shorter tells is just less fair.
		downtime: {
			early: { min: number, max: number }, -- 0-2 candles
			mid: { min: number, max: number }, -- 3-5
			late: { min: number, max: number }, -- 6-7
		},
		-- The first action never lands the instant a player crosses the threshold.
		openingDelaySeconds: number,
	},

	-- ATTACKS
	dripstone: {
		-- Impact zones, by how many players are on the floor. Never enough to cover the chamber: the
		-- attack is a demand to move, and a demand to move that cannot be answered is just damage.
		zonesSolo: number,
		zonesDuo: number,
		zonesParty: number,
		-- The floor marker is visible for this long before anything lands. Sits between the animation's
		-- own telegraph start (0.10s) and its snap (1.62s), so the marker is always up first.
		telegraphSeconds: number,
		-- Radius of one impact disc, and the wax it costs to be standing in one.
		impactRadius: number,
		damage: number,
		-- Minimum gap between two zones in one volley, so a player is never boxed in by overlap.
		minimumZoneSeparation: number,
		-- How far from a player's feet a zone may be placed. Zones are aimed at where people ARE,
		-- offset outward, so the attack is a push rather than an execution.
		aimSpreadMin: number,
		aimSpreadMax: number,
		-- How far above the floor the stone is spawned. Read as a fall distance by the shared
		-- dripstone presentation (Logic/DripstoneRules.fallDuration).
		ceilingClearance: number,
	},

	boulder: {
		-- EXACTLY TWO. Not a tuning knob in any real sense — the whole read of the attack is "he
		-- conjures two stones and throws them" — but it lives here so the spacing below has something
		-- to be a spacing between.
		count: number,
		-- Seconds between shot one and shot two.
		shotSpacing: number,
		-- Where they materialise: outboard of each shoulder, above chest height, and forward, so neither
		-- the conjure nor the flight path can pass through his own torso. MEASURED, not chosen: his
		-- shoulders span 4.74 studs and his clearance cylinder is 3.2, and a sweep of every target bearing
		-- (Tests/UnlittiusRulesTests) puts the worst-case approach of a shoulder-fired stone at 3.39 studs
		-- with these offsets. Reduce either one and the stone starts grazing him at oblique angles.
		spawnOutboard: number,
		spawnHeight: number,
		spawnForward: number,
		-- HE WILL NOT THROW A BOULDER AT SOMEBODY THIS CLOSE. Below it the geometry is unwinnable: a
		-- target six studs away and behind him cannot be hit from EITHER shoulder without the flight path
		-- crossing his own body, whatever the attachments are moved to. That is not a bug to engineer
		-- around, it is the range at which the answer is the claw rake instead — so the burst retargets to
		-- somebody further out, and only falls back to a close target when there is nobody else at all.
		minimumEngagementRange: number,
		-- Seconds the stone spends growing from a fragment to full size before it can fire.
		conjureSeconds: number,
		radius: number,
		speed: number,
		maxDistance: number,
		damage: number,
		-- Aim lead, in seconds of the target's own horizontal velocity, and the speed that prediction
		-- is clamped to. A sprinting player is led; a player abusing a launcher is not.
		predictionSeconds: number,
		predictionMaxSpeed: number,
		-- Shove applied on a hit, in studs per second. Small: this is a stagger, not a launch.
		knockback: number,
	},

	summon: {
		-- Gnawers per summon, by party size, and the live cap on boss-summoned bodies. Existing Stone
		-- Gnawers (Config/StoneGnawer) with their existing brain — he only asks for them.
		countSolo: number,
		countDuo: number,
		countParty: number,
		activeCap: number,
		-- Where they arrive: a ring around the dais, far enough out that one never surfaces on top of
		-- a player who is lighting a candle.
		spawnRadiusMin: number,
		spawnRadiusMax: number,
		-- Minimum seconds between summons regardless of what the director rolls.
		cooldownSeconds: number,
	},

	melee: {
		-- Inside this radius of his root, the double rake becomes the strongly preferred action. It is
		-- the anti-camping rule and nothing else: the dais is not a safe place to stand.
		triggerRadius: number,
		-- The rake's own reach and half-angle at contact. `arcDot` is the cosine of the half-angle —
		-- 0.20 is about 78 degrees off his facing per side, so the pair of swipes covers his front.
		reach: number,
		arcDot: number,
		damagePerSwipe: number,
		-- The second swipe shoves. The first deliberately does not: being hit once should be a warning
		-- you can walk out of.
		knockbackSecondSwipe: number,
		-- The only translation he is ever allowed, in studs.
		maxRootLunge: number,
		-- Seconds before he will rake again, so a player pinned against the dais is punished once and
		-- then given the chance to leave.
		cooldownSeconds: number,
	},

	-- THE BODY (shared/Enemies/Unlittius). Silhouette knobs only: anything that decides where a part
	-- goes lives in the builder, and anything that decides how the fight plays lives above.
	body: {
		-- Studs from the lowest floating base stone to the hood tip. The master spec's 11-12.5 band.
		-- `Enemies/Unlittius.build` measures itself against this and scales the finished rig to hit it,
		-- so the proportions stay as authored while the overall size stays a single number here.
		targetHeight: number,
		-- How far his root floats above the dais surface. MEASURED, not chosen: his talons hang 5.5 studs
		-- below his root at rest (shared/Enemies/Unlittius), so anything less than six studs has him
		-- standing his own claws in the rock, and the fitted collider that stops players walking under
		-- him ends up buried with them.
		hoverHeight: number,
		-- The idle bob, in studs and cycles per second. Small on purpose: he is stone.
		hoverAmplitude: number,
		hoverFrequency: number,
		-- Loose stones orbiting the floating base. 5-7 per the package; more reads as debris.
		orbitStoneCount: number,
		orbitRadius: number,
		orbitSpeed: number,
		-- Cape panels. Broad slabs, never narrow strips.
		capePanelCount: number,
		-- The violet the rune, eyes and cracks are lit in at full power.
		runeColor: Color3,
		-- Rune brightness at 0 candles and at 7. The eighth takes it to zero during the banish.
		runeBrightnessFull: number,
		runeBrightnessLast: number,
		-- The chest rune's PointLight at full power. Deliberately short-ranged: he is a landmark in a
		-- dark room, not a lamp that lights it.
		runeLightRange: number,
		runeLightBrightness: number,
	},

	-- THE BANISH, in seconds along its own timeline. Mirrors 03_ANIMATION/ANIMATION_BLUEPRINT.md.
	banish: {
		unbindSeconds: number, -- rune destabilises, arms spread
		riseSeconds: number, -- the pull toward the ceiling
		alignSeconds: number, -- rolls flat against the ceiling plane
		reliefSwapAt: number, -- the live rig is swapped for the anchored relief
		completeAt: number,
		-- HIS LAST TWO UTTERANCES, on the banish's own clock. The cry lands just after the rune comes
		-- apart — he has understood what is happening to him — and the last word four fifths of a second
		-- before the stone closes, so the seal audibly cuts it off. Both must fall inside the sequence
		-- and before `reliefSwapAt`, which `Tests/UnlittiusRulesTests` pins.
		cryAt: number,
		lastWordAt: number,
		-- How far below the ceiling the relief is embedded, in studs.
		ceilingInset: number,
	},

	-- ANIMATION TIMELINE. Every one of these is read by the server as the AUTHORITY on when a hit
	-- happens — the rig is animated by this game's own keyframe evaluator (shared/Enemies/EnemyKit),
	-- not by a published Roblox AnimationTrack, so there are no animation markers to trust and no
	-- asset ids to fill in. The names match the package's marker names exactly so the two documents
	-- can be read side by side.
	timings: {
		idleLength: number,
		dripstoneLength: number,
		dripstoneSnapAt: number,
		boulderLength: number,
		boulderConjureAt: number,
		boulderFire1At: number,
		boulderFire2At: number,
		summonLength: number,
		summonSpawnAt: number,
		meleeLength: number,
		meleeHit1At: number,
		meleeHit2At: number,
		recoilLength: number,
		recoilImpactAt: number,
		banishLength: number,
	},
}

local Unlittius: UnlittiusConfig = {
	encounter = {
		candleCount = 8,
		-- The wall lamp's own room-candle hold. Long enough to be a commitment while a boulder is in
		-- the air, short enough that eight of them is a fight rather than an errand.
		candleHoldSeconds = 2.0,
		candlePromptRange = 8,
		candlePositionToleranceStuds = 4,
		-- THE RADIAL BUDGET, measured against the room the floor builder can actually carve: one grid
		-- cell, whose open interior reaches 30 studs from the centre (RoomFootprint.maximumHalfExtent).
		-- Everything below has to fit inside that with walking room left over, and
		-- `Tests/UnlittiusRulesTests` pins the whole ladder:
		--
		--     dais 9  <  leash 11  <  columns 14.5  <  candles 20  <  wall 30
		--
		-- which leaves ~9 studs of lap OUTSIDE the candle ring and 11 studs of open floor between the
		-- dais and the ring. The first pass sized these for the 104-stud developer arena and left only
		-- seven studs behind the candles on a real floor, which is a corridor rather than a lap.
		daisRadius = 9,
		-- Four columns, on every other candle bearing: outside the dais, well inside the candle ring, and
		-- on bearings 22.5 degrees off every cardinal so no column can ever stand in a doorway.
		columnCount = 4,
		columnRadius = 14.5,
		columnThickness = 2.6,
		-- Between a head-height stump and a column tall enough to hide a standing player from a boss
		-- floating six studs up.
		columnHeightMin = 5.5,
		columnHeightMax = 11,
		rubbleCount = 7,
		candleRingRadius = 20,
		candleRingOffsetDegrees = 22.5,
		candleLightRange = 26,
		candleLightIntensity = 0.85,
		banishSeconds = 3.4,
		requiresBanishToDescend = true,
		-- HOW CLOSE SOMEBODY HAS TO BE BEFORE HE IS AWAKE, measured from his CHEST rather than the dais
		-- — he floats six studs up and stands twelve, so a third of this is spent on height before it
		-- buys any ground at all.
		--
		-- IT WAS 55 AND HIS CHAMBER IS 64 ACROSS. Sixty-four across means thirty-two from the middle to
		-- a wall and forty-five to a corner, and once his height is taken out of a 55-stud sphere the
		-- flat reach left is about 53 — so a player standing in his own doorway, watching him, was
		-- outside it. What that looks like is a boss who does not move, does not turn, does not speak
		-- and does not attack: `awake` gates the director and the muttering, and the same distance
		-- decides whether anyone is a participant to turn toward. It is indistinguishable from broken,
		-- and it was reported as broken.
		--
		-- 120 is the whole chamber, both vigil doorways and the length of either leg. He is a god
		-- embedded in the room the party is walking into; there is no version of this fight where he
		-- has not noticed them yet.
		sightingRadius = 120,
	},

	movement = {
		-- A quarter of a walk and a half of one. Against `Config.Movement.walkSpeed` (8) and a run of
		-- 16, both are hopeless as a pursuit and that is the point — the same reasoning
		-- `Config.GrubQueen.crawlSpeed` writes out at length, at a speed appropriate to something that
		-- is being carried rather than dragging itself.
		driftSpeed = 2.2,
		repositionSpeed = 3.4,
		-- Two and a half seconds from a standstill to his advance speed, and a shade quicker to stop.
		acceleration = 1.8,
		deceleration = 2.6,
		-- Nine seconds to come about. The counter to the rake, and deliberately generous.
		turnDegreesPerSecond = 40,
		minimumRange = 9,
		-- Eleven studs of slide around a shrine whose candles ring him at twenty: enough to clear a column
		-- and change an angle, never enough to reach the ring or to follow anybody to it.
		homeRadius = 11,
		recenterFraction = 0.8,
		lateralHoldSeconds = 3.5,
		wallMargin = 6,
		freezeDuringAttacks = true,
		leanDegrees = 6,
	},

	voice = {
		lineCount = 12,
		incantationCount = 2,
		-- Roughly one utterance every ten to twenty seconds, which across a full eight-candle fight is
		-- enough to hear most of the twelve without any of them coming round twice.
		minIntervalSeconds = 9.5,
		maxIntervalSeconds = 19,
		quietAfterActionSeconds = 2.2,
		gainAtFullPower = 1,
		gainAtLastCandle = 0.35,
		pitchAtFullPower = 1,
		pitchAtLastCandle = 0.82,
	},

	director = {
		weights = {
			Dripstone = 34,
			BoulderBurst = 32,
			SummonGnawers = 22,
		},
		repeatLimit = 2,
		downtime = {
			early = { min = 2.2, max = 3.0 },
			mid = { min = 1.9, max = 2.6 },
			late = { min = 1.6, max = 2.3 },
		},
		openingDelaySeconds = 2.6,
	},

	dripstone = {
		zonesSolo = 4,
		zonesDuo = 5,
		zonesParty = 6,
		-- 1.5s of marker, against the animation's 1.62s from telegraph to snap. The marker is up
		-- BEFORE the arms finish rising, which is the package's explicit requirement.
		telegraphSeconds = 1.5,
		impactRadius = 2.9,
		-- Between the Longarm's grab (0.55) and a Wax Grub's nibble. Two of these is most of a candle;
		-- one is a mistake you walk away from.
		damage = 0.36,
		minimumZoneSeparation = 7,
		aimSpreadMin = 2,
		aimSpreadMax = 9,
		ceilingClearance = 22,
	},

	boulder = {
		count = 2,
		shotSpacing = 0.24,
		spawnOutboard = 4.6,
		spawnHeight = 1.1,
		spawnForward = 3.6,
		minimumEngagementRange = 12,
		conjureSeconds = 0.6,
		radius = 2.0,
		speed = 42,
		maxDistance = 52,
		damage = 0.32,
		predictionSeconds = 0.16,
		predictionMaxSpeed = 30,
		knockback = 28,
	},

	summon = {
		countSolo = 1,
		countDuo = 2,
		countParty = 2,
		activeCap = 4,
		spawnRadiusMin = 14,
		spawnRadiusMax = 24,
		cooldownSeconds = 22,
	},

	melee = {
		triggerRadius = 10,
		-- His talons already reach four studs past his wrist and his arms hang wide, so this is the
		-- claw's own arc rather than a lunge out of nowhere.
		reach = 11,
		arcDot = 0.2,
		-- Two of these is 0.42 of a candle — worse than a dripstone and less than the Queen's bite.
		-- Standing under him should be the most expensive place in the room and never an instant loss.
		damagePerSwipe = 0.21,
		knockbackSecondSwipe = 24,
		maxRootLunge = 1.4,
		cooldownSeconds = 3.2,
	},

	body = {
		targetHeight = 11.8,
		hoverHeight = 6.4,
		hoverAmplitude = 0.18,
		hoverFrequency = 0.55,
		orbitStoneCount = 6,
		orbitRadius = 2.6,
		orbitSpeed = 0.42,
		capePanelCount = 5,
		runeColor = Color3.fromRGB(138, 92, 240),
		runeBrightnessFull = 1,
		runeBrightnessLast = 0.12,
		runeLightRange = 18,
		runeLightBrightness = 1.6,
	},

	banish = {
		unbindSeconds = 0.45,
		riseSeconds = 1.25,
		alignSeconds = 2.3,
		reliefSwapAt = 3.2,
		completeAt = 3.4,
		cryAt = 0.15,
		lastWordAt = 2.8,
		ceilingInset = 1.4,
	},

	timings = {
		idleLength = 6.0,
		dripstoneLength = 2.6,
		dripstoneSnapAt = 1.62,
		boulderLength = 2.45,
		boulderConjureAt = 0.18,
		boulderFire1At = 0.92,
		boulderFire2At = 1.16,
		summonLength = 3.05,
		summonSpawnAt = 1.42,
		meleeLength = 1.55,
		meleeHit1At = 0.56,
		meleeHit2At = 0.82,
		recoilLength = 1.7,
		recoilImpactAt = 0.1,
		banishLength = 3.4,
	},
}

return Unlittius
