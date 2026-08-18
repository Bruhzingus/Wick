--!strict
-- THE BRAZIER — the fixture a run ends at (DESIGN §12): an iron bowl of dead coals on a tripod,
-- standing on a low cairn, family-tinted.
-- Place at: ReplicatedStorage/Shared/NewModelsAndObjects/Brazier
--
-- WHAT IT REPLACED, TWICE. It began as `newPart(Vector3.new(2, 3, 2), ...)` — one dark grey box, the
-- least developed object in the game despite owning its most loaded moment. It was then replaced by
-- a Gas Lantern whose ignition also ran a floor-wide lamp cascade and a five-second camera beat,
-- which made the end of a run a cutscene that was hard to stage and harder to make look good. This
-- is the third answer and the simplest one: you light a fire, and your run is over.
--
-- LIGHTING THE CAVE IS A DIFFERENT VERB NOW and belongs to a different object
-- (`NewModelsAndObjects/WallLamp`). Nothing this fixture does reaches another room. That separation
-- is the entire point of the rewrite: the brazier ends YOUR run, the lamps light EVERYONE'S cave, and
-- neither has to carry the other's staging.
--
-- Built to the same laws as the Cauldron beside it (ART-BIBLE §2): flat plates, square stock, simple
-- cylinders, no bevels. Detail spent on silhouette — the splayed legs, the proud rim, the heap of
-- coals breaking the bowl's line — because at the edge of candle range an outline is all you get.
--
-- COLD UNTIL LIT. Dead grey coals, no glow, no light. `setLit` is called once, by
-- `server/BrazierService`, the first time anybody commits here.

local Types = require(script.Parent.Parent.Types)
local BrazierConfig = require(script.Parent.Parent.Config.Brazier)

local Brazier = {}

export type BuiltBrazier = {
	model: Model,
	-- The rim's world position: where the prompt hangs and where the ignition VFX is thrown from.
	rimPosition: Vector3,
	coals: { BasePart },
	flames: { BasePart },
	light: PointLight,
	lit: boolean,
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
	-- Same reasoning as the Cauldron's: the cairn below carries collision so the fixture is solid, and
	-- nothing else here answers an AI obstacle probe or a tool cast.
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- ONE BRAZIER, standing on `origin` (a floor point in the completion room).
function Brazier.build(style: Types.FixtureStyle, origin: Vector3): BuiltBrazier
	local f = BrazierConfig.fixture
	local model = Instance.new("Model")
	model.Name = "Brazier"

	-- THE CAIRN. Stacked rock under the tripod's feet, the same move the Cauldron makes: somebody
	-- built a place for this, and a bowl standing on bare cave floor reads as spawned.
	local cairn = part(
		model,
		"BrazierCairn",
		Vector3.new(f.cairnHeight, f.cairnRadius * 2, f.cairnRadius * 2),
		CFrame.new(origin + Vector3.new(0, f.cairnHeight / 2, 0)) * UPRIGHT,
		style.deckColor,
		style.deckMaterial,
		Enum.PartType.Cylinder
	)
	-- The one collidable piece. A player has to be able to stand AT this rather than inside it.
	cairn.CanCollide = true
	model.PrimaryPart = cairn

	local legTop = origin.Y + f.cairnHeight + f.legHeight
	local spread = math.rad(f.legSpread)
	local legCount = math.max(1, math.floor(f.legCount))
	-- THREE LEGS. Three cannot rock on uneven rock, which is why real tripods have three, and the
	-- gap between them is what stops the fixture reading as a solid drum.
	for index = 1, legCount do
		local angle = (index - 1) / legCount * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local footRadius = f.bowlRadius * 0.72 + math.tan(spread) * f.legHeight
		local foot = origin + Vector3.new(0, f.cairnHeight, 0) + direction * footRadius
		local head = Vector3.new(origin.X, legTop, origin.Z) + direction * (f.bowlRadius * 0.72)
		local center = (foot + head) / 2
		part(
			model,
			"BrazierLeg",
			Vector3.new(f.legThickness, f.legThickness, (head - foot).Magnitude),
			CFrame.lookAt(center, center + (head - foot).Unit),
			style.frameColor,
			style.frameMaterial
		)
	end

	-- THE BOWL, described as a floor and a wall ring rather than as a hollow solid: this game has no
	-- CSG in its object language, and a ring of segments would read as a fence.
	local bowlBaseY = legTop
	part(
		model,
		"BrazierBowlFloor",
		Vector3.new(f.bowlWallThickness, f.bowlRadius * 2, f.bowlRadius * 2),
		CFrame.new(Vector3.new(origin.X, bowlBaseY + f.bowlWallThickness / 2, origin.Z)) * UPRIGHT,
		style.vesselColor,
		style.vesselMaterial,
		Enum.PartType.Cylinder
	)
	part(
		model,
		"BrazierBowlWall",
		Vector3.new(f.bowlDepth, f.bowlRadius * 2, f.bowlRadius * 2),
		CFrame.new(Vector3.new(origin.X, bowlBaseY + f.bowlDepth / 2, origin.Z)) * UPRIGHT,
		style.vesselColor,
		style.vesselMaterial,
		Enum.PartType.Cylinder
	)

	-- THE RIM, proud of the bowl. The single line that makes the object read as a vessel from a
	-- distance, exactly as the Cauldron's does.
	local rimY = bowlBaseY + f.bowlDepth
	part(
		model,
		"BrazierRim",
		Vector3.new(f.rimHeight, (f.bowlRadius + f.rimOverhang) * 2, (f.bowlRadius + f.rimOverhang) * 2),
		CFrame.new(Vector3.new(origin.X, rimY, origin.Z)) * UPRIGHT,
		style.frameColor,
		style.frameMaterial,
		Enum.PartType.Cylinder
	)

	-- THE FUEL, heaped. Deterministic placement from the index rather than from an RNG: two braziers
	-- built on two floors are the same object, and a fixture that reshuffles itself between runs
	-- costs a player the ability to recognise it.
	local coals: { BasePart } = {}
	local coalCount = math.max(0, math.floor(f.coalCount))
	for index = 1, coalCount do
		local angle = index * 2.399 -- golden-angle spread: filled, never ringed
		local distance = f.bowlRadius * 0.62 * math.sqrt((index - 0.5) / coalCount)
		local radius = f.coalRadius * (0.72 + ((index * 37) % 9) / 22)
		local at = Vector3.new(
			origin.X + math.cos(angle) * distance,
			bowlBaseY + f.bowlWallThickness + radius * 0.75,
			origin.Z + math.sin(angle) * distance
		)
		local coal = part(
			model,
			"BrazierCoal",
			Vector3.new(radius * 2, radius * 1.5, radius * 2),
			CFrame.new(at) * CFrame.Angles(0, angle, 0),
			f.coalColor,
			Enum.Material.Slate
		)
		table.insert(coals, coal)
	end

	-- THE FIRE, built cold. Three tongues at three heights rather than the candle's single two-piece
	-- flame: a bowl fire is wider than it is tall, and one ball on a heap of coals reads as a
	-- lightbulb sitting in a bucket.
	local flames: { BasePart } = {}
	local flameCount = math.max(1, math.floor(f.flameCount))
	for index = 1, flameCount do
		local angle = index * 2.399 + 1.1
		local distance = f.bowlRadius * 0.3 * ((index - 1) / flameCount)
		local height = f.flameHeight * (1 - (index - 1) * 0.18)
		local at = Vector3.new(
			origin.X + math.cos(angle) * distance,
			bowlBaseY + f.bowlWallThickness + f.coalRadius + height * 0.4,
			origin.Z + math.sin(angle) * distance
		)
		local flame = part(
			model,
			"BrazierFlame",
			Vector3.new(height * 0.5, height, height * 0.5),
			CFrame.new(at),
			if index == 1 then f.flameCoreColor else f.flameTipColor,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		flame.CastShadow = false
		flame.Transparency = 1
		table.insert(flames, flame)
	end

	-- The one light. Created disabled: a cold brazier must be as dark as the rock it stands on, or
	-- the room gives away its own ending before anybody has earned it.
	local light = Instance.new("PointLight")
	light.Name = "BrazierLight"
	light.Color = f.lightColor
	light.Range = f.lightRange
	light.Brightness = f.lightBrightness
	light.Shadows = false
	light.Enabled = false
	light:SetAttribute(f.restBrightnessAttribute, f.lightBrightness)
	light.Parent = flames[1]

	return {
		model = model,
		rimPosition = Vector3.new(origin.X, rimY, origin.Z),
		coals = coals,
		flames = flames,
		light = light,
		lit = false,
	}
end

-- CAUGHT. Called once by `server/BrazierService` the first time any player commits here, and never
-- called back to false: a brazier that went out again would undo the one promise the object makes.
--
-- The lit prop is SHARED — every player on the floor sees the same fire — while each player's own
-- reward, results card and extraction remain entirely independent, exactly as they already were.
function Brazier.setLit(built: BuiltBrazier, lit: boolean)
	local f = BrazierConfig.fixture
	built.lit = lit
	for _, coal in built.coals do
		coal.Color = if lit then f.coalLitColor else f.coalColor
	end
	for index, flame in built.flames do
		flame.Transparency = if lit then (index - 1) * 0.14 else 1
	end
	-- Only the embers become Neon, and only once lit: what glows is the fuel, never the iron.
	if lit and #built.coals > 0 then
		built.coals[1].Color = f.emberColor
		built.coals[1].Material = Enum.Material.Neon
	end
	built.light.Enabled = lit
end

return Brazier
