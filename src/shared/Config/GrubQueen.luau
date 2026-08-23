--!strict
-- Grub Queen boss tuning, ported from shared/Enemies/GrubQueen.luau plus this game's
-- own encounter decisions layered on top. Immobile, cannot be damaged conventionally — only
-- QueenRegistry's dynamite hookup (server/QueenRegistry.luau, mirrors WardenRegistry) can kill her.
--
-- DYNAMITE IS A FLAT COUNT, NOT DISTANCE-SCALED DAMAGE. Unlike StoneWardenBehavior:Blast(), which
-- runs DynamiteRules.blastDamage(distance) so a far throw contributes less, every stick that
-- detonates within her blast radius counts as exactly one charge toward `health`. This was a
-- deliberate choice: her own module signature (`applyDynamite(charges: number)`) and
-- ENCOUNTERS.md's difficulty knob ("number of dynamite charges required") both read as a literal
-- integer count, not a damage pool. `health = 6, dynamiteDamage = 1` already express that directly
-- — do not scale dynamiteDamage by distance.
--
-- REACHING THE DESCENT LADDER REQUIRES KILLING HER. This is a deliberate exception to this game's
-- usual "every enemy is a hazard to route around, never a hard gate" rule — an owner decision,
-- same class of exception DynamiteService.luau documents for itself (the one place a threat can
-- die). Whoever wires this hooks RunOrchestrator's existing `canDescendFrom(playerId, fromDepth)`
-- to refuse descent from a Queen floor while her QueenRegistry entry is still alive.
--
-- THE CHAMBER IS A HAND-AUTHORED FLOOR, NOT A FLOORPLANNER ROOM MODULE. Unlike WardenDen (one
-- room FloorPlanner attaches inside an otherwise-procedural floor), the Queen occupies an entire
-- bespoke floor layout at the eligible depth — multiple large connected rooms, oversized doorways,
-- heavy dripstone, wax and dynamite pickups scattered on opposite sides so the player is forced to
-- keep moving. Some dynamite and/or wax caches sit under rock the player must mine free mid-fight
-- (reusing MiningService's existing seam-strike interaction) rather than being plain pickups. Room
-- layout, exact pickup counts and cache placement are not config values and are not decided here —
-- that is level-building work, not a tuning knob.

export type GrubQueenConfig = {
	-- Charges required to kill her. See header — flat count, not blast-damage float.
	health: number,
	-- Charge value each detonation within blast radius contributes. Kept at 1 so `health` reads as
	-- a literal number of sticks; do not scale this by distance.
	dynamiteDamage: number,
	broodInterval: number,
	broodCount: number,
	maxLiveGrubs: number,
	-- Longarms spawned by the encounter itself, chained to her — not spawned by her the way grubs
	-- are.
	guardCount: number,
	callInterval: number,
	segmentCount: number,
	-- HOW SHE MOVES. Kept numerically in sync with the pack module's own copies, which is what her
	-- animation reads; these are what the brain reads.
	crawlSpeed: number,
	turnDegreesPerSecond: number,
	-- How far from her spawn she will follow anybody. The chamber, and not a stud more.
	pursuitRadius: number,
	leashRadius: number,
	-- THE BITE. `biteRange` is flat, from her root — her mandible tips already sit 7.6 studs in front
	-- of it, so this is a short lunge past them and not a reach out of nowhere. `biteArcDot` is the
	-- cosine of the half-angle she can bite through: 0.35 is about 70 degrees off her facing, so
	-- anything beside or behind her is safe until she turns, which she does slowly.
	biteRange: number,
	biteArcDot: number,
	biteDamage: number,
	biteInterval: number,
	-- Cadence between eligible boss floors, in floor count. ENCOUNTERS.md: "one per 10-15 floors."
	minIntervalFloors: number,
	maxIntervalFloors: number,
	-- Killing her is mandatory before the floor's descent ladder will accept a rider. See header.
	requiresKillToDescend: boolean,
}

local GrubQueen: GrubQueenConfig = {
	health = 6,
	dynamiteDamage = 1,
	broodInterval = 7.5,
	broodCount = 2,
	-- TEN, DOWN FROM FOURTEEN. At two every 7.5 seconds she reaches the cap in under a minute and then
	-- holds it there for the rest of the fight, so this number is not "how many she makes" — it is how
	-- crowded her chamber is for the whole encounter. Fourteen grubs plus two Longarms plus her own
	-- twenty-four-stud body left no floor to fight on, and the brood stopped reading as pressure and
	-- started reading as terrain.
	maxLiveGrubs = 10,

	guardCount = 2,
	callInterval = 26,
	segmentCount = 9,
	-- A quarter of a walk (Config/Movement.walkSpeed = 8) and an eighth of a run. She is not a chase
	-- and must never become one: what she takes from the player is the ability to stand still, and a
	-- Queen who could close on somebody would be taking the fight instead.
	crawlSpeed = 1.8,
	-- Fifteen seconds to come about. This is the counter to the bite, and it is meant to be generous.
	turnDegreesPerSecond = 24,
	pursuitRadius = 90,
	-- SIZED TO THE CHAMBER SHE IS ACTUALLY IN, exactly as `guardLeashRadius` is (Logic/BossFloorPlan)
	-- and for the reason BossEncounterService writes out for the guards: the encounter is meant to be
	-- survivable by leaving the room, and anything that leaves with you deletes that.
	--
	-- IT WAS 46 AND THE ROOM IS 60 ACROSS. Her chamber is one grid cell, so its open floor reaches 30
	-- studs from the centre (RoomFootprint.maximumHalfExtent) — a 46-stud leash let her crawl out
	-- through a doorway and a good way down an arm after somebody, which is the one thing her design
	-- says she must never do. 34 covers the whole chamber including its corners (the half-diagonal is
	-- 42, but the corners are rock, not floor) plus the doorway thresholds, and stops at them.
	leashRadius = 34,
	biteRange = 9.0,
	biteArcDot = 0.35,
	-- THE BIGGEST SINGLE HIT IN THE GAME, and deliberately so: 80% of `Config.Wax.maxWax` against the
	-- Longarm's grab at 0.55 and the falling spire at 0.55. It is survivable from anything above four
	-- fifths of a candle and it is the only attack in the game a player can be certain of avoiding —
	-- it is telegraphed by a half-second rear-back and it only lands in front of her. Standing in the
	-- mouth of the thing the whole floor is about should cost nearly everything.
	biteDamage = 0.8,
	-- Long enough that surviving one bite is a chance to get out rather than a stay of execution.
	biteInterval = 4.5,
	minIntervalFloors = 10,
	maxIntervalFloors = 15,
	requiresKillToDescend = true,
}

return GrubQueen
