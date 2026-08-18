--!strict
-- The Knotwalker's tripwire: a vine drawn taut across a doorway, ankle-high, waiting.
--
-- WHAT THIS CREATURE BECAME AND WHY THE NUMBERS ARE SMALL. The Knotwalker used to chase a prediction
-- of your route. It now works the way its cave does — Moss is the family of "obstructed information"
-- (Config/CaveFamilies), and a trap is that identity as a thing you walk into rather than a thing
-- that walks at you. The whole encounter is the STUMBLE: the wire costs almost no wax by itself, and
-- what it actually takes is the seconds you spend on the floor with something standing over you.
-- Every number below is therefore about TIME, not damage.
--
-- THREE ANSWERS, and the wire is beaten by any of them:
--   * SEE IT AND STEP OVER. It is a couple of inches off the ground and it is lit by nothing, so this
--     is entirely a question of whether you were looking. `hopClearanceStuds` is what a hop clears.
--   * BURN IT. Maximum brightness held next to it for `burnSeconds`. Deliberately the same key as a
--     vine curtain (Logic/VineRules.burnsVines is called directly rather than re-derived) so the dial
--     means one thing everywhere in the game — this is just a far cheaper lock than a curtain.
--   * OUTRUN THE OWNER. Being tripped is survivable on its own; it is only expensive if the
--     Knotwalker is close enough to reach you before you are up.
--
-- THE FASTER YOU ARE GOING, THE LONGER YOU ARE DOWN, which is the one rule that makes the trap read
-- as a trap rather than as a tax. A player who walks a doorway they are unsure of loses a second; a
-- player who sprints blind through it loses three and hears something coming.

export type TripwireConfig = {
	enabled: boolean,
	-- The wire itself.
	geometry: {
		-- Height of the strand above the measured floor. "A couple of inches": deliberately under a
		-- tenth of a stud so it reads as something you could have stepped over and did not.
		heightStuds: number,
		-- Thickness of the drawn strand, and of the slack loops sagging off it.
		strandThickness: number,
		-- How much of the doorway's width the wire spans, as a fraction. Under 1 so the wire is always
		-- anchored in rock at both ends rather than floating in the opening.
		spanFraction: number,
		-- Sag between the anchors, as a fraction of the span. A dead-straight wire looks like a laser.
		sagFraction: number,
		-- Segments the strand is drawn with. Enough for the sag to curve, few enough that a floor
		-- carrying several wires is still a handful of parts.
		segmentCount: number,
		-- Little knots and hairs hanging off the strand, so it reads as grown rather than strung.
		knotCount: number,
		knotSize: number,
		strandColor: Color3,
		strandMaterial: Enum.Material,
	},
	-- What tripping costs.
	trip: {
		-- The stun band. A player barely moving loses `minStunSeconds`; one at `fullStunSpeed` or above
		-- loses `maxStunSeconds`. The owner's brief: 1 to 3 seconds, by speed.
		minStunSeconds: number,
		maxStunSeconds: number,
		-- The speed that earns the full stun. Config/Movement.runSpeed is 16, so a running player is
		-- the one taking the whole three seconds.
		fullStunSpeed: number,
		-- Under this speed the wire is stepped over rather than run into: it does not fire at all.
		-- Somebody edging through a doorway they suspect is trapped is not the victim this creature is
		-- built for.
		minimumTripSpeed: number,
		-- Feet higher than this above the wire clear it. This is the hop (Config/Movement.hopPower).
		hopClearanceStuds: number,
		-- Wax the fall itself costs. Almost nothing — see the header. The cost is the seconds.
		waxDamage: number,
		-- One wire is one trip. A player who gets up standing on a broken wire is not tripped again.
		consumedOnTrip: boolean,
		-- After getting up, the wires on this floor cannot catch this player again for this long. It
		-- covers the moment where you stand up already inside a doorway you were tripped in.
		getUpGraceSeconds: number,
	},
	-- Burning it off. The brightness bar itself is Logic/VineRules' — only the exposure is ours.
	burn: {
		-- Seconds of qualifying light held within `radiusStuds` before the wire catches. A vine curtain
		-- asks for several; a single strand is one fifteenth of the mass and asks for 1.5.
		seconds: number,
		radiusStuds: number,
		-- How long the burnt strand stays visible, shrivelling, before it is removed.
		charSeconds: number,
	},
	-- A wire nobody has touched expires, so an abandoned floor does not stay strung forever and a
	-- creature that wandered off eventually re-lays somewhere that matters.
	--
	-- HOW MANY, WHERE, AND WHAT STANDS OVER YOU AFTERWARDS ARE NOT HERE. Those belong to the body that
	-- lays them and live on its row as `trapline` (Config/Threats, Types/Threat.TraplineProfile). This
	-- file is the WIRE: the same strand would behave the same way whatever strung it.
	armedSeconds: number,
	messages: {
		tripped: string,
		burned: string,
	},
}

local Tripwire: TripwireConfig = {
	enabled = true,
	geometry = {
		-- ~2.5 inches at this game's scale.
		heightStuds = 0.21,
		strandThickness = 0.13,
		spanFraction = 0.92,
		sagFraction = 0.07,
		segmentCount = 7,
		knotCount = 5,
		knotSize = 0.26,
		-- Moss-dark and unlit, like every other piece of growth in this cave. ART-BIBLE §4: nothing
		-- self-illuminates, so the only reason you ever see this is that you brought light to it.
		strandColor = Color3.fromRGB(58, 74, 44),
		strandMaterial = Enum.Material.Grass,
	},
	trip = {
		minStunSeconds = 1,
		maxStunSeconds = 3,
		fullStunSpeed = 16,
		-- Half of walk speed (Config/Movement.walkSpeed is 8).
		minimumTripSpeed = 4,
		hopClearanceStuds = 1.1,
		waxDamage = 0.02,
		consumedOnTrip = true,
		getUpGraceSeconds = 1.5,
	},
	burn = {
		seconds = 1.5,
		radiusStuds = 7,
		charSeconds = 2.5,
	},
	armedSeconds = 150,
	messages = {
		tripped = "Something caught your ankle.",
		burned = "The strand curls and goes out.",
	},
}

return Tripwire
