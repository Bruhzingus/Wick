--!strict
-- Ice-family doorway barricades. They reuse the vine planner's optional-route safety proof, but melt
-- instead of burning and never spread between doorways.
--
-- WHAT THIS OBJECT HAS TO SAY, in the half second a candle first reaches it: "the way through is
-- frozen shut, and heat is what opens it". The old build said none of that — nine even vertical bars
-- and two horizontal rails read as a prison gate somebody INSTALLED in a cave, which is the one thing
-- a natural obstruction must never look like. Everything below is authored to say the opposite: the
-- ice GREW here, out of the doorway itself, and it grew downward.
--
-- THE SILHOUETTE IS BUILT FROM FOUR LAYERS, coarsest to finest:
--   CRUST  — the frozen mass welded into the arch and both jambs. This is what makes the barricade
--            part of the doorway rather than an object standing in it, and it is the last thing to
--            melt, so a half-cleared opening still reads as iced over.
--   FANGS  — tapered icicles hanging from the arch at wildly uneven lengths. The unevenness is the
--            whole read: a row of equal spikes is a comb, and a comb is a manufactured object.
--   SPIKES — shorter ice rising off the floor, laterally OFFSET from the fangs so the two rows
--            interlock. This is what closes the gap without a horizontal rail, and it is why there is
--            no straight sightline through even though every piece is vertical.
--   BLOOM  — small frost shards scattered over the crust and the fang roots, catching the flame at a
--            different angle from the smooth ice behind them.
--
-- NOTHING HERE COLLIDES. The single invisible barrier part built alongside these owns all blocking,
-- exactly as it did before; every visible piece is CanCollide/CanQuery/CanTouch false so no AI probe,
-- movement cast or placement query can see the dressing. That separation is what lets this get as
-- geometrically busy as it likes without costing a single gameplay guarantee.

export type IciclesConfig = {
	requiredBurnRateFraction: number,
	maxBrightnessMeltSeconds: number,
	flareMeltSeconds: number,
	meltRadius: number,
	puddleLifetimeSeconds: number,
	lowLightMessage: string,
	visual: {
		-- Thickness of the invisible blocking barrier, and how far the dressing may sit off the
		-- doorway plane. One value for both so a fang can never poke through its own collision.
		barDepth: number,
		-- Matches the tallest arch `buildWall` can cut, so the barricade always covers the opening.
		archRiseFraction: number,
		-- How far below the floor the invisible barrier extends, so a rolling doorway lane cannot
		-- leave a gap underneath it.
		barrierSkirt: number,

		fangCount: number,
		fangLevels: number,
		fangRootThickness: number,
		fangTipFraction: number,
		fangMinLengthFraction: number,
		fangMaxLengthFraction: number,
		fangLeanDegrees: number,
		fangDepthJitter: number,

		spikeCount: number,
		spikeLevels: number,
		spikeRootThickness: number,
		spikeMinLengthFraction: number,
		spikeMaxLengthFraction: number,

		crustDepth: number,
		crustThickness: number,
		crustBlocksPerJamb: number,
		crustBlocksAlongArch: number,

		bloomCount: number,
		bloomMinSize: number,
		bloomMaxSize: number,

		palette: { Color3 },
		meltColor: Color3,
		puddleColor: Color3,
		material: Enum.Material,
		tipMaterial: Enum.Material,
		transparency: number,
		tipTransparency: number,
		reflectance: number,
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
		barDepth = 2.2,
		archRiseFraction = 0.6,
		barrierSkirt = 3,

		-- ELEVEN FANGS ACROSS ANY WIDTH, because the doorway width varies enormously (roughly 8 to 56
		-- studs) and a fixed SPACING would put three icicles in a crevice and forty in a hall. A fixed
		-- COUNT keeps the read identical at both extremes and keeps the part budget flat.
		fangCount = 11,
		fangLevels = 4,
		fangRootThickness = 1.45,
		-- The tip is a seventh of the root. Anything blunter reads as a stalactite made of rock.
		fangTipFraction = 0.14,
		-- THE RANGE THAT DOES ALL THE WORK. Some fangs reach the floor and some barely clear the arch,
		-- so the bottom edge of the barricade is a jagged line rather than a hem.
		fangMinLengthFraction = 0.38,
		fangMaxLengthFraction = 1,
		fangLeanDegrees = 6,
		fangDepthJitter = 0.45,

		-- FEWER AND SHORTER than the fangs, and offset half a slot from them: the floor ice is what
		-- the hanging ice comes down to MEET, not a mirror of it.
		spikeCount = 7,
		spikeLevels = 3,
		spikeRootThickness = 1.2,
		spikeMinLengthFraction = 0.14,
		spikeMaxLengthFraction = 0.46,

		crustDepth = 1.9,
		crustThickness = 1.5,
		crustBlocksPerJamb = 4,
		crustBlocksAlongArch = 6,

		bloomCount = 14,
		bloomMinSize = 0.4,
		bloomMaxSize = 1.15,

		-- Cold and glassy, and deliberately spanning a real range: one flat blue across every piece is
		-- what made the old build read as moulded plastic. These are lighter than the Ice family's rock
		-- because the barricade is the thing a player is meant to walk up to and inspect — but none of
		-- them emits, so an unlit barricade is still a black shape in a black doorway.
		-- ON THE CAVE'S OWN SCALE. These ran two to four times brighter than the Ice family's rock
		-- (`CaveFamilies.ICE_ROCK`), on the theory that a barricade is something you walk up to and
		-- inspect so it should stand out. It stood out as a pale object pasted into a dark cave. A
		-- barricade is ice that GREW in that doorway, so it is made of the same stuff as the walls —
		-- clearer and a shade lighter, not a different substance. The read comes from silhouette and
		-- from the four-layer build above, never from being brighter than the room.
		palette = {
			Color3.fromRGB(44, 104, 138),
			Color3.fromRGB(56, 120, 152),
			Color3.fromRGB(34, 88, 122),
			Color3.fromRGB(66, 132, 164),
		},
		-- Melting ice does brighten as it goes wet and translucent, so this stays above the palette —
		-- but it is a state change a player should notice, not a light.
		meltColor = Color3.fromRGB(140, 190, 205),
		puddleColor = Color3.fromRGB(80, 128, 146),
		material = Enum.Material.Ice,
		-- Tips and bloom take true Glass so the thin geometry reads as clear ice against the packed
		-- ice behind it — the same two-material trick the cave walls use to separate rock from frost.
		tipMaterial = Enum.Material.Glass,
		transparency = 0.14,
		tipTransparency = 0.34,
		-- Low for the same reason the cave's own surface finishes are: with no environment to reflect,
		-- Roblox `Reflectance` washes a part pale rather than giving it a wet highlight. The builder
		-- jitters this per piece, so the authored value is the middle of the range and not its top.
		reflectance = 0.06,
	},
}

return Icicles
