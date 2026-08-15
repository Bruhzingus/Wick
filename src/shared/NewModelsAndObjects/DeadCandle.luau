--!strict
-- The dead candle: a burned-out player's body, toppled on the cave floor with its wax spilled and
-- set around it. Pure scenery — no prompt, no collision, no light, no query — because everything the
-- encounter DOES is the loot and the flies the planner placed around it (Config/DeadCandle).
--
-- IT EMITS NOTHING, AND THAT IS THE WHOLE PROP. Every other candle in this game is a light source;
-- this one is the silhouette of one with the light taken out, so a player only ever finds it inside
-- their own. Cold grey-white spent wax against dark rock reads at candle range without a single
-- glowing part, which is the ART-BIBLE rule (nothing self-illuminates except fire) applied to the one
-- object most tempted to break it.
--
-- The lean is not decoration either: a candle that burned out standing reads as a fixture somebody
-- placed. This one fell.

local DeadCandleConfig = require(script.Parent.Parent.Config.DeadCandle)

local DeadCandle = {}

export type Built = {
	model: Model,
	root: BasePart,
}

-- Part cylinders run along local X; this stands one up.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function part(
	model: Model,
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material
): BasePart
	local created = Instance.new("Part")
	created.Name = name
	created.Shape = Enum.PartType.Cylinder
	created.Size = size
	created.CFrame = at
	created.Color = color
	created.Material = material
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

-- `seed` only spins the body's facing, so two dead candles on two floors do not lie at the same angle.
-- Nothing about the encounter's difficulty is rolled here or anywhere in this file.
function DeadCandle.build(seed: number): Built
	local body = DeadCandleConfig.body
	local model = Instance.new("Model")
	model.Name = "DeadCandle"

	-- An invisible root at the corpse's own ground point. The service seats the MODEL, so the root is
	-- a handle rather than a floor contact — every visible piece is positioned relative to it.
	local root = Instance.new("Part")
	root.Name = "Anchor"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local facing = CFrame.Angles(0, (seed % 360) * math.pi / 180, 0)

	-- The spilled pool, set hard and flush with the rock: the last of a candle that kept burning after
	-- whoever carried it stopped moving.
	part(
		model,
		"WaxPool",
		Vector3.new(body.puddleThickness, body.puddleRadius * 2, body.puddleRadius * 2),
		facing * CFrame.new(0, body.puddleThickness / 2, 0) * UPRIGHT,
		body.puddleColor,
		Enum.Material.Sand
	)

	-- The body, fallen. Pivoted at its base so the lean lifts the far end off the floor rather than
	-- sinking the near one into it.
	local lean = math.rad(math.clamp(body.leanDegrees, 0, 89))
	local bodyCFrame = facing * CFrame.Angles(lean, 0, 0) * CFrame.new(0, body.height / 2, 0)
	part(
		model,
		"Body",
		Vector3.new(body.height, body.radius * 2, body.radius * 2),
		bodyCFrame * UPRIGHT,
		body.waxColor,
		Enum.Material.SmoothPlastic
	)

	-- A cold wick, still in it. The one detail that says this used to be somebody.
	part(
		model,
		"Wick",
		Vector3.new(body.wickHeight, 0.18, 0.18),
		bodyCFrame * CFrame.new(0, body.height / 2 + body.wickHeight / 2, 0) * UPRIGHT,
		body.wickColor,
		Enum.Material.SmoothPlastic
	)

	return { model = model, root = root }
end

return DeadCandle
