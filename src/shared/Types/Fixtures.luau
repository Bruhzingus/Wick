--!strict
-- THE THREE PER-FLOOR FIXTURES, and the one thing a cave family is allowed to say about them.
--
-- Every floor carries the same three objectives: the Basin's Cauldron, the Gas Lantern that ends a
-- run, and the Descent Ladder that takes you one floor further down. They are the same mechanism in
-- every cave — the sacrifice pool, the reward formula and the ride are identical in Stone, Moss and
-- Ice — so a family may change what they are BUILT FROM and nothing else.
--
-- ONE NESTED TABLE RATHER THAN THREE TOP-LEVEL FIELDS. `presentation.blastDoorStyle` set the
-- precedent for a family dressing a piece of built infrastructure, but three siblings describing one
-- concept ("what an expedition's own gear looks like down here") read better grouped than sprawled
-- across the profile type. See `Config/CaveFamilies.PresentationProfile.fixtureStyle`.
--
-- ART-BIBLE §4 BINDS EVERY COLOUR HERE. None of these surfaces self-illuminate: a cauldron is cold
-- iron until the flame you are carrying finds it, and an unlit lantern is a dead object. The only
-- light any of the three ever emits comes from `Config/Cauldron` and `Config/Lantern`, is authored
-- there deliberately, and is never a family's to raise.

-- Which silhouette the ladder and the fixtures' framing take. This is a SHAPE choice, not a colour
-- one: an iron-banded timber cage, a lashed-wood platform on knotted rope, and a chipped-ice sled
-- are three different builds of the same one-person hoist, the way each family's unstable formation
-- is the same falling hazard cut from different rock.
export type FixtureRig = "Timbered" | "Lashed" | "Chipped"

export type FixtureStyle = {
	rig: FixtureRig,
	-- Structural framing: the cage's iron bands, the cauldron's tripod, the lantern's housing frame.
	frameColor: Color3,
	frameMaterial: Enum.Material,
	-- Boards and body panels: the cage deck, the lantern's post, the cauldron's plinth.
	deckColor: Color3,
	deckMaterial: Enum.Material,
	-- Whatever this family hangs things from — chain, knotted rope, frost-crusted chain. Used by the
	-- ladder's winch run and by the lantern's depth chain.
	lineColor: Color3,
	lineMaterial: Enum.Material,
	-- The vessel wall itself: the cauldron's belly and the lantern's lamp body.
	vesselColor: Color3,
	vesselMaterial: Enum.Material,
}

return {}
