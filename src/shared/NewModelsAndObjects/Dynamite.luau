--!strict
-- Dynamite silhouettes: the loose stick, the crate, the armed charge lying on the floor, and the
-- socket marker cut into a blast door.
--
-- ART-BIBLE §4 BINDS EVERYTHING IN THIS FILE. Nothing built here emits light into the cave: there is
-- not one PointLight below. The socket affordance is a fill-free Highlight and the lit fuse is only a
-- self-illuminating spark pixel; neither makes anything else visible.
--
-- WHY THE STICK IS NOT ONE RED CYLINDER. It is the only man-made object a player will carry, and it
-- has to be identifiable at the edge of candle range from any angle, so the silhouette does the work:
-- a slim body, a HARD dark crimp at each end that breaks the outline, a pale label band across the
-- middle that catches grazing light, and a fuse that leaves the top at an angle. Those four reads
-- survive being three-quarters in shadow; a plain tube does not.

local Types = require(script.Parent.Parent.Types)
local DynamiteConfig = require(script.Parent.Parent.Config.Dynamite)

local DynamiteModel = {}

local FUSE_ORDER_ATTRIBUTE = "WickFuseOrder"
local FUSE_START_ATTRIBUTE = "WickFuseStart"
local FUSE_BASE_ATTRIBUTE = "WickFuseBase"

export type BuiltStick = {
	model: Model,
	root: BasePart,
	-- Where a lit fuse's spark sits. Presentation attaches its emitter here so the spark travels down
	-- the cord rather than hovering over the middle of the stick.
	fuseTip: Attachment,
}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): BasePart
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = at
	created.Color = color
	created.Material = material
	created.Shape = shape or Enum.PartType.Block
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- Part cylinders run along local X; every stick below is authored upright and then laid down by
-- whatever seats it, so this is the one place the axis convention is spelled out.
local function upright(at: CFrame): CFrame
	return at * CFrame.Angles(0, 0, math.pi / 2)
end

-- ONE STICK, built around `origin` with its base at the origin's Y and its fuse leaving the top.
-- Returns the attachment at the fuse tip so a lit charge can put its spark on the cord end.
--
-- `scale` multiplies the authored proportions: a stick in a crate is the same object at three-quarter
-- size, not a different model, which is what keeps the two rows reading as the same item.
function DynamiteModel.buildStick(parent: Instance, origin: CFrame, scale: number): Attachment
	local visual = DynamiteConfig.visual
	local length = visual.stickLength * scale
	local diameter = visual.stickRadius * 2 * scale

	local body = part(
		parent,
		"Stick",
		Vector3.new(length, diameter, diameter),
		upright(origin * CFrame.new(0, length / 2, 0)),
		visual.stickColor,
		Enum.Material.Sand,
		Enum.PartType.Cylinder
	)
	body.Reflectance = 0

	-- The wound paper the charge is rolled in. Two slightly darker sleeves at different heights read as
	-- a spiral wrap without needing a texture — this is waxed paper, not painted metal.
	for _, spec in { { y = 0.3, height = 0.2 }, { y = 0.72, height = 0.16 } } do
		part(
			parent,
			"Wrap",
			Vector3.new(length * spec.height, diameter * 1.035, diameter * 1.035),
			upright(origin * CFrame.new(0, length * spec.y, 0)),
			visual.wrapColor,
			Enum.Material.Sand,
			Enum.PartType.Cylinder
		)
	end

	-- The pale label band across the middle. The one high-value surface on the object, and the reason
	-- a stick is still identifiable when the flame only reaches part of it.
	part(
		parent,
		"Label",
		Vector3.new(length * 0.26, diameter * 1.07, diameter * 1.07),
		upright(origin * CFrame.new(0, length * 0.5, 0)),
		visual.bandColor,
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)

	-- Crimped ends. Slightly WIDER than the body and darker than everything else on the stick, so they
	-- notch the outline at both extremes — the read that survives at range.
	for _, y in { 0.022, 0.978 } do
		part(
			parent,
			"Crimp",
			Vector3.new(length * 0.055, diameter * 1.12, diameter * 1.12),
			upright(origin * CFrame.new(0, length * y, 0)),
			visual.capColor,
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
	end

	-- THE FUSE, walked as short segments along a curve instead of built as one leaning rod. A single
	-- tilted cylinder reads as an antenna; a cord that starts vertical and falls away to one side reads
	-- as something that was cut off a coil, which is what it is.
	local segments = math.max(1, math.floor(visual.fuseSegments))
	local fuseLength = visual.fuseLength * scale
	local fuseDiameter = visual.fuseRadius * 2 * scale
	local segmentLength = fuseLength / segments
	local tip = origin * CFrame.new(0, length, 0)
	for index = 1, segments do
		local t = (index - 0.5) / segments
		-- Quadratic lean: the cord leaves the crimp straight and curls harder the further out it gets.
		local lean = visual.fuseCurl * t * t
		local localFrame = CFrame.new(lean * scale, length + (index - 0.5) * segmentLength, 0)
			* CFrame.Angles(0, 0, -math.atan(visual.fuseCurl * 2 * t))
		local fusePiece = part(
			parent,
			string.format("Fuse_%02d", index),
			Vector3.new(segmentLength * 1.25, fuseDiameter, fuseDiameter),
			upright(origin * localFrame),
			visual.fuseColor,
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
		fusePiece:SetAttribute(FUSE_ORDER_ATTRIBUTE, index)
		if index == segments then
			tip = origin * CFrame.new(lean * scale, length + fuseLength, 0)
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FuseTip"
	-- Parented to the body rather than to a fuse segment so a presentation layer can find it by one
	-- stable path whatever the segment count is tuned to. PARENT FIRST: `WorldCFrame` is resolved
	-- against the parent, so writing it on an orphan attachment silently lands it at the origin.
	attachment.Parent = body
	attachment.WorldCFrame = tip
	attachment:SetAttribute(FUSE_START_ATTRIBUTE, attachment.Position)
	attachment:SetAttribute(
		FUSE_BASE_ATTRIBUTE,
		body.CFrame:PointToObjectSpace((origin * CFrame.new(0, length, 0)).Position)
	)
	return attachment
end

-- THE CRATE. A shallow open-topped box with the sticks bundled upright inside it, so the thing a
-- player is walking toward reads as "several of those" rather than as a container they have to guess
-- the contents of. There is no lid for exactly that reason.
local function buildCrate(parent: Instance, scale: number)
	local visual = DynamiteConfig.visual
	local size = visual.crateSize * scale
	local wall = 0.11 * scale

	-- Four walls and a base rather than a solid block: the open top is the whole point, and a hollow
	-- box also lets the flame fall INTO the crate and light the sticks from above.
	part(
		parent,
		"CrateBase",
		Vector3.new(size.X, wall, size.Z),
		CFrame.new(0, wall / 2, 0),
		visual.crateColor,
		Enum.Material.WoodPlanks
	)
	local walls = {
		{ offset = Vector3.new(0, 0, size.Z / 2 - wall / 2), size = Vector3.new(size.X, size.Y, wall) },
		{ offset = Vector3.new(0, 0, -size.Z / 2 + wall / 2), size = Vector3.new(size.X, size.Y, wall) },
		{ offset = Vector3.new(size.X / 2 - wall / 2, 0, 0), size = Vector3.new(wall, size.Y, size.Z) },
		{ offset = Vector3.new(-size.X / 2 + wall / 2, 0, 0), size = Vector3.new(wall, size.Y, size.Z) },
	}
	for _, spec in walls do
		part(
			parent,
			"CrateWall",
			spec.size,
			CFrame.new(spec.offset + Vector3.new(0, size.Y / 2, 0)),
			visual.crateColor,
			Enum.Material.WoodPlanks
		)
	end

	-- Two iron bands round the box. The only hard, cold material on an otherwise soft wooden object,
	-- and what stops it reading as a cardboard carton at range.
	for _, y in { 0.26, 0.78 } do
		for _, spec in
			{
				{ offset = Vector3.new(0, 0, size.Z / 2), size = Vector3.new(size.X * 1.02, 0.09 * scale, wall * 0.6) },
				{
					offset = Vector3.new(0, 0, -size.Z / 2),
					size = Vector3.new(size.X * 1.02, 0.09 * scale, wall * 0.6),
				},
				{ offset = Vector3.new(size.X / 2, 0, 0), size = Vector3.new(wall * 0.6, 0.09 * scale, size.Z * 1.02) },
				{
					offset = Vector3.new(-size.X / 2, 0, 0),
					size = Vector3.new(wall * 0.6, 0.09 * scale, size.Z * 1.02),
				},
			}
		do
			part(
				parent,
				"CrateBand",
				spec.size,
				CFrame.new(spec.offset + Vector3.new(0, size.Y * y, 0)),
				visual.crateBandColor,
				Enum.Material.Metal
			)
		end
	end

	-- A darker slat down each long face. Free grain: it breaks the flat plank into two boards.
	for _, z in { size.Z / 2 - wall * 0.45, -size.Z / 2 + wall * 0.45 } do
		part(
			parent,
			"CrateSlat",
			Vector3.new(size.X * 0.96, 0.07 * scale, wall * 0.5),
			CFrame.new(0, size.Y * 0.52, z),
			visual.crateSlatColor,
			Enum.Material.WoodPlanks
		)
	end

	-- The sticks themselves, standing in the box, leaned slightly apart so the bundle reads as loose
	-- rather than as a moulded block. Their bases sit on the crate floor and their fuses clear the rim.
	local count = math.max(1, math.floor(visual.crateSticks))
	local stickScale = scale * 0.74
	for index = 1, count do
		local t = (index - 0.5) / count
		local x = (t - 0.5) * size.X * 0.6
		local z = ((index % 2) - 0.5) * size.Z * 0.22
		local lean = (t - 0.5) * 0.34
		DynamiteModel.buildStick(
			parent,
			CFrame.new(x, wall, z) * CFrame.Angles(math.rad(lean * 14), math.rad(index * 37), math.rad(lean * 20)),
			stickScale
		)
	end
end

-- THE SOCKET MARKER: a yellow outline of the stick that shows exactly where a carried charge goes.
--
-- THIS IS AN AFFORDANCE, NOT A PROP, and the distinction is what keeps it inside the art rules. It is
-- built by client/DynamiteController and only for a player who is actually carrying a stick, so it is
-- closer to a HUD element that happens to live in the world than to a light in the cave. It uses a
-- fill-free Highlight and NO PointLight: it is visible without illuminating one voxel of rock, so the rule
-- that light is the only source of visual information is untouched — you still cannot see the door,
-- the room, or anything in it by its light.
function DynamiteModel.buildSocketMarker(parent: Instance, origin: CFrame): Model
	local visual = DynamiteConfig.visual
	local marker = Instance.new("Model")
	marker.Name = "DynamiteSocketOutline"
	local root = part(
		marker,
		"SocketMarkerRoot",
		Vector3.new(0.1, 0.1, 0.1),
		CFrame.new(),
		Color3.new(),
		Enum.Material.SmoothPlastic,
		nil
	)
	root.Transparency = 1
	root.CastShadow = false
	marker.PrimaryPart = root
	-- Build the SAME local silhouette and orientation as `buildArmed`, so the outline is a truthful
	-- preview of the real charge that replaces it rather than merely a dynamite-shaped icon.
	DynamiteModel.buildStick(
		marker,
		CFrame.new(0, visual.stickRadius, 0) * CFrame.Angles(0, math.rad(14), math.rad(90)),
		1
	)
	for _, descendant in marker:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			descendant.CastShadow = false
			-- Highlight needs renderable geometry to outline; 0.99 keeps the silhouette itself effectively
			-- invisible while the fill-free outline remains reliable.
			descendant.Transparency = 0.99
		end
	end

	local outline = Instance.new("Highlight")
	outline.Name = "SocketOutline"
	outline.Adornee = marker
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.FillTransparency = 1
	outline.OutlineColor = visual.socketGlowColor
	outline.OutlineTransparency = visual.socketGlowTransparency
	outline.Parent = marker
	marker:PivotTo(origin)
	marker.Parent = parent
	return marker
end

-- A loose pickup lying in the cave: one stick, or a crate of them. `style` comes from the loot row.
function DynamiteModel.buildPickup(style: Types.DynamiteStyle, scale: number, promptHeight: number): BuiltStick
	local model = Instance.new("Model")
	model.Name = "Dynamite_" .. style

	local root =
		part(model, "PickupRoot", Vector3.new(0.3, 0.3, 0.3), CFrame.new(), Color3.new(), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	local fuseTip: Attachment
	if style == "Crate" then
		buildCrate(model, scale)
		-- A crate's "fuse tip" is only ever a spark anchor for presentation, and a crate is never armed,
		-- so it resolves to the box's own rim rather than to any one stick inside it.
		fuseTip = Instance.new("Attachment")
		fuseTip.Name = "FuseTip"
		fuseTip.Position = Vector3.new(0, DynamiteConfig.visual.crateSize.Y * scale, 0)
		fuseTip.Parent = root
	else
		-- A loose stick LIES DOWN. Standing one on its end would read as placed by somebody, and every
		-- pickup in this cave is something that was dropped or left.
		fuseTip = DynamiteModel.buildStick(
			model,
			CFrame.new(0, DynamiteConfig.visual.stickRadius * scale, 0) * CFrame.Angles(0, math.rad(24), math.rad(90)),
			scale
		)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptPoint"
	attachment.Position = Vector3.new(0, promptHeight * scale, 0)
	attachment.Parent = root

	return { model = model, root = root, fuseTip = fuseTip }
end

-- AN ARMED CHARGE, lying where it was thrown or seated in a door. Same stick, no prompt, plus the
-- spark rig a lit fuse needs. The spark starts disabled and follows the shrinking segmented cord.
function DynamiteModel.buildArmed(): BuiltStick
	local model = Instance.new("Model")
	model.Name = "ArmedDynamite"

	local root =
		part(model, "ChargeRoot", Vector3.new(0.3, 0.3, 0.3), CFrame.new(), Color3.new(), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	local fuseTip = DynamiteModel.buildStick(
		model,
		CFrame.new(0, DynamiteConfig.visual.stickRadius, 0) * CFrame.Angles(0, math.rad(14), math.rad(90)),
		1
	)

	local spark = Instance.new("ParticleEmitter")
	spark.Name = "FuseSpark"
	spark.Color = ColorSequence.new(DynamiteConfig.visual.sparkColor)
	spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spark.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(1, 0.02),
	})
	spark.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	spark.Lifetime = NumberRange.new(0.18, 0.42)
	spark.Rate = 0
	spark.Speed = NumberRange.new(1.4, 3.6)
	spark.SpreadAngle = Vector2.new(180, 180)
	spark.Acceleration = Vector3.new(0, -6, 0)
	spark.Drag = 3
	-- The spark is self-lit, but LightInfluence 0 with no PointLight means it is a bright pixel rather
	-- than a light source: a burning fuse never illuminates the room it is about to wreck.
	spark.LightEmission = 1
	spark.LightInfluence = 0
	spark.Enabled = false
	spark.Parent = fuseTip

	return { model = model, root = root, fuseTip = fuseTip }
end

function DynamiteModel.setLit(built: BuiltStick, lit: boolean)
	local spark = built.fuseTip:FindFirstChild("FuseSpark")
	if spark ~= nil and spark:IsA("ParticleEmitter") then
		spark.Enabled = lit
		spark.Rate = if lit then 42 else 0
	end
	if not lit then
		DynamiteModel.setFuseProgress(built, 0)
	end
end

-- Burns the authored segmented cord from its free end toward the stick while moving the spark with
-- it. This is presentation derived from the authoritative fuse clock; it never changes detonation.
function DynamiteModel.setFuseProgress(built: BuiltStick, progress: number)
	local alpha = math.clamp(progress, 0, 1)
	local fusePieces: { BasePart } = {}
	for _, descendant in built.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(FUSE_ORDER_ATTRIBUTE) ~= nil then
			table.insert(fusePieces, descendant)
		end
	end
	local remaining = math.ceil((1 - alpha) * #fusePieces)
	for _, piece in fusePieces do
		local order = tonumber(piece:GetAttribute(FUSE_ORDER_ATTRIBUTE)) or 0
		piece.Transparency = if order > remaining then 1 else 0
	end

	local startPosition = built.fuseTip:GetAttribute(FUSE_START_ATTRIBUTE)
	local basePosition = built.fuseTip:GetAttribute(FUSE_BASE_ATTRIBUTE)
	if typeof(startPosition) == "Vector3" and typeof(basePosition) == "Vector3" then
		built.fuseTip.Position = startPosition:Lerp(basePosition, alpha)
	end
end

return DynamiteModel
