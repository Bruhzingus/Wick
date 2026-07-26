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
	burnSeconds: number,
	hintCooldownSeconds: number,
	lowLightMessage: string,
	visual: {
		strandCount: number,
		strandThickness: number,
		strandLeanStuds: number,
		leavesPerStrand: number,
		leafMinSize: number,
		leafMaxSize: number,
		archRiseFraction: number,
		barrierThickness: number,
		barrierSkirt: number,
		strandPalette: { Color3 },
		leafPalette: { Color3 },
		charColor: Color3,
		emberColor: Color3,
		material: Enum.Material,
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
	-- Burn threshold as a fraction of Config/Light.maxBurnRate. Just under 1 so the top of the dial
	-- always qualifies, while a Basin brightness cap (0.6x) never does.
	requiredBurnRateFraction = 0.96,
	-- FLARE also burns them — it is simply never required.
	flareBurns = true,
	-- How close the flame must be to the opening (studs).
	burnRadius = 9,
	-- Seconds of continuous qualifying light to clear a curtain. Higher = more exposure spent.
	burnSeconds = 3.2,
	-- Server-side gap between "your light is too low" hints to one player. Vines appear well past the
	-- tutorial floors, so this rides the ordinary transient message channel rather than Config/Feel's
	-- first-three-floors hint system.
	hintCooldownSeconds = 8,
	lowLightMessage = "The vines only burn at full brightness. Open the dial, or find the way around.",
	visual = {
		strandCount = 16,
		strandThickness = 0.34,
		strandLeanStuds = 1.1,
		leavesPerStrand = 3,
		leafMinSize = 0.5,
		leafMaxSize = 1.3,
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
		},
		leafPalette = {
			Color3.fromRGB(58, 82, 44),
			Color3.fromRGB(44, 68, 38),
			Color3.fromRGB(70, 90, 48),
		},
		charColor = Color3.fromRGB(26, 22, 20),
		emberColor = Color3.fromRGB(255, 142, 54),
		material = Enum.Material.Grass,
	},
}

return Vines
