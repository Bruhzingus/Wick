--!strict
-- Threat-domain types (DESIGN §9). Two categories exist so there is never a dominant brightness.

-- The two categories. Closed union — fixed by design.
export type ThreatCategory = "DarkHunter" | "Drawn"

-- Identifier for a specific threat. Open string alias: the content pool grows by adding Config rows,
-- not by editing this type (ARCHITECTURE: content is data, not classes).
export type ThreatId = string

-- What touching this threat does. "Drain" removes wax over time; "Snuff" extinguishes with wax
-- remaining (the revivable death state). Neither ever instant-kills (DESIGN §9).
export type ContactEffect = "Drain" | "Snuff"

-- Reusable content profiles. New rows select these profiles instead of adding per-enemy classes.
export type ThreatVisualStyle = "Default" | "Bug"

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
	perch: PerchProfile?, -- rests on cave walls while wandering instead of drifting across the floor
	contactAttack: ContactAttackProfile?, -- staged contact instead of continuous drain/immediate snuff
}

-- What a threat is currently doing. Decided by ThreatBrain, executed by the server adapter.
export type ThreatMode = "Wander" | "Stalk" | "Seek" | "Flee"

-- Live runtime state of one threat instance. Not persisted.
export type ThreatState = {
	id: ThreatId,
	category: ThreatCategory,
	position: Vector3,
	homePosition: Vector3, -- wander anchor (spawn point)
	mode: ThreatMode,
	targetPosition: Vector3?, -- where it is heading, if anywhere
	targetPlayerId: number?, -- player being pursued, if any
	nextThinkAt: number, -- os.clock() time of the next decision
	retreatUntil: number, -- threats ignore prey until this time after being driven off
}

return {}
