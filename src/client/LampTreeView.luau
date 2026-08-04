--!strict
-- Scrollable prerequisite graph for the Lamp Network. The server owns every purchase state, while
-- this module owns only geometry, selection and restrained visual feedback.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LampNodeIcons = require(script.Parent.LampNodeIcons)
local UITheme = require(script.Parent.UITheme)

local LampTreeView = {}

export type LampOffer = {
	nodeId: string,
	displayName: string,
	description: string,
	iconId: string,
	price: number,
	owned: boolean,
	live: boolean,
	affordable: boolean,
	purchasable: boolean,
	failure: string?,
	missingNode: string?,
	requires: { string },
	requiresAny: { string },
	requiresAnyCount: number,
	treePosition: Vector2,
}

export type View = {
	instance: ScrollingFrame,
	setNodes: (offers: { LampOffer }, selectedId: string?) -> (),
	setSelected: (nodeId: string?, scrollIntoView: boolean?) -> (),
	flashNode: (nodeId: string) -> (),
}

type NodeWidget = {
	offer: LampOffer,
	button: TextButton,
	stroke: UIStroke,
	scale: UIScale,
	icon: LampNodeIcons.Icon,
	nameLabel: TextLabel,
	statusLabel: TextLabel,
}

local palette = UITheme.palette
-- Cards and spacing are sized around the type, not the other way round: a node name at the shared
-- `body` step needs about 100px of line before it wraps, and the grid has to keep the connection
-- lines between cards readable at that size rather than crowding them into the card edges.
local NODE_SIZE = Vector2.new(176, 104)
local GRID = Vector2.new(216, 134)
local MARGIN = Vector2.new(96, 70)

-- How far a press may travel before it counts as a pan rather than a click. Anything under this is a
-- selection with a shaky hand; anything over it must NOT also select the node it happened to start
-- on, or dragging the graph by an empty-looking card silently changes what the detail pane is showing.
local DRAG_THRESHOLD = 6

type Pan = {
	begin: (input: InputObject) -> (),
	consumedClick: () -> boolean,
}

local function lineBetween(parent: GuiObject, from: Vector2, to: Vector2, color: Color3, faint: boolean)
	local delta = to - from
	local distance = delta.Magnitude
	local edge = Instance.new("Frame")
	edge.Name = if faint then "ChoiceLink" else "RequiredLink"
	edge.AnchorPoint = Vector2.new(0, 0.5)
	edge.Position = UDim2.fromOffset(from.X, from.Y)
	edge.Size = UDim2.fromOffset(distance, if faint then 2 else 3)
	edge.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	edge.BackgroundColor3 = color
	edge.BackgroundTransparency = if faint then 0.56 else 0.34
	edge.BorderSizePixel = 0
	edge.ZIndex = 1
	edge.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.18, 0),
		NumberSequenceKeypoint.new(0.82, 0),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	gradient.Parent = edge
end

local function nodeCenter(offer: LampOffer): Vector2
	return Vector2.new(MARGIN.X + offer.treePosition.X * GRID.X, MARGIN.Y + offer.treePosition.Y * GRID.Y)
end

local function statusFor(offer: LampOffer): (string, Color3)
	if offer.owned then
		return "LIT", palette.gold
	elseif not offer.live then
		return "DORMANT", palette.textDim
	elseif offer.purchasable then
		return string.format("%d WAX", offer.price), palette.ember
	elseif offer.missingNode ~= nil or offer.failure == "MissingPrerequisite" then
		return "LOCKED", palette.textDim
	elseif not offer.affordable then
		return string.format("%d WAX", offer.price), palette.textMuted
	end
	return "LOCKED", palette.textDim
end

local function widgetColor(widget: NodeWidget, selected: boolean): (Color3, Color3, Color3, number)
	local offer = widget.offer
	if offer.owned then
		return palette.chipActive, palette.gold, palette.gold, if selected then 0 else 0.16
	elseif not offer.live then
		return palette.chip, palette.strokeSoft, palette.textDim, 0.68
	elseif offer.purchasable then
		return palette.panelRaised, palette.ember, palette.ember, if selected then 0 else 0.12
	elseif selected then
		return palette.chipHover, palette.stroke, palette.textMuted, 0.24
	end
	return palette.chip, palette.strokeSoft, palette.textDim, 0.55
end

local function makeNode(
	parent: GuiObject,
	offer: LampOffer,
	position: Vector2,
	selected: boolean,
	pan: Pan,
	onSelect: (string) -> ()
): NodeWidget
	local button = Instance.new("TextButton")
	button.Name = "Node_" .. string.gsub(offer.nodeId, "[^%w_]", "_")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(position.X, position.Y)
	button.Size = UDim2.fromOffset(NODE_SIZE.X, NODE_SIZE.Y)
	button.BackgroundColor3 = palette.chip
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	button.ZIndex = 3
	button.Parent = parent
	UITheme.corner(button, 12)
	local stroke = UITheme.stroke(button, palette.strokeSoft, 1.5, 0.4)
	local scale = UITheme.scale(button, 1)

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "IconHolder"
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.new(0, 14, 0.5, -6)
	iconHolder.Size = UDim2.fromOffset(42, 42)
	iconHolder.BackgroundTransparency = 1
	iconHolder.ZIndex = 4
	iconHolder.Parent = button
	local icon = LampNodeIcons.create(iconHolder, offer.iconId)
	icon.instance.ZIndex = 4

	local name = Instance.new("TextLabel")
	name.Name = "NodeName"
	name.Position = UDim2.fromOffset(64, 12)
	name.Size = UDim2.new(1, -76, 0, 50)
	name.BackgroundTransparency = 1
	name.Font = UITheme.font.heading
	name.Text = offer.displayName
	name.TextColor3 = palette.text
	name.TextWrapped = true
	name.TextSize = UITheme.textSize.body
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextYAlignment = Enum.TextYAlignment.Center
	name.ZIndex = 4
	name.Parent = button

	local statusText, statusColor = statusFor(offer)
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromOffset(64, 66)
	status.Size = UDim2.new(1, -76, 0, 24)
	status.BackgroundTransparency = 1
	status.Font = UITheme.font.heading
	status.Text = statusText
	status.TextColor3 = statusColor
	status.TextSize = UITheme.textSize.micro
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = 4
	status.Parent = button

	local widget: NodeWidget = {
		offer = offer,
		button = button,
		stroke = stroke,
		scale = scale,
		icon = icon,
		nameLabel = name,
		statusLabel = status,
	}

	local hovered = false
	local function paint(instant: boolean)
		local background, edgeColor, iconColor, transparency = widgetColor(widget, selected)
		if hovered then
			background = if offer.owned then palette.chipActive else palette.chipHover
			edgeColor = palette.ember
			transparency = 0
		end
		local info = if instant then TweenInfo.new(0) else UITheme.motion.hover
		UITheme.tween(button, info, { BackgroundColor3 = background })
		UITheme.tween(stroke, info, {
			Color = edgeColor,
			Transparency = transparency,
			Thickness = if selected then 2.5 else 1.5,
		})
		icon.setColor(iconColor)
		name.TextColor3 = if offer.live or offer.owned then palette.text else palette.textDim
	end

	-- Hover and press are transient, so a fractional scale during them costs nothing. A *resting* one
	-- does: the selected card used to sit at 1.035 forever, which put its label on fractional pixels on
	-- the single card the player is actually reading. Selection is already carried by the background,
	-- the ember rim and the 2.5 stroke, so the card now rests at exactly 1 and stays sharp.
	button.MouseEnter:Connect(function()
		hovered = true
		paint(false)
		UITheme.tween(scale, UITheme.motion.hover, { Scale = 1.025 })
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		paint(false)
		UITheme.tween(scale, UITheme.motion.hover, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UITheme.tween(scale, UITheme.motion.press, { Scale = 0.97 })
	end)
	button.MouseButton1Up:Connect(function()
		UITheme.tween(scale, UITheme.motion.press, { Scale = 1 })
	end)
	-- A card is also a handle for the graph behind it. Without this the only draggable surface would be
	-- the gaps between nodes, which on a dense tree is most of the screen missing.
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pan.begin(input)
		end
	end)
	button.Activated:Connect(function()
		-- The press that just ended was a pan across the graph, not a choice of node.
		if pan.consumedClick() then
			return
		end
		onSelect(offer.nodeId)
	end)

	paint(true)
	return widget
end

function LampTreeView.create(parent: GuiObject, onSelected: (string) -> ()): View
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "LampTree"
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundColor3 = palette.void
	scroller.BackgroundTransparency = 0.24
	scroller.BorderSizePixel = 0
	scroller.CanvasSize = UDim2.fromOffset(0, 0)
	scroller.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroller.ScrollingDirection = Enum.ScrollingDirection.XY
	scroller.ScrollBarImageColor3 = palette.stroke
	scroller.ScrollBarImageTransparency = 0.25
	scroller.ScrollBarThickness = 5
	-- Needed for the frame itself to report presses; without it a drag could only ever be started from
	-- a node, and the empty space between nodes would be dead.
	scroller.Active = true
	scroller.Parent = parent
	UITheme.corner(scroller, 12)
	UITheme.stroke(scroller, palette.strokeSoft, 1, 0.5)

	-- DRAG TO PAN. The graph is wider than the pane at every sensible window size, and scroll bars
	-- alone make reading it a chore — you cannot follow a prerequisite line to its parent without
	-- letting go of where you were. Grabbing the canvas is the natural way to move around a map.
	--
	-- Deliberately MOUSE ONLY. Roblox already drag-scrolls a ScrollingFrame under touch, and adding a
	-- second handler on top of that moves the canvas twice per finger-stud. Wheel scrolling is
	-- untouched and still works.
	--
	-- Movement and release are read from UserInputService rather than from the frame, so a drag that
	-- leaves the pane (or the window) keeps tracking instead of sticking the canvas mid-pan.
	local panning = false
	local panOrigin = Vector2.zero
	local panCanvasOrigin = Vector2.zero
	-- Kept across the end of a drag on purpose: `Activated` fires after the button is released, and it
	-- is the value from the drag that just finished which decides whether that release was a click.
	local panTravel = 0

	local pan: Pan = {
		begin = function(input: InputObject)
			panning = true
			panTravel = 0
			panOrigin = Vector2.new(input.Position.X, input.Position.Y)
			panCanvasOrigin = scroller.CanvasPosition
		end,
		consumedClick = function(): boolean
			return panTravel > DRAG_THRESHOLD
		end,
	}

	scroller.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pan.begin(input)
		end
	end)

	local moveConnection = UserInputService.InputChanged:Connect(function(input: InputObject)
		if not panning or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if scroller.Parent == nil then
			panning = false
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - panOrigin
		panTravel = math.max(panTravel, delta.Magnitude)
		-- Subtracted, so the canvas follows the cursor: dragging left pulls the graph left, the way
		-- grabbing a paper map does. Adding it would scroll the VIEW left and feel inverted.
		-- CanvasPosition is clamped by the engine, so overshooting the edges needs no handling here.
		scroller.CanvasPosition = panCanvasOrigin - delta
	end)

	local endConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			panning = false
		end
	end)

	-- The shop rebuilds this view when it reopens; leaking a global input listener per open would keep
	-- every dead tree panning forever.
	scroller.Destroying:Connect(function()
		panning = false
		moveConnection:Disconnect()
		endConnection:Disconnect()
	end)

	local canvas: Frame? = nil
	local widgets: { [string]: NodeWidget } = {}
	local selectedId: string? = nil

	local function paintSelection()
		for nodeId, widget in widgets do
			local selected = nodeId == selectedId
			local background, edgeColor, iconColor, transparency = widgetColor(widget, selected)
			UITheme.tween(widget.button, UITheme.motion.settle, { BackgroundColor3 = background })
			UITheme.tween(widget.stroke, UITheme.motion.settle, {
				Color = edgeColor,
				Transparency = transparency,
				Thickness = if selected then 2.5 else 1.5,
			})
			UITheme.tween(widget.scale, UITheme.motion.settle, { Scale = 1 })
			widget.icon.setColor(iconColor)
		end
	end

	local function scrollTo(nodeId: string)
		local widget = widgets[nodeId]
		if widget == nil then
			return
		end
		task.defer(function()
			if scroller.Parent == nil or widget.button.Parent == nil then
				return
			end
			local center = Vector2.new(widget.button.Position.X.Offset, widget.button.Position.Y.Offset)
			local window = scroller.AbsoluteSize
			local canvasSize = Vector2.new(scroller.CanvasSize.X.Offset, scroller.CanvasSize.Y.Offset)
			local target = center - window * 0.5
			target = Vector2.new(
				math.clamp(target.X, 0, math.max(0, canvasSize.X - window.X)),
				math.clamp(target.Y, 0, math.max(0, canvasSize.Y - window.Y))
			)
			TweenService:Create(scroller, UITheme.motion.settle, { CanvasPosition = target }):Play()
		end)
	end

	local view: View
	view = {
		instance = scroller,
		setNodes = function(offers: { LampOffer }, nextSelectedId: string?)
			if canvas ~= nil then
				canvas:Destroy()
			end
			table.clear(widgets)

			local maxPosition = Vector2.zero
			local offerById: { [string]: LampOffer } = {}
			for _, offer in offers do
				offerById[offer.nodeId] = offer
				maxPosition = Vector2.new(
					math.max(maxPosition.X, offer.treePosition.X),
					math.max(maxPosition.Y, offer.treePosition.Y)
				)
			end
			local canvasSize = Vector2.new(MARGIN.X * 2 + maxPosition.X * GRID.X, MARGIN.Y * 2 + maxPosition.Y * GRID.Y)
			canvasSize = Vector2.new(
				math.max(canvasSize.X, scroller.AbsoluteSize.X),
				math.max(canvasSize.Y, scroller.AbsoluteSize.Y)
			)

			local built = Instance.new("Frame")
			built.Name = "Canvas"
			built.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
			built.BackgroundTransparency = 1
			built.BorderSizePixel = 0
			built.Parent = scroller
			canvas = built
			scroller.CanvasSize = UDim2.fromOffset(canvasSize.X, canvasSize.Y)

			-- Connections are drawn first so every card sits clearly on top of its prerequisite path.
			for _, offer in offers do
				local destination = nodeCenter(offer)
				for _, requirementId in offer.requires do
					local requirement = offerById[requirementId]
					if requirement ~= nil then
						local color = if requirement.owned and offer.owned then palette.gold else palette.strokeSoft
						lineBetween(built, nodeCenter(requirement), destination, color, false)
					end
				end
				for _, requirementId in offer.requiresAny do
					local requirement = offerById[requirementId]
					if requirement ~= nil then
						local color = if requirement.owned and offer.owned then palette.ember else palette.strokeSoft
						lineBetween(built, nodeCenter(requirement), destination, color, true)
					end
				end
			end

			selectedId = nextSelectedId
			if selectedId == nil or offerById[selectedId :: string] == nil then
				selectedId = if #offers > 0 then offers[1].nodeId else nil
			end
			for _, offer in offers do
				widgets[offer.nodeId] = makeNode(
					built,
					offer,
					nodeCenter(offer),
					offer.nodeId == selectedId,
					pan,
					function(nodeId)
						selectedId = nodeId
						paintSelection()
						onSelected(nodeId)
					end
				)
			end
			if selectedId ~= nil then
				scrollTo(selectedId :: string)
			end
		end,
		setSelected = function(nodeId: string?, scrollIntoView: boolean?)
			if nodeId ~= nil and widgets[nodeId] == nil then
				return
			end
			selectedId = nodeId
			paintSelection()
			if nodeId ~= nil and scrollIntoView ~= false then
				scrollTo(nodeId)
			end
		end,
		flashNode = function(nodeId: string)
			local widget = widgets[nodeId]
			if widget == nil then
				return
			end
			UITheme.flash(widget.button, widget.button.BackgroundColor3, widget.stroke)
			widget.scale.Scale = 0.92
			UITheme.tween(widget.scale, UITheme.motion.rise, { Scale = 1 })
		end,
	}
	return view
end

return LampTreeView
