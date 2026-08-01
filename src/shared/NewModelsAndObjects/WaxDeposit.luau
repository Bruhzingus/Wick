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

-- How far below the model's base the skirt hangs. `SurfaceProbe.seat` lines the model's lowest point
-- up with the floor, so this is slack the terrain can eat: on a shelf that comes in higher than the
-- probe point, this much of the skirt goes under before any of the rock above it does.
local SKIRT_REACH = 0.9

export type BuiltDeposit = {
	model: Model,
	root: BasePart,
	seams: { BasePart },
	-- The rock masses around the seams, kept so a spent deposit can go cold as one object.
	stone: { BasePart },
	-- Where this particular rock's underside should end up relative to the ground it is seated on
	-- (negative: sunk in). Decided here rather than at the placement site so it comes out of the same
	-- seeded stream as the silhouette — how deep a rock sits is part of its shape.
	bottomOffset: number,
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

-- `seed` makes each deposit its own rock while staying reproducible: the same floor rebuilt from
-- the same plan produces the same geology. EVERY shape decision below is drawn from this one
-- stream — proportions, lean, how many masses, where the fracture runs — because a deposit that
-- varies only in its seam positions still reads as the same prop stamped down twice.
function WaxDeposit.build(seed: number): BuiltDeposit
	local visual = MiningConfig.visual
	local shape = visual.shape
	local rng = Random.new(seed)

	local model = Instance.new("Model")
	model.Name = "WaxDeposit"

	local function jitter(): number
		return rng:NextNumber(shape.sizeJitterMin, shape.sizeJitterMax)
	end
	local rockSize =
		Vector3.new(visual.rockSize.X * jitter(), visual.rockSize.Y * jitter(), visual.rockSize.Z * jitter())

	-- How far the seam-bearing mass rides above the model's base. The skirt built below fills that
	-- gap and is what ends up in the dirt, so raising this pushes wax out of the ground without ever
	-- putting air under the rock.
	local pedestal = rng:NextNumber(shape.pedestalMin, shape.pedestalMax)

	-- The core mass's own frame. Everything else is placed RELATIVE to it, so the lean carries the
	-- shoulders and the seams with it instead of leaving a tilted block wearing level decoration.
	-- Yaw is deliberately small: `SurfaceProbe.seat` turns the model to face the room so the seams
	-- greet the player, and a large twist here would throw that away.
	local core = CFrame.new(0, pedestal + rockSize.Y / 2, 0)
		* CFrame.Angles(
			rng:NextNumber(-shape.tiltRadians, shape.tiltRadians),
			rng:NextNumber(-shape.yawRadians, shape.yawRadians),
			rng:NextNumber(-shape.tiltRadians, shape.tiltRadians)
		)

	-- The root is the rock itself, so every query (range, line of sight, prompt anchoring) resolves
	-- against the thing the player is actually looking at.
	local root = part(model, "Seam", rockSize, core, visual.rockColor, Enum.Material.Slate)
	root.CanQuery = true

	local stone: { BasePart } = {}

	-- The skirt: the mass between the raised core and the floor. It reaches below the model's base so
	-- that seating the deposit buries the skirt and nothing else, and it is narrower than the core so
	-- the boulder overhangs it — an outcrop pushing up out of the ground, rather than a block resting
	-- on one. Untilted: this part's job is meeting the floor, and a leaning foot opens a gap.
	local skirtTop = pedestal + 0.35
	local skirtHeight = skirtTop + SKIRT_REACH
	for index = 1, if rng:NextNumber() < 0.5 then 2 else 1 do
		local width = rng:NextNumber(0.52, 0.8) - (index - 1) * 0.16
		local height = skirtHeight - (index - 1) * rng:NextNumber(0.2, 0.6)
		table.insert(
			stone,
			part(
				model,
				"Skirt",
				Vector3.new(rockSize.X * width, height, rockSize.Z * rng:NextNumber(0.5, 0.82)),
				CFrame.new(
					rockSize.X * rng:NextNumber(-0.16, 0.16) * (index - 1),
					skirtTop - height / 2,
					rockSize.Z * rng:NextNumber(-0.1, 0.14)
				) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0),
				visual.rockAccent,
				Enum.Material.Rock
			)
		)
	end

	-- Shoulder masses break the silhouette so it reads as geology rather than as a placed prop. How
	-- many, and how far they sit out, is per-deposit: two symmetrical bumps every time was most of
	-- what made a room full of seams look copy-pasted.
	local shoulderCount = rng:NextInteger(shape.shoulderCountMin, shape.shoulderCountMax)
	for index = 1, shoulderCount do
		local side = if index % 2 == 1 then -1 else 1
		local size = rockSize
			* Vector3.new(rng:NextNumber(0.32, 0.56), rng:NextNumber(0.4, 0.78), rng:NextNumber(0.52, 0.86))
		table.insert(
			stone,
			part(
				model,
				"Shoulder",
				size,
				-- Bottoms land near the core's base, give or take: a shoulder that rides a little high
				-- reads as a slab leaning on the boulder, one that sits low reads as rubble at its foot.
				-- Every shoulder is biased BEHIND the core's midline (+Z is away from the seam face).
				-- They are free to be as big and as turned as they like back there; in front of the
				-- face they would simply stand between the player and the wax.
				core
					* CFrame.new(
						side * rockSize.X * rng:NextNumber(0.24, 0.46),
						(size.Y - rockSize.Y) / 2 + rng:NextNumber(-0.1, 0.4),
						rockSize.Z * rng:NextNumber(0.1, 0.28)
					)
					* CFrame.Angles(
						rng:NextNumber(-0.12, 0.12),
						rng:NextNumber(-0.3, 0.3),
						side * rng:NextNumber(0.04, 0.3)
					),
				visual.rockAccent,
				Enum.Material.Rock
			)
		)
	end

	-- A crown chunk, sometimes. This is what keeps the top from being one flat lid — the single
	-- strongest "it's the same rock again" tell, because the top face is what you see approaching.
	if rng:NextNumber() < shape.spurChance then
		local size = rockSize
			* Vector3.new(rng:NextNumber(0.28, 0.52), rng:NextNumber(0.2, 0.42), rng:NextNumber(0.34, 0.62))
		table.insert(
			stone,
			part(
				model,
				"Spur",
				size,
				core
					* CFrame.new(
						rockSize.X * rng:NextNumber(-0.3, 0.3),
						-- High enough to clear the seams below it, and held off the face for the same
						-- reason the shoulders are.
						rockSize.Y * rng:NextNumber(0.32, 0.48),
						rockSize.Z * rng:NextNumber(-0.08, 0.28)
					)
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.35, 0.35)),
				visual.rockAccent,
				Enum.Material.Rock
			)
		)
	end

	-- The seams. Deliberately partial and irregular: wax caught in cracks, not a painted ore vein.
	-- They string out along ONE fracture line at a per-deposit angle, so a deposit reads as a single
	-- broken vein rather than as wax sprinkled evenly over a face.
	local seams: { BasePart } = {}
	-- Read from `visual`, not from `visual.shape`: the seam COUNT is a property of the deposit's
	-- content, and only the silhouette knobs live under `shape`. Reading them off `shape` returned nil
	-- and threw out of `math.max`, which killed every deposit on every floor before it was built.
	local count = rng:NextInteger(math.max(1, visual.seamCountMin), math.max(1, visual.seamCountMax))
	local veinX = rng:NextNumber(-0.22, 0.22)
	local veinY = rng:NextNumber(0.36, 0.62)
	local veinAngle = rng:NextNumber(-0.8, 0.8)
	-- At most one stray, and only on some deposits: wax showing around the side is a detail you find
	-- on a rock you walked around, not a feature every rock advertises.
	local strayIndex = if rng:NextNumber() < shape.sideSeamChance then rng:NextInteger(1, count) else 0

	for index = 1, count do
		-- -1 → 1 along the fracture. A lone seam sits at the vein's centre rather than at one end.
		local along = if count == 1 then 0 else ((index - 1) / (count - 1) - 0.5) * 2
		local spread = shape.seamClusterSpread
		local acrossFace =
			math.clamp(veinX + math.cos(veinAngle) * along * spread + rng:NextNumber(-0.05, 0.05), -0.4, 0.4)
		local upFace =
			math.clamp(veinY + math.sin(veinAngle) * along * spread + rng:NextNumber(-0.05, 0.05), 0.16, 0.82)
		local size = visual.seamSize
			* Vector3.new(rng:NextNumber(0.7, 1.4), rng:NextNumber(0.75, 1.45), rng:NextNumber(0.85, 1.3))
		local roll = veinAngle + rng:NextNumber(-0.3, 0.3)

		local placement: CFrame
		if index == strayIndex then
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			-- Turned a quarter turn so the seam's thin axis still points out of the face it is on, and
			-- kept to the front half of that face, ahead of where the shoulders pile up.
			placement = core
				* CFrame.new(
					side * (rockSize.X / 2 + 0.04),
					(upFace - 0.5) * rockSize.Y,
					rockSize.Z * rng:NextNumber(-0.34, -0.1)
				)
				* CFrame.Angles(0, side * math.pi / 2, roll)
		else
			placement = core
				* CFrame.new(acrossFace * rockSize.X, (upFace - 0.5) * rockSize.Y, -rockSize.Z / 2 - 0.04)
				* CFrame.Angles(0, 0, roll)
		end

		local seam = part(
			model,
			"WaxSeam",
			size,
			placement,
			-- Alternating tones so the seam has depth at the edge of a candle's reach, where it is
			-- almost always first seen.
			if index % 2 == 0 then visual.waxColor else visual.waxDeepColor,
			Enum.Material.SmoothPlastic
		)
		table.insert(seams, seam)
	end

	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = "PromptAttachment"
	-- Measured from the model's base, not from the root, so raising a rock on a taller pedestal does
	-- not drag its prompt up with it.
	promptAttachment.Position = Vector3.new(0, visual.promptHeight - pedestal - rockSize.Y / 2, 0)
	promptAttachment.Parent = root

	model.PrimaryPart = root
	CollectionService:AddTag(model, MiningVisualProtocol.depositTag)

	return {
		model = model,
		root = root,
		seams = seams,
		stone = stone,
		bottomOffset = -(visual.surfaceEmbed + rng:NextNumber(0, visual.surfaceEmbedJitter)),
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
	-- The shoulders go cold with the core. Leaving them at the accent tone left a worked rock still
	-- wearing its lit-side highlight, which read as "there is wax left here" from a distance.
	for _, mass in built.stone do
		mass.Color = visual.spentColor
	end
end

return WaxDeposit
