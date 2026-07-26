--!strict
-- Lightweight local animation for replicated cave hazard primitives. Mechanics use the static
-- server zones; these small visual motions never change authoritative water depth.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local EnvironmentAnimationController = {}

local WATER_TAG = "WickWaterSurface"

local function numberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function animateWater(now: number)
	local animation = Config.Hazards.animation
	for _, tagged in CollectionService:GetTagged(WATER_TAG) do
		if not tagged:IsA("BasePart") then
			continue
		end
		local phase = numberAttribute(tagged, "WickAnimationPhase", 0)
		local wave = math.sin(now * animation.waterBobSpeed + phase)
		local baseY = numberAttribute(tagged, "WickBaseY", tagged.Position.Y)
		tagged.Position = Vector3.new(tagged.Position.X, baseY + wave * animation.waterBobHeight, tagged.Position.Z)
		local baseTransparency = numberAttribute(tagged, "WickBaseTransparency", tagged.Transparency)
		tagged.Transparency = math.clamp(baseTransparency + wave * animation.waterTransparencyPulse, 0, 1)

		local gradient = tagged:FindFirstChild("FlowGradient", true)
		if gradient ~= nil and gradient:IsA("UIGradient") then
			local travel = (now * animation.waterSheenTravelSpeed + phase / (math.pi * 2)) % 2 - 1
			gradient.Offset = Vector2.new(
				travel,
				math.sin(now * animation.waterSheenCrossSpeed + phase) * animation.waterSheenCrossAmount
			)
		end
	end
end

function EnvironmentAnimationController.start()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		animateWater(now)
	end)
end

return EnvironmentAnimationController
