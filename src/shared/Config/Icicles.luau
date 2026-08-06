--!strict
-- Ice-family doorway bars. They reuse the vine planner's optional-route safety proof, but melt
-- instead of burning and never spread between doorways.

export type IciclesConfig = {
	requiredBurnRateFraction: number,
	maxBrightnessMeltSeconds: number,
	flareMeltSeconds: number,
	meltRadius: number,
	puddleLifetimeSeconds: number,
	lowLightMessage: string,
	visual: {
		barCount: number,
		barThickness: number,
		barDepth: number,
		heightJitter: number,
		railThickness: number,
		archRiseFraction: number,
		barrierSkirt: number,
		iceColor: Color3,
		meltColor: Color3,
		puddleColor: Color3,
		material: Enum.Material,
	},
}

local Icicles: IciclesConfig = {
	requiredBurnRateFraction = 0.96,
	-- Maximum brightness is a costly but reliable key; a Flare removes the same obstruction fast.
	maxBrightnessMeltSeconds = 6,
	flareMeltSeconds = 1.2,
	meltRadius = 9,
	puddleLifetimeSeconds = 10,
	lowLightMessage = "The ice bars melt only at maximum brightness. A Flare will melt them much faster.",
	visual = {
		barCount = 9,
		barThickness = 0.72,
		barDepth = 0.9,
		heightJitter = 1.35,
		railThickness = 0.58,
		archRiseFraction = 0.6,
		barrierSkirt = 3,
		iceColor = Color3.fromRGB(116, 163, 181),
		meltColor = Color3.fromRGB(174, 214, 224),
		puddleColor = Color3.fromRGB(80, 128, 146),
		material = Enum.Material.Ice,
	},
}

return Icicles
