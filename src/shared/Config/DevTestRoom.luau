--!strict
-- The PIN-gated enemy test chamber. This file owns only authored placement, labels and dimensions;
-- server/DevTestRoomBuilder realizes the geometry and a separate service decides what any button does.

export type ControlDefinition = {
	actionId: string,
	label: string,
	color: Color3,
}

export type ControlGroupDefinition = {
	id: string,
	label: string,
	color: Color3,
	columns: number,
	definitions: { ControlDefinition },
}

export type ControlBoardDefinition = {
	id: string,
	localPosition: Vector3,
	facing: Vector3,
	size: Vector3,
	canvasSize: Vector2,
	title: string,
	maxRows: number,
	groups: { ControlGroupDefinition },
}

export type GuideEntryDefinition = {
	entityId: string,
	name: string,
	badge: string,
	description: string,
	testHint: string,
	color: Color3,
}

export type GuideGroupDefinition = {
	id: string,
	label: string,
	color: Color3,
	columns: number,
	entries: { GuideEntryDefinition },
}

export type GuideBoardDefinition = {
	id: string,
	localPosition: Vector3,
	facing: Vector3,
	size: Vector3,
	canvasSize: Vector2,
	title: string,
	groups: { GuideGroupDefinition },
}

export type BossFloorDefinition = {
	id: string,
	-- Which authored floor this is. `DevTestBossFloors` switches on it once, to pick the planner and
	-- the encounter; nothing else in the laboratory branches on it.
	bossId: string,
	-- WHERE THE FLOOR'S GRID ORIGIN SITS, as an offset from the laboratory's centre. Y is ignored:
	-- both floors are built at the laboratory's own floor height so a tester walks in on the level
	-- (`Types/World.FloorPlan.floorY`).
	worldOriginOffset: Vector3,
	-- THE ONE DOORWAY THAT IS NOT IN THE AUTHORED PLAN, as the wall of the ENTRY room it is cut into.
	--
	-- A shipped boss floor has no outside: you arrive down a ladder into its entry room, so every
	-- doorway either plan declares faces another room on the same floor. The laboratory arrives on
	-- foot instead, and rather than teleport a tester into the middle of a room this cuts one extra
	-- opening in the entry — the room a real party arrives in — so the walk in crosses the same
	-- threshold in the same direction the real one does.
	entranceDirection: string,
	title: string,
	subtitle: string,
	startButtonLabel: string,
	startButtonColor: Color3,
	promptObjectText: string,
	-- What the console and the status line call this encounter.
	displayName: string,
}

export type LurkerSiteDefinition = {
	localPosition: Vector3,
	facing: Vector3,
	trapSide: "Left" | "Right",
}

export type DevTestRoomConfig = {
	enabled: boolean,
	session: {
		depth: number,
		globalDepth: number,
		familyId: string,
		scopeId: string,
		maxOrdinaryThreats: number,
		traplineClearanceStuds: number,
		freeToolCharges: number,
		dynamiteCharges: number,
		controlValidationDistance: number,
		controlCooldownSeconds: number,
		rebuildControlCooldownSeconds: number,
		sharedRebuildCooldownSeconds: number,
		containmentCheckSeconds: number,
		containmentMargin: number,
		wardenStunSeconds: number,
		crownTriggerRadius: number,
		ambienceTrim: number,
		superSprintMultiplier: number,
	},
	access: {
		localOffset: Vector3,
		facing: Vector3,
		baseSize: Vector3,
		pedestalSize: Vector3,
		screenSize: Vector3,
		screenCenterHeight: number,
		screenForwardOffset: number,
		title: string,
		codeFormat: string,
		promptActionText: string,
		promptObjectText: string,
		promptDistance: number,
		promptHoldSeconds: number,
	},
	room: {
		offsetFromLobby: Vector3,
		interiorSize: Vector3,
		floorThickness: number,
		wallThickness: number,
		ceilingThickness: number,
		routeOpeningWidth: number,
		routeOpeningHeight: number,
		candleLocalPosition: Vector3,
		threatLocalPosition: Vector3,
		knotwalkerSpawnLocalPosition: Vector3,
		knotwalkerRouteLocalPosition: Vector3,
		knotwalkerTrapLocalPosition: Vector3,
		noiseLocalPosition: Vector3,
		wardenLocalPosition: Vector3,
		wardenFacing: Vector3,
		wardenWaxLocalPosition: Vector3,
		hazardLocalPosition: Vector3,
		lobbyReturnOffset: Vector3,
		roomTitle: string,
		roomSubtitle: string,
	},
	-- THE TWO BOSS FLOORS, AND THEY ARE THE REAL ONES.
	--
	-- WHAT THIS USED TO BE. Two hand-authored boxes — 96 x 48 x 96 for her, 64 x 40 x 64 for him — with
	-- a Part floor, four Part walls, four ceiling lights and the encounter's fixtures dropped in at
	-- their authored offsets. They tested the FIGHT and they were honest about it, but they were not
	-- her floor and his floor: no wax wing, no dynamite wing, no vigils, no way down, no carved ground
	-- to walk over, no rock relief on the walls, no wall lamps, no dripstone, and a flat ceiling at a
	-- height nobody had chosen. A designer looking at one of them was looking at a room the game does
	-- not build.
	--
	-- WHAT IT IS NOW. `server/DevTestBossFloors` runs `Logic/BossFloorPlan.plan` and
	-- `Logic/UnlittiusFloorPlan.plan` — the same two functions RunOrchestrator calls on floors 10 and
	-- 20 — and hands each result to `server/FloorBuilder.build`, the same builder every floor in every
	-- expedition goes through. Five carved rooms each, real Terrain, real ground fields, the authored
	-- ceiling heights, the doorway minimums, the formations, the lamps, the brazier and the ladder. The
	-- laboratory is a corridor away, and the encounter starts from a button in that corridor.
	--
	-- SO THERE IS ALMOST NOTHING LEFT TO AUTHOR HERE, which is the point of the shape below. Each floor
	-- needs a place to stand in the world and a hole to walk in through; everything else — how long the
	-- corridor is, which laboratory wall it leaves, where along that wall it opens — is DERIVED from
	-- those two numbers by `DevTestRoomBuilder.buildBossApproach`. Two authored values cannot disagree
	-- with each other the way twelve can, and the twelve are what let the old shrine sit behind a solid
	-- wall for a whole revision without anything noticing.
	bossFloors: {
		corridorWidth: number,
		corridorHeight: number,
		floorThickness: number,
		wallThickness: number,
		ceilingThickness: number,
		-- The sign and the start button, both on one corridor side wall near the mouth of the floor:
		-- the last thing you read before the room stops being a room and starts being an encounter.
		plaqueInsetFromFloor: number,
		plaqueSide: number,
		signSize: Vector3,
		signCanvasSize: Vector2,
		signHeight: number,
		startButtonSize: Vector3,
		startButtonHeight: number,
		promptActionText: string,
		promptDistance: number,
		promptHoldSeconds: number,
		-- THE CORRIDOR IS LIT AND THE FLOOR AT THE END OF IT IS NOT, deliberately. A WICK floor is
		-- dark; that is the whole game, and a boss floor lit by fixtures the shipped one does not have
		-- would answer none of the questions a designer walks it to ask. The corridor gets enough
		-- light to find the button by, and then you take your own candle in.
		lightingSpacing: number,
		lightingRange: number,
		lightingBrightness: number,
		definitions: { BossFloorDefinition },
	},
	hotkeys: {
		clearEnemies: Enum.KeyCode,
		clearEnemiesLabel: string,
		superSprint: Enum.KeyCode,
		superSprintLabel: string,
	},
	controls: {
		boards: { ControlBoardDefinition },
		buttonSize: Vector3,
		buttonSpacing: Vector2,
		buttonTopInset: number,
		buttonForwardGap: number,
		-- Resolution of a button's own face, in pixels per stud. Derived rather than authored as a flat
		-- canvas so shrinking `buttonSize` shrinks the button and leaves its lettering the same PHYSICAL
		-- height — a fixed canvas would silently rescale every label the moment these panels were
		-- compacted, which is exactly what happened the last time the boards were resized.
		buttonCanvasPixelsPerStud: number,
		promptActionText: string,
		promptDistance: number,
		promptHoldSeconds: number,
	},
	guide: {
		boards: { GuideBoardDefinition },
	},
	lurker: {
		openingWidth: number,
		openingHeight: number,
		postSize: Vector3,
		lintelHeight: number,
		sites: { LurkerSiteDefinition },
		visualSeed: number,
	},
	hazard: {
		variantId: string,
		visualSeed: number,
	},
	markers: {
		size: Vector3,
		candleLabel: string,
		threatLabel: string,
		knotwalkerLabel: string,
		knotwalkerRouteLabel: string,
		knotwalkerTrapLabel: string,
		noiseLabel: string,
		wardenLabel: string,
		hazardLabel: string,
	},
	lighting: {
		fixtureSize: Vector3,
		localOffsets: { Vector3 },
		range: number,
		brightness: number,
	},
	ui: {
		canvasSize: Vector2,
		titleTextSize: number,
		bodyTextSize: number,
		buttonTextSize: number,
		controlTitleTextSize: number,
		controlGroupTextSize: number,
		guideTitleTextSize: number,
		guideGroupTextSize: number,
		guideNameTextSize: number,
		guideBadgeTextSize: number,
		guideBodyTextSize: number,
		guideHintTextSize: number,
	},
	palette: {
		floor: Color3,
		wall: Color3,
		trim: Color3,
		metal: Color3,
		panel: Color3,
		text: Color3,
		mutedText: Color3,
		accent: Color3,
		light: Color3,
		candleMarker: Color3,
		threatMarker: Color3,
		wardenMarker: Color3,
		hazardMarker: Color3,
	},
}

local DevTestRoom: DevTestRoomConfig = {
	enabled = true,
	session = {
		-- A virtual floor key, deliberately outside every generated run. Global depth is separate: ten
		-- enables every mature threat behavior while the room still remains one isolated floor.
		depth = 610,
		globalDepth = 10,
		familyId = "STONE",
		scopeId = "WickDevTestRoom",
		maxOrdinaryThreats = 12,
		-- HOW CLOSE A TESTER MAY STAND WHILE A KNOTWALKER STRINGS A WIRE. In a cave this is 34 studs
		-- (Config/Threats.Knotwalker.trapline.playerClearanceStuds) and it exists so a wire is never
		-- strung in front of somebody walking up to the doorway. In here that rule made the behaviour
		-- impossible to see at all: the tester is always walking up to the doorway, because watching it
		-- happen is why they spawned the creature. Six studs still stops it stringing one THROUGH
		-- somebody, and lets you stand at the opening and watch.
		traplineClearanceStuds = 6,
		freeToolCharges = 999,
		-- Dynamite is the one item whose real gate is scarcity (Config/Dynamite.supply), so the lab
		-- hands out an effectively unlimited supply for the same reason it does tool charges: this room
		-- exists to answer "what does this DO to that creature", and rationing the answer would make
		-- the room useless for the one item most worth testing against a live body. The blast still
		-- costs wax exactly as it does in a cave — the test candle simply cannot die of it.
		dynamiteCharges = 999,
		controlValidationDistance = 24,
		controlCooldownSeconds = 0.35,
		rebuildControlCooldownSeconds = 1,
		sharedRebuildCooldownSeconds = 0.5,
		containmentCheckSeconds = 0.5,
		containmentMargin = 3,
		wardenStunSeconds = 4,
		crownTriggerRadius = 28,
		-- THE CAVE HELD DOWN TO A TENTH while a tester is inside. The lab exists to answer "what does
		-- this creature SOUND like", and full-strength ambience is exactly the bed those answers are
		-- buried in. Applied as a bus trim under the player's own ambience setting, so it stacks with
		-- the slider rather than overwriting it, and lifts on the way out.
		ambienceTrim = 0.1,
		-- HELD-V SUPER SPRINT, and it exists because the laboratory got big. The main chamber is 192
		-- studs across, the boss arena is another 140 beyond it, and at the game's 16-stud run a tester
		-- spends most of a session walking between the thing they pressed and the thing it produced.
		-- Four times is deliberately absurd rather than "brisk": this is a camera dolly, not a movement
		-- mode, and it must never read as a speed the game could be balanced around.
		superSprintMultiplier = 4,
	},
	access = {
		-- Freestanding beside the Landing spawn ring. The prompt is only an interaction surface; the
		-- service still validates authorization and the player's live lobby position.
		localOffset = Vector3.new(30, 0, -44),
		facing = Vector3.new(-1, 0, 0),
		baseSize = Vector3.new(4.2, 0.8, 3.6),
		pedestalSize = Vector3.new(2.8, 4.6, 2.2),
		screenSize = Vector3.new(4.4, 2.8, 0.35),
		screenCenterHeight = 5.2,
		screenForwardOffset = 1.3,
		title = "ENEMY TEST CHAMBER",
		codeFormat = "ENTER CODE  %s",
		promptActionText = "Enter Access Code",
		promptObjectText = "Restricted Test Terminal",
		promptDistance = 10,
		promptHoldSeconds = 0,
	},
	room = {
		-- Far beyond the Landing walls and every elevator shaft, but at the same floor height so a
		-- server-authorized teleport never approaches the falling-part boundary.
		offsetFromLobby = Vector3.new(440, 0, 0),
		-- Four ordinary 64-stud cells form one square chamber with a simple cross-shaped route loop.
		-- That is the minimum topology in which the Knotwalker can visibly cut ahead by another path.
		-- THREE CELLS WIDE, NOT TWO, AND TALL ENOUGH FOR THE QUEEN.
		--
		-- The four-bay route cycle at the centre is unchanged: `buildRouteDividers` places its arches at
		-- +-halfCell from the room centre, so the 2x2 grid RoomNavigation is handed still exists exactly
		-- as authored and the Knotwalker route test still has its cycle. What the extra cell buys is an
		-- APRON around it, and two things need one:
		--
		--   * A Stone Gnawer's charge is 26 studs per second held for 1.6 seconds — roughly forty studs
		--     in a straight line. Inside a 64-stud bay with a route arch through it, every charge ended
		--     against trim before it had shown what it does.
		--   * The Grub Queen is authored for a 46-stud chamber (Logic/BossFloorPlan). A 30-stud ceiling
		--     physically could not contain her, which is most of why she appeared not to spawn.
		--
		-- The bays keep their own surfaces; the apron is flat open floor. Wick-pack bodies seat on the
		-- laboratory's registered flat fallback (EnemyService.setGroundFallback) so they roam all of it,
		-- while ThreatService rows stay on the bay grid they were always given.
		interiorSize = Vector3.new(192, 52, 192),
		floorThickness = 2,
		wallThickness = 2,
		ceilingThickness = 2,
		routeOpeningWidth = 58,
		routeOpeningHeight = 15,
		candleLocalPosition = Vector3.new(-48, 0, -32),
		-- Ordinary rows stay close enough to the Crown that every Calver patrol point can strike it.
		threatLocalPosition = Vector3.new(8, 0, -32),
		knotwalkerSpawnLocalPosition = Vector3.new(9, 0, 9),
		knotwalkerRouteLocalPosition = Vector3.new(-12, 0, -12),
		-- THE DOORWAY IT TRAPS. The four bays meet on the lines x=0 and z=0 (each cell is 64 studs and
		-- their centres sit at plus or minus 32), so this is the middle of the opening between the two
		-- eastern bays — the nearest one to `knotwalkerSpawnLocalPosition`, and therefore the one
		-- `chooseOpening` picks first. Marked on the floor so a tester knows where to stand and watch.
		knotwalkerTrapLocalPosition = Vector3.new(32, 0, 0),
		noiseLocalPosition = Vector3.new(-38, 0, -32),
		-- Production wall setback: the Warden pile and emergence begin against the east wall. Moved out
		-- with that wall when the room grew to three cells — it emerges FROM the rock, so a five-stud
		-- setback is the whole point and leaving it at 59 would have had it rise out of open floor.
		wardenLocalPosition = Vector3.new(91, 0, -32),
		wardenFacing = Vector3.new(-1, 0, 0),
		-- Kept the same seventeen studs in front of the Warden it always was.
		wardenWaxLocalPosition = Vector3.new(74, 0, -44),
		-- The Heavy Crown sits on the Warden's route and within a Calver's strike radius.
		hazardLocalPosition = Vector3.new(0, 0, -32),
		lobbyReturnOffset = Vector3.new(18, 0, -44),
		roomTitle = "ENEMY TEST CHAMBER",
		-- The hotkey is named here because it is the one control with no button to discover it from.
		roomSubtitle = "INFINITE WAX  /  F7: REMOVE ALL ENEMIES  /  HOLD V: SUPER SPRINT  /  EAST DOOR: THE QUEEN'S REAL FLOOR  /  NORTH DOOR: UNLITTIUS' REAL FLOOR  /  BOTH ARE DARK, TAKE YOUR CANDLE",
	},
	bossFloors = {
		-- AT LEAST AS WIDE AND AS TALL AS THE DOORWAYS THEY MEET, which is the one relationship in this
		-- table that is not cosmetic. The corridor walls are what back the opening cut into the entry
		-- room, so a corridor narrower than that opening leaves a slot either side of the door looking
		-- straight out into the void between the two cells. Both authored floors hold their doorways at
		-- least 28 wide and 16 tall (`BossFloorPlan.DOORWAY_MINIMUM` is 26 x 14, `UnlittiusFloorPlan`'s
		-- is 28 x 16), so this clears the larger of the two.
		corridorWidth = 28,
		corridorHeight = 18,
		floorThickness = 2,
		wallThickness = 2,
		ceilingThickness = 2,
		plaqueInsetFromFloor = 16,
		-- The wall on your LEFT as you walk out of the laboratory, for both floors, so a tester learns
		-- the habit once.
		plaqueSide = -1,
		signSize = Vector3.new(20, 6, 0.6),
		signCanvasSize = Vector2.new(500, 150),
		signHeight = 11,
		startButtonSize = Vector3.new(7, 3.4, 0.6),
		startButtonHeight = 5.2,
		promptActionText = "Start Encounter",
		promptDistance = 12,
		promptHoldSeconds = 0.6,
		lightingSpacing = 26,
		-- Dim, and dimmer than the laboratory's own fill. The corridor's job is to get you to the
		-- button and then hand you over to your candle.
		lightingRange = 34,
		lightingBrightness = 0.18,
		definitions = {
			{
				id = "queen",
				bossId = "GrubQueen",
				-- EAST OF THE LABORATORY, entered through the west wall of her entry room.
				--
				-- HER PLUS IS THREE CELLS ACROSS, so this offset has to clear the laboratory by more
				-- than one cell or the wax wing ends up against its east wall. Her entry is at grid
				-- (0, 1) — one cell south of the chamber — and the wax wing at (-1, 0), which is the
				-- corner nearest the laboratory: at +240 the wing's west face lands 46 studs clear of
				-- the laboratory's outer wall, and the corridor runs past it 50 studs to the south.
				--
				-- Z = -32 puts her entry room on the same line as the old arena corridor, at local
				-- z = +32 on the east wall: the only one of the four laboratory walls with no board on
				-- it, and a full cell clear of the Warden's emergence pile.
				worldOriginOffset = Vector3.new(240, 0, -32),
				-- The laboratory is west of her floor, so the corridor meets the entry's west wall and
				-- her authored north doorway carries you on into the chamber — the same direction a
				-- real party walks it, having come down the ladder behind them.
				entranceDirection = "W",
				title = "GRUB QUEEN — FLOOR 10",
				subtitle = "THE REAL AUTHORED FLOOR. WAX WEST, DYNAMITE NORTH, THE WAY DOWN EAST, HER IN THE MIDDLE.",
				startButtonLabel = "START BOSS FIGHT",
				startButtonColor = Color3.fromRGB(122, 52, 44),
				promptObjectText = "Encounter Control",
				displayName = "Grub Queen",
			},
			{
				id = "shrine",
				bossId = "Unlittius",
				-- NORTH OF THE LABORATORY, entered through the south wall of his entry room.
				--
				-- HIS HORSESHOE IS THREE CELLS WIDE AND TWO DEEP, its arc along -Z and its two legs
				-- reaching back toward +Z. The entry is the bottom of the west leg, at grid (-1, 0), so
				-- X = +8 puts that leg's centre at laboratory-local x = -56 — the same clear stretch of
				-- north wall the old shrine corridor used, west of the pack guide board.
				--
				-- Z = -240 leaves 110 studs of corridor between the laboratory's north face and the
				-- entry's south face, and puts his whole floor 208 studs clear of hers.
				worldOriginOffset = Vector3.new(8, 0, -240),
				-- The laboratory is south of his floor, so the corridor meets the entry's south wall
				-- and his authored north doorway carries you up the west leg into the vigil, exactly
				-- the procession the floor is built as.
				entranceDirection = "S",
				title = "UNLITTIUS — FLOOR 20",
				subtitle = "THE REAL AUTHORED FLOOR. UP THE WEST VIGIL, ACROSS HIS SHRINE, DOWN THE EAST. HE CANNOT BE HURT.",
				startButtonLabel = "START SHRINE FIGHT",
				startButtonColor = Color3.fromRGB(70, 52, 108),
				promptObjectText = "Shrine Control",
				displayName = "Unlittius",
			},
		},
	},
	hotkeys = {
		-- REMOVE EVERY TEST ENEMY, from anywhere in the room.
		--
		-- F7 is the only free key that reads as a developer one. F8 is already this game's diagnostics
		-- overlay, so its neighbour carries the same "this is a tool, not a verb" meaning and no player
		-- will reach for it by accident. Every other candidate is taken: WASD move, Q leaves a mining
		-- stance, F follows in spectator, M and 0-6 are the hotbar and tools, Space jumps, Escape closes
		-- the keypad.
		--
		-- F9 WAS REJECTED rather than overlooked: Roblox binds it to the developer console, and a key
		-- that drops a console over the thing you are testing is worse than having no key.
		clearEnemies = Enum.KeyCode.F7,
		clearEnemiesLabel = "F7",
		-- HELD SUPER SPRINT. V is free in every mode this game has — it is not a tool slot, not a
		-- movement verb, and Roblox binds nothing to it — and it is under the hand already on WASD, which
		-- matters for a key you hold rather than press. Held rather than toggled so it can never be left
		-- on: releasing the key is the only state this has.
		superSprint = Enum.KeyCode.V,
		superSprintLabel = "V",
	},
	controls = {
		-- Two short boards replace the old five-row wall of buttons. Entity sections are cave-owned;
		-- utilities stay separate so the picker remains a two-row visual index at a glance.
		--
		-- ONE COLUMN IS ONE CAVE, and that is the whole organizing rule of the entity board. The shared
		-- pool reads down a single column beside them rather than across a two-wide block, so the board
		-- is four parallel rosters you compare left to right instead of a grid you have to parse. It
		-- also costs a column: five columns of buttons became four, which is most of why these two
		-- panels now fit in barely half the wall they used to cover.
		boards = {
			{
				id = "entities",
				-- RAISED FROM y=8 WHEN THE FIFTH ROW ARRIVED. The board grew downward to hold it, and at the
				-- old centre its bottom edge finished a third of a stud below the floor.
				localPosition = Vector3.new(-94.8, 9, -32),
				facing = Vector3.new(1, 0, 0),
				-- BACK TO FOUR COLUMNS, AND BACK TO 34 STUDS. The picker used to carry one column per
				-- cave plus a shared pool plus the wick pack, which is five columns of buttons and a
				-- panel widened to 42 to hold them — and it still could not spawn a Moss crawler or an
				-- Ice grub, because a shared row's variant was hardcoded to the laboratory's own family.
				--
				-- Selecting the CAVE first collapses all of that. Three buttons replace three columns,
				-- every roster below them spawns dressed for whichever cave is armed, and the signature
				-- creature and Warden become one button each instead of three. Fewer buttons, and the
				-- variant coverage went from one cave to all three.
				-- TALLER THAN IT WAS (12.4) BECAUSE THE PACK COLUMN IS FIVE DEEP NOW. Buttons start
				-- `buttonTopInset` below the top and step down by `buttonSpacing.Y`, so a fifth row needs
				-- 16.6 studs of panel or it hangs off the bottom edge — and `buildControlBoard` refuses to
				-- build a group taller than `maxRows` rather than letting it overflow silently.
				--
				-- WIDTH IS UNCHANGED AT 34, deliberately: a fifth COLUMN would not fit (five columns span
				-- 30.4 studs of spacing plus a 6.6-stud button, which is wider than the panel), which is why
				-- the pack grew down rather than across.
				size = Vector3.new(34, 16.6, 0.8),
				-- 20 px per stud on both axes, matching the tools board so identical text sizes render
				-- identically on the pair. That is the invariant to preserve when resizing — the pixel
				-- DENSITY, not the absolute canvas.
				canvasSize = Vector2.new(680, 332),
				title = "ENTITY PICKER",
				maxRows = 5,
				groups = {
					-- THE ARMED CAVE, and it is a mode rather than an action: pressing one of these
					-- spawns nothing. It decides which dressing every button to its right will use, so
					-- the same CRAWLER button produces a Stone, Moss or Ice crawler depending on what is
					-- armed here. That is the whole reason this board was reorganised.
					{
						id = "CAVE",
						label = "ARM CAVE",
						color = Color3.fromRGB(198, 176, 138),
						columns = 1,
						definitions = {
							{
								actionId = "cave:STONE",
								label = "STONE",
								color = Color3.fromRGB(84, 78, 68),
							},
							{
								actionId = "cave:MOSS",
								label = "MOSS",
								color = Color3.fromRGB(58, 77, 58),
							},
							{
								actionId = "cave:ICE",
								label = "ICE",
								color = Color3.fromRGB(58, 76, 90),
							},
						},
					},
					{
						id = "SHARED",
						label = "ALL CAVES",
						color = Color3.fromRGB(166, 147, 116),
						columns = 1,
						definitions = {
							{
								actionId = "spawn:DarkCrawler",
								label = "CRAWLER",
								color = Color3.fromRGB(91, 56, 56),
							},
							{
								actionId = "spawn:Moth",
								label = "MOTH",
								color = Color3.fromRGB(101, 87, 59),
							},
							{
								actionId = "spawn:VoidFly",
								label = "VOIDFLY",
								color = Color3.fromRGB(63, 53, 76),
							},
							{
								actionId = "spawn:AshamedLurker",
								label = "LURKER",
								color = Color3.fromRGB(83, 55, 62),
							},
						},
					},
					-- The wick pack (shared/Enemies). Family-agnostic like the shared pool — they wear
					-- whichever variant the armed cave dresses them in — but a distinct generation of
					-- creature with their own behaviour modules, so they read as their own roster.
					--
					-- THE TWO SET PIECES ARE LAST, for the same reason: pressing either starts a live
					-- encounter rather than adding a body, and neither is something to hit by accident
					-- while reaching for the grub button above them.
					{
						id = "PACK",
						label = "WICK PACK",
						color = Color3.fromRGB(150, 120, 96),
						columns = 1,
						definitions = {
							{
								actionId = "spawn:WaxGrub",
								label = "GRUB BROOD",
								color = Color3.fromRGB(96, 74, 48),
							},
							{
								actionId = "spawn:StoneGnawer",
								label = "GNAWER",
								color = Color3.fromRGB(78, 70, 60),
							},
							{
								actionId = "spawn:Longarm",
								label = "LONGARM",
								color = Color3.fromRGB(70, 58, 66),
							},
							{
								actionId = "spawn:GrubQueen",
								label = "GRUB QUEEN",
								color = Color3.fromRGB(112, 66, 44),
							},
							-- THE FIFTH ROW, and the reason the entity picker board is 16.6 studs tall
							-- instead of 12.4.
							--
							-- UNLIKE THE FOUR ABOVE IT, THIS DOES NOT PUT A BODY IN THE LABORATORY. It makes
							-- the same call the button in his corridor does, so the dais, the eight candles and
							-- the god build in his REAL shrine chamber — carved Terrain, north door, a walk
							-- away — and the tester goes to them. He is not a creature you can stand beside a
							-- Warden and compare: his candles ring a dais at a fixed radius and half his attacks
							-- aim at a forty-stud ceiling. The button exists so the encounter is discoverable
							-- from the console with the rest of the roster, not so it can be fought in the
							-- laboratory.
							{
								actionId = "spawn:Unlittius",
								label = "UNLITTIUS",
								color = Color3.fromRGB(64, 58, 96),
							},
						},
					},
					-- THE TWO CREATURES THAT ONLY EXIST IN ONE CAVE. Which signature and which Warden
					-- these produce follows the armed cave, which is why they are one button each rather
					-- than the three-per-family block this replaced. The status line names what actually
					-- spawned, so the label staying generic costs the tester nothing.
					{
						id = "SIGNATURE",
						label = "ARMED CAVE",
						color = Color3.fromRGB(150, 150, 150),
						columns = 1,
						definitions = {
							{
								actionId = "spawn:Signature",
								label = "SIGNATURE",
								color = Color3.fromRGB(72, 68, 62),
							},
							{
								actionId = "spawn:Warden",
								label = "WARDEN",
								color = Color3.fromRGB(80, 76, 68),
							},
						},
					},
				},
			},
			{
				id = "tools",
				localPosition = Vector3.new(-94.8, 8, 32),
				facing = Vector3.new(1, 0, 0),
				size = Vector3.new(34, 12.4, 0.8),
				canvasSize = Vector2.new(680, 248),
				title = "LAB TOOLS",
				maxRows = 3,
				-- GROUPED BY WHAT A PRESS CHANGES, which is the only grouping a tester can predict from
				-- the label alone: your own candle, the room around it, then the two set pieces that own
				-- their own state. The old lone-button SIGNAL column spent a full column on one press and
				-- read as an afterthought; TEST NOISE is a thing done TO the room and now sits with the
				-- rest of the room.
				groups = {
					{
						id = "SESSION",
						label = "SESSION",
						color = Color3.fromRGB(170, 148, 91),
						columns = 1,
						definitions = {
							{
								actionId = "reset:candle",
								label = "RESET CANDLE",
								color = Color3.fromRGB(105, 83, 47),
							},
							-- The room already hands every entrant `session.dynamiteCharges` silently, so
							-- dynamite has always WORKED here — it simply had no presence on the console,
							-- and an invisible grant is indistinguishable from a missing feature to anyone
							-- who did not read the config. This button is the visible handle: it restates
							-- the same grant on demand, which also covers the case the auto-grant cannot,
							-- namely a tester who has spent the stack mid-session.
							{
								actionId = "grant:dynamite",
								label = "GIVE DYNAMITE",
								color = Color3.fromRGB(124, 62, 44),
							},
							{
								actionId = "return:lobby",
								label = "RETURN",
								color = Color3.fromRGB(53, 83, 67),
							},
						},
					},
					{
						id = "ROOM",
						label = "ROOM",
						color = Color3.fromRGB(170, 116, 91),
						columns = 1,
						definitions = {
							{
								actionId = "remove:all",
								label = "REMOVE ALL",
								color = Color3.fromRGB(112, 48, 42),
							},
							{
								actionId = "emit:noise",
								label = "TEST NOISE",
								color = Color3.fromRGB(50, 77, 91),
							},
						},
					},
					{
						id = "CROWN",
						label = "CROWN",
						color = Color3.fromRGB(184, 125, 65),
						columns = 1,
						definitions = {
							{
								actionId = "reset:hazards",
								label = "RESET",
								color = Color3.fromRGB(101, 78, 43),
							},
							{
								actionId = "trigger:hazard",
								label = "DROP",
								color = Color3.fromRGB(123, 76, 38),
							},
						},
					},
					{
						id = "WARDEN",
						label = "WARDEN",
						color = Color3.fromRGB(129, 120, 105),
						columns = 1,
						definitions = {
							{
								actionId = "warden:wake",
								label = "WAKE",
								color = Color3.fromRGB(88, 68, 50),
							},
							{
								actionId = "warden:stun",
								label = "STUN",
								color = Color3.fromRGB(64, 76, 93),
							},
						},
					},
				},
			},
		},
		-- A QUARTER SMALLER IN EVERY DIMENSION than the panels these replace. The boards were authored
		-- when the console was a five-row wall and had grown to nearly a hundred studs of painted metal
		-- across the room's west face, which put half the buttons outside `promptDistance` of the other
		-- half — a tester walked the wall to press two things that belong together. Nothing here is
		-- hand-placed: DevTestRoomBuilder reflows both boards from these four numbers plus each group's
		-- `columns`, so the pair may be retuned freely as long as the row/height check below still holds.
		--
		-- THE HEIGHT BUDGET, because it is the one that fails silently, and the one number here that is
		-- NOT free to retune on its own. A button's top edge must clear the group header, which the
		-- builder draws down to 0.33 of a board's height — a SCALE, so it moves further down a taller
		-- board while this inset does not move at all. The entity picker is the tall one at 16.6 studs,
		-- putting its header's underside 5.48 studs from the top, so the inset is sized for THAT board:
		-- a first row whose top edge sits at `buttonTopInset - buttonSize.Y / 2` = 5.53 clears it, and
		-- the fifth row's bottom edge lands at
		-- `buttonTopInset + (maxRows - 1) * buttonSpacing.Y + buttonSize.Y / 2` = 15.28, inside 16.6.
		-- The 12.4-stud tools board rides the same inset with room to spare (header at 4.09, three rows
		-- ending at 11.18) and simply carries a slightly deeper gap under its title.
		--
		-- WHICH IS WHY THIS WENT 5 -> 6.3 WHEN THE PACK GAINED ITS FIFTH BUTTON. Growing that board to
		-- hold the row also pushed its header down, and at the old inset the first row of buttons would
		-- have been drawn straight through "WICK PACK". Retune `buttonSize.Y`, `buttonSpacing.Y` or any
		-- board's height and re-derive this; DevTestRoomRulesTests asserts both ends of the budget for
		-- every board so the failure is a red test rather than a mess in Studio.
		buttonSize = Vector3.new(6.6, 1.55, 0.5),
		buttonSpacing = Vector2.new(7.6, 2.05),
		buttonTopInset = 6.3,
		buttonForwardGap = 0.15,
		buttonCanvasPixelsPerStud = 50,
		promptActionText = "Use Control",
		-- Compact panels keep every prompt at body height. The service still performs its own stricter
		-- session/body/console validation before accepting any action.
		promptDistance = 14,
		promptHoldSeconds = 0,
	},
	guide = {
		-- Static reference cards avoid multiplayer selection contention and let testers compare every
		-- behavior/counter before they spawn anything. The center gap clears the room divider seam.
		boards = {
			{
				id = "shared",
				localPosition = Vector3.new(-40, 12, 94.8),
				facing = Vector3.new(0, 0, -1),
				size = Vector3.new(56, 22, 0.8),
				canvasSize = Vector2.new(1120, 440),
				title = "ENTITY FIELD GUIDE",
				groups = {
					{
						id = "SHARED",
						label = "ALL CAVES",
						color = Color3.fromRGB(166, 147, 116),
						columns = 2,
						entries = {
							{
								entityId = "DarkCrawler",
								name = "DARK CRAWLER",
								badge = "DARK-HUNTER",
								description = "Prowls darkness, follows wax trails and repeated noise, then drains wax on contact.",
								testHint = "TEST: Keep it watched to stall; FLARE forces retreat.",
								color = Color3.fromRGB(145, 72, 68),
							},
							{
								entityId = "Moth",
								name = "CAVE MOTH",
								badge = "THE DRAWN",
								description = "Perches on stone, flies at any uncovered flame and drains wax. From floor 4 up, unbroken contact snuffs you — 12s falling to 6s by depth.",
								testHint = "TEST: CUP, DECOY, or run clear. FLARE draws it in.",
								color = Color3.fromRGB(171, 143, 84),
							},
							{
								entityId = "VoidFly",
								name = "VOIDFLY",
								badge = "TERRITORIAL DARK-HUNTER",
								description = "Holds one ceiling patch and dives on candles beneath it; the fourth hit snuffs. Noise widens the patch, and it will chase for 10s.",
								testHint = "TEST: FLARE or a teammate within 8 studs breaks the count; the dial does not.",
								color = Color3.fromRGB(112, 87, 137),
							},
							{
								entityId = "AshamedLurker",
								name = "ASHAMED LURKER",
								badge = "ARCH SET PIECE",
								description = "Traps one half of an arch and grabs runners there; the other lane stays safe.",
								testHint = "TEST: Cross slowly, or hold a bright gaze from the open lane.",
								color = Color3.fromRGB(145, 81, 94),
							},
						},
					},
				},
			},
			{
				id = "families",
				localPosition = Vector3.new(40, 12, 94.8),
				facing = Vector3.new(0, 0, -1),
				size = Vector3.new(56, 22, 0.8),
				canvasSize = Vector2.new(1120, 440),
				title = "CAVE SIGNATURES",
				groups = {
					{
						id = "STONE",
						label = "STONE",
						color = Color3.fromRGB(139, 128, 111),
						columns = 1,
						entries = {
							{
								entityId = "Listener",
								name = "CAVE LISTENER",
								badge = "SIGNATURE DARK-HUNTER",
								description = "Blind, and it hears you move now: a pick from 95 studs, footsteps from 34. It runs at the noise.",
								testHint = "TEST: Make noise, then hold still. Only a FLARE moves it.",
								color = Color3.fromRGB(139, 128, 111),
							},
							{
								entityId = "StoneWarden",
								name = "STONE WARDEN",
								badge = "WARDEN SET PIECE",
								description = "Wake it with all three wax pieces. Contact kills; light and tools do nothing.",
								testHint = "TEST: Lead it under the Heavy Crown. Falling rock is its only stun.",
								color = Color3.fromRGB(139, 128, 111),
							},
						},
					},
					{
						id = "MOSS",
						label = "MOSS",
						color = Color3.fromRGB(104, 136, 91),
						columns = 1,
						entries = {
							{
								entityId = "Knotwalker",
								name = "KNOTWALKER",
								badge = "SIGNATURE DARK-HUNTER",
								description = "Does not hunt. It strings ankle-high vines across two doorways and comes when one drops you.",
								testHint = "TEST: Burn a wire at full dial, or hop it. Your speed sets the stun.",
								color = Color3.fromRGB(104, 136, 91),
							},
							{
								entityId = "MossWarden",
								name = "MOSS WARDEN",
								badge = "WARDEN SET PIECE",
								description = "Wake it with all three wax pieces. Contact kills; light and tools do nothing.",
								testHint = "TEST: Lead it under the Heavy Crown. Falling rock is its only stun.",
								color = Color3.fromRGB(104, 136, 91),
							},
						},
					},
					{
						id = "ICE",
						label = "ICE",
						color = Color3.fromRGB(105, 143, 166),
						columns = 1,
						entries = {
							{
								entityId = "Calver",
								name = "CALVER",
								badge = "SIGNATURE DARK-HUNTER",
								description = "Hammers existing roof formations after a long wind-up and never attacks by contact.",
								testHint = "TEST: Leave the fall zone; FLARE drives it off.",
								color = Color3.fromRGB(105, 143, 166),
							},
							{
								entityId = "IceWarden",
								name = "ICE WARDEN",
								badge = "WARDEN SET PIECE",
								description = "Wake it with all three wax pieces. Contact kills; light and tools do nothing.",
								testHint = "TEST: Lead it under the Heavy Crown. Falling rock is its only stun.",
								color = Color3.fromRGB(105, 143, 166),
							},
						},
					},
				},
			},
			-- THE WICK PACK, on its own wall.
			--
			-- IT IS A THIRD BOARD RATHER THAN A THIRD GROUP because guide cards are laid out
			-- proportionally: adding four entries to the ALL CAVES board would either halve every card's
			-- height (eight entries at two columns is four rows instead of two) or halve its width (a
			-- second group doubles the column count on a fixed-width board). Both make every existing
			-- card harder to read to accommodate creatures that have nothing to do with them.
			--
			-- The two existing guide boards fill the +Z wall (x = -32 and +32, 56 wide each, spanning
			-- -60..+60 of a 128-stud room). The -Z wall was empty, so this takes it and faces back into
			-- the room, which also means a tester reads the pack roster while standing where the pack
			-- spawns rather than turning their back on it.
			{
				id = "pack",
				localPosition = Vector3.new(0, 12, -94.8),
				facing = Vector3.new(0, 0, 1),
				size = Vector3.new(56, 22, 0.8),
				canvasSize = Vector2.new(1120, 440),
				title = "WICK PACK FIELD GUIDE",
				groups = {
					{
						id = "PACK",
						label = "ALL CAVES / NEW GENERATION",
						color = Color3.fromRGB(150, 120, 96),
						columns = 2,
						entries = {
							{
								entityId = "WaxGrub",
								name = "WAX GRUB",
								badge = "TIER 1 SWARM",
								description = "Broods of 2-5. Ignores a moving candle, latches to a still one and drains wax; follows drip trails.",
								testHint = "TEST: Keep moving. STOMP scares one off — a latched one takes up to 3; FLARE clears a brood.",
								color = Color3.fromRGB(150, 120, 96),
							},
							{
								entityId = "StoneGnawer",
								name = "STONE GNAWER",
								badge = "TIER 3 BLIND CHARGER",
								description = "Eats until it hears you, warns for 1.1s, then charges a straight line it cannot steer out of.",
								testHint = "TEST: Stand still to vanish. When it warns, step SIDEWAYS — never back.",
								color = Color3.fromRGB(120, 110, 96),
							},
							{
								entityId = "Longarm",
								name = "LONGARM",
								badge = "TIER 3 STALKER",
								description = "Reads as a two-limbed biped until it strikes, then unfolds to nine studs. Silent until committed.",
								testHint = "TEST: FLARE is the only thing that scares it. A DECOY pulls it off you entirely.",
								color = Color3.fromRGB(112, 96, 120),
							},
							{
								entityId = "GrubQueen",
								name = "GRUB QUEEN",
								badge = "BOSS SET PIECE",
								description = "Only dynamite hurts her. Crawls slowly and bites 9 studs in front; births 2 grubs every 7.5s and calls the room every 26s.",
								testHint = "TEST: EAST door — her REAL floor 10, five carved rooms, wax west and dynamite north. GRUB QUEEN on the console instead puts a bare one on the lab floor. Six sticks kill her; watch the vent brighten before each brood.",
								color = Color3.fromRGB(168, 99, 66),
							},
							{
								entityId = "Unlittius",
								name = "UNLITTIUS",
								badge = "BOSS SET PIECE",
								description = "Floats over a dais and CANNOT be hurt. Drops the marked ceiling, throws two conjured boulders, summons Gnawers, and rakes anyone under him.",
								testHint = "TEST: NORTH door — his REAL floor 20, the horseshoe. UNLITTIUS on the console starts it from here. Light all 8 candles to banish him; each dims him for good, and only a lit candle of your own can light one.",
								color = Color3.fromRGB(122, 92, 178),
							},
						},
					},
				},
			},
		},
	},
	lurker = {
		openingWidth = 12,
		openingHeight = 11,
		postSize = Vector3.new(2.2, 11, 3),
		lintelHeight = 2.2,
		-- Two freestanding arches let the real ashamed/hidden/relocation lifecycle be exercised.
		sites = {
			{ localPosition = Vector3.new(-20, 0, -17), facing = Vector3.new(1, 0, 0), trapSide = "Left" },
			{ localPosition = Vector3.new(20, 0, -17), facing = Vector3.new(-1, 0, 0), trapSide = "Right" },
		},
		visualSeed = 6100610,
	},
	hazard = {
		variantId = "Hammer",
		visualSeed = 6100611,
	},
	markers = {
		size = Vector3.new(8, 0.12, 8),
		candleLabel = "CANDLE RESET",
		threatLabel = "THREAT SPAWN",
		knotwalkerLabel = "KNOTWALKER START",
		knotwalkerRouteLabel = "KNOT ROUTE: WALK EAST",
		-- The bay opening it will actually string a wire across. Marked because a wire goes up in about
		-- two and a half seconds and a tester who is not already looking at the right doorway misses the
		-- one piece of free information this creature ever gives away.
		knotwalkerTrapLabel = "KNOT TRAP DOORWAY",
		noiseLabel = "NOISE LURE",
		wardenLabel = "WARDEN",
		hazardLabel = "FALL ZONE",
	},
	-- A LOW AMBIENT FILL, and it cannot touch a single creature.
	--
	-- WHY THIS IS SAFE TO BRIGHTEN AT ALL. Nothing in this game perceives Roblox lighting. Every
	-- creature that reads light — the dark-hunters that flee it, the Moth that is drawn to it, the grub
	-- and the Longarm that panic at a flare — reads `Logic/LightField` over the list
	-- `server/LightSources.collect` builds, and that list is assembled from candles, flares, decoys,
	-- remains and burning moss. A PointLight is not a light source to this game; it is scenery. So the
	-- laboratory can be lit to whatever a tester needs to SEE by without changing what anything in it
	-- does, which is exactly the property a test room wants.
	--
	-- WHY IT NEEDED FIXING. The fixtures hang from the ceiling, and the ceiling went from 30 studs to
	-- 52 when the room grew to three cells — with the old 36-stud range they stopped reaching the floor
	-- by sixteen studs, so the room went black from the waist down. The grid was also still sized to
	-- the old +-42 footprint and covered under half of the new +-96 span.
	lighting = {
		fixtureSize = Vector3.new(8, 0.3, 8),
		-- Nine fixtures on a 64-stud pitch, which is one per room cell and reaches the corners.
		localOffsets = {
			Vector3.new(-64, 0, -64),
			Vector3.new(0, 0, -64),
			Vector3.new(64, 0, -64),
			Vector3.new(-64, 0, 0),
			Vector3.new(0, 0, 0),
			Vector3.new(64, 0, 0),
			Vector3.new(-64, 0, 64),
			Vector3.new(0, 0, 64),
			Vector3.new(64, 0, 64),
		},
		-- Comfortably past the 52-stud drop to the floor so the pools overlap into a wash rather than
		-- landing as nine separate spots with dark between them.
		range = 82,
		-- DELIBERATELY DIM. This is a fill that lets a tester read the room and the creature in it, not
		-- daylight: the point of the laboratory is watching a body behave, and washing it out would hide
		-- the silhouettes and the eye glow that are half of what there is to look at.
		brightness = 0.4,
	},
	ui = {
		canvasSize = Vector2.new(720, 420),
		titleTextSize = 54,
		bodyTextSize = 34,
		buttonTextSize = 26,
		controlTitleTextSize = 34,
		controlGroupTextSize = 24,
		guideTitleTextSize = 34,
		guideGroupTextSize = 24,
		guideNameTextSize = 23,
		guideBadgeTextSize = 14,
		guideBodyTextSize = 17,
		guideHintTextSize = 16,
	},
	palette = {
		floor = Color3.fromRGB(45, 43, 41),
		wall = Color3.fromRGB(35, 34, 34),
		trim = Color3.fromRGB(73, 68, 62),
		metal = Color3.fromRGB(47, 49, 51),
		panel = Color3.fromRGB(15, 16, 17),
		text = Color3.fromRGB(231, 224, 207),
		mutedText = Color3.fromRGB(153, 145, 132),
		accent = Color3.fromRGB(203, 63, 49),
		light = Color3.fromRGB(255, 201, 139),
		candleMarker = Color3.fromRGB(191, 151, 81),
		threatMarker = Color3.fromRGB(122, 48, 45),
		wardenMarker = Color3.fromRGB(104, 97, 87),
		hazardMarker = Color3.fromRGB(178, 107, 45),
	},
}

return DevTestRoom
