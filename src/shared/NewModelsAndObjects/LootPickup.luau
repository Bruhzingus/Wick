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

local function buildWaxCache(model: Model, def: Types.LootDef, scale: number)
	part(
		model,
		"StoneDish",
		Vector3.new(0.18, 2.35, 2.35) * scale,
		verticalCylinder(CFrame.new(0, 0.12 * scale, 0)),
		STONE,
		Enum.Material.Slate,
		Enum.PartType.Cylinder
	)

	local placements = {
		{ x = -0.52, z = 0.2, height = 1.15, width = 0.86, tilt = -0.08 },
		{ x = 0.42, z = 0.38, height = 0.82, width = 1.02, tilt = 0.09 },
		{ x = 0.08, z = -0.5, height = 0.62, width = 0.72, tilt = -0.04 },
	}
	for index, placement in placements do
		local height = placement.height * scale
		local waxColor = def.color:Lerp(Color3.new(1, 1, 1), (index - 1) * 0.055)
		part(
			model,
			"WaxChunk",
			Vector3.new(height, placement.width * scale, placement.width * scale),
			verticalCylinder(
				CFrame.new(placement.x * scale, 0.2 * scale + height / 2, placement.z * scale)
					* CFrame.Angles(placement.tilt, 0, placement.tilt)
			),
			waxColor,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		if index <= 2 then
			part(
				model,
				"Wick",
				Vector3.new(0.07, 0.28, 0.07) * scale,
				CFrame.new(placement.x * scale, 0.2 * scale + height + 0.12 * scale, placement.z * scale),
				DARK,
				Enum.Material.Fabric,
				nil
			)
		end
	end
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

	if def.kind == "WaxType" then
		buildWaxCache(model, def, scale)
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
