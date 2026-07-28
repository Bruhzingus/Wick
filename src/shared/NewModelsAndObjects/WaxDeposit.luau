--!strict
-- The Raw Wax deposit silhouette: a low boulder shouldered into the cave wall with pale wax showing
-- through its fractures. Built server-side (the server owns progress, so it owns the model) and
-- worn down in place as the seam is struck.
--
-- It obeys the style laws exactly as strictly as the hazards do: no Neon, no PointLight, no
-- billboard, no outline. The only thing that marks it as interactive is that the one warm-coloured
-- material in a cold cave is the same wax the player is made of. If it cannot be seen without a
-- flame on it, that is correct.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MiningConfig = require(ReplicatedStorage.Shared.Config.Mining)
local MiningVisualProtocol = require(ReplicatedStorage.Shared.MiningVisualProtocol)

local WaxDeposit = {}

export type BuiltDeposit = {
	model: Model,
	root: BasePart,
	seams: { BasePart },
	promptAttachment: Attachment,
}

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

-- `seed` makes each deposit's fracture pattern its own while staying reproducible: the same floor
-- rebuilt from the same plan produces the same rock.
function WaxDeposit.build(seed: number): BuiltDeposit
	local visual = MiningConfig.visual
	local rng = Random.new(seed)

	local model = Instance.new("Model")
	model.Name = "WaxDeposit"

	-- The root is the rock itself, so every query (range, line of sight, prompt anchoring) resolves
	-- against the thing the player is actually looking at.
	local root = part(
		model,
		"Seam",
		visual.rockSize,
		CFrame.new(0, visual.rockSize.Y / 2, 0),
		visual.rockColor,
		Enum.Material.Slate
	)
	root.CanQuery = true

	-- Two shoulder masses break the silhouette so it reads as geology rather than as a placed prop.
	for index = 1, 2 do
		local side = if index == 1 then -1 else 1
		local size = visual.rockSize * Vector3.new(0.46, 0.62, 0.7)
		part(
			model,
			"Shoulder",
			size,
			CFrame.new(
				side * visual.rockSize.X * rng:NextNumber(0.3, 0.42),
				size.Y / 2 + rng:NextNumber(0, 0.25),
				rng:NextNumber(-0.4, 0.4)
			) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), side * rng:NextNumber(0.05, 0.22)),
			visual.rockAccent,
			Enum.Material.Rock
		)
	end

	-- The seams. Deliberately partial and irregular: wax caught in cracks, not a painted ore vein.
	local seams: { BasePart } = {}
	for index = 1, math.max(1, math.floor(visual.seamCount)) do
		local height = visual.rockSize.Y * rng:NextNumber(0.24, 0.76)
		local seam = part(
			model,
			"WaxSeam",
			visual.seamSize * Vector3.new(rng:NextNumber(0.7, 1.3), rng:NextNumber(0.8, 1.4), 1),
			CFrame.new(visual.rockSize.X * rng:NextNumber(-0.34, 0.34), height, -visual.rockSize.Z / 2 - 0.04)
				* CFrame.Angles(0, 0, rng:NextNumber(-0.5, 0.5)),
			-- Alternating tones so the seam has depth at the edge of a candle's reach, where it is
			-- almost always first seen.
			if index % 2 == 0 then visual.waxColor else visual.waxDeepColor,
			Enum.Material.SmoothPlastic
		)
		table.insert(seams, seam)
	end

	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = "PromptAttachment"
	promptAttachment.Position = Vector3.new(0, visual.promptHeight - visual.rockSize.Y / 2, 0)
	promptAttachment.Parent = root

	model.PrimaryPart = root
	CollectionService:AddTag(model, MiningVisualProtocol.depositTag)

	return {
		model = model,
		root = root,
		seams = seams,
		promptAttachment = promptAttachment,
	}
end

-- Wear the seam down as progress accrues. Wax retreats into the rock and cools toward the spent
-- colour, so how far along a deposit is stays legible from across the room with no UI at all.
function WaxDeposit.applyProgress(built: BuiltDeposit, progress: number)
	local visual = MiningConfig.visual
	local clamped = math.clamp(progress, 0, 1)
	for index, seam in built.seams do
		-- Staggered thresholds: seams give out one at a time rather than all fading together.
		local threshold = (index - 1) / math.max(#built.seams, 1)
		local local_ = math.clamp((clamped - threshold) * math.max(#built.seams, 1), 0, 1)
		seam.Transparency = local_
		seam.Color = (if index % 2 == 0 then visual.waxColor else visual.waxDeepColor):Lerp(visual.spentColor, local_)
	end
end

-- The seam is gone. The rock stays exactly where it was: the floor's geometry never changes under
-- a player, and a spent deposit is a landmark that says "someone worked this".
function WaxDeposit.markDepleted(built: BuiltDeposit)
	local visual = MiningConfig.visual
	for _, seam in built.seams do
		seam.Transparency = 1
	end
	built.root.Color = visual.spentColor
end

return WaxDeposit
