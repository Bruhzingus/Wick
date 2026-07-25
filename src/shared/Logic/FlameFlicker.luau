--!strict
-- Pure, frame-rate-independent candle combustion signal. This is presentation data only:
-- gameplay light, wax drain, and threat perception continue to use the stable server target.

local LightConfig = require(script.Parent.Parent.Config.Light)

export type Context = {
	draft: number,
	sprint: number,
	threat: number,
}

export type Sample = {
	brightnessMultiplier: number,
	warmth: number,
}

local FlameFlicker = {}

local function coherentNoise(timeSeconds: number, ownerPhase: number, frequencyHz: number, phaseOffset: number): number
	local flicker = LightConfig.rendering.flicker
	-- Roblox coherent noise is most precise at bounded coordinates. Travel around a closed 2D
	-- path instead of feeding it a Unix-scale server timestamp; the long loop joins seamlessly.
	local loopSeconds = math.max(flicker.loopSeconds, 1)
	local angle = (timeSeconds % loopSeconds) * math.pi * 2 / loopSeconds + phaseOffset
	local radius = frequencyHz * loopSeconds / (math.pi * 2)
	return math.clamp(
		math.noise(math.cos(angle) * radius, math.sin(angle) * radius, ownerPhase + phaseOffset * 0.173)
			* flicker.noiseScale,
		-1,
		1
	)
end

local function smoothStep(edge0: number, edge1: number, value: number): number
	if edge1 <= edge0 then
		return if value >= edge1 then 1 else 0
	end
	local t = math.clamp((value - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

function FlameFlicker.sample(timeSeconds: number, ownerUserId: number, context: Context): Sample
	local flicker = LightConfig.rendering.flicker
	if not flicker.enabled then
		return {
			brightnessMultiplier = 1,
			warmth = 0,
		}
	end

	local ownerPhase = (math.abs(ownerUserId) % flicker.ownerSeedModulo) * flicker.ownerSeedScale
	local variation = 0
	for _, layer in flicker.layers do
		variation += coherentNoise(timeSeconds, ownerPhase, layer.frequencyHz, layer.phaseOffset) * layer.amplitude
	end

	local draftWeight = math.clamp(context.draft, 0, 1)
	local sprintWeight = math.clamp(context.sprint, 0, 1)
	local threatWeight = math.clamp(context.threat, 0, 1)
	variation += coherentNoise(timeSeconds, ownerPhase, flicker.draft.frequencyHz, flicker.draft.phaseOffset) * flicker.draft.amplitude * draftWeight
	variation += coherentNoise(timeSeconds, ownerPhase, flicker.sprint.frequencyHz, flicker.sprint.phaseOffset) * flicker.sprint.amplitude * sprintWeight
	variation += coherentNoise(timeSeconds, ownerPhase, flicker.threat.frequencyHz, flicker.threat.phaseOffset) * flicker.threat.amplitude * threatWeight

	local gutterNoise = coherentNoise(timeSeconds, ownerPhase, flicker.gutter.frequencyHz, flicker.gutter.phaseOffset)
	local gutter = smoothStep(flicker.gutter.threshold, 1, (gutterNoise + 1) * 0.5)
	local brightnessMultiplier = math.clamp(
		1 + variation - gutter * flicker.gutter.depth,
		flicker.minimumBrightnessMultiplier,
		flicker.maximumBrightnessMultiplier
	)
	local brightnessLoss = math.max(0, 1 - brightnessMultiplier)
	local warmth = math.clamp(
		brightnessLoss * flicker.warmthPerBrightnessLoss + gutter * flicker.gutter.warmthBoost,
		0,
		flicker.maximumWarmthBlend
	)

	return {
		brightnessMultiplier = brightnessMultiplier,
		warmth = warmth,
	}
end

return FlameFlicker
