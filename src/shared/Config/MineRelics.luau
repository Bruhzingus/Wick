--!strict
-- THE OLD WORKINGS — the rare, long-abandoned mining equipment left in these caves by whoever was
-- down here before you. A derailed ore cart, a run of buckled rail, a rotted prop frame, a keg of
-- blasting powder nobody came back for.
--
-- WHAT THEY ARE FOR, AND THE ONE THING THEY MAY NEVER BECOME. These are ambience: they say the cave
-- has a history and that somebody else ran out of light in it. They are NOT content. No relic holds
-- loot, opens a prompt, feeds the light or sound field, or is read by any rule — a player who walks
-- past one has lost nothing, which is exactly the relationship the dead candle already has with its
-- own corpse prop (Config/DeadCandle). If a relic ever needs to DO something it stops being dressing
-- and needs a planner placement and a service, like every other object in the game.
--
-- RARITY IS THE WHOLE POINT AND IS TUNED HERE. Seen every floor these become wallpaper and the cave
-- stops being a cave that was never meant to be found. Two gates do it: a floor first rolls whether
-- it has any workings at all, then a small per-room chance places at most `maxPerFloor` of them. On
-- top of that `Logic/MineRelicRules` walks the catalog rather than re-rolling it, so consecutive
-- floors cannot hand you the same silhouette twice.
--
-- WHAT THE SHIPPED NUMBERS ACTUALLY PRODUCE, measured over three thousand simulated twelve-floor
-- descents against real room masks: about 44% of floors carry anything at all, 0.66 pieces per floor,
-- and roughly one floor between sightings. A twelve-floor run therefore meets around eight pieces
-- spread over five floors and never the same silhouette twice running. Note that the room roll is
-- NOT the last word — a room that rolls a relic can still fail to seat it, because a four-door room
-- is mostly doorway lane and a large piece genuinely has nowhere legal to stand. That refusal is the
-- system working: fewer relics is always the right answer over one standing in a walkway.
--
-- ART-BIBLE §2 says environments are readable geometry and not decorated spaces, and that law is
-- what shapes every number below rather than something these are exempt from: one object, wide
-- apart, flat readable silhouette, no surface noise, and a palette of dead iron and rotted timber
-- that carries no colour a player could mistake for information. Nothing here self-illuminates —
-- the lantern on the hook post is COLD, which is the point of hanging it there.
--
-- SIZES AND PROPORTIONS ARE NOT HERE. They live with the silhouettes in
-- `NewModelsAndObjects/MineRelics`, the way CaveKit's formations and LootPickup's pickups own
-- theirs. What this file owns is everything a designer would actually retune: how often a relic
-- appears, where it may stand, what it is made of, and how far it has to stay from a route.

export type RelicAnchoring = "Open" | "Wall"

export type RelicDef = {
	id: string,
	-- Draw weight inside the catalog walk. Higher is not "more often per floor" — the floor gates
	-- decide that — it is "more often the piece that floor turned out to have".
	weight: number,
	-- Global depth this piece may first appear at. Rail infrastructure is shallow-workings kit and the
	-- deeper pieces read as somebody pushing further than they should have.
	minDepth: number,
	-- Conservative XZ disc the piece occupies. Everything routing-related is measured from this, so it
	-- is authored a little generous rather than tight to the geometry.
	footprintRadius: number,
	-- Headroom the piece needs. A room with a lower roof simply does not get this relic.
	minCeilingHeight: number,
	-- `Wall` pieces are pushed out to the rock face and turned to look back into the room (a ladder
	-- leans on something; a tool rack hangs on something). `Open` pieces stand on the floor at a free
	-- yaw.
	anchoring: RelicAnchoring,
	-- WALL PIECES ONLY: how far the piece's own origin stands off the rock face.
	--
	-- It is NOT `footprintRadius`, and using that instead is the mistake this field exists to stop.
	-- The footprint is the conservative disc routing is measured against, and backing a piece off by
	-- the whole of it leaves a ladder floating two studs clear of the wall it is supposed to be
	-- leaning on. This is the much smaller number: how far back the model's own geometry reaches at
	-- +Z, which every silhouette in `NewModelsAndObjects/MineRelics` builds toward by convention.
	wallOffset: number,
}

export type MineRelicsConfig = {
	enabled: boolean,
	placement: {
		-- Shallowest global depth any workings appear at. Floor 1 is deliberately included: finding the
		-- first rusted cart on the way in is the cheapest way to say this place was worked.
		minDepth: number,
		-- Rolled once per floor, before any room is considered. This is the number that decides how
		-- many descents pass without seeing anything at all.
		floorChance: number,
		-- Hard cap per floor, whatever the room rolls do.
		maxPerFloor: number,
		-- Per eligible room, on a floor that already rolled workings. Entry, Basin and Brazier rooms are
		-- never eligible: they are the three rooms every run stands still in, and they are protected
		-- shapes for exactly that reason (Logic/RoomFootprint.isProtectedShape).
		roomChance: number,
		-- Bearings swept when looking for a spot, evenly spaced from a rolled start angle, and how many
		-- radii are tried along each one.
		--
		-- A SWEEP RATHER THAN UNIFORM RANDOM ROLLS, and it is not a micro-optimisation. Doorway lanes
		-- are 15-25 studs wide and converge on the room centre, so in a four-door room they eat almost
		-- everything except four corner wedges. Independent random rolls find those wedges rarely
		-- enough that the two biggest open-standing pieces — the ore cart and the rail run, which are
		-- the whole point of the catalog — were being placed in under a fifth of the rooms that tried.
		-- A full bearing sweep at several radii finds the wedge if there is one.
		placementBearings: number,
		placementRadiiPerBearing: number,
		-- Ring band the sweep samples, as a fraction of the room cell. Wall pieces start further out and
		-- are then pushed to the rock; open pieces sweep a WIDER band than they used to, because the
		-- free ground in a well-connected room is out near the walls rather than around the middle.
		openRingMinFactor: number,
		openRingMaxFactor: number,
		wallRingMinFactor: number,
		wallRingMaxFactor: number,
		-- How far a wall piece walks outward per probe step, and how many steps it may take, before
		-- backing off its own footprint. This is what puts a ladder ON the rock face in a shaped room
		-- rather than a guessed distance from a cell edge that curves away from it.
		wallProbeStep: number,
		wallProbeSteps: number,
		-- Kept clear of every doorway lane and the navigation hub ON TOP of the relic's own footprint.
		-- The lanes are already the width the largest ground threat needs, so this is margin for the
		-- fact that a player hugs geometry when something is behind them.
		routeClearance: number,
		-- Kept clear of the edge of any planned pool. A cart half in the water would look better than
		-- almost anything else in this file; it would also put a collidable prop on the one surface the
		-- hazard rule measures a candle against.
		poolClearance: number,
		-- Seated this far INTO the analytic floor. Terrain is voxelized and the analytic field is not,
		-- so a piece placed exactly on the surface floats over roughly half of it.
		sinkStuds: number,
		-- Slope sample distance used to sit a piece on the real floor gradient instead of level.
		slopeSample: number,
		-- Deterministic shuffle seed for the catalog walk. Changing it reorders which floor gets which
		-- piece and nothing else.
		orderSeed: number,
	},
	palette: {
		-- DEAD IRON. Desaturated and dark enough that candlelight resolves the shape before it resolves
		-- any colour — rust that read as orange would be the one warm thing in a cave that reserves warm
		-- for firelight.
		ironColors: { Color3 },
		ironMaterial: Enum.Material,
		-- Fittings, bands, bolts and rail head: the same iron, a shade cooler and harder, so a banded
		-- edge separates from the plate it is banding.
		fittingColor: Color3,
		fittingMaterial: Enum.Material,
		-- ROTTED TIMBER. Sleepers, props, crates, barrow handles.
		timberColors: { Color3 },
		timberMaterial: Enum.Material,
		-- Split/dry ends and the inside of anything broken open.
		timberSplitColor: Color3,
		ropeColor: Color3,
		ropeMaterial: Enum.Material,
		-- Lantern glass. Low reflectance, no transparency worth speaking of, and NEVER Neon: it is a
		-- dead lamp and it has to read as one at every distance.
		glassColor: Color3,
		glassTransparency: number,
		glassReflectance: number,
		-- FLAKED LIME-WASH. The only paint in the caves, and it exists for exactly one silhouette: the
		-- hazard chevrons on the notice board, which have to read as a WARNING at candle range with no
		-- text on them and no colour the game has already spoken for. Crimson is a dark-hunter's eyes,
		-- warm orange is flame, pale yellow is a Drawn's halo and neon yellow is the dynamite socket
		-- marker (ART-BIBLE §4, §10b), so the one channel left is a cold, desaturated pale — which is
		-- also what whitewash on old mine timber actually weathers to.
		--
		-- Deliberately well under the spent-wax greys it sits nearest in value: it must be the brightest
		-- thing on the board without becoming the brightest thing in the room. It emits nothing, and the
		-- chevrons are laid as separate broken bars so the dark timber shows through and breaks the mass
		-- up rather than presenting one clean painted plane.
		paintColor: Color3,
		paintMaterial: Enum.Material,
		-- Spilled ore, spoil and split powder. Cold rubble, matched to the cave's own broken rock.
		spoilColors: { Color3 },
		spoilMaterial: Enum.Material,
		-- Everything within `dampBlend` of the floor is mixed toward this, so a piece looks like it has
		-- been standing in the wet since long before anybody arrived.
		dampTint: Color3,
		dampBlend: number,
		-- Base chance any one authored growth anchor carries the cave's own cover, before the family's
		-- `presentation.coverDensityFactor` scales it (Logic/CaveFamilyRules.relicWeathering).
		growthChance: number,
		growthSize: number,
	},
	catalog: { RelicDef },
}

local MineRelics: MineRelicsConfig = {
	enabled = true,
	placement = {
		minDepth = 1,
		floorChance = 0.62,
		maxPerFloor = 2,
		roomChance = 0.3,
		placementBearings = 16,
		placementRadiiPerBearing = 3,
		openRingMinFactor = 0.18,
		openRingMaxFactor = 0.4,
		wallRingMinFactor = 0.28,
		wallRingMaxFactor = 0.38,
		wallProbeStep = 1.25,
		wallProbeSteps = 14,
		routeClearance = 1.6,
		poolClearance = 3,
		sinkStuds = 0.3,
		slopeSample = 1.5,
		orderSeed = 40_507,
	},
	palette = {
		ironColors = {
			Color3.fromRGB(58, 50, 45),
			Color3.fromRGB(66, 56, 48),
			Color3.fromRGB(49, 45, 44),
			Color3.fromRGB(71, 62, 53),
		},
		ironMaterial = Enum.Material.CorrodedMetal,
		fittingColor = Color3.fromRGB(64, 64, 68),
		fittingMaterial = Enum.Material.Metal,
		timberColors = {
			Color3.fromRGB(46, 38, 31),
			Color3.fromRGB(38, 33, 28),
			Color3.fromRGB(55, 45, 35),
		},
		timberMaterial = Enum.Material.Wood,
		timberSplitColor = Color3.fromRGB(63, 54, 43),
		ropeColor = Color3.fromRGB(52, 47, 38),
		ropeMaterial = Enum.Material.Fabric,
		glassColor = Color3.fromRGB(28, 30, 33),
		glassTransparency = 0.35,
		glassReflectance = 0.04,
		paintColor = Color3.fromRGB(118, 114, 106),
		paintMaterial = Enum.Material.Concrete,
		spoilColors = {
			Color3.fromRGB(45, 47, 54),
			Color3.fromRGB(53, 54, 61),
			Color3.fromRGB(38, 40, 46),
		},
		spoilMaterial = Enum.Material.Slate,
		dampTint = Color3.fromRGB(26, 26, 30),
		dampBlend = 0.42,
		growthChance = 0.28,
		growthSize = 0.8,
	},
	-- TWELVE SILHOUETTES, and the spread across them is deliberate: three say "ore moved through
	-- here", three say "somebody stored things here", three say "somebody worked here", two say
	-- "somebody had to get up or see", and one says "somebody was warned". A catalog of twelve carts
	-- would be one prop with variants.
	--
	-- THE LAST CATEGORY HAS EXACTLY ONE MEMBER AND SHOULD KEEP IT. A warning is the only relic that
	-- addresses the player rather than describing the room, and it is the strongest piece here for that
	-- reason — which is also why a second one would halve the first. Signage that turns up twice in a
	-- descent stops being somebody's last act of care and becomes the cave's wallpaper.
	catalog = {
		{
			id = "Minecart",
			weight = 12,
			minDepth = 1,
			footprintRadius = 5.1,
			minCeilingHeight = 15,
			anchoring = "Open",
			wallOffset = 0,
		},
		{
			id = "RailRun",
			weight = 12,
			minDepth = 1,
			-- A ten-stud run of track: the longest piece in the catalog, though the cart reaches wider.
			footprintRadius = 5.6,
			minCeilingHeight = 15,
			anchoring = "Open",
			wallOffset = 0,
		},
		{
			id = "BufferStop",
			weight = 8,
			minDepth = 2,
			footprintRadius = 6,
			minCeilingHeight = 15,
			anchoring = "Wall",
			wallOffset = 1.5,
		},
		{
			id = "PitProps",
			weight = 9,
			minDepth = 1,
			footprintRadius = 5,
			-- The frame is roughly seven studs to the top of its header beam.
			minCeilingHeight = 18,
			anchoring = "Wall",
			wallOffset = 1.4,
		},
		{
			id = "SupplyCrates",
			weight = 10,
			minDepth = 1,
			footprintRadius = 4.6,
			minCeilingHeight = 15,
			anchoring = "Wall",
			wallOffset = 2.2,
		},
		{
			id = "PowderKegs",
			weight = 8,
			minDepth = 4,
			footprintRadius = 4.6,
			minCeilingHeight = 15,
			anchoring = "Wall",
			wallOffset = 1.8,
		},
		{
			id = "Windlass",
			weight = 7,
			minDepth = 2,
			footprintRadius = 4.1,
			minCeilingHeight = 17,
			anchoring = "Open",
			wallOffset = 0,
		},
		{
			id = "LanternPost",
			weight = 9,
			minDepth = 1,
			footprintRadius = 1.7,
			minCeilingHeight = 15,
			anchoring = "Wall",
			wallOffset = 0.7,
		},
		{
			id = "Wheelbarrow",
			weight = 10,
			minDepth = 1,
			footprintRadius = 3.1,
			minCeilingHeight = 15,
			anchoring = "Open",
			wallOffset = 0,
		},
		{
			id = "ToolRack",
			weight = 9,
			minDepth = 2,
			footprintRadius = 2.7,
			minCeilingHeight = 15,
			anchoring = "Wall",
			wallOffset = 1.1,
		},
		{
			id = "DangerSign",
			-- Weighted with the commonest pieces rather than the rarest. The floor gates already make
			-- any relic uncommon, and a warning is worth more the earlier a player meets one: it is the
			-- cheapest thing in the game that tells somebody the cave was understood before it was
			-- abandoned.
			weight = 10,
			minDepth = 1,
			footprintRadius = 3,
			minCeilingHeight = 15,
			anchoring = "Wall",
			-- The stakes are driven at the rock and the board leans back onto it; this is how far the
			-- board's own top edge reaches at +Z.
			wallOffset = 1.3,
		},
		{
			id = "Ladder",
			weight = 8,
			minDepth = 2,
			footprintRadius = 3.6,
			-- It leans; it does not have to reach anything.
			minCeilingHeight = 19,
			anchoring = "Wall",
			-- Its head rests nearly three studs behind its foot, which is the whole lean.
			wallOffset = 3.4,
		},
	},
}

return MineRelics
