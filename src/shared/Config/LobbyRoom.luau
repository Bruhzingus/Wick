--!strict
-- The Landing: the static mineshaft hub between runs. Unlike Config/Floors this is one fixed layout
-- built once at boot (server/LobbyRoomBuilder) — never seeded or regenerated per run, so every
-- player who returns from a cave and every player who joins afterwards stands in the same room.
-- Positions below are local offsets from `origin`; server/LobbyRoomBuilder resolves world position.

-- AN ELEVATOR IS A PARTY, NOT A CAVE. Each alcove is an independent party queue (Interfaces/Party)
-- that picks its cave by vote once its occupants have readied up, so `partyId` addresses the car and
-- carries no meaning about where it goes. This used to be `tierId`, back when which car you stood in
-- WAS the tier selection and the hub could only ever hold one party.
export type LobbyElevatorDef = {
	partyId: number,
	offset: Vector3,
}

export type LobbyLightingConfig = {
	candleRange: number,
	candleBrightness: number,
	ceilingLampRange: number,
	ceilingLampBrightness: number,
	elevatorLampRange: number,
	elevatorLampBrightness: number,
}

export type LobbyWallCandleConfig = {
	height: number,
	spacing: number,
	cornerInset: number,
	fixtureClearance: number,
	bracketPlateSize: Vector3,
	bracketArmSize: Vector3,
	candleSize: Vector3,
	flameSize: Vector3,
	wallInset: number,
}

export type LobbyTunnelConfig = {
	width: number,
	height: number,
	depth: number,
	barrierSetback: number,
}

export type LobbyRailConfig = {
	startZ: number,
	endZ: number,
	gauge: number,
	railSize: Vector2,
	sleeperSize: Vector3,
	stopperOffset: Vector3,
	stopperSize: Vector3,
}

export type LobbyMineCartConfig = {
	mainOffset: Vector3,
	floorSize: Vector3,
	wallHeight: number,
	wallThickness: number,
	waxCartOffsets: { { offset: Vector3, yawDegrees: number } },
	waxHeapOffsets: { Vector3 },
	waxHeapSizes: { Vector3 },
}

-- EVERY LANDING IS SOMETHING THE MINE ALREADY OWNS. Not one of these is a shape invented for the
-- course: they are the arrival track, the storeroom crates, the barrels in the corners, the iron the
-- hub is braced with and the planking the floor is laid in. A parkour course built out of grey slabs
-- would be the only object in the Landing that came from somewhere else.
export type LobbyParkourStyle =
	-- Laid planking. The wide, forgiving landings of the opening stretch.
	"Plank"
	-- A length of the arrival track: sleepers and rail, walked along between the rails.
	| "Track"
	-- A storeroom crate, landed on its lid. Same cube the corners of the room are stacked with.
	| "Crate"
	-- A barrel stood on end. A round landing whose rim throws you off if you clip it — this is the
	-- precision target the last stretch is built out of.
	| "Barrel"
	-- Bare iron. The narrowest thing in the course and the only one with no timber on it.
	| "Girder"
	-- The summit staging: planking wide enough to stand on and breathe.
	| "Deck"

export type LobbyParkourStepDef = {
	style: LobbyParkourStyle,
	-- Local to `parkour.originOffset`. X and Z place the platform; Y is the height of the surface you
	-- STAND ON, not the body's centre — the builder hangs each style's own depth below it — so this
	-- column reads as the step heights it is, and the difference between two rows is the rise you jump.
	offset: Vector3,
	-- World X by Z footprint of the walking surface. A Barrel is round: both components are its
	-- diameter. A Girder authored 6 by 1.4 is generous about distance and unforgiving about aim, which
	-- is the whole character of that platform.
	size: Vector2,
}

export type LobbyParkourConfig = {
	originOffset: Vector3,
	steps: { LobbyParkourStepDef },
	plankThickness: number,
	trackThickness: number,
	girderThickness: number,
	deckThickness: number,
	crateDepth: number,
	barrelHeight: number,
	postThickness: number,
	postCollarHeight: number,
	postBaseSize: Vector3,
	-- One in every N platforms carries a candle on its post. Lighting the route is the only reason the
	-- course is legible from the floor at all; the hub's ceiling lamps are 25 studs up and flatten it.
	candleEveryStep: number,
	-- Measured DOWN FROM THE LANDING'S UNDERSIDE, not from its surface. A Crate is solid timber and a
	-- Barrel is solid staves: a drop measured from the walking surface buries the candle inside the very
	-- landing it is lighting, and by a different amount for every style. From the underside it is always
	-- on bare post.
	candleDropBelowLanding: number,
	candleMinimumHeight: number,
	candleYawDegrees: number,
	railGauge: number,
	railSize: Vector2,
	sleeperSize: Vector3,
	sleeperSpacing: number,
	barrelHoopThickness: number,
	barrelHoopOutset: number,
	summitWaxOffsets: { Vector3 },
	summitWaxSize: Vector3,
	lampPostHeight: number,
	lampOffset: Vector3,
	lampShadeSize: Vector3,
	lampBulbSize: Vector3,
	lampRange: number,
	lampBrightness: number,
}

export type LobbyUpdateEntry = {
	version: number,
	date: string,
	lines: { string },
}

export type LobbyShopDisplayConfig = {
	counterSize: Vector3,
	counterTopSize: Vector3,
	backdropSize: Vector3,
	backdropOffset: Vector3,
	postSize: Vector3,
	postOffset: Vector3,
	awningSize: Vector3,
	awningOffset: Vector3,
	signOffset: Vector3,
	signWidth: number,
	signHeight: number,
	schematicOffset: Vector3,
	schematicSize: Vector2,
	schematicBackingDepth: number,
	schematicFrameThickness: number,
	schematicNodeInset: Vector2,
	schematicConduitThickness: number,
	schematicHousingDepthOffset: number,
}

export type LobbyRoomConfig = {
	origin: Vector3,
	roomWidth: number, -- X extent of the hub floor
	roomDepth: number, -- Z extent of the hub floor
	wallHeight: number,
	floorThickness: number,
	wallThickness: number,
	beamSpacing: number, -- studs between ceiling support beams
	railSpacing: number, -- studs between mine-cart rail sleepers
	lighting: LobbyLightingConfig,
	wallCandles: LobbyWallCandleConfig,
	tunnel: LobbyTunnelConfig,
	rails: LobbyRailConfig,
	mineCarts: LobbyMineCartConfig,
	parkour: LobbyParkourConfig,
	spawnOffset: Vector3,
	spawnSpread: number, -- radius of the first ring of arrival positions
	spawnSlots: number, -- positions per ring before arrivals step outward to a wider one
	fallRecoveryDrop: number, -- studs below the hub floor that counts as "fell down a shaft"
	runSpeed: number,
	jumpPower: number,
	shopOffset: Vector3,
	shopFacingYaw: number, -- degrees about Y; the storefront's local +Z is the way it faces
	shopPromptText: string,
	shopObjectText: string,
	shopMessage: string,
	shopPromptRange: number,
	shopDisplay: LobbyShopDisplayConfig,
	lampHousingSize: Vector3,
	lampHousingTransparency: number,
	lampHousingColdColor: Color3,
	lampHousingLitColor: Color3,
	lampFlickerHz: number,
	lampFlickerDepth: number,
	lampLitRange: number,
	lampLitBrightness: number,
	elevators: { LobbyElevatorDef },
	elevatorCarWidth: number,
	elevatorCarDepth: number,
	elevatorCarHeight: number,
	elevatorGateThickness: number,
	elevatorZoneRadius: number, -- horizontal distance counting as "standing in this elevator"
	elevatorExitOffset: Vector3, -- car-local safe point used by explicit leave and leader kick
	elevatorBoardWidth: number,
	elevatorBoardHeight: number,
	rideDistance: number, -- studs the car physically descends during the start countdown
	rideShaftDepth: number, -- how far the built shaft runs below the car's resting position
	rideShaftRibSpacing: number, -- studs between shaft wall ribs (the parallax that sells motion)
	rideShaftRibThickness: number,
	rideShaftRibOutset: number, -- distance from the car edge to a rib ring's outside edge
	rideShakeStuds: number, -- peak camera shake amplitude during the ride
	rideShakeHz: number,
	welcomeSignOffset: Vector3,
	welcomeSignText: string,
	howToPlayOffset: Vector3,
	howToPlayIntro: string,
	howToPlayRules: { string },
	boardWidth: number,
	boardHeight: number,
	versionSignOffset: Vector3,
	versionSignWidth: number,
	versionSignHeight: number,
	leaderboardOffset: Vector3,
	leaderboardWidth: number,
	leaderboardHeight: number,
	leaderboardTitle: string,
	leaderboardRows: number,
	leaderboardRefreshSeconds: number,
	leaderboardManualRefreshSeconds: number,
	leaderboardRefreshPromptText: string,
	leaderboardRefreshObjectText: string,
	leaderboardRefreshRange: number,
	leaderboardEmptyText: string,
	leaderboardUnavailableText: string,
	updateBoardOffset: Vector3,
	updateBoardWidth: number,
	updateBoardHeight: number,
	updateBoardTitle: string,
	updateLog: { LobbyUpdateEntry },
}

local LobbyRoom: LobbyRoomConfig = {
	-- Far above every cave floor (floor depth d sits at Y = -(d-1) * Floors.geometry.floorGap, and the
	-- tallest cavern roof tops out near Y = 58), with enough headroom below for the elevator shafts the
	-- descent ride travels down. The hub can never overlap procedurally built Terrain.
	origin = Vector3.new(0, 500, 0),
	-- THE LANDING IS A HALL, NOT A CORRIDOR. Every fixture in here is now mounted on a wall rather than
	-- standing in the middle of the floor: the four cars against the rear wall (z = +75), the two big
	-- boards and the rail tunnel on the entry wall (z = -75), the shop storefront on the west wall
	-- (x = -100) and the standings on the east (x = +100). The room has to be wide enough that those
	-- four faces do not crowd each other and deep enough that you can read a board from the far side.
	roomWidth = 200,
	roomDepth = 150,
	wallHeight = 30,
	floorThickness = 2,
	wallThickness = 2,
	beamSpacing = 16,
	railSpacing = 6,
	-- Pools wide and bright enough to overlap: with only nine ceiling lamps across a 200x150 room,
	-- gaps between them (and the corners furthest from any wall candle) went visibly dark. Every
	-- range/brightness pair below was raised together so the hub stays lit end to end while keeping
	-- its timber-and-stone contrast rather than washing flat white.
	lighting = {
		candleRange = 24,
		candleBrightness = 1.15,
		ceilingLampRange = 70,
		ceilingLampBrightness = 2.3,
		elevatorLampRange = 26,
		elevatorLampBrightness = 1.4,
	},
	wallCandles = {
		height = 9,
		spacing = 14,
		cornerInset = 7,
		fixtureClearance = 2,
		bracketPlateSize = Vector3.new(1.2, 1.8, 0.25),
		bracketArmSize = Vector3.new(0.35, 0.35, 1.15),
		candleSize = Vector3.new(0.65, 1.8, 0.65),
		flameSize = Vector3.new(0.5, 0.8, 0.5),
		wallInset = 0.35,
	},
	tunnel = {
		width = 14,
		height = 14,
		-- Deep enough that its far end sits outside the nearest ceiling lamp's throw. That lamp
		-- (lighting.ceilingLampRange = 70) hangs at roughly x=0, z=-58.5, y=25; the tunnel's centreline
		-- point at depth D is about sqrt((16.5+D)^2 + 18^2) studs from it, which clears the 70-stud range
		-- once D exceeds ~51. With Lighting.Ambient pinned to black (EnvironmentSetup.apply), anything
		-- past that point gets zero light and reads as true black — this is what makes the mouth read as
		-- lit rock while the back genuinely disappears, rather than the whole shaft staying dimly visible.
		depth = 90,
		barrierSetback = 5,
	},
	rails = {
		startZ = -74,
		endZ = -22,
		gauge = 3.2,
		railSize = Vector2.new(0.5, 0.35),
		sleeperSize = Vector3.new(6, 0.3, 1.4),
		stopperOffset = Vector3.new(0, 1, -22),
		stopperSize = Vector3.new(6, 2, 1.2),
	},
	mineCarts = {
		-- Far enough beyond the +Z edge of the arrival ring that a spawned body cannot intersect it.
		mainOffset = Vector3.new(0, 1.4, -28),
		floorSize = Vector3.new(5, 0.4, 7),
		wallHeight = 2.6,
		wallThickness = 0.4,
		waxCartOffsets = {
			{ offset = Vector3.new(-72, 1.4, 28), yawDegrees = 18 },
			{ offset = Vector3.new(70, 1.4, 30), yawDegrees = -16 },
		},
		waxHeapOffsets = {
			Vector3.new(-1.25, 2.05, -1.8),
			Vector3.new(1.1, 2, -1.3),
			Vector3.new(-0.4, 2.3, 0.2),
			Vector3.new(1.25, 2.05, 1.5),
			Vector3.new(-1.2, 1.95, 1.7),
		},
		waxHeapSizes = {
			Vector3.new(2.2, 1.6, 2.3),
			Vector3.new(2, 1.5, 2.1),
			Vector3.new(2.5, 1.8, 2.6),
			Vector3.new(2.1, 1.5, 2),
			Vector3.new(1.8, 1.4, 2.1),
		},
	},
	-- STAGING SOMEBODY LEFT UP, and nothing more than that. No checkpoints, no timer, no standings row
	-- and nothing anywhere that records you climbed it — it exists so a player waiting on three other
	-- people to ready up has something to do with their hands, and the moment it pays out anything it
	-- stops being that and starts being a reason to not get in the elevator.
	--
	-- IT IS A LINE OF PLATFORMS, and it is a line for a reason. This has been built twice before: first
	-- as three switchback lanes stacked twelve studs apart, which a player could jump straight ACROSS to
	-- cut out half the course; then as a spiral around a square, which fixed the skipping and looked
	-- terrible — jump distance caps the square at about twelve studs, so a spiral that climbs twenty
	-- ends up taller than it is wide, and four full-height corner posts turn it into a thicket of poles
	-- with small shelves lost between them. A route that mostly walks away in ONE DIRECTION has neither
	-- problem: nothing doubles back next to anything, so there is nothing to short-cut across, and the
	-- silhouette is a line of platforms stepping up rather than a tower.
	--
	-- THE ONE PLACE IT TURNS is the sixth platform, and that turn is why the two lanes sit sixteen studs
	-- apart in Z rather than touching. Crossing between them is a 12-to-13 stud jump against an arc that
	-- reaches at most 10.8 at the heights involved, so the return leg cannot be entered early.
	-- Tests/LobbyParkourTests re-derives that for every pair of platforms.
	--
	-- IT LIVES IN THE EAST AISLE. Everything the hub needs a player to reach is somewhere else: the four
	-- elevator queues (z >= 54, and the course stops at 21), the storefront (west wall), both standings
	-- boards (east wall at z = -16 and -52, and the course never goes below z = 0) and the arrival ring
	-- (z = -44). It occupies x 26..90 and z 0..21 and tops out at 18.2, clear of the east wall by nine
	-- studs, of the loaded wax cart at (70, 30) by five, and of the ceiling beams by five above a
	-- player's head on the summit.
	--
	-- DIFFICULTY IS SLIM PLATFORMS AND HONEST GAPS, in that order. Every jump sits at 61-70% of what the
	-- arc can actually do, which is a real jump you have to commit to and not a leap you fail to a stud
	-- of missing run-up; what makes it bite is that the landings run 3.2 studs down to a 1.2-stud girder
	-- and a 2.2-stud barrel lid. Two jumps are deliberately easy — the turn and the last one onto the
	-- summit — because a player who has just crossed two girders should not lose it on the dismount.
	parkour = {
		originOffset = Vector3.new(28, 0, 2),
		-- NINE JUMPS, AND NO TWO THE SAME SHAPE. In order: a plain hop up; onto a long narrow beam you
		-- walk; off the beam onto a barrel lid; a long DROP onto a length of track, which is the one
		-- jump that gains distance by losing height; a short diagonal around the turn; a diagonal back
		-- across onto the return leg; a straight run onto the narrowest girder in the course; the same
		-- again onto the smallest barrel; and an easy step onto the summit.
		steps = {
			-- Out leg, heading +X. Wide enough at the start to be an obvious invitation.
			{ style = "Plank", offset = Vector3.new(0, 2, 0), size = Vector2.new(4, 3.5) },
			{ style = "Plank", offset = Vector3.new(12, 4.2, 2), size = Vector2.new(3.2, 3) },
			-- Bare iron, laid along the jump: forgiving about distance, unforgiving about aim, and you
			-- walk its length to line up the next one.
			{ style = "Girder", offset = Vector3.new(26, 6.4, 0), size = Vector2.new(6, 1.4) },
			-- A barrel lid. Round, so clipping the rim rolls you off instead of letting you scramble.
			{ style = "Barrel", offset = Vector3.new(39, 8.6, 2), size = Vector2.new(2.6, 2.6) },
			-- THE DROP. Eleven studs across and 1.6 DOWN — falling buys distance the others cannot, and
			-- it is the one place the course stops climbing, so the height reads as deliberate.
			{ style = "Track", offset = Vector3.new(54, 7, 0), size = Vector2.new(5, 3) },
			-- The turn. Deliberately a short diagonal: corners are where a player works out where the
			-- route goes next, not where it bites.
			{ style = "Crate", offset = Vector3.new(60, 9.4, 8), size = Vector2.new(3, 3) },
			-- Return leg, heading -X, sixteen studs across so it cannot be entered from the out leg.
			{ style = "Plank", offset = Vector3.new(50, 11.6, 16), size = Vector2.new(3, 3) },
			{ style = "Girder", offset = Vector3.new(37, 13.8, 16), size = Vector2.new(5, 1.2) },
			{ style = "Barrel", offset = Vector3.new(24, 16, 16), size = Vector2.new(2.2, 2.2) },
			-- The summit. Wide on purpose, and the only thing up here is a lamp and somebody's spilled
			-- wax: the course ends by being over, and you get down by jumping off.
			{ style = "Deck", offset = Vector3.new(14, 18.2, 16), size = Vector2.new(6, 6) },
		},
		plankThickness = 1,
		trackThickness = 0.7,
		girderThickness = 0.8,
		deckThickness = 1.2,
		-- A LOW crate and a SHORT barrel rather than the cubes and drums standing in the corners
		-- downstairs: a body hanging its full width below its own walking surface reads as a block on a
		-- stick from the floor, which is most of what went wrong with the version before this one.
		crateDepth = 2.4,
		barrelHeight = 2.4,
		-- Timber, and thick enough to read as a leg rather than a wire. Every platform gets exactly one,
		-- straight down to a base plate on the floor — no bracing, no frame, nothing crossing the gaps a
		-- player is jumping through.
		postThickness = 1.1,
		postCollarHeight = 0.35,
		postBaseSize = Vector3.new(2.2, 0.4, 2.2),
		candleEveryStep = 2,
		candleDropBelowLanding = 1.6,
		-- Below this the bracket is close enough to the floor to be walked into rather than seen.
		candleMinimumHeight = 2,
		-- Facing world -Z, which is ACROSS the route and never along it. A bracket has a collidable arm
		-- standing a stud out of the post a stud under the lip; pointed along a jump it is an invisible
		-- thing to clip on the way in. It also puts the lit side toward the arrival ring, which is the
		-- side the course is seen from.
		candleYawDegrees = 180,
		railGauge = 2.2,
		railSize = Vector2.new(0.4, 0.3),
		sleeperSize = Vector3.new(0.7, 0.2, 3),
		sleeperSpacing = 2,
		barrelHoopThickness = 0.25,
		barrelHoopOutset = 0.12,
		-- Spilled on the summit deck. Nothing collects it, nothing counts it and there is no way to get
		-- it down: it is the punchline, not a prize.
		summitWaxOffsets = {
			Vector3.new(1.6, 0, 1.4),
			Vector3.new(2.2, 0, 0.4),
			Vector3.new(1.3, 0, -0.5),
		},
		summitWaxSize = Vector3.new(1.1, 1.1, 1.1),
		-- One lamp on a post at the back of the deck, the same shape as the hub's ceiling lamps at a
		-- fraction of the throw. It marks the top from across the room; it does not light the corner.
		lampPostHeight = 4.6,
		lampOffset = Vector3.new(-2, 0, -2),
		lampShadeSize = Vector3.new(2, 0.6, 2),
		lampBulbSize = Vector3.new(1, 0.55, 1),
		lampRange = 24,
		lampBrightness = 1.1,
	},
	-- Near the entry wall, facing the elevators across the room.
	spawnOffset = Vector3.new(0, 0, -44),
	spawnSpread = 10,
	-- TWELVE, not `Config.Run.partyCap`. Four elevator cars of four means this hub can hold sixteen
	-- people at once, so dividing the spawn circle by the PARTY cap put every fifth arrival exactly on
	-- top of the first. Arrivals past the twelfth step out to a wider ring instead of colliding.
	spawnSlots = 12,
	-- Deeper than a stumble off the spawn pad, shallower than the ride's own travel, so a rider is
	-- never mistaken for someone who fell down an open shaft.
	fallRecoveryDrop = 40,
	-- Lobby movement is presentation only (no PlayerState, so no wax cost); it just needs to feel
	-- good to cross a room this size. This is deliberately faster than expedition run speed.
	runSpeed = 30,
	-- The lobby avatar keeps a full jump; the run candle has only Config.Movement.hopPower.
	jumpPower = 48,
	-- HUNG ON THE WEST WALL, not standing in the middle of the room. `shopOffset` is where the counter
	-- meets the floor and `shopFacingYaw` is which way the storefront looks; every other number in
	-- `shopDisplay` is measured in the stall's own frame, so the whole thing moves and turns together.
	-- The wall's inner face is at x = -(roomWidth/2 - wallThickness/2) = -99, and the backdrop reaches
	-- 3 studs behind the counter, so -96 is as close as this can sit without sinking into the rock.
	shopOffset = Vector3.new(-96, 0, -8),
	-- 90 degrees turns the stall's local +Z onto world +X: the counter faces east, into the room.
	shopFacingYaw = 90,
	shopPromptText = "Browse the shop",
	shopObjectText = "General Store",
	shopMessage = "The shop is still being stocked - check back soon.",
	shopPromptRange = 14,
	-- One broad timber storefront replaces the old row of freestanding lamp signs. The compact
	-- schematic sits on its back wall: server geometry shows the shape of the network while the shop
	-- UI owns names, prices, prerequisites and purchases.
	--
	-- EVERY OFFSET HERE IS LOCAL TO THE STALL, NOT TO THE WORLD. +X is along the counter, +Y is up and
	-- +Z is the way the shopper faces it, which is the same convention `textBoard` uses for a readable
	-- face. That is what lets `shopFacingYaw` hang the whole storefront on a side wall: the backdrop,
	-- schematic and awning root sit at NEGATIVE z (behind the counter, against the rock) and the sign
	-- and lamp housings at positive z (out over the shopper).
	--
	-- Roughly 1.35x the old freestanding stall. It is against a wall of a room now half again as wide,
	-- and at the old size it read as a market table rather than as one of the room's four faces.
	shopDisplay = {
		counterSize = Vector3.new(46, 3.5, 4.5),
		counterTopSize = Vector3.new(47, 0.5, 5.5),
		backdropSize = Vector3.new(46, 22, 0.6),
		backdropOffset = Vector3.new(0, 11, -2.7),
		postSize = Vector3.new(1.1, 23, 1.1),
		postOffset = Vector3.new(23.5, 11.5, 1.6),
		awningSize = Vector3.new(48, 0.9, 9),
		awningOffset = Vector3.new(0, 23, 1.6),
		signOffset = Vector3.new(0, 20.6, 4.5),
		signWidth = 19,
		signHeight = 3.2,
		schematicOffset = Vector3.new(0, 12.5, -1.9),
		schematicSize = Vector2.new(40, 13),
		schematicBackingDepth = 0.45,
		schematicFrameThickness = 0.6,
		schematicNodeInset = Vector2.new(1.9, 1.5),
		schematicConduitThickness = 0.3,
		schematicHousingDepthOffset = 0.7,
	},

	-- Every node still owns a tiny physical housing in the storefront schematic. The per-viewer
	-- renderer lights only the housings this player owns.
	lampHousingSize = Vector3.new(1.4, 1.8, 1.4),
	-- The housing is a CAGE around the flame, not a box hiding it. Matches the hub's existing lantern
	-- cages; an opaque value here makes every purchase's visual payoff invisible, which is the exact
	-- bug this value exists to prevent.
	lampHousingTransparency = 0.55,
	-- Cold iron when dead, iron with a fire in it when lit. The colour swap keeps progress legible
	-- from across the room rather than only at arm's length.
	lampHousingColdColor = Color3.fromRGB(58, 56, 54),
	lampHousingLitColor = Color3.fromRGB(96, 82, 66),
	-- A lit lamp breathes rather than sitting at a fixed brightness, so the schematic reads as small
	-- flames instead of indicator lights. Kept shallow: this must stay at the edge of notice.
	lampFlickerHz = 1.7,
	lampFlickerDepth = 0.14,
	-- Deliberately small pools. A lit housing must read as one more warm point on a line, never as
	-- room lighting — the hub's ceiling lamps already do that job.
	lampLitRange = 14,
	lampLitBrightness = 0.5,
	-- FOUR PARTY CARS, spaced across the far wall. Deliberately not three-per-cave any more: a party is a
	-- party queue and the cave is voted for inside it, so the count is about how many separate groups
	-- the hub can hold at once (four parties of four) rather than about how many caves exist.
	--
	-- ALL FOUR SHARE ONE Z, AND MUST. `LobbyRoomBuilder.buildFloor` derives the entire elevator band —
	-- the strip of floor the four shaft openings are cut out of — from `elevators[1].offset.Z` alone.
	-- Give one car a different Z and its shaft opening is cut in the wrong place, leaving that car
	-- sitting on solid planks and a hole in the floor somewhere it does not belong.
	elevators = {
		{ partyId = 1, offset = Vector3.new(-66, 0, 62) },
		{ partyId = 2, offset = Vector3.new(-22, 0, 62) },
		{ partyId = 3, offset = Vector3.new(22, 0, 62) },
		{ partyId = 4, offset = Vector3.new(66, 0, 62) },
	},
	elevatorCarWidth = 14,
	elevatorCarDepth = 14,
	elevatorCarHeight = 14,
	elevatorGateThickness = 0.5,
	-- Covers the whole car floor including its corners (half-diagonal of a 14x14 car is ~9.9).
	elevatorZoneRadius = 10,
	-- Past the open gate and outside `elevatorZoneRadius`, so the next occupancy tick cannot pull an
	-- explicitly removed body straight back into the party it just left.
	elevatorExitOffset = Vector3.new(0, 0, -13),
	elevatorBoardWidth = 11,
	elevatorBoardHeight = 7,
	-- The ride is the loading transition: the car actually travels this far down its shaft over
	-- Config.Run.startCountdownSeconds before the cave replaces the lobby body.
	rideDistance = 220,
	rideShaftDepth = 260,
	rideShaftRibSpacing = 10,
	rideShaftRibThickness = 0.8,
	rideShaftRibOutset = 1.5,
	rideShakeStuds = 0.1,
	rideShakeHz = 5.5,
	welcomeSignOffset = Vector3.new(-40, 13, -73.5),
	-- The two things a first-time reader has to leave this board knowing: wax is what keeps you
	-- alive, and it is NOT what pays you. Phase 8 removed the living-wax payout (server/BrazierService),
	-- so any wording here that promises to "carry home what is left of you" describes a build that no
	-- longer exists. Raw Wax cut out of the seams is the only currency, and a Brazier is the only
	-- place it becomes money.
	welcomeSignText = "WICK\n\nYou are a living candle.\n\nYour wax is your health, your light, your "
		.. "fuel and your clock. Every second lit is a second spent, and you shrink as you spend "
		.. "it.\n\nNothing down there can be fought, only read. What the caves are worth is the Raw "
		.. "Wax in their seams: cut it out, carry it up, and light a Brazier. That is the only way it "
		.. "becomes money.\n\nBurn out first and it stays down there with you.",
	howToPlayOffset = Vector3.new(40, 13, -73.5),
	howToPlayIntro = "HOW TO PLAY",
	-- Rendered in order as a numbered list. Keybinds are NOT written here — the builder pulls those
	-- live from Config.Feel.controls so signage can never drift from the real bindings.
	--
	-- ONE RULE PER THING THE CAVE WILL OTHERWISE TEACH BY KILLING YOU, in the order a run meets them:
	-- ready up, the dial, what the dark holds, what to do about it, how you get paid, and the three
	-- ways a floor ends you. Every line is checked against shipped config rather than intent —
	-- entry fees are Config/CaveFamilies, the light responses are Config/Threats, the strike read is
	-- Config/Mining, and the payout is Config/Extraction (priced by the depth a unit was cut at).
	--
	-- LENGTH IS A LAYOUT CONSTRAINT, NOT A STYLE PREFERENCE. The builder renders these TextScaled, so
	-- text that runs long does not overflow — it silently shrinks the whole board until nobody reads
	-- it from across the room. Eight rules at roughly 100 characters is what fits `boardHeight` at a
	-- legible size; adding a ninth means growing the board, not tightening the leading.
	howToPlayRules = {
		"Walk into any elevator to join its party, up to four. Walk out again to leave it.",
		"Ready up, then the car votes on a cave. Moss and Ice charge every member a fee to enter.",
		"Burn bright to see far and work fast. Burn low to last longer and stay hidden. That dial is the game.",
		"Moths come to your light. Hunters come for you in the dark. Every room is a read on which is there.",
		"You cannot fight either one. Flare repels hunters, a decoy pulls moths away, cup covers your flame.",
		"Raw Wax is the money. Plant at a seam and strike its bright core; clean hits are faster and quieter.",
		"Water at flame height snuffs you, and you shrink as you burn, so the way in is not the way out.",
		"Watch the ceiling. Cracked, leaning stone falls, and a low candle is snuffed rather than hurt.",
		"A Basin sells wax for a permanent sacrifice. A Brazier pays out your Raw Wax by depth and ends your run.",
	},
	-- WIDE, because width is what this board actually needed. The rules are long single sentences and
	-- the controls table wants three columns beside them; at 22 studs both were fighting for the same
	-- space and the whole board rendered small to fit. At 38 a rule wraps to two lines instead of
	-- three, which is worth more than the height increase was.
	--
	-- The two entry-wall boards now span x -59..-21 and 21..59 of a 200-wide wall, leaving the middle
	-- 42 studs clear for the rails and their tunnel. `blocksEntrySign` widens with this automatically,
	-- so the support posts at -50/-33.3 and 33.3/50 drop out and the rest of the row stays.
	boardWidth = 38,
	-- Grown from 13 with the rule list. The two entry-wall boards now carry the whole loop rather
	-- than a five-line summary, and at the old height TextScaled shrank that to unreadable. Their
	-- offsets sit at y = 13 so a 17-stud board clears the floor (spans y 4.5 to 21.5) and still
	-- passes well under the ceiling beams at 28.6.
	boardHeight = 17,
	-- A small plaque against the entry wall, just past the how-to-play board's right edge
	-- (howToPlayOffset.X + boardWidth/2 = 59) with a five-stud gap. Low and small on purpose — a
	-- build marker, not a third board competing with the two real ones.
	versionSignOffset = Vector3.new(66, 5, -73.5),
	versionSignWidth = 4,
	versionSignHeight = 2.2,
	-- THE EAST WALL'S WHOLE JOB. Mounted flat against x = +100 and facing back across the room, which
	-- is why `LobbyRoomBuilder.buildLeaderboard` turns it -90 degrees about Y: `textBoard` reads its
	-- own local +Z as the readable face, so a wall-mounted board has to be rotated rather than merely
	-- moved. Grown with the room — ten rows of standings on a 24-stud board seen across a 200-stud
	-- hall rendered as a smudge, and every row is TextScaled, so size here IS legibility.
	leaderboardOffset = Vector3.new(96, 13, -16),
	leaderboardWidth = 34,
	leaderboardHeight = 20,
	leaderboardTitle = "DEEPEST DESCENTS",
	leaderboardRows = 10,
	-- Cross-server standings are cheap to read but not free; once a minute is plenty for a hub.
	leaderboardRefreshSeconds = 60,
	-- A player may pull the board's tag for an immediate read, but cannot turn a crowded lobby into
	-- an OrderedDataStore polling loop.
	leaderboardManualRefreshSeconds = 10,
	leaderboardRefreshPromptText = "Refresh standings",
	leaderboardRefreshObjectText = "Deepest Descents",
	leaderboardRefreshRange = 16,
	leaderboardEmptyText = "No one has come back up yet.",
	leaderboardUnavailableText = "Standings are unavailable in Studio.",
	updateBoardOffset = Vector3.new(96, 13, -52),
	updateBoardWidth = 30,
	updateBoardHeight = 20,
	updateBoardTitle = "RECENT UPDATES",
	-- Newest first. Versions are the same monotonic build numbers shown on the entry-wall plaque.
	updateLog = {
		{
			version = 130,
			date = "2026-08-09",
			lines = {
				"Staging has gone up along the east aisle of the Landing.",
				"Nine jumps to the top, over girders, barrel lids and a length of track.",
				"It pays nothing and nobody is counting.",
			},
		},
		{
			version = 97,
			date = "2026-08-07",
			lines = {
				"Mobile controls rebuilt — the action buttons no longer overlap.",
				"The Signal Bell can finally be rung on a phone.",
				"Menus fit the screen and scroll instead of running off the edge.",
			},
		},
		{
			version = 94,
			date = "2026-08-06",
			lines = {
				"Raw Wax is now measured in grams, and every landed swing pays.",
				"A fumble earns nothing. Payouts are lower, and depth pays a little less.",
				"All Raw Wax balances have been reset — nobody kept an advantage.",
				"Explosive seams: endless wax, a rising hiss, and everything hears it go.",
				"Mined wax no longer keeps a deep floor lit for free.",
			},
		},
		{
			version = 71,
			date = "2026-08-03",
			lines = {
				"The Landing now opens onto a dark arrival tunnel.",
				"Wall candles and loaded wax carts dress the room.",
				"New update notes now appear once when you join.",
			},
		},
		{
			version = 69,
			date = "2026-08-03",
			lines = {
				"Caves gained distinct air, acoustics and footsteps.",
				"Roof-bound creature placement was corrected.",
			},
		},
		{
			version = 68,
			date = "2026-08-03",
			lines = {
				"Stone, Moss and Ice gained signature creatures.",
				"Each cave family now has its own ambience and hazards.",
			},
		},
	},
}

return LobbyRoom
