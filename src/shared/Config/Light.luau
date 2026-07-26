--!strict
-- Light output tuning: how the brightness dial (burn rate) maps to the candle's light (DESIGN §4).
-- Pure data. Logic/BrightnessMap computes authoritative targets; clients render the PointLights.

local Types = require(script.Parent.Parent.Types)

export type DialConfig = {
	scrollStep: number,
	snapPoints: { number },
	snapRadius: number,
}

export type FlickerLayerConfig = {
	frequencyHz: number,
	amplitude: number,
	phaseOffset: number,
}

export type FlickerContextConfig = {
	frequencyHz: number,
	amplitude: number,
	phaseOffset: number,
}

export type FlickerConfig = {
	enabled: boolean,
	minimumBrightnessMultiplier: number,
	maximumBrightnessMultiplier: number,
	contextResponseSeconds: number,
	impactReleaseSeconds: number,
	loopSeconds: number,
	noiseScale: number,
	ownerSeedModulo: number,
	ownerSeedScale: number,
	layers: { FlickerLayerConfig },
	gutter: {
		frequencyHz: number,
		phaseOffset: number,
		threshold: number,
		depth: number,
		warmthBoost: number,
	},
	sprint: FlickerContextConfig,
	threat: FlickerContextConfig,
	warmthPerBrightnessLoss: number,
	maximumWarmthBlend: number,
	warmColor: Color3,
	bounceWarmColor: Color3,
}

export type RenderingConfig = {
	color: Color3,
	bounceColor: Color3,
	transitionSeconds: number,
	positionResponseSeconds: number,
	positionSnapDistance: number,
	positionSettleDistance: number,
	carrierSize: number,
	disableBrightnessThreshold: number,
	localShadowBrightnessFraction: number,
	localBounceBrightnessFraction: number,
	localBounceRangeFraction: number,
	flicker: FlickerConfig,
	bloom: {
		intensity: number,
		size: number,
		threshold: number,
	},
	colorGrade: {
		tintColor: Color3,
		contrast: number,
		saturation: number,
	},
}

export type LightConfig = {
	minBurnRate: Types.BurnRate,
	maxBurnRate: Types.BurnRate,
	minRange: number,
	maxRange: number,
	minBrightness: number,
	maxBrightness: number,
	minIntensity: number,
	maxIntensity: number,
	falloffExponent: number,
	dial: DialConfig,
	rendering: RenderingConfig,
}

local Light: LightConfig = {
	-- The ordinary dial deliberately occupies a middle band. CUP and FLARE own near-darkness and
	-- overwhelming brightness, so neither dial endpoint replaces those threat-counterplay tools.
	minBurnRate = 0.18,
	-- Highest the dial can go, before a Basin MaxBrightness cap.
	maxBurnRate = 0.78,
	-- PointLight.Range (studs) at minBurnRate. Ordinary low burn remains navigable; CUP is darker.
	minRange = 10,
	-- PointLight.Range (studs) at maxBurnRate. FLARE reaches far beyond this ceiling.
	maxRange = 30,
	-- PointLight.Brightness at minBurnRate.
	minBrightness = 0.9,
	-- PointLight.Brightness at maxBurnRate.
	maxBrightness = 2.6,
	-- Threat-field strength at the dial endpoints. Kept separate from rendered Brightness so the
	-- ordinary dial can influence threat reads without ever becoming FLARE's forced-retreat effect.
	minIntensity = 0.18,
	maxIntensity = 0.42,
	-- Shape of the burnRate -> range/brightness curve (t ^ exponent). >1 = stays dim until you push the dial high.
	falloffExponent = 1.0,
	-- Input feel of the dial itself (client-side; server still clamps the result).
	dial = {
		-- Burn-rate change per scroll-wheel notch. Smaller = finer control.
		scrollStep = 0.05,
		-- Dial values the slider gently snaps to. Skill expression lives between them.
		snapPoints = { 0.3, 0.5, 0.7 },
		-- How close (in burn rate) the thumb must be to a snap point to stick.
		snapRadius = 0.02,
	},
	-- Client-only rendering. Gameplay light perception remains authoritative in LightSources.
	rendering = {
		color = Color3.fromRGB(255, 190, 100),
		bounceColor = Color3.fromRGB(255, 132, 58),
		-- Exponential response time for dial changes, ignition, and snuffing.
		transitionSeconds = 0.2,
		-- The client shadow emitter follows the flame with a tiny stabilizing delay. Teleports snap.
		positionResponseSeconds = 0.055,
		positionSnapDistance = 8,
		-- Complete tiny residual moves so an idle shadow map becomes truly stationary.
		positionSettleDistance = 0.01,
		carrierSize = 0.1,
		-- Switch fully off only after a fade reaches this brightness.
		disableBrightnessThreshold = 0.01,
		-- One full-range spherical PointLight supplies soft shadow detail. Most output remains in the
		-- stable unshadowed fill, so a client quality/terrain shadow-LOD change cannot hide geometry.
		-- There is exactly one shadowed light per client regardless of party size.
		localShadowBrightnessFraction = 0.35,
		-- A short-range amber layer approximates warm cave-surface bounce without another shadow map.
		localBounceBrightnessFraction = 0.1,
		localBounceRangeFraction = 0.58,
		-- Physical flame variation is client-rendered only. The authoritative gameplay light,
		-- PointLight range, Enabled threshold, and stabilized shadow emitter never fluctuate.
		flicker = {
			enabled = true,
			-- Idle combustion normally stays near 0.91-1.09. The wider floor is reserved for a
			-- rare combustion gutter or a dripstone impact.
			minimumBrightnessMultiplier = 0.76,
			maximumBrightnessMultiplier = 1.1,
			-- Environmental states crossfade instead of jumping to a new noise phase.
			contextResponseSeconds = 0.16,
			-- A dripstone strike may gutter immediately, then recover without a final hard pop.
			impactReleaseSeconds = 0.12,
			-- A seamless bounded coordinate loop avoids floating-point quantization from feeding
			-- Unix-scale server timestamps directly into coherent noise.
			loopSeconds = 1024,
			-- Roblox coherent noise has a deliberately conservative native range; normalize it
			-- before the final configured bounds are applied.
			noiseScale = 2,
			ownerSeedModulo = 104729,
			ownerSeedScale = 0.0047,
			-- Three time scales read as fuel drift, flame-body movement, and fine turbulence.
			layers = {
				{ frequencyHz = 0.48, amplitude = 0.024, phaseOffset = 11.7 },
				{ frequencyHz = 3.15, amplitude = 0.046, phaseOffset = 37.1 },
				{ frequencyHz = 9.2, amplitude = 0.018, phaseOffset = 83.6 },
			},
			gutter = {
				frequencyHz = 0.105,
				phaseOffset = 149.3,
				threshold = 0.78,
				depth = 0.14,
				warmthBoost = 0.22,
			},
			-- Fixed context bands are blended in by weight. Their phases never change when a
			-- state begins, so sprint transitions cannot snap the illumination.
			sprint = { frequencyHz = 10.7, amplitude = 0.035, phaseOffset = 307.2 },
			threat = { frequencyHz = 4.4, amplitude = 0.014, phaseOffset = 401.8 },
			-- A weakening flame shifts slightly toward ember orange; it never becomes a color strobe.
			warmthPerBrightnessLoss = 1.65,
			maximumWarmthBlend = 0.42,
			warmColor = Color3.fromRGB(255, 145, 68),
			bounceWarmColor = Color3.fromRGB(255, 96, 38),
		},
		bloom = {
			intensity = 0.14,
			size = 16,
			threshold = 0.92,
		},
		colorGrade = {
			tintColor = Color3.fromRGB(255, 242, 220),
			contrast = 0.045,
			saturation = -0.06,
		},
	},
}

return Light
