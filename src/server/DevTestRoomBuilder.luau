--!strict
-- Builds the PIN terminal in the Landing and the isolated physical enemy-test chamber. This module
-- is deliberately geometry-only: prompts expose fixed action handles, while a server service owns
-- authorization, player state, threat lifecycle and every resulting gameplay mutation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local DevTestBossApproach = require(ReplicatedStorage.Shared.Logic.DevTestBossApproach)

local DevTestRoomBuilder = {}

type ControlBoardDefinition = typeof(Config.DevTestRoom.controls.boards[1])
type GuideBoardDefinition = typeof(Config.DevTestRoom.guide.boards[1])
type GuideEntryDefinition = typeof(Config.DevTestRoom.guide.boards[1].groups[1].entries[1])

export type LurkerSite = {
	cframe: CFrame,
	doorWidth: number,
	doorHeight: number,
	trapSide: "Left" | "Right",
}

-- ONE WALK OUT TO ONE REAL BOSS FLOOR, once built.
--
-- WHAT THIS REPLACED: two types, `Arena` and `ShrineArena`, each describing a Part box with a boss in
-- it — her chamber's centre, her post, her guards' posts, his room's ceiling height. None of that
-- belongs to the laboratory any more. The floors at the far end of these corridors are the real
-- authored ones (`server/DevTestBossFloors`), so the Queen's post comes from `BossFloorPlan.fixtures`
-- through `BossEncounterService` exactly as it does on floor 10, and his dais from
-- `UnlittiusEncounterService` exactly as on floor 20. Neither is the laboratory's business to know.
--
-- What IS the laboratory's business is the walk: a corridor, a button, and where the two rooms meet.
export type BossApproach = {
	id: string,
	definition: any,
	-- The authored plan the corridor was solved against, carried through rather than re-planned by
	-- the service: two calls to `planFor` would agree today and are one config edit away from not.
	plan: Types.FloorPlan,
	approach: DevTestBossApproach.Approach,
	startPrompt: ProximityPrompt,
	-- The corridor as a containment box: centre at the FLOOR, height measured up from it, matching
	-- `DevTestRoomRules.isInsideRoom`.
	corridorCenter: Vector3,
	corridorSize: Vector3,
}

export type Runtime = {
	accessModel: Model,
	accessPrompt: ProximityPrompt,
	roomModel: Model,
	groundPart: BasePart,
	dynamicFolder: Folder,
	actionPrompts: { [string]: ProximityPrompt },
	roomCenter: Vector3,
	candleSpawnPosition: Vector3,
	threatSpawnPosition: Vector3,
	knotwalkerSpawnPosition: Vector3,
	noisePosition: Vector3,
	wardenSpawnCFrame: CFrame,
	wardenWaxPosition: Vector3,
	lurkerSites: { LurkerSite },
	hazardAnchorCFrame: CFrame,
	hazardImpactPosition: Vector3,
	lobbyReturnPosition: Vector3,
	-- One per authored boss floor, in `Config.DevTestRoom.bossFloors.definitions` order. Empty only
	-- if a floor was configured somewhere the corridor could not physically reach.
	bossApproaches: { BossApproach },
}

local cached: Runtime? = nil

local function flatDirection(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.001 then flat.Unit else Vector3.new(0, 0, -1)
end

local function frameFacing(position: Vector3, direction: Vector3): CFrame
	local facing = flatDirection(direction)
	return CFrame.lookAt(position, position + facing)
end

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = cframe
	created.Color = color
	created.Material = material
	created.Anchored = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

local function surface(part_: BasePart, face: Enum.NormalId, canvasSize: Vector2?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = face
	gui.CanvasSize = canvasSize or Config.DevTestRoom.ui.canvasSize
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part_
	return gui
end

local function label(
	parent: Instance,
	text: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	textSize: number,
	font: Enum.Font
): TextLabel
	local created = Instance.new("TextLabel")
	created.Name = "Label"
	created.Position = position
	created.Size = size
	created.BackgroundTransparency = 1
	created.Font = font
	created.Text = text
	created.TextColor3 = color
	created.TextSize = textSize
	created.TextScaled = false
	created.TextWrapped = true
	created.TextXAlignment = Enum.TextXAlignment.Center
	created.TextYAlignment = Enum.TextYAlignment.Center
	created.Parent = parent
	return created
end

local function prompt(
	parent: Instance,
	name: string,
	actionText: string,
	objectText: string,
	distance: number,
	holdSeconds: number
): ProximityPrompt
	local created = Instance.new("ProximityPrompt")
	created.Name = name
	created.ActionText = actionText
	created.ObjectText = objectText
	created.MaxActivationDistance = distance
	created.HoldDuration = holdSeconds
	created.RequiresLineOfSight = true
	created.Parent = parent
	return created
end

local function buildAccessTerminal(): (Model, ProximityPrompt)
	local cfg = Config.DevTestRoom
	local access = cfg.access
	local palette = cfg.palette
	local ground = Config.LobbyRoom.origin + access.localOffset
	local root = frameFacing(ground, access.facing)

	local model = Instance.new("Model")
	model.Name = "WickDevTestAccessTerminal"

	local base = part(
		"Base",
		access.baseSize,
		root * CFrame.new(0, access.baseSize.Y / 2, 0),
		palette.trim,
		Enum.Material.Slate,
		model
	)
	part(
		"Pedestal",
		access.pedestalSize,
		root * CFrame.new(0, access.baseSize.Y + access.pedestalSize.Y / 2, 0),
		palette.metal,
		Enum.Material.Metal,
		model
	)
	local screen = part(
		"Screen",
		access.screenSize,
		root * CFrame.new(0, access.screenCenterHeight, -access.screenForwardOffset),
		palette.panel,
		Enum.Material.SmoothPlastic,
		model
	)
	local gui = surface(screen, Enum.NormalId.Front)
	label(
		gui,
		access.title,
		UDim2.fromScale(0.05, 0.08),
		UDim2.fromScale(0.9, 0.43),
		palette.text,
		cfg.ui.titleTextSize,
		Enum.Font.GothamBold
	)
	label(
		gui,
		string.format(access.codeFormat, Config.Diagnostics.unlockCode),
		UDim2.fromScale(0.05, 0.54),
		UDim2.fromScale(0.9, 0.3),
		palette.accent,
		cfg.ui.bodyTextSize,
		Enum.Font.Code
	)

	local accessPrompt = prompt(
		screen,
		"DevTestAccessPrompt",
		access.promptActionText,
		access.promptObjectText,
		access.promptDistance,
		access.promptHoldSeconds
	)
	model.PrimaryPart = base
	model.Parent = workspace
	return model, accessPrompt
end

-- A doorway punched through one wall of a shell: how far along that wall it sits, and how big it is.
type Doorway = {
	offset: number,
	width: number,
	height: number,
}

-- ONE WALL, optionally with a hole in it. Built as up to three parts — the run either side of the
-- opening and a lintel over it — so the same helper raises a plain wall and a wall you can walk
-- through, and the laboratory's east wall and the arena's entry wall cannot drift apart.
--
-- `wallCenter` is the middle of the wall at FLOOR level; the parts are raised from there.
local function buildWall(
	model: Model,
	name: string,
	wallCenter: Vector3,
	spanAlongZ: boolean,
	span: number,
	height: number,
	thickness: number,
	color: Color3,
	doorway: Doorway?
)
	local function slab(suffix: string, sectionSpan: number, alongOffset: number, sectionHeight: number, baseY: number)
		if sectionSpan <= 0 or sectionHeight <= 0 then
			return
		end
		local size = if spanAlongZ
			then Vector3.new(thickness, sectionHeight, sectionSpan)
			else Vector3.new(sectionSpan, sectionHeight, thickness)
		local offset = if spanAlongZ
			then Vector3.new(0, baseY + sectionHeight / 2, alongOffset)
			else Vector3.new(alongOffset, baseY + sectionHeight / 2, 0)
		part(name .. suffix, size, CFrame.new(wallCenter + offset), color, Enum.Material.Slate, model)
	end

	if doorway == nil then
		slab("", span, 0, height, 0)
		return
	end

	local openingHalf = math.max(doorway.width, 0) / 2
	local openingHeight = math.clamp(doorway.height, 0, height)
	local lowEdge = -span / 2
	local highEdge = span / 2
	local lowSpan = (doorway.offset - openingHalf) - lowEdge
	local highSpan = highEdge - (doorway.offset + openingHalf)
	slab("Low", lowSpan, lowEdge + lowSpan / 2, height, 0)
	slab("High", highSpan, highEdge - highSpan / 2, height, 0)
	-- The lintel spans the opening only; the runs either side are full height, so this is what keeps the
	-- wall solid above head level rather than leaving a slot to the ceiling.
	slab("Lintel", openingHalf * 2, doorway.offset, height - openingHeight, openingHeight)
end

-- A closed box of floor, ceiling and four walls, with an optional doorway in any one of them.
-- Returns the floor part, which is what everything downstream seats on.
local function buildBoxShell(
	model: Model,
	center: Vector3,
	interiorSize: Vector3,
	floorThickness: number,
	ceilingThickness: number,
	wallThickness: number,
	doorways: { [string]: Doorway }
): BasePart
	local palette = Config.DevTestRoom.palette
	local width = interiorSize.X
	local height = interiorSize.Y
	local depth = interiorSize.Z
	local wall = wallThickness

	local floor = part(
		"Floor",
		Vector3.new(width + wall * 2, floorThickness, depth + wall * 2),
		CFrame.new(center + Vector3.new(0, -floorThickness / 2, 0)),
		palette.floor,
		Enum.Material.Slate,
		model
	)
	part(
		"Ceiling",
		Vector3.new(width + wall * 2, ceilingThickness, depth + wall * 2),
		CFrame.new(center + Vector3.new(0, height + ceilingThickness / 2, 0)),
		palette.wall,
		Enum.Material.Slate,
		model
	)
	-- North and south run the full outer width so they cap the ends of the east and west walls, exactly
	-- as this shell has always been built.
	--
	-- NORTH IS -Z AND SOUTH IS +Z, matching `Logic/DoorwayGeometry.NORMAL` and therefore the whole rest
	-- of the game. THIS FILE USED TO HAVE THEM THE OTHER WAY AROUND — "NorthWall" was built at +Z — and
	-- because the only doorway anybody had ever punched through this shell was an EAST one, nothing ever
	-- noticed. The first time a second arena was added off the -Z wall, the opening was placed on the
	-- far side of the room from its own corridor, which is a room you cannot reach and cannot see: the
	-- arena, its corridor, its sign and its start button were all built correctly and were all behind a
	-- solid wall.
	--
	-- Fixed here rather than worked around at the call site, because a builder whose compass disagrees
	-- with the game's compass will keep producing that bug for whoever adds the third arena.
	buildWall(
		model,
		"WestWall",
		center + Vector3.new(-(width + wall) / 2, 0, 0),
		true,
		depth,
		height,
		wall,
		palette.wall,
		doorways.West
	)
	buildWall(
		model,
		"EastWall",
		center + Vector3.new((width + wall) / 2, 0, 0),
		true,
		depth,
		height,
		wall,
		palette.wall,
		doorways.East
	)
	buildWall(
		model,
		"NorthWall",
		center + Vector3.new(0, 0, -(depth + wall) / 2),
		false,
		width + wall * 2,
		height,
		wall,
		palette.wall,
		doorways.North
	)
	buildWall(
		model,
		"SouthWall",
		center + Vector3.new(0, 0, (depth + wall) / 2),
		false,
		width + wall * 2,
		height,
		wall,
		palette.wall,
		doorways.South
	)
	return floor
end

-- The laboratory's own box, with one opening per boss floor cut into whichever wall faces it.
--
-- NOT ONE OF THOSE OPENINGS IS AUTHORED ANY MORE, and that is the fix for the bug this room kept
-- having. Which wall, where along it, how wide and how tall all come from the solved approach, which
-- got them from the doorway `FloorBuilder` is about to roll in the boss floor's entry room. Before
-- this the pair were authored twice — once here and once beside the corridor — and the two disagreed
-- in three different ways across two revisions: an east opening whose corridor left from the north, a
-- 26-stud corridor feeding a 28-stud door, and a north wall with no opening in it at all behind which
-- a whole second arena sat unreachable. All three built without a warning.
local function buildRoomShell(model: Model, roomCenter: Vector3, approaches: { DevTestBossApproach.Approach }): BasePart
	local room = Config.DevTestRoom.room
	local doorways: { [string]: Doorway } = {}
	for _, approach in approaches do
		-- The opening is as wide as the corridor rather than as wide as the boss floor's own doorway,
		-- because it is the CORRIDOR that has to pass through this wall. The corridor is already at
		-- least as wide as that doorway (`DevTestBossApproach.solve`), so the walk never narrows.
		doorways[approach.labWall] = {
			offset = approach.labDoorwayOffset,
			width = approach.corridorWidth,
			height = approach.corridorHeight,
		}
	end
	return buildBoxShell(
		model,
		roomCenter,
		room.interiorSize,
		room.floorThickness,
		room.ceilingThickness,
		room.wallThickness,
		doorways
	)
end

local function buildRouteArch(model: Model, center: Vector3, alongX: boolean, index: number)
	local room = Config.DevTestRoom.room
	local width = Config.Floors.geometry.cellSize
	local height = room.interiorSize.Y
	local wall = room.wallThickness
	local openingWidth = math.clamp(room.routeOpeningWidth, 0, width)
	local openingHeight = math.clamp(room.routeOpeningHeight, 0, height)
	local sideWidth = (width - openingWidth) / 2
	if sideWidth > 0 then
		local sideOffset = openingWidth / 2 + sideWidth / 2
		for side, offset in { -sideOffset, sideOffset } do
			part(
				string.format("RouteArch%dPost%d", index, side),
				if alongX
					then Vector3.new(sideWidth, openingHeight, wall)
					else Vector3.new(wall, openingHeight, sideWidth),
				CFrame.new(
					center
						+ if alongX
							then Vector3.new(offset, openingHeight / 2, 0)
							else Vector3.new(0, openingHeight / 2, offset)
				),
				Config.DevTestRoom.palette.trim,
				Enum.Material.Slate,
				model
			)
		end
	end
	local lintelHeight = height - openingHeight
	if lintelHeight > 0 then
		part(
			"RouteArch" .. tostring(index) .. "Lintel",
			if alongX then Vector3.new(width, lintelHeight, wall) else Vector3.new(wall, lintelHeight, width),
			CFrame.new(center + Vector3.new(0, openingHeight + lintelHeight / 2, 0)),
			Config.DevTestRoom.palette.trim,
			Enum.Material.Slate,
			model
		)
	end
end

local function buildRouteDividers(model: Model, roomCenter: Vector3)
	-- Four broad arches form a single cross-shaped divider and the same 2x2 cycle RoomNavigation
	-- receives. Each opening covers every deterministic Stone/Moss/Ice doorway offset, so changing a
	-- signature enemy's family presentation cannot make its real waypoint hit solid trim.
	local halfCell = Config.Floors.geometry.cellSize / 2
	buildRouteArch(model, roomCenter + Vector3.new(-halfCell, 0, 0), true, 1)
	buildRouteArch(model, roomCenter + Vector3.new(halfCell, 0, 0), true, 2)
	buildRouteArch(model, roomCenter + Vector3.new(0, 0, -halfCell), false, 3)
	buildRouteArch(model, roomCenter + Vector3.new(0, 0, halfCell), false, 4)
end

local function buildMarker(parent: Instance, position: Vector3, color: Color3, text: string)
	local cfg = Config.DevTestRoom
	local marker = part(
		text:gsub("%s+", "") .. "Marker",
		cfg.markers.size,
		CFrame.new(position + Vector3.new(0, cfg.markers.size.Y / 2, 0)),
		color,
		Enum.Material.Neon,
		parent
	)
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 0.55
	local gui = surface(marker, Enum.NormalId.Top)
	label(
		gui,
		text,
		UDim2.fromScale(0.04, 0.05),
		UDim2.fromScale(0.92, 0.9),
		Config.DevTestRoom.palette.text,
		cfg.ui.bodyTextSize,
		Enum.Font.GothamBold
	)
end

local function buildLurkerArches(parent: Instance, roomCenter: Vector3): { LurkerSite }
	local cfg = Config.DevTestRoom
	local lurker = cfg.lurker
	local palette = cfg.palette
	local sites: { LurkerSite } = {}
	for index, definition in lurker.sites do
		local position = roomCenter + definition.localPosition
		local siteFrame = frameFacing(position, definition.facing)
		local postX = lurker.openingWidth / 2 + lurker.postSize.X / 2
		for _, side in { -1, 1 } do
			part(
				"LurkerArchPost" .. tostring(index),
				lurker.postSize,
				siteFrame * CFrame.new(postX * side, lurker.postSize.Y / 2, 0),
				palette.trim,
				Enum.Material.Slate,
				parent
			)
		end
		part(
			"LurkerArchLintel" .. tostring(index),
			Vector3.new(lurker.openingWidth + lurker.postSize.X * 2, lurker.lintelHeight, lurker.postSize.Z),
			siteFrame * CFrame.new(0, lurker.openingHeight + lurker.lintelHeight / 2, 0),
			palette.trim,
			Enum.Material.Slate,
			parent
		)
		table.insert(sites, {
			cframe = siteFrame,
			doorWidth = lurker.openingWidth,
			doorHeight = lurker.openingHeight,
			trapSide = definition.trapSide,
		})
	end
	return sites
end

local function totalControlColumns(boardDefinition: ControlBoardDefinition): number
	local total = 0
	for _, group in boardDefinition.groups do
		total += math.max(1, math.floor(group.columns))
	end
	return math.max(1, total)
end

local function groupHeader(
	parent: Instance,
	boardSize: Vector3,
	firstX: number,
	spacingX: number,
	startColumn: number,
	columns: number,
	text: string,
	color: Color3,
	textSize: number
)
	local centerX = firstX + (startColumn + (columns - 1) / 2) * spacingX
	local width = math.min(0.96, math.max(0.08, columns * spacingX / boardSize.X))
	label(
		parent,
		text,
		UDim2.fromScale(0.5 + centerX / boardSize.X - width / 2, 0.19),
		UDim2.fromScale(width, 0.14),
		color,
		textSize,
		Enum.Font.GothamBold
	)
end

local function groupDivider(parent: Instance, xScale: number, color: Color3)
	local divider = Instance.new("Frame")
	divider.Name = "GroupDivider"
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.Position = UDim2.fromScale(xScale, 0.2)
	divider.Size = UDim2.new(0, 2, 0.75, 0)
	divider.BackgroundColor3 = color
	divider.BackgroundTransparency = 0.62
	divider.BorderSizePixel = 0
	divider.Parent = parent
end

local function buildControlBoard(
	parent: Instance,
	roomCenter: Vector3,
	boardDefinition: ControlBoardDefinition,
	actionPrompts: { [string]: ProximityPrompt }
)
	local cfg = Config.DevTestRoom
	local controls = cfg.controls
	local palette = cfg.palette
	local boardPosition = roomCenter + boardDefinition.localPosition
	local boardFrame = frameFacing(boardPosition, boardDefinition.facing)
	local board = part(
		"ControlBoard_" .. boardDefinition.id,
		boardDefinition.size,
		boardFrame,
		palette.panel,
		Enum.Material.Metal,
		parent
	)
	local boardGui = surface(board, Enum.NormalId.Front, boardDefinition.canvasSize)
	label(
		boardGui,
		boardDefinition.title,
		UDim2.fromScale(0.03, 0.025),
		UDim2.fromScale(0.94, 0.14),
		palette.text,
		cfg.ui.controlTitleTextSize,
		Enum.Font.GothamBold
	)

	-- The button face's canvas is derived from the button's real size rather than fixed, so a change to
	-- `buttonSize` moves the panel and leaves its lettering at the same physical height on the wall.
	local buttonCanvas = Vector2.new(
		math.round(controls.buttonSize.X * controls.buttonCanvasPixelsPerStud),
		math.round(controls.buttonSize.Y * controls.buttonCanvasPixelsPerStud)
	)
	local totalColumns = totalControlColumns(boardDefinition)
	local firstX = -(totalColumns - 1) * controls.buttonSpacing.X / 2
	local firstY = boardDefinition.size.Y / 2 - controls.buttonTopInset
	local front = (boardDefinition.size.Z + controls.buttonSize.Z) / 2 + controls.buttonForwardGap
	local globalColumn = 0
	for groupIndex, group in boardDefinition.groups do
		local columns = math.max(1, math.floor(group.columns))
		local rows = math.ceil(#group.definitions / columns)
		if rows > boardDefinition.maxRows then
			error(
				string.format(
					"DevTestRoom control group %s exceeds its %d-row board",
					group.id,
					boardDefinition.maxRows
				)
			)
		end
		groupHeader(
			boardGui,
			boardDefinition.size,
			firstX,
			controls.buttonSpacing.X,
			globalColumn,
			columns,
			group.label,
			group.color,
			cfg.ui.controlGroupTextSize
		)
		for index, definition in group.definitions do
			local column = (index - 1) % columns
			local row = math.floor((index - 1) / columns)
			local x = firstX + (globalColumn + column) * controls.buttonSpacing.X
			local y = firstY - row * controls.buttonSpacing.Y
			local button = part(
				"Control_" .. definition.actionId:gsub("[^%w]", "_"),
				controls.buttonSize,
				-- THE X IS NEGATED, AND IT HAS TO BE. Everything else on this board — the title, the
				-- group headers, the dividers — is drawn on the board's SurfaceGui, which sits on the
				-- FRONT face (local -Z). Looking at that face, the board's local +X runs to the viewer's
				-- LEFT, so canvas X and local X point in opposite directions.
				--
				-- The headers convert their column position into canvas scale and the buttons are real
				-- parts placed in local space, so sharing one `firstX + column * spacing` progression
				-- between them silently MIRRORS the buttons against their own headers: with five groups
				-- the shared roster rendered under "ICE" and the ice roster under "ALL CAVES". Each
				-- button still carried its own correct label and action — only the grouping lied, which
				-- is why this survived so long.
				boardFrame * CFrame.new(-x, y, -front),
				definition.color,
				Enum.Material.SmoothPlastic,
				parent
			)
			button.CanCollide = false
			button:SetAttribute("WickDevTestAction", definition.actionId)
			local buttonGui = surface(button, Enum.NormalId.Front, buttonCanvas)
			label(
				buttonGui,
				definition.label,
				UDim2.fromScale(0.04, 0.08),
				UDim2.fromScale(0.92, 0.84),
				palette.text,
				cfg.ui.buttonTextSize,
				Enum.Font.GothamBold
			)
			local controlPrompt = prompt(
				button,
				"DevTestActionPrompt",
				controls.promptActionText,
				definition.label,
				controls.promptDistance,
				controls.promptHoldSeconds
			)
			controlPrompt:SetAttribute("WickDevTestAction", definition.actionId)
			if actionPrompts[definition.actionId] ~= nil then
				error("Duplicate DevTestRoom action id: " .. definition.actionId)
			end
			actionPrompts[definition.actionId] = controlPrompt
		end
		globalColumn += columns
		if groupIndex < #boardDefinition.groups then
			local boundaryX = firstX + (globalColumn - 0.5) * controls.buttonSpacing.X
			groupDivider(boardGui, 0.5 + boundaryX / boardDefinition.size.X, palette.trim)
		end
	end
end

local function buildControls(parent: Instance, roomCenter: Vector3): { [string]: ProximityPrompt }
	local actionPrompts: { [string]: ProximityPrompt } = {}
	for _, boardDefinition in Config.DevTestRoom.controls.boards do
		buildControlBoard(parent, roomCenter, boardDefinition, actionPrompts)
	end
	return actionPrompts
end

local function guideCard(parent: Instance, entry: GuideEntryDefinition, position: UDim2, size: UDim2)
	local cfg = Config.DevTestRoom
	local palette = cfg.palette
	local card = Instance.new("Frame")
	card.Name = "GuideCard_" .. entry.entityId
	card.Position = position
	card.Size = size
	card.BackgroundColor3 = palette.metal
	card.BackgroundTransparency = 0.22
	card.BorderSizePixel = 0
	card.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = entry.color
	stroke.Thickness = 2
	stroke.Transparency = 0.42
	stroke.Parent = card

	local nameLabel = label(
		card,
		entry.name,
		UDim2.fromScale(0.035, 0.025),
		UDim2.fromScale(0.93, 0.17),
		entry.color,
		cfg.ui.guideNameTextSize,
		Enum.Font.GothamBold
	)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	local badgeLabel = label(
		card,
		entry.badge,
		UDim2.fromScale(0.035, 0.19),
		UDim2.fromScale(0.93, 0.12),
		palette.mutedText,
		cfg.ui.guideBadgeTextSize,
		Enum.Font.Code
	)
	badgeLabel.TextXAlignment = Enum.TextXAlignment.Left
	local descriptionLabel = label(
		card,
		entry.description,
		UDim2.fromScale(0.035, 0.32),
		UDim2.fromScale(0.93, 0.36),
		palette.text,
		cfg.ui.guideBodyTextSize,
		Enum.Font.Gotham
	)
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	local hintLabel = label(
		card,
		entry.testHint,
		UDim2.fromScale(0.035, 0.7),
		UDim2.fromScale(0.93, 0.27),
		entry.color,
		cfg.ui.guideHintTextSize,
		Enum.Font.GothamBold
	)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.TextYAlignment = Enum.TextYAlignment.Top
end

local function buildGuideBoard(parent: Instance, roomCenter: Vector3, boardDefinition: GuideBoardDefinition)
	local cfg = Config.DevTestRoom
	local palette = cfg.palette
	local boardFrame = frameFacing(roomCenter + boardDefinition.localPosition, boardDefinition.facing)
	local board = part(
		"GuideBoard_" .. boardDefinition.id,
		boardDefinition.size,
		boardFrame,
		palette.panel,
		Enum.Material.Metal,
		parent
	)
	local boardGui = surface(board, Enum.NormalId.Front, boardDefinition.canvasSize)
	label(
		boardGui,
		boardDefinition.title,
		UDim2.fromScale(0.025, 0.02),
		UDim2.fromScale(0.95, 0.1),
		palette.text,
		cfg.ui.guideTitleTextSize,
		Enum.Font.GothamBold
	)

	local totalColumns = 0
	for _, group in boardDefinition.groups do
		totalColumns += math.max(1, math.floor(group.columns))
	end
	totalColumns = math.max(1, totalColumns)
	local outerX = 0.025
	local columnGap = 0.012
	local usableWidth = 0.95 - columnGap * (totalColumns - 1)
	local columnWidth = usableWidth / totalColumns
	local contentTop = 0.24
	local contentHeight = 0.735
	local rowGap = 0.016
	local startColumn = 0
	for _, group in boardDefinition.groups do
		local columns = math.max(1, math.floor(group.columns))
		local rows = math.max(1, math.ceil(#group.entries / columns))
		local headerX = outerX + startColumn * (columnWidth + columnGap)
		local headerWidth = columnWidth * columns + columnGap * (columns - 1)
		label(
			boardGui,
			group.label,
			UDim2.fromScale(headerX, 0.12),
			UDim2.fromScale(headerWidth, 0.1),
			group.color,
			cfg.ui.guideGroupTextSize,
			Enum.Font.GothamBold
		)
		local cardHeight = (contentHeight - rowGap * (rows - 1)) / rows
		for index, entry in group.entries do
			local localColumn = (index - 1) % columns
			local row = math.floor((index - 1) / columns)
			local x = outerX + (startColumn + localColumn) * (columnWidth + columnGap)
			local y = contentTop + row * (cardHeight + rowGap)
			guideCard(boardGui, entry, UDim2.fromScale(x, y), UDim2.fromScale(columnWidth, cardHeight))
		end
		startColumn += columns
	end
end

local function buildGuideBoards(parent: Instance, roomCenter: Vector3)
	for _, boardDefinition in Config.DevTestRoom.guide.boards do
		buildGuideBoard(parent, roomCenter, boardDefinition)
	end
end

local function buildLighting(parent: Instance, roomCenter: Vector3)
	local cfg = Config.DevTestRoom
	local room = cfg.room
	for index, localOffset in cfg.lighting.localOffsets do
		local position = roomCenter
			+ Vector3.new(localOffset.X, room.interiorSize.Y - cfg.lighting.fixtureSize.Y / 2, localOffset.Z)
		local fixture = part(
			"CeilingLight" .. tostring(index),
			cfg.lighting.fixtureSize,
			CFrame.new(position),
			cfg.palette.light,
			Enum.Material.Neon,
			parent
		)
		fixture.CanCollide = false
		fixture.CanQuery = false
		fixture.CanTouch = false
		local light = Instance.new("PointLight")
		light.Color = cfg.palette.light
		light.Range = cfg.lighting.range
		light.Brightness = cfg.lighting.brightness
		light.Shadows = false
		light.Parent = fixture
	end
end

-- ONE CORRIDOR OUT TO ONE REAL BOSS FLOOR, and the plaque and button on the way.
--
-- WHAT THIS REPLACED. Two near-identical functions, one per arena, each building a Part corridor and
-- then a Part box for the fight to happen in — a 96-cube for her and a 64-cube for him — from twelve
-- authored numbers apiece. Both boxes are gone: the floors at the end of these corridors are the real
-- ones, carved by `server/FloorBuilder` from the same authored plans an expedition gets on floors 10
-- and 20 (server/DevTestBossFloors). All that is left to build here is the walk.
--
-- AND THE WALK IS ENTIRELY DERIVED. `Logic/DevTestBossApproach` has already solved where the floor's
-- entry doorway landed, how wide it rolled, which laboratory wall faces it and how far apart the two
-- are; this function only turns that answer into parts. Nothing below chooses a position. That is the
-- whole defence against the failure this room kept having — a corridor two studs narrower than its
-- doorway, an opening on the wrong wall, an arena with no way in at all — none of which throws, and
-- all of which builds perfectly.
local function buildBossApproach(
	model: Model,
	plan: Types.FloorPlan,
	approach: DevTestBossApproach.Approach,
	definition: any
): BossApproach
	local cfg = Config.DevTestRoom
	local floors = cfg.bossFloors
	local palette = cfg.palette

	local folder = Instance.new("Folder")
	folder.Name = "BossApproach_" .. definition.id
	folder.Parent = model

	local outward = approach.outward
	local lateral = Vector3.new(math.abs(outward.Z), 0, math.abs(outward.X))
	local center = approach.corridorCenter
	local size = approach.corridorSize
	local width = approach.corridorWidth
	local height = approach.corridorHeight
	local length = approach.corridorLength

	-- Floor, ceiling and both side walls. The two ENDS are deliberately open: one is the hole in the
	-- laboratory's own wall and the other is the doorway cut in the entry room, and putting a slab
	-- across either is how you get a corridor to nowhere.
	local slabFootprint = lateral * (width + floors.wallThickness * 2)
		+ Vector3.new(math.abs(outward.X) * length, 0, math.abs(outward.Z) * length)
	part(
		"BossCorridorFloor_" .. definition.id,
		slabFootprint + Vector3.new(0, floors.floorThickness, 0),
		CFrame.new(Vector3.new(center.X, approach.entrancePosition.Y - floors.floorThickness / 2, center.Z)),
		palette.floor,
		Enum.Material.Slate,
		folder
	)
	part(
		"BossCorridorCeiling_" .. definition.id,
		slabFootprint + Vector3.new(0, floors.ceilingThickness, 0),
		CFrame.new(Vector3.new(center.X, approach.entrancePosition.Y + height + floors.ceilingThickness / 2, center.Z)),
		palette.wall,
		Enum.Material.Slate,
		folder
	)
	for _, side in { -1, 1 } do
		part(
			string.format("BossCorridorWall%d_%s", side, definition.id),
			lateral * floors.wallThickness
				+ Vector3.new(math.abs(outward.X) * length, 0, math.abs(outward.Z) * length)
				+ Vector3.new(0, height, 0),
			CFrame.new(center + lateral * (side * (width + floors.wallThickness) / 2)),
			palette.wall,
			Enum.Material.Slate,
			folder
		)
	end

	-- THE PLAQUE AND THE BUTTON, on one side wall a short way back from the mouth of the floor. The
	-- last thing you read before the room stops being a room.
	local plaqueCenter = approach.entrancePosition
		+ outward * floors.plaqueInsetFromFloor
		+ lateral * (floors.plaqueSide * width / 2)
	-- Facing ACROSS the corridor, back toward the opposite wall, so both read square-on to somebody
	-- walking past rather than edge-on to somebody walking at them.
	local facing = lateral * -floors.plaqueSide

	local signPosition = plaqueCenter + Vector3.new(0, floors.signHeight, 0) + facing * (floors.signSize.Z / 2)
	local sign = part(
		"BossApproachSign_" .. definition.id,
		Vector3.new(floors.signSize.X, floors.signSize.Y, floors.signSize.Z),
		CFrame.lookAt(signPosition, signPosition + facing),
		palette.panel,
		Enum.Material.Metal,
		folder
	)
	sign.CanCollide = false
	local signGui = surface(sign, Enum.NormalId.Front, floors.signCanvasSize)
	label(
		signGui,
		definition.title,
		UDim2.fromScale(0.03, 0.06),
		UDim2.fromScale(0.94, 0.4),
		palette.text,
		cfg.ui.titleTextSize,
		Enum.Font.GothamBold
	)
	label(
		signGui,
		definition.subtitle,
		UDim2.fromScale(0.03, 0.48),
		UDim2.fromScale(0.94, 0.44),
		palette.mutedText,
		cfg.ui.bodyTextSize,
		Enum.Font.Gotham
	)

	local buttonPosition = plaqueCenter
		+ Vector3.new(0, floors.startButtonHeight, 0)
		+ facing * (floors.startButtonSize.Z / 2)
	local button = part(
		"BossApproachStart_" .. definition.id,
		floors.startButtonSize,
		CFrame.lookAt(buttonPosition, buttonPosition + facing),
		definition.startButtonColor,
		Enum.Material.SmoothPlastic,
		folder
	)
	button.CanCollide = false
	local buttonGui = surface(
		button,
		Enum.NormalId.Front,
		Vector2.new(
			math.round(floors.startButtonSize.X * cfg.controls.buttonCanvasPixelsPerStud),
			math.round(floors.startButtonSize.Y * cfg.controls.buttonCanvasPixelsPerStud)
		)
	)
	label(
		buttonGui,
		definition.startButtonLabel,
		UDim2.fromScale(0.04, 0.08),
		UDim2.fromScale(0.92, 0.84),
		palette.text,
		cfg.ui.buttonTextSize,
		Enum.Font.GothamBold
	)
	local startPrompt = prompt(
		button,
		"DevTestBossStartPrompt_" .. definition.id,
		floors.promptActionText,
		definition.promptObjectText,
		floors.promptDistance,
		floors.promptHoldSeconds
	)

	-- LIGHT IN THE CORRIDOR AND NOT ONE LUMEN PAST IT. A WICK floor is dark; that is the whole game,
	-- and a boss floor lit by fixtures the shipped one does not have would answer none of the
	-- questions a designer walks out here to ask. This gets you to the button. Your candle does the
	-- rest.
	local lightCount = math.max(1, math.floor(length / floors.lightingSpacing))
	for index = 1, lightCount do
		local along = (index - 0.5) / lightCount
		local position = approach.entrancePosition
			+ outward * (length * along)
			+ Vector3.new(0, height - cfg.lighting.fixtureSize.Y / 2, 0)
		local fixture = part(
			string.format("BossCorridorLight%d_%s", index, definition.id),
			cfg.lighting.fixtureSize,
			CFrame.new(position),
			palette.light,
			Enum.Material.Neon,
			folder
		)
		fixture.CanCollide = false
		fixture.CanQuery = false
		fixture.CanTouch = false
		local light = Instance.new("PointLight")
		light.Color = palette.light
		light.Range = floors.lightingRange
		light.Brightness = floors.lightingBrightness
		light.Shadows = false
		light.Parent = fixture
	end

	return {
		id = definition.id,
		definition = definition,
		plan = plan,
		approach = approach,
		startPrompt = startPrompt,
		-- AT THE FLOOR, not at the middle of the tube. This one is read by the laboratory's
		-- containment check, which measures a box's height upward from its centre
		-- (`DevTestRoomRules.isInsideRoom`); the mid-height centre above is what the PARTS were placed
		-- from, and handing the same vector to both is how half a corridor ends up out of bounds.
		corridorCenter = Vector3.new(center.X, approach.entrancePosition.Y, center.Z),
		corridorSize = size,
	}
end

local function buildRoom(): (
	Model,
	BasePart,
	Folder,
	{ [string]: ProximityPrompt },
	Vector3,
	Vector3,
	Vector3,
	Vector3,
	CFrame,
	Vector3,
	{ LurkerSite },
	CFrame,
	Vector3,
	Vector3,
	{ BossApproach }
)
	local cfg = Config.DevTestRoom
	local room = cfg.room
	local roomCenter = Config.LobbyRoom.origin + room.offsetFromLobby
	local candlePosition = roomCenter + room.candleLocalPosition
	local threatPosition = roomCenter + room.threatLocalPosition
	local knotwalkerPosition = roomCenter + room.knotwalkerSpawnLocalPosition
	local knotwalkerRoutePosition = roomCenter + room.knotwalkerRouteLocalPosition
	local noisePosition = roomCenter + room.noiseLocalPosition
	local wardenPosition = roomCenter + room.wardenLocalPosition
	local wardenWaxPosition = roomCenter + room.wardenWaxLocalPosition
	local hazardImpact = roomCenter + room.hazardLocalPosition
	local hazardAnchor = hazardImpact + Vector3.new(0, room.interiorSize.Y, 0)

	-- THE BOSS FLOORS ARE SOLVED BEFORE A SINGLE WALL GOES UP, because the laboratory's own openings
	-- are cut from the answer. Pure arithmetic — no Instance is touched by any of this — so a floor
	-- that cannot be reached from where it was configured reports itself here and is simply left out,
	-- rather than punching a hole in a wall that leads nowhere.
	--
	-- SOLVED WITH THE SESSION'S FAMILY, not the armed-cave selector. The two floors are carved once
	-- when the laboratory is built and the selector changes at runtime; re-dressing a carved floor
	-- would mean re-carving it, and a designer who wants to see his shrine in Ice can arm Ice and
	-- reopen the lab. Their doorway rolls read the family too, so this also keeps the two openings in
	-- the laboratory's walls fixed for the life of the room.
	local approaches: { DevTestBossApproach.Approach } = {}
	local approachPlans: { Types.FloorPlan } = {}
	local approachDefinitions: { any } = {}
	for _, definition in cfg.bossFloors.definitions do
		local plan, approach =
			DevTestBossApproach.forDefinition(definition, roomCenter, cfg.session.familyId, cfg.session.depth)
		if plan == nil or approach == nil then
			warn(
				string.format(
					"[WICK] dev boss floor %q cannot be reached from the laboratory at its configured origin; skipped",
					definition.id
				)
			)
			continue
		end
		table.insert(approaches, approach)
		table.insert(approachPlans, plan)
		table.insert(approachDefinitions, definition)
	end

	local model = Instance.new("Model")
	model.Name = "WickDevTestRoom"
	local floor = buildRoomShell(model, roomCenter, approaches)
	buildRouteDividers(model, roomCenter)
	model.PrimaryPart = floor

	local staticFolder = Instance.new("Folder")
	staticFolder.Name = "StaticFixtures"
	staticFolder.Parent = model
	local dynamicFolder = Instance.new("Folder")
	dynamicFolder.Name = "DynamicContent"
	dynamicFolder.Parent = model

	buildMarker(staticFolder, candlePosition, cfg.palette.candleMarker, cfg.markers.candleLabel)
	buildMarker(staticFolder, threatPosition, cfg.palette.threatMarker, cfg.markers.threatLabel)
	buildMarker(staticFolder, knotwalkerPosition, cfg.palette.threatMarker, cfg.markers.knotwalkerLabel)
	buildMarker(staticFolder, knotwalkerRoutePosition, cfg.palette.candleMarker, cfg.markers.knotwalkerRouteLabel)
	-- The bay opening the creature will string its wire across. See knotwalkerTrapLocalPosition.
	buildMarker(
		staticFolder,
		roomCenter + room.knotwalkerTrapLocalPosition,
		cfg.palette.threatMarker,
		cfg.markers.knotwalkerTrapLabel
	)
	buildMarker(staticFolder, noisePosition, cfg.palette.accent, cfg.markers.noiseLabel)
	buildMarker(staticFolder, wardenPosition, cfg.palette.wardenMarker, cfg.markers.wardenLabel)
	buildMarker(staticFolder, hazardImpact, cfg.palette.hazardMarker, cfg.markers.hazardLabel)
	local lurkerSites = buildLurkerArches(staticFolder, roomCenter)
	local actionPrompts = buildControls(staticFolder, roomCenter)
	buildGuideBoards(staticFolder, roomCenter)
	buildLighting(staticFolder, roomCenter)
	-- The corridors out, parented under the same model as the laboratory so a decoy or a thrown stick
	-- still solves against them (`ToolService.setDevTestGeometry`). The FLOORS at the far end are not
	-- built here and are not parented here: they are carved Terrain with their own model, raised by
	-- `server/DevTestBossFloors` once the laboratory exists.
	local bossApproaches: { BossApproach } = {}
	for index, approach in approaches do
		table.insert(
			bossApproaches,
			buildBossApproach(model, approachPlans[index], approach, approachDefinitions[index])
		)
	end

	model.Parent = workspace
	return model,
		floor,
		dynamicFolder,
		actionPrompts,
		candlePosition,
		threatPosition,
		knotwalkerPosition,
		noisePosition,
		frameFacing(wardenPosition, room.wardenFacing),
		wardenWaxPosition,
		lurkerSites,
		CFrame.new(hazardAnchor),
		hazardImpact,
		roomCenter,
		bossApproaches
end

function DevTestRoomBuilder.build(): Runtime
	local existing = cached
	if existing ~= nil and existing.roomModel.Parent ~= nil and existing.accessModel.Parent ~= nil then
		return existing
	end
	if existing ~= nil then
		if existing.roomModel.Parent ~= nil then
			existing.roomModel:Destroy()
		end
		if existing.accessModel.Parent ~= nil then
			existing.accessModel:Destroy()
		end
	end

	local accessModel, accessPrompt = buildAccessTerminal()
	local roomModel, groundPart, dynamicFolder, actionPrompts, candleSpawnPosition, threatSpawnPosition, knotwalkerSpawnPosition, noisePosition, wardenSpawnCFrame, wardenWaxPosition, lurkerSites, hazardAnchorCFrame, hazardImpactPosition, roomCenter, bossApproaches =
		buildRoom()
	local built: Runtime = {
		accessModel = accessModel,
		accessPrompt = accessPrompt,
		roomModel = roomModel,
		groundPart = groundPart,
		dynamicFolder = dynamicFolder,
		actionPrompts = actionPrompts,
		roomCenter = roomCenter,
		candleSpawnPosition = candleSpawnPosition,
		threatSpawnPosition = threatSpawnPosition,
		knotwalkerSpawnPosition = knotwalkerSpawnPosition,
		noisePosition = noisePosition,
		wardenSpawnCFrame = wardenSpawnCFrame,
		wardenWaxPosition = wardenWaxPosition,
		lurkerSites = lurkerSites,
		hazardAnchorCFrame = hazardAnchorCFrame,
		hazardImpactPosition = hazardImpactPosition,
		lobbyReturnPosition = Config.LobbyRoom.origin + Config.DevTestRoom.room.lobbyReturnOffset,
		bossApproaches = bossApproaches,
	}
	cached = built
	return built
end

return DevTestRoomBuilder
