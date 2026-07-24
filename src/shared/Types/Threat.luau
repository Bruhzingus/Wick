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
	hoverHeight: number,
	attackHeight: number,
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
	contactAttack: ContactAttackProfile?, -- staged contact instead of continuous drain/immediate snuff
}

-- What a threat is currently doing. Decided by ThreatBrain, executed by the server adapter.
export type ThreatMode = "Wander" | "Seek" | "Flee"

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
	retreatUntil: number, -- ambushers ignore prey until this time after being burned off
}

return {}
