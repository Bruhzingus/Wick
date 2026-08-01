--!strict
-- Cave-family profiles, difficulty resolution, and the v3 -> v4 save migration.
--
-- WHAT THIS SUITE DELIBERATELY DOES NOT TEST: specific tuning values. Asserting that Moss's threat
-- multiplier is exactly 1.1 would mean every legitimate retune failed the suite until somebody
-- updated the number here too, which teaches people to edit tests rather than to think. What is
-- tested is the SHAPE of the model — that the ordering between families holds, that a family cannot
-- be harder through the one axis it is forbidden to be harder through, and that nobody's save loses
-- access.

local Harness = require(script.Parent.Harness)
local CaveFamiliesConfig = require(script.Parent.Parent.Config.CaveFamilies)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)
local DepthConfig = require(script.Parent.Parent.Config.Depth)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local CaveTierConfig = require(script.Parent.Parent.Config.CaveTiers)

local function familyById(id: string): CaveFamiliesConfig.CaveFamilyProfile
	local profile = CaveFamilyRules.byId(id)
	assert(profile ~= nil, "test fixture requires family " .. id)
	return profile :: CaveFamiliesConfig.CaveFamilyProfile
end

local suite: Harness.Suite = {
	name = "CaveFamilyRules",
	tests = {
		Harness.test("every shipped profile passes validation", function()
			local ok, issues = CaveFamilyRules.validate()
			local detail = ""
			for _, issue in issues do
				detail ..= string.format("\n  %s.%s: %s", issue.familyId, issue.field, issue.message)
			end
			Harness.expect(ok, "shipped cave families failed validation:" .. detail)
		end),

		Harness.test("the three shipped families exist and resolve by id", function()
			for _, id in { "STONE", "MOSS", "ICE" } do
				Harness.expect(CaveFamilyRules.isValidId(id), id .. " must be a real family")
				Harness.equal(CaveFamilyRules.resolve(id).id, id)
			end
		end),

		Harness.test("an invalid family id resolves to the free family instead of erroring", function()
			-- A rolled-back config, a stale client payload, or a save written by a newer build must all
			-- produce a playable cave rather than a crash. Falling back to the FREE family is what makes
			-- that safe: the fallback can never grant access to something a player has not bought.
			for _, bad in { "", "STONE ", "moss", "NOPE", "1" } do
				Harness.equal(CaveFamilyRules.resolve(bad).id, CaveFamiliesConfig.defaultId, "bad id: " .. bad)
			end
			Harness.equal(CaveFamilyRules.resolve(nil).id, CaveFamiliesConfig.defaultId)
			Harness.isNil(CaveFamilyRules.byId("NOPE"))
			Harness.expect(not CaveFamilyRules.isValidId(nil), "nil is not a valid id")
		end),

		Harness.test("all three families begin at global depth 1", function()
			-- A family is a DIFFERENT cave, not a deeper starting point. Every tier row projects a
			-- constant 1, and this is the assertion that stops that ever quietly becoming a knob again.
			for _, tier in CaveTierConfig do
				Harness.equal(tier.startDepth, 1, tier.displayName .. " must start at the surface")
			end
		end),

		Harness.test("passive wax drain is identical in every family", function()
			-- THE product invariant. Moss and Ice are harder through threats, hazards, topology,
			-- visibility and environment — never through an unavoidable timer that runs faster, which
			-- is not difficulty, only a shorter run.
			local reference: number? = nil
			for _, profile in CaveFamilyRules.list() do
				if reference == nil then
					reference = profile.waxDrainMultiplier
				end
				Harness.equal(profile.waxDrainMultiplier, reference, profile.id .. " drains wax at a different rate")
			end
			Harness.equal(reference, 1, "the shared drain multiplier must be neutral")
		end),

		Harness.test("every multiplier is finite, non-negative, and covers every depth band", function()
			for _, profile in CaveFamilyRules.list() do
				for _, band in DepthConfig.bands do
					for _, depthInBand in { band.maxDepth } do
						local threat = CaveFamilyRules.threatBudgetMultiplier(profile, depthInBand)
						local hazard = CaveFamilyRules.hazardBudgetMultiplier(profile, depthInBand)
						for _, value in { threat, hazard } do
							Harness.expect(value == value, profile.id .. " produced NaN at depth " .. depthInBand)
							Harness.expect(
								value > -math.huge and value < math.huge,
								profile.id .. " produced an infinite multiplier"
							)
							Harness.expect(value >= 0, profile.id .. " produced a negative multiplier")
						end
					end
				end
				-- Past the last authored band the final band's values continue to apply rather than the
				-- lookup falling off the end.
				local deep = CaveFamilyRules.threatBudgetMultiplier(profile, 400)
				Harness.expect(deep > 0, profile.id .. " lost its threat scaling past the authored bands")
			end
		end),

		Harness.test("Moss and Ice scale faster than Stone, and the gap widens with depth", function()
			local stone, moss, ice = familyById("STONE"), familyById("MOSS"), familyById("ICE")
			local previousMossGap, previousIceGap = -math.huge, -math.huge
			for _, depth in { 1, 5, 8, 12, 18 } do
				local stoneThreat = CaveFamilyRules.threatBudgetMultiplier(stone, depth)
				local mossThreat = CaveFamilyRules.threatBudgetMultiplier(moss, depth)
				local iceThreat = CaveFamilyRules.threatBudgetMultiplier(ice, depth)
				Harness.expect(mossThreat > stoneThreat, "Moss must out-scale Stone at depth " .. depth)
				Harness.expect(iceThreat > mossThreat, "Ice must out-scale Moss at depth " .. depth)

				-- The gap is what makes them different CURVES rather than different constants.
				local mossGap = mossThreat - stoneThreat
				local iceGap = iceThreat - stoneThreat
				Harness.expect(mossGap >= previousMossGap, "Moss's lead over Stone must not shrink with depth")
				Harness.expect(iceGap >= previousIceGap, "Ice's lead over Stone must not shrink with depth")
				previousMossGap, previousIceGap = mossGap, iceGap
			end
			-- Stone itself is the flat baseline: its band multipliers are all exactly 1, so its curve
			-- comes entirely from the shared depth model.
			Harness.equal(
				CaveFamilyRules.threatBudgetMultiplier(stone, 1),
				CaveFamilyRules.threatBudgetMultiplier(stone, 18),
				"Stone must stay the flat regression baseline across every band"
			)
		end),

		Harness.test("falling hazards spread wider in harder caves and deeper floors", function()
			-- HOW MANY formations one room can physically hold is settled by geometry, so the lever a
			-- family actually has on falling hazards is how many ROOMS are dangerous. This pins that
			-- relationship: harder cave, wider spread; deeper floor, wider spread.
			local stone, moss, ice = familyById("STONE"), familyById("MOSS"), familyById("ICE")
			local authored = 0.5
			local previousStone = 0
			for _, depth in { 1, 5, 8, 12, 18 } do
				local stoneSpread = CaveFamilyRules.hazardousRoomFraction(stone, depth, authored)
				local mossSpread = CaveFamilyRules.hazardousRoomFraction(moss, depth, authored)
				local iceSpread = CaveFamilyRules.hazardousRoomFraction(ice, depth, authored)
				Harness.expect(mossSpread >= stoneSpread, "Moss must not spread hazards narrower than Stone")
				Harness.expect(iceSpread >= stoneSpread, "Ice must not spread hazards narrower than Stone")
				Harness.expect(stoneSpread >= previousStone, "spread must not narrow as a run goes deeper")
				previousStone = stoneSpread
				-- Always below 1: the planner additionally guarantees a safe ordinary room, and this is
				-- the config-side half of that promise.
				for _, spread in { stoneSpread, mossSpread, iceSpread } do
					Harness.expect(spread > 0 and spread < 1, "a floor may never be entirely dangerous")
				end
			end
			-- Ice, the family whose ceilings fracture, must be meaningfully ahead somewhere real.
			Harness.expect(
				CaveFamilyRules.hazardousRoomFraction(ice, 5, authored)
					> CaveFamilyRules.hazardousRoomFraction(stone, 5, authored) * 1.2,
				"Ice must read as materially more hazardous than Stone at mid depth"
			)
		end),

		Harness.test("a family's doorway bias can never take an opening below the safe minimum", function()
			local g = FloorsConfig.geometry
			for _, profile in CaveFamilyRules.list() do
				for _, rolled in { 0, 1, g.doorwayMinWidth, g.doorwayMaxWidth, 1e6 } do
					local width = CaveFamilyRules.doorwayWidth(profile, rolled)
					Harness.expect(width >= g.doorwayMinWidth, profile.id .. " cut a doorway below the minimum")
					Harness.expect(width <= g.doorwayMaxWidth, profile.id .. " cut a doorway above the maximum")
				end
			end
		end),

		Harness.test("ceiling rolls stay inside the authored range for every family", function()
			local rng = Random.new(4_242)
			for _, profile in CaveFamilyRules.list() do
				local low, high = math.huge, -math.huge
				for _ = 1, 400 do
					local height = CaveFamilyRules.rollCeilingHeight(profile, rng)
					Harness.expect(
						height >= FloorsConfig.geometry.ceilingMinHeight - 1e-6
							and height <= FloorsConfig.geometry.ceilingMaxHeight + 1e-6,
						profile.id .. " rolled a ceiling outside the authored range"
					)
					low = math.min(low, height)
					high = math.max(high, height)
				end
				-- NOT UNIFORMLY CRAMPED AND NOT UNIFORMLY OPEN. A family biased toward low roofs must
				-- still produce tall rooms and vice versa, or it has stopped being a cave and become a
				-- corridor.
				Harness.expect(high - low > 10, profile.id .. " collapsed its ceilings onto one height")
			end
		end),

		Harness.test("threat ecology changes the mix without touching a single threat stat", function()
			local moss, ice = familyById("MOSS"), familyById("ICE")
			-- The shipped intent, stated as relationships rather than as numbers.
			Harness.expect(
				CaveFamilyRules.threatWeightMultiplier(moss, "Lurker")
					> CaveFamilyRules.threatWeightMultiplier(ice, "Lurker"),
				"Moss must lean on Lurkers more than Ice does"
			)
			Harness.expect(
				CaveFamilyRules.threatWeightMultiplier(ice, "Stalker")
					> CaveFamilyRules.threatWeightMultiplier(moss, "Stalker"),
				"Ice must lean on Stalkers more than Moss does"
			)
			-- An unlisted threat is neutral, never zero: a family narrows the mix, it does not delete
			-- rows from the roster.
			Harness.equal(CaveFamilyRules.threatWeightMultiplier(familyById("STONE"), "Lurker"), 1)
			Harness.equal(CaveFamilyRules.threatWeightMultiplier(moss, "NotAThreat" :: any), 1)
		end),

		Harness.test("introduction shifts bring threats forward and never sample below floor 1", function()
			local moss = familyById("MOSS")
			Harness.equal(CaveFamilyRules.threatDepthIndex(moss, "Swarm", 4), 5, "Moss meets Swarms a floor early")
			Harness.equal(CaveFamilyRules.threatDepthIndex(moss, "Lurker", 4), 4, "an unshifted row is unchanged")
			Harness.expect(
				CaveFamilyRules.threatDepthIndex(moss, "Swarm", 1) >= 1,
				"a shift must never sample below the first authored row"
			)
		end),

		Harness.test("vine curtains follow the family's own introduction and count", function()
			local stone, moss, ice = familyById("STONE"), familyById("MOSS"), familyById("ICE")
			local sawEarlierMoss = false
			for depth = 1, 20 do
				local stoneCount = CaveFamilyRules.vineTargetCount(stone, depth)
				local mossCount = CaveFamilyRules.vineTargetCount(moss, depth)
				Harness.equal(CaveFamilyRules.vineTargetCount(ice, depth), 0, "Ice grows nothing to burn")
				Harness.expect(mossCount >= stoneCount, "Moss must never carry fewer curtains than Stone")
				if stoneCount == 0 and mossCount > 0 then
					sawEarlierMoss = true
				end
			end
			Harness.expect(sawEarlierMoss, "Moss must meet curtains at a depth Stone does not")
		end),

		Harness.test("shape weights resolve deterministically and always yield a footprint", function()
			for _, profile in CaveFamilyRules.list() do
				-- Same roll, same kind, every time.
				for _, roll in { 0, 0.25, 0.5, 0.75, 0.999999 } do
					Harness.equal(
						CaveFamilyRules.selectShapeKind(profile, roll),
						CaveFamilyRules.selectShapeKind(profile, roll),
						"shape selection must be a pure function of its roll"
					)
				end
				-- Out-of-range and NaN rolls still return a real kind rather than nil.
				for _, roll in { -1, 2, 0 / 0 } do
					local kind = CaveFamilyRules.selectShapeKind(profile, roll)
					Harness.expect(
						profile.roomShapeWeights[kind] ~= nil,
						profile.id .. " produced an unknown shape kind from a hostile roll"
					)
				end
				-- Half of every family's ordinary rooms are rectangles by config.
				local total = 0
				for _, kind in CaveFamilyRules.shapeKinds() do
					total += CaveFamilyRules.shapeWeight(profile, kind)
				end
				Harness.near(
					CaveFamilyRules.shapeWeight(profile, "Rectangle") / total,
					0.5,
					1e-9,
					profile.id .. " must keep half its ordinary rooms rectangular"
				)
			end
		end),

		Harness.test("negative or absent weights are refused rather than inverted", function()
			local hostile = {
				id = "HOSTILE" :: any,
				roomShapeWeights = { Rectangle = -5, Ellipse = 0 / 0, Capsule = 1, TwinLobe = 0 },
			}
			Harness.equal(CaveFamilyRules.shapeWeight(hostile :: any, "Rectangle"), 0)
			Harness.equal(CaveFamilyRules.shapeWeight(hostile :: any, "Ellipse"), 0)
			Harness.equal(CaveFamilyRules.shapeWeight(hostile :: any, "Capsule"), 1)
			Harness.equal(CaveFamilyRules.selectShapeKind(hostile :: any, 0.5), "Capsule")
			-- A family with no weight at all still produces a room.
			local empty = { roomShapeWeights = { Rectangle = 0, Ellipse = 0, Capsule = 0, TwinLobe = 0 } }
			Harness.equal(CaveFamilyRules.selectShapeKind(empty :: any, 0.5), "Rectangle")
		end),

		--------------------------------------------------------------------------------
		-- Presentation
		--------------------------------------------------------------------------------

		Harness.test("every family has its own surface textures, not just its own tint", function()
			-- COLOUR ALONE IS NOT A DIFFERENT CAVE. Three families sharing one material with three tints
			-- read as one cave under three gels, because the grain the candle catches would be identical
			-- in all of them. Each family must differ in the materials a player's light actually falls
			-- on: the terrain underfoot, the wall slabs, and the broken rock across their faces.
			local signatures: { [string]: string } = {}
			for _, profile in CaveFamilyRules.list() do
				local presentation = profile.presentation
				local signature = string.format(
					"%s|%s|%s",
					tostring(presentation.terrainMaterial),
					tostring(presentation.wallMaterial),
					tostring(presentation.rockMaterial)
				)
				for otherId, otherSignature in signatures do
					Harness.expect(
						signature ~= otherSignature,
						string.format("%s and %s are the same cave in different colours", profile.id, otherId)
					)
				end
				signatures[profile.id] = signature

				-- And the dressing on top of that rock is its own material too.
				Harness.expect(
					typeof(presentation.coverMaterial) == "EnumItem",
					profile.id .. " has no wall-cover material"
				)
				Harness.expect(#presentation.formationMaterials > 0, profile.id .. " has no formation materials")
			end
		end),

		Harness.test("every family stays a DARK cave, whatever its hue", function()
			-- THE RULE THE WHOLE GAME RESTS ON: light is the only source of visual information. A family
			-- may take a hue; it may never take brightness, because a cave that reads as lit undoes the
			-- thing the darkness is for. This is the guard that stops a future retune brightening a cave
			-- one palette entry at a time without anybody noticing.
			--
			-- Relative luminance, weighted for how the eye actually responds — a mid green is far
			-- brighter than a mid blue at the same numeric value, and an unweighted average would wave
			-- through exactly the pale green-grey most likely to creep in.
			local function luminance(color: Color3): number
				return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
			end

			-- Structural rock is held hardest: it is most of what is on screen.
			local ROCK_LIMIT = 0.30
			-- Dressing and formations may catch the flame a little more — wet moss, frost, ice — but
			-- still nowhere near a lit surface.
			local DRESSING_LIMIT = 0.40

			for _, profile in CaveFamilyRules.list() do
				local presentation = profile.presentation
				for _, entry in
					{
						{ name = "wallColor", color = presentation.wallColor, limit = ROCK_LIMIT },
						{ name = "rockColor", color = presentation.rockColor, limit = ROCK_LIMIT },
						{ name = "terrainColor", color = presentation.terrainColor, limit = ROCK_LIMIT },
					}
				do
					Harness.expect(
						luminance(entry.color) <= entry.limit,
						string.format(
							"%s.%s is too bright for a dark cave (%.3f > %.2f)",
							profile.id,
							entry.name,
							luminance(entry.color),
							entry.limit
						)
					)
				end
				for index, color in presentation.coverPalette do
					Harness.expect(
						luminance(color) <= DRESSING_LIMIT,
						string.format("%s coverPalette[%d] is too bright (%.3f)", profile.id, index, luminance(color))
					)
				end
				for index, color in presentation.formationPalette do
					Harness.expect(
						luminance(color) <= DRESSING_LIMIT,
						string.format(
							"%s formationPalette[%d] is too bright (%.3f)",
							profile.id,
							index,
							luminance(color)
						)
					)
				end
				-- Atmosphere takes the family's hue and never its own brightness.
				Harness.expect(
					luminance(presentation.atmosphereDecay) <= ROCK_LIMIT,
					profile.id .. " atmosphere decay is too bright"
				)
			end
		end),

		--------------------------------------------------------------------------------
		-- Migration
		--------------------------------------------------------------------------------

		Harness.test("a new player owns nothing and loses nothing", function()
			Harness.equal(#CaveFamilyRules.migrateOwnedTiers(nil, nil), 0)
			Harness.equal(#CaveFamilyRules.migrateOwnedTiers({}, {}), 0)
		end),

		Harness.test("owning The Descent grants Moss, and The Deep grants Ice", function()
			local descentOwner = CaveFamilyRules.migrateOwnedTiers({ 2 }, {})
			Harness.equal(#descentOwner, 1)
			Harness.equal(descentOwner[1], "MOSS")

			local deepOwner = CaveFamilyRules.migrateOwnedTiers({ 3 }, {})
			Harness.equal(#deepOwner, 1)
			Harness.equal(deepOwner[1], "ICE")

			local both = CaveFamilyRules.migrateOwnedTiers({ 3, 2 }, {})
			Harness.equal(#both, 2)
			Harness.expect(table.find(both, "MOSS") ~= nil, "an owner of both keeps Moss")
			Harness.expect(table.find(both, "ICE") ~= nil, "an owner of both keeps Ice")
		end),

		Harness.test("migration is idempotent however many times it runs", function()
			local once = CaveFamilyRules.migrateOwnedTiers({ 2, 3 }, {})
			local twice = CaveFamilyRules.migrateOwnedTiers({ 2, 3 }, once)
			local thrice = CaveFamilyRules.migrateOwnedTiers({ 2, 3 }, twice)
			Harness.equal(#twice, #once)
			Harness.equal(#thrice, #once)
			for index, familyId in once do
				Harness.equal(twice[index], familyId, "a second run reordered the set")
				Harness.equal(thrice[index], familyId, "a third run reordered the set")
			end
		end),

		Harness.test("a corrupt legacy list is survived rather than trusted", function()
			-- Duplicates, junk types, unknown tiers, fractional ids and a tier that does not exist.
			local owned = CaveFamilyRules.migrateOwnedTiers({ 2, 2, "3", true, 99, -1, 2.9, 3 } :: any, {})
			Harness.equal(#owned, 2, "only real tiers may become families")
			Harness.expect(table.find(owned, "MOSS") ~= nil, "the duplicated real tier still resolves once")
			Harness.expect(table.find(owned, "ICE") ~= nil, "a whole tier id must still resolve")
			-- `2.9` floors to 2 and is already owned, so it cannot add a second Moss entry.
			local seen: { [string]: boolean } = {}
			for _, familyId in owned do
				Harness.isNil(seen[familyId], "migration produced a duplicate entry")
				seen[familyId] = true
			end
		end),

		Harness.test("an already-migrated profile keeps exactly what it had", function()
			local existing = { "MOSS", "ICE" }
			local migrated = CaveFamilyRules.migrateOwnedTiers(nil, existing)
			Harness.equal(#migrated, 2)
			Harness.equal(migrated[1], "MOSS")
			Harness.equal(migrated[2], "ICE")
			-- Junk already in the stored set is dropped rather than carried forward.
			Harness.equal(#CaveFamilyRules.migrateOwnedTiers(nil, { "MOSS", "GONE", 7 } :: any), 1)
		end),

		Harness.test("the numeric tier projection stays a bijection with the families", function()
			-- The migration is only a rename because these two describe the same three caves. If a
			-- family ever lost its row, or two shared one, ownership would stop being translatable.
			Harness.equal(#CaveTierConfig, #CaveFamilyRules.list())
			for _, tier in CaveTierConfig do
				local profile = CaveFamilyRules.byId(tier.familyId)
				Harness.expect(profile ~= nil, "tier " .. tier.id .. " projects an unknown family")
				Harness.equal((profile :: any).legacyTierId, tier.id, "the projection must round-trip")
				Harness.equal(CaveFamilyRules.legacyTierId(tier.familyId), tier.id)
				Harness.equal((CaveFamilyRules.fromLegacyTierId(tier.id) :: any).id, tier.familyId)
			end
			Harness.isNil(CaveFamilyRules.fromLegacyTierId(99))
			Harness.isNil(CaveFamilyRules.fromLegacyTierId(0 / 0))
		end),

		Harness.test("the free cave stays free and unownable so nobody can be locked out", function()
			-- Whatever else happens to a balance, there is always a cave a player can walk into with
			-- nothing. That is what stops a bad streak in a paid cave from ending the game for someone.
			local free = 0
			for _, tier in CaveTierConfig do
				if tier.entryFee <= 0 then
					free += 1
					Harness.equal(tier.permanentUnlockPrice, 0, tier.displayName .. " is free and cannot be sold")
					Harness.equal(tier.familyId, CaveFamiliesConfig.defaultId, "the free cave must be the fallback")
				else
					Harness.expect(
						tier.permanentUnlockPrice > tier.entryFee,
						tier.displayName .. " must cost more to own than to enter"
					)
				end
			end
			Harness.equal(free, 1, "exactly one cave is free")
		end),

		Harness.test("a harder cave never pays less than an easier one", function()
			local sorted = table.clone(CaveTierConfig)
			table.sort(sorted, function(a, b)
				return a.threatBudgetMultiplier < b.threatBudgetMultiplier
			end)
			for index = 2, #sorted do
				Harness.expect(
					sorted[index].payoutPermille >= sorted[index - 1].payoutPermille,
					"a more dangerous cave must never pay less than a safer one"
				)
			end
		end),
	},
}

return suite
