--!strict
-- Renders replicated candle-light targets locally. Each client owns exactly one omnidirectional
-- shadow caster (its own candle); teammate candles are smoothly interpolated fill lights.
-- A stabilized spherical shadow accent plus dominant fill masks engine shadow-map changes, while
-- deterministic combustion flicker affects only rendered brightness/color and never gameplay light.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FlameFlicker = require(ReplicatedStorage.Shared.Logic.FlameFlicker)
local LightVisualProtocol = require(ReplicatedStorage.Shared.LightVisualProtocol)

local CandleLightController = {}

type Entry = {
	attachment: Attachment,
	fill: PointLight,
	shadow: PointLight?,
	bounce: PointLight?,
	carrier: BasePart?,
	currentRange: number,
	currentBrightness: number,
	currentSprintWeight: number,
	currentThreatWeight: number,
	currentImpactMultiplier: number,
	ownerUserId: number,
	isLocal: boolean,
	-- Set only by emitters that are not a burning wick (a ghost's cold remnant). When present it
	-- replaces the configured flame colour and skips the warm flicker lerp; nil means an ordinary candle.
	overrideColor: Color3?,
}

local entries: { [Attachment]: Entry } = {}
local bloom: BloomEffect? = nil
local colorGrade: ColorCorrectionEffect? = nil
local localThreatNear = false

local function numberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function makeLight(name: string, parent: Instance, shadows: boolean, color: Color3): PointLight
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = color
	light.Shadows = shadows
	light.Enabled = false
	light.Brightness = 0
	light.Range = 0
	light.Parent = parent
	return light
end

local function makeShadowLight(parent: Instance): PointLight
	-- A candle is spherical. The old camera-facing SpotLight swept a hard cone edge across nearby
	-- cave geometry and made it appear to load in when the player moved or looked around.
	return makeLight("WickCandleShadowCore", parent, true, Config.Light.rendering.color)
end

local function makeCarrier(position: Vector3): BasePart
	local carrier = Instance.new("Part")
	carrier.Name = "WickLocalLightCarrier"
	carrier.Size = Vector3.one * Config.Light.rendering.carrierSize
	carrier.CFrame = CFrame.new(position)
	carrier.Transparency = 1
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.CastShadow = false
	carrier.Parent = workspace
	return carrier
end

local function add(instance: Instance)
	if not instance:IsA("Attachment") or entries[instance] ~= nil then
		return
	end

	local ownerUserId = numberAttribute(instance, LightVisualProtocol.attributes.ownerUserId, 0)
	local isLocal = ownerUserId == Players.LocalPlayer.UserId
	local targetRange = math.max(0, numberAttribute(instance, LightVisualProtocol.attributes.range, 0))
	local declaredColor = instance:GetAttribute(LightVisualProtocol.attributes.color)
	local overrideColor = if typeof(declaredColor) == "Color3" then declaredColor else nil
	local baseColor = overrideColor or Config.Light.rendering.color
	local carrier = if isLocal then makeCarrier(instance.WorldPosition) else nil
	local lightParent: Instance = carrier or instance
	local fill = makeLight("WickCandleFill", lightParent, false, baseColor)
	fill.Range = targetRange

	local shadow: PointLight? = nil
	local bounce: PointLight? = nil
	if isLocal then
		shadow = makeShadowLight(lightParent)
		-- The shadow and stable fill share one spherical boundary. A shorter shadow-only range would
		-- create another visibility shell as the candle crossed it.
		shadow.Range = targetRange
		bounce = makeLight("WickCandleBounce", lightParent, false, Config.Light.rendering.bounceColor)
		bounce.Range = targetRange * Config.Light.rendering.localBounceRangeFraction
	end

	entries[instance] = {
		attachment = instance,
		fill = fill,
		shadow = shadow,
		bounce = bounce,
		carrier = carrier,
		currentRange = targetRange,
		currentBrightness = 0,
		currentSprintWeight = 0,
		currentThreatWeight = 0,
		currentImpactMultiplier = 1,
		ownerUserId = ownerUserId,
		isLocal = isLocal,
		overrideColor = overrideColor,
	}
end

local function remove(instance: Instance)
	if not instance:IsA("Attachment") then
		return
	end
	local entry = entries[instance]
	if entry == nil then
		return
	end
	entry.fill:Destroy()
	if entry.shadow ~= nil then
		entry.shadow:Destroy()
	end
	if entry.bounce ~= nil then
		entry.bounce:Destroy()
	end
	if entry.carrier ~= nil then
		entry.carrier:Destroy()
	end
	if entry.isLocal then
		if bloom ~= nil then
			bloom.Enabled = false
		end
		if colorGrade ~= nil then
			colorGrade.Enabled = false
		end
	end
	entries[instance] = nil
end

local function setRendered(light: PointLight, range: number, brightness: number, activationBrightness: number)
	local threshold = Config.Light.rendering.disableBrightnessThreshold
	-- Activation follows the unflickered target so a deep gutter cannot toggle a light near zero.
	if activationBrightness <= threshold then
		light.Brightness = 0
		light.Enabled = false
		return
	end
	light.Enabled = true
	light.Range = math.max(0, range)
	light.Brightness = brightness
end

local function updatePostEffects(brightness: number)
	local strength = math.clamp(brightness / Config.Light.maxBrightness, 0, 1)
	local visible = brightness > Config.Light.rendering.disableBrightnessThreshold
	local bloomEffect = bloom
	if bloomEffect ~= nil then
		bloomEffect.Enabled = visible
		bloomEffect.Intensity = Config.Light.rendering.bloom.intensity * strength
	end
	local grade = colorGrade
	if grade ~= nil then
		grade.Enabled = visible
		grade.TintColor = Color3.new(1, 1, 1):Lerp(Config.Light.rendering.colorGrade.tintColor, strength)
		grade.Contrast = Config.Light.rendering.colorGrade.contrast * strength
		grade.Saturation = Config.Light.rendering.colorGrade.saturation * strength
	end
end

local function updateImpactMultiplier(entry: Entry, serverTime: number, dt: number): number
	local attachment = entry.attachment
	local impactFlickerUntil = numberAttribute(attachment, LightVisualProtocol.attributes.impactFlickerUntil, 0)
	if serverTime < impactFlickerUntil then
		local impact = Config.Hazards.unstableDripstone
		local pulse = (
			math.sin(serverTime * impact.flameFlickerFrequencyHz * math.pi * 2 + entry.ownerUserId * 0.173) + 1
		) / 2
		entry.currentImpactMultiplier = impact.flameFlickerMinMultiplier
			+ (1 - impact.flameFlickerMinMultiplier) * pulse
	else
		local response = Config.Light.rendering.flicker.impactReleaseSeconds
		local alpha = if response <= 0 then 1 else 1 - math.exp(-dt / response)
		entry.currentImpactMultiplier += (1 - entry.currentImpactMultiplier) * alpha
	end
	return entry.currentImpactMultiplier
end

local function render(entry: Entry, serverTime: number, dt: number)
	local attachment = entry.attachment
	local targetRange = math.max(0, numberAttribute(attachment, LightVisualProtocol.attributes.range, 0))
	local targetBrightness = math.max(0, numberAttribute(attachment, LightVisualProtocol.attributes.brightness, 0))
	if attachment:GetAttribute(LightVisualProtocol.attributes.enabled) ~= true then
		targetBrightness = 0
	end

	local response = Config.Light.rendering.transitionSeconds
	local alpha = if response <= 0 then 1 else 1 - math.exp(-dt / response)
	entry.currentRange += (targetRange - entry.currentRange) * alpha
	entry.currentBrightness += (targetBrightness - entry.currentBrightness) * alpha

	local targetSprintWeight = if entry.isLocal
			and Players.LocalPlayer:GetAttribute(Config.Feel.sprintFeedback.activeAttribute) == true
		then 1
		else 0
	local targetThreatWeight = if entry.isLocal and localThreatNear then 1 else 0
	local contextResponse = Config.Light.rendering.flicker.contextResponseSeconds
	local contextAlpha = if contextResponse <= 0 then 1 else 1 - math.exp(-dt / contextResponse)
	entry.currentSprintWeight += (targetSprintWeight - entry.currentSprintWeight) * contextAlpha
	entry.currentThreatWeight += (targetThreatWeight - entry.currentThreatWeight) * contextAlpha

	local combustion = FlameFlicker.sample(serverTime, entry.ownerUserId, {
		sprint = entry.currentSprintWeight,
		threat = entry.currentThreatWeight,
	})
	local impactMultiplier = updateImpactMultiplier(entry, serverTime, dt)
	local renderedBrightness = entry.currentBrightness * combustion.brightnessMultiplier * impactMultiplier
	local rendering = Config.Light.rendering
	-- A declared colour is used flat: combustion warmth is what a live flame does, and the only emitter
	-- that declares one is not burning.
	local override = entry.overrideColor
	local flameColor = if override ~= nil
		then override
		else rendering.color:Lerp(rendering.flicker.warmColor, combustion.warmth)
	local bounceColor = if override ~= nil
		then override
		else rendering.bounceColor:Lerp(rendering.flicker.bounceWarmColor, combustion.warmth)
	entry.fill.Color = flameColor
	if entry.shadow ~= nil then
		entry.shadow.Color = flameColor
	end
	if entry.bounce ~= nil then
		entry.bounce.Color = bounceColor
	end

	if entry.isLocal then
		local carrier = entry.carrier
		if carrier ~= nil then
			local targetPosition = attachment.WorldPosition
			local offset = targetPosition - carrier.Position
			local distance = offset.Magnitude
			local smoothedPosition: Vector3
			if
				distance >= Config.Light.rendering.positionSnapDistance
				or distance <= Config.Light.rendering.positionSettleDistance
			then
				-- Teleports and the final sub-pixel residual both snap. The latter stops an idle
				-- candle from dirtying its shadow map forever with asymptotic carrier changes.
				smoothedPosition = targetPosition
			else
				local positionResponse = Config.Light.rendering.positionResponseSeconds
				local positionAlpha = if positionResponse <= 0 then 1 else 1 - math.exp(-dt / positionResponse)
				smoothedPosition = carrier.Position + offset * positionAlpha
			end
			if smoothedPosition ~= carrier.Position then
				carrier.Position = smoothedPosition
			end
		end

		local shadowFraction = math.clamp(Config.Light.rendering.localShadowBrightnessFraction, 0, 1)
		local bounceFraction = math.clamp(Config.Light.rendering.localBounceBrightnessFraction, 0, 1 - shadowFraction)
		local fillFraction = math.max(0, 1 - shadowFraction - bounceFraction)
		setRendered(entry.fill, entry.currentRange, renderedBrightness * fillFraction, entry.currentBrightness)
		local shadow = entry.shadow
		if shadow ~= nil then
			setRendered(shadow, entry.currentRange, renderedBrightness * shadowFraction, entry.currentBrightness)
		end
		local bounceLight = entry.bounce
		if bounceLight ~= nil then
			setRendered(
				bounceLight,
				entry.currentRange * Config.Light.rendering.localBounceRangeFraction,
				renderedBrightness * bounceFraction,
				entry.currentBrightness
			)
		end
		-- Full-screen grading follows the stable target. Flickering exposure reads as a camera
		-- effect; the physical PointLights already carry the combustion signal.
		updatePostEffects(entry.currentBrightness)
	else
		setRendered(entry.fill, entry.currentRange, renderedBrightness, entry.currentBrightness)
	end
end

function CandleLightController.setLocalConditions(threatNear: boolean)
	localThreatNear = threatNear
end

function CandleLightController.start()
	local bloomEffect = Instance.new("BloomEffect")
	bloomEffect.Name = "WickCandleBloom"
	bloomEffect.Enabled = false
	bloomEffect.Intensity = 0
	bloomEffect.Size = Config.Light.rendering.bloom.size
	bloomEffect.Threshold = Config.Light.rendering.bloom.threshold
	bloomEffect.Parent = Lighting
	bloom = bloomEffect

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WickCandleGrade"
	grade.Enabled = false
	grade.Parent = Lighting
	colorGrade = grade

	for _, instance in CollectionService:GetTagged(LightVisualProtocol.tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(LightVisualProtocol.tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(LightVisualProtocol.tag):Connect(remove)
	RunService.RenderStepped:Connect(function(dt)
		local serverTime = workspace:GetServerTimeNow()
		for _, entry in entries do
			render(entry, serverTime, dt)
		end
	end)
end

return CandleLightController
