--!strict
-- THE BASIN'S CAULDRON — the vessel the sacrifice happens over (DESIGN §10).
--
-- PRESENTATION ONLY. Nothing in this file is read by `Logic/SacrificeRules`, `server/BasinService`
-- or `client/BasinPrompt`: the offer pool, the grant band, the one-exchange-per-floor rule and the
-- privacy of an offer are all exactly what they were when this fixture was a flat orange disc. What
-- changed is that the room now contains an object instead of a decal.
--
-- WHY A VESSEL AT ALL. ART-BIBLE describes this room as "a shallow stone basin/font of glowing
-- liquid wax... a place of ritual rather than danger", and a 16-stud Neon circle painted on the
-- floor is the one reading of that sentence with no object in it. A squat iron pot on a tripod,
-- wax moving in the bottom of it and set wax run down the outside, says the same thing with a
-- silhouette — which is what a player actually finds at the edge of candle range.
--
-- SCALE IS SET BY THE PLAYER, NOT BY THE ROOM. A candle is four studs tall at full wax
-- (`Config/Character.heightAtFullWax`) with its eye a little above that, so the rim below sits just
-- under eye height: you walk up to this and look DOWN into it. Every number here is authored
-- against that one relationship and should be retuned against it.
--
-- NOTHING HERE IS A LIGHT SOURCE. The wax surface is Neon — self-illuminating pixels, visible in
-- the dark without lighting one voxel of rock — and the coals under the belly are Neon at high
-- transparency. Neither carries a PointLight, which is the exact line ART-BIBLE §4 draws and the
-- same line the dynamite socket marker and every loot silhouette already sit on.

export type CauldronConfig = {
	bellyRadius: number,
	bellyHeight: number,
	rimOverhang: number,
	rimHeight: number,
	legCount: number,
	legHeight: number,
	legThickness: number,
	plinthRadius: number,
	plinthHeight: number,
	waxColor: Color3,
	waxTransparency: number,
	waxInset: number,
	runnelCount: number,
	runnelWidth: number,
	emberColor: Color3,
	emberTransparency: number,
	rippleBobStuds: number,
	rippleBobSpeed: number,
	rippleTransparencyPulse: number,
	promptHeight: number,
	waxTag: string,
}

local Cauldron: CauldronConfig = {
	-- The pot itself. Wider than it is tall: a cauldron, not a barrel.
	bellyRadius = 2.2,
	bellyHeight = 1.9,
	-- The lip, proud of the belly on all sides. This is the edge the candle catches first and the
	-- reason the object still reads as an open vessel when only its top is lit.
	rimOverhang = 0.28,
	rimHeight = 0.34,
	-- The tripod. Three legs, never four: three cannot rock on an uneven cave floor, and the odd
	-- number stops the silhouette reading as a table.
	legCount = 3,
	legHeight = 1.1,
	legThickness = 0.42,
	-- A low cairn of set stone the tripod stands on, so the fixture has a base that meets the ground
	-- instead of three thin legs ending in rock.
	plinthRadius = 2.9,
	plinthHeight = 0.5,
	-- THE ESTABLISHED AMBER, carried over unchanged from the flat disc this replaces. The Basin's
	-- colour is already load-bearing (it is how the room is recognised from a doorway) and this
	-- overhaul deliberately did not retune it.
	waxColor = Color3.fromRGB(255, 180, 80),
	waxTransparency = 0.06,
	-- How far below the rim the wax sits. Enough that the pot is visibly not full — a vessel filled
	-- to its lip reads as a solid orange cylinder from any angle above it.
	waxInset = 0.55,
	-- Set wax run down the outside, in `Config/DripTrail.dripColor`. The same "this was liquid and
	-- then it stopped being" detail Frozen Wax's loot silhouette uses.
	runnelCount = 5,
	runnelWidth = 0.34,
	-- The coals implied under the belly. Deliberately dull and mostly transparent: this is a hint of
	-- a heat source, not a second fire in a game with exactly one.
	emberColor = Color3.fromRGB(120, 40, 18),
	emberTransparency = 0.62,
	-- The surface's slow movement, rendered locally by client/EnvironmentAnimationController from the
	-- same tag-and-attribute pattern the water surfaces already use. Small on purpose: molten wax is
	-- heavy and moves like syrup, and anything faster reads as boiling water.
	rippleBobStuds = 0.055,
	rippleBobSpeed = 0.9,
	rippleTransparencyPulse = 0.05,
	-- Where the existing "Offer yourself" prompt floats, measured from the room floor. Just above the
	-- rim, so the prompt belongs to the pot rather than hovering inside it.
	promptHeight = 4.2,
	waxTag = "WickCauldronWax",
}

return Cauldron
