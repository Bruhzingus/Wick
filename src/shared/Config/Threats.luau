--!strict
-- Threat tuning (DESIGN §9). Two categories so there is never a dominant brightness.
-- lightResponse SIGN: DarkHunter negative (repelled by light), Drawn positive (attracted).
-- Magnitude = sensitivity. Dark-hunters DRAIN wax on contact; they never instant-kill.
-- One generic behaviour system (Logic/ThreatBrain) consumes every row; a new threat is a new row.
-- A snuffer-style enemy would be a row with contactEffect = "Snuff" and waxDamagePerSecond = 0.

local Types = require(script.Parent.Parent.Types)

export type ThreatBehaviorConfig = {
	repathIntervalSeconds: number,
	wanderSpeedFraction: number,
	wanderRadius: number,
	huntLightThreshold: number,
	repelLightThreshold: number,
}

export type ThreatsConfig = {
	behavior: ThreatBehaviorConfig,
	definitions: { [Types.ThreatId]: Types.ThreatDef },
}

local Threats: ThreatsConfig = {
	-- Shared brain constants, applied to every threat.
	behavior = {
		-- Seconds between decisions. Lower = more reactive threats = harder.
		repathIntervalSeconds = 0.5,
		-- Fraction of full speed used while wandering. Higher = harder to read at a distance.
		wanderSpeedFraction = 0.35,
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
			speed = 10, -- studs/s; higher = harder
			detectionRadius = 18, -- studs; higher = harder
			lightResponse = -1.0, -- strongly repelled; closer to 0 = harder to drive off
			waxDamagePerSecond = 0.05, -- wax drained on contact; higher = harder
			contactEffect = "Drain",
			contactRadius = 3,
			bodySize = 3,
		},
		Stalker = {
			id = "Stalker",
			displayName = "Stalker",
			category = "DarkHunter",
			speed = 14,
			detectionRadius = 24,
			lightResponse = -0.6, -- only partly repelled — needs more light to drive off
			waxDamagePerSecond = 0.08,
			contactEffect = "Drain",
			contactRadius = 3,
			bodySize = 4,
		},
		Moth = {
			id = "Moth",
			displayName = "Moth",
			category = "Drawn",
			speed = 12,
			detectionRadius = 30, -- sees light from far; higher = harder
			lightResponse = 1.0, -- strongly drawn to light; higher = harder
			waxDamagePerSecond = 0.04,
			contactEffect = "Drain",
			contactRadius = 3,
			bodySize = 3,
		},
		Swarm = {
			id = "Swarm",
			displayName = "Swarm",
			category = "Drawn",
			speed = 8,
			detectionRadius = 22,
			lightResponse = 0.7,
			waxDamagePerSecond = 0.10, -- slow, but drains hard once on you
			contactEffect = "Drain",
			contactRadius = 4,
			bodySize = 5,
		},
	},
}

return Threats
