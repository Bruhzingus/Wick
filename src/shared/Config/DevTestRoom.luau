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
		interiorSize = Vector3.new(128, 30, 128),
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
		-- Production wall setback: the Warden pile and emergence begin against the east wall.
		wardenLocalPosition = Vector3.new(59, 0, -32),
		wardenFacing = Vector3.new(-1, 0, 0),
		wardenWaxLocalPosition = Vector3.new(42, 0, -44),
		-- The Heavy Crown sits on the Warden's route and within a Calver's strike radius.
		hazardLocalPosition = Vector3.new(0, 0, -32),
		lobbyReturnOffset = Vector3.new(18, 0, -44),
		roomTitle = "ENEMY TEST CHAMBER",
		roomSubtitle = "INFINITE WAX  /  GREEN MARKER: WALK EAST",
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
				localPosition = Vector3.new(-62.8, 8, -32),
				facing = Vector3.new(1, 0, 0),
				size = Vector3.new(34, 12.4, 0.8),
				-- 20 px per stud on both axes, matching the tools board so identical text sizes render
				-- identically on the pair.
				canvasSize = Vector2.new(680, 248),
				title = "ENTITY PICKER",
				maxRows = 4,
				groups = {
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
					{
						id = "STONE",
						label = "STONE",
						color = Color3.fromRGB(139, 128, 111),
						columns = 1,
						definitions = {
							{
								actionId = "spawn:Listener",
								label = "LISTENER",
								color = Color3.fromRGB(70, 64, 59),
							},
							{
								actionId = "spawn:StoneWarden",
								label = "WARDEN",
								color = Color3.fromRGB(82, 77, 69),
							},
						},
					},
					{
						id = "MOSS",
						label = "MOSS",
						color = Color3.fromRGB(104, 136, 91),
						columns = 1,
						definitions = {
							{
								actionId = "spawn:Knotwalker",
								label = "KNOTWALKER",
								color = Color3.fromRGB(58, 77, 58),
							},
							{
								actionId = "spawn:MossWarden",
								label = "WARDEN",
								color = Color3.fromRGB(61, 82, 55),
							},
						},
					},
					{
						id = "ICE",
						label = "ICE",
						color = Color3.fromRGB(105, 143, 166),
						columns = 1,
						definitions = {
							{
								actionId = "spawn:Calver",
								label = "CALVER",
								color = Color3.fromRGB(62, 79, 91),
							},
							{
								actionId = "spawn:IceWarden",
								label = "WARDEN",
								color = Color3.fromRGB(61, 80, 94),
							},
						},
					},
				},
			},
			{
				id = "tools",
				localPosition = Vector3.new(-62.8, 8, 32),
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
				localPosition = Vector3.new(-32, 12, 62.8),
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
								description = "Perches on walls, follows uncovered flame and feeds until deep contact can snuff.",
								testHint = "TEST: CUP, DECOY, or run clear. FLARE draws it in.",
								color = Color3.fromRGB(171, 143, 84),
							},
							{
								entityId = "VoidFly",
								name = "VOIDFLY",
								badge = "TERRITORIAL DARK-HUNTER",
								description = "Guards one ceiling patch and snuffs after four uninterrupted territorial dives.",
								testHint = "TEST: FLARE or a nearby teammate breaks the sequence; the dial does not.",
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
				localPosition = Vector3.new(32, 12, 62.8),
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
								description = "Functionally blind: mining, falling stone and bells draw it; walking is silent.",
								testHint = "TEST: Emit noise, then go quiet. Light will not help.",
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
								description = "Reads your facing and commits one room ahead instead of chasing your position.",
								testHint = "TEST: Walk east at green, then reverse or change route.",
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
	lighting = {
		fixtureSize = Vector3.new(8, 0.3, 8),
		localOffsets = {
			Vector3.new(-42, 0, -42),
			Vector3.new(0, 0, -42),
			Vector3.new(42, 0, -42),
			Vector3.new(-42, 0, 0),
			Vector3.new(0, 0, 0),
			Vector3.new(42, 0, 0),
			Vector3.new(-42, 0, 42),
			Vector3.new(0, 0, 42),
			Vector3.new(42, 0, 42),
		},
		range = 36,
		brightness = 0.55,
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
