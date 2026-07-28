--!strict
-- Threat tuning (DESIGN §9). Two categories so there is never a dominant brightness.
-- lightResponse SIGN: DarkHunter negative (illumination-sensitive), Drawn positive (attracted).
-- Only a LightSource explicitly marked as panic light can force DarkHunter retreat.
-- Magnitude = sensitivity. Most dark-hunters drain wax; staged attackers can snuff after repeated hits.
-- One generic behaviour system (Logic/ThreatBrain) consumes every row; a new threat is a new row.
-- Snuffer is the same generic row shape with contactEffect = "Snuff" and zero wax damage.

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
}

export type ThreatVisualConfig = {
	procedural: {
		enabled: boolean,
		proxySize: Vector3,
		groundOffsets: {
			crawler: number,
			moth: number,
			ceilingFly: number,
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
			victimCueName: string,
			minimumPitchMultiplier: number,
			maximumPitchMultiplier: number,
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
			groundOffsets = {
				crawler = 3.72,
				moth = 1.8,
				ceilingFly = 0.5,
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
			-- One spatial creature layer plus a close-mixed sting for the confirmed victim. Small
			-- pitch variance stops repeated contact from turning a horror cue into a metronome.
			attackAudio = {
				crawlerCueName = "DarkCrawlerAttack",
				drawnCueName = "DrawnAttack",
				ceilingFlyCueName = "VoidFlyAttack",
				victimCueName = "ThreatHit",
				minimumPitchMultiplier = 0.92,
				maximumPitchMultiplier = 1.08,
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
		-- Studs a wandering threat roams from its spawn point.
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
	},
	definitions = {
		Lurker = {
			id = "Lurker",
			displayName = "Lurker",
			category = "DarkHunter",
			speed = 8, -- studs/s; higher = harder
			detectionRadius = 18, -- studs; higher = harder
			lightResponse = -1.0, -- strongly repelled; closer to 0 = harder to drive off
			waxDamagePerSecond = 0.05, -- wax drained on contact; higher = harder
			contactEffect = "Drain",
			contactRadius = 3,
			bodySize = 3,
			spawnWeightByDepth = { 8, 7, 6, 5, 4, 3, 2, 1, 1, 1 },
			-- The baseline set of ears. A single clean pick strike (Config/Sound: 0.55) sits under
			-- this threshold at every distance, so ONE swing never brings a Lurker; two or three
			-- overlapping swings do, and fumbling gets there faster.
			hearing = {
				sensitivity = 1.0,
				curiosityThreshold = 0.8,
				hearingRadius = 55,
				investigateSeconds = 9,
				investigateSpeedFraction = 0.5,
			},
		},
		Stalker = {
			id = "Stalker",
			displayName = "Stalker",
			category = "DarkHunter",
			speed = 11,
			detectionRadius = 24,
			lightResponse = -0.6, -- only partly repelled — needs more light to drive off
			waxDamagePerSecond = 0.08,
			contactEffect = "Drain",
			contactRadius = 3,
			bodySize = 4,
			spawnWeightByDepth = { 0, 1, 2, 4, 5, 6, 7, 8, 9, 10 },
			-- Keenest ears and the quickest to come and look — it is the row that already keeps its
			-- distance and repositions, so "went to check on a sound" is in character for it.
			hearing = {
				sensitivity = 1.2,
				curiosityThreshold = 0.7,
				hearingRadius = 68,
				investigateSeconds = 8,
				investigateSpeedFraction = 0.6,
			},
		},
		Moth = {
			id = "Moth",
			displayName = "Moth",
			category = "Drawn",
			speed = 9,
			detectionRadius = 30, -- sees light from far; higher = harder
			lightResponse = 1.0, -- strongly drawn to light; higher = harder
			waxDamagePerSecond = 0.04,
			contactEffect = "Drain",
			contactRadius = 3,
			bodySize = 3,
			spawnWeightByDepth = { 8, 7, 6, 5, 4, 3, 2, 1, 1, 1 },
			-- Idle moths belong on the stone, not milling in the open. Longer dwells = quieter caves.
			perch = {
				searchRadius = 14,
				searchDirections = 8,
				minimumHeight = 2.5,
				maximumHeight = 7,
				surfaceOffset = 0.35,
				minimumDwellSeconds = 6,
				maximumDwellSeconds = 16,
				minimumWallSlopeDegrees = 55,
			},
		},
		Swarm = {
			id = "Swarm",
			displayName = "Swarm",
			category = "Drawn",
			speed = 6.5,
			detectionRadius = 22,
			lightResponse = 0.7,
			waxDamagePerSecond = 0.10, -- slow, but drains hard once on you
			contactEffect = "Drain",
			contactRadius = 4,
			bodySize = 5,
			spawnWeightByDepth = { 0, 1, 2, 3, 5, 6, 7, 8, 9, 10 },
		},
		Hollow = {
			id = "Hollow",
			displayName = "Hollow",
			category = "DarkHunter",
			-- Slow and broad-sensing: it controls dark routes without becoming a chase enemy.
			speed = 5.5,
			detectionRadius = 30,
			lightResponse = -0.8,
			waxDamagePerSecond = 0.06,
			contactEffect = "Drain",
			contactRadius = 3.5,
			bodySize = 5,
			spawnWeightByDepth = { 0, 0, 1, 2, 3, 5, 7, 8, 9, 10 },
			-- The broad-sensing row hears the most and commits the longest, but walks over slowly.
			-- Its low threshold means a single clean strike CAN rouse it at close range — mining in
			-- the same room as a Hollow is meant to be a bad idea rather than a survivable one.
			hearing = {
				sensitivity = 1.4,
				curiosityThreshold = 0.6,
				hearingRadius = 80,
				investigateSeconds = 12,
				investigateSpeedFraction = 0.45,
			},
		},
		AshMoth = {
			id = "AshMoth",
			displayName = "Ash Moth",
			category = "Drawn",
			-- Quick to investigate, but individually forgiving on contact.
			speed = 8.5,
			detectionRadius = 38,
			lightResponse = 1.2,
			waxDamagePerSecond = 0.025,
			contactEffect = "Drain",
			contactRadius = 2.5,
			bodySize = 2,
			spawnWeightByDepth = { 0, 0, 1, 2, 4, 6, 8, 9, 10, 11 },
			-- Rests higher and more briefly than a cave moth: quicker to be roused, quicker to settle.
			perch = {
				searchRadius = 16,
				searchDirections = 8,
				minimumHeight = 3.5,
				maximumHeight = 9,
				surfaceOffset = 0.3,
				minimumDwellSeconds = 4,
				maximumDwellSeconds = 11,
				minimumWallSlopeDegrees = 55,
			},
		},
		Snuffer = {
			id = "Snuffer",
			displayName = "Snuffer",
			category = "Drawn",
			-- Rare moth-logic threat: no wax damage, but contact causes the revivable snuffed state.
			speed = 5,
			detectionRadius = 26,
			lightResponse = 0.75,
			waxDamagePerSecond = 0,
			contactEffect = "Snuff",
			contactRadius = 3,
			bodySize = 4,
			spawnWeightByDepth = { 0, 0, 0, 1, 1, 2, 3, 4, 5, 6 },
		},
		VoidFly = {
			id = "VoidFly",
			displayName = "VoidFly",
			category = "DarkHunter",
			-- Territorial ceiling bug: it patrols one dark patch and dives only when a candle
			-- walks underneath. Max burn or a nearby teammate temporarily drives it away.
			speed = 7,
			detectionRadius = 16,
			lightResponse = -1,
			waxDamagePerSecond = 0,
			contactEffect = "Snuff",
			contactRadius = 2.4,
			bodySize = 1.2,
			-- 60% above the original { 0, 2, 3, 4, 5, 5, 5, 4, 4, 3 } relative weights.
			spawnWeightByDepth = { 0, 3.2, 4.8, 6.4, 8, 8, 8, 6.4, 6.4, 4.8 },
			visualStyle = "Bug",
			ambush = {
				activationRadius = 9,
				territoryRadius = 15,
				patrolRadius = 5,
				teammateRepelRadius = 8,
				retreatDistance = 13,
				retreatSeconds = 5,
				-- High cavern roofs put the tiny physical tell beyond both candle inspection and
				-- its quiet 32-stud buzz. Ceiling ambushers are therefore a low-room profile.
				maximumCeilingHeight = 30,
				-- Keeps the full animated silhouette under the sampled Terrain underside rather
				-- than embedding its root in the minimum-clearance roof.
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
	},
}

return Threats
