--!strict
-- THE BASIN'S CAULDRON — one squat vessel of molten wax on a tripod, family-tinted.
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/Cauldron
--
-- Built to the same laws CaveKit and MineRelics are built to: flat plates, square stock and simple
-- cylinders, no bevels and no surface noise (ART-BIBLE §2). Detail is spent on SILHOUETTE — the
-- proud rim, the three legs, the run of set wax down one side — because at the edge of candle range
-- an outline is all a player gets.
--
-- WHAT IT REPLACED, and why the swap is worth a file: the Basin used to be a flat orange Neon
-- cylinder sixteen studs across lying on the floor. It read as a decal rather than an object, and
-- there was nothing in the room to walk up TO. Everything the Basin DOES — the four private offers,
-- the grant band, one exchange per floor — is untouched by this; `server/BasinService` still anchors
-- the same prompt, still rolls through `Logic/SacrificeRules`, and has no idea this file exists.
--
-- NOTHING HERE IS A LIGHT SOURCE. The wax surface and the coals under the belly are Neon, which in
-- this engine means self-illuminating pixels and NOT illumination: they are visible in the dark
-- without lighting one voxel of the rock around them. There is no PointLight in this file, and there
-- must never be one — the Basin is a room you find with your own flame.

local CollectionService = game:GetService("CollectionService")

local Types = require(script.Parent.Parent.Types)
local CauldronConfig = require(script.Parent.Parent.Config.Cauldron)
local DripTrailConfig = require(script.Parent.Parent.Config.DripTrail)

local Cauldron = {}

export type BuiltCauldron = {
	model: Model,
	-- The moving surface. `client/EnvironmentAnimationController` finds it by tag and bobs it; nothing
	-- on the server touches it after this.
	waxSurface: BasePart,
	-- World height of the rim, so a caller can hang a prompt off the pot rather than guessing.
	rimY: number,
}

-- Part cylinders run along local X. Everything below is authored upright.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

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
	-- CanQuery false on every piece, exactly as a vine curtain's barrier and a moss cluster's
	-- obstruction do it: the mass below is given collision so a player cannot walk through the pot,
	-- but no AI obstacle probe or tool cast may ever see a fixture standing on the room's own
	-- navigation hub as a wall. A threat routes through this room the way it always did.
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- ONE CAULDRON, standing on `origin` (the room floor point the Basin is registered at).
--
-- `rng` is the floor's own cosmetic stream, so where the wax happened to run down the outside is
-- deterministic per depth and identical on a rebuild — the same contract every other dressing
-- decision in the builder holds to.
function Cauldron.build(style: Types.FixtureStyle, origin: Vector3, rng: Random): BuiltCauldron
	local config = CauldronConfig
	local model = Instance.new("Model")
	model.Name = "BasinCauldron"

	local plinthTop = config.plinthHeight
	local bellyBottom = plinthTop + config.legHeight
	local bellyTop = bellyBottom + config.bellyHeight
	local rimCentreY = bellyTop + config.rimHeight / 2

	-- THE CAIRN. Legs that simply end at the rock read as a table someone carried in; a low stone
	-- base reads as something that was set up here and has not moved since.
	local plinth = part(
		model,
		"CauldronPlinth",
		Vector3.new(config.plinthHeight, config.plinthRadius * 2, config.plinthRadius * 2),
		CFrame.new(origin + Vector3.new(0, config.plinthHeight / 2, 0)) * UPRIGHT,
		style.deckColor,
		style.deckMaterial,
		Enum.PartType.Cylinder
	)
	plinth.CanCollide = true

	-- THREE LEGS, never four. Three cannot rock on an uneven cave floor, and an odd count stops the
	-- silhouette resolving as a table at range.
	local legCount = math.max(3, math.floor(config.legCount))
	for index = 1, legCount do
		local angle = (index - 1) / legCount * math.pi * 2
		local radius = config.bellyRadius * 0.72
		part(
			model,
			"CauldronLeg",
			Vector3.new(config.legThickness, config.legHeight + 0.3, config.legThickness),
			CFrame.new(
				origin
					+ Vector3.new(math.cos(angle) * radius, plinthTop + config.legHeight / 2, math.sin(angle) * radius)
			) * CFrame.Angles(0, -angle, 0),
			style.frameColor,
			style.frameMaterial
		)
	end

	-- THE BELLY. Wider than it is tall — a cauldron, not a barrel.
	local belly = part(
		model,
		"CauldronBody",
		Vector3.new(config.bellyHeight, config.bellyRadius * 2, config.bellyRadius * 2),
		CFrame.new(origin + Vector3.new(0, bellyBottom + config.bellyHeight / 2, 0)) * UPRIGHT,
		style.vesselColor,
		style.vesselMaterial,
		Enum.PartType.Cylinder
	)
	belly.CanCollide = true
	model.PrimaryPart = belly

	-- THE LIP, proud on every side. This is the edge a sweeping candle catches first, and the reason
	-- the object still reads as an open vessel when only its top is lit.
	part(
		model,
		"CauldronRim",
		Vector3.new(
			config.rimHeight,
			(config.bellyRadius + config.rimOverhang) * 2,
			(config.bellyRadius + config.rimOverhang) * 2
		),
		CFrame.new(origin + Vector3.new(0, rimCentreY, 0)) * UPRIGHT,
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)

	-- Two bands round the belly. Free grain: they break a plain tube into a made object without a
	-- single extra silhouette read competing with the rim.
	for _, fraction in { 0.3, 0.68 } do
		part(
			model,
			"CauldronBand",
			Vector3.new(0.16, config.bellyRadius * 2.04, config.bellyRadius * 2.04),
			CFrame.new(origin + Vector3.new(0, bellyBottom + config.bellyHeight * fraction, 0)) * UPRIGHT,
			style.frameColor,
			style.frameMaterial,
			Enum.PartType.Cylinder
		)
	end

	-- THE COALS. Dull, mostly transparent, and strictly decorative: it implies where the heat comes
	-- from and is never allowed to become a second light in a game that has exactly one.
	local embers = part(
		model,
		"CauldronEmbers",
		Vector3.new(0.22, config.bellyRadius * 1.5, config.bellyRadius * 1.5),
		CFrame.new(origin + Vector3.new(0, plinthTop + 0.12, 0)) * UPRIGHT,
		config.emberColor,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	embers.Transparency = config.emberTransparency
	embers.CastShadow = false

	-- THE WAX ITSELF, sunk below the rim so the pot is visibly not full. A vessel filled to its lip
	-- reads as a solid orange cylinder from every angle a player will ever see it from.
	local waxSurfaceY = bellyTop - config.waxInset
	local waxSurface = part(
		model,
		"CauldronWax",
		Vector3.new(0.5, (config.bellyRadius - 0.18) * 2, (config.bellyRadius - 0.18) * 2),
		CFrame.new(origin + Vector3.new(0, waxSurfaceY, 0)) * UPRIGHT,
		config.waxColor,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	waxSurface.Transparency = config.waxTransparency
	waxSurface.CastShadow = false
	-- The animation contract, written once here and read every frame by the client. Same attribute
	-- names the water surfaces use, so one controller animates both from one convention.
	waxSurface:SetAttribute("WickBaseY", waxSurface.Position.Y)
	waxSurface:SetAttribute("WickBaseTransparency", config.waxTransparency)
	waxSurface:SetAttribute("WickAnimationPhase", rng:NextNumber(0, math.pi * 2))
	CollectionService:AddTag(waxSurface, config.waxTag)

	-- WHAT RAN OVER AND SET. Dull matte brown in the drip trail's own colour (ART-BIBLE §10) — the
	-- one detail that says the wax in this pot has been moving for a long time. Not tinted by the
	-- family: cooled wax is cooled wax in every cave, exactly as a dropped trail is.
	local runnelCount = math.max(0, math.floor(config.runnelCount))
	for _ = 1, runnelCount do
		local angle = rng:NextNumber(0, math.pi * 2)
		local length = rng:NextNumber(config.bellyHeight * 0.45, config.bellyHeight * 0.95)
		local radius = config.bellyRadius + 0.02
		part(
			model,
			"CauldronRunnel",
			Vector3.new(config.runnelWidth, length, 0.14),
			CFrame.new(
				origin
					+ Vector3.new(
						math.cos(angle) * radius,
						bellyTop - config.rimHeight / 2 - length / 2,
						math.sin(angle) * radius
					)
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			DripTrailConfig.dripColor,
			Enum.Material.SmoothPlastic
		)
		-- Where the runnel finally stopped: a small set pool on the cairn under it.
		part(
			model,
			"CauldronSetWax",
			Vector3.new(0.12, rng:NextNumber(0.7, 1.3), rng:NextNumber(0.7, 1.3)),
			CFrame.new(
				origin + Vector3.new(math.cos(angle) * radius * 0.9, plinthTop + 0.06, math.sin(angle) * radius * 0.9)
			) * UPRIGHT,
			DripTrailConfig.dripColor,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
	end

	return {
		model = model,
		waxSurface = waxSurface,
		rimY = origin.Y + bellyTop + config.rimHeight,
	}
end

return Cauldron
