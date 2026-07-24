--!strict
-- Threat tuning (DESIGN §9). Two categories so there is never a dominant brightness.
-- lightResponse SIGN: DarkHunter negative (repelled by light), Drawn positive (attracted).
-- Magnitude = sensitivity. Most dark-hunters drain wax; staged attackers can snuff after repeated hits.
-- One generic behaviour system (Logic/ThreatBrain) consumes every row; a new threat is a new row.
-- Snuffer is the same generic row shape with contactEffect = "Snuff" and zero wax damage.

local Types = require(script.Parent.Parent.Types)

export type ThreatBehaviorConfig = {
	repathIntervalSeconds: number,
	wanderSpeedFraction: number,
	wanderRadius: number,
	huntLightThreshold: number,
	repelLightThreshold: number,
}

export type ThreatVisualConfig = {
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
		-- Studs a wandering threat roams from its spawn point.
		wanderRadius = 25,
		-- A dark-hunter hunts a player whose local light level x |lightResponse| is BELOW this.
		-- Higher = you must burn brighter to stay safe = harder.
		huntLightThreshold = 0.15,
		-- A dark-hunter flees when light at its own position x |lightResponse| EXCEEDS this.
		-- Higher = takes more light to repel = harder.
		repelLightThreshold = 0.45,
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
			spawnWeightByDepth = { 0, 2, 3, 4, 5, 5, 5, 4, 4, 3 },
			visualStyle = "Bug",
			ambush = {
				activationRadius = 9,
				territoryRadius = 15,
				patrolRadius = 5,
				teammateRepelRadius = 8,
				retreatDistance = 13,
				retreatSeconds = 5,
				hoverHeight = 8,
				attackHeight = 2.2,
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
