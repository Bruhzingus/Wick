--!strict
-- Procedural dangerous-dripstone silhouettes. This module owns appearance only; all three variants
-- use the same server state machine. Their shared dry fracture collar, lean, and sparse rock dust
-- are the learnable tell that harmless CaveKit formations never combine.

local CaveKit = require(script.Parent.CaveKit)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)

local UnstableDripstone = {}

export type Variant = {
	id: string,
	displayName: string,
	weight: number,
	length: number,
	radius: number,
	prongCount: number,
	leanDegrees: number,
	taper: number,
	crownScale: number,
	warningSeconds: number,
	triggerRadius: number,
	impactRadius: number,
	waxLossFraction: number,
}

local function visualPart(
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = at
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- The entire formation moves locally during warning/fall. Keeping it out of the dynamic shadow
	-- map avoids turning the warning wobble into a cave-wide shadow invalidation.
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function UnstableDripstone.build(parent: Instance, anchor: CFrame, variant: Variant, visualSeed: number): Model
	local rng = Random.new(visualSeed)
	local visual = HazardsConfig.unstableDripstone
	local model = Instance.new("Model")
	model.Name = "UnstableDripstone_" .. variant.id

	local pivot =
		visualPart("Pivot", Vector3.new(0.2, 0.2, 0.2), anchor, visual.modelPivotColor, Enum.Material.Slate, model)
	pivot.Transparency = 1
	model.PrimaryPart = pivot

	local leanYaw = rng:NextNumber(0, math.pi * 2)
	local lean = math.rad(variant.leanDegrees)
	local leanFrame = CFrame.Angles(math.cos(leanYaw) * lean, 0, math.sin(leanYaw) * lean)
	for prongIndex = 1, variant.prongCount do
		local normalized = prongIndex - (variant.prongCount + 1) / 2
		local lateral = normalized * variant.radius * visual.modelProngSpacing
		local yaw = leanYaw + math.pi / 2
		local offset = Vector3.new(math.cos(yaw) * lateral, -variant.radius * 0.08, math.sin(yaw) * lateral)
		local heightScale = 1
			- math.abs(normalized) * 0.1
			+ rng:NextNumber(-visual.modelProngHeightJitter, visual.modelProngHeightJitter)
		local radiusScale = if variant.prongCount == 1
			then 1
			else visual.modelSecondaryProngRadiusScale + rng:NextNumber(-0.04, 0.04)
		local formation = CaveKit.stalactite(model, anchor * CFrame.new(offset) * leanFrame, {
			height = variant.length * heightScale,
			radius = variant.radius * radiusScale,
			levels = math.clamp(math.round(variant.length * 0.72), 4, 7),
			lean = variant.leanDegrees * 0.55,
			taper = variant.taper,
			twist = 58 + prongIndex * 7,
			seed = visualSeed + prongIndex * 10_007,
			wet = false,
			collide = false,
		})
		for _, descendant in formation:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CastShadow = false
			end
		end
	end

	-- A chunky dry crown makes Hammer top-heavy; the other variants get a smaller broken shoulder.
	local crownWidth = variant.radius * variant.crownScale
	for crownIndex = 1, visual.modelCrownPieces do
		local crownYaw = rng:NextNumber(0, math.pi * 2)
		visualPart(
			"FracturedCrown",
			Vector3.new(
				crownWidth * rng:NextNumber(0.65, 1),
				variant.radius * rng:NextNumber(0.45, 0.8),
				crownWidth * rng:NextNumber(0.45, 0.85)
			),
			anchor
				* CFrame.new(0, -variant.radius * (0.08 + crownIndex * 0.12), 0)
				* CFrame.Angles(rng:NextNumber(-0.12, 0.12), crownYaw, rng:NextNumber(-0.12, 0.12)),
			visual.modelCrownColor,
			if crownIndex == 1 then Enum.Material.Basalt else Enum.Material.Slate,
			model
		)
	end

	-- Three nearly black, broken collar bands are the permanent danger tell. Each is interrupted and
	-- crooked rather than a glowing/painted ring, so it still belongs to the cave.
	for crackIndex = 1, visual.modelFracturePieces do
		local crackYaw = rng:NextNumber(0, math.pi * 2)
		local crackWidth = variant.radius * rng:NextNumber(1.3, 2)
		visualPart(
			"DryFracture",
			Vector3.new(crackWidth, 0.075, variant.radius * rng:NextNumber(0.22, 0.42)),
			anchor
				* CFrame.new(0, -variant.radius * (0.18 + crackIndex * 0.22), 0)
				* CFrame.Angles(rng:NextNumber(-0.16, 0.16), crackYaw, rng:NextNumber(-0.16, 0.16)),
			visual.modelFractureColor,
			Enum.Material.Basalt,
			model
		)
	end

	local dustAttachment = Instance.new("Attachment")
	dustAttachment.Name = "DryFractureOrigin"
	dustAttachment.Position = Vector3.new(0, -variant.radius * 0.45, 0)
	dustAttachment.Parent = pivot

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "DryFractureDust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Enabled = false
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.7, 1.25)
	dust.Speed = NumberRange.new(0.7, 1.8)
	dust.EmissionDirection = Enum.NormalId.Bottom
	dust.Acceleration = Vector3.new(0, -3.5, 0)
	dust.SpreadAngle = Vector2.new(18, 18)
	dust.Rotation = NumberRange.new(-180, 180)
	dust.RotSpeed = NumberRange.new(-35, 35)
	dust.Color = ColorSequence.new(visual.modelDustColorStart, visual.modelDustColorEnd)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62),
		NumberSequenceKeypoint.new(0.75, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = dustAttachment

	model.Parent = parent
	return model
end

return UnstableDripstone
