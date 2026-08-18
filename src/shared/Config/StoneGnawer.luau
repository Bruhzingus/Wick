--!strict
-- Stone Gnawer tuning, ported from shared/Enemies/StoneGnawer.luau. Tier 3 blind
-- charger: hunts entirely by sound, never reacts to light. Structurally the Lethal Company dog —
-- eat, hear, warn, charge in a straight line, stagger on collision.
--
-- `chargeDamage` IS A WAX-DRAIN AMOUNT, NOT HEALTH DAMAGE. Nothing in this game has a Humanoid
-- health pool for players — every hit routes through WaxService.drainExternal, the same channel
-- every existing threat's contactAttack uses (see ThreatService.applyContact). Whoever wires the
-- charge-collision handler needs to call drainExternal with this number, not Humanoid:TakeDamage.
--
-- `warnSeconds` MUST NOT SHRINK. 1.1s already accounts for ~150-300ms of Bluetooth audio latency;
-- CLAUDE.md is explicit that anything under ~450ms means the tell arrives after the hit lands.
--
-- `chargeDamage` IS A FRACTION OF `Config.Wax.maxWax` (1.3), NOT THE PACK'S ORIGINAL RAW UNITS. The
-- vendored pack shipped `chargeDamage = 55` — a number from whatever scale it was authored against,
-- not this game's. Left untouched it was 42x the entire candle: an unconditional, unavoidable
-- burnout on any charge hit, sleeve absorption included. Rescaled to the single worst fraction on
-- the roster (worse than any Hazards.luau falling formation, which top out at 0.55) — this creature
-- is meant to be the most punishing avoidable hit in the game, not a guaranteed run-ender regardless
-- of how much wax you were carrying.

local Types = require(script.Parent.Parent.Types)

export type StoneGnawerConfig = {
	health: number,
	walkSpeed: number,
	chargeSpeed: number,
	chargeDamage: number,
	chargeLockSeconds: number,
	staggerSeconds: number,
	hearSprint: number,
	hearWalk: number,
	-- How a cave noise's authored loudness (Config/Sound.emitters) becomes the 0..1 this creature's
	-- hearing is expressed in, where 1 means "as loud as a sprinting player". Anything at or above it
	-- saturates: the creature has no louder response than committing, so a detonation and a footfall
	-- produce the same charge, just from further away.
	--
	-- IT LIVES HERE RATHER THAN IN THE BEHAVIOR because it decides, together with `hearSprint` and an
	-- emitter's radius, how far any given noise is actually heard from — and that is a number worth
	-- being able to assert against rather than one buried in a server file.
	-- A JUMP IS A STOMP, and this is how far away it commits to one.
	--
	-- Landings need their own reach because the shared sound field cannot give them one. A landing's
	-- emitter is authored at radius 30 (Config/Sound) and that number is holding up the Cave Listener's
	-- contract — widen it and jumping starts summoning the creature whose whole promise is that it only
	-- answers mining, falling stone and the bell. So the reach lives here, measured against the event's
	-- own position, exactly as the Wax Grub's `stompRadius` does for the same event.
	--
	-- WHY IT IS THE FULL `hearSprint` AND NOT LESS. Through the field alone a landing died about 24
	-- studs out — LESS far than this creature hears a sprinting player (38), which made the loudest
	-- thing a player can do on foot the quietest thing it could notice. A body hitting rock is the one
	-- movement noise that should reach this creature's ceiling.
	hearLanding: number,
	-- FALLING STONE IS THE SOUND IT CANNOT IGNORE, and it gets its own reach for the same structural
	-- reason landings do: the pack's `hearNoise` caps every reaction at `hearSprint` regardless of how
	-- loud the thing was, so a collapsing dripstone column and a footstep committed it from exactly the
	-- same distance. The cave's own field already carries a `DripstoneImpact` at full perceived
	-- loudness to about 67 studs (Config/Sound: loudness 1.4, radius 85, against this creature's
	-- `sprintReferenceLoudness` of 0.3) — the 42-stud cap was throwing that away.
	hearDripstone: number,
	sprintReferenceLoudness: number,
	-- HUNTING: what it does about a noise too far away to charge at.
	--
	-- This is a SECOND CHANNEL, not a bigger version of the first. Inside the reaches above it does
	-- what it has always done — head up, aim, commit. Beyond them, a big structural noise makes it
	-- WALK there, and the two must not blur: a creature that charged at things it could not reach
	-- would be charging blind across rooms, and one that only ever hunted would never be dangerous.
	--
	-- WHY IT HEARS THESE AT ALL AT THIS RANGE. The kinds below are rock breaking, not air moving, and
	-- an eyeless thing with its jaw on the floor feels them through the floor. That is this creature's
	-- own channel exactly as the movement one is, and it is why the reach is measured off the raw
	-- event rather than through `SoundField` — the field describes what the cave HEARS, and a
	-- dripstone impact stops being audible at 85 studs while the shock through the rock does not.
	huntRadius: number,
	-- Floors stack 96 studs apart (Config/Floors.geometry.floorGap) and `huntRadius` is larger than
	-- that, which breaks the "no depth filter needed" invariant every other channel on this creature
	-- relies on. This is the filter: a vibration more than this far above or below is somebody else's
	-- floor collapsing, not this one's.
	huntVerticalBand: number,
	-- How long it will keep walking toward one before giving up. Generous, because the walk is slow
	-- (6 studs/s) and the point is that it commits to the trip.
	huntSeconds: number,
	-- Close enough to call it arrived, at which point it stops and listens rather than standing on the
	-- spot — which is what turns a hunt into an ambush for whoever set the noise off.
	huntArriveRadius: number,
	-- HOW OFTEN IT SNUFFLES WHILE HUNTING, in seconds, as a base and a jitter added on top. Rolled per
	-- snuffle from the creature's own rng, so two Gnawers crossing the same floor never fall into step
	-- — which is the single thing that would make it read as a machine rather than an animal.
	snuffleSeconds: number,
	snuffleJitterSeconds: number,
	-- The noise kinds worth crossing a floor for. Every one of them is the cave itself breaking.
	-- Player noises are deliberately absent: sprinting and landing are the CHARGE channel, and a
	-- Gnawer that walked toward footsteps from 150 studs would never leave anybody alone.
	huntKinds: { [string]: boolean },
	warnSeconds: number,
	-- GRAZING. How long it must go undisturbed in `listen` before it puts its head back down, how far
	-- it will drift from where it spawned while doing so, and how long it stands at each grazing spot.
	grazeSettleSeconds: number,
	grazeRadius: number,
	grazePauseSeconds: number,
	grazePauseJitterSeconds: number,
	-- TWO STICKS, and the only creature on the roster besides the Warden that survives one. It is the
	-- heaviest body here and the encounter is built around escaping a charge rather than answering it;
	-- a single stick that removed it would make the dodge optional for anybody holding one.
	--
	-- A NON-LETHAL BLAST SHOULD LAND IT IN ITS OWN `stagger` STATE (staggerSeconds above, 2.0s) rather
	-- than only setting the roster-wide driven-off clock below. Same beat as hitting a wall mid-charge,
	-- which is the reaction a player already knows how to read on this creature.
	blast: Types.BlastProfile,
}

local StoneGnawer: StoneGnawerConfig = {
	health = 140,
	walkSpeed = 6,
	chargeSpeed = 26,
	-- ~58% of max: the worst single hit in the game, deliberately above every Hazards.luau ceiling.
	chargeDamage = 0.75,
	chargeLockSeconds = 1.6,
	staggerSeconds = 2.0,
	-- ITS EARS, AND THEY ARE DELIBERATELY WORSE THAN THE CAVE LISTENER'S.
	--
	-- The Listener hears a pick from 95 studs and a runner from 34 (Config/Threats.Listener.hearing).
	-- This creature is the escalation of that idea, and an escalation that was better at everything
	-- would just be the Listener again with a bigger number — so it gives ground on perception and
	-- takes it back on what happens next. 42 studs at a full sprint is under half the Listener's reach
	-- for a pick, and 16 when you are barely moving.
	--
	-- WHAT IT BUYS INSTEAD is the charge: 26 studs per second for 1.6 seconds is roughly forty studs
	-- crossed in a straight line, which is further than it could hear you standing still. That is the
	-- whole creature — it notices less of the floor than the Listener does, and answers what it does
	-- notice from much further away and much faster than you can walk out of.
	hearSprint = 42,
	hearWalk = 16,
	hearLanding = 42,
	-- SUPER SENSITIVE TO FALLING STONE, and this is the number that says so: 72 studs against 42 for a
	-- sprinting player. A dripstone coming down anywhere in the same room, or through the doorway of
	-- the next one, gets the full head-up-and-commit response — and since a charge covers about forty
	-- studs, a fall at the far end of that reach is a Gnawer that arrives rather than one that gets
	-- there. Beyond it, `huntRadius` takes over and it walks instead.
	hearDripstone = 72,
	sprintReferenceLoudness = 0.3,
	-- Two rooms and a bit (Config/Floors.geometry.cellSize is 64), so a collapse in the next room over
	-- is always worth the walk and one at the far end of the floor is not.
	huntRadius = 150,
	huntVerticalBand = 40,
	-- 22 seconds at 6 studs a second is 130 studs of walking, which covers the radius with enough
	-- margin for pathing round a chamber rather than through it.
	huntSeconds = 22,
	huntArriveRadius = 7,
	-- 0.7 to 2.1 seconds apart. Fast enough that the creature is plainly working at something, slow
	-- enough to leave the gaps an animal casting for a scent actually has — and the gaps are where a
	-- player hears it coming, because the snuffle is the only sound it makes while it travels.
	snuffleSeconds = 0.7,
	snuffleJitterSeconds = 1.4,
	huntKinds = {
		-- Falling stone: the one this creature is built around.
		DripstoneImpact = true,
		-- The two detonations. A player who blows a seam or throws a stick has told every Gnawer on the
		-- floor roughly where they are standing, which is a cost those tools should have.
		SeamExplosion = true,
		DynamiteBlast = true,
		-- A seam actually breaking open. Quieter and shorter-ranged than the detonations by its own
		-- emitter (Config/Sound: radius 74 against 150), so in practice this one only pulls a Gnawer
		-- that was already fairly close.
		MineBreak = true,
	},
	warnSeconds = 1.1,
	-- LONG ENOUGH THAT SETTLING IS AN EVENT, SHORT ENOUGH THAT THE ROOM RECOVERS. 3.5s of genuine quiet
	-- is well past the 1.6s charge and the 2.0s stagger, so a Gnawer never puts its head down in the
	-- middle of an exchange — it settles only once the player has actually stopped, which is what makes
	-- the eat loop starting again a usable "it lost me" signal rather than noise.
	grazeSettleSeconds = 3.5,
	-- A GNAWER IS A FEATURE OF A ROOM. It orbits its spawn point and never leaves it: 14 studs is enough
	-- that the body has visibly moved when you come back, and far short of any doorway it could wander
	-- out of and into a floor budget that never accounted for it.
	grazeRadius = 14,
	grazePauseSeconds = 4,
	grazePauseJitterSeconds = 3,
	blast = { hitPoints = 2, staggerSeconds = 6 },
}

return StoneGnawer
