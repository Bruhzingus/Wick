-- StoneWardenModel.lua
local StoneWardenModel = {}

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
	root.CanCollide = false
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
	hitbox.CanCollide = true
	hitbox.Anchored = false
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	local torsoRoot = Instance.new("Part")
	torsoRoot.Size = Vector3.new(1, 1, 1)
	torsoRoot.Transparency = 1
	torsoRoot.CanCollide = false
	torsoRoot.Anchored = true
	torsoRoot.CFrame = hitbox.CFrame * CFrame.new(0, -2, 0)
	torsoRoot.Parent = model
	weldVisual(hitbox, torsoRoot)

	local currentY = 0
	local yaw = 0
	local torsoDims = {
		{ w = 4.0, h = 1.5, d = 3.0 },
		{ w = 5.0, h = 1.8, d = 3.5 },
		{ w = 6.0, h = 2.0, d = 4.0 },
		{ w = 7.0, h = 1.5, d = 3.0 },
		{ w = 3.0, h = 1.5, d = 2.5 },
	}

	for i, d in ipairs(torsoDims) do
		yaw = yaw + (20 * (0.55 + math.random() * 0.9)) * math.pi / 180
		local cf = torsoRoot.CFrame * CFrame.new(0, currentY + d.h / 2, 0) * CFrame.Angles(0, yaw, 0)
		local slab = createSlab(model, Vector3.new(d.w, d.h, d.d), cf, (i % 3) + 1, (i % 3) + 1)
		weldVisual(hitbox, slab)
		currentY = currentY + d.h * 0.8
	end

	local headCFrame = torsoRoot.CFrame * CFrame.new(0, currentY + 1.5, 0)
	local head = createSlab(model, Vector3.new(2.5, 3.0, 3.5), headCFrame, 2, 2)
	weldVisual(hitbox, head)
	local brow = createSlab(model, Vector3.new(3.0, 0.8, 1.5), headCFrame * CFrame.new(0, 0.5, 1.5), 3, 1)
	weldVisual(hitbox, brow)

	local function buildLeg(side)
		local legRootCFrame = torsoRoot.CFrame * CFrame.new(side * 2.5, -4.0, 0)
		local thigh = createSlab(model, Vector3.new(2.2, 3.0, 2.2), legRootCFrame * CFrame.new(0, -1.5, 0), 1, 1)
		local knee = createSlab(model, Vector3.new(2.5, 1.5, 2.5), legRootCFrame * CFrame.new(0, -3.5, 0), 2, 2)
		local calf = createSlab(model, Vector3.new(1.8, 3.0, 1.8), legRootCFrame * CFrame.new(0, -5.5, 0), 3, 3)
		local foot = createSlab(model, Vector3.new(2.5, 1.5, 4.5), legRootCFrame * CFrame.new(0, -7.5, 1.0), 1, 1)
		weldVisual(hitbox, thigh)
		weldVisual(hitbox, knee)
		weldVisual(hitbox, calf)
		weldVisual(hitbox, foot)
	end
	buildLeg(-1)
	buildLeg(1)

	local function buildArm(side)
		local armRootCFrame = torsoRoot.CFrame * CFrame.new(side * 3.5, 4.5, 0)
		local upperArm = createSlab(model, Vector3.new(2.6, 3.5, 2.6), armRootCFrame * CFrame.new(0, -1.75, 0), 2, 2)
		local elbow = createSlab(model, Vector3.new(3.0, 1.5, 3.0), armRootCFrame * CFrame.new(0, -3.75, 0), 3, 3)
		local forearmCFrame = armRootCFrame * CFrame.new(0, -6.0, 1.0) * CFrame.Angles(-0.4, 0, 0)
		local forearm = createSlab(model, Vector3.new(2.2, 4.5, 2.2), forearmCFrame, 1, 1)
		local hand = createSlab(model, Vector3.new(2.8, 2.5, 2.8), forearmCFrame * CFrame.new(0, -2.5, 0.5), 2, 2)
		weldVisual(hitbox, upperArm)
		weldVisual(hitbox, elbow)
		weldVisual(hitbox, forearm)
		weldVisual(hitbox, hand)
	end
	buildArm(-1)
	buildArm(1)

	-- Dormant rubble is anchored, but an active Warden must be one movable welded assembly.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= hitbox then
			descendant.Anchored = false
			descendant.Massless = true
		end
	end

	return model
end

return StoneWardenModel
