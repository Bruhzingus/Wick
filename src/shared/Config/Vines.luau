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
		strandThicknessJitter: number,
		strandLeanStuds: number,
		strandMinLengthFraction: number,
		strandMaxLengthFraction: number,
		segmentsPerStrand: number,
		segmentOverlap: number,
		strandWaveStuds: number,
		strandDepthWaveStuds: number,
		branchCountPerStrand: number,
		branchMinLength: number,
		branchMaxLength: number,
		branchThickness: number,
		podChancePerBranch: number,
		podMinSize: number,
		podMaxSize: number,
		podAspectRatio: number,
		archRootCount: number,
		archRootThickness: number,
		archRootDepthJitter: number,
		archKnotCount: number,
		archKnotMinSize: number,
		archKnotMaxSize: number,
		emberRate: number,
		emberLifetimeMin: number,
		emberLifetimeMax: number,
		emberSpeedMin: number,
		emberSpeedMax: number,
		emberSpreadDegrees: number,
		emberSize: number,
		emberRise: number,
		archRiseFraction: number,
		barrierThickness: number,
		barrierSkirt: number,
		strandPalette: { Color3 },
		dryTipPalette: { Color3 },
		charColor: Color3,
		emberColor: Color3,
		strandMaterial: Enum.Material,
		dryTipMaterial: Enum.Material,
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
	lowLightMessage = "DRY VINES. Dynamite will not clear them. Hold an UNCOVERED flame at MAX brightness, use FLARE, or take the way around.",
	visual = {
		-- Two sparse ranks of segmented roots replace the old three-layer wall of flat LeafyGrass
		-- plates. The silhouette still closes the doorway, but narrow black gaps remain between the
		-- roots and every visible piece reads as part of one hanging plant rather than as a textured
		-- sheet. This also keeps a curtain below roughly 150 parts at the widest authored opening.
		strandCount = 11,
		layerCount = 2,
		layerSpacing = 0.7,
		lateralJitter = 0.42,
		lateralOverhangFraction = 0.045,
		strandThickness = 0.42,
		strandThicknessJitter = 0.22,
		strandLeanStuds = 2.2,
		strandMinLengthFraction = 0.84,
		strandMaxLengthFraction = 1,
		-- Four overlapping cylinders give each root a deliberate crooked line. One stretched cylinder
		-- per root read as a row of installed bars; dozens of tiny pieces would return to visual noise.
		segmentsPerStrand = 4,
		segmentOverlap = 0.12,
		strandWaveStuds = 0.75,
		strandDepthWaveStuds = 0.28,
		-- Short woody side branches and an occasional dead seed pod are the only small detail. There
		-- are deliberately no broad leaves: Roblox's tiled LeafyGrass texture was the rippling gold
		-- surface that made the previous curtain look corrupted under candlelight.
		branchCountPerStrand = 1,
		branchMinLength = 0.65,
		branchMaxLength = 1.35,
		branchThickness = 0.14,
		podChancePerBranch = 0.38,
		podMinSize = 0.22,
		podMaxSize = 0.42,
		podAspectRatio = 1.7,
		-- A heavy root crown visibly enters from the rock above the opening. It prevents the hanging
		-- strands from reading as suspended rods and gives the fire one coherent source to consume.
		archRootCount = 9,
		archRootThickness = 0.52,
		archRootDepthJitter = 0.32,
		archKnotCount = 7,
		archKnotMinSize = 0.55,
		archKnotMaxSize = 1.05,
		-- These sparks appear across the whole root face as soon as qualifying full-brightness light
		-- is being held. They emit no PointLight and change no rule; they are the immediate confirmation
		-- that the player's flame is actually taking hold before the 1.1-second catch completes.
		emberRate = 56,
		emberLifetimeMin = 0.45,
		emberLifetimeMax = 1,
		emberSpeedMin = 0.8,
		emberSpeedMax = 3.2,
		emberSpreadDegrees = 28,
		emberSize = 0.2,
		emberRise = 5,
		-- Curtain height above the doorway's nominal height, as a fraction of it. Matches the widest
		-- arch FloorBuilder can cut, so a curtain always covers the whole opening.
		archRiseFraction = 0.6,
		barrierThickness = 1.2,
		-- How far the collision barrier extends below the doorway lane, so a dipping floor cannot
		-- open a crawl gap underneath the vines.
		barrierSkirt = 3,
		-- Near-black wet bark with a few starved olive-brown faces. Candlelight should reveal a root
		-- silhouette first; colour variation is subordinate and never becomes a bright green wall.
		strandPalette = {
			Color3.fromRGB(34, 37, 27),
			Color3.fromRGB(42, 43, 29),
			Color3.fromRGB(49, 44, 28),
			Color3.fromRGB(29, 34, 26),
			Color3.fromRGB(54, 47, 30),
		},
		dryTipPalette = {
			Color3.fromRGB(74, 65, 40),
			Color3.fromRGB(88, 73, 43),
			Color3.fromRGB(64, 58, 38),
		},
		charColor = Color3.fromRGB(26, 22, 20),
		emberColor = Color3.fromRGB(255, 142, 54),
		-- Bark gets one restrained tiled material; the tiny dry tips are matte. No translucent,
		-- reflective, Neon, Grass, or LeafyGrass surface belongs on a cold curtain.
		strandMaterial = Enum.Material.Wood,
		dryTipMaterial = Enum.Material.SmoothPlastic,
	},
}

return Vines
