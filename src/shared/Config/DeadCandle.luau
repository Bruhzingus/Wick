--!strict
-- THE DEAD CANDLE. A rare deep-floor tableau: somebody else's candle, burned out on the cave floor,
-- with their haul still lying where they dropped it — and three VoidFlies living on the corpse.
--
-- WHY IT IS WORTH BUILDING AND WHAT IT IS MADE OF. Nothing here is a new mechanic. It is three
-- ordinary loot rolls and three ordinary threat spawns, placed together by Logic/DeadCandleRules and
-- emitted into the same `lootSpawns` / `threatSpawns` lists every other floor object uses, plus one
-- piece of scenery. What makes it an encounter is the ARRANGEMENT: the reward is inside the flies'
-- overlapping territories, so taking it is a decision about position and light rather than a pickup
-- on the way past. Three flies also means the answers scale — one flare, one teammate, or one long
-- run answers one fly, and this asks what you do about three.
--
-- IT IS A STORY BEFORE IT IS A FIGHT. A player who reads the room and leaves loses nothing they had.
-- That is the point of putting it deep: by Floor 10 a party knows what a VoidFly does, so the tableau
-- is legible on sight, and the only new information is how badly they want what is under it.
--
-- WHY FLOORS 10+. It is the first depth where the roster's own curves have finished ramping and where
-- a party is carrying enough that a bad trade costs a run. It is also the deepest authored band in
-- most spawn tables, so a rare encounter here is the variance the late floors otherwise lack.

export type DeadCandleLayout = {
	-- Ring radius the three pickups are laid out on, around the corpse. Wide enough that they cannot
	-- be swept up from one standing position, tight enough that all three sit under the flies.
	lootRingRadius: number,
	-- Ring the flies' ceiling anchors sit on. Larger than the loot ring so their patrol circuits cover
	-- the pickups rather than crossing exactly over them.
	flyRingRadius: number,
	-- Rotation between the loot ring and the fly ring, in degrees, so a pickup is never directly under
	-- a fly's anchor at spawn.
	flyRingOffsetDegrees: number,
	-- Gameplay disc kept clear around the corpse itself for the body and its spilled wax.
	corpseClearance: number,
}

export type DeadCandleConfig = {
	enabled: boolean,
	-- Global depth, not local floor: this reads the same difficulty depth every other curve does.
	minGlobalDepth: number,
	-- Rolled once per eligible floor. Deliberately low — an encounter a party expects to find is a
	-- resource node, and this is supposed to be a thing that happened to somebody.
	chancePerEligibleFloor: number,
	lootCount: number,
	flyCount: number,
	-- Which row the corpse's flies are. Named here rather than inferred so the encounter cannot
	-- silently change creature if the roster is reordered.
	threatId: string,
	layout: DeadCandleLayout,
	body: {
		-- Everything below is the toppled candle prop (NewModelsAndObjects/DeadCandle). It is scenery:
		-- no prompt, no collision, no light. A burned-out candle emits nothing, which is the whole
		-- reason the tableau is dark and the flies on it are only audible.
		height: number,
		radius: number,
		-- How far the body has slumped over, in degrees from upright. Never zero: a candle that burned
		-- out standing reads as a fixture, and this has to read as somebody who fell.
		leanDegrees: number,
		wickHeight: number,
		puddleRadius: number,
		puddleThickness: number,
		-- Cold, grey-white spent wax and the black wick. Both are unlit by design.
		waxColor: Color3,
		puddleColor: Color3,
		wickColor: Color3,
		-- Sunk slightly into the floor so the pool reads as spilled and set rather than laid on top.
		surfaceClearance: number,
	},
}

local DeadCandle: DeadCandleConfig = {
	enabled = true,
	minGlobalDepth = 10,
	chancePerEligibleFloor = 0.3,
	lootCount = 3,
	flyCount = 3,
	threatId = "VoidFly",
	layout = {
		lootRingRadius = 4.2,
		flyRingRadius = 7,
		flyRingOffsetDegrees = 60,
		corpseClearance = 6,
	},
	body = {
		-- A candle at the end of its run: barely taller than it is wide.
		height = 2.2,
		radius = 0.85,
		leanDegrees = 72,
		wickHeight = 0.5,
		puddleRadius = 2.6,
		puddleThickness = 0.18,
		waxColor = Color3.fromRGB(196, 188, 172),
		puddleColor = Color3.fromRGB(170, 162, 148),
		wickColor = Color3.fromRGB(24, 20, 18),
		surfaceClearance = -0.08,
	},
}

return DeadCandle
