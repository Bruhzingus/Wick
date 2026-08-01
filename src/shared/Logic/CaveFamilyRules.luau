--!strict
-- Pure evaluation of the cave-family profiles. Config/CaveFamilies is data; this module is the only
-- place that data is interpreted, validated, or turned into a number a generator can use.
--
-- THE RULE THIS MODULE EXISTS TO ENFORCE: no service, planner, or builder may branch on a cave-family
-- id. They ask for a resolved value — a threat budget, a ceiling roll, a doorway width, a shape
-- weight — and get one. That is what keeps "add a fourth family" a config row rather than a sweep
-- through the codebase looking for `if familyId == "MOSS"`.

local Types = require(script.Parent.Parent.Types)
local CaveFamiliesConfig = require(script.Parent.Parent.Config.CaveFamilies)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local VinesConfig = require(script.Parent.Parent.Config.Vines)
local DepthConfig = require(script.Parent.Parent.Config.Depth)
local DepthRules = require(script.Parent.DepthRules)

local CaveFamilyRules = {}

export type CaveFamilyId = CaveFamiliesConfig.CaveFamilyId
export type CaveFamilyProfile = CaveFamiliesConfig.CaveFamilyProfile
export type RoomShapeKind = CaveFamiliesConfig.RoomShapeKind

local FAMILIES: { CaveFamilyProfile } = CaveFamiliesConfig.families
local DEFAULT_ID: CaveFamilyId = CaveFamiliesConfig.defaultId

-- Every shape kind, in a fixed order. Weight resolution walks THIS list rather than iterating the
-- weights table, so a family's shape roll never depends on Lua's hash ordering.
local SHAPE_ORDER: { RoomShapeKind } = { "Rectangle", "Ellipse", "Capsule", "TwinLobe" }

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

function CaveFamilyRules.shapeKinds(): { RoomShapeKind }
	return SHAPE_ORDER
end

function CaveFamilyRules.list(): { CaveFamilyProfile }
	return FAMILIES
end

function CaveFamilyRules.byId(familyId: string?): CaveFamilyProfile?
	if typeof(familyId) ~= "string" then
		return nil
	end
	for _, profile in FAMILIES do
		if profile.id == familyId then
			return profile
		end
	end
	return nil
end

function CaveFamilyRules.isValidId(familyId: string?): boolean
	return CaveFamilyRules.byId(familyId) ~= nil
end

-- The profile a caller actually gets. An unknown, absent, or rolled-back id resolves to the free
-- family rather than erroring: a floor built before a config change, or a save restored across one,
-- must still generate. Access is never granted by this fallback — Stone is free to everybody.
function CaveFamilyRules.resolve(familyId: string?): CaveFamilyProfile
	local profile = CaveFamilyRules.byId(familyId)
	if profile ~= nil then
		return profile
	end
	local fallback = CaveFamilyRules.byId(DEFAULT_ID)
	if fallback == nil then
		-- A config with no default family is a broken config, but a run still has to be playable
		-- rather than crash mid-descent.
		return FAMILIES[1]
	end
	return fallback
end

-- The numeric tier row this family occupies. This is the value the lobby, shop, party, elevator and
-- pre-family save data all speak, and it is also this family's contribution to the deterministic
-- floor seed (Logic/DepthRules.getFloorSeed) — which is why it is a stable property of the row
-- rather than a derived hash of the string.
function CaveFamilyRules.legacyTierId(familyId: string?): number
	return CaveFamilyRules.resolve(familyId).legacyTierId
end

function CaveFamilyRules.fromLegacyTierId(tierId: number?): CaveFamilyProfile?
	if typeof(tierId) ~= "number" or not isFiniteNumber(tierId) then
		return nil
	end
	local whole = math.floor(tierId)
	for _, profile in FAMILIES do
		if profile.legacyTierId == whole then
			return profile
		end
	end
	return nil
end

-- THE v3 -> v4 SAVE MIGRATION, as a pure function so it can be tested without a DataStore.
-- `Interfaces/Persistence.migrate` calls exactly this; there is no second copy of the rule.
--
-- A RENAME, NOT A GRANT AND NOT A REVOCATION. Each numeric tier a player owned maps to the family
-- that now occupies that row, so The Descent's owner owns Moss and The Deep's owner owns Ice. Nobody
-- gains access they did not buy and nobody loses access they did.
--
-- IDEMPOTENT: `existing` is carried through and every id is checked before insertion, so running it
-- twice — or running it on a profile that has already been migrated and re-saved — produces exactly
-- the same set. Order is stable (existing entries first, then legacy rows in family order) so two
-- runs cannot even differ by ordering.
--
-- A LEGACY ROW THAT NO LONGER MAPS IS DROPPED. If a future config removes a family there is nothing
-- to own; recording an id with no profile behind it would leave dead data in the save and an
-- ownership check that can never be satisfied.
function CaveFamilyRules.migrateOwnedTiers(legacyTierIds: { any }?, existing: { string }?): { string }
	local owned: { string } = {}
	if existing ~= nil then
		for _, familyId in existing do
			if
				typeof(familyId) == "string"
				and CaveFamilyRules.isValidId(familyId)
				and table.find(owned, familyId) == nil
			then
				table.insert(owned, familyId)
			end
		end
	end
	if legacyTierIds == nil then
		return owned
	end
	-- Iterating FAMILIES outside and the legacy list inside keeps the output order a property of the
	-- config rather than of whatever order a corrupt save happened to store its tiers in.
	for _, profile in FAMILIES do
		if table.find(owned, profile.id) ~= nil then
			continue
		end
		for _, tierId in legacyTierIds do
			if typeof(tierId) == "number" and isFiniteNumber(tierId) and math.floor(tierId) == profile.legacyTierId then
				table.insert(owned, profile.id)
				break
			end
		end
	end
	return owned
end

--------------------------------------------------------------------------------
-- Difficulty resolution
--------------------------------------------------------------------------------

local function bandMultiplier(table_: { [string]: number }, band: string): number
	local value = table_[band]
	if value == nil or not isFiniteNumber(value) or value < 0 then
		return 1
	end
	return value
end

-- THE canonical family threat scaling:
--
--   resolvedThreatBudget = baseThreatBudgetForFloor x caveBaseThreatMultiplier x caveThreatBandMultiplier
--
-- The caller supplies the first factor (Config/Floors.threatBudgetPerFloor extended by
-- Logic/DepthRules); this returns the product of the other two. Party scaling, room caps, hazard
-- caps, introduction rules, protected-room rules and planner safety validation all still apply on
-- top and are never relaxed to reach a number.
function CaveFamilyRules.threatBudgetMultiplier(profile: CaveFamilyProfile, globalDepth: number): number
	local band = DepthRules.getDepthBand(globalDepth)
	return math.max(0, profile.baseThreatMultiplier) * bandMultiplier(profile.threatBandMultipliers, band)
end

-- Same shape for unstable formations (dripstone in Stone and Moss, icicles in Ice). The planner's
-- own per-room cap, hazardous-room fraction, and harmless-formation ratio still bind above this.
function CaveFamilyRules.hazardBudgetMultiplier(profile: CaveFamilyProfile, globalDepth: number): number
	local band = DepthRules.getDepthBand(globalDepth)
	return math.max(0, profile.baseHazardMultiplier)
		* bandMultiplier(profile.hazardBandMultipliers, band)
		* math.max(0, profile.geometry.dripstoneFactor)
end

-- HOW WIDELY falling hazards spread across a floor in this family, scaled from the authored per-band
-- fraction (Config/Hazards.unstableDripstone).
--
-- WHY THE SPREAD AND NOT JUST THE COUNT. How many formations one room can physically hold is settled
-- by geometry — the trigger discs have to clear each other, the doorway lanes and the room's own
-- walls — and that ceiling is around three or four whatever the budget says. Past roughly floor eight
-- every family therefore saturated at the same number and the family hazard multiplier stopped
-- meaning anything at exactly the depths it was supposed to matter most. The only lever that moves a
-- floor's total is how many ROOMS are dangerous, so that is the one a family scales.
--
-- SQUARE-ROOTED on purpose. The raw hazard multiplier grows past 2.9 by the Dangerous band, and
-- applying it directly would put every family on the ceiling immediately and flatten the difference
-- all over again. The root keeps the ordering while leaving room between families.
--
-- The result is capped below 1, and the planner additionally refuses to make every ordinary room
-- dangerous: a floor always keeps somewhere with nothing overhead, because a cave with no safe ground
-- is a corridor with a timer.
function CaveFamilyRules.hazardousRoomFraction(
	profile: CaveFamilyProfile,
	globalDepth: number,
	authoredFraction: number
): number
	local scalar = math.sqrt(math.max(0, CaveFamilyRules.hazardBudgetMultiplier(profile, globalDepth)))
	return math.clamp(authoredFraction * scalar, 0, 0.85)
end

--------------------------------------------------------------------------------
-- Threat ecology
--------------------------------------------------------------------------------

function CaveFamilyRules.threatWeightMultiplier(profile: CaveFamilyProfile, threatId: Types.ThreatId): number
	local value = profile.threatEcology.weightMultipliers[threatId]
	if value == nil or not isFiniteNumber(value) or value < 0 then
		return 1
	end
	return value
end

-- The depth index a threat's authored spawn-weight table is sampled at in this family. A positive
-- shift samples the table as though the floor were deeper, which is how a family introduces an
-- existing row earlier without editing Config/Threats. Never samples below the first authored row,
-- so a shift can bring a threat forward but never past its own floor-1 weight.
function CaveFamilyRules.threatDepthIndex(
	profile: CaveFamilyProfile,
	threatId: Types.ThreatId,
	globalDepth: number
): number
	local shift = profile.threatEcology.introductionShift[threatId]
	if shift == nil or not isFiniteNumber(shift) then
		return globalDepth
	end
	return math.max(1, globalDepth + math.floor(shift))
end

--------------------------------------------------------------------------------
-- Topology and geometry
--------------------------------------------------------------------------------

function CaveFamilyRules.loopConnectionChance(profile: CaveFamilyProfile): number
	return math.clamp(FloorsConfig.loopConnectionChance * math.max(0, profile.topology.loopBias), 0, 1)
end

function CaveFamilyRules.minimumLoopConnections(profile: CaveFamilyProfile): number
	return math.max(0, math.floor(FloorsConfig.minimumLoopConnections * math.max(0, profile.topology.loopBias) + 0.5))
end

-- Higher optional-branch bias means assembly continues the newest chain LESS often, which is what
-- leaves older rooms with spare sides for side branches to hang off.
function CaveFamilyRules.linearContinuationChance(profile: CaveFamilyProfile): number
	local bias = math.max(0.001, profile.topology.optionalBranchBias)
	return math.clamp(FloorsConfig.linearContinuationChance / bias, 0, 1)
end

-- A LONGER connector bias means folding back beside an existing room LESS often, so the floor spreads
-- into longer runs instead of compacting into a knot.
function CaveFamilyRules.loopSeekingChance(profile: CaveFamilyProfile): number
	local bias = math.max(0.001, profile.topology.connectorLengthBias)
	return math.clamp(FloorsConfig.loopSeekingChance / bias, 0, 1)
end

-- The per-room ceiling. Every family rolls across the FULL authored range and is then pulled toward
-- its own preferred band by `ceilingPreferenceStrength`, so no family loses its tall rooms or its
-- tight ones — Moss stays capable of an open cavern and Ice of a low crawl. `verticalVariation`
-- widens or narrows the spread around whatever the pull produced.
function CaveFamilyRules.rollCeilingHeight(profile: CaveFamilyProfile, rng: Random): number
	local g = FloorsConfig.geometry
	local low, high = g.ceilingMinHeight, g.ceilingMaxHeight
	local free = low + (high - low) * rng:NextNumber()

	local geometry = profile.geometry
	local strength = math.clamp(geometry.ceilingPreferenceStrength, 0, 1)
	local preferredLow = math.clamp(math.min(geometry.ceilingPreferredMin, geometry.ceilingPreferredMax), low, high)
	local preferredHigh = math.clamp(math.max(geometry.ceilingPreferredMin, geometry.ceilingPreferredMax), low, high)
	-- A SECOND roll rather than reusing the first: reusing it would make the pull a deterministic
	-- function of the free roll and collapse the family's ceilings onto one curve.
	local preferred = preferredLow + (preferredHigh - preferredLow) * rng:NextNumber()
	local pulled = free * (1 - strength) + preferred * strength

	local spread = math.max(0, profile.topology.verticalVariation)
	local centre = (low + high) / 2
	return math.clamp(centre + (pulled - centre) * spread, low, high)
end

-- The doorway width this family actually cuts. NEVER below the shared safe minimum: a family may
-- make its openings tighter on average and can never make one impassable, which is why the clamp
-- lives here rather than in each caller.
function CaveFamilyRules.doorwayWidth(profile: CaveFamilyProfile, rolledWidth: number): number
	local g = FloorsConfig.geometry
	local bias = math.max(0, profile.geometry.doorwayWidthBias)
	-- `doorwayMinWidth` is the authored floor for a physical opening — the tight crevice the geometry
	-- is deliberately biased toward. It is NOT `doorClearanceWidth`, which is the wider protected lane
	-- the planner keeps free INSIDE the room around that opening; clamping to that would turn every
	-- crevice in the game into a hall.
	return math.clamp(rolledWidth * bias, g.doorwayMinWidth, g.doorwayMaxWidth)
end

function CaveFamilyRules.wetFloorProbability(profile: CaveFamilyProfile): number
	return math.clamp(profile.environment.wetFloorProbability, 0, 1)
end

function CaveFamilyRules.internalFormationCount(profile: CaveFamilyProfile, baseCount: number): number
	return math.max(0, math.floor(baseCount * math.max(0, profile.geometry.internalFormationDensity) + 0.5))
end

-- Vine curtains, with this family's introduction shift and count factor applied. A family with vines
-- disabled returns zero at every depth, so no curtain planning happens at all rather than being
-- filtered out later.
function CaveFamilyRules.vineTargetCount(profile: CaveFamilyProfile, globalDepth: number): number
	local environment = profile.environment
	if not environment.vinesEnabled or not VinesConfig.enabled then
		return 0
	end
	local shifted = globalDepth + math.max(0, math.floor(environment.vineIntroductionShift))
	if shifted < VinesConfig.minDepth then
		return 0
	end
	local counts = VinesConfig.perFloorByDepth
	if #counts == 0 then
		return 0
	end
	local authored = math.max(0, counts[math.clamp(math.floor(shifted), 1, #counts)])
	return math.max(0, math.floor(authored * math.max(0, environment.vineCountFactor) + 0.5))
end

--------------------------------------------------------------------------------
-- Room shapes
--------------------------------------------------------------------------------

function CaveFamilyRules.shapeWeight(profile: CaveFamilyProfile, kind: RoomShapeKind): number
	local weight = profile.roomShapeWeights[kind]
	if weight == nil or not isFiniteNumber(weight) or weight < 0 then
		return 0
	end
	return weight
end

-- Which outer footprint an ordinary room takes, from ONE uniform roll in [0, 1). Walks the fixed
-- shape order so the result never depends on table iteration order, and falls back to Rectangle when
-- a family's weights are all zero — a room always has a footprint.
function CaveFamilyRules.selectShapeKind(profile: CaveFamilyProfile, roll: number): RoomShapeKind
	local total = 0
	for _, kind in SHAPE_ORDER do
		total += CaveFamilyRules.shapeWeight(profile, kind)
	end
	if total <= 0 then
		return "Rectangle"
	end
	local target = math.clamp(if roll == roll then roll else 0, 0, 0.9999999) * total
	local cumulative = 0
	for _, kind in SHAPE_ORDER do
		cumulative += CaveFamilyRules.shapeWeight(profile, kind)
		if target < cumulative then
			return kind
		end
	end
	return "Rectangle"
end

function CaveFamilyRules.rollRoomSizeScale(profile: CaveFamilyProfile, rng: Random): number
	local geometry = profile.geometry
	local low = math.max(0.1, math.min(geometry.roomSizeScaleMin, geometry.roomSizeScaleMax))
	local high = math.max(low, math.max(geometry.roomSizeScaleMin, geometry.roomSizeScaleMax))
	if high <= low then
		return low
	end
	return rng:NextNumber(low, high)
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

export type ValidationIssue = { familyId: string, field: string, message: string }

-- Fails LOUDLY in tests and quietly at runtime: `validate` returns issues instead of erroring, so a
-- bad config row is a failing test rather than a server that will not boot. Everything here is a
-- property a family may never violate, not a taste judgement about tuning.
function CaveFamilyRules.validate(): (boolean, { ValidationIssue })
	local issues: { ValidationIssue } = {}
	local function fail(familyId: string, field: string, message: string)
		table.insert(issues, { familyId = familyId, field = field, message = message })
	end

	local seenIds: { [string]: boolean } = {}
	local seenTierIds: { [number]: boolean } = {}
	local bandIds: { string } = {}
	for _, band in DepthConfig.bands do
		table.insert(bandIds, band.id)
	end

	if CaveFamilyRules.byId(DEFAULT_ID) == nil then
		fail(tostring(DEFAULT_ID), "defaultId", "the default family id does not name a real row")
	end

	local referenceDrain: number? = nil

	for _, profile in FAMILIES do
		local id = profile.id

		if seenIds[id] then
			fail(id, "id", "duplicate family id")
		end
		seenIds[id] = true

		if typeof(profile.displayName) ~= "string" or #profile.displayName == 0 then
			fail(id, "displayName", "must be a non-empty string")
		end
		if seenTierIds[profile.legacyTierId] then
			fail(id, "legacyTierId", "duplicate legacy tier id " .. tostring(profile.legacyTierId))
		end
		seenTierIds[profile.legacyTierId] = true
		if profile.legacyTierId % 1 ~= 0 or profile.legacyTierId < 1 then
			fail(id, "legacyTierId", "must be a whole number at or above 1")
		end

		for _, field in { "entryFee", "unlockCost", "payoutPermille" } do
			local value = (profile :: any)[field]
			if not isFiniteNumber(value) or value < 0 or value % 1 ~= 0 then
				fail(id, field, "currency values must be whole and non-negative")
			end
		end

		for _, field in { "baseThreatMultiplier", "baseHazardMultiplier", "waxDrainMultiplier" } do
			local value = (profile :: any)[field]
			if not isFiniteNumber(value) or value < 0 then
				fail(id, field, "must be a finite, non-negative multiplier")
			end
		end

		-- EQUAL PASSIVE DRAIN IS A PRODUCT INVARIANT, not a tuning value: a family may never be
		-- harder because the unavoidable timer runs faster.
		if referenceDrain == nil then
			referenceDrain = profile.waxDrainMultiplier
		elseif profile.waxDrainMultiplier ~= referenceDrain then
			fail(id, "waxDrainMultiplier", "every family must share one passive wax drain multiplier")
		end

		for _, band in bandIds do
			for _, field in { "threatBandMultipliers", "hazardBandMultipliers" } do
				local value = ((profile :: any)[field] :: { [string]: number })[band]
				if value == nil then
					fail(id, field, "missing band " .. band)
				elseif not isFiniteNumber(value) or value < 0 then
					fail(id, field, "band " .. band .. " must be finite and non-negative")
				end
			end
		end

		local shapeTotal = 0
		for _, kind in SHAPE_ORDER do
			local weight = profile.roomShapeWeights[kind]
			if weight == nil then
				fail(id, "roomShapeWeights", "missing shape " .. kind)
			elseif not isFiniteNumber(weight) or weight < 0 then
				fail(id, "roomShapeWeights", kind .. " must be finite and non-negative")
			else
				shapeTotal += weight
			end
		end
		if shapeTotal <= 0 then
			fail(id, "roomShapeWeights", "at least one shape must carry weight")
		end

		local geometry = profile.geometry
		if geometry.roomSizeScaleMin <= 0 or geometry.roomSizeScaleMax < geometry.roomSizeScaleMin then
			fail(id, "geometry.roomSizeScale", "min must be positive and no greater than max")
		end
		if geometry.ceilingPreferredMax < geometry.ceilingPreferredMin then
			fail(id, "geometry.ceilingPreferred", "max must not be below min")
		end
		if geometry.ceilingPreferenceStrength < 0 or geometry.ceilingPreferenceStrength > 1 then
			fail(id, "geometry.ceilingPreferenceStrength", "must be within [0, 1]")
		end
		for _, field in { "internalFormationDensity", "doorwayWidthBias", "dripstoneFactor" } do
			local value = (geometry :: any)[field]
			if not isFiniteNumber(value) or value < 0 then
				fail(id, "geometry." .. field, "must be finite and non-negative")
			end
		end

		local topology = profile.topology
		for _, field in { "loopBias", "optionalBranchBias", "connectorLengthBias", "verticalVariation" } do
			local value = (topology :: any)[field]
			if not isFiniteNumber(value) or value <= 0 then
				fail(id, "topology." .. field, "must be finite and positive")
			end
		end

		local environment = profile.environment
		if environment.wetFloorProbability < 0 or environment.wetFloorProbability > 1 then
			fail(id, "environment.wetFloorProbability", "must be within [0, 1]")
		end
		if not isFiniteNumber(environment.vineIntroductionShift) or environment.vineIntroductionShift < 0 then
			fail(id, "environment.vineIntroductionShift", "must be finite and non-negative")
		end
		if not isFiniteNumber(environment.vineCountFactor) or environment.vineCountFactor < 0 then
			fail(id, "environment.vineCountFactor", "must be finite and non-negative")
		end

		for threatId, multiplier in profile.threatEcology.weightMultipliers do
			if not isFiniteNumber(multiplier) or multiplier < 0 then
				fail(id, "threatEcology.weightMultipliers", tostring(threatId) .. " must be finite and non-negative")
			end
		end
		for threatId, shift in profile.threatEcology.introductionShift do
			if not isFiniteNumber(shift) or shift % 1 ~= 0 then
				fail(id, "threatEcology.introductionShift", tostring(threatId) .. " must be a whole number")
			end
		end

		local ore = profile.ore
		if ore.nativeTier % 1 ~= 0 or ore.nativeTier < 1 then
			fail(id, "ore.nativeTier", "must be a whole tier at or above 1")
		end
		if #ore.availability == 0 then
			fail(id, "ore.availability", "must contain at least one band")
		end
		local previousMinDepth: number? = nil
		for _, band in ore.availability do
			if band.minDepth % 1 ~= 0 or band.minDepth < 1 then
				fail(id, "ore.availability", "band minDepth must be a whole depth at or above 1")
			end
			-- Deepest-first ordering is what makes resolution a single forward scan.
			if previousMinDepth ~= nil and band.minDepth >= previousMinDepth then
				fail(id, "ore.availability", "bands must be listed deepest-first")
			end
			previousMinDepth = band.minDepth
			local total = 0
			for _, entry in band.tiers do
				if entry.tier % 1 ~= 0 or entry.tier < 1 then
					fail(id, "ore.availability", "tier ids must be whole numbers at or above 1")
				end
				if not isFiniteNumber(entry.weight) or entry.weight < 0 then
					fail(id, "ore.availability", "tier weights must be finite and non-negative")
				end
				total += entry.weight
			end
			if total <= 0 then
				fail(id, "ore.availability", "every band must carry weight")
			end
		end
		-- The shallowest band is the family's identity: at depth 1 you mine exactly its native rock.
		local shallowest = ore.availability[#ore.availability]
		if shallowest ~= nil then
			if shallowest.minDepth ~= 1 then
				fail(id, "ore.availability", "the shallowest band must start at depth 1")
			end
			if #shallowest.tiers ~= 1 or shallowest.tiers[1].tier ~= ore.nativeTier then
				fail(id, "ore.availability", "the shallowest band must be exactly the native tier")
			end
		end

		local presentation = profile.presentation
		if typeof(presentation.threatVariantId) ~= "string" or #presentation.threatVariantId == 0 then
			fail(id, "presentation.threatVariantId", "must be a non-empty string")
		end
		if presentation.threatVariantTintStrength < 0 or presentation.threatVariantTintStrength > 1 then
			fail(id, "presentation.threatVariantTintStrength", "must be within [0, 1]")
		end
		if presentation.coverDensityFactor < 0 or not isFiniteNumber(presentation.coverDensityFactor) then
			fail(id, "presentation.coverDensityFactor", "must be finite and non-negative")
		end
	end

	return #issues == 0, issues
end

return CaveFamilyRules
