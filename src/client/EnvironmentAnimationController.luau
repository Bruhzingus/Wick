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

-- THE BASIN'S CAULDRON (Config/Cauldron). Molten wax moving in the bottom of a pot, and deliberately
-- moving very little: wax is heavy and runs like syrup, and anything faster reads as boiling water.
--
-- HERE RATHER THAN IN A CONTROLLER OF ITS OWN because it is the same job this file already does — a
-- tagged surface with a base pose and a seeded phase, bobbed locally, changing nothing authoritative.
-- A second animation system for one part would have been a second answer to a question this file has
-- already answered.
local function animateCauldrons(now: number)
	local config = Config.Cauldron
	for _, tagged in CollectionService:GetTagged(config.waxTag) do
		if not tagged:IsA("BasePart") then
			continue
		end
		local phase = numberAttribute(tagged, "WickAnimationPhase", 0)
		local baseY = numberAttribute(tagged, "WickBaseY", tagged.Position.Y)
		-- Two frequencies rather than one. A single sine reads as a mechanical bob; a slow swell with
		-- a smaller, faster wobble on top reads as a surface with something under it.
		local swell = math.sin(now * config.rippleBobSpeed + phase)
		local wobble = math.sin(now * config.rippleBobSpeed * 2.7 + phase * 1.6) * 0.35
		tagged.Position =
			Vector3.new(tagged.Position.X, baseY + (swell + wobble) * config.rippleBobStuds, tagged.Position.Z)
		local baseTransparency = numberAttribute(tagged, "WickBaseTransparency", tagged.Transparency)
		tagged.Transparency = math.clamp(baseTransparency + swell * config.rippleTransparencyPulse, 0, 1)
	end
end

function EnvironmentAnimationController.start()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		animateWater(now)
		animateCauldrons(now)
	end)
end

return EnvironmentAnimationController
