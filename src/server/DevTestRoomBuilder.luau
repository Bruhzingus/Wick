--!strict
-- Builds the PIN terminal in the Landing and the isolated physical enemy-test chamber. This module
-- is deliberately geometry-only: prompts expose fixed action handles, while a server service owns
-- authorization, player state, threat lifecycle and every resulting gameplay mutation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

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

local function buildRoomShell(model: Model, roomCenter: Vector3): BasePart
	local cfg = Config.DevTestRoom
	local room = cfg.room
	local palette = cfg.palette
	local width = room.interiorSize.X
	local height = room.interiorSize.Y
	local depth = room.interiorSize.Z
	local wall = room.wallThickness

	local floor = part(
		"Floor",
		Vector3.new(width + wall * 2, room.floorThickness, depth + wall * 2),
		CFrame.new(roomCenter + Vector3.new(0, -room.floorThickness / 2, 0)),
		palette.floor,
		Enum.Material.Slate,
		model
	)
	part(
		"Ceiling",
		Vector3.new(width + wall * 2, room.ceilingThickness, depth + wall * 2),
		CFrame.new(roomCenter + Vector3.new(0, height + room.ceilingThickness / 2, 0)),
		palette.wall,
		Enum.Material.Slate,
		model
	)
	for _, spec in
		{
			{
				name = "WestWall",
				size = Vector3.new(wall, height, depth),
				offset = Vector3.new(-(width + wall) / 2, height / 2, 0),
			},
			{
				name = "EastWall",
				size = Vector3.new(wall, height, depth),
				offset = Vector3.new((width + wall) / 2, height / 2, 0),
			},
			{
				name = "NorthWall",
				size = Vector3.new(width + wall * 2, height, wall),
				offset = Vector3.new(0, height / 2, (depth + wall) / 2),
			},
			{
				name = "SouthWall",
				size = Vector3.new(width + wall * 2, height, wall),
				offset = Vector3.new(0, height / 2, -(depth + wall) / 2),
			},
		}
	do
		part(spec.name, spec.size, CFrame.new(roomCenter + spec.offset), palette.wall, Enum.Material.Slate, model)
	end
	return floor
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
				boardFrame * CFrame.new(x, y, -front),
				definition.color,
				Enum.Material.SmoothPlastic,
				parent
			)
			button.CanCollide = false
			button:SetAttribute("WickDevTestAction", definition.actionId)
			local buttonGui = surface(button, Enum.NormalId.Front, Vector2.new(440, 104))
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
	Vector3
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

	local model = Instance.new("Model")
	model.Name = "WickDevTestRoom"
	local floor = buildRoomShell(model, roomCenter)
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
	buildMarker(staticFolder, noisePosition, cfg.palette.accent, cfg.markers.noiseLabel)
	buildMarker(staticFolder, wardenPosition, cfg.palette.wardenMarker, cfg.markers.wardenLabel)
	buildMarker(staticFolder, hazardImpact, cfg.palette.hazardMarker, cfg.markers.hazardLabel)
	local lurkerSites = buildLurkerArches(staticFolder, roomCenter)
	local actionPrompts = buildControls(staticFolder, roomCenter)
	buildGuideBoards(staticFolder, roomCenter)
	buildLighting(staticFolder, roomCenter)

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
		roomCenter
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
	local roomModel, groundPart, dynamicFolder, actionPrompts, candleSpawnPosition, threatSpawnPosition, knotwalkerSpawnPosition, noisePosition, wardenSpawnCFrame, wardenWaxPosition, lurkerSites, hazardAnchorCFrame, hazardImpactPosition, roomCenter =
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
	}
	cached = built
	return built
end

return DevTestRoomBuilder
