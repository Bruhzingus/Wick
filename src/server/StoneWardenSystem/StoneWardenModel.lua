-- StoneWardenModel.lua
local StoneWardenModel = {}

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

function StoneWardenModel.buildDormantPile(spawnCFrame)
	local model = Instance.new("Model")
	model.Name = "StoneWardenDormant"

	local root = Instance.new("Part")
	root.Size = Vector3.new(10, 10, 10)
	root.CFrame = spawnCFrame
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	for _ = 1, 25 do
		local scale = 2.5 + math.random() * 5.0
		local offset = CFrame.new(math.random(-6, 6), math.random(-2, 4), math.random(-6, 6))
			* CFrame.Angles(math.random(), math.random(), math.random())
		local rock = createSlab(
			model,
			Vector3.new(scale, scale * 1.3, scale),
			spawnCFrame * offset,
			math.random(1, 3),
			math.random(1, 3)
		)
		weldVisual(root, rock)
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
