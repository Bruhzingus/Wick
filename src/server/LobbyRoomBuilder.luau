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

local LobbyRoomBuilder = {}

-- Everything on one elevator that ElevatorService needs to drive. `car` is the model that physically
-- descends during the ride; the header board and shaft stay behind in the room.
export type ElevatorParts = {
	tierId: number,
	car: Model,
	restPivot: CFrame,
	gate: BasePart,
	lever: ProximityPrompt,
	headerTitle: TextLabel,
	headerStatus: TextLabel,
	headerRoster: TextLabel,
}

-- Everything about one Lamp Network fixture that a caller needs. The prompt is answered by
-- PartyLobbyService (which owns lobby messaging) exactly like the shop stall's, so this file keeps
-- deciding nothing; the labels are exposed so signage can be repainted when ownership changes.
export type LampParts = {
	nodeId: string,
	prompt: ProximityPrompt,
	titleLabel: TextLabel,
	detailLabel: TextLabel,
}

-- Constructed timber and iron, not natural rock: the hub reads as built, warm and safe, in
-- deliberate contrast to the caves below.
local TIMBER = Color3.fromRGB(96, 68, 46)
local TIMBER_DARK = Color3.fromRGB(58, 41, 28)
local PLANK = Color3.fromRGB(78, 55, 38)
local IRON = Color3.fromRGB(58, 56, 54)
local IRON_DARK = Color3.fromRGB(38, 37, 36)
local RAIL = Color3.fromRGB(104, 96, 86)
local STONE = Color3.fromRGB(62, 58, 54)
local LANTERN = Color3.fromRGB(255, 188, 112)
local BOARD_BACKING = Color3.fromRGB(34, 27, 22)
local GOLD = Color3.fromRGB(255, 212, 128)
local PARCHMENT = Color3.fromRGB(232, 224, 210)
local DIM_TEXT = Color3.fromRGB(150, 138, 122)

local built = false
local elevatorParts: { ElevatorParts } = {}
local leaderboardLabel: TextLabel? = nil
local shopPrompt: ProximityPrompt? = nil
local lampParts: { LampParts } = {}

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

-- A floor-standing lantern post. `basePosition` is the point the post STANDS on, so the post is
-- offset up by half its height rather than centred on the floor and sunk through it.
local function lanternPost(basePosition: Vector3, parent: Instance)
	local postHeight = 7
	block(
		Vector3.new(0.7, postHeight, 0.7),
		basePosition + Vector3.new(0, postHeight / 2, 0),
		TIMBER_DARK,
		Enum.Material.Wood,
		parent
	).Name =
		"LanternPost"

	local headY = basePosition.Y + postHeight + 0.5
	local cage = block(
		Vector3.new(1.6, 1.6, 1.6),
		Vector3.new(basePosition.X, headY, basePosition.Z),
		IRON,
		Enum.Material.Metal,
		parent
	)
	cage.Name = "LanternCage"
	cage.Transparency = 0.55

	local bulb = block(
		Vector3.new(0.9, 0.9, 0.9),
		Vector3.new(basePosition.X, headY, basePosition.Z),
		LANTERN,
		Enum.Material.Neon,
		parent
	)
	bulb.Name = "LanternBulb"
	bulb.CanCollide = false
	bulb.CastShadow = false
	pointLight(bulb, Config.LobbyRoom.lighting.lanternRange, Config.LobbyRoom.lighting.lanternBrightness, false)
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

	local walls = {
		{ Vector3.new(room.roomWidth, room.wallHeight, room.wallThickness), Vector3.new(0, 0, -halfD), "EntryWall" },
		{ Vector3.new(room.roomWidth, room.wallHeight, room.wallThickness), Vector3.new(0, 0, halfD), "RearWall" },
		{ Vector3.new(room.wallThickness, room.wallHeight, room.roomDepth), Vector3.new(-halfW, 0, 0), "WallWest" },
		{ Vector3.new(room.wallThickness, room.wallHeight, room.roomDepth), Vector3.new(halfW, 0, 0), "WallEast" },
	}
	for _, wall in walls do
		block(
			wall[1] :: Vector3,
			origin + (wall[2] :: Vector3) + Vector3.new(0, room.wallHeight / 2, 0),
			STONE,
			Enum.Material.Rock,
			parent
		).Name =
			wall[3] :: string
	end

	-- Timber ceiling supports: a cross-beam plus two legs at each spacing interval. This is what
	-- makes the space read as a mineshaft rather than a warehouse.
	--
	-- The welcome and how-to-play boards are mounted flush on the entry wall (z = -halfD), the same
	-- plane as the front row of these posts, and the beam grid's x-spacing happens to land right
	-- across both boards' width. Skip a post's front leg wherever it would stand in front of a
	-- board — the rear leg (and every other post) is untouched.
	local signBoardHalfWidth = room.boardWidth / 2
	local postHalfWidth = 0.6
	local function blocksEntrySign(x: number): boolean
		for _, boardX in { room.welcomeSignOffset.X, room.howToPlayOffset.X } do
			if math.abs(x - boardX) < signBoardHalfWidth + postHalfWidth then
				return true
			end
		end
		return false
	end

	local beamCount = math.max(2, math.floor(room.roomWidth / room.beamSpacing))
	for i = 0, beamCount do
		local x = -halfW + (i / beamCount) * room.roomWidth
		block(
			Vector3.new(1.2, 1.4, room.roomDepth),
			origin + Vector3.new(x, ceilingY - 0.7, 0),
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
		end
	end

	-- Mine-cart rails running the length of the room toward the elevators.
	for _, railX in { -1.6, 1.6 } do
		block(
			Vector3.new(0.5, 0.35, room.roomDepth - 8),
			origin + Vector3.new(railX, 0.18, -4),
			RAIL,
			Enum.Material.Metal,
			parent
		).Name =
			"Rail"
	end
	local sleeperCount = math.floor((room.roomDepth - 8) / room.railSpacing)
	for i = 0, sleeperCount do
		local z = -halfD + 4 + i * room.railSpacing
		block(Vector3.new(6, 0.3, 1.4), origin + Vector3.new(0, 0.12, z), TIMBER_DARK, Enum.Material.Wood, parent).Name =
			"RailSleeper"
	end

	-- Ceiling lamps on a grid, plus lantern posts hugging the side walls.
	for _, x in { -halfW * 0.55, 0, halfW * 0.55 } do
		for _, z in { -halfD * 0.55, halfD * 0.4 } do
			ceilingLamp(origin + Vector3.new(x, ceilingY - 5, z), origin.Y + ceilingY, parent)
		end
	end
	for _, z in { -halfD + 12, -8, halfD - 24 } do
		lanternPost(origin + Vector3.new(-halfW + 4, 0, z), parent)
		lanternPost(origin + Vector3.new(halfW - 4, 0, z), parent)
	end
end

-- Scattered crates and barrels: cheap, readable dressing that gives the space scale and stops the
-- floor reading as an empty plane.
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

	-- A parked mine cart on the rails.
	local cartPosition = origin + Vector3.new(0, 1.4, -halfD + 18)
	block(Vector3.new(5, 0.4, 7), cartPosition, IRON, Enum.Material.Metal, parent).Name = "CartFloor"
	for _, spec in
		{
			{ Vector3.new(5, 2.6, 0.4), Vector3.new(0, 1.3, 3.3) },
			{ Vector3.new(5, 2.6, 0.4), Vector3.new(0, 1.3, -3.3) },
			{ Vector3.new(0.4, 2.6, 7), Vector3.new(2.3, 1.3, 0) },
			{ Vector3.new(0.4, 2.6, 7), Vector3.new(-2.3, 1.3, 0) },
		}
	do
		block(spec[1] :: Vector3, cartPosition + (spec[2] :: Vector3), IRON, Enum.Material.Metal, parent).Name =
			"CartWall"
	end
end

--------------------------------------------------------------------------------
-- Shop, signage, standings
--------------------------------------------------------------------------------

local function buildShop(origin: Vector3, parent: Instance): ProximityPrompt
	local room = Config.LobbyRoom
	local position = origin + room.shopOffset

	local counter =
		block(Vector3.new(12, 3.5, 3), position + Vector3.new(0, 1.75, 0), TIMBER, Enum.Material.Wood, parent)
	counter.Name = "ShopCounter"
	block(Vector3.new(12, 0.4, 4), position + Vector3.new(0, 3.7, 0), PLANK, Enum.Material.Wood, parent).Name =
		"ShopCounterTop"
	block(Vector3.new(12, 9, 0.5), position + Vector3.new(0, 4.5, 2.5), PLANK, Enum.Material.WoodPlanks, parent).Name =
		"ShopBackdrop"
	for _, x in { -6, 6 } do
		block(Vector3.new(0.8, 11, 0.8), position + Vector3.new(x, 5.5, -1.5), TIMBER_DARK, Enum.Material.Wood, parent).Name =
			"ShopPost"
	end
	block(Vector3.new(13.6, 0.6, 5), position + Vector3.new(0, 11, 0), TIMBER, Enum.Material.Wood, parent).Name =
		"ShopAwning"

	local _, gui = textBoard(
		CFrame.new(position + Vector3.new(0, 7.5, -1.9)) * CFrame.Angles(0, math.rad(180), 0),
		9,
		2.6,
		parent,
		"ShopSign"
	)
	local title = boardLabel(gui, "Title", UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.92, 0.9), GOLD, 64, true)
	title.Text = string.upper(room.shopObjectText)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center

	lanternPost(position + Vector3.new(-7.5, 0, -2), parent)
	lanternPost(position + Vector3.new(7.5, 0, -2), parent)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = room.shopPromptText
	prompt.ObjectText = room.shopObjectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	return prompt
end

--------------------------------------------------------------------------------
-- The lamp line
--------------------------------------------------------------------------------

-- One dark housing, its plinth, its sign and its prompt. Built unlit ALWAYS: ownership is per-player
-- and this geometry is shared, so the lit state is a client decision (LobbyVisualProtocol).
local function buildLampFixture(origin: Vector3, index: number, node: Interfaces.LampNode, parent: Instance): LampParts
	local room = Config.LobbyRoom
	local base = origin + Vector3.new(room.lampLineX, 0, room.lampLineFirstZ + room.lampLineSpacing * (index - 1))

	-- The machine the lamp feeds. Deliberately one shape for every node rather than nine bespoke
	-- props: the sign says which machine it is, and a grey-box hub should not spend nine models on a
	-- distinction the text already makes.
	local plinth = block(
		room.lampPlinthSize,
		base + Vector3.new(0, room.lampPlinthSize.Y / 2, 0),
		TIMBER,
		Enum.Material.Wood,
		parent
	)
	plinth.Name = "LampPlinth"
	block(
		Vector3.new(room.lampPlinthSize.X + 0.6, 0.3, room.lampPlinthSize.Z + 0.6),
		base + Vector3.new(0, room.lampPlinthSize.Y + 0.15, 0),
		PLANK,
		Enum.Material.Wood,
		parent
	).Name =
		"LampPlinthTop"

	-- The bracket and the housing that hangs off the conduit above it.
	block(
		Vector3.new(1.6, 0.4, 0.4),
		base + Vector3.new(0.9, room.lampConduitHeight - 0.6, 0),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	).Name =
		"LampBracket"

	local housing = block(
		room.lampHousingSize,
		base + Vector3.new(1.6, room.lampConduitHeight - 1.4, 0),
		IRON,
		Enum.Material.Metal,
		parent
	)
	housing.Name = "LampHousing"
	housing:SetAttribute(LobbyVisualProtocol.attributes.lampNodeId, node.id)
	CollectionService:AddTag(housing, LobbyVisualProtocol.lampHousingTag)

	-- The flame itself, and the light it would throw. Both start fully off. The client turns them on
	-- for a node its own player owns; nothing here ever does.
	local flame = block(
		Vector3.new(0.5, 0.7, 0.5),
		base + Vector3.new(1.6, room.lampConduitHeight - 1.4, 0),
		LANTERN,
		Enum.Material.Neon,
		housing
	)
	flame.Name = "LampFlame"
	flame.Transparency = 1
	flame.CanCollide = false

	local light = Instance.new("PointLight")
	light.Name = "LampLight"
	light.Color = LANTERN
	light.Range = room.lampLitRange
	light.Brightness = room.lampLitBrightness
	light.Enabled = false
	light.Parent = housing

	-- The sign faces east, into the room, since the line runs down the west wall.
	local _, gui = textBoard(
		CFrame.new(base + Vector3.new(1.3, room.lampPlinthSize.Y + 2.2, 0)) * CFrame.Angles(0, math.rad(90), 0),
		room.lampSignWidth,
		room.lampSignHeight,
		parent,
		"LampSign"
	)
	local title = boardLabel(gui, "Title", UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.44), GOLD, 30, true)
	title.Text = string.upper(node.displayName)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local detail =
		boardLabel(gui, "Detail", UDim2.fromScale(0.04, 0.5), UDim2.fromScale(0.92, 0.42), DIM_TEXT, 20, false)
	detail.Text = node.promptClause
	detail.TextXAlignment = Enum.TextXAlignment.Left

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = node.displayName
	-- Name, effect and price, all readable BEFORE the hold commits anything. This is how the track
	-- meets "immediately understandable at the point of purchase" structurally rather than by hoping
	-- a two-word name carries its own meaning.
	prompt.ActionText = string.format("%s — %d Raw Wax", node.promptClause, node.cost)
	-- THE HOLD IS THE CONFIRMATION. A tap does nothing, so there is no accidental purchase and no
	-- confirm dialog — which is what keeps this inside the shop-stub pattern instead of becoming UI.
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = room.lampPromptRange
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(LobbyVisualProtocol.attributes.lampNodeId, node.id)
	prompt.Parent = plinth

	return { nodeId = node.id, prompt = prompt, titleLabel = title, detailLabel = detail }
end

local function buildLampLine(origin: Vector3, parent: Instance): { LampParts }
	local room = Config.LobbyRoom
	local fixtures: { LampParts } = {}
	local nodes = Interfaces.LampNetwork.list()
	if not Interfaces.LampNetwork.isEnabled() or #nodes == 0 then
		-- Master rollback: no conduit, no housings, no prompts. A player who already owns nodes simply
		-- finds nothing to interact with rather than an error.
		return fixtures
	end

	-- One unbroken run of conduit behind the whole line, extending half a span past each end so the
	-- line reads as arriving from somewhere and leaving for somewhere.
	local span = room.lampLineSpacing * (#nodes - 1)
	local centerZ = room.lampLineFirstZ + span / 2
	block(
		Vector3.new(0.35, 0.35, span + room.lampLineSpacing),
		origin + Vector3.new(room.lampLineX, room.lampConduitHeight, centerZ),
		IRON_DARK,
		Enum.Material.Metal,
		parent
	).Name =
		"LampConduit"

	for index, node in nodes do
		table.insert(fixtures, buildLampFixture(origin, index, node, parent))
	end
	return fixtures
end

-- Reads live from Config.Feel so signage can never drift from the real keybinds.
local function controlsText(): string
	local Feel = Config.Feel
	local parts: { string } = {}
	for _, tool in Feel.controls.tools do
		table.insert(parts, tool.keyLabel .. "  " .. string.upper(tool.toolId))
	end
	for _, key in { "Sprint" } do
		local binding = Feel.controls.movement[key]
		table.insert(parts, binding.keyLabel .. "  " .. binding.displayName)
	end
	table.insert(parts, "WHEEL  BRIGHTNESS")
	return table.concat(parts, "\n")
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
	boardPanel(gui, UDim2.fromScale(0.03, 0.03), UDim2.fromScale(0.63, 0.94))
	boardPanel(gui, UDim2.fromScale(0.68, 0.16), UDim2.fromScale(0.29, 0.81))

	local title = boardLabel(gui, "Title", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.11), GOLD, 68, true)
	title.Text = room.howToPlayIntro

	local rules: { string } = {}
	for index, rule in room.howToPlayRules do
		table.insert(rules, string.format("%d.  %s", index, rule))
	end
	local body =
		boardLabel(gui, "Rules", UDim2.fromScale(0.05, 0.18), UDim2.fromScale(0.62, 0.76), PARCHMENT, 30, false)
	body.Text = table.concat(rules, "\n\n")

	local controlsTitle =
		boardLabel(gui, "ControlsTitle", UDim2.fromScale(0.7, 0.18), UDim2.fromScale(0.26, 0.07), GOLD, 34, true)
	controlsTitle.Text = "CONTROLS"
	local controls =
		boardLabel(gui, "Controls", UDim2.fromScale(0.7, 0.27), UDim2.fromScale(0.26, 0.67), PARCHMENT, 30, false)
	controls.Text = controlsText()
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
	local _, gui = textBoard(cframe, room.boardWidth, room.boardHeight, parent, "LeaderboardBoard")

	local title = boardLabel(gui, "Title", UDim2.fromScale(0.06, 0.04), UDim2.fromScale(0.88, 0.11), GOLD, 68, true)
	title.Text = room.leaderboardTitle
	local subtitle =
		boardLabel(gui, "Subtitle", UDim2.fromScale(0.06, 0.15), UDim2.fromScale(0.88, 0.06), DIM_TEXT, 26, false)
	subtitle.Text = "The deepest floor each candle has ever reached."

	leaderboardLabel =
		boardLabel(gui, "Rows", UDim2.fromScale(0.06, 0.24), UDim2.fromScale(0.88, 0.7), PARCHMENT, 34, false)
	lanternPost(origin + room.leaderboardOffset + Vector3.new(-2.5, -9, -8), parent)
	lanternPost(origin + room.leaderboardOffset + Vector3.new(-2.5, -9, 8), parent)
end

--------------------------------------------------------------------------------
-- Elevators
--------------------------------------------------------------------------------

-- The shaft each car descends into: a ribbed tube below the floor opening. The ribs are the whole
-- point — they are the parallax that makes the ride read as motion rather than a fade.
local function buildShaft(origin: Vector3, offset: Vector3, parent: Instance)
	local room = Config.LobbyRoom
	local top = origin + offset
	local depth = room.rideShaftDepth
	local halfW, halfD = room.elevatorCarWidth / 2, room.elevatorCarDepth / 2
	local centreY = top.Y - depth / 2

	local walls = {
		{ Vector3.new(room.elevatorCarWidth + 2, depth, 1), Vector3.new(0, 0, halfD + 0.5) },
		{ Vector3.new(room.elevatorCarWidth + 2, depth, 1), Vector3.new(0, 0, -halfD - 0.5) },
		{ Vector3.new(1, depth, room.elevatorCarDepth + 2), Vector3.new(halfW + 0.5, 0, 0) },
		{ Vector3.new(1, depth, room.elevatorCarDepth + 2), Vector3.new(-halfW - 0.5, 0, 0) },
	}
	for _, wall in walls do
		block(
			wall[1] :: Vector3,
			Vector3.new(top.X, centreY, top.Z) + (wall[2] :: Vector3),
			STONE,
			Enum.Material.Rock,
			parent
		).Name =
			"ShaftWall"
	end

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
	for i = 1, ribCount do
		local y = top.Y - i * room.rideShaftRibSpacing
		for _, segment in ribSegments do
			block(segment.size, Vector3.new(top.X, y, top.Z) + segment.offset, TIMBER_DARK, Enum.Material.Wood, parent).Name =
				"ShaftRib"
		end
	end

	block(
		Vector3.new(room.elevatorCarWidth + 2, 2, room.elevatorCarDepth + 2),
		Vector3.new(top.X, top.Y - depth, top.Z),
		STONE,
		Enum.Material.Rock,
		parent
	).Name =
		"ShaftBase"
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

local function buildElevator(origin: Vector3, tierId: number, offset: Vector3, parent: Instance): ElevatorParts
	local room = Config.LobbyRoom
	local position = origin + offset
	local tier = Interfaces.CaveTiers.get(tierId)
	local label = if tier ~= nil then tier.displayName else ("Tier " .. tostring(tierId))
	local carHeight = room.elevatorCarHeight
	local halfW, halfD = room.elevatorCarWidth / 2, room.elevatorCarDepth / 2

	buildShaft(origin, offset, parent)

	-- Everything below is parented to the car model and travels together during the ride.
	local car = Instance.new("Model")
	car.Name = "ElevatorCar_" .. label
	car:SetAttribute(LobbyVisualProtocol.attributes.tierId, tierId)

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
	readoutBacking:SetAttribute(LobbyVisualProtocol.attributes.tierId, tierId)
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

	-- The lever lives inside the car on the east wall, at hand height.
	local leverAnchor =
		block(Vector3.new(0.8, 2.4, 0.8), position + Vector3.new(halfW - 1, 4, 2), IRON, Enum.Material.Metal, car)
	leverAnchor.Name = "Lever"
	local lever = Instance.new("ProximityPrompt")
	lever.ActionText = room.elevatorLeverPromptText
	lever.ObjectText = room.elevatorLeverObjectText
	lever.HoldDuration = 0
	lever.MaxActivationDistance = room.elevatorZoneRadius + 4
	lever.RequiresLineOfSight = false
	lever.Enabled = false
	lever.Parent = leverAnchor

	car.Parent = parent
	CollectionService:AddTag(car, LobbyVisualProtocol.carTag)

	local headerTitle, headerStatus, headerRoster = buildHeader(origin, offset, parent)
	headerTitle.Text = string.upper(label)

	return {
		tierId = tierId,
		car = car,
		restPivot = car:GetPivot(),
		gate = gate,
		lever = lever,
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

-- Arrivals are spread around the spawn point so a full party never stacks inside one another.
function LobbyRoomBuilder.spawnPositionFor(index: number): Vector3
	local spread = Config.LobbyRoom.spawnSpread
	if spread <= 0 then
		return LobbyRoomBuilder.spawnPosition()
	end
	local angle = (index % Config.Run.partyCap) * (2 * math.pi / Config.Run.partyCap)
	return LobbyRoomBuilder.spawnPosition() + Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread)
end

function LobbyRoomBuilder.elevators(): { ElevatorParts }
	return elevatorParts
end

function LobbyRoomBuilder.leaderboardLabel(): TextLabel?
	return leaderboardLabel
end

-- The shop stall's prompt. Exposed rather than answered here so PartyLobbyService (which owns lobby
-- messaging) decides the reply, keeping this file free of gameplay decisions.
function LobbyRoomBuilder.shopPrompt(): ProximityPrompt?
	return shopPrompt
end

-- Every Lamp Network fixture, in config order. Exposed rather than answered here for exactly the
-- same reason as the shop stall: what a purchase costs and whether it is allowed is a gameplay
-- decision, and this file makes none.
function LobbyRoomBuilder.lampFixtures(): { LampParts }
	return lampParts
end

function LobbyRoomBuilder.build()
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
	shopPrompt = buildShop(room.origin, folder)
	lampParts = buildLampLine(room.origin, folder)
	buildWelcome(room.origin, folder)
	buildHowToPlay(room.origin, folder)
	buildVersionSign(room.origin, folder)
	buildLeaderboard(room.origin, folder)

	for _, elevator in room.elevators do
		table.insert(elevatorParts, buildElevator(room.origin, elevator.tierId, elevator.offset, folder))
	end

	-- Roblox picks a SpawnLocation for Player:LoadCharacter; without one every lobby body would
	-- appear at the world origin and be teleported in, one visible frame late.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LandingSpawn"
	spawnLocation.Size = Vector3.new(16, 0.4, 16)
	spawnLocation.Position = LobbyRoomBuilder.spawnPosition() + Vector3.new(0, 0.2, 0)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Color = TIMBER
	spawnLocation.Material = Enum.Material.WoodPlanks
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.BottomSurface = Enum.SurfaceType.Smooth
	spawnLocation.Parent = folder
end

return LobbyRoomBuilder
