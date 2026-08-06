-- StoneWardenModel.lua
local StoneWardenModel = {}

export type JointHandle = {
	motor: Motor6D,
	baseC0: CFrame,
}

export type ArmRig = {
	shoulder: JointHandle,
	elbow: JointHandle,
	wrist: JointHandle,
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

-- Set once per floor by StoneWardenService from the family profile. Module-level rather than threaded
-- through every builder because the whole encounter is one body in one cave: there is never a second
-- Warden on a floor, and never two floors of different families live at once.
function StoneWardenModel.setPalette(palette, materials)
	if palette ~= nil and #palette >= 3 then
		Palette = palette
	end
	if materials ~= nil and #materials >= 3 then
		Materials = materials
	end
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

-- The dormant Warden is PART OF THE WALL, not a heap standing in open floor. `spawnCFrame` sits on
-- the ground at the foot of its wall with its look vector pointing INTO the room, so local +Z is into
-- the stone and the whole mass is laid between the wall face and the room: wide and low at the base,
-- narrowing as it rises, with the deepest slabs buried in the wall itself. What a player should read
-- walking in is an outcrop that happens to have shoulders — and then have it stand up.
--
-- The depths below stop short of `layout.wallSetback` studs so the mass fuses with the wall without
-- pushing slabs through it into the next room; nothing here collides, because the wall behind it
-- already does.
local COURSES = {
	{ y = 1.1, halfWidth = 4.6, depth = 3.0, scale = 3.3, count = 5 },
	{ y = 3.6, halfWidth = 3.8, depth = 2.7, scale = 2.9, count = 4 },
	{ y = 6.0, halfWidth = 2.9, depth = 2.4, scale = 2.5, count = 3 },
	{ y = 8.0, halfWidth = 1.6, depth = 2.1, scale = 2.1, count = 2 },
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
			) * CFrame.Angles((math.random() - 0.5) * 0.5, math.random() * math.pi, (math.random() - 0.5) * 0.4)
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
	return model
end

function StoneWardenModel.buildActiveWarden(spawnCFrame)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = require(ReplicatedStorage.Shared.Config)
	local model = Instance.new("Model")
	model.Name = "StoneWarden"

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = Config.StoneWarden.walkSpeed
	humanoid.DisplayName = ""
	humanoid.Parent = model

	local hitbox = Instance.new("Part")
	hitbox.Name = "HumanoidRootPart"
	hitbox.Size = Vector3.new(6, 12, 4)
	hitbox.CFrame = spawnCFrame * CFrame.new(0, 6, 0)
	hitbox.Transparency = 1
	hitbox.CastShadow = false
	-- This exact 6x12x4 part remains the complete gameplay body. It is made live only after
	-- emergence; no visible stone is allowed to collide, query, or generate touches around it.
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
	local brow = createActiveSlab(
		model,
		"WardenBrow",
		Vector3.new(3.8, 0.85, 1.5),
		head.CFrame * CFrame.new(0, 0.45, -1.62) * CFrame.Angles(math.rad(-8), 0, 0),
		3,
		1
	)
	weldVisual(head, brow)

	local spine = {
		body = jointAt(hitbox, visualRoot, visualRoot.CFrame, "VisualRootMotor"),
		pelvis = jointAt(visualRoot, pelvis, spawnCFrame * CFrame.new(0, 4.0, 0), "PelvisMotor"),
		waist = jointAt(pelvis, waist, spawnCFrame * CFrame.new(0, 4.85, 0), "WaistMotor"),
		chest = jointAt(waist, chest, spawnCFrame * CFrame.new(0, 6.25, 0), "ChestMotor"),
		head = jointAt(chest, head, spawnCFrame * CFrame.new(0, 8.45, -0.02), "HeadMotor"),
	}

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
		return {
			hip = jointAt(pelvis, thigh, spawnCFrame * CFrame.new(side * 1.9, 4.05, 0), sideName .. "HipMotor"),
			knee = jointAt(thigh, calf, spawnCFrame * CFrame.new(side * 1.92, 1.72, 0.02), sideName .. "KneeMotor"),
			ankle = jointAt(calf, foot, spawnCFrame * CFrame.new(side * 1.94, 0.72, -0.2), sideName .. "AnkleMotor"),
			foot = foot,
		}
	end

	local rig = {
		model = model,
		root = hitbox,
		humanoid = humanoid,
		visualRoot = visualRoot,
		spine = spine,
		arms = {
			left = buildArm(-1, "Left"),
			right = buildArm(1, "Right"),
		},
		legs = {
			left = buildLeg(-1, "Left"),
			right = buildLeg(1, "Right"),
		},
	}

	return rig
end

return StoneWardenModel
