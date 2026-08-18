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
		noiseLocalPosition: Vector3,
		wardenLocalPosition: Vector3,
		wardenFacing: Vector3,
		wardenWaxLocalPosition: Vector3,
		hazardLocalPosition: Vector3,
		lobbyReturnOffset: Vector3,
		roomTitle: string,
		roomSubtitle: string,
	},
	-- THE BOSS ARENA: a second chamber, reached on foot down a corridor from the main laboratory.
	--
	-- Authored as its own room rather than as another marker on the laboratory floor because the Grub
	-- Queen is a FLOOR, not a spawn. In a real run she owns a hand-built five-room plus
	-- (Logic/BossFloorPlan) that the player arrives on, reads, and fights across — and testing her in the
	-- middle of a room already holding a Warden pile, two Lurker arches and a Crown answers nothing
	-- about the encounter. This gives the fight the one thing the laboratory could not: a threshold you
	-- cross, and a room that contains only her.
	--
	-- EVERY FIXTURE OFFSET COMES FROM `Logic/BossFloorPlan.fixtures`, not from this file. Her position
	-- relative to the entrance and her two guards' flanking posts are the encounter's own composition,
	-- and a second copy of them here would drift from the real fight the first time either was tuned.
	-- What is authored here is only the ROOM: how big it is, how you get in, and where the start button
	-- is. See `DevTestRoomBuilder.buildArena` for the frame that maps those offsets into it.
	arena: {
		-- Which laboratory wall the corridor leaves through, as a local Z on the east (+X) wall. The east
		-- wall is the only one of the four carrying no board, and +32 keeps the opening a full cell clear
		-- of the Warden's emergence pile at -32.
		corridorLocalZ: number,
		corridorLength: number,
		corridorWidth: number,
		corridorHeight: number,
		interiorSize: Vector3,
		floorThickness: number,
		wallThickness: number,
		ceilingThickness: number,
		doorwayWidth: number,
		doorwayHeight: number,
		-- Arena-local, in the SAME frame convention BossFloorPlan uses: +Z is back toward the entrance,
		-- so a positive Z here is beside the door you just walked through.
		startButtonLocalPosition: Vector3,
		startButtonSize: Vector3,
		startButtonColor: Color3,
		startButtonLabel: string,
		signLocalPosition: Vector3,
		signSize: Vector3,
		signCanvasSize: Vector2,
		title: string,
		subtitle: string,
		promptActionText: string,
		promptObjectText: string,
		promptDistance: number,
		promptHoldSeconds: number,
		markerLabel: string,
		lightingLocalOffsets: { Vector3 },
		lightingRange: number,
		lightingBrightness: number,
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
		roomSubtitle = "INFINITE WAX  /  F7: REMOVE ALL ENEMIES  /  HOLD V: SUPER SPRINT  /  EAST DOOR: QUEEN ARENA",
	},
	arena = {
		corridorLocalZ = 32,
		-- Long enough that the arena is a PLACE you went to rather than an alcove off the laboratory —
		-- the doorway at one end is not in shot from the other, so arriving reads as arriving.
		corridorLength = 40,
		-- AT LEAST AS WIDE AND AS TALL AS THE ARENA DOORWAY IT RUNS INTO, which is the one relationship
		-- here that is not cosmetic: the corridor's own walls are what back that opening, so a corridor
		-- narrower than the doorway leaves a slot either side of the door looking out into the void.
		corridorWidth = 26,
		corridorHeight = 16,
		-- One and a half times the authored 64-stud boss chamber, and 48 tall against her authored 46
		-- (Logic/BossFloorPlan.CENTER_CEILING). Bigger than the real room on purpose: a tester wants to
		-- watch the fight from outside it as well as stand in it, and her brood needs somewhere to spread
		-- that is not the camera. The height is the one dimension that is NOT free — she is the tallest
		-- body in the game and a short ceiling is most of what "she did not spawn" used to mean.
		interiorSize = Vector3.new(96, 48, 96),
		floorThickness = 2,
		wallThickness = 2,
		ceilingThickness = 2,
		-- The real floor holds every opening on it to 26x14 (BossFloorPlan.DOORWAY_MINIMUM) so nothing in
		-- the encounter has to duck. The corridor is narrower than that because it is a service passage
		-- rather than encounter space, but the ARENA's own doorway matches the authored minimum.
		doorwayWidth = 26,
		doorwayHeight = 14,
		-- Beside the door, on the entry wall, at chest height: you walk in, it is the first thing facing
		-- you, and pressing it is the last thing you do before the room is no longer safe.
		startButtonLocalPosition = Vector3.new(-20, 5, 46.4),
		startButtonSize = Vector3.new(7, 3.4, 0.8),
		startButtonColor = Color3.fromRGB(122, 52, 44),
		startButtonLabel = "START BOSS FIGHT",
		-- ABOVE the doorway, not across it. Centred on the door and mounted on the lintel, so it is the
		-- thing over your head as you come through rather than a panel in the opening.
		signLocalPosition = Vector3.new(0, 19, 47.4),
		signSize = Vector3.new(34, 8, 0.8),
		-- 20 px per stud on both axes, the same density every board in the laboratory is authored at.
		signCanvasSize = Vector2.new(680, 160),
		title = "GRUB QUEEN ARENA",
		subtitle = "PRESS START — SHE AND TWO CHAINED LONGARMS SPAWN IN THEIR AUTHORED POSTS",
		promptActionText = "Start Encounter",
		promptObjectText = "Encounter Control",
		promptDistance = 12,
		-- A held press, unlike every board button. This one starts a fight rather than adding a body, and
		-- a tester walking past the entry wall should not be able to brush it.
		promptHoldSeconds = 0.6,
		markerLabel = "QUEEN",
		-- Four fixtures on the room's quarters. Deliberately dimmer than the laboratory's: her chamber is
		-- meant to be a cave you can barely read, and a floodlit boss is a different creature.
		lightingLocalOffsets = {
			Vector3.new(-24, 0, -24),
			Vector3.new(24, 0, -24),
			Vector3.new(-24, 0, 24),
			Vector3.new(24, 0, 24),
		},
		lightingRange = 60,
		lightingBrightness = 0.35,
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
				localPosition = Vector3.new(-94.8, 8, -32),
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
				size = Vector3.new(34, 12.4, 0.8),
				-- 20 px per stud on both axes, matching the tools board so identical text sizes render
				-- identically on the pair. That is the invariant to preserve when resizing — the pixel
				-- DENSITY, not the absolute canvas.
				canvasSize = Vector2.new(680, 248),
				title = "ENTITY PICKER",
				maxRows = 4,
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
					-- QUEEN IS LAST because she is the set piece: spawning her starts a live encounter
					-- that births grubs on a timer, which is not something to press by accident while
					-- reaching for the grub button above it.
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
		-- THE HEIGHT BUDGET, because it is the one that fails silently. A button's top edge must clear
		-- the group header, which the builder draws down to 0.33 of a board's height: for the 12.4-stud
		-- boards above that is 4.09 studs from the top against a first-row top edge at
		-- `buttonTopInset - buttonSize.Y / 2` = 4.23. The last row's bottom edge lands at
		-- `buttonTopInset + (maxRows - 1) * buttonSpacing.Y + buttonSize.Y / 2` = 11.93, inside 12.4.
		-- Raise `maxRows` past four, or `buttonSize.Y`/`buttonSpacing.Y` much past these, and buttons
		-- start overrunning the header or the bottom edge with no error to say so.
		buttonSize = Vector3.new(6.6, 1.55, 0.5),
		buttonSpacing = Vector2.new(7.6, 2.05),
		buttonTopInset = 5,
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
								testHint = "TEST: Six sticks kill her — required before the ladder accepts you. Watch the vent brighten before each brood.",
								color = Color3.fromRGB(168, 99, 66),
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
