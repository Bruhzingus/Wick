--!strict
-- Raw Wax deposit interaction. Standard, Twin, Deep, Dim, and Bright rows share one authoritative
-- strike language while varying exposure, yield, helper payout, and burn requirement. Row access is
-- unlocked through the Lamp Network; carried Raw Wax remains separate from living Wax and is valued
-- only through the extraction path.
--
-- WHAT A BREAK IS WORTH lives in `Config/Extraction`, not here. This file owns only the interaction —
-- how a seam is worked, where one may sit, and what it looks like. The one exception is
-- `waxPerPerfectStrike` below, which is a property of the SWING rather than of the economy.
--
-- THE INTERACTION, in one paragraph: standing near a deposit puts a pickaxe in your hands. Clicking
-- the seam plants you and opens a continuous fracture rail; each further click swings at its bright
-- core. A clean strike advances by the current row's authored share; a fumble is worth less AND is
-- louder, so a player who cannot hit the window spends more time making more noise.
-- Nothing about the swing damages a threat: the pickaxe has no hitbox and never will.
--
-- WHAT IT COSTS: no wax. The price of a deposit is time standing still in one place, planted,
-- with an uncovered flame, making noise the dark can hear (Config/Sound). If mining turns out to be
-- reflexive rather than a decision, add the cost here — do not add a weapon.

-- ONE SHARED SEAM LANGUAGE. Rows beyond `Standard` are sold by the Lamp Network (Config/LampNetwork) and are
-- selected per deposit by Logic/MiningRules; a floor's deposit COUNT is unaffected by which rows are
-- unlocked, so buying a seam node changes WHAT you find and never HOW MUCH.
--
-- THE PAY RATE IS THE DIAL EVERY ROW IS BALANCED ON: `units / cleanStrikes`. Standard is 2/3 = 0.67
-- units per clean strike, and any row that beats that has to pay for it with exposure the player can
-- see and read, never with a bigger number alone.
export type DepositRow = {
	id: string,
	displayName: string,
	-- Relative weight among the rows that are unlocked AND eligible at this depth. Only meaningful
	-- against its siblings; a row alone at its depth is chosen whatever its weight.
	weight: number,
	minDepth: number,
	-- Clean strikes to break. Drives per-strike progress (1 / cleanStrikes), so this is the only place
	-- a row's length is stated.
	cleanStrikes: number,
	-- Raw Wax units granted to EACH paid miner. Not split between them — see `maxPaidMiners`.
	units: number,
	-- How many miners one break may pay. 1 for every ordinary seam. Above 1 makes the row genuinely
	-- co-operative: the strike count stays the same however many people work it, so two miners each
	-- doing half the work are each paid in full.
	maxPaidMiners: number,
	-- Fraction of the game's MAXIMUM burn rate that must be held to land a strike. 0 = any brightness.
	--
	-- Compared against the unmodified `Config/Light.maxBurnRate`, never against the player's own
	-- capped maximum — otherwise a candle that sacrificed its brightness ceiling at the Basin would
	-- still qualify at 90% of its reduced cap, and the sacrifice would have cost it nothing here.
	minBurnFraction: number,
	-- Fraction of the game's MAXIMUM burn rate the flame must stay at or below. 1 = no upper limit.
	-- Together with `minBurnFraction`, this turns the light dial into an authored working window.
	maxBurnFraction: number,
	-- The Lamp Network node that sells this row, or nil for the row everybody always has.
	unlockNode: string?,
}

export type MiningConfig = {
	enabled: boolean,
	rows: { DepositRow },
	deposit: {
		modelId: string,
		displayName: string,
		interactionRange: number,
		promptViewDot: number,
		requiresLineOfSight: boolean,
		requiresLit: boolean,
		requiresUncoveredFlame: boolean,
		strikeCooldownSeconds: number,
		swingWindupSeconds: number,
		swingTimeoutSeconds: number,
		movementSpeedMultiplier: number,
		waxPerPerfectStrike: number,
	},
	timing: {
		sweepSeconds: number,
		perfectCenter: number,
		bandWander: number,
		perfectHalfWidth: number,
		goodHalfWidth: number,
		goodFractionOfPerfect: number,
		missFractionOfPerfect: number,
		maxInputRewindSeconds: number,
		inputFutureToleranceSeconds: number,
	},
	placement: {
		minDepth: number,
		depositCounts: { { maxDepth: number, weights: { number } } },
		maxPerFloor: number,
		placementAttempts: number,
		footprint: number,
		standingClearance: number,
		wallInsetMin: number,
		wallInsetMax: number,
		wallLateralRange: number,
		minHazardSeparation: number,
		minThreatSeparation: number,
	},
	visual: {
		rockSize: Vector3,
		seamCountMin: number,
		seamCountMax: number,
		seamSize: Vector3,
		rockColor: Color3,
		rockAccent: Color3,
		waxColor: Color3,
		waxDeepColor: Color3,
		spentColor: Color3,
		promptHeight: number,
		surfaceEmbed: number,
		surfaceEmbedJitter: number,
		shape: {
			sizeJitterMin: number,
			sizeJitterMax: number,
			pedestalMin: number,
			pedestalMax: number,
			tiltRadians: number,
			yawRadians: number,
			shoulderCountMin: number,
			shoulderCountMax: number,
			spurChance: number,
			seamClusterSpread: number,
			sideSeamChance: number,
		},
		glow: {
			color: Color3,
			range: number,
			nearDistance: number,
			minTransparency: number,
			thickness: number,
			fadePerSecond: number,
		},
	},
	pickaxe: {
		headSize: Vector3,
		prongSize: Vector3,
		collarSize: Vector3,
		handleSize: Vector3,
		gripSize: Vector3,
		gripCount: number,
		gripSpacing: number,
		headColor: Color3,
		headEdgeColor: Color3,
		handleColor: Color3,
		gripColor: Color3,
		restOffset: CFrame,
		raisedOffset: CFrame,
		anticipationOffset: CFrame,
		strikeOffset: CFrame,
		reboundOffset: CFrame,
		glanceOffset: CFrame,
		breakOffset: CFrame,
		raiseSeconds: number,
		anticipationSeconds: number,
		swingSeconds: number,
		impactSeconds: number,
		reboundSeconds: number,
		recoverSeconds: number,
		bobStuds: number,
		bobSeconds: number,
		swayDegrees: number,
		trailColor: Color3,
		trailLifetime: number,
		trailWidthScale: number,
		aimScreenOffsetStuds: Vector2,
		aimYawDegrees: number,
		aimPitchDegrees: number,
		idleAimFraction: number,
	},
	qte: {
		position: UDim2,
		widthPixels: number,
		heightPixels: number,
		trackThicknessPixels: number,
		goodBandHeightPixels: number,
		perfectBandHeightPixels: number,
		markerSize: Vector2,
		enterScale: number,
		enterSeconds: number,
		exitSeconds: number,
		requestTimeoutSeconds: number,
		shakeDuration: number,
		shakeMagnitudePixels: number,
	},
	feedback: {
		comboPitchStep: number,
		comboPitchMax: number,
		hintSeconds: number,
		cargoPulseScale: number,
		impactDebrisCount: number,
		impactDebrisLifetime: number,
		impactDebrisSpeed: number,
		impactDebrisUpSpeed: number,
		impactDebrisSizeMin: number,
		impactDebrisSizeMax: number,
		impactPresentationRange: number,
	},
}

local Mining: MiningConfig = {
	enabled = true,

	rows = {
		{
			-- The seam everybody has, and the rate every other row is measured against.
			id = "Standard",
			displayName = "Raw Wax",
			weight = 100,
			minDepth = 1,
			cleanStrikes = 3,
			units = 2,
			maxPaidMiners = 1,
			minBurnFraction = 0,
			maxBurnFraction = 1,
			unlockNode = nil,
		},
		{
			-- TWIN SEAM. Two working faces, and the same six clean strikes to break however many people
			-- swing at it — so two miners each doing three are each paid in full, and one miner doing all
			-- six is paid once. Solo it is strictly worse than a Standard seam (half the rate for double
			-- the time planted); with a friend it is the same rate for double the floor's income.
			--
			-- That asymmetry IS the purchase. It is never a trap, because a solo player can simply walk
			-- past it, and it is never mandatory, because the floor's other seams are unaffected.
			id = "Twin",
			displayName = "Twin Seam",
			weight = 45,
			minDepth = 1,
			cleanStrikes = 6,
			units = 2,
			maxPaidMiners = 2,
			minBurnFraction = 0,
			maxBurnFraction = 1,
			unlockNode = "lamp.twin_seam",
		},
		{
			-- DEEP SEAM. Exactly the Standard pay rate (6/9 = 2/3), so the reward is not the rate — it is
			-- that the units exist at all on a floor this deep. What it costs is one unbroken block of
			-- roughly twelve seconds planted, lit and uncovered, which on floor 6+ is a long time to
			-- be a stationary light with your back to the room.
			id = "Deep",
			displayName = "Deep Seam",
			weight = 40,
			minDepth = 6,
			cleanStrikes = 9,
			units = 6,
			maxPaidMiners = 1,
			minBurnFraction = 0,
			maxBurnFraction = 1,
			unlockNode = "lamp.deep_seam",
		},
		{
			-- DIM SEAM. A short, cool seam that pays three units for four clean strikes, but turns
			-- hostile light management into its key: the miner must stay lit and uncovered while
			-- keeping the dial below roughly one third. A Flare locks it out instead of bypassing it.
			id = "Dim",
			displayName = "Dim Seam",
			weight = 30,
			minDepth = 1,
			cleanStrikes = 4,
			units = 3,
			maxPaidMiners = 1,
			minBurnFraction = 0,
			maxBurnFraction = 0.35,
			unlockNode = "lamp.dim_seam",
		},
		{
			-- BRIGHT SEAM. Double the Standard rate (4/3) for roughly four seconds as the brightest thing in
			-- the cave, immobile, at the top of the dial where the Drawn can read you across the whole
			-- floor. This is the burning-vine idea applied to mining: the dial becomes a key rather than
			-- only a lighting trade.
			--
			-- A Basin brightness cap locks a candle out of these entirely, and that is deliberate — it is
			-- the sacrifice having a consequence a player can point at. A teammate without the cap can
			-- work the seam beside them.
			id = "Bright",
			displayName = "Bright Seam",
			weight = 30,
			minDepth = 1,
			cleanStrikes = 3,
			units = 4,
			maxPaidMiners = 1,
			-- Just under the dial's ceiling so a thumb on a mobile slider can hold it, and a Flare — which
			-- pushes well past the dial — always qualifies.
			minBurnFraction = 0.9,
			maxBurnFraction = 1,
			unlockNode = "lamp.bright_seam",
		},
	},
	deposit = {
		modelId = "RawWaxDeposit",
		displayName = "Raw Wax",
		-- Close enough that you are committed to this spot. Deliberately tighter than the loot
		-- pickup range (7): mining is standing AT the seam, not near it.
		interactionRange = 6.5,
		-- Only offer the interaction for a seam the player is actually examining. Authority still
		-- comes from the server's independent reach and obstruction checks.
		promptViewDot = 0.56,
		requiresLineOfSight = true,
		-- You cannot mine in the dark. This is what makes a deposit expose you to the Drawn as well
		-- as to anything listening: you have to be burning to work.
		requiresLit = true,
		-- ...and you cannot cup the flame down to hide while you do it.
		requiresUncoveredFlame = true,
		-- Recovery between strikes: the pick has to come back up. The next sweep starts when this
		-- ends, so the rhythm is strike → recover → sweep → strike, and the loop has a beat.
		strikeCooldownSeconds = 0.55,
		-- Dead time at the top of each sweep before the marker starts moving. Gives the rail a
		-- readable "here it comes" beat rather than the marker already being in motion.
		swingWindupSeconds = 0.14,
		-- How long a stance may go without a strike before it releases on its own. Long enough to
		-- look at what is walking toward you; short enough that a player who tabs out is not left
		-- rooted to a rock.
		swingTimeoutSeconds = 6,
		-- Movement commitment. Working a seam is a LOCKED stance: while engaged you are planted, and
		-- any movement input immediately ends the stance instead of moving you slowly. Leaving is
		-- always one keypress away — but you cannot mine and reposition at the same time, and the
		-- moment you decide to move you have stopped mining.
		movementSpeedMultiplier = 0,
		-- THE SHARDS. A clean strike shatters wax out of the seam, and some of it lands on you and
		-- stays there — a small, real gain in your candle for hitting the window properly.
		--
		-- ONLY perfect strikes pay it. A fumble sprays nothing, so this rewards reading the rail
		-- rather than grinding a rock, and it cannot be farmed by mashing.
		--
		-- WHY THIS NUMBER IS SMALL: a full candle is 1.3 wax (Config/Wax), and traversing a whole floor
		-- costs roughly 0.07. The design margin is that a well-mined floor very nearly pays for itself
		-- in wax and a badly-mined one is a net loss. Much past ~0.03 per strike and the game inverts
		-- into a wax fountain where a good miner never watches the meter again, which would quietly
		-- delete the resource the entire game is built on (see TUNING).
		--
		-- CUT FROM 0.025 WHEN FLOORS GAINED MULTIPLE SEAMS. The old value was tuned against exactly one
		-- seam per floor: 3 strikes x 0.025 = 0.075 returned against 0.07 spent. Once a deep floor can
		-- carry 3.15 seams on average, that same value returns 0.236 per floor — precisely the fountain
		-- the paragraph above exists to forbid. At 0.012 the return by depth band is
		-- 0.023 / 0.040 / 0.050 / 0.085 / 0.113 against the same ~0.07 cost. Shallow floors are a net
		-- wax loss; optional deep detours now offer a deliberate wax surplus alongside higher currency.
		-- Deep seam density rose after the original calculation. At this unchanged grant, fully Perfect
		-- Floors 7-9 / 10+ return about 0.085 / 0.113 Living Wax; playtests must keep that optional
		-- recovery from turning into a risk-free loop.
		waxPerPerfectStrike = 0.012,
	},
	timing = {
		-- One full pass of the marker across the rail. Fast enough to demand attention, slow enough
		-- that a phone thumb can hit it.
		sweepSeconds = 1.15,
		-- Where the target band sits in the sweep, as a fraction of one pass. Off-centre so the
		-- rhythm cannot be learned as "release halfway".
		perfectCenter = 0.62,
		-- How far the band deterministically wanders from that centre, strike to strike. The whole
		-- reason it exists: with a fixed band and a continuously sweeping rail, mining would collapse
		-- into a metronome you could hit with your eyes closed. Wandering keeps every strike a read.
		-- 0 pins the band and makes the loop learnable-by-rhythm; above ~0.4 it stops feeling fair.
		bandWander = 0.28,
		-- Half-widths, also as a fraction of a pass. Perfect is ~9% of the sweep (about 52 ms each
		-- side); Good is the forgiving shoulder around it.
		perfectHalfWidth = 0.045,
		goodHalfWidth = 0.13,
		-- PROGRESS PER SWING, expressed as fractions OF A CLEAN STRIKE rather than of the deposit.
		--
		-- A clean strike is worth `1 / row.cleanStrikes`, so these two numbers are the only thing that
		-- has to be stated once for every row: a 3-strike Standard seam and a 9-strike Deep Seam both
		-- forgive a fumble by the same proportion, and adding a row cannot accidentally change how
		-- punishing its strike read is.
		--
		-- These reproduce the previous absolute values exactly for a 3-strike seam (0.66 x 1/3 = 0.22,
		-- 0.3 x 1/3 = 0.1), so the Standard seam is bit-for-bit what it always was.
		goodFractionOfPerfect = 0.66,
		-- A miss still chips the seam. Grinding is allowed; it is simply slow and loud.
		missFractionOfPerfect = 0.3,
		-- The client reports the shared Workspace clock sampled at the physical click. Authority
		-- accepts only a small, bounded rewind from packet arrival: enough to remove ordinary
		-- one-way latency from a 100 ms timing aperture, never enough to invent an old strike.
		maxInputRewindSeconds = 0.22,
		inputFutureToleranceSeconds = 0.04,
	},
	placement = {
		-- Eligible from the first floor: mining needs the most playtest samples it can get, and it
		-- teaches alongside the dial rather than after it.
		minDepth = 1,
		-- HOW MANY SEAMS A FLOOR CARRIES, by global depth. `weights[i]` is the relative weight of
		-- carrying exactly `i - 1` deposits, so `{35, 65}` reads "35 chance of none, 65 of one".
		-- Depths past the final row use the final row (the same convention as Config/Depth.bands).
		--
		-- THIS REPLACED A FLAT 65% CHANCE OF EXACTLY ONE SEAM AT EVERY DEPTH. A flat rate made a
		-- deposit a thing you either found or did not, identically on floor 1 and floor 12, which meant
		-- the mining layer contributed nothing to the depth push the rest of the economy is built on.
		-- Now a shallow floor usually carries one seam or none and a deep floor usually carries two or
		-- three, with a rare fourth seam at the deepest band, so descending changes how much there is to
		-- work as well as what a unit is worth.
		--
		-- The note that used to sit here said a second deposit "turns a detour into a route". That was
		-- the right worry, and it is answered structurally rather than by a cap: the placement loop
		-- below takes at most ONE deposit per room, across distinct off-route rooms, so every seam stays
		-- a separate detour rather than becoming a line the player walks.
		--
		-- Expected counts by band: 0.65 / 1.10 / 1.40 / 2.35 / 3.15. Floors 1-6 are deliberately
		-- unchanged; the two deep bands gain 27% and 29% respectively. `unitsPerDeposit`
		-- (Config/Extraction) dropped from 3 to 2 in the same change; without that, deep income roughly
		-- triples. With it, a 5-floor Shallows run still pays ~149 against the ~152 TUNING measured,
		-- and only the deep end gets richer. Full derivation in LAMP-NETWORK.md §6.
		depositCounts = {
			{ maxDepth = 3, weights = { 35, 65 } },
			{ maxDepth = 4, weights = { 20, 50, 30 } },
			{ maxDepth = 6, weights = { 0, 60, 40 } },
			{ maxDepth = 9, weights = { 0, 0, 65, 35 } },
			{ maxDepth = 10, weights = { 0, 0, 0, 85, 15 } },
		},
		-- ABSOLUTE ceiling, not a balance lever — the weights above decide the real count. This clamps
		-- them, so a mistyped weight row can never ask the planner for eight seams.
		maxPerFloor = 4,
		placementAttempts = 24,
		-- Footprint reserved for the seam itself, and the dry standing room a player needs in front
		-- of it. Both are checked against water before a spot is accepted.
		footprint = 6,
		standingClearance = 7,
		-- Deposits sit against a wall, like loot pockets, so approaching one means leaving the
		-- middle of the room and putting your back to it.
		--
		-- THE RANGE IS CHOSEN SO EVERY ROLL IS ALREADY LEGAL. A seam reserves a 14-stud box (the seam
		-- plus its standing room, widened by the probe's voxel margin), and the analytic room boundary
		-- sits 30 studs out, so a placement is contained only within 23 studs of the centre. The old
		-- 5..11 inset rolled the seam 21..27 studs out — over half of it outside that bound — and every
		-- one of those rolls had to be walked back inward by `anchorInside`, which cost about a third of
		-- all placement attempts and pushed accepted seams into the eroded side-wall band where the
		-- shaped-room voxels are least reliable. 9..15 rolls 17..23 studs: still unmistakably against the
		-- rock, never out on the walking line, and legal on the first try.
		wallInsetMin = 9,
		wallInsetMax = 15,
		wallLateralRange = 22,
		-- Clear of pools and unstable formations: a player committed to a swing must never be
		-- standing under something that is about to fall.
		minHazardSeparation = 9,
		-- ...and never within arm's reach of where a threat starts the floor.
		minThreatSeparation = 14,
	},
	visual = {
		-- A low boulder shouldered into the wall, with wax seams showing through fractures. Reads as
		-- geology first, resource second — no glow, no outline, no floating icon.
		-- The BASE dimensions. Every deposit jitters them per-seed (see `shape`), so this is the
		-- silhouette's average rather than the silhouette every rock actually gets.
		rockSize = Vector3.new(5.2, 3.4, 3.6),
		seamCountMin = 3,
		seamCountMax = 6,
		seamSize = Vector3.new(1.5, 0.5, 0.42),
		rockColor = Color3.fromRGB(52, 56, 66),
		rockAccent = Color3.fromRGB(62, 66, 78),
		-- The one warm note in a cold palette. Amber rather than the candle's pale cream: this is wax
		-- still in the rock, not wax already rendered into a body, and the difference in tone is what
		-- lets a seam register as a THING at the edge of a candle's reach instead of as pale stone.
		waxColor = Color3.fromRGB(236, 176, 92),
		waxDeepColor = Color3.fromRGB(188, 124, 48),
		-- A depleted seam goes cold and dark. The rock stays: the floor keeps its geometry.
		spentColor = Color3.fromRGB(45, 49, 59),
		promptHeight = 2.6,
		-- How far the SKIRT sinks into the resolved ground. Only the skirt: the seam-bearing mass now
		-- stands on top of it (see `shape.pedestal*`), which is what actually fixed deposits reading
		-- as buried. Lifting the whole rock instead would have left it hovering with daylight under
		-- it, because the ground the probe finds is one point and the terrain around it is not flat.
		surfaceEmbed = 0.3,
		surfaceEmbedJitter = 0.25,
		-- Per-deposit silhouette variation. All of it is driven from the placement's visual seed, so a
		-- floor rebuilt from the same plan produces the same rocks — this is variety, not noise.
		shape = {
			-- Per-AXIS scale of `rockSize`, so deposits differ in proportion and not just in bulk.
			sizeJitterMin = 0.82,
			sizeJitterMax = 1.24,
			-- How far the seam-bearing mass is raised above the ground, in studs. The skirt beneath it
			-- takes the burial so the wax does not: cave floors are relief, not a plane, and a seam band
			-- sitting a stud higher is the difference between "an outcrop" and "a rock in a hole".
			pedestalMin = 0.7,
			pedestalMax = 1.5,
			-- Lean of the whole mass. Small: a boulder tipped much further reads as physics debris.
			tiltRadians = 0.13,
			-- Twist away from square-on. Kept tight because the seam face has to stay readable from
			-- the side a player approaches from.
			yawRadians = 0.2,
			shoulderCountMin = 2,
			shoulderCountMax = 4,
			-- Odds of an extra chunk on the crown, which is what breaks up the flat-slab top.
			spurChance = 0.6,
			-- How far along its fracture line the seams string out, as a fraction of the rock face. The
			-- seams of one deposit belong to ONE crack, rather than being scattered independently.
			seamClusterSpread = 0.34,
			-- Odds that a deposit puts one seam around a side face instead of all of them out front.
			sideSeamChance = 0.35,
		},
		-- The proximity ember. A local, client-only warmth that comes up as you close on a seam, so a
		-- deposit stands out once you are near it without ever becoming a beacon across a dark room.
		-- It is presentation only: no PointLight, so it changes nothing about what threats can see.
		glow = {
			-- Warm gold, deliberately pulled AWAY from red: high green relative to red (ratio ~1.35)
			-- reads as candlelight/amber rather than embers or hazard-orange. Neon is self-lit and
			-- ignores scene lighting, so the raw hue is what the player sees — a redder value here
			-- reads as a warning light, not wax.
			color = Color3.fromRGB(255, 190, 110),
			-- Beyond this the seam is ordinary painted rock. Comfortably past interaction range so the
			-- glow is an invitation you notice before you arrive, not a reward for arriving.
			range = 26,
			-- Full strength at this distance and closer.
			nearDistance = 8,
			-- Strongest the ember ever gets, and Neon reads as fully saturated at almost any opacity —
			-- so "slight" means mostly transparent even at point-blank range, not a strong colour dialled
			-- down. Raised from an earlier pass that looked like a solid neon panel rather than a hint
			-- of warmth in the rock.
			minTransparency = 0.82,
			-- How far the ember shell stands INSIDE the seam face (negative = inset). A shell larger
			-- than the seam it sits on pokes past its silhouette and reads as a separate hard-edged
			-- panel — the very "blocky red rectangle" this exists to avoid. Insetting keeps the glow
			-- entirely inside the wax it belongs to.
			thickness = -0.05,
			-- Approach/retreat smoothing, so walking past a seam breathes instead of snapping.
			fadePerSecond = 3.5,
		},
	},
	pickaxe = {
		-- A short, blunt, obviously non-combat tool. It is presented in first person only while a
		-- deposit is in reach and has no collision, no hitbox, and no activation away from a seam.
		headSize = Vector3.new(0.62, 0.3, 0.34),
		prongSize = Vector3.new(0.72, 0.3, 0.34),
		collarSize = Vector3.new(0.32, 0.38, 0.32),
		handleSize = Vector3.new(0.18, 2.2, 0.18),
		gripSize = Vector3.new(0.23, 0.08, 0.23),
		gripCount = 5,
		gripSpacing = 0.14,
		headColor = Color3.fromRGB(92, 98, 108),
		headEdgeColor = Color3.fromRGB(132, 137, 145),
		handleColor = Color3.fromRGB(91, 65, 43),
		gripColor = Color3.fromRGB(48, 35, 29),
		-- Five poses, and the whole animation is the trip between them.
		-- REST: carried at the hip while a seam is merely in reach. Low and out of the way.
		restOffset = CFrame.new(1.12, -1.32, -1.55) * CFrame.Angles(math.rad(4), math.rad(-10), math.rad(-32)),
		-- READY: cocked back over the shoulder the instant you engage. This is the pose the pick
		-- lives in for the whole stance, and the one it snaps back to between strikes — the raised
		-- arm IS the visible statement that you are committed to this rock.
		raisedOffset = CFrame.new(0.9, -0.24, -1.42) * CFrame.Angles(math.rad(8), math.rad(-12), math.rad(-46)),
		anticipationOffset = CFrame.new(1.03, -0.08, -1.38) * CFrame.Angles(math.rad(12), math.rad(-14), math.rad(-58)),
		-- IMPACT: buried in the seam, low and forward, past the centre of the screen.
		strikeOffset = CFrame.new(0.28, -1.02, -1.92) * CFrame.Angles(math.rad(-10), math.rad(6), math.rad(38)),
		reboundOffset = CFrame.new(0.48, -0.76, -1.7) * CFrame.Angles(math.rad(-4), math.rad(1), math.rad(25)),
		-- Outcome-specific contact: a fumble scrapes sideways, while depletion follows through into
		-- the opening. Accuracy changes the physical path instead of only recolouring the HUD.
		glanceOffset = CFrame.new(0.78, -0.72, -1.58) * CFrame.Angles(math.rad(-7), math.rad(-18), math.rad(42)),
		breakOffset = CFrame.new(0.14, -1.12, -2.03) * CFrame.Angles(math.rad(-14), math.rad(9), math.rad(32)),
		-- Drawing the tool: rest → ready when the stance opens.
		raiseSeconds = 0.2,
		-- The down-stroke. Short and accelerating — a pickaxe falls, it does not glide. Started on
		-- the CLICK rather than on the server's answer, so the swing never feels like it lagged.
		anticipationSeconds = 0.075,
		swingSeconds = 0.105,
		-- Dwell at the rock. The tiny pause that makes the hit feel like it landed on something.
		impactSeconds = 0.052,
		reboundSeconds = 0.088,
		-- Back to ready. Tuned just under `deposit.strikeCooldownSeconds` so the pick is always up
		-- and still before the next sweep begins — the animation and the rhythm share one beat.
		recoverSeconds = 0.225,
		-- Idle breathing while held ready, so a stance is never a frozen prop on screen.
		bobStuds = 0.025,
		bobSeconds = 2.8,
		swayDegrees = 0.8,
		trailColor = Color3.fromRGB(235, 167, 84),
		trailLifetime = 0.07,
		trailWidthScale = 0.5,
		-- Bias the viewmodel toward the seam's actual viewport position. The held pose only leans a
		-- little; the down-stroke commits fully so contact belongs to the rock being worked.
		aimScreenOffsetStuds = Vector2.new(0.34, 0.22),
		aimYawDegrees = 8,
		aimPitchDegrees = 5,
		idleAimFraction = 0.16,
	},
	qte = {
		position = UDim2.fromScale(0.5, 0.655),
		-- One fracture rail, one target aperture, one marker. The old 48-part radial dial repeated the
		-- same information decoratively and pulled the eye away from the cave.
		widthPixels = 238,
		heightPixels = 76,
		trackThicknessPixels = 2,
		goodBandHeightPixels = 7,
		perfectBandHeightPixels = 13,
		markerSize = Vector2.new(3, 24),
		enterScale = 0.96,
		enterSeconds = 0.16,
		exitSeconds = 0.13,
		-- Reliable remotes should answer well inside this. It only releases local input if a response
		-- never arrives by closing the local stance and sending an idempotent disengage; the longer
		-- authoritative idle watchdog remains server-owned.
		requestTimeoutSeconds = 1.25,
		shakeDuration = 0.12,
		shakeMagnitudePixels = 3,
	},
	feedback = {
		-- The consecutive-Perfect ladder. Each clean strike in a row pitches the next one up a step;
		-- any other outcome drops it back to the floor. Small steps: this should read as a rising
		-- line you notice, not as a chipmunk.
		comboPitchStep = 0.012,
		comboPitchMax = 1.04,
		-- How long a strike's feedback line stays up.
		hintSeconds = 1.4,
		-- A restrained acknowledgement rather than an arcade pickup punch.
		cargoPulseScale = 1.08,
		impactDebrisCount = 7,
		impactDebrisLifetime = 0.55,
		impactDebrisSpeed = 5.5,
		impactDebrisUpSpeed = 3.8,
		impactDebrisSizeMin = 0.055,
		impactDebrisSizeMax = 0.13,
		-- Teammates inside this radius receive the server-authorized spatial impact presentation.
		impactPresentationRange = 74,
	},
}

return Mining
