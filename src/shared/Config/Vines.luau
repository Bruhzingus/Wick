--!strict
-- Burning vines: a deep-floor doorway curtain that only a candle pushed to the top of its dial can
-- clear. Pure data; Logic/VineRules owns the rules, FloorPlanner places them, and the server
-- VineService owns burn state.
--
-- TWO INVARIANTS, both enforced in the planner, not here:
--   1. A vined doorway is never the only way into a room. Anyone whose dial was capped at the Basin
--      (or who sacrificed FLARE) can always reach everything a vine guards by another route.
--   2. Vines never sit on the guaranteed entry -> Brazier -> Basin route.

export type VinesConfig = {
	enabled: boolean,
	minDepth: number,
	perFloorByDepth: { number },
	chancePerEligibleDoorway: number,
	requiredBurnRateFraction: number,
	flareBurns: boolean,
	burnRadius: number,
	igniteSeconds: number,
	burnSeconds: number,
	spreadRadius: number,
	spreadDelaySeconds: number,
	hintCooldownSeconds: number,
	lowLightMessage: string,
	visual: {
		strandCount: number,
		layerCount: number,
		layerSpacing: number,
		lateralJitter: number,
		lateralOverhangFraction: number,
		strandThickness: number,
		strandLeanStuds: number,
		leavesPerStrand: number,
		leafMinSize: number,
		leafMaxSize: number,
		leafThicknessFraction: number,
		archRiseFraction: number,
		barrierThickness: number,
		barrierSkirt: number,
		strandPalette: { Color3 },
		leafPalette: { Color3 },
		charColor: Color3,
		emberColor: Color3,
		strandMaterial: Enum.Material,
		leafMaterial: Enum.Material,
	},
}

local Vines: VinesConfig = {
	enabled = true,
	-- First floor that can host a vine curtain. Earlier floors teach the dial without gating on it.
	minDepth = 5,
	-- Maximum curtains per floor, indexed by depth (clamped). More = more of the floor gated.
	perFloorByDepth = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3 },
	-- Chance an eligible (redundant, off-route) doorway is chosen once the floor still wants one.
	chancePerEligibleDoorway = 0.55,
	-- Burn threshold as a fraction of the player's current dial ceiling. A brightness sacrifice
	-- changes the light they emit, never whether pushing their own dial to maximum works as a key.
	requiredBurnRateFraction = 0.96,
	-- FLARE also burns them — it is simply never required.
	flareBurns = true,
	-- How close the flame must be to the opening (studs).
	burnRadius = 9,
	-- Seconds of continuous qualifying light needed to set a curtain alight. Short: the cost is the
	-- brightness you had to run at, not the standing around.
	igniteSeconds = 1.1,
	-- Once lit, the curtain burns itself out over this long with no further input. Dry growth does
	-- not need tending — catching a section catches the lot.
	burnSeconds = 2.6,
	-- A burning curtain throws fire to any other curtain within this many studs, which then ignites
	-- in turn. 0 disables spread and makes each doorway its own fire.
	spreadRadius = 30,
	-- Beat between one curtain catching and its neighbours doing so, so the chain reads as fire
	-- travelling rather than every doorway popping at once.
	spreadDelaySeconds = 0.55,
	-- Server-side gap between "your light is too low" hints to one player. Vines appear well past the
	-- tutorial floors, so this rides the ordinary transient message channel rather than Config/Feel's
	-- first-three-floors hint system.
	hintCooldownSeconds = 8,
	lowLightMessage = "The vines only burn at full brightness. Open the dial, or find the way around.",
	visual = {
		-- Strands per layer. The curtain is built as several overlapping layers rather than one comb,
		-- so there is no straight sightline through it from any angle.
		-- ~200 parts per curtain at these numbers. Raising any of the three multiplies that.
		strandCount = 18,
		layerCount = 3,
		-- Spacing between layers, through the doorway (studs).
		layerSpacing = 0.42,
		-- Sideways scatter on each strand, on top of its even slot. Comfortably larger than a slot
		-- width, so neighbouring strands cross instead of hanging in a row.
		lateralJitter = 0.85,
		-- Strands spill this fraction of the opening's width past each jamb, so the growth reads as
		-- something that crept over the arch rather than a fitted screen.
		lateralOverhangFraction = 0.08,
		strandThickness = 0.3,
		strandLeanStuds = 1.4,
		leavesPerStrand = 3,
		leafMinSize = 0.6,
		leafMaxSize = 1.5,
		-- Leaves are flat blades, not blobs: thickness as a fraction of their length.
		leafThicknessFraction = 0.12,
		-- Curtain height above the doorway's nominal height, as a fraction of it. Matches the widest
		-- arch FloorBuilder can cut, so a curtain always covers the whole opening.
		archRiseFraction = 0.6,
		barrierThickness = 1.2,
		-- How far the collision barrier extends below the doorway lane, so a dipping floor cannot
		-- open a crawl gap underneath the vines.
		barrierSkirt = 3,
		strandPalette = {
			Color3.fromRGB(46, 58, 34),
			Color3.fromRGB(38, 50, 30),
			Color3.fromRGB(56, 64, 38),
			Color3.fromRGB(62, 54, 36),
			Color3.fromRGB(34, 42, 28),
		},
		leafPalette = {
			Color3.fromRGB(58, 82, 44),
			Color3.fromRGB(44, 68, 38),
			Color3.fromRGB(70, 90, 48),
			Color3.fromRGB(84, 98, 52),
			Color3.fromRGB(50, 74, 50),
		},
		charColor = Color3.fromRGB(26, 22, 20),
		emberColor = Color3.fromRGB(255, 142, 54),
		-- Woody stems, leafy blades. Two materials rather than one keeps the curtain from reading as
		-- a single flat green mass under candlelight.
		strandMaterial = Enum.Material.Wood,
		leafMaterial = Enum.Material.LeafyGrass,
	},
}

return Vines
