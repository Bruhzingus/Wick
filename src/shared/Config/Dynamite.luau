--!strict
-- DYNAMITE — the found consumable, its blast, and the sealed vaults it opens.
--
-- WHAT IT IS FOR, in one line: it is the only thing in the cave that answers a problem by removing it,
-- and it is deliberately rare enough that a player never has one when they most want one.
--
-- IT IS NOT A TOOL (Types/Dynamite explains the type-level reason). It costs no wax, has no cooldown,
-- cannot be sacrificed at the Basin, and does exactly nothing unless you found one. The gate is the
-- count, and the count is small.
--
-- THE NO-COMBAT EXCEPTION LIVES HERE. DESIGN pillar 2 says threats are read and managed, never
-- defeated, and every other verb in the game still obeys that. Dynamite is the authored exception
-- (DESIGN §6a, owner decision): `threat` below is per-creature blast health, so one stick removes a
-- crawler and one stick is an inconvenience to a Warden. Three things keep the exception from
-- swallowing the pillar, and all three are numbers in this file rather than good intentions:
--
--   1. SUPPLY. `supply` hands out roughly one stick every two floors. You cannot solve rooms with it.
--   2. SELF-HARM. `blast.playerWaxCost` is the largest single hit in the game, and the blast does not
--      care who lit it. Using this in a corridor you are standing in is a real decision.
--   3. NOISE. `blast.alertRadius` calls the whole floor to the crater, exactly as an Explosive Seam
--      does. Killing the thing in front of you is the loudest possible way to announce yourself.
--
-- Its OTHER use is the quiet one and the reason it exists at all: blast vaults (`vault` below) are
-- sealed dead-end rooms full of ore and empty of creatures. Spending a stick on rock instead of on a
-- creature is the trade this whole item is built around.

local Types = require(script.Parent.Parent.Types)

export type DynamiteSupplyConfig = {
	stickMinGap: number,
	stickMaxGap: number,
	stickFirstDepth: number,
	crateMinGap: number,
	crateMaxGap: number,
	crateFirstDepth: number,
	crateCharges: number,
	maxCarried: number,
	scheduleIterationCap: number,
}

export type DynamiteFuseConfig = {
	thrownSeconds: number,
	socketedSeconds: number,
	sparkTickSeconds: number,
}

-- A REAL THROW. `range` is the distance covered at the ideal 45-degree launch and every other angle
-- resolves shorter; `Logic/DynamiteRules` derives the release speed from `range` and `gravity` so
-- there is no separate speed to keep in sync with the distance.
--
-- This deliberately does NOT reuse `Types.ThrowPlacement` any more. That shape belongs to the Decoy,
-- which is genuinely a placement — it resolves a horizontal point at a fixed distance and seats a
-- candle there. Dynamite is thrown. Sharing one type meant carrying `throwArcHeight`,
-- `maxGroundSlopeDegrees` and `surfaceOffset` fields that ballistics has no use for, and readers had
-- to know which half of the block was live.
export type DynamiteThrowConfig = {
	range: number,
	gravity: number,
	launchHeight: number,
	simulationSteps: number,
	maxFlightSeconds: number,
	obstructionInset: number,
	groundProbeHeight: number,
	groundProbeDepth: number,
	animationSeconds: number,
	-- The shortest a flight may be, as a fraction of `animationSeconds`. The flight is scaled by how
	-- far the stick actually travelled, so a charge dropped at your feet lands almost at once and a
	-- full-range throw takes the whole beat; without a floor, a one-stud drop would take zero seconds
	-- and pop into existence on the ground.
	minimumAnimationFraction: number,
	restHeight: number,
	restSampleRadius: number,
}

-- THE STICK IN YOUR HANDS (client/DynamiteViewmodelController).
--
-- CAMERA-SPACE POSES, exactly like Config/Mining.pickaxe, and for the same reason: a run is locked
-- first person (client/CameraController) and the player's body is a candle, so every tool this game
-- draws is a floating object in camera space rather than something held by a rigged arm.
--
-- THREE POSES AND THE TRIPS BETWEEN THEM. HELD is the stick carried at the hip once equipped.
-- WINDUP is it cocked back beside the head while the button is down. RELEASE is the end of the whip
-- forward, and the stick is hidden the instant the pose reaches it — from there the thrown charge
-- the server spawned is the only stick in the world, which is what stops there ever being two.
export type DynamiteViewmodelConfig = {
	stickScale: number,
	heldOffset: CFrame,
	windupOffset: CFrame,
	releaseOffset: CFrame,
	drawSeconds: number,
	stowSeconds: number,
	-- How long the button must be held to reach a full cock. Releasing early is not punished: the
	-- throw simply starts from however far back the arm actually got, the same way a mining strike
	-- starts from the live prime (Config/Mining.pickaxe.primeSweepFraction).
	windupSeconds: number,
	releaseSeconds: number,
	recoverSeconds: number,
	releaseSpinDegrees: number,
	bobStuds: number,
	bobSeconds: number,
	swayDegrees: number,
	-- How much of the idle breathing the wind-up damps out. A cocked arm is a steady arm.
	windupSteadiness: number,
}

export type DynamiteBlastConfig = {
	radius: number,
	playerWaxCost: number,
	minimumWaxCost: number,
	shakeRadius: number,
	floorShakeStrength: number,
	shakeStuds: number,
	shakeDegrees: number,
	shakeSeconds: number,
	shakeFrequency: number,
	alertRadius: number,
	alertSeconds: number,
	noiseKind: string,
}

-- Cue names in `Config/Audio.cues`.
--
-- THE HANDLING CUES ARE LOCAL AND NON-SPATIAL. Equipping, cocking and releasing are things happening
-- in the player's own hands a foot from their own ears; they are mixed as UI-adjacent Focus one-shots
-- rather than as world events. The two that ARE world events — the fuse and the blast — were already
-- here and are unchanged: those are heard by everybody, from wherever the charge actually is.
export type DynamiteAudioConfig = {
	fuseCue: string,
	blastCue: string,
	equipCue: string,
	stowCue: string,
	windupCue: string,
	throwCue: string,
	-- Pressing the key with an empty bag, or a throw the server refused. The one cue that says "that
	-- did not happen", so a failed throw is never silence the player has to interpret.
	deniedCue: string,
}

export type DynamiteThreatConfig = {
	default: Types.BlastProfile,
	wardenHitPoints: number,
	wardenStunSeconds: number,
	wardenSlowMultiplier: number,
	wardenSlowSeconds: number,
}

export type DynamiteDoorConfig = {
	thrownBreakRadius: number,
	socketCatchRadius: number,
	socketRange: number,
	socketHoldSeconds: number,
	placeActionText: string,
	objectText: string,
	rubbleLifetimeSeconds: number,
	rubblePieces: number,
}

export type DynamiteVaultConfig = {
	enabled: boolean,
	roomModuleId: string,
	minDepth: number,
	chancePerFloor: number,
	secondVaultChance: number,
	maxPerFloor: number,
	ceilingHeight: number,
	depositsMin: number,
	depositsMax: number,
	loot: number,
}

export type DynamiteVisualConfig = {
	stickLength: number,
	stickRadius: number,
	stickColor: Color3,
	wrapColor: Color3,
	bandColor: Color3,
	capColor: Color3,
	fuseColor: Color3,
	fuseSegments: number,
	fuseLength: number,
	fuseRadius: number,
	fuseCurl: number,
	crateSticks: number,
	crateSize: Vector3,
	crateColor: Color3,
	crateSlatColor: Color3,
	crateBandColor: Color3,
	sparkColor: Color3,
	socketGlowColor: Color3,
	socketGlowTransparency: number,
	socketPulseSeconds: number,
	socketPulseDepth: number,
	doorThickness: number,
	doorArchRiseFraction: number,
	doorSocketDepth: number,
	socketStandoff: number,
	doorFaceRocks: number,
	doorRockMinSize: number,
	doorRockMaxSize: number,
	doorCrackCount: number,
	doorCrackThickness: number,
	styleColors: { [Types.BlastDoorStyle]: Color3 },
	styleMaterials: { [Types.BlastDoorStyle]: Enum.Material },
	styleCrackColors: { [Types.BlastDoorStyle]: Color3 },
}

export type DynamiteConfig = {
	enabled: boolean,
	supply: DynamiteSupplyConfig,
	fuse: DynamiteFuseConfig,
	throw: DynamiteThrowConfig,
	viewmodel: DynamiteViewmodelConfig,
	blast: DynamiteBlastConfig,
	audio: DynamiteAudioConfig,
	threat: DynamiteThreatConfig,
	door: DynamiteDoorConfig,
	vault: DynamiteVaultConfig,
	visual: DynamiteVisualConfig,
}

local Dynamite: DynamiteConfig = {
	enabled = true,
	-- HOW OFTEN THE CAVE HANDS ONE OVER, as a deterministic schedule rather than a per-floor dice roll.
	-- `Logic/DynamiteRules.supplyForDepth` walks the gaps from a run seed, so a run genuinely gets a
	-- stick every one-to-three floors instead of "50% per floor", which is the same average and
	-- occasionally means six dry floors in a row. A player should be able to form the habit of
	-- expecting one soon without ever knowing which floor.
	supply = {
		stickMinGap = 1,
		stickMaxGap = 3,
		-- THE SCHEDULE STARTS ON THIS FLOOR RATHER THAN ROLLING FOR IT, so floor 2 always carries a
		-- stick and every run's introduction to the item happens at the same, early, survivable place.
		-- After that the gaps are rolled and nobody knows which floor is next. Floor 1 is left alone
		-- deliberately: it is where a player learns the dial, and an explosive in the first room they
		-- ever walk into would be the loudest possible way to teach the wrong lesson first.
		stickFirstDepth = 2,
		-- THE CRATE IS A RUN EVENT, not a resupply. At 10-20 floors apart most expeditions never see
		-- one, and the ones that do are deep enough that three sticks is genuinely a different run.
		crateMinGap = 10,
		crateMaxGap = 20,
		crateFirstDepth = 8,
		crateCharges = 3,
		-- The carry cap is what stops a long run from becoming an armoury. Low enough that finding a
		-- crate while nearly full genuinely wastes sticks, which is the pressure that makes a player
		-- spend the one they are holding.
		maxCarried = 4,
		-- Defensive bound on the schedule walk; an expedition has no floor cap, and a pure function
		-- should not be the thing that discovers that.
		scheduleIterationCap = 4096,
	},
	-- THE FUSE IS THE WHOLE INTERACTION, exactly as it is for the Explosive Seam, and it is authored
	-- against the same three seconds for the same reason: three seconds is long enough to get out of
	-- your own blast and far too short to get out of the room.
	--
	-- A SOCKETED CHARGE BURNS LONGER. You light it standing at the door with your back to whatever is
	-- behind you, so the extra second is the walk away from a thing you chose to do, not a reaction
	-- window you were given.
	fuse = {
		thrownSeconds = 3,
		socketedSeconds = 4.5,
		sparkTickSeconds = 0.25,
	},
	-- Throwing reuses the Decoy's validated arc wholesale (`Logic/ToolRules.throwHorizontalPoint` and
	-- `throwArcPoint`), so a stick obeys the same rule a decoy does: vertical aim never buys range, and
	-- a wall shortens the throw rather than letting it pass through.
	--
	-- IT THROWS FURTHER THAN A DECOY (30 vs 25) and that is the item working: distance is the only
	-- protection a thrower has, so the reach is what turns this from a suicide charge into a decision.
	throw = {
		-- THE DISTANCE A THROW COVERS AT THE IDEAL 45-DEGREE LAUNCH, and the only number the throw's
		-- physics needs. `DynamiteRules.launchSpeed` derives the release speed from this and `gravity`
		-- as `sqrt(range * gravity)`; every other angle falls out of the arithmetic and is SHORTER.
		--
		-- So this is a ceiling, not a fixed distance. A flat throw carries maybe two-thirds of it, a
		-- steep one much less, and one aimed at your own feet lands there. Raising it makes every throw
		-- longer at every angle rather than only the ideal one.
		range = 30,
		-- Roblox's own default. Authored here rather than read from `Workspace.Gravity` so the arc is a
		-- pure function of config — the same simulation runs in a cold test as on a live server, and a
		-- future change to world gravity for some unrelated reason cannot silently retune the throw.
		gravity = 196.2,
		-- Where the stick leaves the body, above the candle's base. Roughly hand height on a full-size
		-- candle; the arc starts here rather than at the feet so a flat throw clears the ground it is
		-- launched from.
		launchHeight = 1.5,
		-- How the server walks the arc looking for what the stick hits. `maxFlightSeconds` is a safety
		-- ceiling rather than an expected duration — an ideal 45-degree throw is airborne for well under
		-- a second, and only a near-vertical throw from a high ledge approaches this.
		simulationSteps = 48,
		maxFlightSeconds = 2.4,
		-- Pulled back from whatever surface the arc struck, so a stick never resolves flush inside the
		-- rock it hit.
		obstructionInset = 0.6,
		-- Fallback ground probe, used only when the arc runs its full length without striking anything.
		groundProbeHeight = 8,
		groundProbeDepth = 24,
		-- A rare throw should actually leave the hand rather than teleporting to its resolved landing.
		-- Short enough that it never steals meaningful time from the three-second fuse.
		--
		-- THIS IS THE FULL-RANGE FLIGHT, not every flight. `DynamiteService.animateThrownCharge` scales
		-- it by how far the stick actually went, because a fixed duration made a charge dropped at your
		-- feet drift down over the same third of a second as one thrown thirty studs — which reads as
		-- the stick floating rather than being dropped.
		animationSeconds = 0.38,
		minimumAnimationFraction = 0.35,
		-- Lift above the sampled surface. Matched to `Config/Loot.surfaceClearance` rather than to the
		-- stick's own radius: this number's job is to clear Terrain's voxel interpolation, not to look
		-- proportionate, and the old 0.22 was inside that error — which is what put thrown sticks in the
		-- floor. Every other floor-sitting object in the game clears by at least this much.
		restHeight = 0.4,
		-- Radius of the nine-point ground sample (`SurfaceProbe.tryGroundY`). Roughly the stick's own
		-- footprint, so a charge landing on the shoulder of a voxel hump seats on the hump rather than
		-- on the dip beside it.
		restSampleRadius = 1.2,
	},
	-- THE BLAST. Read this next to `Config/Mining.explosive`: a stick is a smaller radius than a seam
	-- going up but costs more wax at the centre, because a seam is something the cave did to you and
	-- this is something you did to yourself.
	blast = {
		radius = 26,
		-- At point blank. Falls off linearly to nothing at `radius`. The single largest discrete hit in
		-- the game — it does NOT kill a full candle outright, deliberately, because what should end a
		-- greedy run is what walks in afterwards rather than the explosion itself.
		playerWaxCost = 0.62,
		-- Below this the hit is dropped entirely rather than logged as a rounding smear on the ledger.
		minimumWaxCost = 0.01,
		-- Players outside the strong local shake still feel this fraction of it anywhere on the same
		-- floor. The blast is a floor event, but the distant response stays restrained enough that it
		-- cannot be mistaken for being inside the damage radius.
		shakeRadius = 70,
		floorShakeStrength = 0.18,
		-- THE BLAST'S OWN SHAKE. It used to borrow the falling dripstone's numbers wholesale, which made
		-- the loudest single event in the game read exactly like a rock landing near you: same size,
		-- same duration, same 41 rad/s buzz. These are the same shape, tuned for what this actually is.
		--
		-- Bigger and lower than a stone impact: 0.16 studs against the dripstone's 0.1, and 26 rad/s
		-- (~4 Hz) against its 41, because an explosion is a heavy shove and falling rock is a sharp
		-- rattle. Held a little longer for the same reason -- a blast has a tail.
		--
		-- Still restrained in absolute terms. Dynamite is the one thing in the game that can kill
		-- (DESIGN section 6a) and the shake is not where that is communicated: the wax cost, the noise
		-- it draws and the dead ground it leaves are. This says "that was enormous", then gets out of
		-- the way so the player can see what walks in afterwards.
		shakeStuds = 0.16,
		shakeDegrees = 1.6,
		shakeSeconds = 0.55,
		shakeFrequency = 26,
		-- The floor comes looking, exactly as it does for a detonating seam. This is the price of the
		-- loud answer and it is why dynamite never becomes the default one.
		alertRadius = 150,
		alertSeconds = 12,
		noiseKind = "DynamiteBlast",
	},
	-- THE HELD STICK. Tuned against the pickaxe's own poses so the two tools sit in the same part of
	-- the screen and read as belonging to one pair of hands. Positions are camera space: +X right,
	-- +Y up, -Z forward.
	viewmodel = {
		-- Very slightly under-scaled. At 1.0 a 1.35-stud stick this close to the camera eats the bottom
		-- right of the screen, and this is a thing the player has to be able to see PAST.
		stickScale = 0.92,
		-- HELD: carried low and right, angled across the body. Out of the way of the cave, and low
		-- enough that it never covers the middle distance where a threat resolves out of the dark.
		heldOffset = CFrame.new(0.92, -0.82, -1.66) * CFrame.Angles(math.rad(16), math.rad(-20), math.rad(30)),
		-- WINDUP: cocked back and up beside the head. The biggest silhouette change in the animation,
		-- because it is the only frame that tells the player the button actually registered.
		windupOffset = CFrame.new(1.02, 0.14, -0.92) * CFrame.Angles(math.rad(-40), math.rad(-12), math.rad(48)),
		-- RELEASE: whipped forward past the centre of the screen. The stick is hidden the instant the
		-- pose lands here; the world charge takes over from this point.
		releaseOffset = CFrame.new(-0.08, -0.16, -2.55) * CFrame.Angles(math.rad(54), math.rad(16), math.rad(-26)),
		drawSeconds = 0.26,
		stowSeconds = 0.2,
		-- Deliberately quick. A long charge-up would imply the throw gets stronger, and it does not —
		-- range is fixed (`throw.range`) and the server owns the arc. This is a wind-up, not a meter.
		windupSeconds = 0.32,
		releaseSeconds = 0.11,
		recoverSeconds = 0.26,
		releaseSpinDegrees = 220,
		bobStuds = 0.03,
		bobSeconds = 2.6,
		swayDegrees = 1.1,
		windupSteadiness = 0.75,
	},
	audio = {
		fuseCue = "DynamiteFuse",
		blastCue = "DynamiteBlast",
		equipCue = "DynamiteEquip",
		stowCue = "DynamiteStow",
		windupCue = "DynamiteWindup",
		throwCue = "DynamiteThrow",
		deniedCue = "DynamiteDenied",
	},
	-- PER-CREATURE LETHALITY (owner decision, DESIGN §6a). `hitPoints` reads as "sticks at point blank".
	-- A row without its own `blast` block takes `default`, so a new creature is killable rather than
	-- accidentally immune — the failure mode of the other default would be invisible in play.
	threat = {
		-- One stick, close, removes an ordinary body. Anything past about two-thirds of the radius
		-- survives it, which is what keeps a panicked throw at a wall from clearing a room.
		default = {
			hitPoints = 1,
			-- Survivors are driven off exactly as a Flare drives them off, so a blast that failed to
			-- kill is still a real defensive result and never a wasted stick.
			staggerSeconds = 6,
		},
		-- THE WARDEN IS NOT A THREAT ROW and does not read the table above. Three point-blank sticks is
		-- more than a run will ever be carrying, which preserves DESIGN §9's promise that the encounter
		-- has exactly one real counter (leading it under a falling crown). What dynamite buys instead is
		-- a genuine, expensive delay: it is rooted for `wardenStunSeconds` and then walks slower for
		-- `wardenSlowSeconds`.
		wardenHitPoints = 3,
		wardenStunSeconds = 2.4,
		wardenSlowMultiplier = 0.55,
		wardenSlowSeconds = 8,
	},
	-- THE BLAST DOOR and the charge pocket cut into it.
	door = {
		-- A thrown stick landing this close to the door face breaks it too. Generous on purpose: the
		-- socket is the clean way, and a player who improvised should be rewarded for the idea rather
		-- than punished for their aim.
		thrownBreakRadius = 9,
		-- HOW CLOSE A THROWN STICK'S FLIGHT PATH HAS TO PASS TO THE CHARGE POCKET to seat itself in it
		-- and arm, instead of bouncing off the rock and landing at the foot of the door.
		--
		-- This is the "stick a bomb on the door" catch, and it is checked along the ARC rather than at
		-- the landing point — a stick thrown at a vertical face never comes to rest on that face, so a
		-- landing-point test would have failed on exactly the dead-centre throw the marker invites.
		--
		-- Generous relative to the marker's own size (a stick is ~1.4 studs long) because the marker is
		-- a small object seen across a dark room, and because missing it is not interesting: a near miss
		-- already breaks the door through `thrownBreakRadius` anyway. What the catch buys is the clean
		-- read — the stick visibly goes WHERE THE MARKER WAS.
		socketCatchRadius = 4.5,
		socketRange = 7,
		socketHoldSeconds = 0.45,
		-- The owner-approved one-step interaction: confirming the outlined socket spends, seats, and
		-- lights the stick. The hold itself is the commitment window.
		placeActionText = "Place & Light Dynamite",
		objectText = "Blast Door",
		-- Short on purpose. The thrown face is NON-COLLIDING (see `breakDoor`), so it sinks through the
		-- floor rather than landing; this is the window in which every piece is still on the way up.
		rubbleLifetimeSeconds = 0.9,
		rubblePieces = 14,
	},
	-- THE VAULT ITSELF. A dead-end room attached after the loop pass, so it is a leaf by construction:
	-- nothing behind this door is ever on the way to anything, and blowing it can never be progression.
	--
	-- NO THREAT SPAWNS INSIDE, and that is the whole bargain. The cost of the room is the stick and the
	-- noise the stick makes; the room itself is not a second trap. A vault that also held a creature
	-- would make opening one a coin flip, and the item is too rare to gamble.
	vault = {
		enabled = true,
		-- The `Config/Floors.roomModules` row this room is. Every pass that has to leave a vault alone —
		-- threats, vines, falling formations, lurkers, vegetation, ordinary loot —
		-- recognises it by this id, which is the same mechanism the Warden's den already uses.
		roomModuleId = "BlastVault",
		-- Held off the first two floors for the same reason the Explosive Seam is: a new player should
		-- meet the cave before the cave starts offering them explosives.
		minDepth = 3,
		chancePerFloor = 0.4,
		-- Rolled only if the first one landed, so two is genuinely uncommon rather than half of all
		-- vault floors.
		secondVaultChance = 0.28,
		maxPerFloor = 2,
		-- Low and close. A vault reads as a pocket somebody sealed, not as another cavern.
		ceilingHeight = 19,
		depositsMin = 1,
		depositsMax = 3,
		loot = 1,
	},
	-- ART. ART-BIBLE §4 binds all of this: nothing here may emit light into the cave. The one glowing
	-- element is the socket marker, which is a per-player affordance drawn by the client for a player
	-- who is carrying a stick — it is Neon with NO PointLight, so it is visible without illuminating a
	-- single voxel of rock. See client/DynamiteController.
	visual = {
		-- Proportions of a real stick: long, slim, and unmistakable in silhouette at candle range.
		stickLength = 1.35,
		stickRadius = 0.19,
		stickColor = Color3.fromRGB(139, 46, 38),
		wrapColor = Color3.fromRGB(120, 38, 32),
		bandColor = Color3.fromRGB(188, 170, 138),
		capColor = Color3.fromRGB(62, 52, 44),
		fuseColor = Color3.fromRGB(96, 82, 60),
		-- The fuse is several short segments walked along a curve rather than one leaning cylinder,
		-- which is what makes it read as cord rather than as an aerial.
		fuseSegments = 5,
		fuseLength = 0.62,
		fuseRadius = 0.045,
		fuseCurl = 0.34,
		crateSticks = 4,
		crateSize = Vector3.new(1.62, 0.92, 1.05),
		crateColor = Color3.fromRGB(88, 66, 43),
		crateSlatColor = Color3.fromRGB(72, 53, 34),
		crateBandColor = Color3.fromRGB(74, 70, 66),
		sparkColor = Color3.fromRGB(255, 214, 138),
		-- The "put yours here" marker. Yellow, because every other readable glow in this game is
		-- already spoken for: crimson is a dark-hunter's eyes and warm orange is flame.
		socketGlowColor = Color3.fromRGB(255, 214, 74),
		socketGlowTransparency = 0.15,
		socketPulseSeconds = 1.6,
		socketPulseDepth = 0.3,
		doorThickness = 3.2,
		-- `FloorBuilder.buildWall` cuts an ARCH, not a rectangle: the opening rises up to 60% above the
		-- doorway's own height. A door sized to `profile.height` would therefore leave a crescent gap
		-- along the top that a player could see — and shine a candle — straight through, which for the
		-- one barrier in the game that is supposed to read as solid rock is the worst possible tell.
		--
		-- Matched to the vine curtain's own `archRiseFraction` for exactly that reason. Over-estimating
		-- is free: the extra height is buried in the wall above the arch.
		doorArchRiseFraction = 0.6,
		doorSocketDepth = 0.55,
		-- How far PROUD of the door's approach face the glowing marker floats. It is not in the recess:
		-- a marker sunk into its own hole is only visible head-on, and this thing has to read from across
		-- a dark room and from an angle. Small enough to still look seated in the pocket behind it.
		socketStandoff = 0.35,
		-- Broken facets across the face so the door reads as packed rubble somebody wedged into the
		-- opening, never as a slab.
		doorFaceRocks = 26,
		doorRockMinSize = 1.1,
		doorRockMaxSize = 3.4,
		doorCrackCount = 5,
		doorCrackThickness = 0.16,
		-- WHAT THE DOOR IS MADE OF, per cave family. Resolved through `Logic/CaveFamilyRules`; no
		-- service, planner or builder branches on a family id to get here.
		styleColors = {
			Rock = Color3.fromRGB(58, 62, 73),
			MossRock = Color3.fromRGB(46, 58, 48),
			Ice = Color3.fromRGB(64, 84, 104),
		},
		styleMaterials = {
			Rock = Enum.Material.Slate,
			MossRock = Enum.Material.Rock,
			Ice = Enum.Material.Glacier,
		},
		-- The fracture lines already in the face: the tell that this rock is the one rock in the cave
		-- that can be broken.
		styleCrackColors = {
			Rock = Color3.fromRGB(28, 30, 36),
			MossRock = Color3.fromRGB(22, 29, 24),
			Ice = Color3.fromRGB(150, 190, 214),
		},
	},
}

return Dynamite
