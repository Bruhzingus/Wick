--!strict
-- THE DESCENT LADDER — how a player, or a pair of them, gets from a floor to the one directly below.
--
-- IT IS A ONE-WAY ELEVATOR, MECHANICALLY AND FICTIONALLY. It connects exactly one floor to the next
-- one down. Riders never control its upward return, it cannot be called from below, and it has no
-- connection whatsoever to `ReturnToLobby` — a player who wants to leave the cave uses the Gas Lantern and the existing
-- lobby flow, not this. A bidirectional shaft would let somebody ride back to any earlier floor,
-- which is a different game.
--
-- WHAT THIS REPLACED. The way down used to be an invisible zone around a floating cyan beacon: walk
-- into it and you were instantly on the next floor. There was no mechanism, no consent and no
-- travel. Now there is a real cage on a real winch, a `ProximityPrompt` like every other diegetic
-- interaction in the game (mining, blast doors), and a ride.
--
-- THE RIDE IS REAL TRAVEL, NOT A FADE, and it is affordable for exactly one reason: the next floor
-- is normally already carved by the time anybody reaches the ladder (`RunOrchestrator.ensureLookahead`).
-- If lookahead has not kept up, the server finishes that floor synchronously before committing the
-- riders or broadcasting motion; a cage never descends toward incomplete geometry.
--
-- THE SERVER OWNS THE MOVE AND THE CLIENT OWNS THE MOTION. One timestamped curve is broadcast; every
-- client reconstructs the same analytic descent locally, and the only authoritative transforms the
-- server writes are the cage's bottom pose and its return to rest. This is the pattern
-- `server/ElevatorService` + `client/ElevatorController` already use, for the same reason: replicated
-- per-frame CFrames judder at exactly the moment a player is looking hardest at them.

export type DescentLadderAudioConfig = {
	departCue: string,
	rideCue: string,
	arriveCue: string,
	rideEmitterSeconds: number,
}

export type DescentLadderArrivalConfig = {
	exitGraceSeconds: number,
	pushSeconds: number,
	pushSpeed: number,
	maxHoldSeconds: number,
	forcedExitStuds: number,
	deckVerticalTolerance: number,
	threatGraceSeconds: number,
	openingHeight: number,
}

export type DescentLadderConfig = {
	promptRange: number,
	promptHoldSeconds: number,
	positionToleranceStuds: number,
	rideSeconds: number,
	cageReturnSeconds: number,
	riderCapacity: number,
	riderSpacingStuds: number,
	arrival: DescentLadderArrivalConfig,
	cageWidth: number,
	cageDepth: number,
	cageHeight: number,
	deckThickness: number,
	barThickness: number,
	shaftClearance: number,
	shaftRibSpacing: number,
	shaftRibThickness: number,
	headframeHeight: number,
	chainThickness: number,
	hoistSideOutset: number,
	riderHeadClearRadius: number,
	hatchThickness: number,
	workLamp: {
		enabled: boolean,
		scale: number,
		lightRange: number,
		lightBrightness: number,
	},
	shakeStuds: number,
	shakeHz: number,
	audio: DescentLadderAudioConfig,
	depthAttribute: string,
}

local DescentLadder: DescentLadderConfig = {
	-- Studs the prompt appears at. Wider than the Basin's, because unlike the Basin this is the one
	-- object in the room a player is actively looking for.
	promptRange = 12,
	-- Held, not tapped. Short enough not to be a chore on every floor, long enough that nobody rides
	-- down by brushing a key while a teammate is still two rooms back.
	promptHoldSeconds = 0.45,
	-- Slack added to `promptRange` when the server re-validates the rider is really at the cage
	-- (matches the trust-boundary margins Config/Security owns).
	positionToleranceStuds = 2,
	-- HOW LONG THE RIDE TAKES, and the single most important number in this file. Long enough that
	-- the descent is felt as travel; short enough that it
	-- never becomes a toll a player resents paying on the eighth floor in a row.
	rideSeconds = 4,
	-- After the lower gate closes, the winch visibly hauls the empty cage back to the floor above.
	-- The rider has no lower call control and cannot travel with that return.
	cageReturnSeconds = 3,
	-- HOW MANY RIDE AT ONCE. Two.
	--
	-- IT USED TO BE ONE, and that was the wrong answer rather than a smaller one. A party crosses a
	-- floor together and arrives at the ladder together, so a strict one-rider cage meant the ordinary
	-- case was one player descending and the rest watching a hatch for seven seconds — the ride, plus
	-- the winch hauling the empty cage back — before the next could follow. Worse, the second player
	-- was not merely refused: they were physically stepped off the deck they had walked onto.
	--
	-- TWO, NOT FOUR. The deck grew to carry a pair (see `cageWidth`) and stopped there: a candle is 1.4
	-- studs across, so two stand side by side with real air around them and four would be a crowd
	-- clipping through each other. The lobby's multi-seat company elevator is still a different object
	-- built for a different moment; this is a working cage that takes a pair.
	riderCapacity = 2,
	-- How far each rider stands either side of the cage's centre line. Half the gap between two bodies:
	-- enough that they read as two people sharing a car rather than one candle inside another.
	riderSpacingStuds = 1.2,
	-- THE LOWER LANDING. Riders get a moment to walk out. After that the cage pushes forward gently,
	-- uses a final server-owned placement only as a collision safety net, closes, and returns empty.
	-- Enemy targeting is suspended from commitment through the short post-arrival grace so neither a
	-- closed cage nor its threshold becomes a cheap hit.
	arrival = {
		exitGraceSeconds = 2.5,
		pushSeconds = 1,
		pushSpeed = 5,
		-- HOW LONG THE GATE WAITS ON A DECK THAT IS STILL OCCUPIED, on top of the grace and the push.
		-- Those two are the budget for an arrival that goes normally; this is the allowance for one that
		-- does not, and the cage holds its gate open for the whole of it rather than closing through a
		-- rider who is still aboard. Generous on purpose: 5 studs at walking pace is well under a second,
		-- so anything reaching this deadline is a rider who cannot leave rather than one who is leaving,
		-- and ejecting them is then the kinder outcome for the party waiting on the floor above.
		maxHoldSeconds = 8,
		forcedExitStuds = 5,
		deckVerticalTolerance = 2.5,
		threatGraceSeconds = 2.5,
		openingHeight = 9,
	},
	-- THE CAGE. Open framing on a deck wide enough for two (see `riderCapacity`).
	--
	-- IT GREW FROM 4.2 x 4.2 x 5.2. Two candles fit in the old car arithmetically and it still felt like
	-- a wardrobe from inside it: the ride is first person from a flame standing on the deck, so every
	-- stud between the rider and the frame is the difference between riding in a cage and wearing one.
	-- The extra height matters most — it lifts the upper band and the roof ring clear of a full-wax
	-- candle's eye line instead of leaving them to cross the view for four seconds.
	--
	-- EVERYTHING DOWNSTREAM IS DERIVED, so these three numbers are the only place the cage has a size:
	-- the shaft lining and its guide rails, the collar, the hatch leaves, the terrain cut
	-- (`server/FloorBuilder`), the dressing reservation around the fixture, and the mouth the boarding
	-- check measures all read them. The travel distance is the floor gap owned by `Config/Floors`, so
	-- changing the vertical stack keeps the shaft, cage and landing aligned as one system.
	cageWidth = 5.2,
	cageDepth = 5.2,
	cageHeight = 6,
	deckThickness = 0.4,
	-- Open framing: corner posts and a few bands, never panels. A boxed-in car would turn the ride
	-- into a fade with extra steps, and the whole argument for the ride is that you watch real rock
	-- go past.
	barThickness = 0.26,
	-- Air between the cage and the shaft wall, where the guide rails run.
	shaftClearance = 1,
	-- The rib rings lining the shaft. THESE ARE THE PARALLAX: without something passing the cage at a
	-- regular interval, a descent through a smooth tube reads as standing still in the dark.
	shaftRibSpacing = 5.5,
	shaftRibThickness = 0.32,
	-- The headframe standing over the mouth, carrying the sheave the chain runs over. What makes the
	-- fixture read as machinery going somewhere instead of a hole with a box in it.
	--
	-- TIED TO `cageHeight`, NOT CHOSEN FREELY: `cageHeight + 2`. The builder hangs the hoist chain from
	-- `headframeHeight - 1.4` down to `cageHeight + 0.6`, so this relationship is what makes those two
	-- ends meet on a parked cage — the chain's job is done by the cage's own yoke and stub when it is in
	-- the mouth, and the separate length only appears if a gap opens. Raise the cage without raising
	-- this and the frame sits down inside the car it is supposed to be lifting.
	headframeHeight = 8,
	chainThickness = 0.22,
	-- THE HOIST NEVER RUNS THROUGH THE CAGE. Its cable sits outside the rear-right roof corner; the
	-- shaft cable, parked chain, sheave and cage yoke all derive the
	-- same point. `riderHeadClearRadius` is asserted against every authored seat when the cage builds,
	-- so a future size/spacing retune fails loudly instead of putting hardware through first person.
	hoistSideOutset = 0.5,
	riderHeadClearRadius = 1.6,
	-- The hatch that covers the mouth whenever the cage is not parked in it. Diegetic and structural
	-- at once: it is what a working shaft would have, and it is why an empty shaft is never a pit a
	-- teammate can fall into.
	hatchThickness = 0.3,
	-- THE ONE THING IN THIS CAVE THAT IS ALREADY LIT WHEN YOU FIND IT (`NewModelsAndObjects/Lantern`
	-- builds it — it is the Gas Lantern at three-quarter size, hung off the headframe by its bail).
	--
	-- WHY IT EXISTS. The way down used to be a cyan beacon with a light pillar visible across the
	-- room; retiring that left the ladder as a dark rig you could walk past. This puts a small warm
	-- point back — enough to say "a machine is over here" and to pick out the headframe and the collar
	-- as you approach, and nowhere near enough to light the room or read as the old beacon.
	--
	-- IT CHANGES NOTHING MECHANICAL. A decorative `PointLight` is invisible to `server/LightSources`,
	-- which assembles the perception field from server-owned flames, flares, decoys and remains rather
	-- than by scanning the world — so this cannot alter what a threat sees, what it is drawn to, or how
	-- far away a player can be perceived from. Raise `lightRange` and you make the fixture easier to
	-- find; you never make its rider easier to hunt.
	workLamp = {
		enabled = true,
		scale = 0.75,
		-- Well inside the 64-stud room: the far wall stays dark and the lamp is a point in the black
		-- rather than a lit area. The self-lit flame bead is what carries at range; the light is only
		-- what resolves the rig once you are close enough to walk to it.
		lightRange = 20,
		lightBrightness = 0.85,
	},
	-- Rider camera shudder, in the same currency as the lobby ride's (Config/LobbyRoom). A touch
	-- sharper and faster: this is a rigged cage on a chain, not a company car on rails.
	shakeStuds = 0.08,
	shakeHz = 6.4,
	audio = {
		departCue = "LadderLatch",
		rideCue = "LadderWinch",
		arriveCue = "LadderLatch",
		rideEmitterSeconds = 6,
	},
	-- Written onto every cage so a client can tell one floor's ladder from another's without the
	-- server having to name the instance in more than one place.
	depthAttribute = "WickDescentDepth",
}

return DescentLadder
