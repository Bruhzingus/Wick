-- StoneWardenModel.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureDressing = require(ReplicatedStorage.Shared.NewModelsAndObjects.CreatureDressing)

local StoneWardenModel = {}

export type JointHandle = {
	motor: Motor6D,
	baseC0: CFrame,
}

export type ArmRig = {
	shoulder: JointHandle,
	elbow: JointHandle,
	wrist: JointHandle,
	hand: BasePart,
}

export type LegRig = {
	hip: JointHandle,
	knee: JointHandle,
	ankle: JointHandle,
	foot: BasePart,
}

export type ActiveRig = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	visualRoot: BasePart,
	spine: {
		body: JointHandle,
		pelvis: JointHandle,
		waist: JointHandle,
		chest: JointHandle,
		head: JointHandle,
	},
	arms: {
		left: ArmRig,
		right: ArmRig,
	},
	legs: {
		left: LegRig,
		right: LegRig,
	},
	-- Everything below is presentation the behaviour drives but the pose does not. Kept on the rig so
	-- the two consumers (emergence staging, squeeze grit) do not have to search the model by name.
	eyeLights: { PointLight },
	eyeParts: { BasePart },
	coreSeams: { BasePart },
	shoulderDust: ParticleEmitter,
	footDust: { left: ParticleEmitter, right: ParticleEmitter },
}

-- THE ROCK THIS THING IS MADE OF, and it has to be the rock of the cave it stands up out of.
--
-- These three colours and materials were hardcoded to Stone's slate, which meant an Ice Warden was a
-- heap of grey slate emerging from a packed-glacier wall and a Moss Warden was the same slate in a
-- wet green-grey one. The encounter's entire first beat is "that outcrop just moved" — it cannot land
-- if the outcrop never looked like part of the wall to begin with.
--
-- These stay as the FALLBACK, used when a caller has no family in hand. `setPalette` overrides them
-- for a real floor; Stone's own family values are identical to these, so a Stone Warden is unchanged.
local Palette = {
	Color3.fromRGB(52, 56, 66),
	Color3.fromRGB(62, 66, 78),
	Color3.fromRGB(45, 49, 59),
}

local Materials = {
	Enum.Material.Slate,
	Enum.Material.Basalt,
	Enum.Material.Concrete,
}

-- WHAT IS BURNING INSIDE IT, and the growth its cave has put on it. Both are family-scoped and both
-- are set by the same call as the palette, because a body dressed for one cave in the rock of another
-- would be a worse failure than the single grey Warden this replaced.
--
-- `Accent` is a Config/StoneWarden.WardenAccent. `Dressing` is a Logic/CaveFamilyRules.creatureDressing
-- result, which is the same seam the crawler, the moth and the Lurker already grow out of — Stone's is
-- "None" and costs literally nothing, so a Stone Warden gains geometry here and no growth.
local Accent = nil
local Dressing = nil

-- Module-level rather than threaded through every builder because the whole encounter is one body in
-- one cave: there is never a second Warden on a floor, and never two floors of different families
-- live at once.
function StoneWardenModel.setPalette(palette, materials)
	if palette ~= nil and #palette >= 3 then
		Palette = palette
	end
	if materials ~= nil and #materials >= 3 then
		Materials = materials
	end
end

function StoneWardenModel.setStyle(accent, dressing)
	Accent = accent
	Dressing = dressing
end

local function accentOrDefault()
	if Accent ~= nil then
		return Accent
	end
	return require(ReplicatedStorage.Shared.Config).StoneWarden.defaultAccent
end

local function createSlab(parent, size, cframe, colorIdx, matIdx)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = Palette[colorIdx]
	part.Material = Materials[matIdx]
	part.CastShadow = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = true
	part.Parent = parent
	return part
end

local function weldVisual(root, visual)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = visual
	weld.Parent = root
end

local function createActiveSlab(parent, name, size, cframe, colorIdx, matIdx)
	local part = createSlab(parent, size, cframe, colorIdx, matIdx)
	part.Name = name
	part.Anchored = false
	return part
end

-- ARMOUR, not extra limbs. Every piece built through here is welded rigidly to a segment that is
-- already jointed, so the skeleton the animator poses is byte-for-byte the one it posed before this
-- detail pass existed: the same five spine joints, the same three per limb, the same names.
--
-- `host` is the segment it rides on. `offset` is in that segment's own space, so a plate stays on the
-- shoulder it was authored for however the arm is swinging when the model is finally placed.
local function clad(host, name, size, offset, colorIdx, matIdx)
	local piece = createSlab(host.Parent, size, host.CFrame * offset, colorIdx, matIdx)
	piece.Name = name
	piece.Anchored = false
	weldVisual(host, piece)
	return piece
end

-- WHAT IS STILL ALIGHT UNDER THE ROCK. Thin seams, sunk almost flush into the slab they cross, lit by
-- the family's own accent (Config/StoneWarden.accents).
--
-- ART-BIBLE §4 forbids ROCK that is self-lit and every cave surface in the game obeys it. This is not
-- rock: it is the same allowance the roster already makes for the dark-hunter's crimson slits and the
-- Drawn's warm halo — a creature is permitted to carry its own small light, because a creature you
-- can pick out of the dark a moment before it reaches you is the difference between a threat and an
-- ambush. Nothing here has a light source; the seams are emissive surfaces only, and the ONLY actual
-- lights on the body are the two eyes below, at a range that cannot show a player the room.
local function seam(host, name, size, offset, color)
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.CFrame = host.CFrame * offset
	piece.Color = color
	piece.Material = Enum.Material.Neon
	piece.Transparency = 0.35
	piece.CastShadow = false
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.Anchored = false
	piece.Parent = host.Parent
	weldVisual(host, piece)
	return piece
end

local function createVisualRoot(parent, cframe)
	local part = Instance.new("Part")
	part.Name = "WardenVisualRoot"
	part.Size = Vector3.new(0.25, 0.25, 0.25)
	part.CFrame = cframe
	part.Transparency = 1
	part.CastShadow = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.Parent = parent
	return part
end

local function jointAt(part0, part1, pivot, name)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.C0 = part0.CFrame:ToObjectSpace(pivot)
	motor.C1 = part1.CFrame:ToObjectSpace(pivot)
	motor.Part0 = part0
	motor.Part1 = part1
	motor.Parent = part0
	return {
		motor = motor,
		baseC0 = motor.C0,
	}
end

local function dustEmitter(parent, name, color)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 1.3)
	emitter.Speed = NumberRange.new(0.5, 3)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1.5),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(color, Color3.fromRGB(38, 38, 42))
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Parent = parent
	return emitter
end

-- The dormant Warden is PART OF THE WALL, not a heap standing in open floor. `spawnCFrame` sits on
-- the ground at the foot of its wall with its look vector pointing INTO the room, so local +Z is into
-- the stone and the whole mass is laid between the wall face and the room: wide and low at the base,
-- narrowing as it rises, with the deepest slabs buried in the wall itself. What a player should read
-- walking in is an outcrop that happens to have shoulders — and then have it stand up.
--
-- The depths below stop short of `layout.wallSetback` studs so the mass fuses with the wall without
-- pushing slabs through it into the next room; nothing here collides, because the wall behind it
-- already does.
--
-- `lean` tilts a course's slabs forward out of the wall. It rises with height, so the top of the pile
-- overhangs the bottom — that overhang is the entire reason the silhouette reads as a hunched back
-- rather than as a cairn, and it is what makes the first frame of the emergence legible.
local COURSES = {
	{ y = 1.0, halfWidth = 5.0, depth = 3.1, scale = 3.4, count = 6, lean = 0.02 },
	{ y = 3.3, halfWidth = 4.2, depth = 2.8, scale = 3.0, count = 5, lean = 0.09 },
	{ y = 5.6, halfWidth = 3.4, depth = 2.4, scale = 2.6, count = 4, lean = 0.16 },
	{ y = 7.6, halfWidth = 2.4, depth = 2.1, scale = 2.3, count = 3, lean = 0.22 },
	{ y = 9.2, halfWidth = 1.3, depth = 1.9, scale = 1.9, count = 2, lean = 0.26 },
}

function StoneWardenModel.buildDormantPile(spawnCFrame)
	local model = Instance.new("Model")
	model.Name = "StoneWardenDormant"

	local root = Instance.new("Part")
	root.Size = Vector3.new(11, 10, 6)
	root.CFrame = spawnCFrame * CFrame.new(0, 5, 1.5)
	root.Transparency = 1
	root.CastShadow = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	for _, course in ipairs(COURSES) do
		for i = 1, course.count do
			-- Spread ACROSS the wall rather than around a point: the mass has to be broad and shallow,
			-- because a deep one standing out from the wall is the heap this replaced.
			local lateral = 0
			if course.count > 1 then
				lateral = -course.halfWidth + (i - 1) * (course.halfWidth * 2 / (course.count - 1))
			end
			local scale = course.scale * (0.8 + math.random() * 0.45)
			local offset = CFrame.new(
				lateral + (math.random() - 0.5) * 1.5,
				course.y + (math.random() - 0.5) * 0.9,
				course.depth + (math.random() - 0.5) * 1.1
			) * CFrame.Angles(
				-course.lean * math.pi + (math.random() - 0.5) * 0.5,
				math.random() * math.pi,
				(math.random() - 0.5) * 0.4
			)
			local rock = createSlab(
				model,
				Vector3.new(scale * 1.35, scale, scale * 0.85),
				spawnCFrame * offset,
				math.random(1, 3),
				math.random(1, 3)
			)
			weldVisual(root, rock)
		end
	end

	-- The two slabs the shoulders are actually under. Wider than anything above them and set slightly
	-- proud of the wall, so the outcrop has one horizontal line across it at the height a body's
	-- shoulders would be — the read a player gets is "that is too regular", which is all the warning
	-- this fixture is supposed to give before the wax is taken.
	for _, side in { -1, 1 } do
		local shoulder = createSlab(
			model,
			Vector3.new(4.4, 1.9, 2.6),
			spawnCFrame * CFrame.new(side * 3.1, 6.6, 2.2) * CFrame.Angles(math.rad(-14), math.rad(side * 6), 0),
			2,
			2
		)
		weldVisual(root, shoulder)
	end

	-- Dust bleeding out of the seams while the wall works itself loose. Disabled until the wake
	-- reaches its first beat; a dormant outcrop that smokes is an outcrop nobody walks up to.
	local dust = dustEmitter(root, "WardenWakeDust", Palette[2])
	dust.Rate = 0
	dust.Speed = NumberRange.new(1, 6)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 3.4),
	})

	return model, dust
end

function StoneWardenModel.buildActiveWarden(spawnCFrame)
	local Config = require(ReplicatedStorage.Shared.Config)
	local accent = accentOrDefault()
	local model = Instance.new("Model")
	model.Name = "StoneWarden"

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = Config.StoneWarden.walkSpeed
	humanoid.DisplayName = ""
	humanoid.Parent = model

	local hitbox = Instance.new("Part")
	hitbox.Name = "HumanoidRootPart"
	hitbox.Size = Vector3.new(Config.StoneWarden.squeeze.standingWidth, Config.StoneWarden.squeeze.standingHeight, 4)
	hitbox.CFrame = spawnCFrame * CFrame.new(0, Config.StoneWarden.squeeze.standingHeight / 2, 0)
	hitbox.Transparency = 1
	hitbox.CastShadow = false
	-- This part remains the complete gameplay body. It is made live only after emergence; no visible
	-- stone is allowed to collide, query, or generate touches around it. Its dimensions now come from
	-- Config/StoneWarden.squeeze rather than being written here, because the squeeze resizes THIS part
	-- and the two shapes have to be authored next to each other to stay consistent.
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.CanTouch = true
	hitbox.Massless = false
	hitbox.RootPriority = 127
	hitbox.Anchored = true
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	-- Rest geometry is authored from the floor contact frame. In the former welded body, the leg root
	-- was placed at ground height and every segment extended downward from it, burying both feet more
	-- than seven studs under the cave. These soles sit just above Y=0 even at the deepest gait bob.
	local visualRoot = createVisualRoot(model, spawnCFrame * CFrame.new(0, 3.8, 0))
	local pelvis = createActiveSlab(
		model,
		"WardenPelvis",
		Vector3.new(5.1, 1.8, 3.8),
		spawnCFrame * CFrame.new(0, 4.0, 0) * CFrame.Angles(0, math.rad(-7), 0),
		1,
		1
	)
	local waist = createActiveSlab(
		model,
		"WardenWaist",
		Vector3.new(5.7, 2.0, 3.7),
		spawnCFrame * CFrame.new(0, 5.45, 0) * CFrame.Angles(0, math.rad(8), 0),
		2,
		2
	)
	local chest = createActiveSlab(
		model,
		"WardenChest",
		Vector3.new(7.0, 2.5, 4.1),
		spawnCFrame * CFrame.new(0, 7.15, 0) * CFrame.Angles(0, math.rad(-5), 0),
		3,
		1
	)
	local head = createActiveSlab(
		model,
		"WardenHead",
		Vector3.new(3.4, 3.0, 3.7),
		spawnCFrame * CFrame.new(0, 9.65, -0.08) * CFrame.Angles(math.rad(-5), math.rad(6), 0),
		2,
		2
	)

	-- THE HEAD, WHICH IS THE ONLY PART OF THIS BODY A PLAYER EVER LOOKS AT. Everything else is mass;
	-- this is where the encounter has a face. A heavier brow with the eyes recessed UNDER it, a jaw
	-- slung forward, and two temple slabs — so that at candle range the silhouette has an overhang and
	-- two lights under it rather than a cube with dots on the front.
	clad(
		head,
		"WardenBrow",
		Vector3.new(4.0, 1.0, 1.7),
		CFrame.new(0, 0.5, -1.7) * CFrame.Angles(math.rad(-11), 0, 0),
		3,
		1
	)
	clad(
		head,
		"WardenJaw",
		Vector3.new(2.9, 1.1, 2.6),
		CFrame.new(0, -1.5, -0.75) * CFrame.Angles(math.rad(7), 0, 0),
		1,
		3
	)
	for _, side in { -1, 1 } do
		clad(
			head,
			"WardenTemple",
			Vector3.new(0.9, 1.9, 2.4),
			CFrame.new(side * 1.75, 0.25, -0.2) * CFrame.Angles(0, 0, math.rad(side * 9)),
			3,
			2
		)
		-- A short spur off the crown, angled back. Three per side would be a helmet; one is weathering.
		clad(
			head,
			"WardenCrownSpur",
			Vector3.new(0.7, 1.5, 0.8),
			CFrame.new(side * 1.1, 1.5, 0.6) * CFrame.Angles(math.rad(28), 0, math.rad(side * 16)),
			2,
			1
		)
	end

	local eyeParts = {}
	local eyeLights = {}
	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Name = "WardenEye"
		eye.Size = Vector3.new(0.62, 0.34, 0.3)
		eye.CFrame = head.CFrame * CFrame.new(side * 0.85, 0.12, -1.75) * CFrame.Angles(0, 0, math.rad(side * -8))
		eye.Color = accent.eyeColor
		eye.Material = Enum.Material.Neon
		eye.CastShadow = false
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Massless = true
		eye.Anchored = false
		eye.Parent = model
		weldVisual(head, eye)
		table.insert(eyeParts, eye)

		-- Created DISABLED. The active body is built at the same moment as the dormant pile and spends
		-- the whole pre-wake floor sitting invisible inside it; a light is not a BasePart, so the
		-- emergence transparency cross-fade cannot hide one, and two embers burning inside an outcrop
		-- would give the entire set-piece away before a player had touched the wax.
		local light = Instance.new("PointLight")
		light.Name = "WardenEyeLight"
		light.Color = accent.eyeColor
		light.Brightness = accent.eyeLightBrightness
		light.Range = accent.eyeLightRange
		light.Shadows = false
		light.Enabled = false
		light.Parent = eye
		table.insert(eyeLights, light)
	end

	local coreSeams = {}
	local function addSeam(host, name, size, offset)
		local piece = seam(host, name, size, offset, accent.coreColor)
		table.insert(coreSeams, piece)
		return piece
	end

	-- BODY PLATING. The old body was seven boxes; at candle range that reads as a stack of crates
	-- walking. These add the three lines a player actually resolves in the dark — a shoulder line
	-- wider than the hips, a back that rises to a ridge, and a chest that overhangs the waist.
	local chestSeamRng = Random.new(0x57A7)
	clad(
		chest,
		"WardenSternum",
		Vector3.new(3.6, 2.2, 1.2),
		CFrame.new(0, -0.15, -2.1) * CFrame.Angles(math.rad(-6), 0, 0),
		1,
		1
	)
	clad(
		chest,
		"WardenCollar",
		Vector3.new(5.4, 0.9, 2.6),
		CFrame.new(0, 1.35, -0.5) * CFrame.Angles(math.rad(-9), 0, 0),
		2,
		2
	)
	for index = 1, 4 do
		local t = (index - 1) / 3
		clad(
			chest,
			"WardenRidge",
			Vector3.new(1.5 - t * 0.55, 1.4 + t * 0.9, 1.1),
			CFrame.new((t - 0.5) * 2.4, -0.6 + t * 1.5, 2.05)
				* CFrame.Angles(math.rad(20 + t * 16), 0, math.rad((t - 0.5) * 22)),
			3,
			1
		)
	end
	for index = 1, math.max(0, accent.coreSeamCount) do
		local t = (index - 0.5) / math.max(1, accent.coreSeamCount)
		local host = if index % 2 == 0 then chest else waist
		local halfWidth = host.Size.X * 0.36
		addSeam(
			host,
			"WardenCoreSeam",
			Vector3.new(chestSeamRng:NextNumber(0.9, 2.0), 0.16, 0.16),
			CFrame.new((t * 2 - 1) * halfWidth, chestSeamRng:NextNumber(-0.5, 0.5), -host.Size.Z / 2 + 0.06)
				* CFrame.Angles(0, 0, chestSeamRng:NextNumber(-0.7, 0.7))
		)
	end

	clad(
		waist,
		"WardenFlankLeft",
		Vector3.new(1.1, 1.7, 3.2),
		CFrame.new(-2.7, -0.1, 0.1) * CFrame.Angles(0, 0, math.rad(-7)),
		3,
		1
	)
	clad(
		waist,
		"WardenFlankRight",
		Vector3.new(1.1, 1.7, 3.2),
		CFrame.new(2.7, -0.1, 0.1) * CFrame.Angles(0, 0, math.rad(7)),
		3,
		1
	)
	for _, side in { -1, 1 } do
		clad(
			pelvis,
			"WardenHipPlate",
			Vector3.new(1.3, 2.0, 3.0),
			CFrame.new(side * 2.4, -0.3, 0.15) * CFrame.Angles(0, 0, math.rad(side * 11)),
			2,
			3
		)
	end

	local spine = {
		body = jointAt(hitbox, visualRoot, visualRoot.CFrame, "VisualRootMotor"),
		pelvis = jointAt(visualRoot, pelvis, spawnCFrame * CFrame.new(0, 4.0, 0), "PelvisMotor"),
		waist = jointAt(pelvis, waist, spawnCFrame * CFrame.new(0, 4.85, 0), "WaistMotor"),
		chest = jointAt(waist, chest, spawnCFrame * CFrame.new(0, 6.25, 0), "ChestMotor"),
		head = jointAt(chest, head, spawnCFrame * CFrame.new(0, 8.45, -0.02), "HeadMotor"),
	}

	-- Anchors the cave family is allowed to grow things on. Deliberately no head entry: the eyes have
	-- to be the first thing that resolves at range in every family, and CreatureDressing's own contract
	-- refuses a skull anchor for exactly that reason.
	local dressingAnchors = {}
	local function anchorAt(part, normal, scale, upward, allowStrand)
		table.insert(dressingAnchors, {
			part = part,
			normal = normal,
			scale = scale,
			upward = upward,
			allowStrand = allowStrand,
		})
	end

	local function buildArm(side, sideName)
		local upperArm = createActiveSlab(
			model,
			"Warden" .. sideName .. "UpperArm",
			Vector3.new(2.7, 3.0, 2.8),
			spawnCFrame * CFrame.new(side * 3.35, 6.0, 0) * CFrame.Angles(0, 0, math.rad(side * 4)),
			2,
			2
		)
		local forearm = createActiveSlab(
			model,
			"Warden" .. sideName .. "Forearm",
			Vector3.new(2.45, 3.5, 2.55),
			spawnCFrame * CFrame.new(side * 3.48, 2.95, -0.3) * CFrame.Angles(math.rad(8), 0, 0),
			1,
			1
		)
		local hand = createActiveSlab(
			model,
			"Warden" .. sideName .. "Hand",
			Vector3.new(3.15, 1.8, 3.35),
			spawnCFrame * CFrame.new(side * 3.5, 1.18, -0.7) * CFrame.Angles(math.rad(-4), 0, math.rad(side * 3)),
			3,
			3
		)

		-- The pauldron. This is the single biggest change to the silhouette: it takes the shoulder
		-- line out past the hips, which is what makes the body read as a shape with a top-heavy mass
		-- rather than a column — and it is the thing the squeeze visibly has to pull in.
		clad(
			upperArm,
			"Warden" .. sideName .. "Pauldron",
			Vector3.new(3.5, 1.7, 3.4),
			CFrame.new(side * 0.5, 1.35, 0) * CFrame.Angles(0, 0, math.rad(side * 17)),
			3,
			1
		)
		clad(
			upperArm,
			"Warden" .. sideName .. "PauldronSpur",
			Vector3.new(1.0, 1.2, 1.2),
			CFrame.new(side * 1.7, 1.9, 0.3) * CFrame.Angles(math.rad(16), 0, math.rad(side * 34)),
			2,
			2
		)
		clad(
			forearm,
			"Warden" .. sideName .. "Bracer",
			Vector3.new(0.95, 2.6, 2.9),
			CFrame.new(side * 1.35, 0.1, 0) * CFrame.Angles(0, 0, math.rad(side * 5)),
			2,
			1
		)
		-- Knuckles. A fist reads as a threat where a slab reads as a mitten, and the contact kill is
		-- the one thing this creature does — so the part that delivers it should look like it does.
		for index = 1, 3 do
			clad(
				hand,
				"Warden" .. sideName .. "Knuckle",
				Vector3.new(0.85, 0.8, 0.95),
				CFrame.new((index - 2) * 0.95, 0.85, -1.35) * CFrame.Angles(math.rad(-12), 0, 0),
				1,
				1
			)
		end

		anchorAt(upperArm, Vector3.new(side, 0.35, 0).Unit, 3.0, true, true)
		anchorAt(forearm, Vector3.new(side, 0.1, -0.4).Unit, 2.6, false, true)
		anchorAt(hand, Vector3.new(0, 1, 0), 2.4, true, false)

		return {
			shoulder = jointAt(
				chest,
				upperArm,
				spawnCFrame * CFrame.new(side * 3.25, 7.45, 0),
				sideName .. "ShoulderMotor"
			),
			elbow = jointAt(
				upperArm,
				forearm,
				spawnCFrame * CFrame.new(side * 3.45, 4.5, -0.08),
				sideName .. "ElbowMotor"
			),
			wrist = jointAt(forearm, hand, spawnCFrame * CFrame.new(side * 3.5, 1.42, -0.55), sideName .. "WristMotor"),
			hand = hand,
		}
	end

	local function buildLeg(side, sideName)
		local thigh = createActiveSlab(
			model,
			"Warden" .. sideName .. "Thigh",
			Vector3.new(2.65, 2.6, 2.85),
			spawnCFrame * CFrame.new(side * 1.9, 2.9, 0),
			1,
			1
		)
		local calf = createActiveSlab(
			model,
			"Warden" .. sideName .. "Calf",
			Vector3.new(2.4, 1.8, 2.45),
			spawnCFrame * CFrame.new(side * 1.92, 1.25, 0.08),
			2,
			2
		)
		local foot = createActiveSlab(
			model,
			"Warden" .. sideName .. "Foot",
			Vector3.new(3.35, 1.4, 4.9),
			spawnCFrame * CFrame.new(side * 1.95, 0.95, -0.78),
			3,
			1
		)

		clad(
			calf,
			"Warden" .. sideName .. "Knee",
			Vector3.new(2.1, 1.3, 1.0),
			CFrame.new(0, 0.55, -1.4) * CFrame.Angles(math.rad(-14), 0, 0),
			1,
			2
		)
		clad(foot, "Warden" .. sideName .. "Heel", Vector3.new(2.9, 1.5, 1.4), CFrame.new(0, 0.15, 2.1), 1, 1)
		for index = 1, 3 do
			clad(
				foot,
				"Warden" .. sideName .. "Toe",
				Vector3.new(0.9, 1.0, 1.3),
				CFrame.new((index - 2) * 1.0, -0.1, -2.5) * CFrame.Angles(math.rad(6), 0, 0),
				3,
				3
			)
		end

		anchorAt(thigh, Vector3.new(side * 0.6, 0.8, 0).Unit, 2.8, true, false)
		anchorAt(calf, Vector3.new(side * 0.5, 0.3, 0.8).Unit, 2.3, false, false)

		return {
			hip = jointAt(pelvis, thigh, spawnCFrame * CFrame.new(side * 1.9, 4.05, 0), sideName .. "HipMotor"),
			knee = jointAt(thigh, calf, spawnCFrame * CFrame.new(side * 1.92, 1.72, 0.02), sideName .. "KneeMotor"),
			ankle = jointAt(calf, foot, spawnCFrame * CFrame.new(side * 1.94, 0.72, -0.2), sideName .. "AnkleMotor"),
			foot = foot,
		}
	end

	local arms = {
		left = buildArm(-1, "Left"),
		right = buildArm(1, "Right"),
	}
	local legs = {
		left = buildLeg(-1, "Left"),
		right = buildLeg(1, "Right"),
	}

	anchorAt(chest, Vector3.new(0, 0.7, 0.7).Unit, 3.4, true, false)
	anchorAt(waist, Vector3.new(0, 0.2, 1).Unit, 3.0, false, false)
	anchorAt(pelvis, Vector3.new(0, 0.5, 0.9).Unit, 3.0, true, false)

	-- The cave grows on it, through the same one builder every other body in the roster uses. Stone
	-- returns before it allocates anything, so a Stone Warden is bare rock and pays nothing.
	if Dressing ~= nil then
		CreatureDressing.apply(Dressing, dressingAnchors, 0x5A2D)
	end

	-- Grit off the shoulders while it is grinding through an opening, and off the soles on impact.
	-- Both are attached where the contact actually is, so the dust comes off the stone that is
	-- scraping rather than out of the middle of the body.
	local shoulderDust = dustEmitter(chest, "WardenSqueezeDust", Palette[2])
	local footDust = {
		left = dustEmitter(legs.left.foot, "WardenFootDust", Palette[1]),
		right = dustEmitter(legs.right.foot, "WardenFootDust", Palette[1]),
	}

	local rig = {
		model = model,
		root = hitbox,
		humanoid = humanoid,
		visualRoot = visualRoot,
		spine = spine,
		arms = arms,
		legs = legs,
		eyeLights = eyeLights,
		eyeParts = eyeParts,
		coreSeams = coreSeams,
		shoulderDust = shoulderDust,
		footDust = footDust,
	}

	return rig
end

return StoneWardenModel
