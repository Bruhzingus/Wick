--!strict
-- Builds "The Landing" — the static mineshaft hub — once at server boot. Unlike FloorBuilder this is
-- not seeded or rebuilt per run: one fixed layout for the server's lifetime, so a player returning
-- from a cave and a player joining afterwards stand in the same room. Decides no gameplay: elevator
-- interaction and the descent ride live in ElevatorService, tier/ready/party state in
-- PartyLobbyService/Interfaces.Party. This file only places Instances and hands out references.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)
local LeverGeometry = require(ReplicatedStorage.Shared.Logic.LeverGeometry)

local LobbyRoomBuilder = {}

-- Everything on one elevator that ElevatorService needs to drive. `car` is the model that physically
-- descends during the ride; the header board and shaft stay behind in the room.
export type ElevatorParts = {
	partyId: number,
	car: Model,
	restPivot: CFrame,
	gate: BasePart,
	-- The descent lever's one lamp. Nobody touches the lever, so this is the whole of its state: lit
	-- while the car is armed for a descent, dark once it is committed and the handle has thrown.
	leverLamp: BasePart,
	headerTitle: TextLabel,
	headerStatus: TextLabel,
	headerRoster: TextLabel,
}

export type LeaderboardRow = {
	rank: TextLabel,
	candle: TextLabel,
	depth: TextLabel,
}

export type LeaderboardDisplay = {
	rows: { LeaderboardRow },
	status: TextLabel,
	refreshPrompt: ProximityPrompt,
}

-- Constructed timber and iron, not natural rock: the hub reads as built, warm and safe, in
-- deliberate contrast to the caves below.
local TIMBER = Color3.fromRGB(96, 68, 46)
local TIMBER_DARK = Color3.fromRGB(58, 41, 28)
local PLANK = Color3.fromRGB(78, 55, 38)
local IRON = Color3.fromRGB(58, 56, 54)
local IRON_DARK = Color3.fromRGB(38, 37, 36)
local RAIL = Color3.fromRGB(104, 96, 86)
local BRASS = Color3.fromRGB(143, 103, 58)
local STONE = Color3.fromRGB(62, 58, 54)
local LANTERN = Color3.fromRGB(255, 188, 112)
local BOARD_BACKING = Color3.fromRGB(34, 27, 22)
local GOLD = Color3.fromRGB(255, 212, 128)
local PARCHMENT = Color3.fromRGB(232, 224, 210)
local DIM_TEXT = Color3.fromRGB(150, 138, 122)
local TUNNEL_BLACK = Color3.fromRGB(4, 3, 3)
local WAX_BODY = Color3.fromRGB(238, 232, 210)
local WAX_DEEP = Color3.fromRGB(212, 202, 172)
-- Broken country rock and spent ore: what comes up the shaft that ISN'T wax. Cold and dark against
-- every warm timber in the room, which is the whole point of having any of it here — it is the one
-- material in the hub that belongs to the cave rather than to the company.
local SPOIL = Color3.fromRGB(54, 52, 58)
local SPOIL_DARK = Color3.fromRGB(41, 39, 45)
-- Enamel hazard paint. Pitched BRIGHT on purpose and only usable here: the hub is a lit room, so a
-- warning has to out-read nine ceiling lamps falling on bare timber. The caves get their own, far
-- dimmer flaked lime-wash (`Config/MineRelics.palette.paintColor`) for the opposite reason — down
-- there a sign is found by one candle, and anything this bright would be the brightest thing in the
-- world. Same object, two rooms, two exposures.
local PAINT = Color3.fromRGB(198, 188, 168)

-- GALLERY TIMBERWORK. `BEAM_DEPTH` is shared by the beam itself, the knee braces that die into its
-- underside and the lagging nailed below it, so the three cannot drift apart the way they would if
-- each carried its own copy of the number. `BRACE_RUN` is both the drop down the post AND the reach
-- along the beam, which is what makes the diagonal a true 45 degrees and its length that run times
-- root two — change one number and the brace stays correct.
local BEAM_DEPTH = 1.4
local BRACE_RUN = 4
-- The descent lever alone. Painted machinery, deliberately COLD against a room built entirely of
-- warm timber and iron, because it is the one object in the hub that is not scenery — a rider should
-- be able to pick it out of the car's wall at a glance and read what it is doing. Both greens are
-- kept desaturated and light: under the hub's orange lanterns a saturated green turns to mud, and a
-- dark one turns to a black lump. The grip is the only warm note, and it is the whole silhouette.
local SWITCH_PAINT = Color3.fromRGB(96, 120, 112)
local SWITCH_PAINT_LIT = Color3.fromRGB(116, 141, 132)
local SWITCH_GRIP = Color3.fromRGB(146, 58, 44)

local built = false
local elevatorParts: { ElevatorParts } = {}
local leaderboardDisplay: LeaderboardDisplay? = nil
local shopPrompt: ProximityPrompt? = nil

local function newPart(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function block(size: Vector3, position: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	return newPart(size, CFrame.new(position), color, material, parent)
end

local function pointLight(parent: BasePart, range: number, brightness: number, shadows: boolean)
	local light = Instance.new("PointLight")
	light.Color = LANTERN
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows
	light.Parent = parent
end

-- A wall candle's CFrame sits against the wall with local +Z pointing into the room.
local function wallCandle(cframe: CFrame, parent: Instance)
	local candle = Config.LobbyRoom.wallCandles
	local plate = newPart(candle.bracketPlateSize, cframe, IRON_DARK, Enum.Material.Metal, parent)
	plate.Name = "CandleBracket"

	local armY = -candle.candleSize.Y / 2
	local arm = newPart(
		candle.bracketArmSize,
		cframe * CFrame.new(0, armY, candle.bracketArmSize.Z / 2),
		IRON,
		Enum.Material.Metal,
		parent
	)
	arm.Name = "CandleBracketArm"

	-- A Roblox cylinder's round faces run along its own local X, not Y, so standing the wax up with a
	-- 90° roll makes candleSize.X the rendered height and candleSize.Y a diameter — the opposite of
	-- what every offset below assumes. Swap X/Y on the part's actual Size so the geometry matches the
	-- math, and rest its base on the arm's real top face (armY plus half the arm's own thickness)
	-- instead of an offset that silently assumed a thicker arm than `bracketArmSize` builds — that
	-- mismatch was the gap that left the candle floating above its bracket.
	local armTopY = armY + candle.bracketArmSize.Y / 2
	local bodyCFrame = cframe
		* CFrame.new(0, armTopY + candle.candleSize.Y / 2, candle.bracketArmSize.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	local body = newPart(
		Vector3.new(candle.candleSize.Y, candle.candleSize.X, candle.candleSize.Z),
		bodyCFrame,
		WAX_BODY,
		Enum.Material.SmoothPlastic,
		parent
	)
	body.Name = "WallCandleWax"
	body.Shape = Enum.PartType.Cylinder
	body.CanCollide = false

	local flame = newPart(
		candle.flameSize,
		cframe * CFrame.new(0, armTopY + candle.candleSize.Y + candle.flameSize.Y / 2, candle.bracketArmSize.Z),
		LANTERN,
		Enum.Material.Neon,
		parent
	)
	flame.Name = "WallCandleFlame"
	flame.Shape = Enum.PartType.Ball
	flame.CanCollide = false
	flame.CastShadow = false
	pointLight(flame, Config.LobbyRoom.lighting.candleRange, Config.LobbyRoom.lighting.candleBrightness, false)
end

-- A lamp hanging from the ceiling on a short chain: the hub's real light source.
local function ceilingLamp(position: Vector3, ceilingY: number, parent: Instance)
	local dropLength = math.max(ceilingY - position.Y, 1)
	block(
		Vector3.new(0.25, dropLength, 0.25),
		Vector3.new(position.X, position.Y + dropLength / 2, position.Z),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	).Name =
		"LampChain"

	local shade = block(Vector3.new(3.4, 1, 3.4), position + Vector3.new(0, 0.6, 0), IRON, Enum.Material.Metal, parent)
	shade.Name = "LampShade"

	local bulb = block(Vector3.new(1.6, 0.8, 1.6), position, LANTERN, Enum.Material.Neon, parent)
	bulb.Name = "LampBulb"
	bulb.CanCollide = false
	bulb.CastShadow = false
	pointLight(bulb, Config.LobbyRoom.lighting.ceilingLampRange, Config.LobbyRoom.lighting.ceilingLampBrightness, false)
end

-- A bolted enamel hazard plate: dark ground, pale diagonal bars, readable face along local +Z (the
-- same convention `textBoard` uses).
--
-- IT CARRIES NO TEXT, AND THAT IS THE POINT OF IT. The hub already has four boards a player walks up
-- to and reads; this is the opposite kind of sign — one that has to land at a glance, from across the
-- room, at whatever angle somebody happens to be walking past a hole in the floor. Diagonal bars are
-- the one warning mark that survives all of that, and they cost no localisation and oblige nobody to
-- decide what the mining company was called.
--
-- THE BAR ARITHMETIC IS WHAT KEEPS THIS FROM LOOKING BROKEN, so it is derived rather than eyeballed.
-- Parts are boxes, and a box rotated off vertical grows in BOTH axes: it reaches
--
--     sideways by  length/2 * sin(lean) + barWidth/2 * cos(lean)
--     vertically by  length/2 * cos(lean) + barWidth/2 * sin(lean)
--
-- If either exceeds the plate's half-extent the stripe visibly juts off the plate into open air, with
-- nothing behind it. The obvious cut — `height / cos(lean)`, the length whose CENTRELINE just spans
-- the plate — is the trap: it ignores the bar's own width entirely and overhangs top and bottom every
-- time. Inverting the vertical equation for length is what actually fits, and the horizontal reach is
-- then small enough that spacing bars at `width / (bars + 1)` clears the sides at both plate sizes
-- this room uses.
local HAZARD_LEAN = math.rad(32)

local function hazardPlate(cframe: CFrame, width: number, height: number, bars: number, parent: Instance)
	local plate = newPart(Vector3.new(width, height, 0.24), cframe, BOARD_BACKING, Enum.Material.Metal, parent)
	plate.Name = "HazardPlate"

	local spacing = width / (bars + 1)
	local barWidth = spacing * 0.42
	-- Solved from the vertical reach above, then held a further 2% short so the bar ends stop just
	-- inside the plate's edges instead of landing flush on them and z-fighting.
	local barLength = (height - barWidth * math.sin(HAZARD_LEAN)) / math.cos(HAZARD_LEAN) * 0.98

	for index = 1, bars do
		local offsetX = (index - (bars + 1) / 2) * spacing
		newPart(
			Vector3.new(barWidth, barLength, 0.06),
			cframe * CFrame.new(offsetX, 0, 0.15) * CFrame.Angles(0, 0, HAZARD_LEAN),
			PAINT,
			Enum.Material.SmoothPlastic,
			parent
		).Name =
			"HazardBar"
	end

	-- Four bolt heads, because a plate with no visible fixing reads as a decal on the wall.
	for _, corner in
		{
			Vector3.new(-width / 2 + 0.22, height / 2 - 0.22, 0.14),
			Vector3.new(width / 2 - 0.22, height / 2 - 0.22, 0.14),
			Vector3.new(-width / 2 + 0.22, -height / 2 + 0.22, 0.14),
			Vector3.new(width / 2 - 0.22, -height / 2 + 0.22, 0.14),
		}
	do
		local bolt =
			newPart(Vector3.new(0.16, 0.16, 0.1), cframe * CFrame.new(corner), IRON, Enum.Material.Metal, parent)
		bolt.Name = "HazardBolt"
		bolt.CanCollide = false
	end
end

-- A framed board with wrapped text, facing along the given CFrame's +Z. Returns the label so live
-- boards (party rosters, standings) can be rewritten later without rebuilding geometry.
local function textBoard(
	cframe: CFrame,
	width: number,
	height: number,
	parent: Instance,
	name: string
): (Part, SurfaceGui)
	local backing = newPart(Vector3.new(width, height, 0.4), cframe, BOARD_BACKING, Enum.Material.Wood, parent)
	backing.Name = name

	-- A timber frame around the backing; four thin bars rather than a texture.
	local frameThickness = 0.5
	for _, spec in
		{
			{ Vector3.new(width + frameThickness, frameThickness, 0.6), Vector3.new(0, height / 2, 0) },
			{ Vector3.new(width + frameThickness, frameThickness, 0.6), Vector3.new(0, -height / 2, 0) },
			{ Vector3.new(frameThickness, height, 0.6), Vector3.new(-width / 2, 0, 0) },
			{ Vector3.new(frameThickness, height, 0.6), Vector3.new(width / 2, 0, 0) },
		}
	do
		newPart(spec[1] :: Vector3, cframe * CFrame.new(spec[2] :: Vector3), TIMBER, Enum.Material.Wood, parent).Name =
			"BoardFrame"
	end

	local gui = Instance.new("SurfaceGui")
	-- `textBoard` defines its readable side as local +Z, which is the Part's Back face.
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 48
	gui.LightInfluence = 0
	gui.Parent = backing
	return backing, gui
end

-- A soft parchment plate behind a region of board text. Raw text directly on the wood backing
-- fights the material's grain and reads as dim/muddy at a distance; a plate gives it a flat, even
-- surface to sit on. Rounded (not a hard-edged box) and dark enough to still read as "the board",
-- not a slapped-on UI panel.
local function boardPanel(gui: SurfaceGui, position: UDim2, size: UDim2): Frame
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.fromRGB(12, 9, 8)
	panel.BackgroundTransparency = 0.22
	panel.BorderSizePixel = 0
	panel.ZIndex = 1
	panel.Position = position
	panel.Size = size
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 28)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 96, 66)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = panel

	return panel
end

local function boardLabel(
	gui: SurfaceGui,
	name: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	maxTextSize: number,
	bold: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.Text = ""
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.6
	label.ZIndex = 2
	label.Parent = gui
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
	return label
end

--------------------------------------------------------------------------------
-- Room shell
--------------------------------------------------------------------------------

-- Floor segments deliberately skip each elevator's footprint so the cars have an open shaft to
-- descend through instead of clipping down through a solid slab.
local function elevatorGapsAlongX(): { { min: number, max: number } }
	local room = Config.LobbyRoom
	local half = room.elevatorCarWidth / 2
	local gaps: { { min: number, max: number } } = {}
	for _, elevator in room.elevators do
		table.insert(gaps, { min = elevator.offset.X - half, max = elevator.offset.X + half })
	end
	table.sort(gaps, function(a, b)
		return a.min < b.min
	end)
	return gaps
end

local function buildFloor(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local halfW, halfD = room.roomWidth / 2, room.roomDepth / 2
	local halfCar = room.elevatorCarDepth / 2
	local bandMinZ = room.elevators[1].offset.Z - halfCar
	local bandMaxZ = room.elevators[1].offset.Z + halfCar

	local function slab(centreX: number, centreZ: number, sizeX: number, sizeZ: number, name: string)
		if sizeX <= 0.01 or sizeZ <= 0.01 then
			return
		end
		block(
			Vector3.new(sizeX, room.floorThickness, sizeZ),
			origin + Vector3.new(centreX, -room.floorThickness / 2, centreZ),
			PLANK,
			Enum.Material.WoodPlanks,
			parent
		).Name =
			name
	end

	-- Main room floor, in front of the elevator band.
	slab(0, (-halfD + bandMinZ) / 2, room.roomWidth, bandMinZ + halfD, "Floor")
	-- Behind the cars.
	slab(0, (bandMaxZ + halfD) / 2, room.roomWidth, halfD - bandMaxZ, "FloorRear")
	-- The elevator band itself, split around each shaft opening.
	local cursor = -halfW
	for _, gap in elevatorGapsAlongX() do
		slab((cursor + gap.min) / 2, (bandMinZ + bandMaxZ) / 2, gap.min - cursor, bandMaxZ - bandMinZ, "FloorBand")
		cursor = gap.max
	end
	slab((cursor + halfW) / 2, (bandMinZ + bandMaxZ) / 2, halfW - cursor, bandMaxZ - bandMinZ, "FloorBand")
end

local function buildArrivalTunnel(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local tunnel = room.tunnel
	local halfD = room.roomDepth / 2
	local centreZ = -halfD - tunnel.depth / 2
	local shellThickness = room.wallThickness

	for _, spec in
		{
			{
				Vector3.new(shellThickness, tunnel.height, tunnel.depth),
				Vector3.new(-tunnel.width / 2, tunnel.height / 2, centreZ),
			},
			{
				Vector3.new(shellThickness, tunnel.height, tunnel.depth),
				Vector3.new(tunnel.width / 2, tunnel.height / 2, centreZ),
			},
			{ Vector3.new(tunnel.width, shellThickness, tunnel.depth), Vector3.new(0, tunnel.height, centreZ) },
			{ Vector3.new(tunnel.width, shellThickness, tunnel.depth), Vector3.new(0, -shellThickness / 2, centreZ) },
		}
	do
		block(spec[1] :: Vector3, origin + (spec[2] :: Vector3), TUNNEL_BLACK, Enum.Material.Slate, parent).Name =
			"ArrivalTunnel"
	end
	block(
		Vector3.new(tunnel.width, tunnel.height, shellThickness),
		origin + Vector3.new(0, tunnel.height / 2, -halfD - tunnel.depth),
		TUNNEL_BLACK,
		Enum.Material.Slate,
		parent
	).Name =
		"ArrivalTunnelBack"

	local barrier = block(
		Vector3.new(tunnel.width, tunnel.height, shellThickness),
		origin + Vector3.new(0, tunnel.height / 2, -halfD - tunnel.barrierSetback),
		TUNNEL_BLACK,
		Enum.Material.SmoothPlastic,
		parent
	)
	barrier.Name = "ArrivalTunnelBarrier"
	barrier.Transparency = 1
	barrier.CanCollide = true

	-- One wide hazard plate bolted to the header above the portal — where a real mine puts the sign
	-- that means "past this point the rules change".
	--
	-- ABOVE the mouth rather than flanking it, and that is a placement decision rather than a spare
	-- bit of wall. The entry wall's candle run already excludes a span either side of the tunnel
	-- (`buildWallCandles`), so a plate down at eye level either fights a bracketed candle for the same
	-- studs or has to be shoved far enough out that it stops being about the doorway at all. The header
	-- is empty, unlit from below, and it is the surface a player is looking straight at while they walk
	-- out of the dark into the room.
	hazardPlate(
		CFrame.new(origin + Vector3.new(0, tunnel.height + 2.2, -halfD + shellThickness / 2 + 0.13)),
		6.4,
		1.6,
		6,
		parent
	)
end

type ExclusionSpan = {
	min: number,
	max: number,
}

local function fixtureSpan(centre: number, width: number): ExclusionSpan
	local clearance = Config.LobbyRoom.wallCandles.fixtureClearance
	return { min = centre - width / 2 - clearance, max = centre + width / 2 + clearance }
end

local function insideSpan(value: number, spans: { ExclusionSpan }): boolean
	for _, span in spans do
		if value >= span.min and value <= span.max then
			return true
		end
	end
	return false
end

-- How much of the west wall the storefront covers, so no candle is bracketed onto rock the shop is
-- standing in front of. The stall is mounted flat against that wall and turned to face the room, so
-- the run of wall it hides is its own WIDTH (local X) — the awning and posts are its widest masses —
-- laid along the wall's Z axis from `shopOffset.Z`.
local function shopWallSpan(): ExclusionSpan
	local room = Config.LobbyRoom
	local display = room.shopDisplay
	local widest = math.max(
		display.counterSize.X,
		display.counterTopSize.X,
		display.backdropSize.X,
		display.awningSize.X,
		display.postOffset.X * 2 + display.postSize.X
	)
	return fixtureSpan(room.shopOffset.Z, widest)
end

local function buildWallCandles(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local candle = room.wallCandles
	local halfW, halfD = room.roomWidth / 2, room.roomDepth / 2
	local wallFaceOffset = room.wallThickness / 2 + candle.wallInset
	local entrySpans = {
		fixtureSpan(room.welcomeSignOffset.X, room.boardWidth),
		fixtureSpan(room.howToPlayOffset.X, room.boardWidth),
		fixtureSpan(room.versionSignOffset.X, room.versionSignWidth),
		fixtureSpan(0, room.tunnel.width),
	}
	local rearSpans: { ExclusionSpan } = {}
	for _, elevator in room.elevators do
		table.insert(
			rearSpans,
			fixtureSpan(
				elevator.offset.X,
				math.max(room.elevatorCarWidth + room.rideShaftRibOutset * 2, room.elevatorBoardWidth)
			)
		)
	end
	local westSpans = { shopWallSpan() }
	local eastSpans = {
		fixtureSpan(room.leaderboardOffset.Z, room.leaderboardWidth),
		fixtureSpan(room.updateBoardOffset.Z, room.updateBoardWidth),
	}

	for x = -halfW + candle.cornerInset, halfW - candle.cornerInset, candle.spacing do
		if not insideSpan(x, entrySpans) then
			wallCandle(CFrame.new(origin + Vector3.new(x, candle.height, -halfD + wallFaceOffset)), parent)
		end
		if not insideSpan(x, rearSpans) then
			wallCandle(
				CFrame.new(origin + Vector3.new(x, candle.height, halfD - wallFaceOffset))
					* CFrame.Angles(0, math.rad(180), 0),
				parent
			)
		end
	end
	for z = -halfD + candle.cornerInset, halfD - candle.cornerInset, candle.spacing do
		if not insideSpan(z, westSpans) then
			wallCandle(
				CFrame.new(origin + Vector3.new(-halfW + wallFaceOffset, candle.height, z))
					* CFrame.Angles(0, math.rad(90), 0),
				parent
			)
		end
		if not insideSpan(z, eastSpans) then
			wallCandle(
				CFrame.new(origin + Vector3.new(halfW - wallFaceOffset, candle.height, z))
					* CFrame.Angles(0, math.rad(-90), 0),
				parent
			)
		end
	end
end

local function buildShell(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local halfW, halfD = room.roomWidth / 2, room.roomDepth / 2
	local ceilingY = room.wallHeight

	buildFloor(origin, parent)

	block(
		Vector3.new(room.roomWidth, room.wallThickness, room.roomDepth),
		origin + Vector3.new(0, ceilingY + room.wallThickness / 2, 0),
		STONE,
		Enum.Material.Slate,
		parent
	).Name =
		"Ceiling"

	local entrySideWidth = (room.roomWidth - room.tunnel.width) / 2
	local entryHeaderHeight = room.wallHeight - room.tunnel.height
	local walls = {
		{
			Vector3.new(entrySideWidth, room.wallHeight, room.wallThickness),
			Vector3.new(-(room.tunnel.width + entrySideWidth) / 2, 0, -halfD),
			"EntryWall",
		},
		{
			Vector3.new(entrySideWidth, room.wallHeight, room.wallThickness),
			Vector3.new((room.tunnel.width + entrySideWidth) / 2, 0, -halfD),
			"EntryWall",
		},
		{
			Vector3.new(room.tunnel.width, entryHeaderHeight, room.wallThickness),
			Vector3.new(0, room.tunnel.height, -halfD),
			"EntryWallHeader",
		},
		{ Vector3.new(room.roomWidth, room.wallHeight, room.wallThickness), Vector3.new(0, 0, halfD), "RearWall" },
		{ Vector3.new(room.wallThickness, room.wallHeight, room.roomDepth), Vector3.new(-halfW, 0, 0), "WallWest" },
		{ Vector3.new(room.wallThickness, room.wallHeight, room.roomDepth), Vector3.new(halfW, 0, 0), "WallEast" },
	}
	for _, wall in walls do
		block(
			wall[1] :: Vector3,
			origin
				+ (wall[2] :: Vector3)
				+ Vector3.new(
					0,
					if (wall[3] :: string) == "EntryWallHeader" then entryHeaderHeight / 2 else room.wallHeight / 2,
					0
				),
			STONE,
			Enum.Material.Rock,
			parent
		).Name =
			wall[3] :: string
	end
	buildArrivalTunnel(origin, parent)

	-- Timber ceiling supports: a cross-beam plus two legs at each spacing interval. This is what
	-- makes the space read as a mineshaft rather than a warehouse.
	--
	-- Everything the entry wall carries is mounted flush against it (z = -halfD), the same plane as the
	-- front row of these posts, and the beam grid's x-spacing lands right across the boards. Skip a
	-- post's front leg wherever it would stand in front of one of them, or in the tunnel mouth — the
	-- rear leg (and every other post) is untouched.
	--
	-- THE VERSION PLAQUE IS IN THIS LIST TOO, small as it is: at a 200-wide room the beam grid steps
	-- 16.67 studs and lands at x = 66.67, which is inside the plaque at x = 66. A post there does not
	-- merely crowd it, it stands in the same studs.
	local postHalfWidth = 0.6
	local entryFixtures = {
		{ centre = room.welcomeSignOffset.X, width = room.boardWidth },
		{ centre = room.howToPlayOffset.X, width = room.boardWidth },
		{ centre = room.versionSignOffset.X, width = room.versionSignWidth },
		{ centre = 0, width = room.tunnel.width },
	}
	local function blocksEntrySign(x: number): boolean
		for _, fixture in entryFixtures do
			if math.abs(x - fixture.centre) < fixture.width / 2 + postHalfWidth then
				return true
			end
		end
		return false
	end

	local beamCount = math.max(2, math.floor(room.roomWidth / room.beamSpacing))
	for i = 0, beamCount do
		local x = -halfW + (i / beamCount) * room.roomWidth
		block(
			Vector3.new(1.2, BEAM_DEPTH, room.roomDepth),
			origin + Vector3.new(x, ceilingY - BEAM_DEPTH / 2, 0),
			TIMBER,
			Enum.Material.Wood,
			parent
		).Name =
			"CeilingBeam"
		for _, z in { -halfD + 1.5, halfD - 1.5 } do
			if z < 0 and blocksEntrySign(x) then
				continue
			end
			block(
				Vector3.new(1.2, ceilingY, 1.2),
				origin + Vector3.new(x, ceilingY / 2, z),
				TIMBER,
				Enum.Material.Wood,
				parent
			).Name =
				"SupportPost"

			-- A KNEE BRACE from every post up to the beam it carries, always angled INTO the room —
			-- outward there is only wall, and a brace that dies into a wall braces nothing.
			--
			-- Two hundred studs of post-and-beam is the single largest thing in this room and, unbraced,
			-- it reads as furniture: right angles say "assembled", a braced angle says "engineered", and
			-- the hub's whole job is to feel like somebody's working infrastructure so that the raw rock
			-- below has something to be the opposite of.
			local inward = if z < 0 then 1 else -1
			local beamUnderside = ceilingY - BEAM_DEPTH
			newPart(
				Vector3.new(0.7, BRACE_RUN * math.sqrt(2), 0.7),
				CFrame.new(origin + Vector3.new(x, beamUnderside - BRACE_RUN / 2, z + inward * BRACE_RUN / 2))
					-- Rotating about X takes local +Y to (0, cos, sin), so a 45-degree turn signed by
					-- `inward` puts the brace's length on exactly the diagonal the two ends define.
					* CFrame.Angles(math.rad(45 * inward), 0, 0),
				TIMBER,
				Enum.Material.Wood,
				parent
			).Name =
				"KneeBrace"
			-- The iron gusset at the head of the brace. One small part, and it is what stops the diagonal
			-- reading as a plank leaning on the ceiling.
			block(
				Vector3.new(0.9, 0.5, 1.4),
				origin + Vector3.new(x, beamUnderside - 0.25, z + inward * (BRACE_RUN - 0.4)),
				IRON_DARK,
				Enum.Material.Metal,
				parent
			).Name =
				"BraceGusset"
		end
	end

	-- LAGGING BOARDS nailed across the underside of the beams, bay by bay, the way a gallery roof is
	-- actually boarded out behind its supports.
	--
	-- ONLY EVERY OTHER BAY, and phase-shifted between them. A board in every bay at a fixed spacing is
	-- a manufactured slatted ceiling — the one thing a hand-cut mine roof never looks like — whereas a
	-- patchy, offset set reads as somewhere that has been repaired in pieces over years. It is also the
	-- cheapest available fix for the fact that the ceiling above all this is one flat slab.
	--
	-- Deterministic from the loop indices, with no random source anywhere near it: this hub is built
	-- once for the server's lifetime and every player has to be standing in the same room.
	local laggingY = ceilingY - BEAM_DEPTH - 0.22
	for bay = 0, beamCount - 1, 2 do
		local left = -halfW + (bay / beamCount) * room.roomWidth
		local right = -halfW + ((bay + 1) / beamCount) * room.roomWidth
		for board = 0, 3 do
			local along = (board + (bay % 3) * 0.28) / 3.6
			block(
				Vector3.new(right - left - 1.2, 0.4, 1.5),
				origin + Vector3.new((left + right) / 2, laggingY, -halfD + 14 + along * (room.roomDepth - 28)),
				TIMBER_DARK,
				Enum.Material.Wood,
				parent
			).Name =
				"LaggingBoard"
		end
	end

	-- The arrival track ends inside the room: the cart travelled +Z out of the black shaft.
	local railLength = room.rails.endZ - room.rails.startZ
	local railCentreZ = (room.rails.startZ + room.rails.endZ) / 2
	for _, railX in { -room.rails.gauge / 2, room.rails.gauge / 2 } do
		block(
			Vector3.new(room.rails.railSize.X, room.rails.railSize.Y, railLength),
			origin + Vector3.new(railX, room.rails.railSize.Y / 2, railCentreZ),
			RAIL,
			Enum.Material.Metal,
			parent
		).Name =
			"Rail"
	end
	local sleeperCount = math.floor(railLength / room.railSpacing)
	for i = 0, sleeperCount do
		local z = room.rails.startZ + i * room.railSpacing
		block(
			room.rails.sleeperSize,
			origin + Vector3.new(0, room.rails.sleeperSize.Y / 2, z),
			TIMBER_DARK,
			Enum.Material.Wood,
			parent
		).Name =
			"RailSleeper"
	end
	block(room.rails.stopperSize, origin + room.rails.stopperOffset, TIMBER_DARK, Enum.Material.Wood, parent).Name =
		"CartStopper"

	-- Nine ceiling lamps in a 3x3 grid remain the room's main light. Wall candles add warmth without
	-- replacing them. The grid reaches close enough to every corner (with `lighting.ceilingLampRange`
	-- covering the rest of the distance) that no stretch of floor is left lit by candles alone.
	for _, x in { -halfW * 0.6, 0, halfW * 0.6 } do
		for _, z in { -halfD * 0.78, 0, halfD * 0.6 } do
			ceilingLamp(origin + Vector3.new(x, ceilingY - 5, z), origin.Y + ceilingY, parent)
		end
	end
	buildWallCandles(origin, parent)
end

-- Scattered crates and barrels: cheap, readable dressing that gives the space scale and stops the
-- floor reading as an empty plane.
local function mineCart(cframe: CFrame, parent: Instance, carriesWax: boolean)
	local cart = Config.LobbyRoom.mineCarts
	newPart(cart.floorSize, cframe, IRON, Enum.Material.Metal, parent).Name = "CartFloor"
	local halfW, halfD = cart.floorSize.X / 2, cart.floorSize.Z / 2
	for _, spec in
		{
			{
				Vector3.new(cart.floorSize.X, cart.wallHeight, cart.wallThickness),
				Vector3.new(0, cart.wallHeight / 2, halfD - cart.wallThickness / 2),
			},
			{
				Vector3.new(cart.floorSize.X, cart.wallHeight, cart.wallThickness),
				Vector3.new(0, cart.wallHeight / 2, -halfD + cart.wallThickness / 2),
			},
			{
				Vector3.new(cart.wallThickness, cart.wallHeight, cart.floorSize.Z),
				Vector3.new(halfW - cart.wallThickness / 2, cart.wallHeight / 2, 0),
			},
			{
				Vector3.new(cart.wallThickness, cart.wallHeight, cart.floorSize.Z),
				Vector3.new(-halfW + cart.wallThickness / 2, cart.wallHeight / 2, 0),
			},
		}
	do
		newPart(spec[1] :: Vector3, cframe * CFrame.new(spec[2] :: Vector3), IRON, Enum.Material.Metal, parent).Name =
			"CartWall"
	end
	if carriesWax then
		for index, offset in cart.waxHeapOffsets do
			local lump = newPart(
				cart.waxHeapSizes[index],
				cframe * CFrame.new(offset),
				if index % 2 == 0 then WAX_DEEP else WAX_BODY,
				-- A pale, matte-ish finish rather than SmoothPlastic: raw wax should read as a soft
				-- heap, not a shiny metallic bead catching the lamp's warm highlight like gold.
				Enum.Material.Sand,
				parent
			)
			lump.Name = "RawWax"
			lump.Shape = Enum.PartType.Ball
			lump.CanCollide = false
		end
	end
end

-- A low heap of broken country rock: what comes up the shaft that ISN'T wax, tipped where somebody
-- last emptied a barrow. Overlapping angular lumps rather than one dome — a dome reads as sand, and
-- this has to read as stone that was broken by somebody.
local function spoilHeap(centre: Vector3, extent: number, parent: Instance)
	for index = 0, 5 do
		local angle = index * 1.05
		local radius = extent * (0.12 + (index % 3) * 0.24)
		local size = extent * (0.72 - (index % 3) * 0.14)
		local lump = newPart(
			Vector3.new(size, size * 0.5, size * 0.82),
			CFrame.new(centre + Vector3.new(math.cos(angle) * radius, size * 0.18, math.sin(angle) * radius))
				* CFrame.Angles(0.2 + index * 0.11, angle * 1.7, 0.14 * index),
			if index % 2 == 0 then SPOIL else SPOIL_DARK,
			Enum.Material.Slate,
			parent
		)
		lump.Name = "SpoilHeap"
		-- Ankle height in a room people sprint and jump through. Collidable, this is a trip hazard the
		-- player never sees coming; that trade is never worth a piece of dressing.
		lump.CanCollide = false
	end
end

-- A chain hung off a ceiling beam with a shackle on the end, reaching nowhere. The hub's roof is
-- twenty-eight studs of empty air above head height, so anything that occupies the middle of it gives
-- the room its real scale back — you cannot judge a ceiling you have nothing to measure against.
local function hangingChain(top: Vector3, length: number, parent: Instance)
	block(Vector3.new(0.22, length, 0.22), top - Vector3.new(0, length / 2, 0), IRON_DARK, Enum.Material.Metal, parent).Name =
		"HangingChain"
	local shackle = newPart(
		Vector3.new(0.5, 0.8, 0.5),
		CFrame.new(top - Vector3.new(0, length + 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		IRON,
		Enum.Material.Metal,
		parent
	)
	shackle.Name = "ChainHook"
	shackle.Shape = Enum.PartType.Cylinder
	shackle.CanCollide = false
end

-- A pick and a shovel stood against whatever is behind them. `at` is the foot of the pair, and its
-- LookVector is the direction they lean AWAY from — so callers point it at the wall or crate the
-- tools are resting on.
--
-- Built to the same construction as the caves' `MineRelics` tool rack (a blade pair crossing a haft,
-- a plate for the shovel) so the two rooms' equipment reads as one company's kit, just one set still
-- in service and the other left underground.
local function leaningTools(at: CFrame, parent: Instance)
	local pick = at * CFrame.new(-0.5, 0, 0) * CFrame.Angles(math.rad(-13), 0, 0)
	newPart(Vector3.new(0.17, 3.4, 0.17), pick * CFrame.new(0, 1.7, 0), TIMBER, Enum.Material.Wood, parent).Name =
		"PickHaft"
	for _, side in { -1, 1 } do
		newPart(
			Vector3.new(0.15, 0.18, 1.2),
			pick * CFrame.new(0, 3.3, side * 0.58) * CFrame.Angles(math.rad(side * 8), 0, 0),
			IRON,
			Enum.Material.Metal,
			parent
		).Name =
			"PickBlade"
	end

	local shovel = at * CFrame.new(0.55, 0, 0.12) * CFrame.Angles(math.rad(-9), math.rad(11), 0)
	newPart(Vector3.new(0.15, 3, 0.15), shovel * CFrame.new(0, 1.75, 0), TIMBER, Enum.Material.Wood, parent).Name =
		"ShovelHaft"
	newPart(
		Vector3.new(0.66, 0.78, 0.11),
		shovel * CFrame.new(0, 0.36, 0) * CFrame.Angles(math.rad(7), 0, 0),
		RAIL,
		Enum.Material.Metal,
		parent
	).Name =
		"ShovelBlade"
end

-- A banded pail. Three parts, and the band is the one that does the work: without it the body is a
-- barrel at the wrong scale rather than a bucket.
local function bucket(centre: Vector3, parent: Instance)
	local body = newPart(
		Vector3.new(1.3, 1.1, 1.1),
		CFrame.new(centre + Vector3.new(0, 0.65, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		IRON,
		Enum.Material.Metal,
		parent
	)
	body.Name = "Bucket"
	body.Shape = Enum.PartType.Cylinder
	local rim = newPart(
		Vector3.new(0.16, 1.2, 1.2),
		CFrame.new(centre + Vector3.new(0, 1.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	)
	rim.Name = "BucketRim"
	rim.Shape = Enum.PartType.Cylinder
	rim.CanCollide = false
	local handle = newPart(
		Vector3.new(0.09, 0.09, 1.3),
		CFrame.new(centre + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	)
	handle.Name = "BucketHandle"
	handle.Shape = Enum.PartType.Cylinder
	handle.CanCollide = false
end

local function buildProps(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local halfW, halfD = room.roomWidth / 2, room.roomDepth / 2

	local crates = {
		{ Vector3.new(4, 4, 4), Vector3.new(-halfW + 10, 2, -halfD + 14) },
		{ Vector3.new(3, 3, 3), Vector3.new(-halfW + 15, 1.5, -halfD + 11) },
		{ Vector3.new(4, 4, 4), Vector3.new(-halfW + 11, 6, -halfD + 14) },
		{ Vector3.new(4, 4, 4), Vector3.new(halfW - 12, 2, -halfD + 16) },
		{ Vector3.new(3, 3, 3), Vector3.new(halfW - 17, 1.5, -halfD + 13) },
		{ Vector3.new(5, 4, 4), Vector3.new(halfW - 14, 2, halfD - 30) },
		{ Vector3.new(4, 4, 4), Vector3.new(-halfW + 13, 2, halfD - 34) },
	}
	for _, crate in crates do
		block(crate[1] :: Vector3, origin + (crate[2] :: Vector3), TIMBER, Enum.Material.WoodPlanks, parent).Name =
			"Crate"
	end

	for _, spot in { Vector3.new(-halfW + 20, 0, -halfD + 20), Vector3.new(halfW - 22, 0, halfD - 36) } do
		local barrel =
			block(Vector3.new(3, 4, 3), origin + spot + Vector3.new(0, 2, 0), TIMBER_DARK, Enum.Material.Wood, parent)
		barrel.Shape = Enum.PartType.Cylinder
		barrel.CFrame = CFrame.new(origin + spot + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		barrel.Name = "Barrel"
	end

	-- The arrival cart sits on the track; three loaded carts dress quiet side pockets.
	mineCart(CFrame.new(origin + room.mineCarts.mainOffset), parent, false)
	for _, cart in room.mineCarts.waxCartOffsets do
		mineCart(CFrame.new(origin + cart.offset) * CFrame.Angles(0, math.rad(cart.yawDegrees), 0), parent, true)
	end

	-- WHAT A SHIFT LEAVES BEHIND. Everything below is placed against something the room already has —
	-- spoil beside a cart that carried it, tools against a crate somebody set them down on — because
	-- dressing dropped in open floor reads as scattered set decoration, and dressing that is leaning on
	-- something reads as having been PUT there. Same parts either way; the difference is the whole
	-- effect.
	--
	-- ALL OF IT KEPT OUT OF THE EAST AISLE (x 25-90, z -5 to 25), which is the parkour course's run-up
	-- and landing band. That route is deliberately the one fixture in this hub with nothing built into
	-- the volume a player jumps through (see `buildParkour`), and floor clutter under it would undo
	-- that from the outside.
	for _, heap in
		{
			-- Tipped out beside each loaded wax cart, and at the buffer end of the arrival track.
			{ Vector3.new(-66, 0, 24), 4.4 },
			{ Vector3.new(66, 0, 36), 3.8 },
			{ Vector3.new(7, 0, -23), 3.2 },
		}
	do
		spoilHeap(origin + (heap[1] :: Vector3), heap[2] :: number, parent)
	end

	-- Against the two crate stacks the room already has, turned so the tools lean INTO the crates.
	leaningTools(
		CFrame.new(origin + Vector3.new(-halfW + 17, 0, -halfD + 17)) * CFrame.Angles(0, math.rad(200), 0),
		parent
	)
	leaningTools(
		CFrame.new(origin + Vector3.new(halfW - 18, 0, halfD - 28)) * CFrame.Angles(0, math.rad(20), 0),
		parent
	)

	bucket(origin + Vector3.new(-halfW + 24, 0, -halfD + 26), parent)
	bucket(origin + Vector3.new(halfW - 26, 0, halfD - 41), parent)

	-- Four chains off the beam grid, at bays well clear of both the ceiling-lamp positions and the
	-- parkour aisle. The drop lengths differ on purpose: four identical chains read as a fixture, four
	-- unequal ones read as leftovers.
	local beamUnderside = room.wallHeight - BEAM_DEPTH
	for _, chain in
		{
			{ Vector3.new(-33.3, beamUnderside, -30), 7.5 },
			{ Vector3.new(33.3, beamUnderside, -34), 5.2 },
			{ Vector3.new(-66.7, beamUnderside, 12), 9 },
			{ Vector3.new(66.7, beamUnderside, 52), 6.4 },
		}
	do
		hangingChain(origin + (chain[1] :: Vector3), chain[2] :: number, parent)
	end
end

-- One platform. `surface` is the point you STAND ON — its centre and its top face — so the caller only
-- ever reasons about walkable heights, and this decides how far each style hangs below that. Returns
-- the underside, which is where the post has to stop.
--
-- Every branch is built out of a fixture the room already has: `buildShell` lays the arrival track,
-- `buildProps` stacks the crates and stands the barrels, and the ironwork is the same RAIL and IRON
-- everything else here is braced with. Nothing in this course is a shape invented for it.
local function parkourLanding(style: string, surface: Vector3, size: Vector2, parent: Instance): number
	local course = Config.LobbyRoom.parkour

	if style == "Crate" then
		block(
			Vector3.new(size.X, course.crateDepth, size.Y),
			surface - Vector3.new(0, course.crateDepth / 2, 0),
			TIMBER,
			Enum.Material.WoodPlanks,
			parent
		).Name =
			"ParkourCrate"
		return surface.Y - course.crateDepth
	elseif style == "Barrel" then
		-- A Roblox cylinder's round faces run along its own local X, so the barrel is stood on end with
		-- a 90-degree roll and its Size authored (height, diameter, diameter) to match.
		local height = course.barrelHeight
		local diameter = size.X
		local upright = CFrame.new(surface - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local body = newPart(Vector3.new(height, diameter, diameter), upright, TIMBER_DARK, Enum.Material.Wood, parent)
		body.Name = "ParkourBarrel"
		body.Shape = Enum.PartType.Cylinder
		-- Two iron hoops, proud of the staves and NOT collidable: a player who catches the rim should
		-- roll off the barrel, not off a hoop a tenth of a stud wide that they never saw.
		for _, offset in { -height / 4, height / 4 } do
			local hoop = newPart(
				Vector3.new(
					course.barrelHoopThickness,
					diameter + course.barrelHoopOutset,
					diameter + course.barrelHoopOutset
				),
				upright * CFrame.new(offset, 0, 0),
				RAIL,
				Enum.Material.Metal,
				parent
			)
			hoop.Name = "ParkourBarrelHoop"
			hoop.Shape = Enum.PartType.Cylinder
			hoop.CanCollide = false
		end
		return surface.Y - height
	elseif style == "Girder" then
		block(
			Vector3.new(size.X, course.girderThickness, size.Y),
			surface - Vector3.new(0, course.girderThickness / 2, 0),
			IRON,
			Enum.Material.Metal,
			parent
		).Name =
			"ParkourGirder"
		return surface.Y - course.girderThickness
	elseif style == "Track" then
		-- Sleepers and rail on a plank bed. The bed carries you; the sleepers and rails sit proud of it,
		-- which is what makes crossing this read as walking a length of track rather than a grey slab.
		block(
			Vector3.new(size.X, course.trackThickness, size.Y),
			surface - Vector3.new(0, course.trackThickness / 2, 0),
			TIMBER_DARK,
			Enum.Material.Wood,
			parent
		).Name =
			"ParkourTrackBed"
		local sleeperSpan = math.min(course.sleeperSize.Z, size.Y)
		local sleeperCount = math.max(1, math.floor(size.X / course.sleeperSpacing))
		for index = 0, sleeperCount do
			local along = -size.X / 2 + (index / sleeperCount) * size.X
			block(
				Vector3.new(course.sleeperSize.X, course.sleeperSize.Y, sleeperSpan),
				surface + Vector3.new(along, course.sleeperSize.Y / 2, 0),
				TIMBER,
				Enum.Material.Wood,
				parent
			).Name =
				"ParkourSleeper"
		end
		for _, gauge in { -course.railGauge / 2, course.railGauge / 2 } do
			block(
				Vector3.new(size.X, course.railSize.Y, course.railSize.X),
				surface + Vector3.new(0, course.sleeperSize.Y + course.railSize.Y / 2, gauge),
				RAIL,
				Enum.Material.Metal,
				parent
			).Name =
				"ParkourRail"
		end
		return surface.Y - course.trackThickness
	end

	local thickness = if style == "Deck" then course.deckThickness else course.plankThickness
	block(
		Vector3.new(size.X, thickness, size.Y),
		surface - Vector3.new(0, thickness / 2, 0),
		PLANK,
		Enum.Material.WoodPlanks,
		parent
	).Name = if style
			== "Deck"
		then "ParkourDeck"
		else "ParkourPlank"
	return surface.Y - thickness
end

-- What the summit is FOR: a lamp on a post and somebody's spilled wax. Nothing counts it and there is
-- no way down but to jump off, which is the whole ceremony.
local function buildParkourSummit(deckSurface: Vector3, parent: Instance)
	local course = Config.LobbyRoom.parkour

	for _, offset in course.summitWaxOffsets do
		local lump = block(
			course.summitWaxSize,
			deckSurface + offset + Vector3.new(0, course.summitWaxSize.Y / 2, 0),
			WAX_BODY,
			Enum.Material.Sand,
			parent
		)
		lump.Name = "ParkourSummitWax"
		lump.Shape = Enum.PartType.Ball
		lump.CanCollide = false
	end

	local foot = deckSurface + course.lampOffset
	block(
		Vector3.new(0.4, course.lampPostHeight, 0.4),
		foot + Vector3.new(0, course.lampPostHeight / 2, 0),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	).Name =
		"ParkourLampPost"
	local shadeY = foot.Y + course.lampPostHeight
	block(
		course.lampShadeSize,
		Vector3.new(foot.X, shadeY + course.lampShadeSize.Y / 2, foot.Z),
		IRON,
		Enum.Material.Metal,
		parent
	).Name =
		"ParkourLampShade"
	local bulb = block(
		course.lampBulbSize,
		Vector3.new(foot.X, shadeY - course.lampBulbSize.Y / 2, foot.Z),
		LANTERN,
		Enum.Material.Neon,
		parent
	)
	bulb.Name = "ParkourLampBulb"
	bulb.CanCollide = false
	bulb.CastShadow = false
	pointLight(bulb, course.lampRange, course.lampBrightness, false)
end

-- A line of platforms up the east aisle, and DELIBERATELY INERT: no prompt, no tag, no attribute, no
-- Touched connection and nothing for any service to find. Everything else in this hub is geometry some
-- system elsewhere reaches for by name; this is the one fixture that is only geometry, because the
-- moment anything can observe a player reaching the top, somebody will want it to pay out.
--
-- ONE POST PER PLATFORM AND NOTHING ELSE. No frame, no bracing and nothing spanning between them: the
-- volume a player is jumping through has to stay empty, and every previous attempt at making this look
-- more built made it read as a thicket with the route lost inside it.
-- `Config.LobbyRoom.parkour` explains the layout; Tests/LobbyParkourTests re-derives that it is
-- climbable and that no platform can be skipped.
local function buildParkour(origin: Vector3, parent: Instance)
	local course = Config.LobbyRoom.parkour
	local base = origin + course.originOffset

	for index, step in course.steps do
		local surface = Vector3.new(base.X + step.offset.X, base.Y + step.offset.Y, base.Z + step.offset.Z)
		local undersideY = parkourLanding(step.style, surface, step.size, parent)

		local postHeight = undersideY - origin.Y
		if postHeight > 0.01 then
			block(
				Vector3.new(course.postThickness, postHeight, course.postThickness),
				Vector3.new(surface.X, origin.Y + postHeight / 2, surface.Z),
				TIMBER,
				Enum.Material.Wood,
				parent
			).Name =
				"ParkourPost"
			-- An iron collar under the platform and a plate at the floor. Two small parts, and between
			-- them they are what stop a post reading as a stick with a board balanced on it.
			block(
				Vector3.new(course.postThickness + 0.3, course.postCollarHeight, course.postThickness + 0.3),
				Vector3.new(surface.X, undersideY - course.postCollarHeight / 2, surface.Z),
				IRON_DARK,
				Enum.Material.Metal,
				parent
			).Name =
				"ParkourPostCollar"
			block(
				course.postBaseSize,
				Vector3.new(surface.X, origin.Y + course.postBaseSize.Y / 2, surface.Z),
				TIMBER_DARK,
				Enum.Material.Wood,
				parent
			).Name =
				"ParkourPostBase"
		end

		-- A candle every few posts. The hub's ceiling lamps are twenty-five studs up and flatten this
		-- whole structure; the route only reads as a route because it is picked out in flame.
		local candleY = undersideY - course.candleDropBelowLanding
		if index % course.candleEveryStep == 0 and candleY - origin.Y > course.candleMinimumHeight then
			wallCandle(
				CFrame.new(Vector3.new(surface.X, candleY, surface.Z))
					* CFrame.Angles(0, math.rad(course.candleYawDegrees), 0)
					* CFrame.new(0, 0, course.postThickness / 2),
				parent
			)
		end

		if index == #course.steps then
			buildParkourSummit(surface, parent)
		end
	end
end

--------------------------------------------------------------------------------
-- Shop, signage, standings
--------------------------------------------------------------------------------

local function validTreePosition(position: Vector2): boolean
	return position.X == position.X
		and position.Y == position.Y
		and math.abs(position.X) < math.huge
		and math.abs(position.Y) < math.huge
end

-- Config owns the authored graph layout. The fallback keeps a malformed or temporarily older row
-- visible without inventing a gameplay dependency: it is only a compact presentation grid.
local function logicalTreePosition(node: Interfaces.LampNode, index: number): Vector2
	local position = node.treePosition
	if validTreePosition(position) then
		return position
	end
	local fallbackColumns = 4
	local zeroIndex = index - 1
	return Vector2.new(zeroIndex % fallbackColumns, math.floor(zeroIndex / fallbackColumns))
end

-- One node's physical lamp on the storefront schematic. `offset` is in the STALL's frame, not the
-- world: `base` carries the storefront's position and facing, so the socket plate lands behind the
-- housing whichever wall the shop is hung on.
--
-- THE TAG AND THE ATTRIBUTE ARE THE WHOLE POINT OF THIS FUNCTION. client/LampNetworkController finds
-- every housing by `LobbyVisualProtocol.lampHousingTag` and reads which node it is from the
-- `lampNodeId` attribute, then lights only the ones the viewer owns. Drop either and the geometry
-- still builds, still looks right, and every purchase in the game silently stops paying off.
local function buildShopLampHousing(base: CFrame, offset: Vector3, node: Interfaces.LampNode, parent: Instance)
	local room = Config.LobbyRoom
	local size = room.lampHousingSize

	local socket = newPart(
		Vector3.new(size.X + 0.5, size.Y + 0.5, 0.22),
		base * CFrame.new(offset - Vector3.new(0, 0, size.Z / 2 + 0.12)),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	)
	socket.Name = "LampSocket"
	socket.CanCollide = false
	socket.CanQuery = false
	socket.CastShadow = false

	local housing = newPart(size, base * CFrame.new(offset), IRON, Enum.Material.Metal, parent)
	housing.Name = "LampHousing"
	housing.Transparency = room.lampHousingTransparency
	housing.CanCollide = false
	housing.CanQuery = false
	housing.CastShadow = false
	housing:SetAttribute(LobbyVisualProtocol.attributes.lampNodeId, node.id)
	CollectionService:AddTag(housing, LobbyVisualProtocol.lampHousingTag)

	local flame = newPart(
		Vector3.new(size.X * 0.36, size.Y * 0.4, size.Z * 0.36),
		base * CFrame.new(offset),
		LANTERN,
		Enum.Material.Neon,
		housing
	)
	flame.Name = "LampFlame"
	flame.Transparency = 1
	flame.CanCollide = false
	flame.CanQuery = false
	flame.CastShadow = false

	local light = Instance.new("PointLight")
	light.Name = "LampLight"
	light.Color = LANTERN
	light.Range = room.lampLitRange
	light.Brightness = room.lampLitBrightness
	light.Shadows = false
	light.Enabled = false
	light.Parent = housing
end

local function buildSchematicConduit(
	fromPosition: Vector3,
	toPosition: Vector3,
	optionalBranch: boolean,
	parent: Instance
)
	local thickness = Config.LobbyRoom.shopDisplay.schematicConduitThickness
	local delta = toPosition - fromPosition
	local length = delta.Magnitude
	if length <= 0.01 then
		return
	end
	local conduit = newPart(
		Vector3.new(thickness, thickness, length),
		CFrame.lookAt((fromPosition + toPosition) / 2, toPosition),
		if optionalBranch then RAIL else BRASS,
		Enum.Material.Metal,
		parent
	)
	conduit.Name = if optionalBranch then "LampBranchConduit" else "LampConduit"
	conduit.CanCollide = false
	conduit.CanQuery = false
	conduit.CastShadow = false
end

-- `base` is the storefront's own frame (see `shopBaseCFrame`); every position computed below is a
-- LOCAL offset in that frame and only becomes world space through `base`. That is what lets the
-- whole schematic — backing, frame, conduits and housings — turn with the stall onto a side wall.
local function buildShopSchematic(base: CFrame, parent: Instance)
	local room = Config.LobbyRoom
	local display = room.shopDisplay
	local nodes = Interfaces.LampNetwork.list()
	if not Interfaces.LampNetwork.isEnabled() or #nodes == 0 then
		return
	end

	local backingCenter = display.schematicOffset
	local backing = newPart(
		Vector3.new(display.schematicSize.X, display.schematicSize.Y, display.schematicBackingDepth),
		base * CFrame.new(backingCenter),
		BOARD_BACKING,
		Enum.Material.Metal,
		parent
	)
	backing.Name = "LampNetworkSchematic"

	local frameThickness = display.schematicFrameThickness
	local frameDepth = display.schematicBackingDepth + 0.14
	for _, spec in
		{
			{
				Vector3.new(display.schematicSize.X + frameThickness, frameThickness, frameDepth),
				Vector3.new(0, display.schematicSize.Y / 2, 0),
			},
			{
				Vector3.new(display.schematicSize.X + frameThickness, frameThickness, frameDepth),
				Vector3.new(0, -display.schematicSize.Y / 2, 0),
			},
			{
				Vector3.new(frameThickness, display.schematicSize.Y, frameDepth),
				Vector3.new(-display.schematicSize.X / 2, 0, 0),
			},
			{
				Vector3.new(frameThickness, display.schematicSize.Y, frameDepth),
				Vector3.new(display.schematicSize.X / 2, 0, 0),
			},
		}
	do
		local frame = newPart(spec[1], base * CFrame.new(backingCenter + spec[2]), TIMBER, Enum.Material.Wood, parent)
		frame.Name = "LampSchematicFrame"
	end

	local logicalById: { [string]: Vector2 } = {}
	local minimum = Vector2.new(math.huge, math.huge)
	local maximum = Vector2.new(-math.huge, -math.huge)
	for index, node in nodes do
		local logical = logicalTreePosition(node, index)
		logicalById[node.id] = logical
		minimum = Vector2.new(math.min(minimum.X, logical.X), math.min(minimum.Y, logical.Y))
		maximum = Vector2.new(math.max(maximum.X, logical.X), math.max(maximum.Y, logical.Y))
	end

	local usableWidth = math.max(0, display.schematicSize.X - display.schematicNodeInset.X * 2)
	local usableHeight = math.max(0, display.schematicSize.Y - display.schematicNodeInset.Y * 2)
	local logicalWidth = maximum.X - minimum.X
	local logicalHeight = maximum.Y - minimum.Y
	-- Both are PROUD of the backing, toward the shopper (local +Z), so the lamps sit on the schematic
	-- rather than inside it and every line still passes behind its endpoint housings.
	local housingZ = backingCenter.Z
		+ display.schematicBackingDepth / 2
		+ room.lampHousingSize.Z / 2
		+ display.schematicHousingDepthOffset
	local conduitZ = backingCenter.Z + display.schematicBackingDepth / 2 + frameDepth / 2
	local localById: { [string]: Vector3 } = {}

	for _, node in nodes do
		local logical = logicalById[node.id]
		local xAlpha = if logicalWidth > 0 then (logical.X - minimum.X) / logicalWidth else 0.5
		local yAlpha = if logicalHeight > 0 then (logical.Y - minimum.Y) / logicalHeight else 0.5
		localById[node.id] = Vector3.new(
			backingCenter.X - usableWidth / 2 + usableWidth * xAlpha,
			backingCenter.Y + usableHeight / 2 - usableHeight * yAlpha,
			housingZ
		)
	end

	-- Lay the whole graph down first so every line visibly passes behind its endpoint housings.
	--
	-- `buildSchematicConduit` works in WORLD points (it aims itself with CFrame.lookAt), so each end
	-- is pushed through `base` here rather than the function being taught about the stall's frame.
	local function conduitPoint(offset: Vector3): Vector3
		return base:PointToWorldSpace(Vector3.new(offset.X, offset.Y, conduitZ))
	end
	for _, node in nodes do
		local toPosition = localById[node.id]
		for _, requiredId in node.requires do
			local fromPosition = localById[requiredId]
			if fromPosition ~= nil then
				buildSchematicConduit(conduitPoint(fromPosition), conduitPoint(toPosition), false, parent)
			end
		end
		for _, requiredId in node.requiresAny do
			local fromPosition = localById[requiredId]
			if fromPosition ~= nil then
				buildSchematicConduit(conduitPoint(fromPosition), conduitPoint(toPosition), true, parent)
			end
		end
	end
	for _, node in nodes do
		buildShopLampHousing(base, localById[node.id], node, parent)
	end
end

-- THE STOREFRONT IS PLACED BY CFRAME, NOT BY ADDING VECTORS. Everything here used to be
-- `position + offset`, which silently hard-wires the stall to the world axes: the counter's width
-- had to run along X and its depth along Z, so the shop could only ever stand in open floor facing
-- -Z. `base` carries both where the stall is and which way it looks, and every part below is placed
-- through it, so hanging the shop on the west wall is `shopFacingYaw` and nothing else.
local function shopBaseCFrame(origin: Vector3): CFrame
	local room = Config.LobbyRoom
	return CFrame.new(origin + room.shopOffset) * CFrame.Angles(0, math.rad(room.shopFacingYaw), 0)
end

local function buildShop(origin: Vector3, parent: Instance): ProximityPrompt
	local room = Config.LobbyRoom
	local display = room.shopDisplay
	local base = shopBaseCFrame(origin)

	local counter = newPart(
		display.counterSize,
		base * CFrame.new(0, display.counterSize.Y / 2, 0),
		TIMBER,
		Enum.Material.Wood,
		parent
	)
	counter.Name = "ShopCounter"
	newPart(
		display.counterTopSize,
		base * CFrame.new(0, display.counterSize.Y + display.counterTopSize.Y / 2, 0),
		PLANK,
		Enum.Material.Wood,
		parent
	).Name =
		"ShopCounterTop"
	newPart(display.backdropSize, base * CFrame.new(display.backdropOffset), PLANK, Enum.Material.WoodPlanks, parent).Name =
		"ShopBackdrop"
	for _, direction in { -1, 1 } do
		local offset = Vector3.new(display.postOffset.X * direction, display.postOffset.Y, display.postOffset.Z)
		newPart(display.postSize, base * CFrame.new(offset), TIMBER_DARK, Enum.Material.Wood, parent).Name = "ShopPost"
	end
	newPart(display.awningSize, base * CFrame.new(display.awningOffset), TIMBER, Enum.Material.Wood, parent).Name =
		"ShopAwning"

	-- NO 180-DEGREE FLIP ANY MORE, and that is not an oversight. `textBoard` reads its own local +Z as
	-- the readable face, and the stall's local +Z is now the way it faces, so the sign is simply
	-- placed in the stall's frame. Because `base` is a pure rotation about Y away from the entry-wall
	-- boards, the text renders exactly as theirs does — no mirroring, no back-to-front reading.
	local _, gui =
		textBoard(base * CFrame.new(display.signOffset), display.signWidth, display.signHeight, parent, "ShopSign")
	local title = boardLabel(gui, "Title", UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.92, 0.9), GOLD, 64, true)
	title.Text = string.upper(room.shopObjectText)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center

	buildShopSchematic(base, parent)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = room.shopPromptText
	prompt.ObjectText = room.shopObjectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = room.shopPromptRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	return prompt
end

-- Reads live from Config.Feel so signage can never drift from the real keybinds.
-- BOTH PLATFORMS, ONE ROW PER ACTION. The hub is shared by mouse and touch players and the board
-- cannot know which is reading it, so it names the action once and gives both bindings beside it.
--
-- RETURNED AS THREE PARALLEL COLUMNS, not one pre-spaced string. The board font is proportional, so
-- padding names out with spaces lines up nothing; three labels drawn at one fixed size do, and they
-- stay aligned whatever the bindings are renamed to.
--
-- Tool keys are read live from Config.Feel so signage can never drift from the real bindings.
local function controlRows(): ({ string }, { string }, { string })
	local actions = { "" }
	local keys = { "KEY" }
	local touch = { "TOUCH" }
	for _, tool in Config.Feel.controls.tools do
		table.insert(actions, string.upper(tool.toolId))
		table.insert(keys, tool.keyLabel)
		-- Every tool row carries a `touchOrder`, which is precisely what puts it on screen as a button
		-- in the touch cluster (client/TouchControls) for a touch player.
		table.insert(touch, "BUTTON")
	end
	-- Neither of the last two is a Config.Feel row, so both are written out. Brightness is the scroll
	-- wheel in client/DialController and a dragged slider on touch; mining is MouseButton1 in
	-- client/MiningController. They are listed because Raw Wax is the only currency in the game
	-- (Config/Extraction) and a player who never finds the seam swing never earns anything.
	table.insert(actions, "BRIGHTNESS")
	table.insert(keys, "WHEEL")
	table.insert(touch, "SLIDER")
	table.insert(actions, "MINE")
	table.insert(keys, "CLICK")
	table.insert(touch, "TAP")
	return actions, keys, touch
end

-- A board label at a FIXED size rather than TextScaled. Used only by the controls table, where three
-- separate labels have to share one baseline grid: TextScaled would let each column pick its own
-- size from its own longest word, and the rows would stop lining up.
local function boardColumn(
	gui: SurfaceGui,
	name: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	fixedSize: number,
	bold: boolean
): TextLabel
	local label = boardLabel(gui, name, position, size, color, fixedSize, bold)
	label.TextScaled = false
	label.TextWrapped = false
	label.TextSize = fixedSize
	return label
end

local function buildHowToPlay(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local _, gui = textBoard(
		CFrame.new(origin + room.howToPlayOffset),
		room.boardWidth,
		room.boardHeight,
		parent,
		"HowToPlayBoard"
	)

	-- Two plates mirror the two-column layout below: rules on the left, controls on the right.
	-- The split is deliberately lopsided. The controls table is a fixed six rows however wide the
	-- board gets, so width spent on it is width the rules cannot use, and the rules are TextScaled:
	-- every column point handed back to them raises the size the whole board renders at.
	boardPanel(gui, UDim2.fromScale(0.03, 0.03), UDim2.fromScale(0.63, 0.94))
	boardPanel(gui, UDim2.fromScale(0.675, 0.14), UDim2.fromScale(0.295, 0.83))

	local title = boardLabel(gui, "Title", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.09), GOLD, 84, true)
	title.Text = room.howToPlayIntro

	local rules: { string } = {}
	for index, rule in room.howToPlayRules do
		table.insert(rules, string.format("%d.  %s", index, rule))
	end
	local body =
		boardLabel(gui, "Rules", UDim2.fromScale(0.05, 0.16), UDim2.fromScale(0.59, 0.78), PARCHMENT, 40, false)
	body.Text = table.concat(rules, "\n\n")

	local controlsTitle =
		boardLabel(gui, "ControlsTitle", UDim2.fromScale(0.70, 0.16), UDim2.fromScale(0.25, 0.06), GOLD, 40, true)
	controlsTitle.Text = "CONTROLS"

	-- Three columns on one baseline grid: what the action is, and what each platform presses for it.
	local actions, keys, touch = controlRows()
	local rowSize = 34
	local columns = {
		{ name = "ControlAction", text = actions, x = 0.70, width = 0.13, color = PARCHMENT, align = "Left" },
		{ name = "ControlKey", text = keys, x = 0.835, width = 0.07, color = GOLD, align = "Left" },
		{ name = "ControlTouch", text = touch, x = 0.905, width = 0.065, color = DIM_TEXT, align = "Left" },
	}
	for _, column in columns do
		local label = boardColumn(
			gui,
			column.name :: string,
			UDim2.fromScale(column.x :: number, 0.26),
			UDim2.fromScale(column.width :: number, 0.68),
			column.color :: Color3,
			rowSize,
			false
		)
		label.LineHeight = 1.6
		label.Text = table.concat(column.text :: { string }, "\n")
	end
end

-- A small build marker beside the how-to-play board: "v" plus Config.Version.number, incremented by
-- one in the same change as every other edit made to this project. Dim on purpose — legible up
-- close, invisible as a design element from across the room.
local function buildVersionSign(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local _, gui = textBoard(
		CFrame.new(origin + room.versionSignOffset),
		room.versionSignWidth,
		room.versionSignHeight,
		parent,
		"VersionSign"
	)
	local label = boardLabel(gui, "Text", UDim2.fromScale(0.08, 0.08), UDim2.fromScale(0.84, 0.84), DIM_TEXT, 28, false)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = "v" .. tostring(Config.Version.number)
end

local function buildWelcome(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local _, gui = textBoard(
		CFrame.new(origin + room.welcomeSignOffset),
		room.boardWidth,
		room.boardHeight,
		parent,
		"WelcomeBoard"
	)
	boardPanel(gui, UDim2.fromScale(0.03, 0.03), UDim2.fromScale(0.94, 0.94))
	local label =
		boardLabel(gui, "Text", UDim2.fromScale(0.06, 0.08), UDim2.fromScale(0.88, 0.84), PARCHMENT, 46, false)
	label.Text = room.welcomeSignText
end

local function buildLeaderboard(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	-- Mounted on the east wall, so its face (+Z local) is rotated to point back into the room (-X).
	local cframe = CFrame.new(origin + room.leaderboardOffset) * CFrame.Angles(0, math.rad(-90), 0)
	local backing, gui = textBoard(cframe, room.leaderboardWidth, room.leaderboardHeight, parent, "LeaderboardBoard")
	boardPanel(gui, UDim2.fromScale(0.035, 0.235), UDim2.fromScale(0.93, 0.65))

	local eyebrow =
		boardLabel(gui, "Eyebrow", UDim2.fromScale(0.07, 0.035), UDim2.fromScale(0.86, 0.045), DIM_TEXT, 22, true)
	eyebrow.Text = "GLOBAL RECORDS  /  ALL-TIME"
	eyebrow.TextXAlignment = Enum.TextXAlignment.Center

	local title = boardLabel(gui, "Title", UDim2.fromScale(0.06, 0.075), UDim2.fromScale(0.88, 0.11), GOLD, 68, true)
	title.Text = room.leaderboardTitle
	title.TextXAlignment = Enum.TextXAlignment.Center
	local subtitle =
		boardLabel(gui, "Subtitle", UDim2.fromScale(0.08, 0.185), UDim2.fromScale(0.84, 0.04), DIM_TEXT, 22, false)
	subtitle.Text = "The deepest floor each candle has ever reached."
	subtitle.TextXAlignment = Enum.TextXAlignment.Center

	local rankHeader =
		boardLabel(gui, "RankHeader", UDim2.fromScale(0.08, 0.265), UDim2.fromScale(0.12, 0.035), DIM_TEXT, 19, true)
	rankHeader.Text = "RANK"
	local candleHeader =
		boardLabel(gui, "CandleHeader", UDim2.fromScale(0.22, 0.265), UDim2.fromScale(0.47, 0.035), DIM_TEXT, 19, true)
	candleHeader.Text = "CANDLE"
	local depthHeader =
		boardLabel(gui, "DepthHeader", UDim2.fromScale(0.70, 0.265), UDim2.fromScale(0.22, 0.035), DIM_TEXT, 19, true)
	depthHeader.Text = "DEPTH"
	depthHeader.TextXAlignment = Enum.TextXAlignment.Right

	local rows: { LeaderboardRow } = {}
	for index = 1, room.leaderboardRows do
		local rowY = 0.315 + (index - 1) * 0.055
		local rank = boardLabel(
			gui,
			"Rank" .. tostring(index),
			UDim2.fromScale(0.08, rowY),
			UDim2.fromScale(0.12, 0.045),
			GOLD,
			26,
			true
		)
		rank.TextYAlignment = Enum.TextYAlignment.Center
		local candle = boardLabel(
			gui,
			"Candle" .. tostring(index),
			UDim2.fromScale(0.22, rowY),
			UDim2.fromScale(0.47, 0.045),
			PARCHMENT,
			27,
			false
		)
		candle.TextYAlignment = Enum.TextYAlignment.Center
		local depth = boardLabel(
			gui,
			"Depth" .. tostring(index),
			UDim2.fromScale(0.70, rowY),
			UDim2.fromScale(0.22, 0.045),
			PARCHMENT,
			24,
			true
		)
		depth.TextXAlignment = Enum.TextXAlignment.Right
		depth.TextYAlignment = Enum.TextYAlignment.Center
		rank.Visible = false
		candle.Visible = false
		depth.Visible = false
		table.insert(rows, { rank = rank, candle = candle, depth = depth })
	end

	local status =
		boardLabel(gui, "Status", UDim2.fromScale(0.08, 0.91), UDim2.fromScale(0.84, 0.04), DIM_TEXT, 18, false)
	status.Text = "INTERACT TO REFRESH  /  AUTO-UPDATES EACH MINUTE"
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextYAlignment = Enum.TextYAlignment.Center

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RefreshLeaderboardPrompt"
	prompt.ActionText = room.leaderboardRefreshPromptText
	prompt.ObjectText = room.leaderboardRefreshObjectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = room.leaderboardRefreshRange
	prompt.RequiresLineOfSight = true
	prompt.Parent = backing
	leaderboardDisplay = { rows = rows, status = status, refreshPrompt = prompt }
end

local function buildUpdateBoard(origin: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	-- East wall: local +Z points west into the room, matching textBoard's readable Back face.
	local cframe = CFrame.new(origin + room.updateBoardOffset) * CFrame.Angles(0, math.rad(-90), 0)
	local _, gui = textBoard(cframe, room.updateBoardWidth, room.updateBoardHeight, parent, "UpdateBoard")
	boardPanel(gui, UDim2.fromScale(0.04, 0.16), UDim2.fromScale(0.92, 0.79))

	local title = boardLabel(gui, "Title", UDim2.fromScale(0.06, 0.035), UDim2.fromScale(0.88, 0.1), GOLD, 58, true)
	title.Text = room.updateBoardTitle
	title.TextXAlignment = Enum.TextXAlignment.Center

	local visibleEntries = math.min(#room.updateLog, 3)
	local rowHeight = 0.76 / math.max(visibleEntries, 1)
	for index = 1, visibleEntries do
		local entry = room.updateLog[index]
		local y = 0.18 + (index - 1) * rowHeight
		local heading = boardLabel(
			gui,
			"UpdateHeading" .. tostring(index),
			UDim2.fromScale(0.08, y),
			UDim2.fromScale(0.84, rowHeight * 0.22),
			GOLD,
			30,
			true
		)
		heading.Text = string.format("BUILD %d  /  %s", entry.version, entry.date)
		local body = boardLabel(
			gui,
			"UpdateLines" .. tostring(index),
			UDim2.fromScale(0.08, y + rowHeight * 0.23),
			UDim2.fromScale(0.84, rowHeight * 0.7),
			PARCHMENT,
			25,
			false
		)
		local lines: { string } = {}
		for _, line in entry.lines do
			table.insert(lines, "• " .. line)
		end
		body.Text = table.concat(lines, "\n")
	end
end

--------------------------------------------------------------------------------
-- Elevators
--------------------------------------------------------------------------------

-- HOIST GEOMETRY, shared by the shaft below the floor and the headframe above it.
--
-- NONE OF IT MAY BE PARENTED TO THE CAR MODEL. ElevatorService PivotTo's that whole model 220 studs
-- down the shaft during the descent, so anything under it rides down too: a headframe parented there
-- would sink through the ceiling of the room it is bolted to, and a counterweight would fall in step
-- with the car it is supposed to be balancing. The single exception is the stub of cable bolted to
-- the car roof, which HAS to travel with the roof it is bolted to.
local SHAFT_CLEARANCE = 2 -- gap between the car edge and the shaft wall, where the guide rails run
local COUNTERWEIGHT_CHASE = 5 -- the counterweight's own slot, immediately behind the car
local CABLE_THICKNESS = 0.3
local CABLE_HALF_SPACING = 3.5 -- half the gap between the two hoist cables over the car roof
local CABLE_STUB_LENGTH = 2.4
local SHEAVE_THICKNESS = 1.2
local HEADFRAME_HEIGHT = 23.6 -- top of the headframe legs, measured from the alcove floor
local SHEAVE_AXLE_Y = 23

-- Where the counterweight hangs when the car is parked at the top: near the bottom of the shaft,
-- because a counterweight is at the far end of the rope from the car. It is deliberately not
-- animated — nothing in ElevatorService drives it — so it is placed in the pose that matches the
-- state the hub is in for all but a few seconds at a time.
local COUNTERWEIGHT_SIZE = Vector3.new(5, 7, 3.5)
local COUNTERWEIGHT_REST_DEPTH = 26 -- studs above the shaft floor

-- A small bolted work-lantern hung on the nearest rib rings, just enough of them to reveal ribs and
-- rails receding into the dark right under the car. Without one of these the tube is pure black
-- (Lighting.Ambient is pinned to black — see EnvironmentSetup.apply) and reads as a flat void rather
-- than a shaft the car is actually descending into; past their range it is still true black by
-- design, same as the arrival tunnel.
local function shaftLantern(position: Vector3, parent: Instance)
	local lamp = newPart(Vector3.new(0.6, 0.9, 0.6), CFrame.new(position), LANTERN, Enum.Material.Neon, parent)
	lamp.Name = "ShaftLantern"
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CastShadow = false
	pointLight(lamp, 16, 1.3, false)
end

-- The shaft each car descends into: a ribbed tube below the floor opening. The ribs are the whole
-- point — they are the parallax that makes the ride read as motion rather than a fade.
--
-- The tube is cut WIDER than the car on all four sides: `SHAFT_CLEARANCE` of air either side for the
-- guide rails to run down, and a `COUNTERWEIGHT_CHASE` slot behind it for the counterweight. All of
-- that extra width sits below the room floor (`buildFloor` only ever opens a hole the size of the
-- car itself), so it adds machinery to look down at without adding anywhere to fall.
local function buildShaft(origin: Vector3, offset: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local top = origin + offset
	local depth = room.rideShaftDepth
	local halfW, halfD = room.elevatorCarWidth / 2, room.elevatorCarDepth / 2
	local centreY = top.Y - depth / 2

	local innerHalfW = halfW + SHAFT_CLEARANCE
	local frontZ = -(halfD + SHAFT_CLEARANCE)
	local backZ = halfD + COUNTERWEIGHT_CHASE
	local tubeCentreZ = (frontZ + backZ) / 2
	local tubeDepth = backZ - frontZ

	local walls = {
		{ Vector3.new(innerHalfW * 2 + 2, depth, 1), Vector3.new(0, 0, backZ + 0.5) },
		{ Vector3.new(innerHalfW * 2 + 2, depth, 1), Vector3.new(0, 0, frontZ - 0.5) },
		{ Vector3.new(1, depth, tubeDepth + 2), Vector3.new(innerHalfW + 0.5, 0, tubeCentreZ) },
		{ Vector3.new(1, depth, tubeDepth + 2), Vector3.new(-innerHalfW - 0.5, 0, tubeCentreZ) },
	}
	-- CastShadow off for everything below the floor: Ambient is pinned to black down here, so none of
	-- these shadows can ever fall on anything a player can see, and leaving dozens of thin ribs and
	-- rails 260 studs deep casting shadows nobody can see is exactly the kind of geometry that
	-- shimmers/flickers under a shadow map at that distance.
	for _, wall in walls do
		local part = block(
			wall[1] :: Vector3,
			Vector3.new(top.X, centreY, top.Z) + (wall[2] :: Vector3),
			STONE,
			Enum.Material.Rock,
			parent
		)
		part.Name = "ShaftWall"
		part.CastShadow = false
	end

	-- GUIDE RAILS: two down the car's own tube, two down the counterweight chase. They cross every rib
	-- ring on the way, which is what a rail bracketed to each ring looks like, and they are what make
	-- the shaft read as a track something runs in rather than as a hole with a pattern on the wall.
	local rails = {
		Vector3.new(halfW + SHAFT_CLEARANCE / 2, 0, 0),
		Vector3.new(-(halfW + SHAFT_CLEARANCE / 2), 0, 0),
		Vector3.new(COUNTERWEIGHT_SIZE.X / 2 + 0.5, 0, halfD + COUNTERWEIGHT_CHASE / 2),
		Vector3.new(-(COUNTERWEIGHT_SIZE.X / 2 + 0.5), 0, halfD + COUNTERWEIGHT_CHASE / 2),
	}
	for _, railOffset in rails do
		local rail = block(
			Vector3.new(0.8, depth, 1.6),
			Vector3.new(top.X, centreY, top.Z) + railOffset,
			RAIL,
			Enum.Material.Metal,
			parent
		)
		rail.Name = "ShaftGuideRail"
		rail.CastShadow = false
	end

	-- The counterweight itself, and the rope that ties it back over the sheave. The rope runs the
	-- whole way up to the headframe as one piece, so looking down the chase from the room reads as a
	-- line under tension rather than as a block sitting on nothing.
	local counterweightY = top.Y - depth + COUNTERWEIGHT_REST_DEPTH
	local chaseZ = halfD + COUNTERWEIGHT_CHASE / 2
	block(
		COUNTERWEIGHT_SIZE,
		Vector3.new(top.X, counterweightY, top.Z + chaseZ),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	).Name =
		"Counterweight"

	local ropeTopY = top.Y + SHEAVE_AXLE_Y
	local ropeBottomY = counterweightY + COUNTERWEIGHT_SIZE.Y / 2
	block(
		Vector3.new(CABLE_THICKNESS, ropeTopY - ropeBottomY, CABLE_THICKNESS),
		Vector3.new(top.X, (ropeTopY + ropeBottomY) / 2, top.Z + chaseZ),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	).Name =
		"CounterweightCable"

	local ribCount = math.floor(depth / room.rideShaftRibSpacing)
	local ribThickness = room.rideShaftRibThickness
	local ribWidth = room.elevatorCarWidth + room.rideShaftRibOutset * 2
	local ribDepth = room.elevatorCarDepth + room.rideShaftRibOutset * 2
	-- A shaft rib is a perimeter ring, not a floor. The old implementation made one solid
	-- width-by-depth plate at every interval; the descending car visibly passed through those
	-- plates at body/head height and made riders look as if they were falling through floors.
	local ribSegments = {
		{
			size = Vector3.new(ribWidth, ribThickness, ribThickness),
			offset = Vector3.new(0, 0, ribDepth / 2),
		},
		{
			size = Vector3.new(ribWidth, ribThickness, ribThickness),
			offset = Vector3.new(0, 0, -ribDepth / 2),
		},
		{
			size = Vector3.new(ribThickness, ribThickness, ribDepth - ribThickness * 2),
			offset = Vector3.new(ribWidth / 2, 0, 0),
		},
		{
			size = Vector3.new(ribThickness, ribThickness, ribDepth - ribThickness * 2),
			offset = Vector3.new(-ribWidth / 2, 0, 0),
		},
	}
	-- Only the nearest rings get a lantern — enough to light the ribs and rails immediately below the
	-- car so the tube visibly reads as a shaft, without lighting the whole 260-stud drop.
	local lanternRibs = 4
	for i = 1, ribCount do
		local y = top.Y - i * room.rideShaftRibSpacing
		for _, segment in ribSegments do
			local rib = block(
				segment.size,
				Vector3.new(top.X, y, top.Z) + segment.offset,
				TIMBER_DARK,
				Enum.Material.Wood,
				parent
			)
			rib.Name = "ShaftRib"
			rib.CastShadow = false
		end
		if i <= lanternRibs then
			-- Mounted on the front ring (the -Z side, toward the gate) so it hangs in plain view when
			-- looking down through the open gate rather than behind a rib segment.
			shaftLantern(Vector3.new(top.X, y - room.rideShaftRibSpacing / 2, top.Z - ribDepth / 2 + 1), parent)
		end
	end

	-- Floors the whole tube, chase included, so the counterweight has something to stand over.
	local base = block(
		Vector3.new(innerHalfW * 2 + 2, 2, tubeDepth + 2),
		Vector3.new(top.X, top.Y - depth, top.Z + tubeCentreZ),
		STONE,
		Enum.Material.Rock,
		parent
	)
	base.Name = "ShaftBase"
	base.CastShadow = false
end

-- THE HEADFRAME: what makes a car read as machinery going somewhere rather than a box that sinks
-- into a trapdoor. Two legs standing on the alcove floor either side of the shaft mouth, an axle
-- across their tops, one sheave turning on it, and the ropes it turns over — the car's two hoist
-- cables tangent to the front of the wheel, the counterweight's rope tangent to the back.
--
-- THE WHEEL'S RADIUS IS NOT A LOOK, IT IS THE SPACING OF THE TWO ROPE RUNS. The car ropes hang at
-- z = 0 and the counterweight's at the middle of its chase, so a wheel that both are tangent to has
-- to be exactly half that apart across and centred between them. Change the chase and the wheel
-- follows, or the ropes stop touching the thing that is supposed to be carrying them.
--
-- Parented to `parent` — the room — never to the car. See the note above `SHAFT_CLEARANCE`.
local function buildHeadframe(origin: Vector3, offset: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local base = origin + offset
	local halfW, halfD = room.elevatorCarWidth / 2, room.elevatorCarDepth / 2
	local chaseZ = halfD + COUNTERWEIGHT_CHASE / 2
	local sheaveRadius = chaseZ / 2
	local sheaveZ = chaseZ / 2
	local legX = halfW + SHAFT_CLEARANCE + 1.5

	for _, direction in { -1, 1 } do
		block(
			Vector3.new(1.4, HEADFRAME_HEIGHT, 1.4),
			base + Vector3.new(legX * direction, HEADFRAME_HEIGHT / 2, sheaveZ),
			TIMBER_DARK,
			Enum.Material.Wood,
			parent
		).Name =
			"HeadframeLeg"

		-- A small hazard plate on the room-facing side of each leg. There is an open shaft between
		-- these two legs, and it is the only hole in the floor of a room players run around in — the
		-- one thing in the hub that genuinely warrants marking. Turned to face -Z, which is the way a
		-- rider walks in from.
		hazardPlate(
			CFrame.new(base + Vector3.new(legX * direction, 6, sheaveZ - 0.7 - 0.13))
				* CFrame.Angles(0, math.rad(180), 0),
			1.3,
			1,
			2,
			parent
		)
	end
	-- Deliberately high on the legs: it has to clear the car roof at `elevatorCarHeight` and still pass
	-- under the bottom of the wheel, or the frame reads as a beam the car could never rise past.
	block(
		Vector3.new(legX * 2 + 1.4, 1, 1.2),
		base + Vector3.new(0, HEADFRAME_HEIGHT * 0.72, sheaveZ),
		TIMBER_DARK,
		Enum.Material.Wood,
		parent
	).Name =
		"HeadframeBrace"

	-- A Roblox cylinder runs along its own X, which is already the axis both of these want.
	local axle = block(
		Vector3.new(legX * 2, 0.8, 0.8),
		base + Vector3.new(0, SHEAVE_AXLE_Y, sheaveZ),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	)
	axle.Name = "SheaveAxle"
	axle.Shape = Enum.PartType.Cylinder
	axle.CanCollide = false

	local sheave = block(
		Vector3.new(SHEAVE_THICKNESS, sheaveRadius * 2, sheaveRadius * 2),
		base + Vector3.new(0, SHEAVE_AXLE_Y, sheaveZ),
		IRON,
		Enum.Material.Metal,
		parent
	)
	sheave.Name = "HoistSheave"
	sheave.Shape = Enum.PartType.Cylinder
	sheave.CanCollide = false

	-- The two hoist cables, hanging from the wheel down to roof height. They are static: the car's own
	-- stub (built with the car, so it travels with it) is what covers the join.
	local roofY = room.elevatorCarHeight + 0.25
	local cableBottomY = roofY + CABLE_STUB_LENGTH * 0.7
	for _, direction in { -1, 1 } do
		block(
			Vector3.new(CABLE_THICKNESS, SHEAVE_AXLE_Y - cableBottomY, CABLE_THICKNESS),
			base + Vector3.new(CABLE_HALF_SPACING * direction, (SHEAVE_AXLE_Y + cableBottomY) / 2, 0),
			IRON_DARK,
			Enum.Material.Metal,
			parent
		).Name =
			"HoistCable"
	end
end

-- The header above each alcove: tier name, lock/status line, and the live party roster. This is the
-- board that makes an elevator a party maker — you can see who is in your car before you commit.
local function buildHeader(origin: Vector3, offset: Vector3, parent: Instance): (TextLabel, TextLabel, TextLabel)
	local room = Config.LobbyRoom
	local position = origin + offset
	local headerY = position.Y + room.elevatorCarHeight + room.elevatorBoardHeight / 2 + 1
	local faceZ = position.Z - room.elevatorCarDepth / 2 - 0.6

	block(
		Vector3.new(room.elevatorCarWidth + 3, 1.2, 2),
		Vector3.new(position.X, position.Y + room.elevatorCarHeight + 0.6, position.Z - room.elevatorCarDepth / 2),
		TIMBER,
		Enum.Material.Wood,
		parent
	).Name =
		"AlcoveHeaderBeam"

	local cframe = CFrame.new(Vector3.new(position.X, headerY, faceZ)) * CFrame.Angles(0, math.rad(180), 0)
	local _, gui = textBoard(cframe, room.elevatorBoardWidth, room.elevatorBoardHeight, parent, "ElevatorHeader")

	local title = boardLabel(gui, "Title", UDim2.fromScale(0.06, 0.04), UDim2.fromScale(0.88, 0.22), GOLD, 62, true)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local status =
		boardLabel(gui, "Status", UDim2.fromScale(0.06, 0.27), UDim2.fromScale(0.88, 0.13), DIM_TEXT, 30, false)
	status.TextXAlignment = Enum.TextXAlignment.Center
	local roster =
		boardLabel(gui, "Roster", UDim2.fromScale(0.06, 0.42), UDim2.fromScale(0.88, 0.54), PARCHMENT, 30, false)
	roster.TextXAlignment = Enum.TextXAlignment.Center
	return title, status, roster
end

-- THE DESCENT LEVER — the hub's read-out on what the machinery is doing, not a control. NOBODY PULLS
-- IT. Readying up is the party panel's job (and the panel says so in words); the lever is the room
-- answering back, throwing itself down at the moment the car commits to a descent. A player who
-- walks up to it gets no prompt, because a lever you can grab is a promise that pulling it does
-- something, and here the vote decides.
--
-- SMALL, THIN, AND READ FROM ITS SILHOUETTE (ART-BIBLE §2: legibility over fidelity). A dark rim, a
-- painted panel about as tall as a rider's chest to their eyes, six small brass bolt heads climbing
-- it in two columns, a pinned hinge standing a little off its centre, and hanging from that pin a
-- T-bar: two slim rails, a crossbar tying their outer ends, and a red grip run through it.
--
-- THE GRIP IS THE OBJECT. It is the only warm colour and the only part shaped like something hands
-- close on, so everything behind it is deliberately kept slim, matte and quiet — an earlier pass
-- built this at nearly twice the size in bold masses and it read as a slab of green with orange
-- bricks stuck to it, because at that scale the parts compete with the one shape that matters.
--
-- IT RESTS ARMED, RAKED UP, AND THROWS DOWN WHEN A DESCENT ACTUALLY STARTS. `LeverGeometry` owns the
-- two named poses and every moving piece's pose in both of them, so this function only ever builds
-- the rest pose; the throw itself is animated client-side in `client/ElevatorController` from the
-- exact same formula, over the whole car's own current position, so it can never drift from the
-- plate that's dragging it down the shaft at the same moment.
--
-- THE HANDLE IS BUILT FROM `LeverGeometry.handlePieces` RATHER THAN PART BY PART, because the two
-- animators walk that same list by name. Adding a piece here by hand would add one the switch never
-- moves — a rail left hanging in mid-air while the rest of the lever throws.
--
-- `basePosition` is the car's own centre; every offset below is measured from it, so the lever rides
-- with the car for free. Returns the lamp: ElevatorService owns whether it is lit, and this function
-- decides nothing about when a descent is allowed.
local function descentLever(basePosition: Vector3, halfWidth: number, parent: Instance): BasePart
	local layout = LeverGeometry.layout(halfWidth)

	local rim =
		newPart(layout.rimSize, CFrame.new(basePosition + layout.rimOffset), IRON_DARK, Enum.Material.Metal, parent)
	rim.Name = "LeverRim"

	-- SMOOTHPLASTIC, NOT METAL, ON EVERY PAINTED SURFACE. Metal takes a specular highlight from each
	-- of the hub's lanterns, and on flat slabs at this scale that reads as grease rather than as
	-- paint. The bare metal here is the rim, the fixings and the hinge — the parts that should shine.
	local plate = newPart(
		layout.plateSize,
		CFrame.new(basePosition + layout.plateOffset),
		SWITCH_PAINT,
		Enum.Material.SmoothPlastic,
		parent
	)
	plate.Name = "LeverPlate"
	plate.CanCollide = false

	-- The bolts are what say "somebody installed this", which is the whole reason the panel does not
	-- read as a rectangle of paint. Numbered so nothing in the car shares a name.
	for index, offset in layout.boltOffsets do
		local bolt = newPart(layout.boltSize, CFrame.new(basePosition + offset), BRASS, Enum.Material.Metal, parent)
		bolt.Name = "LeverBolt" .. tostring(index)
		bolt.Shape = Enum.PartType.Cylinder
		bolt.CanCollide = false
	end

	-- The two cheeks the pin runs between. `LeverGeometry` explains why the hinge stands off the
	-- panel at all; here they just need to look like what the handle is hung from.
	for index, offset in layout.cheekOffsets do
		local cheek =
			newPart(layout.cheekSize, CFrame.new(basePosition + offset), IRON_DARK, Enum.Material.Metal, parent)
		cheek.Name = "LeverCheek" .. tostring(index)
		cheek.CanCollide = false
	end

	-- A Roblox cylinder runs along its own X, so the hinge pin is turned a quarter onto the swing
	-- axis (the car's Z) — that is what shows its round end to a rider rather than its flat face.
	local pin = newPart(
		layout.pinSize,
		CFrame.new(basePosition + layout.pinOffset) * CFrame.Angles(0, math.rad(90), 0),
		IRON,
		Enum.Material.Metal,
		parent
	)
	pin.Name = "LeverPin"
	pin.Shape = Enum.PartType.Cylinder
	pin.CanCollide = false

	-- NON-COLLIDABLE THROUGHOUT. The handle sweeps through a volume a rider can be standing in, and a
	-- switch that shoves somebody across the car on departure would be worse than one that passes
	-- through them.
	for _, piece in LeverGeometry.handlePieces(layout.pivotOffset, LeverGeometry.REST_ANGLE) do
		-- The moving parts are a shade lighter than the panel they hang in front of, which is what
		-- keeps the handle from sinking into it in the car's low light.
		local colour = if piece.name == "LeverGrip" then SWITCH_GRIP else SWITCH_PAINT_LIT
		local part =
			newPart(piece.size, CFrame.new(basePosition) * piece.cframe, colour, Enum.Material.SmoothPlastic, parent)
		part.Name = piece.name
		part.CanCollide = false
		if piece.cylinder then
			part.Shape = Enum.PartType.Cylinder
		end
	end

	-- ONE lamp, dark until the car is armed for a descent. ElevatorService owns when it lights. It is
	-- SMALL and sunk in a dark bezel: a bare neon disc on a flat panel blows out into a white blob
	-- and takes the rest of the object's shape with it.
	local bezel =
		newPart(layout.bezelSize, CFrame.new(basePosition + layout.bezelOffset), IRON_DARK, Enum.Material.Metal, parent)
	bezel.Name = "LeverLampBezel"
	bezel.Shape = Enum.PartType.Cylinder
	bezel.CanCollide = false

	local lamp = newPart(
		layout.lampSize,
		CFrame.new(basePosition + layout.lampOffset),
		-- Built DARK, matching the "no party aboard yet" the room actually starts in. ElevatorService
		-- only ever writes this on a change, so the state it starts in is the state it has to start in.
		IRON_DARK,
		Enum.Material.Metal,
		parent
	)
	lamp.Name = "LeverReadyLamp"
	lamp.Shape = Enum.PartType.Cylinder
	lamp.CanCollide = false
	lamp.CastShadow = false
	local lampLight = Instance.new("PointLight")
	lampLight.Name = "ReadyGlow"
	lampLight.Color = LANTERN
	-- Enough to wash the panel around it and no more. This is a pilot light, not a room light: the
	-- ceiling lamps own the car's illumination (ART-BIBLE §4, one source per space).
	lampLight.Range = 5
	lampLight.Brightness = 0.7
	lampLight.Shadows = false
	lampLight.Enabled = false
	lampLight.Parent = lamp

	return lamp
end

-- A CAR IS A PARTY, NOT A CAVE. It is named by its position in the rank rather than by a destination,
-- because where it goes is decided by its party's vote after they are aboard (Interfaces/Party).
local function partyLabel(partyId: number): string
	return "PARTY " .. tostring(partyId)
end

local function buildElevator(origin: Vector3, partyId: number, offset: Vector3, parent: Instance): ElevatorParts
	local room = Config.LobbyRoom
	local position = origin + offset
	local label = partyLabel(partyId)
	local carHeight = room.elevatorCarHeight
	local halfW, halfD = room.elevatorCarWidth / 2, room.elevatorCarDepth / 2

	buildShaft(origin, offset, parent)
	buildHeadframe(origin, offset, parent)

	-- Everything below is parented to the car model and travels together during the ride.
	local car = Instance.new("Model")
	car.Name = "ElevatorCar_" .. label
	car:SetAttribute(LobbyVisualProtocol.attributes.partyId, partyId)

	local platform = block(
		Vector3.new(room.elevatorCarWidth, 0.8, room.elevatorCarDepth),
		position,
		IRON,
		Enum.Material.DiamondPlate,
		car
	)
	platform.Name = "Platform"
	car.PrimaryPart = platform

	local shell = {
		{ Vector3.new(room.elevatorCarWidth, carHeight, 0.5), Vector3.new(0, carHeight / 2, halfD), "CarBack" },
		{ Vector3.new(0.5, carHeight, room.elevatorCarDepth), Vector3.new(-halfW, carHeight / 2, 0), "CarSideWest" },
		{ Vector3.new(0.5, carHeight, room.elevatorCarDepth), Vector3.new(halfW, carHeight / 2, 0), "CarSideEast" },
		{
			Vector3.new(room.elevatorCarWidth, 0.5, room.elevatorCarDepth),
			Vector3.new(0, carHeight, 0),
			"CarRoof",
		},
	}
	for _, spec in shell do
		block(spec[1] :: Vector3, position + (spec[2] :: Vector3), IRON, Enum.Material.Metal, car).Name =
			spec[3] :: string
	end
	-- Corner posts, so the car reads as a built cage rather than four flat slabs.
	for _, corner in { Vector3.new(-halfW, 0, -halfD), Vector3.new(halfW, 0, -halfD) } do
		block(
			Vector3.new(1, carHeight, 1),
			position + corner + Vector3.new(0, carHeight / 2, 0),
			IRON_DARK,
			Enum.Material.Metal,
			car
		).Name =
			"CarPost"
	end

	-- THE ONE PIECE OF THE HOIST THAT RIDES DOWN. Everything else about the machinery — headframe,
	-- sheave, cables, counterweight — is parented to the room, because the car model is PivotTo'd the
	-- whole length of the descent. These two stubs are bolted to the roof, so they have to travel with
	-- it: they are what covers the join where the static cables meet the car while it is parked.
	local roofY = carHeight + 0.25
	for _, direction in { -1, 1 } do
		block(
			Vector3.new(CABLE_THICKNESS, CABLE_STUB_LENGTH, CABLE_THICKNESS),
			position + Vector3.new(CABLE_HALF_SPACING * direction, roofY + CABLE_STUB_LENGTH / 2, 0),
			IRON_DARK,
			Enum.Material.Metal,
			car
		).Name =
			"CarHoistCable"
	end
	block(
		Vector3.new(CABLE_HALF_SPACING * 2 + 1.4, 0.5, 1.2),
		position + Vector3.new(0, roofY + 0.25, 0),
		IRON_DARK,
		Enum.Material.Metal,
		car
	).Name =
		"CarHoistYoke"

	local bulb = block(
		Vector3.new(2, 0.6, 2),
		position + Vector3.new(0, carHeight - 1.2, halfD - 1.5),
		LANTERN,
		Enum.Material.Neon,
		car
	)
	bulb.Name = "CarLamp"
	bulb.CanCollide = false
	bulb.CastShadow = false
	pointLight(
		bulb,
		Config.LobbyRoom.lighting.elevatorLampRange,
		Config.LobbyRoom.lighting.elevatorLampBrightness,
		false
	)

	-- The gate: open (transparent, non-colliding) until ElevatorService closes it for the ride. Closed
	-- server-side rather than per-client so everyone in the room watches the car seal, not just riders.
	local gate = block(
		Vector3.new(room.elevatorCarWidth, carHeight, room.elevatorGateThickness),
		position + Vector3.new(0, carHeight / 2, -halfD + 0.3),
		IRON_DARK,
		Enum.Material.DiamondPlate,
		car
	)
	gate.Name = "Gate"
	gate.CanCollide = false
	gate.Transparency = 1

	-- In-car readout on the back wall, facing the rider. ElevatorController writes the descent text
	-- here during the ride; it is tagged rather than handed over so the client owns its own copy.
	local readoutBacking = newPart(
		Vector3.new(room.elevatorCarWidth - 3, 3, 0.3),
		CFrame.new(position + Vector3.new(0, carHeight * 0.62, halfD - 0.5)) * CFrame.Angles(0, math.rad(180), 0),
		BOARD_BACKING,
		Enum.Material.Metal,
		car
	)
	readoutBacking.Name = "CarReadout"
	readoutBacking:SetAttribute(LobbyVisualProtocol.attributes.partyId, partyId)
	CollectionService:AddTag(readoutBacking, LobbyVisualProtocol.readoutTag)

	local readoutGui = Instance.new("SurfaceGui")
	readoutGui.Face = Enum.NormalId.Back
	readoutGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	readoutGui.PixelsPerStud = 48
	readoutGui.LightInfluence = 0
	readoutGui.Parent = readoutBacking
	local readoutLabel =
		boardLabel(readoutGui, "Text", UDim2.fromScale(0.03, 0.1), UDim2.fromScale(0.94, 0.8), GOLD, 48, true)
	readoutLabel.TextXAlignment = Enum.TextXAlignment.Center
	readoutLabel.TextYAlignment = Enum.TextYAlignment.Center
	readoutLabel.Text = string.upper(label)

	-- The lever lives inside the car on the east wall, in plain sight of a rider.
	local leverLamp = descentLever(position, halfW, car)

	car.Parent = parent
	CollectionService:AddTag(car, LobbyVisualProtocol.carTag)

	local headerTitle, headerStatus, headerRoster = buildHeader(origin, offset, parent)
	headerTitle.Text = string.upper(label)

	return {
		partyId = partyId,
		car = car,
		restPivot = car:GetPivot(),
		gate = gate,
		leverLamp = leverLamp,
		headerTitle = headerTitle,
		headerStatus = headerStatus,
		headerRoster = headerRoster,
	}
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function LobbyRoomBuilder.spawnPosition(): Vector3
	return Config.LobbyRoom.origin + Config.LobbyRoom.spawnOffset
end

-- Arrivals are spread around the spawn point so nobody ever lands inside somebody else.
--
-- RINGS, NOT ONE CIRCLE. This used to divide the circle by `Config.Run.partyCap`, which was right
-- when a server held exactly one party of four. Four parties of four means the hub can hold sixteen
-- people, so four positions would put every fifth arrival on top of the first. Slots past the first
-- ring step outward and are rotated by half a slot, so no two indices ever resolve to one point.
function LobbyRoomBuilder.spawnPositionFor(index: number): Vector3
	local room = Config.LobbyRoom
	local spread = room.spawnSpread
	if spread <= 0 then
		return LobbyRoomBuilder.spawnPosition()
	end
	local slots = math.max(1, room.spawnSlots)
	local ring = math.floor(index / slots)
	local angle = (index % slots) * (2 * math.pi / slots) + ring * (math.pi / slots)
	local radius = spread * (1 + ring * 0.75)
	return LobbyRoomBuilder.spawnPosition() + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- A player's own spawn slot, held for as long as they are in the server.
--
-- A STABLE SLOT PER PLAYER IS THE POINT. Callers no longer have a party slot to pass (a hub arrival
-- belongs to no party until they walk into a car), and passing a constant would stack the whole
-- lobby on one stud. The counter only ever moves forward, so two players present at once can never
-- hold the same slot however many have joined and left before them.
local spawnSlots: { [number]: number } = {}
local nextSpawnSlot = 0

function LobbyRoomBuilder.spawnPositionForPlayer(playerId: number): Vector3
	local slot = spawnSlots[playerId]
	if slot == nil then
		slot = nextSpawnSlot
		nextSpawnSlot += 1
		spawnSlots[playerId] = slot
	end
	return LobbyRoomBuilder.spawnPositionFor(slot)
end

function LobbyRoomBuilder.releaseSpawnSlot(playerId: number)
	spawnSlots[playerId] = nil
end

function LobbyRoomBuilder.elevators(): { ElevatorParts }
	return elevatorParts
end

function LobbyRoomBuilder.leaderboardDisplay(): LeaderboardDisplay?
	return leaderboardDisplay
end

-- The shop stall's prompt. Exposed rather than answered here so PartyLobbyService (which owns lobby
-- messaging) decides the reply, keeping this file free of gameplay decisions.
function LobbyRoomBuilder.shopPrompt(): ProximityPrompt?
	return shopPrompt
end

-- `withLandingSpawn` is false on a reserved expedition server, and only there. See the SpawnLocation
-- at the bottom of this function for why that one instance is a decision and not a detail.
function LobbyRoomBuilder.build(withLandingSpawn: boolean?)
	if built then
		return
	end
	built = true

	local room = Config.LobbyRoom
	local folder = Instance.new("Folder")
	folder.Name = "WickLobbyRoom"
	folder.Parent = workspace

	buildShell(room.origin, folder)
	buildProps(room.origin, folder)
	buildParkour(room.origin, folder)
	shopPrompt = buildShop(room.origin, folder)
	buildWelcome(room.origin, folder)
	buildHowToPlay(room.origin, folder)
	buildVersionSign(room.origin, folder)
	buildLeaderboard(room.origin, folder)
	buildUpdateBoard(room.origin, folder)

	for _, elevator in room.elevators do
		table.insert(elevatorParts, buildElevator(room.origin, elevator.partyId, elevator.offset, folder))
	end

	-- Roblox picks a SpawnLocation for Player:LoadCharacter; without one every lobby body would
	-- appear at the world origin and be teleported in, one visible frame late. Invisible and flush
	-- with the floor rather than a raised plank of its own: the floor already reads as timber, so the
	-- pad needs no shape of its own calling attention to where you first land.
	--
	-- AND IT IS THE ONE THING A RESERVED EXPEDITION SERVER MUST NOT HAVE.
	--
	-- An expedition runs on a reserved server on this same PlaceId, so this whole hub is built there
	-- too — a full duplicate the party is never meant to see. That was survivable until you ask what
	-- Roblox's camera does while a player has no character at all, which is exactly the state an
	-- arriving expedition member is deliberately left in (`PartyLobbyService.onPlayerAdded` spawns no
	-- lobby avatar; the real body is the candle `RunOrchestrator` makes 500 studs down once floor one
	-- is carved). With `Character` and `CameraSubject` both nil, the default camera parks at the map's
	-- SpawnLocation — and this pad was the only one in the world. The result was the descent's most
	-- reported bug: you ride the lobby car, you get a loading screen, you appear back in the hub for a
	-- moment, and then you are "teleported" to the cave. Only one teleport ever happened. What the
	-- player saw in the middle was this camera, sitting inside a lit copy of a room they had just left.
	--
	-- Removing the pad leaves the default camera with nowhere in the hub to rest, which is all this
	-- fix needs. The hub itself is still built: a reserved server puts bodies back in it when a run
	-- resolves (`PartyLobbyService.returnToLobby`), and the only cost of the missing pad is that those
	-- returning bodies are placed by `spawnLobby` a frame after `LoadCharacter` rather than landing on
	-- a pad — which is what that function does for every one of them anyway.
	if withLandingSpawn == false then
		return
	end
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LandingSpawn"
	spawnLocation.Size = Vector3.new(16, 0.4, 16)
	spawnLocation.Position = LobbyRoomBuilder.spawnPosition() + Vector3.new(0, -0.2, 0)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Color = PLANK
	spawnLocation.Material = Enum.Material.WoodPlanks
	spawnLocation.Transparency = 1
	spawnLocation.CastShadow = false
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.BottomSurface = Enum.SurfaceType.Smooth
	spawnLocation.Parent = folder
end

return LobbyRoomBuilder
