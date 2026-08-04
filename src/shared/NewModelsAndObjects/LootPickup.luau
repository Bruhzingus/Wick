--!strict
-- Diegetic in-run loot silhouettes. Pickups use readable shape and wax/tool colour, never Neon,
-- PointLights, or glowing spheres.

local Types = require(script.Parent.Parent.Types)

local LootPickup = {}

export type BuiltPickup = {
	model: Model,
	root: BasePart,
	promptAttachment: Attachment,
}

local DARK = Color3.fromRGB(35, 29, 24)
local STONE = Color3.fromRGB(62, 59, 56)
local METAL = Color3.fromRGB(83, 78, 73)

local function part(
	model: Model,
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
	created.Parent = model
	return created
end

local function verticalCylinder(at: CFrame): CFrame
	-- Part cylinders run along local X.
	return at * CFrame.Angles(0, 0, math.pi / 2)
end

-- THE STACKING PAIR share one silhouette — a cut wax billet on a stone dish — and are told apart by
-- material, colour and one detail each, because they are the two items a player will see most and
-- has to identify at candle range without reading a prompt. Life Wax is a wrapped, dense, matte
-- block; Bright Wax is a pale faceted one.
local function buildWaxBillet(model: Model, def: Types.LootDef, scale: number, faceted: boolean)
	part(
		model,
		"StoneDish",
		Vector3.new(0.18, 2.35, 2.35) * scale,
		verticalCylinder(CFrame.new(0, 0.12 * scale, 0)),
		STONE,
		Enum.Material.Slate,
		Enum.PartType.Cylinder
	)

	local blockHeight = 1.05 * scale
	part(
		model,
		"WaxBillet",
		Vector3.new(1.15 * scale, blockHeight, 1.15 * scale),
		CFrame.new(0, 0.2 * scale + blockHeight / 2, 0) * CFrame.Angles(0, math.rad(14), 0),
		def.color,
		if faceted then Enum.Material.Glass else Enum.Material.SmoothPlastic,
		nil
	)

	if faceted then
		-- Cut corners: two smaller blocks turned 45 degrees read as facets catching the flame.
		for index, y in { 0.34, 0.78 } do
			part(
				model,
				"Facet",
				Vector3.new(0.92 * scale, 0.3 * scale, 0.92 * scale),
				CFrame.new(0, 0.2 * scale + y * scale, 0) * CFrame.Angles(0, math.rad(45 + index * 12), 0),
				def.color:Lerp(Color3.new(1, 1, 1), 0.2),
				Enum.Material.Glass,
				nil
			)
		end
	else
		-- A cord wrapped twice round the middle: dense, kept, rationed.
		for _, y in { 0.42, 0.66 } do
			part(
				model,
				"Binding",
				Vector3.new(1.24 * scale, 0.11 * scale, 1.24 * scale),
				CFrame.new(0, 0.2 * scale + y * scale, 0) * CFrame.Angles(0, math.rad(14), 0),
				DARK,
				Enum.Material.Fabric,
				nil
			)
		end
	end

	part(
		model,
		"Offcut",
		Vector3.new(0.46 * scale, 0.3 * scale, 0.62 * scale),
		CFrame.new(0.78 * scale, 0.34 * scale, -0.5 * scale) * CFrame.Angles(0, math.rad(-28), math.rad(9)),
		def.color:Lerp(Color3.new(1, 1, 1), 0.08),
		if faceted then Enum.Material.Glass else Enum.Material.SmoothPlastic,
		nil
	)
end

-- FROZEN WAX. A candle of wax that froze solid, still standing where it set, with the cold coming
-- off it. The mist is a ParticleEmitter and NOT a light: nothing in this cave glows on its own, so
-- the block is only visible when a player's own flame reaches it (ART-BIBLE section 4).
local function buildFrozenWax(model: Model, def: Types.LootDef, scale: number)
	part(
		model,
		"FrostShelf",
		Vector3.new(0.2, 2.1, 2.1) * scale,
		verticalCylinder(CFrame.new(0, 0.12 * scale, 0)),
		Color3.fromRGB(96, 118, 134),
		Enum.Material.Glacier,
		Enum.PartType.Cylinder
	)

	local candleHeight = 1.7 * scale
	local candle = part(
		model,
		"FrozenCandle",
		Vector3.new(candleHeight, 0.78 * scale, 0.78 * scale),
		verticalCylinder(CFrame.new(0, 0.2 * scale + candleHeight / 2, 0)),
		def.color,
		Enum.Material.Ice,
		Enum.PartType.Cylinder
	)
	-- Frozen mid-drip: the runs down its side are what say "this was liquid and then it was not".
	for index, angle in { 0.4, 2.3, 4.4 } do
		local runHeight = (0.5 + index * 0.2) * scale
		part(
			model,
			"FrozenRun",
			Vector3.new(runHeight, 0.2 * scale, 0.2 * scale),
			verticalCylinder(
				CFrame.new(
					math.cos(angle) * 0.36 * scale,
					0.2 * scale + candleHeight - runHeight / 2 - 0.1 * scale,
					math.sin(angle) * 0.36 * scale
				)
			),
			def.color:Lerp(Color3.new(1, 1, 1), 0.22),
			Enum.Material.Ice,
			Enum.PartType.Cylinder
		)
	end
	-- The wick is still there, and still unlit. This block is fuel, not a light source.
	part(
		model,
		"Wick",
		Vector3.new(0.07, 0.3, 0.07) * scale,
		CFrame.new(0, 0.2 * scale + candleHeight + 0.14 * scale, 0),
		DARK,
		Enum.Material.Fabric,
		nil
	)

	local mistAttachment = Instance.new("Attachment")
	mistAttachment.Name = "ColdMist"
	mistAttachment.Position = Vector3.new(0, 0.35 * scale, 0)
	mistAttachment.Parent = candle

	local mist = Instance.new("ParticleEmitter")
	mist.Name = "ColdMist"
	mist.Color = ColorSequence.new(Color3.fromRGB(158, 205, 236), Color3.fromRGB(198, 226, 244))
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35 * scale),
		NumberSequenceKeypoint.new(1, 1.05 * scale),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Lifetime = NumberRange.new(1.6, 2.6)
	mist.Rate = 6
	mist.Speed = NumberRange.new(0.15, 0.45)
	mist.SpreadAngle = Vector2.new(24, 24)
	-- Cold air FALLS. A rising plume would read as steam off something warm.
	mist.Acceleration = Vector3.new(0, -0.55, 0)
	mist.Drag = 2.5
	mist.Rotation = NumberRange.new(-40, 40)
	mist.RotSpeed = NumberRange.new(-14, 14)
	-- THE line that keeps this legal: the mist is lit by the player's candle and emits nothing itself.
	mist.LightEmission = 0
	mist.LightInfluence = 1
	mist.Parent = mistAttachment
end

-- EXTRA WICKS. A stub of a candle that somebody has pushed spare wicks into, plus the coil they came
-- off. Read at a glance as "more flame from the same wax".
local function buildExtraWicks(model: Model, def: Types.LootDef, scale: number)
	local stubHeight = 0.72 * scale
	part(
		model,
		"WaxStub",
		Vector3.new(stubHeight, 1.0 * scale, 1.0 * scale),
		verticalCylinder(CFrame.new(0, stubHeight / 2, 0)),
		def.color,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
	-- Three wicks, splayed. The maximum a bundle can roll, so the silhouette promises the item.
	for index, lean in { -0.24, 0, 0.2 } do
		part(
			model,
			"Wick",
			Vector3.new(0.08 * scale, 0.62 * scale, 0.08 * scale),
			CFrame.new((index - 2) * 0.24 * scale, stubHeight + 0.28 * scale, 0) * CFrame.Angles(0, 0, lean),
			DARK,
			Enum.Material.Fabric,
			nil
		)
	end
	part(
		model,
		"WickCoil",
		Vector3.new(0.22, 0.86, 0.86) * scale,
		verticalCylinder(CFrame.new(0.86 * scale, 0.12 * scale, -0.34 * scale)),
		Color3.fromRGB(122, 104, 82),
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)
end

-- CANDLE SLEEVE. Exactly what it says: a cardboard tube you slide over a candle. Its readability
-- lives in the material — it is the ONLY cardboard object in the cave.
local function buildCandleSleeve(model: Model, def: Types.LootDef, scale: number)
	local sleeveHeight = 1.55 * scale
	part(
		model,
		"Sleeve",
		Vector3.new(sleeveHeight, 1.06 * scale, 1.06 * scale),
		verticalCylinder(CFrame.new(0, sleeveHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(4))),
		def.color,
		Enum.Material.Cardboard,
		Enum.PartType.Cylinder
	)
	-- The glued seam up one side, and the flap folded over at the top: the two details that say
	-- "somebody made this out of a box" rather than "this is a wooden ring".
	part(
		model,
		"Seam",
		Vector3.new(sleeveHeight * 0.94, 0.16 * scale, 0.1 * scale),
		CFrame.new(0, sleeveHeight / 2, 0)
			* CFrame.Angles(0, 0, math.rad(4))
			* CFrame.new(0, 0, 0.52 * scale)
			* CFrame.Angles(0, 0, math.rad(90)),
		def.color:Lerp(DARK, 0.35),
		Enum.Material.Cardboard,
		nil
	)
	part(
		model,
		"Flap",
		Vector3.new(0.62 * scale, 0.08 * scale, 0.5 * scale),
		CFrame.new(0.3 * scale, sleeveHeight + 0.03 * scale, 0.2 * scale)
			* CFrame.Angles(math.rad(-16), 0, math.rad(11)),
		def.color:Lerp(Color3.new(1, 1, 1), 0.12),
		Enum.Material.Cardboard,
		nil
	)
end

local function buildFlareCharge(model: Model, def: Types.LootDef, scale: number)
	local bodyFrame = CFrame.new(0, 0.48 * scale, 0) * CFrame.Angles(0, math.rad(-18), math.rad(4))
	part(
		model,
		"FlareBody",
		Vector3.new(2.55, 0.62, 0.62) * scale,
		bodyFrame,
		def.color,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	for _, x in { -1.17, 1.17 } do
		part(
			model,
			"FlareCap",
			Vector3.new(0.2, 0.72, 0.72) * scale,
			bodyFrame * CFrame.new(x * scale, 0, 0),
			DARK,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
	end
	part(
		model,
		"PullTab",
		Vector3.new(0.12, 0.44, 0.48) * scale,
		bodyFrame * CFrame.new(-1.34 * scale, 0.06 * scale, 0),
		METAL,
		Enum.Material.DiamondPlate,
		nil
	)
end

local function buildDecoyCharge(model: Model, def: Types.LootDef, scale: number)
	local orientation = CFrame.Angles(0, math.rad(12), 0)
	for index, z in { -0.42, 0, 0.42 } do
		local y = if index == 2 then 0.66 else 0.42
		part(
			model,
			"WaxRoll",
			Vector3.new(2.1, 0.54, 0.54) * scale,
			CFrame.new(0, y * scale, 0) * orientation * CFrame.new(0, 0, z * scale),
			def.color:Lerp(Color3.new(1, 1, 1), (index - 1) * 0.035),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
	end
	for _, x in { -0.55, 0.55 } do
		part(
			model,
			"Binding",
			Vector3.new(0.16, 1.15, 1.35) * scale,
			CFrame.new(0, 0.49 * scale, 0) * orientation * CFrame.new(x * scale, 0, 0),
			DARK,
			Enum.Material.Fabric,
			nil
		)
	end
end

local function buildMatch(model: Model, def: Types.LootDef, scale: number)
	part(
		model,
		"Matchstick",
		Vector3.new(0.18, 1.7, 0.18) * scale,
		CFrame.new(0, 0.87 * scale, 0) * CFrame.Angles(0, math.rad(16), math.rad(-7)),
		Color3.fromRGB(154, 101, 57),
		Enum.Material.Wood,
		nil
	)
	part(
		model,
		"MatchHead",
		Vector3.new(0.31, 0.31, 0.31) * scale,
		CFrame.new(0, 1.72 * scale, 0) * CFrame.Angles(0, math.rad(16), math.rad(-7)),
		def.color,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	part(
		model,
		"Matchbox",
		Vector3.new(0.82, 0.36, 1.18) * scale,
		CFrame.new(0.2 * scale, 0.22 * scale, 0.08 * scale) * CFrame.Angles(0, math.rad(-12), 0),
		DARK,
		Enum.Material.Cardboard,
		nil
	)
end

function LootPickup.build(def: Types.LootDef, scale: number, promptHeight: number): BuiltPickup
	local model = Instance.new("Model")
	model.Name = "Loot_" .. def.id

	local root = part(
		model,
		"PickupRoot",
		Vector3.new(0.3, 0.3, 0.3),
		CFrame.new(),
		Color3.new(),
		Enum.Material.SmoothPlastic,
		nil
	)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	if def.kind == "CandleModifier" then
		local modifierId = def.modifierId
		if modifierId == "FrozenWax" then
			buildFrozenWax(model, def, scale)
		elseif modifierId == "ExtraWicks" then
			buildExtraWicks(model, def, scale)
		elseif modifierId == "CandleSleeve" then
			buildCandleSleeve(model, def, scale)
		else
			-- LifeWax and BrightWax: one billet silhouette, told apart by cut and material.
			buildWaxBillet(model, def, scale, modifierId == "BrightWax")
		end
	elseif def.kind == "SelfRelight" then
		buildMatch(model, def, scale)
	elseif def.toolId == "Flare" then
		buildFlareCharge(model, def, scale)
	else
		buildDecoyCharge(model, def, scale)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptPoint"
	attachment.Position = Vector3.new(0, promptHeight * scale, 0)
	attachment.Parent = root

	return {
		model = model,
		root = root,
		promptAttachment = attachment,
	}
end

return LootPickup
