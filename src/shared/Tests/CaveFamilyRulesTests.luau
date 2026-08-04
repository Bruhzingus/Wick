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
local FeelConfig = require(script.Parent.Parent.Config.Feel)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local StoneWardenConfig = require(script.Parent.Parent.Config.StoneWarden)

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
			-- The shipped intent, stated as relationships rather than as numbers. Moss is damp and
			-- overgrown and is where the moths are; Ice is open, bare hunting ground.
			Harness.expect(
				CaveFamilyRules.threatWeightMultiplier(moss, "Moth")
					> CaveFamilyRules.threatWeightMultiplier(ice, "Moth"),
				"Moss must lean on moths more than Ice does"
			)
			Harness.expect(
				CaveFamilyRules.threatWeightMultiplier(ice, "DarkCrawler")
					> CaveFamilyRules.threatWeightMultiplier(moss, "DarkCrawler"),
				"Ice must lean on crawlers more than Moss does"
			)
			-- An unlisted threat is neutral, never zero: a family narrows the mix, it does not delete
			-- rows from the roster.
			Harness.equal(CaveFamilyRules.threatWeightMultiplier(familyById("STONE"), "DarkCrawler"), 1)
			Harness.equal(CaveFamilyRules.threatWeightMultiplier(moss, "NotAThreat" :: any), 1)
		end),

		Harness.test("each family has a signature creature the other two never meet", function()
			-- THE POINT OF A SIGNATURE CREATURE: it is not rarer elsewhere, it is ABSENT elsewhere.
			-- Exactly one family may carry each, and the ones that do not must weight it to a hard zero
			-- rather than a small number — the planner reads zero as "not here" in both its eligibility
			-- check and its spawn roll, and anything above zero would eventually put an Ice creature in
			-- a Moss cave on a long enough run.
			local signatures = { Listener = "STONE", Knotwalker = "MOSS", Calver = "ICE" }
			for threatId, ownerId in signatures do
				local owners = 0
				for _, profile in CaveFamilyRules.list() do
					local weight = CaveFamilyRules.threatWeightMultiplier(profile, threatId :: any)
					if profile.id == ownerId then
						Harness.expect(weight > 0, ownerId .. " must actually carry its own " .. threatId)
						owners += 1
					else
						Harness.equal(weight, 0, profile.id .. " must never meet the " .. threatId)
					end
				end
				Harness.equal(owners, 1, threatId .. " must belong to exactly one family")
			end
		end),

		Harness.test("the shared roster stays available in every family", function()
			-- The counterpart to the rule above. A family narrows the mix and may never delete a row
			-- from the roster every cave draws: if a family could zero the crawler, a player could
			-- descend twenty floors of it without meeting the creature the whole light system teaches.
			for _, threatId in { "DarkCrawler", "Moth", "VoidFly" } do
				for _, profile in CaveFamilyRules.list() do
					Harness.expect(
						CaveFamilyRules.threatWeightMultiplier(profile, threatId :: any) > 0,
						profile.id .. " deleted " .. threatId .. " from the shared roster"
					)
				end
			end
		end),

		Harness.test("introduction shifts bring threats forward and never sample below floor 1", function()
			local moss = familyById("MOSS")
			Harness.equal(CaveFamilyRules.threatDepthIndex(moss, "Moth", 4), 5, "Moss meets its moths a floor early")
			Harness.equal(CaveFamilyRules.threatDepthIndex(moss, "DarkCrawler", 4), 4, "an unshifted row is unchanged")
			Harness.expect(
				CaveFamilyRules.threatDepthIndex(moss, "Moth", 1) >= 1,
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
		-- Hazard ecology
		--------------------------------------------------------------------------------

		Harness.test("every family's ceilings hang a different mix of the same pool", function()
			-- The falling hazard used to be the same object with the same behaviour in all three caves,
			-- differing only in what it was painted as. What is pinned now is that the MIX differs — and
			-- specifically along the axis each family's identity promises.
			local stone, moss, ice = familyById("STONE"), familyById("MOSS"), familyById("ICE")
			local function weight(profile: CaveFamiliesConfig.CaveFamilyProfile, variantId: string): number
				return CaveFamilyRules.dripstoneVariantWeightMultiplier(profile, variantId)
			end

			-- Ice is the sharp, exposed cave: needles and long spires over blunt crowns.
			Harness.expect(weight(ice, "Needle") > weight(moss, "Needle"), "Ice must hang more needles than Moss")
			Harness.expect(weight(ice, "Spire") > weight(moss, "Spire"), "Ice must hang more long spires than Moss")
			Harness.expect(weight(moss, "Hammer") > weight(ice, "Hammer"), "Moss must hang more heavy crowns than Ice")

			-- Stone is untouched: every original variant at exactly its authored weight, which is what
			-- makes it the regression baseline for hazards the same way it is for everything else.
			for _, variantId in { "Needle", "Fork", "Hammer", "Spire" } do
				Harness.equal(weight(stone, variantId), 1, "Stone must stay the authored hazard baseline")
			end
		end),

		Harness.test("a family-signature formation is refused outright by the other two", function()
			-- Same rule as the signature creatures, for the same reason: absent, not merely rare.
			local signatures = { Lance = "ICE", Mass = "MOSS" }
			for variantId, ownerId in signatures do
				for _, profile in CaveFamilyRules.list() do
					local weight = CaveFamilyRules.dripstoneVariantWeightMultiplier(profile, variantId)
					if profile.id == ownerId then
						Harness.expect(weight > 0, ownerId .. " must carry its own " .. variantId)
					else
						Harness.equal(weight, 0, profile.id .. " must never hang a " .. variantId)
					end
				end
			end
		end),

		Harness.test("the Warden's counter crown stays reachable in every family", function()
			-- Config/StoneWarden.counterDripstoneVariantId hard-names the Heavy Crown as the encounter's
			-- one counter, in every cave, bypassing variant selection entirely. A family that weighted
			-- it to zero would still get the counter placed — but a player would never have seen one in
			-- ordinary cave, and so would not read it as something they can lead a Warden under.
			for _, profile in CaveFamilyRules.list() do
				Harness.expect(
					CaveFamilyRules.dripstoneVariantWeightMultiplier(
						profile,
						StoneWardenConfig.counterDripstoneVariantId
					) > 0,
					profile.id .. " never hangs the formation its Warden encounter depends on"
				)
			end
		end),

		Harness.test("no family can refuse every falling formation", function()
			-- A family that zeroed the whole pool would still be handed a hazard budget and would spend
			-- every placement attempt failing to roll anything. `validate` rejects it; this pins the
			-- consequence rather than the check.
			for _, profile in CaveFamilyRules.list() do
				local total = 0
				for _, variant in HazardsConfig.unstableDripstone.variants do
					total += CaveFamilyRules.dripstoneVariantWeightMultiplier(profile, variant.id) * variant.weight
				end
				Harness.expect(total > 0, profile.id .. " cannot hang anything at all")
			end
		end),

		--------------------------------------------------------------------------------
		-- Ambience
		--------------------------------------------------------------------------------

		Harness.test("each family rolls a materially different soundscape", function()
			local stone, moss, ice = familyById("STONE"), familyById("MOSS"), familyById("ICE")
			local function weight(profile: CaveFamiliesConfig.CaveFamilyProfile, candidateId: string): number
				return CaveFamilyRules.ambientWeightMultiplier(profile, candidateId)
			end

			-- Built from what each family actually IS, so these read against the environment profile
			-- rather than against taste. Moss is the wettest cave (wetFloorProbability 0.55) and Ice the
			-- driest (0.30); the water candidates have to follow that or the audio is decoration.
			Harness.expect(
				moss.environment.wetFloorProbability > ice.environment.wetFloorProbability,
				"test fixture assumes Moss is the wetter cave"
			)
			for _, candidateId in { "HiddenWaterPulse", "WaterDrip" } do
				Harness.expect(
					weight(moss, candidateId) > weight(ice, candidateId),
					"Moss must sound wetter than Ice: " .. candidateId
				)
			end
			-- Dry packed glacier strains and cracks in a way wet rock does not.
			Harness.expect(weight(ice, "StrataStrain") > weight(moss, "StrataStrain"), "Ice must groan more than Moss")

			-- Stone is the baseline both were authored against.
			for _, candidateId in { "StrataStrain", "FissureBreath", "CalciteTicks", "HiddenWaterPulse", "GravelCreep" } do
				Harness.equal(weight(stone, candidateId), 1, "Stone must stay the authored ambience baseline")
			end
		end),

		Harness.test("a family may be quieter or busier, and may never be silent", function()
			local moss, ice = familyById("MOSS"), familyById("ICE")
			Harness.expect(
				CaveFamilyRules.ambientSilenceMultiplier(ice) > CaveFamilyRules.ambientSilenceMultiplier(moss),
				"Ice must be the quieter cave and Moss the busier one"
			)
			for _, profile in CaveFamilyRules.list() do
				local silence = CaveFamilyRules.ambientSilenceMultiplier(profile)
				Harness.expect(silence > 0, profile.id .. " turned its ambience off entirely")
				-- A cave must still make at least one sound, or "quieter" has become "muted".
				local total = 0
				for _, event in FeelConfig.ambientCave.soundEvents do
					total += CaveFamilyRules.ambientWeightMultiplier(profile, event.id) * event.weight
				end
				Harness.expect(total > 0, profile.id .. " cannot make a single sound")
			end
		end),

		Harness.test("audio is never a difficulty lever: no family touches a cue's gain or bus", function()
			-- THE INVARIANT THAT MAKES PER-FAMILY AUDIO SAFE, and the reason a family profile carries
			-- rates and nothing else. A family may change how OFTEN the cave speaks; the mix belongs to
			-- Config/Audio and is identical in every cave. If a family could quieten a cue it could
			-- quieten the layer a player uses to hear something coming, which is a difficulty change
			-- made with a volume slider.
			--
			-- Expressed structurally: the ambience profile has exactly these two fields, so there is
			-- nowhere for a gain override to live. A future field here should fail this test and force
			-- somebody to argue for it.
			for _, profile in CaveFamilyRules.list() do
				local fields = 0
				for _ in profile.ambience :: { [string]: any } do
					fields += 1
				end
				Harness.equal(fields, 2, profile.id .. " grew an ambience field beyond rate and silence")
				Harness.expect(profile.ambience.candidateWeights ~= nil, "candidateWeights must exist")
				Harness.expect(typeof(profile.ambience.silenceWeight) == "number", "silenceWeight must be a number")
			end
		end),

		--------------------------------------------------------------------------------
		-- Presentation
		--------------------------------------------------------------------------------

		Harness.test("a family dresses creatures with geometry, not only a tint", function()
			-- COLOUR ALONE IS NOT A DIFFERENT CREATURE, on exactly the argument the rock materials test
			-- below already makes about the cave. A family that only lerped a hue would be shipping the
			-- same body three times, so the two reskinned families must each build something.
			local stone, moss, ice = familyById("STONE"), familyById("MOSS"), familyById("ICE")
			Harness.equal(stone.presentation.creatures.growthStyle, "None", "Stone must stay the bare baseline")
			Harness.equal(stone.presentation.creatures.growthCoverage, 0, "Stone must build nothing on a body")

			for _, profile in { moss, ice } do
				local creatures = profile.presentation.creatures
				Harness.expect(creatures.growthStyle ~= "None", profile.id .. " must dress its creatures")
				Harness.expect(creatures.growthCoverage > 0, profile.id .. " dresses nothing")
				Harness.expect(#creatures.growthPalette > 0, profile.id .. " has no dressing colours")
			end
			-- And the two reskinned families must differ from EACH OTHER, or they are one reskin twice.
			Harness.expect(
				moss.presentation.creatures.growthStyle ~= ice.presentation.creatures.growthStyle,
				"Moss and Ice must dress creatures differently from one another"
			)
		end),

		Harness.test("no family may dress a creature's head, whatever else it does", function()
			-- The crimson dark-hunter slits and the Drawn's warm halo are how a player decides what to
			-- do about the thing in front of them, and they must be the first thing that resolves at
			-- range in every cave. A product invariant on the same footing as equal passive wax drain.
			for _, profile in CaveFamilyRules.list() do
				Harness.expect(
					profile.presentation.creatures.headExclusion,
					profile.id .. " allows growth on a creature's head"
				)
			end
		end),

		Harness.test("a dressed creature is never brighter than the cave it stands in", function()
			-- Pale-on-black is the highest-contrast thing this layer can build, so growth is held to the
			-- same darkness bound as every other dressing colour. A family may make a creature easier to
			-- SEE — that direction is always safe — but it may not make one glow.
			local function luminance(color: Color3): number
				return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
			end
			for _, profile in CaveFamilyRules.list() do
				for index, color in profile.presentation.creatures.growthPalette do
					Harness.expect(
						luminance(color) <= 0.4,
						string.format(
							"%s creature growth[%d] is too bright (%.3f)",
							profile.id,
							index,
							luminance(color)
						)
					)
				end
			end
		end),

		Harness.test("each family's air carries light a different distance", function()
			-- THE MOST FUNDAMENTAL VISUAL DIFFERENCE BETWEEN THESE CAVES, because when light is the only
			-- source of visual information, how far it reaches IS how big the world feels. This used to
			-- be one global value with three tints over it.
			local stone = CaveFamilyRules.atmosphere("STONE")
			local moss = CaveFamilyRules.atmosphere("MOSS")
			local ice = CaveFamilyRules.atmosphere("ICE")

			-- Moss is the thickest air and Ice the thinnest, matching what each family already is: a
			-- choked wet warren against open glacier halls.
			Harness.expect(moss.density > stone.density, "Moss must swallow a flame sooner than Stone")
			Harness.expect(ice.density < stone.density, "Ice must let a flame reach further than Stone")
			-- Haze is depth. Ice's long halls need a readable far end; Moss's should end in a wall of
			-- dark a few studs out.
			Harness.expect(ice.haze > moss.haze, "Ice must show more distance than Moss")
		end),

		Harness.test("no family may thin the air enough to make an unlit room legible", function()
			-- THE LINE A FAMILY MAY NOT CROSS. Every other system in the game — the brightness dial, the
			-- threat light bands, the entire reason wax matters — assumes you cannot see without a flame.
			-- Enforced by clamp AND by validate, so neither a retune nor a fourth family can cross it.
			local floor = CaveFamilyRules.minimumAtmosphereDensity
			Harness.expect(floor > 0, "there must be a real darkness floor")
			for _, profile in CaveFamilyRules.list() do
				Harness.expect(
					CaveFamilyRules.atmosphere(profile.id).density >= floor,
					profile.id .. " thinned the dark past the shared floor"
				)
			end
			-- Even a hostile profile is clamped rather than obeyed.
			local hostile = CaveFamilyRules.atmosphere("NOT_A_FAMILY")
			Harness.expect(hostile.density >= floor, "an unknown family must still resolve to real darkness")
		end),

		Harness.test("each cave sounds a different size, and the lobby inherits none of it", function()
			-- Reverb is the strongest "different place" signal in audio because it colours every sound at
			-- once. Ordered against what each family physically is: Ice has the fewest internal
			-- formations, the longest connectors and the hardest surfaces; Moss has the most cover, the
			-- densest formations and the tightest rooms.
			local stone = CaveFamilyRules.acoustics("STONE")
			local moss = CaveFamilyRules.acoustics("MOSS")
			local ice = CaveFamilyRules.acoustics("ICE")

			Harness.expect(ice.decayScale > stone.decayScale, "Ice must ring longer than Stone")
			Harness.expect(moss.decayScale < stone.decayScale, "Moss must be deader than Stone")
			Harness.expect(ice.wetOffset > moss.wetOffset, "Ice must be the more reflective cave")

			-- Stone is the authored mix untouched: Config/Audio's per-bus reverb was tuned in a Stone
			-- cave, so a scale of exactly 1 and an offset of exactly 0 is what makes it the baseline.
			Harness.near(stone.decayScale, 1, 1e-9, "Stone must leave the authored reverb alone")
			Harness.near(stone.wetOffset, 0, 1e-9, "Stone must leave the authored wet level alone")

			-- A family may never delete the cave's acoustic outright, however dead it wants to sound.
			for _, profile in CaveFamilyRules.list() do
				Harness.expect(CaveFamilyRules.acoustics(profile.id).decayScale > 0, profile.id .. " has no acoustic")
			end
		end),

		Harness.test("every cave sounds different underfoot, and water overrides all of them", function()
			-- The most frequent sound in the game, and one that did not exist at all until recently: the
			-- player made no noise walking, which is what makes a first-person body read as a camera.
			local seen: { [string]: string } = {}
			for _, profile in CaveFamilyRules.list() do
				local cue = CaveFamilyRules.footstepCue(profile.id, false)
				Harness.expect(#cue > 0, profile.id .. " has no footstep")
				local owner = seen[cue]
				Harness.expect(
					owner == nil,
					string.format("%s and %s walk on the same floor", profile.id, tostring(owner))
				)
				seen[cue] = profile.id

				-- Wading is the same water in every cave, and it is a hazard actively costing wax, so it
				-- takes over from the family's own surface everywhere.
				Harness.equal(
					CaveFamilyRules.footstepCue(profile.id, true),
					CaveFamilyRules.waterFootstepCue,
					profile.id .. " must sound like water when it is standing in water"
				)
			end
			-- An unknown family still produces a real sound rather than dropping the player's body.
			Harness.expect(#CaveFamilyRules.footstepCue("NOT_A_FAMILY", false) > 0, "an unknown cave still has a floor")
		end),

		Harness.test("each cave names its Warden after itself, and Stone keeps the original", function()
			-- The one place the `{Family} {Name}` rule bends. Applying it literally would rename Stone's
			-- encounter to "Warden" and produce "Moss Stone Warden"; treating "Stone Warden" as already
			-- being the prefixed form costs nothing and reads correctly in all three.
			Harness.equal(CaveFamilyRules.wardenDisplayName("STONE"), "Stone Warden")
			Harness.equal(CaveFamilyRules.wardenDisplayName("MOSS"), "Moss Warden")
			Harness.equal(CaveFamilyRules.wardenDisplayName("ICE"), "Ice Warden")
			-- An unknown id resolves to the free family like everything else, so a stale payload names
			-- a real creature rather than producing an empty string in a death message.
			Harness.equal(CaveFamilyRules.wardenDisplayName(nil), "Stone Warden")
			Harness.equal(CaveFamilyRules.wardenDisplayName("NOPE"), "Stone Warden")
		end),

		Harness.test("the set-piece creatures hide against their own family's rock", function()
			-- The Ashamed Lurker's socket and the Warden's courses were hardcoded to Stone's slate, so
			-- both only worked in one cave of three. What the resolver hands them now has to actually
			-- differ per family, or the fix is cosmetic.
			local signatures: { [string]: string } = {}
			for _, profile in CaveFamilyRules.list() do
				local dressing = CaveFamilyRules.creatureDressing(profile.id)
				-- It must BE this family's wall, not an approximation of it.
				Harness.equal(
					dressing.rockColor,
					profile.presentation.wallColor,
					profile.id .. " socket is not its wall"
				)
				Harness.equal(dressing.rockMaterial, profile.presentation.wallMaterial, profile.id .. " socket grain")

				local signature = string.format("%s|%s", tostring(dressing.rockColor), tostring(dressing.rockMaterial))
				for otherId, otherSignature in signatures do
					Harness.expect(
						signature ~= otherSignature,
						string.format("%s and %s hide against the same rock", profile.id, otherId)
					)
				end
				signatures[profile.id] = signature
			end
		end),

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
