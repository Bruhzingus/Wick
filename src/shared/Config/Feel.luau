--!strict
-- Client-only feel and readability tuning. None of these values affect authoritative game rules:
-- they control warnings, cosmetic flame motion, debug visibility, and the shared input legend.

local Types = require(script.Parent.Parent.Types)

export type ToolControl = {
	toolId: Types.ToolId,
	keyCode: Enum.KeyCode,
	keyLabel: string,
	touchPosition: UDim2,
	audioCue: string,
}

export type MovementControl = {
	keyCode: Enum.KeyCode,
	keyLabel: string,
	displayName: string,
	touchPosition: UDim2,
	audioCue: string,
}

export type FeelConfig = {
	lowWax: {
		enabled: boolean,
		threshold: number,
		urgentThreshold: number,
		pulseFrequencyHz: number,
		normalColor: Color3,
		snuffedColor: Color3,
		warningColor: Color3,
		urgentColor: Color3,
		minColorBlend: number,
		maxColorBlend: number,
	},
	flameFlicker: {
		enabled: boolean,
		color: Color3,
		baseBrightness: number,
		brightnessAmplitude: number,
		range: number,
		frequencyHz: number,
		draftFrequencyMultiplier: number,
		draftAmplitudeMultiplier: number,
		threatAmplitudeMultiplier: number,
	},
	draftWarning: {
		enabled: boolean,
		tintColor: Color3,
		baseBrightness: number,
		brightnessAmplitude: number,
		pulseFrequencyHz: number,
		contrast: number,
	},
	waterWarning: {
		enabled: boolean,
		tintColor: Color3,
		brightness: number,
		contrast: number,
	},
	dialSnap: {
		enabled: boolean,
		trackColor: Color3,
		flashColor: Color3,
		flashSeconds: number,
	},
	dialInput: {
		sendIntervalSeconds: number,
		serverReconcileDelaySeconds: number,
	},
	threatWarning: {
		enabled: boolean,
		collectionTag: string,
		radius: number,
		scanIntervalSeconds: number,
	},
	debug: {
		showThreatLabels: boolean,
	},
	controls: {
		tools: { ToolControl },
		movement: {
			Dodge: MovementControl,
			Slide: MovementControl,
			Sprint: MovementControl,
		},
	},
	hotbar: {
		enabled: boolean,
		displayOrder: number,
		desktopPosition: UDim2,
		desktopSize: UDim2,
		touchPosition: UDim2,
		touchSize: UDim2,
		backgroundColor: Color3,
		backgroundTransparency: number,
		chipColor: Color3,
		chipTransparency: number,
		keyColor: Color3,
		textColor: Color3,
		strokeColor: Color3,
		strokeTransparency: number,
		cornerRadiusPixels: number,
		rowGapPixels: number,
		chipGapPixels: number,
		minTextSize: number,
		maxTextSize: number,
		desktopHeader: string,
		touchHeader: string,
		freeChargeFormat: string,
	},
}

local Feel: FeelConfig = {
	lowWax = {
		enabled = true,
		-- Absolute wax fraction at which the melt line begins pulsing.
		threshold = 0.25,
		urgentThreshold = 0.1,
		pulseFrequencyHz = 1.6,
		normalColor = Color3.fromRGB(235, 225, 200),
		snuffedColor = Color3.fromRGB(120, 115, 105),
		warningColor = Color3.fromRGB(255, 154, 72),
		urgentColor = Color3.fromRGB(255, 72, 48),
		minColorBlend = 0.25,
		maxColorBlend = 0.85,
	},
	flameFlicker = {
		enabled = true,
		-- A local additive light: deliberately small so it reads as flame motion, not extra sight range.
		color = Color3.fromRGB(255, 176, 92),
		baseBrightness = 0.04,
		brightnessAmplitude = 0.08,
		range = 5,
		frequencyHz = 7,
		draftFrequencyMultiplier = 2.1,
		draftAmplitudeMultiplier = 2.4,
		threatAmplitudeMultiplier = 1.45,
	},
	draftWarning = {
		enabled = true,
		tintColor = Color3.fromRGB(205, 220, 235),
		baseBrightness = -0.025,
		brightnessAmplitude = 0.035,
		pulseFrequencyHz = 5,
		contrast = 0.04,
	},
	waterWarning = {
		enabled = true,
		tintColor = Color3.fromRGB(185, 215, 235),
		brightness = -0.035,
		contrast = 0.05,
	},
	dialSnap = {
		enabled = true,
		trackColor = Color3.fromRGB(30, 28, 32),
		flashColor = Color3.fromRGB(255, 180, 80),
		flashSeconds = 0.12,
	},
	dialInput = {
		-- Keep sustained drag traffic below Security.SetBurnRate (8/s), leaving room for release.
		sendIntervalSeconds = 0.15,
		-- Do not let an in-flight StateSync overwrite a just-sent scroll/drag value.
		serverReconcileDelaySeconds = 0.35,
	},
	threatWarning = {
		enabled = true,
		collectionTag = "WickThreat",
		radius = 30,
		scanIntervalSeconds = 0.25,
	},
	debug = {
		-- Keep false for horror/readability playtests. This is intentionally config-gated for grey-box debugging.
		showThreatLabels = false,
	},
	controls = {
		tools = {
			{
				toolId = "Snuff",
				keyCode = Enum.KeyCode.One,
				keyLabel = "1",
				touchPosition = UDim2.new(0, 62, 1, -142),
				audioCue = "ToolSnuff",
			},
			{
				toolId = "Flare",
				keyCode = Enum.KeyCode.Two,
				keyLabel = "2",
				touchPosition = UDim2.new(0, 132, 1, -142),
				audioCue = "ToolFlare",
			},
			{
				toolId = "Cast",
				keyCode = Enum.KeyCode.Three,
				keyLabel = "3",
				touchPosition = UDim2.new(0, 62, 1, -72),
				audioCue = "ToolCast",
			},
			{
				toolId = "Cup",
				keyCode = Enum.KeyCode.Four,
				keyLabel = "4",
				touchPosition = UDim2.new(0, 132, 1, -72),
				audioCue = "ToolCup",
			},
		},
		movement = {
			Dodge = {
				keyCode = Enum.KeyCode.Q,
				keyLabel = "Q",
				displayName = "DODGE",
				touchPosition = UDim2.new(1, -132, 1, -72),
				audioCue = "Dodge",
			},
			Slide = {
				keyCode = Enum.KeyCode.C,
				keyLabel = "C",
				displayName = "SLIDE",
				touchPosition = UDim2.new(1, -62, 1, -72),
				audioCue = "Slide",
			},
			Sprint = {
				keyCode = Enum.KeyCode.LeftShift,
				keyLabel = "SHIFT",
				displayName = "SPRINT",
				touchPosition = UDim2.new(1, -62, 1, -142),
				audioCue = "Sprint",
			},
		},
	},
	hotbar = {
		enabled = true,
		displayOrder = 8,
		desktopPosition = UDim2.fromScale(0.5, 0.93),
		desktopSize = UDim2.fromScale(0.68, 0.105),
		-- Touch action buttons live along the bottom edges; this compact legend stays above them.
		touchPosition = UDim2.fromScale(0.5, 0.22),
		touchSize = UDim2.fromScale(0.88, 0.12),
		backgroundColor = Color3.fromRGB(12, 11, 14),
		backgroundTransparency = 0.2,
		chipColor = Color3.fromRGB(35, 32, 38),
		chipTransparency = 0.12,
		keyColor = Color3.fromRGB(255, 180, 80),
		textColor = Color3.fromRGB(232, 226, 215),
		strokeColor = Color3.fromRGB(92, 77, 62),
		strokeTransparency = 0.35,
		cornerRadiusPixels = 5,
		rowGapPixels = 4,
		chipGapPixels = 5,
		minTextSize = 9,
		maxTextSize = 18,
		desktopHeader = "CONTROLS  ·  WHEEL / RIGHT SLIDER = BRIGHTNESS",
		touchHeader = "TOUCH CONTROLS  ·  RIGHT SLIDER = BRIGHTNESS",
		freeChargeFormat = "%s · %d FREE",
	},
}

return Feel
