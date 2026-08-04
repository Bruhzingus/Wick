--!strict
-- Threat tuning (DESIGN §9). Two categories so there is never a dominant brightness.
-- lightResponse SIGN: DarkHunter negative (illumination-sensitive), Drawn positive (attracted).
-- Only a LightSource explicitly marked as panic light can force DarkHunter retreat.
-- Magnitude = sensitivity. Most dark-hunters drain wax; staged attackers can snuff after repeated hits.
-- One generic behaviour system (Logic/ThreatBrain) consumes every row; a new threat is a new row.
-- ONE ROW PER CREATURE. If two rows would draw the same body and carry no label between them, they
-- are one row with a `depthScaling` curve, not two — see the note above `definitions`.

local Types = require(script.Parent.Parent.Types)

export type ThreatBehaviorConfig = {
	repathIntervalSeconds: number,
	wanderSpeedFraction: number,
	stalkSpeedFraction: number,
	wanderRadius: number,
	wanderArrivalToleranceStuds: number,
	huntLightThreshold: number,
	darkHunterSneakLightThreshold: number,
	darkHunterObservedDotThreshold: number,
	repelLightThreshold: number,
	darkHunterKeepDistance: number,
	darkHunterBlindSeconds: number,
	investigateArrivalToleranceStuds: number,
	roam: {
		minimumDwellSeconds: number,
		maximumDwellSeconds: number,
	},
}

export type ThreatVisualConfig = {
	procedural: {
		enabled: boolean,
		proxySize: Vector3,
		groundOffsets: {
			crawler: number,
			moth: number,
			ceilingFly: number,
			listener: number,
			knotwalker: number,
			calver: number,
		},
		cullDistance: number,
		cullHysteresis: number,
		maxAnimationDeltaSeconds: number,
		illuminationStep: number,
		targetReplicationDistance: number,
		attackPulseIntervalSeconds: number,
		attackAudio: {
			crawlerCueName: string,
			drawnCueName: string,
			ceilingFlyCueName: string,
			crawlerLungeCueName: string,
			drawnLungeCueName: string,
			ceilingFlyLungeCueName: string,
			victimCueName: string,
			minimumPitchMultiplier: number,
			maximumPitchMultiplier: number,
		},
		locomotionAudio: {
			stepCueName: string,
			-- A foot plant lighter than this is not worth a voice. The crawler's gait keeps ticking
			-- over at a shuffle when it is standing still, and every one of those is a footstep the
			-- player would hear from a creature that is not going anywhere.
			minimumStepWeight: number,
			-- Playback volume is the animation's own step weight remapped into this band, so the same
			-- cue covers a stalk and a charge without a second row.
			quietStepVolume: number,
			loudStepVolume: number,
			mothWingCueName: string,
			mothWingMinIntervalSeconds: number,
			mothWingMaxIntervalSeconds: number,
			-- Beyond this there is no point spending a voice: it is past the cue's own rolloff.
			audibleDistance: number,
		},
		activity: {
			wander: number,
			stalk: number,
			seek: number,
			flee: number,
			investigate: number,
		},
		ceilingFlyBuzz: {
			cueName: string,
			minIntervalSeconds: number,
			maxIntervalSeconds: number,
			outOfRangeRetrySeconds: number,
			audibleDistance: number,
			occlusionEndpointInset: number,
		},
		debugHunterColor: Color3,
		debugDrawnColor: Color3,
	},
	darkHunter: {
		bodyColor: Color3,
		eyeColor: Color3,
		eyeMinSize: number,
		eyeMaxSize: number,
		eyeSizeScale: number,
		eyeWidthScale: number,
		eyeHeightScale: number,
		eyeDepthScale: number,
		eyeAngleDegrees: number,
		eyeGlowBrightness: number,
		eyeGlowRange: number,
	},
	drawn: {
		bodyColor: Color3,
		thoraxColor: Color3,
		wingColor: Color3,
		wingTransparency: number,
	},
	bug: {
		wingColor: Color3,
		wingTransparency: number,
	},
}

export type ThreatsConfig = {
	behavior: ThreatBehaviorConfig,
	visuals: ThreatVisualConfig,
	definitions: { [Types.ThreatId]: Types.ThreatDef },
}

local Threats: ThreatsConfig = {
	visuals = {
		procedural = {
			-- The server replicates one invisible anchored Part per threat; clients build the detailed
			-- procedural body around it and animate locally.
			enabled = true,
			proxySize = Vector3.new(0.25, 0.25, 0.25),
			-- Height of the ROOT above the floor, and so the only thing keeping a body out of the rock:
			-- none of this collides. Each offset has to clear the lowest point that body's own
			-- animation reaches, plus slack for ground the analytic field smoothed over.
			groundOffsets = {
				crawler = 3.72,
				-- A moth flies, and its wings reach the floor long before its body does: the 2.05-stud
				-- forewing sweeps 63 degrees through every beat, carrying the tip ~1.8 studs below the
				-- thorax. At the old 1.8 the down-beat grazed even flat ground and drove itself into
				-- anything sloped, which is how moths ended up looking planted in the cave floor.
				moth = 3.1,
				ceilingFly = 0.5,
				-- A Listener carries its skull low and its hips high, so the root sits well under the
				-- crawler's: the mass a player sees is the flattened head near the ground, not a chest.
				listener = 2.65,
				-- Taller than a crawler at the hip and narrower everywhere else. The long forelimbs reach
				-- below the root through their whole cycle, which is what the extra clearance covers.
				knotwalker = 3.95,
				-- Roof-clinging like the VoidFly, and off the same reasoning: this is the root's clearance
				-- under the sampled ceiling, not a height above the floor.
				calver = 0.6,
			},
			cullDistance = 120,
			cullHysteresis = 12,
			maxAnimationDeltaSeconds = 1 / 20,
			-- Quantization keeps cosmetic light changes from becoming per-frame attribute traffic.
			illuminationStep = 0.05,
			targetReplicationDistance = 0.5,
			-- Contact drain is continuous, so the swing that reads it has to be paced here rather
			-- than by the damage tick. Must stay above the client strike's own length (0.86 s in
			-- DarkCrawler) or a new beat clips the recovery of the one before it.
			attackPulseIntervalSeconds = 1.05,
			-- TWO spatial creature layers plus a close-mixed sting for the confirmed victim. The lunge
			-- fires the instant the server's contact beat arrives — the body committing — and the
			-- attack cue and the victim sting fire on the animation's own strike frame, so what a
			-- player hears is a wind-up they can still react to followed by the blow arriving, rather
			-- than one noise while the arm is still cocked. Small pitch variance stops repeated
			-- contact from turning a horror cue into a metronome.
			attackAudio = {
				crawlerCueName = "DarkCrawlerAttack",
				drawnCueName = "DrawnAttack",
				ceilingFlyCueName = "VoidFlyAttack",
				crawlerLungeCueName = "DarkCrawlerLunge",
				drawnLungeCueName = "DrawnLunge",
				ceilingFlyLungeCueName = "VoidFlyLunge",
				victimCueName = "ThreatHit",
				minimumPitchMultiplier = 0.92,
				maximumPitchMultiplier = 1.08,
			},
			-- Movement audio, driven by the bodies themselves rather than by a timer: the crawler
			-- reports the frame a foot reaches the ground and the moth is given a flutter on an
			-- interval. Both are quiet by design — this layer is what tells a player something is
			-- coming and roughly how fast, and it stops being that the moment it is loud enough to
			-- locate precisely.
			locomotionAudio = {
				stepCueName = "ThreatStep",
				minimumStepWeight = 0.24,
				quietStepVolume = 0.35,
				loudStepVolume = 1,
				mothWingCueName = "MothWing",
				mothWingMinIntervalSeconds = 2.4,
				mothWingMaxIntervalSeconds = 6.5,
				audibleDistance = 48,
			},
			activity = {
				wander = 0.16,
				stalk = 0.42,
				seek = 1,
				flee = 0.62,
				-- Between a drift and a stalk: alert body language that is visibly not a hunt, so a
				-- player who lured something can read that it is looking for a sound, not for them.
				investigate = 0.55,
			},
			ceilingFlyBuzz = {
				cueName = "FlyBuzz",
				minIntervalSeconds = 9,
				maxIntervalSeconds = 20,
				outOfRangeRetrySeconds = 2,
				audibleDistance = 32,
				-- Stop just short of the fly so its own nearby Terrain roof cannot reject the buzz.
				occlusionEndpointInset = 0.35,
			},
			debugHunterColor = Color3.fromRGB(150, 165, 200),
			debugDrawnColor = Color3.fromRGB(230, 195, 130),
		},
		darkHunter = {
			bodyColor = Color3.fromRGB(5, 3, 7),
			eyeColor = Color3.fromRGB(128, 0, 7),
			eyeMinSize = 0.12,
			eyeMaxSize = 0.3,
			eyeSizeScale = 0.075,
			eyeWidthScale = 1.9,
			eyeHeightScale = 0.42,
			eyeDepthScale = 0.42,
			eyeAngleDegrees = 20,
			eyeGlowBrightness = 0.14,
			eyeGlowRange = 2.5,
		},
		drawn = {
			bodyColor = Color3.fromRGB(48, 45, 44),
			thoraxColor = Color3.fromRGB(67, 62, 59),
			wingColor = Color3.fromRGB(112, 106, 101),
			wingTransparency = 0.18,
		},
		bug = {
			wingColor = Color3.fromRGB(78, 75, 82),
			wingTransparency = 0.2,
		},
	},
	-- Shared brain constants, applied to every threat.
	behavior = {
		-- Seconds between decisions. Lower = more reactive threats = harder.
		repathIntervalSeconds = 0.65,
		-- Fraction of full speed used while wandering. Higher = harder to read at a distance.
		wanderSpeedFraction = 0.3,
		-- Medium-light crawlers reposition deliberately without committing to an attack.
		stalkSpeedFraction = 0.48,
		-- Studs a wandering threat drifts from its current home. Deliberately under the room half-cell
		-- (Floors: 64/2), so a drift stays inside one room and `roam` below is the only thing that
		-- moves a threat between them.
		wanderRadius = 25,
		-- Distance at which a wandering threat is considered to have reached its target and rolls a
		-- new one.
		wanderArrivalToleranceStuds = 2,
		-- A dark-hunter hunts a player whose local light level x |lightResponse| is BELOW this.
		-- Higher = you must burn brighter to stay safe = harder.
		huntLightThreshold = 0.2,
		-- In the band above a direct low-light hunt, an unwatched crawler closes in at stalk speed.
		-- Turning to face it restores the ordinary keep-distance behavior on the next think.
		darkHunterSneakLightThreshold = 0.32,
		-- Dot(player facing, player -> hunter) at or above this counts as watching it. About a
		-- 69-degree half-angle keeps peripheral awareness useful without granting rear vision.
		darkHunterObservedDotThreshold = 0.35,
		-- A dark-hunter flees when FLARE at its own position x |lightResponse| EXCEEDS this.
		-- Ordinary dial light never triggers this threshold.
		repelLightThreshold = 0.45,
		-- In the band between hunt and repel thresholds, hold this much space from a candle.
		darkHunterKeepDistance = 11,
		-- After the estimated straight-line retreat travel, hunters remain blind to prey for this
		-- additional safety window. Obstacles can lengthen the actual retreat without reacquisition.
		darkHunterBlindSeconds = 2,
		-- How close a listener has to get to a remembered noise before it counts as "looked".
		-- Wider than the wander tolerance: it is checking an area, not touching a point.
		investigateArrivalToleranceStuds = 5,
		-- Roaming. Nothing lives in one room for a whole run: after this long drifting with nothing to
		-- chase, a threat re-homes to a room next door and drifts on from there, so a floor's threats
		-- redistribute themselves instead of each guarding the tile it spawned on. The dwell is longer
		-- than the ~25 s a wandering body needs to cross one cell, so a roam reads as moving on rather
		-- than as pacing a doorway. Sensing ANYTHING resets it — roaming is what a threat does when
		-- the cave is quiet, never something that interrupts a hunt.
		roam = {
			minimumDwellSeconds = 30,
			maximumDwellSeconds = 75,
		},
	},
	-- Every row's detectionRadius below is 30% above its original value. Sensing now reaches past the
	-- room a player can see into, so how bright you are burning has to be decided BEFORE you arrive
	-- rather than when something already stands at the edge of your light. Flee distance and the
	-- post-Flare blind window derive from the same number, so panic light still drives a hunter clear
	-- out of its now-wider reach.
	--
	-- THREE ROWS, THREE CREATURES. This table used to hold eight rows that rendered as three bodies:
	-- a dark-hunter trio and a drawn quartet, none of which a player could ever tell apart. Nothing in
	-- the game labelled them — the audio cues, the tutorial text and the client bodies all already
	-- spoke of one DarkCrawler and one cave moth — so the split was bookkeeping, and depth-staggered
	-- spawn tables were doing the job of a difficulty curve. The two things that split was genuinely
	-- carrying are now explicit properties of the rows that survived:
	--
	--   * the ramp is `depthScaling`, written out floor by floor (Logic/ThreatRules resolves it);
	--   * contact that extinguishes is `sustainedContact` on the moth, not a separate creature.
	--
	-- Every scaling curve below is the composition it replaces, evaluated: at each floor, the old
	-- rows' stats averaged under their own spawn weights at that floor. Floor 1 is therefore exactly
	-- what floor 1 always met, and floor 10 is exactly what floor 10 always met.
	definitions = {
		DarkCrawler = {
			id = "DarkCrawler",
			displayName = "Dark Crawler",
			category = "DarkHunter",
			-- Flat values are the FLOOR 1 profile; `depthScaling` carries them down. A field with no
			-- curve stays at the value written here for the whole run.
			speed = 8, -- studs/s; higher = harder
			detectionRadius = 23.4, -- studs; higher = harder
			lightResponse = -1.0, -- strongly repelled; closer to 0 = harder to drive off
			waxDamagePerSecond = 0.05, -- wax drained on contact; higher = harder
			contactEffect = "Drain",
			-- One body, one reach, one pathing clearance, at every depth. The three merged rows sat at
			-- 3/4/5 studs and all drew the same silhouette, so the spread was never visible.
			contactRadius = 3.2,
			bodySize = 4,
			-- The merged rows' summed weight, halved: a room used to allow about two of the three, so
			-- summing outright would have quietly doubled the crawler's share against the VoidFly it
			-- competes with in the same allow-lists.
			spawnWeightByDepth = { 5.5, 5.5, 6, 7.5, 8, 9.5, 10.5, 11.5, 12.5, 14 },
			-- The baseline set of ears, and the ones the shallow floors are balanced around. A single
			-- clean pick strike (Config/Sound: 0.55) sits under this threshold at every distance, so
			-- ONE swing never brings a crawler up here; two or three overlapping swings do, and
			-- fumbling gets there faster. Deeper crawlers hear better — see `depthScaling.hearing`.
			hearing = {
				sensitivity = 1.0,
				curiosityThreshold = 0.8,
				hearingRadius = 55,
				-- Held flat on purpose: across the whole depth range the old composition moved these two
				-- by under 10%, which is not a curve, it is rounding error with ten entries.
				investigateSeconds = 9,
				investigateSpeedFraction = 0.5,
			},
			-- WHAT GOING DEEPER DOES TO A CRAWLER. It senses much further (23 -> 35 studs, half again
			-- as far), it gets harder to drive off with light (-1.0 -> -0.71, so the same flare buys
			-- less retreat), it drains faster, and it hears more of the cave. What it does NOT do is
			-- get faster: the old trio's speeds were 8/11/5.5 and their weights crossed such that the
			-- composite never left the low eights. Depth makes a crawler harder to avoid and harder to
			-- shake, never harder to outrun — outrunning one is the counterplay that has to keep working.
			depthScaling = {
				speed = { 8, 8.38, 8.39, 8.64, 8.63, 8.39, 8.22, 8.24, 8.24, 8.24 },
				detectionRadius = { 23.4, 24.4, 26.9, 29.1, 30.6, 32.3, 33.6, 34.4, 34.5, 34.5 },
				lightResponse = { -1, -0.95, -0.89, -0.82, -0.78, -0.76, -0.74, -0.72, -0.72, -0.71 },
				waxDamagePerSecond = { 0.05, 0.054, 0.058, 0.063, 0.065, 0.066, 0.068, 0.069, 0.069, 0.069 },
				-- Ears open as you descend. By the deep floors the threshold has fallen far enough that
				-- a single clean strike at close range CAN rouse one, which is the deep-floor mining
				-- pressure the broad-sensing row used to provide by turning up in the spawn roll.
				hearing = {
					sensitivity = { 1, 1.03, 1.09, 1.15, 1.18, 1.23, 1.26, 1.28, 1.28, 1.29 },
					curiosityThreshold = { 0.8, 0.79, 0.76, 0.73, 0.71, 0.69, 0.67, 0.66, 0.66, 0.66 },
					hearingRadius = { 55, 56.6, 60.7, 64.3, 66.7, 69.5, 71.6, 72.9, 73, 73.1 },
				},
			},
		},
		Moth = {
			id = "Moth",
			displayName = "Cave Moth",
			category = "Drawn",
			speed = 9,
			-- Flat: the merged quartet's composite sensing never left 37.6-38.7 studs at any depth. A
			-- moth sees your flame from across the room on floor 1 and on floor 10 alike; what changes
			-- is what happens when it reaches you.
			detectionRadius = 38,
			lightResponse = 0.95, -- strongly drawn to light; higher = harder
			waxDamagePerSecond = 0.04,
			contactEffect = "Drain",
			contactRadius = 3.2,
			bodySize = 3.5,
			-- Summed and halved on the same reasoning as the crawler above.
			spawnWeightByDepth = { 4, 4, 4.5, 5.5, 7, 8.5, 10, 11, 12.5, 14 },
			-- CONTACT THAT EXTINGUISHES, kept as a mechanic. It used to be a separate rare row whose
			-- contact put you out instantly and cost no wax — a creature drawn with the same body,
			-- the same palette and the same eye glow as an ordinary moth, so the only tell was dying
			-- to it. Here it is what an ordinary moth does when you cannot get off it: the drain runs
			-- while it feeds, and if you never break away it takes the flame. Same snuffed state, same
			-- revive, but now with a window a player can see coming and act inside of.
			--
			-- The counterplay is unchanged and is what the tutorial line already says: drop your light
			-- so it loses you, DECOY it away, or simply leave. Running (Config/Movement.runSpeed = 16)
			-- outpaces a moth at every depth by a wide margin, and from floor 4 — the first floor the
			-- clock is live at all — the speed curve below has already fallen under a WALK (8), so a
			-- player who never sprints is still never trapped by one.
			sustainedContact = {
				-- Overwritten per floor below; this is the floor-1 value, and 0 means it cannot happen.
				secondsToSnuff = 0,
				-- Contact is a radius test against a body whose wings carry it a fair way each beat.
				-- Under a second of separation is that beat, not an escape.
				graceSeconds = 0.75,
			},
			-- Idle moths belong on the stone, not milling in the open. Longer dwells = quieter caves.
			--
			-- THE WHOLE ROW PERCHES NOW. Two of the four merged rows perched and two did not, and since
			-- all four drew the same body the difference read as moths randomly failing to land. These
			-- are the cave moth's own authored numbers, kept exactly: the deeper variant's tighter,
			-- higher, twitchier rest was a sub-variant flavour and goes with the sub-variant.
			perch = {
				searchRadius = 14,
				searchDirections = 8,
				minimumHeight = 2.5,
				maximumHeight = 7,
				-- Measured against the SHARED CaveMoth body this row renders — not its nominal bodySize,
				-- which only the grey-box fallback and pathing clearance use. Resting belly-to-stone
				-- still beats the wings toward the face, and the forewing carries its tip ~1.8 studs off
				-- the body, so anything under that plants the moth in the wall.
				surfaceOffset = 2.2,
				minimumDwellSeconds = 6,
				maximumDwellSeconds = 16,
				minimumWallSlopeDegrees = 55,
			},
			-- WHAT GOING DEEPER DOES TO A MOTH: it stops being a wax cost and starts being a way to
			-- die. The stat drift is small and mostly downward — the deep composition leaned on the
			-- slow heavy-draining rows — so the curve that matters is the snuff clock.
			depthScaling = {
				speed = { 9, 8.69, 8.39, 7.86, 7.68, 7.47, 7.33, 7.16, 7.1, 7.05 },
				waxDamagePerSecond = { 0.04, 0.047, 0.05, 0.052, 0.054, 0.052, 0.05, 0.048, 0.048, 0.047 },
				-- ZERO THROUGH FLOOR 3, which is exactly where the row that owned this mechanic used to
				-- first appear, and exactly the depth the tutorial hints stop at (Config/Feel: maxDepth
				-- 3). A player meeting their first moth is taught it costs wax; nothing puts them out
				-- before the game has finished explaining itself. From floor 4 the window closes.
				sustainedContactSecondsToSnuff = { 0, 0, 0, 12, 11, 10, 9, 8, 7, 6 },
			},
		},
		VoidFly = {
			id = "VoidFly",
			displayName = "VoidFly",
			category = "DarkHunter",
			-- Territorial ceiling bug: it patrols one dark patch and dives only when a candle
			-- walks underneath. Max burn or a nearby teammate temporarily drives it away.
			speed = 7,
			detectionRadius = 20.8,
			lightResponse = -1,
			waxDamagePerSecond = 0,
			contactEffect = "Snuff",
			contactRadius = 2.4,
			bodySize = 1.2,
			-- 60% above the original { 0, 2, 3, 4, 5, 5, 5, 4, 4, 3 } relative weights.
			spawnWeightByDepth = { 0, 3.2, 4.8, 6.4, 8, 8, 8, 6.4, 6.4, 4.8 },
			visualStyle = "Bug",
			ambush = {
				-- The ambusher's real sense: a territorial row never consults detectionRadius, so this
				-- is the number that carries its share of the 30% sensing pass. territoryRadius stays
				-- put — FloorBuilder reserves roof dressing from it, and the two must not collide.
				activationRadius = 11.7,
				territoryRadius = 15,
				patrolRadius = 5,
				teammateRepelRadius = 8,
				retreatDistance = 13,
				retreatSeconds = 5,
				-- High cavern roofs put the tiny physical tell beyond both candle inspection and
				-- its quiet 32-stud buzz. Ceiling ambushers are therefore a low-room profile.
				maximumCeilingHeight = 30,
				-- Keeps the full animated silhouette under the sampled Terrain underside rather than
				-- embedding its root in the minimum-clearance roof. It covers the flying body's own
				-- reach ABOVE its root — the thorax IS the root, carrying wing and leg above it — plus
				-- margin for a ceiling sloping away from the single point ThreatService probes. Both
				-- shrank with the body: it is now a bug barely a stud wide instead of a 2.6-stud one,
				-- so the old 2.4 left it hanging in open air well below a roof it is supposed to be
				-- clinging to. The probe itself no longer reports a ceiling ABOVE the real one (see
				-- server/ThreatService.surfaceRoofY), which is what made the wide margin load-bearing.
				ceilingClearance = 1.5,
				roofDecorationClearance = 4.5,
				-- Safe legacy fallback only; live floors provide exact ground/roof surface data.
				hoverHeight = 8,
				attackHeight = 2.2,
				diveSpeed = 14,
				returnSpeed = 10,
				contactHeightTolerance = 0.45,
			},
			contactAttack = {
				cooldownSeconds = 0.8,
				hitsToSnuff = 4,
				waxDamagePerHit = 0.012,
			},
		},
		--------------------------------------------------------------------------------
		-- SIGNATURE CREATURES — one per cave family, and each found in exactly one cave.
		--
		-- The three rows above are the SHARED ROSTER: every family draws them, stat-identical, and a
		-- family changes only how often (Config/CaveFamilies.threatEcology) and what they are dressed in.
		-- The three below are the opposite — each is weighted to zero in two of the three families, so
		-- meeting one tells you which cave you are in as surely as the rock does.
		--
		-- THEY NEED NO MECHANISM OF THEIR OWN. They sit in the ordinary Config/Floors allow-lists and the
		-- ordinary spawn roll; a zero weight in a family is already read as "not here" by the planner's
		-- eligibility check and its selection. There is no `if familyId == ...` anywhere behind them.
		--
		-- EACH IS ANCHORED TO WHAT ITS FAMILY ALREADY IS, rather than being a new stat block dropped in a
		-- cave: Stone's is the fair, readable creature that teaches the noise system; Moss's weaponises
		-- the knotted topology that family generates; Ice's weaponises the falling ice that family
		-- already hangs more of than anywhere else.
		--------------------------------------------------------------------------------
		Listener = {
			id = "Listener",
			displayName = "Cave Listener",
			category = "DarkHunter",
			-- STONE'S. The one creature in the game that does not care how bright you are burning.
			-- Everything else on the roster reads light in one direction or the other; this one is
			-- functionally blind and hunts entirely by sound, which makes it the row that teaches the
			-- noise system the way the crawler teaches the light system. It belongs in Stone because
			-- Stone is where a player learns the game, and because Stone's Tier 1 rock means more swings
			-- of a pick per unit of value than anywhere else.
			--
			-- SLOWER THAN A WALK on purpose (Config/Movement: walk 8, run 16). Its threat is that it
			-- FINDS you, never that it catches you — the counterplay is to stop making noise, and
			-- standing still always works.
			speed = 7.5,
			-- FUNCTIONALLY BLIND, and non-zero for a reason: Logic/ThreatBrain derives a retreat target
			-- and a blind window from this radius, and a literal zero would collapse both into "flee to
			-- exactly where I am standing". Six studs means it can only see something already on top of
			-- it, which is what a player reads as blind.
			detectionRadius = 6,
			-- Weak, and negative because the sign IS the category. Ordinary brightness barely moves it,
			-- which is the whole design — but FLARE crosses `repelLightThreshold` for every dark-hunter
			-- alike, so the panic answer that works on everything still works here.
			lightResponse = -0.35,
			waxDamagePerSecond = 0.055,
			contactEffect = "Drain",
			contactRadius = 3.4,
			bodySize = 4.2,
			-- Absent on floors 1-2: the tutorial band teaches light first, and a creature that ignores
			-- light would muddy that lesson before it has landed.
			spawnWeightByDepth = { 0, 0, 3.5, 5, 6.5, 8, 9, 10, 11, 12 },
			visualStyle = "Listener",
			-- THE EARS THE WHOLE ROW IS BUILT ON. Against Config/Sound's 0.55 for a clean pick strike, a
			-- threshold of 0.45 under 1.6 sensitivity means ONE swing rouses this creature at range —
			-- deliberately, and in contrast to the crawler, which needs several overlapping strikes. The
			-- long investigate and the fast investigate walk are what make being heard actually cost you
			-- something: it commits, and it arrives.
			hearing = {
				sensitivity = 1.6,
				curiosityThreshold = 0.45,
				hearingRadius = 95,
				investigateSeconds = 14,
				investigateSpeedFraction = 0.72,
			},
			-- WHAT GOING DEEPER DOES TO A LISTENER: its ears open and its contact bites harder. What it
			-- never does is get faster or learn to see — both would attack the counterplay itself rather
			-- than raising the price of failing at it. Outrunning one and going quiet must keep working
			-- on floor 20 exactly as they did on floor 3.
			depthScaling = {
				lightResponse = { -0.35, -0.35, -0.35, -0.34, -0.33, -0.32, -0.31, -0.3, -0.29, -0.28 },
				waxDamagePerSecond = { 0.055, 0.055, 0.058, 0.061, 0.064, 0.066, 0.068, 0.07, 0.071, 0.072 },
				hearing = {
					sensitivity = { 1.6, 1.6, 1.66, 1.73, 1.8, 1.86, 1.92, 1.97, 2.01, 2.05 },
					curiosityThreshold = { 0.45, 0.45, 0.43, 0.41, 0.39, 0.37, 0.35, 0.33, 0.32, 0.31 },
					hearingRadius = { 95, 95, 99, 104, 109, 114, 119, 123, 127, 130 },
				},
			},
		},
		Knotwalker = {
			id = "Knotwalker",
			displayName = "Knotwalker",
			category = "DarkHunter",
			-- MOSS'S, and named for what Config/CaveFamilies calls that cave: "a knot you lose your
			-- bearings in". Moss generates more cycles, more optional branches and far more TwinLobe
			-- rooms than anywhere else, and this row is that topology turned into a creature. It does not
			-- chase you. It walks the room graph toward where you are HEADING, so the danger is in the
			-- room you have not seen yet — which is the family's "obstructed information" identity
			-- expressed as a body rather than as a wall.
			--
			-- SLOWER THAN A RUN, and it has to stay that way: it must never beat you to somewhere by
			-- being faster, only by taking a different way there.
			speed = 7,
			-- It needs to place you roughly to predict at all, and this is what it loses when you leave.
			detectionRadius = 26,
			lightResponse = -0.85,
			waxDamagePerSecond = 0.05,
			contactEffect = "Drain",
			contactRadius = 3,
			-- Narrow where the crawler is long-legged: built to pull itself through a TwinLobe's neck.
			bodySize = 3.8,
			spawnWeightByDepth = { 0, 0, 0, 4.5, 6, 7.5, 9, 10, 11, 12 },
			visualStyle = "Knotwalker",
			-- Ordinary ears, deliberately: a creature that both predicted your route AND heard you across
			-- the floor would have no gap left in it for a player to use.
			hearing = {
				sensitivity = 0.9,
				curiosityThreshold = 0.85,
				hearingRadius = 48,
				investigateSeconds = 8,
				investigateSpeedFraction = 0.55,
			},
			intercept = {
				-- Just over half a room cell (Config/Floors.geometry.cellSize is 64), so the prediction
				-- lands at the far side of the space a player is crossing rather than deep in the next
				-- one. Close enough that the creature is somewhere they were actually going; near enough
				-- that they can still see it get there.
				projectionStuds = 38,
				commitmentSeconds = 4.5,
				-- ONE room. Two would be indistinguishable from it knowing where you are going.
				roomsAhead = 1,
				maximumPredictionDistance = 90,
			},
			-- WHAT GOING DEEPER DOES TO A KNOTWALKER: it holds a read on you from further away and costs
			-- more when it lands one. The commitment window in `intercept` is NOT scaled — that number is
			-- the player's guarantee that doubling back beats it, and a difficulty curve may not erode a
			-- guarantee.
			depthScaling = {
				detectionRadius = { 26, 26, 26, 28, 30, 32, 34, 35, 36, 37 },
				lightResponse = { -0.85, -0.85, -0.85, -0.82, -0.79, -0.76, -0.74, -0.72, -0.71, -0.7 },
				waxDamagePerSecond = { 0.05, 0.05, 0.05, 0.054, 0.058, 0.061, 0.064, 0.066, 0.068, 0.069 },
			},
		},
		Calver = {
			id = "Calver",
			displayName = "Calver",
			category = "DarkHunter",
			-- ICE'S, and named for the glaciology: calving is ice breaking away from the mass. Falling ice
			-- is already the family's signature pressure (Config/CaveFamilies: dripstoneFactor 1.45, and
			-- Ice is the only family that hangs long spires), and this is the creature that brings it
			-- down. It clings in the tall vaults Ice biases toward and strikes the rock when a candle
			-- passes underneath.
			--
			-- IT NEVER TOUCHES YOU. Zero wax damage, no contact attack, no dive — the first creature in
			-- the game whose entire output is an environmental trigger. What it drops was authored by the
			-- planner, was inspectable from across the room before it moved, and still gives its own full
			-- warning when it falls. It changes WHEN, never WHETHER, so a player who read the ceiling and
			-- crossed under it anyway is the one who pays. With nothing in range it only scrapes.
			--
			-- IT DOES NOT PROTECT ITS ROOM, and that is load-bearing rather than an oversight.
			-- Logic/ThreatRules.snuffsWithoutWarning is false for a zero-drain row that cannot snuff, so
			-- Logic/FloorPlanner will happily hang formations in its room — which it must, or the
			-- creature would be standing in the one place with nothing for it to use.
			speed = 6,
			detectionRadius = 18,
			lightResponse = -1,
			waxDamagePerSecond = 0,
			contactEffect = "Drain",
			contactRadius = 2,
			bodySize = 2.4,
			spawnWeightByDepth = { 0, 0, 0, 4, 5, 6, 7, 7.5, 8, 8 },
			visualStyle = "Calver",
			ceilingStrike = {
				strikeRadius = 22,
				activationRadius = 13,
				cooldownSeconds = 12,
				-- The wind-up a player can act on, and it runs BEFORE the formation's own warning rather
				-- than instead of it: the full reaction budget is this plus the variant's warningSeconds.
				windUpSeconds = 1.1,
				-- Matched to the ambusher's roof geometry so the two read as one cave layer rather than as
				-- two creatures with different rules about ceilings. Higher than the VoidFly's cap because
				-- Ice biases its ceilings tall and this row belongs in exactly those vaults.
				maximumCeilingHeight = 42,
				ceilingClearance = 1.8,
				roofDecorationClearance = 5,
				territoryRadius = 20,
				patrolRadius = 7,
				hoverHeight = 10,
				retreatDistance = 16,
				retreatSeconds = 6,
			},
			-- WHAT GOING DEEPER DOES TO A CALVER: it reaches further and acts more often. Its wind-up is
			-- NOT scaled, for the same reason the Knotwalker's commitment is not — the window a player
			-- reacts inside is the promise the row is built on.
			depthScaling = {
				detectionRadius = { 18, 18, 18, 19, 20, 21, 22, 23, 23, 24 },
				lightResponse = { -1, -1, -1, -0.96, -0.93, -0.9, -0.88, -0.86, -0.85, -0.84 },
			},
		},
	},
}

return Threats
