--!strict
-- THE PER-FLOOR FIXTURES, and the one thing a cave family is allowed to say about them.
--
-- Every floor carries the same objectives: the Basin's Cauldron, the Brazier a run ends at, the
-- Descent Ladder that takes you one floor further down, and the wall lamps a player can light on the
-- way. They are the same mechanism in every cave — the sacrifice pool, the reward formula, the ride
-- and what a lit lamp is worth are identical in Stone, Moss and Ice — so a family may change what
-- they are BUILT FROM and nothing else.
--
-- ONE NESTED TABLE RATHER THAN SEPARATE TOP-LEVEL FIELDS. `presentation.blastDoorStyle` set the
-- precedent for a family dressing a piece of built infrastructure, but siblings describing one
-- concept ("what an expedition's own gear looks like down here") read better grouped than sprawled
-- across the profile type. See `Config/CaveFamilies.PresentationProfile.fixtureStyle`.
--
-- ART-BIBLE §4 BINDS EVERY COLOUR HERE. None of these surfaces self-illuminate while cold: a
-- cauldron is cold iron until the flame you are carrying finds it, and an unlit wall candle is a dead
-- object with a burnt wick. The only light any of them ever emits comes from `Config/Cauldron`,
-- `Config/Brazier` and `Config/WallLamp`, is authored there deliberately, and is never a family's to
-- raise.
--
-- THE WAX ITSELF IS NEVER FAMILY-TINTED. A wall candle's pillar is the same tallow the player is made
-- of, in every cave, because the read "this is the same stuff as me, burnt out" is the whole reason
-- the fixture is a candle. Only its iron takes a family's colour.

-- Which silhouette the ladder and the fixtures' framing take. This is a SHAPE choice, not a colour
-- one: an iron-banded timber cage, a lashed-wood platform on knotted rope, and a chipped-ice sled
-- are three different builds of the same one-person hoist, the way each family's unstable formation
-- is the same falling hazard cut from different rock.
export type FixtureRig = "Timbered" | "Lashed" | "Chipped"

export type FixtureStyle = {
	rig: FixtureRig,
	-- Structural framing: the cage's iron bands, the cauldron's tripod, the brazier's legs and rim, a
	-- wall lamp's back plate, drip pan and crown.
	frameColor: Color3,
	frameMaterial: Enum.Material,
	-- Boards and body panels: the cage deck, the cauldron's plinth, the brazier's cairn.
	deckColor: Color3,
	deckMaterial: Enum.Material,
	-- Whatever this family hangs things from — chain, knotted rope, frost-crusted chain. Used by the
	-- ladder's winch run and by a wall lamp's bracket arm and stay.
	lineColor: Color3,
	lineMaterial: Enum.Material,
	-- The vessel wall itself: the cauldron's belly, the brazier's bowl, the crowned lamp's reflector.
	vesselColor: Color3,
	vesselMaterial: Enum.Material,
}

return {}
