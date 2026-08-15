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
-- Both are plain data files that require only Types, so validating a family's hazard and ambience
-- tables against the rows they actually key off costs no dependency cycle.
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local FeelConfig = require(script.Parent.Parent.Config.Feel)
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

-- The three ambient candidates that are NOT rows in `Config/Feel.ambientCave.soundEvents` — the
-- director builds them from their own controllers, or from real world geometry, rather than from a
-- surface raycast. They are weighted through the same per-family table as the sound events, so their
-- ids have to be one shared spelling: the validator below checks a family answered for them and
-- `client/AmbientCaveDirector` looks them up by the same constant. Two copies of the string would
-- fail open, weighting nothing and reporting fine.
local AMBIENT_ROCKFALL_ID = "Rockfall"
local AMBIENT_WATER_DRIP_ID = "WaterDrip"
-- The abandoned workings settling (`Config/MineRelics`). Unlike the other two this one can refuse
-- itself when the floor has no equipment on it, which is a property of the candidate rather than
-- something a family may weight away.
local AMBIENT_RELIC_ID = "OldWorkings"

CaveFamilyRules.ambientRockfallId = AMBIENT_ROCKFALL_ID
CaveFamilyRules.ambientWaterDripId = AMBIENT_WATER_DRIP_ID
CaveFamilyRules.ambientRelicId = AMBIENT_RELIC_ID

-- THE THINNEST AIR ANY CAVE MAY HAVE. A family makes its own call about how far a flame reaches, and
-- this is where that call stops being a family's business: below roughly this, an unlit room starts
-- to become legible, and the darkness is the one thing every other system in this game is built on
-- top of. Enforced by clamp AND by `validate`, so neither a retune nor a new family can cross it.
local MINIMUM_ATMOSPHERE_DENSITY = 0.22
CaveFamilyRules.minimumAtmosphereDensity = MINIMUM_ATMOSPHERE_DENSITY

-- Wading, in every cave. Also the fallback for a family with no footstep cue authored: a real sound
-- from the wrong surface is a far smaller failure than a player who silently stops having a body.
local WATER_FOOTSTEP_CUE = "FootstepWater"
CaveFamilyRules.waterFootstepCue = WATER_FOOTSTEP_CUE

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
-- Hazard ecology
--------------------------------------------------------------------------------

-- The multiplier applied to a falling-formation variant's authored weight in this family. Missing = 1
-- on exactly the same reasoning as `threatWeightMultiplier`: a family narrows the pool rather than
-- deleting rows from it, so a variant nobody weighted stays available instead of silently vanishing.
--
-- ZERO IS MEANINGFUL AND SAFE. A family may refuse a variant outright, and that only removes it from
-- SELECTION — every id stays resolvable by `Logic/DripstoneRules.variantById`, which is what the
-- client controller, the server service and the builder all use to read a formation back out of a
-- plan, and what `Config/StoneWarden.counterDripstoneVariantId` relies on to place its counter crown
-- in a family that might never roll one.
function CaveFamilyRules.dripstoneVariantWeightMultiplier(profile: CaveFamilyProfile, variantId: string): number
	local value = profile.hazardEcology.variantWeightMultipliers[variantId]
	if value == nil or not isFiniteNumber(value) or value < 0 then
		return 1
	end
	return value
end

--------------------------------------------------------------------------------
-- Ambience
--------------------------------------------------------------------------------

-- How much more or less often this family rolls one ambient candidate, by id. Sound events, the
-- rockfall and the water drip all resolve through here, so `client/AmbientCaveDirector` asks ONE
-- question about every candidate it considers rather than three differently-shaped ones.
--
-- THE ONE THING A FAMILY MAY CHANGE ABOUT AUDIO. Rate, and nothing else — cue gain, bus routing and
-- the mixer are Config/Audio's and are identical in every cave. That separation is what keeps a
-- family's soundscape from becoming a difficulty signal: a cave may sound different, it may never
-- sound quiet enough to hide something the player would otherwise have heard coming.
function CaveFamilyRules.ambientWeightMultiplier(profile: CaveFamilyProfile, candidateId: string): number
	local value = profile.ambience.candidateWeights[candidateId]
	if value == nil or not isFiniteNumber(value) or value < 0 then
		return 1
	end
	return value
end

-- How much of this family's roll is spent on authored silence, relative to Config/Feel's own
-- `silentWeight`. Clamped above zero rather than at it: a family that could roll perpetual silence
-- would have stopped being a quieter cave and started being a cave with the ambience turned off.
function CaveFamilyRules.ambientSilenceMultiplier(profile: CaveFamilyProfile): number
	local value = profile.ambience.silenceWeight
	if not isFiniteNumber(value) or value <= 0 then
		return 1
	end
	return value
end

--------------------------------------------------------------------------------
-- Atmosphere
--------------------------------------------------------------------------------

export type AtmosphereSettings = {
	color: Color3,
	decay: Color3,
	density: number,
	haze: number,
	glare: number,
}

-- THE AIR OF THIS CAVE, resolved in one call so the caller writes five properties and makes no
-- decisions. Density is clamped to a FLOOR as well as a ceiling, and that floor is the load-bearing
-- part: thin air is a family trait, but air thin enough to see across an unlit room would end the
-- darkness the whole game rests on. A family may change how far your flame reaches; it may never
-- change whether you need one.
function CaveFamilyRules.atmosphere(familyId: string?): AtmosphereSettings
	local presentation = CaveFamilyRules.resolve(familyId).presentation
	return {
		color = presentation.atmosphereColor,
		decay = presentation.atmosphereDecay,
		density = math.clamp(presentation.atmosphereDensity, MINIMUM_ATMOSPHERE_DENSITY, 1),
		haze = math.clamp(presentation.atmosphereHaze, 0, 10),
		glare = math.clamp(presentation.atmosphereGlare, 0, 10),
	}
end

-- WHAT THIS CAVE'S LIGHT LOOKS LIKE ONCE IT HAS LANDED (`Config/CaveFamilies.ColorGradeProfile`).
--
-- THE ONE LEVER THAT CAN CHANGE A CAVE'S COLOUR TEMPERATURE. Ambient is pinned to black, so every
-- lit pixel in the game is lit by something warm the player carries, and `surface x light` means no
-- material palette can ever produce a cold-looking cave on its own. A grade multiplies the final
-- image instead, which is why it works where three rounds of retinting did not.
--
-- CLAMPED SO IT MAY ONLY EVER DARKEN, and that clamp is what makes this safe rather than merely
-- useful. A tint channel above 1 would AMPLIFY the rendered image — the one thing a grade must never
-- do, because it would brighten an already-dark cave without any light source existing to justify
-- it, and would do so uniformly, including on the geometry the darkness is protecting. Multiplying
-- by a value in [0, 1] can only subtract, and zero times black is still black, so no grade can make
-- an unlit room legible however it is authored. `Brightness` is not exposed at all for the same
-- reason: it is additive, and additive is a light by another name.
function CaveFamilyRules.colorGrade(familyId: string?): CaveFamiliesConfig.ColorGradeProfile
	local authored = CaveFamilyRules.resolve(familyId).presentation.colorGrade
	local function channel(value: number): number
		return if isFiniteNumber(value) then math.clamp(value, 0, 1) else 1
	end
	return {
		tintColor = Color3.new(
			channel(authored.tintColor.R),
			channel(authored.tintColor.G),
			channel(authored.tintColor.B)
		),
		saturation = if isFiniteNumber(authored.saturation) then math.clamp(authored.saturation, -1, 1) else 0,
		contrast = if isFiniteNumber(authored.contrast) then math.clamp(authored.contrast, -1, 1) else 0,
	}
end

-- WHAT THIS CAVE SOUNDS LIKE UNDERFOOT. Standing water overrides the family everywhere: the water is
-- the same water in every cave, and wading is a hazard actively costing wax, so it is the one footfall
-- that should cut through rather than blend into the floor.
function CaveFamilyRules.footstepCue(familyId: string?, inWater: boolean): string
	if inWater then
		return WATER_FOOTSTEP_CUE
	end
	local cue = CaveFamilyRules.resolve(familyId).presentation.footstepCue
	return if typeof(cue) == "string" and #cue > 0 then cue else WATER_FOOTSTEP_CUE
end

export type CaveAcoustics = {
	decayScale: number,
	wetOffset: number,
}

-- HOW BIG THIS CAVE SOUNDS, as a modifier on the authored per-bus reverb rather than a replacement
-- for it. Config/Audio tunes genuinely different tails for ambience, world and focus audio, and a
-- family has to change the space those tails describe without collapsing the difference between them
-- — so this returns a scale and an offset, never absolute values.
--
-- Clamped at both ends. A decay scale of zero would delete the cave's acoustic entirely and a large
-- one would turn a cave into a cathedral; the wet offset is bounded because it is added to a dB
-- level that Roblox itself clamps at -80, and a family that pushed a bus there would have silently
-- muted the room tone rather than deadened it.
function CaveFamilyRules.acoustics(familyId: string?): CaveAcoustics
	local presentation = CaveFamilyRules.resolve(familyId).presentation
	local scale = presentation.reverbDecayScale
	local offset = presentation.reverbWetOffset
	return {
		decayScale = if isFiniteNumber(scale) then math.clamp(scale, 0.25, 4) else 1,
		wetOffset = if isFiniteNumber(offset) then math.clamp(offset, -12, 12) else 0,
	}
end

--------------------------------------------------------------------------------
-- Creature naming
--------------------------------------------------------------------------------

-- WHAT THIS CAVE'S WARDEN IS CALLED: Stone Warden, Moss Warden, Ice Warden.
--
-- THE NAMING RULE EVERYWHERE ELSE is `{Family} {Name}` for the reskinned families with Stone keeping
-- the plain original, because Stone is the default and a default should not be marked. This is the one
-- row where following that literally produces a worse result in both directions: it would rename
-- Stone's encounter to just "Warden" — taking the name from the family that ships it — and it would
-- produce "Moss Stone Warden", where the word "Stone" is describing rock rather than a cave.
--
-- So "Stone Warden" is read as ALREADY being the family-prefixed form. Stone keeps the exact name its
-- players already know, the other two read correctly, and nothing about the encounter's config id,
-- room module, service or files changes — this is a display string and only a display string.
function CaveFamilyRules.wardenDisplayName(familyId: string?): string
	local profile = CaveFamilyRules.resolve(familyId)
	-- Taken from the family's own display name ("Stone Caves" -> "Stone") rather than a second table
	-- to maintain, so a renamed family renames its Warden with it.
	local prefix = string.match(profile.displayName, "^(%S+)")
	return if prefix ~= nil and #prefix > 0 then prefix .. " Warden" else "Warden"
end

-- What a blast vault's door is cut from in this cave (Config/Dynamite). THE ONLY WAY anything is
-- allowed to ask that question: the planner stamps the style into the plan and the builder reads the
-- stamp, so no service, planner or builder ever branches on a family id to dress a door.
function CaveFamilyRules.blastDoorStyle(profile: CaveFamilyProfile): Types.BlastDoorStyle
	return profile.presentation.blastDoorStyle
end

-- WHAT THIS CAVE'S THREE PER-FLOOR FIXTURES ARE BUILT FROM (`Types/Fixtures`): the Basin's Cauldron,
-- the Gas Lantern a run ends at, and the Descent Ladder that carries one player one floor down.
--
-- Resolved through the family the same way a creature's dressing and a vault door's rock are, and
-- for the same reason: no builder, service or model may ever branch on a family id to decide what
-- something looks like. One resolver, three silhouettes, and every rule those fixtures enforce is
-- identical in all three caves.
function CaveFamilyRules.fixtureStyle(familyId: string?): Types.FixtureStyle
	return CaveFamilyRules.resolve(familyId).presentation.fixtureStyle
end

--------------------------------------------------------------------------------
-- Creature dressing
--------------------------------------------------------------------------------

export type CreatureDressing = {
	-- What a body's own skin is lerped toward, and how far. Replaces the client reaching into
	-- `presentation.coverPalette[1]` directly, which was the whole of the family variant system before
	-- families had geometry.
	tint: Color3,
	tintStrength: number,
	growthStyle: CaveFamiliesConfig.CreatureGrowthStyle,
	growthCoverage: number,
	growthSize: number,
	growthPalette: { Color3 },
	growthMaterial: Enum.Material,
	skinMaterial: Enum.Material?,
	-- NOTE: `headExclusion` is deliberately NOT carried here. It is a config invariant enforced by
	-- `validate` and by bodies simply never offering a head anchor — the dresser is handed a list of
	-- surfaces and has no way to recognise a skull, so passing it a flag it cannot act on would have
	-- been a contract that only looked like a guarantee.
	--
	-- THE ROCK A BODY THAT IMITATES ROCK IS IMITATING. Only the two set-pieces read these — the Ashamed
	-- Lurker's wall socket and back plates, and the Stone Warden's courses. Both were authored against
	-- Stone's slate and hardcoded to it, which meant the Lurker's whole premise (invisible in the arch
	-- until a flame resolves it) worked in exactly one of the three caves, and the Warden emerged from a
	-- glacier as a heap of grey slate.
	rockColor: Color3,
	rockLightColor: Color3,
	rockMaterial: Enum.Material,
}

-- EVERYTHING A FAMILY SAYS ABOUT A CREATURE, resolved once. The family answers "what has taken hold in
-- this cave"; each body answers "and this is where it takes hold on me". That split is why one
-- resolver serves five very different silhouettes without knowing anything about any of them.
--
-- A dressing is presentation and ONLY presentation: no caller may derive a stat, a radius, a speed or
-- a perception value from anything here.
function CaveFamilyRules.creatureDressing(familyId: string?): CreatureDressing
	local presentation = CaveFamilyRules.resolve(familyId).presentation
	local creatures = presentation.creatures
	return {
		tint = presentation.coverPalette[1],
		tintStrength = math.clamp(presentation.threatVariantTintStrength, 0, 1),
		growthStyle = creatures.growthStyle,
		growthCoverage = math.clamp(creatures.growthCoverage, 0, 1),
		growthSize = math.max(0, creatures.growthSize),
		growthPalette = creatures.growthPalette,
		growthMaterial = creatures.growthMaterial,
		skinMaterial = creatures.skinMaterial,
		rockColor = presentation.wallColor,
		rockLightColor = presentation.rockColor,
		rockMaterial = presentation.wallMaterial,
	}
end

--------------------------------------------------------------------------------
-- Surface dressing
--------------------------------------------------------------------------------

-- THE SECOND MATERIAL LAYER OVER THIS FAMILY'S FLOOR, and the fringe of ice across its ceilings and
-- doorway mouths. Both are returned as the authored row with the counts floored to whole numbers,
-- because a builder placing 6.4 sheets has to make that decision somewhere and here is the one place
-- that knows it is a count rather than a scalar.
--
-- A family that builds neither returns zero counts and the builder's placement loops simply never
-- run. That is the same shape `groundCoverPatchesPerRoom` already uses and it is what keeps the
-- builder from ever asking which family it is in.
function CaveFamilyRules.floorGlaze(familyId: string?): CaveFamiliesConfig.FloorGlazeProfile
	local authored = CaveFamilyRules.resolve(familyId).presentation.floorGlaze
	local resolved = table.clone(authored)
	resolved.sheetsPerRoom = math.max(0, math.floor(authored.sheetsPerRoom))
	return resolved
end

function CaveFamilyRules.icicleFringe(familyId: string?): CaveFamiliesConfig.IcicleFringeProfile
	local authored = CaveFamilyRules.resolve(familyId).presentation.icicleFringe
	local resolved = table.clone(authored)
	resolved.clustersPerRoom = math.max(0, math.floor(authored.clustersPerRoom))
	resolved.clustersPerDoorway = math.max(0, math.floor(authored.clustersPerDoorway))
	resolved.spikesPerCluster = math.max(0, math.floor(authored.spikesPerCluster))
	return resolved
end

-- HOW THIS FAMILY'S SURFACES HAND THE CANDLE BACK — its wall/ground cover and its formations. See
-- `Config/CaveFamilies.SurfaceFinishProfile` for why this exists at all; the short version is that
-- the eye identifies ice by specular behaviour rather than by hue, and colour alone produced a blue
-- sticker however well the blue was chosen.
function CaveFamilyRules.coverFinish(familyId: string?): CaveFamiliesConfig.SurfaceFinishProfile
	return CaveFamilyRules.resolve(familyId).presentation.coverFinish
end

function CaveFamilyRules.formationFinish(familyId: string?): CaveFamiliesConfig.SurfaceFinishProfile
	return CaveFamilyRules.resolve(familyId).presentation.formationFinish
end

-- DOES THIS FINISH ACTUALLY VARY ANYTHING? The builders ask before rolling, and skip every roll when
-- the answer is no.
--
-- THIS IS A DETERMINISM GUARD, NOT AN OPTIMISATION. Stone is the regression baseline the whole family
-- system is measured against — a Stone floor at a given seed must come out of any refactor identical
-- — and every placement after the cover patches draws from the same random stream. A single
-- unconditional `rng:NextNumber` inside the finish code would shift every boulder, column, straw and
-- relic on the floor, which is a change nobody would see in a diff and everybody would see in a save.
--
-- DERIVED FROM THE DATA rather than carried as a `enabled` flag on purpose: a flag can disagree with
-- the numbers beside it, and the first time it does the bug is invisible.
function CaveFamilyRules.surfaceFinishVaries(finish: CaveFamiliesConfig.SurfaceFinishProfile?): boolean
	if finish == nil then
		return false
	end
	return #finish.materials > 1
		or finish.transparencyMax > finish.transparencyMin
		or finish.reflectanceMax > 0
		or finish.tiltDegrees > 0
end

--------------------------------------------------------------------------------
-- Abandoned workings
--------------------------------------------------------------------------------

export type RelicWeathering = {
	palette: { Color3 },
	material: Enum.Material,
	shape: "Patch" | "Shard",
	-- Chance any one authored anchor on a relic carries growth, already scaled by this family.
	density: number,
	size: number,
}

-- WHAT HAS TAKEN HOLD ON THE EQUIPMENT SOMEBODY LEFT DOWN HERE (`Config/MineRelics`).
--
-- READ OFF THE FAMILY'S SURFACE COVER, NOT OFF A NEW CONFIG BLOCK, and that is deliberate: the moss
-- and the rime a cave creeps over its own walls are the same moss and rime that would creep over a
-- rusting cart standing against one. Adding a parallel `relics` table to every family row would have
-- been a second set of numbers describing one fact about a cave, and the two would drift.
--
-- Density is the family's authored cover factor scaled onto the relic module's own base chance and
-- clamped, so a Moss cave furs the upward faces of a crate while a Stone cave leaves the occasional
-- dark fleck — and neither can reach a coverage that would hide the silhouette underneath.
function CaveFamilyRules.relicWeathering(familyId: string?, baseChance: number, baseSize: number): RelicWeathering
	local presentation = CaveFamilyRules.resolve(familyId).presentation
	local factor = presentation.coverDensityFactor
	local scaled = if isFiniteNumber(factor) and factor > 0 then baseChance * factor else baseChance
	return {
		palette = presentation.coverPalette,
		material = presentation.coverMaterial,
		shape = presentation.coverShape,
		density = math.clamp(scaled, 0, 0.85),
		size = math.max(0, baseSize),
	}
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
		if environment.doorwayBarrierStyle ~= "Vines" and environment.doorwayBarrierStyle ~= "Icicles" then
			fail(id, "environment.doorwayBarrierStyle", "must be Vines or Icicles")
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

		-- EVERY AUTHORED VARIANT MUST BE ANSWERED FOR, the way every depth band must be. A missing entry
		-- resolves to a neutral 1, so without this a newly authored formation would silently appear in
		-- every family at full weight — including the two it was written to be exclusive to one of.
		local variantWeightTotal = 0
		for _, variant in HazardsConfig.unstableDripstone.variants do
			local weight = profile.hazardEcology.variantWeightMultipliers[variant.id]
			if weight == nil then
				fail(id, "hazardEcology.variantWeightMultipliers", "missing variant " .. variant.id)
			elseif not isFiniteNumber(weight) or weight < 0 then
				fail(id, "hazardEcology.variantWeightMultipliers", variant.id .. " must be finite and non-negative")
			else
				variantWeightTotal += weight * math.max(0, variant.weight)
			end
		end
		-- A family that refused every formation would still be handed a hazard budget and would spend
		-- every placement attempt failing to roll anything.
		if variantWeightTotal <= 0 then
			fail(id, "hazardEcology.variantWeightMultipliers", "at least one falling formation must carry weight")
		end

		-- Same completeness rule, same reason: an ambient event nobody weighted would leak into every
		-- family at its authored rate. The two non-cue candidates the director also rolls are named
		-- here because they are weighted through the same table.
		local ambientIds: { string } = { AMBIENT_ROCKFALL_ID, AMBIENT_WATER_DRIP_ID, AMBIENT_RELIC_ID }
		for _, event in FeelConfig.ambientCave.soundEvents do
			table.insert(ambientIds, event.id)
		end
		local ambientWeightTotal = 0
		for _, candidateId in ambientIds do
			local weight = profile.ambience.candidateWeights[candidateId]
			if weight == nil then
				fail(id, "ambience.candidateWeights", "missing ambient candidate " .. candidateId)
			elseif not isFiniteNumber(weight) or weight < 0 then
				fail(id, "ambience.candidateWeights", candidateId .. " must be finite and non-negative")
			else
				ambientWeightTotal += weight
			end
		end
		if ambientWeightTotal <= 0 then
			fail(id, "ambience.candidateWeights", "a cave must be able to make at least one sound")
		end
		-- Quieter is a family trait. Silent is the absence of ambience, and it would be the one audio
		-- change that genuinely alters what a player can hear coming.
		if not isFiniteNumber(profile.ambience.silenceWeight) or profile.ambience.silenceWeight <= 0 then
			fail(id, "ambience.silenceWeight", "must be finite and above zero")
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
		-- A slab may be fully hidden (the terrain wall behind it takes over) or fully shown, and
		-- anything between is a legitimate half-veil. Outside [0, 1] is not a look, it is a mistake
		-- that renders as a solid wall or an invisible one depending on which way it went.
		if
			not isFiniteNumber(presentation.wallSlabTransparency)
			or presentation.wallSlabTransparency < 0
			or presentation.wallSlabTransparency > 1
		then
			fail(id, "presentation.wallSlabTransparency", "must be within [0, 1]")
		end
		if presentation.coverShape ~= "Patch" and presentation.coverShape ~= "Shard" then
			fail(id, "presentation.coverShape", "must be Patch or Shard")
		end
		if not isFiniteNumber(presentation.groundCoverPatchesPerRoom) or presentation.groundCoverPatchesPerRoom < 0 then
			fail(id, "presentation.groundCoverPatchesPerRoom", "must be finite and non-negative")
		end

		-- THE TWO NON-EMISSIVE DRESSING LAYERS. Nothing here can affect gameplay — every piece either
		-- builds is collision-neutral — so what is checked is only that a family which asked for some
		-- can actually be handed something buildable. An unauthored colour resolves to white and an
		-- unauthored material to Plastic, which in a cave lit by one candle is the loudest mistake a
		-- config can make, and a zero or inverted size range would place parts nobody can see.
		local glaze = presentation.floorGlaze
		if glaze == nil then
			fail(id, "presentation.floorGlaze", "every family must answer whether it glazes its floor")
		else
			if not isFiniteNumber(glaze.sheetsPerRoom) or glaze.sheetsPerRoom < 0 then
				fail(id, "presentation.floorGlaze.sheetsPerRoom", "must be finite and non-negative")
			end
			if not isFiniteNumber(glaze.minSize) or glaze.minSize <= 0 or glaze.maxSize < glaze.minSize then
				fail(id, "presentation.floorGlaze", "minSize must be positive and no greater than maxSize")
			end
			if not isFiniteNumber(glaze.thickness) or glaze.thickness <= 0 then
				fail(id, "presentation.floorGlaze.thickness", "must be finite and positive")
			end
			if #glaze.palette == 0 then
				fail(id, "presentation.floorGlaze.palette", "needs at least one colour")
			end
			if typeof(glaze.material) ~= "EnumItem" then
				fail(id, "presentation.floorGlaze.material", "must be a Material")
			end
		end

		-- THE SURFACE FINISHES. Both are presentation-only and neither can affect a gameplay query, so
		-- what is checked is that a family which asked for variation can be handed something buildable
		-- — an inverted range would silently resolve to a single value and quietly undo the whole
		-- point of the field, and a transparency at or above 1 would make cover invisible rather than
		-- clear, which is a very expensive way to delete a family's floor identity.
		for _, entry in
			{
				{ field = "coverFinish", finish = presentation.coverFinish },
				{ field = "formationFinish", finish = presentation.formationFinish },
			}
		do
			local finish = entry.finish
			if finish == nil then
				fail(id, "presentation." .. entry.field, "every family must say how its surfaces catch light")
				continue
			end
			for _, pair in
				{
					{ low = "transparencyMin", high = "transparencyMax" },
					{ low = "reflectanceMin", high = "reflectanceMax" },
				}
			do
				local low = (finish :: any)[pair.low]
				local high = (finish :: any)[pair.high]
				if not isFiniteNumber(low) or not isFiniteNumber(high) or low < 0 or high < low then
					fail(
						id,
						"presentation." .. entry.field .. "." .. pair.low,
						"must be finite, non-negative and no greater than " .. pair.high
					)
				end
			end
			-- Transparency is a [0, 1) property here rather than [0, 1]: a fully transparent facet is
			-- not clear ice, it is a part nobody will ever see doing nothing for the frame budget.
			if finish.transparencyMax >= 1 then
				fail(id, "presentation." .. entry.field .. ".transparencyMax", "must stay below fully invisible")
			end
			if not isFiniteNumber(finish.reflectanceMax) or finish.reflectanceMax > 1 then
				fail(id, "presentation." .. entry.field .. ".reflectanceMax", "must not exceed a mirror")
			end
			for _, field in { "thicknessScale", "sizeScale", "tiltDegrees" } do
				local value = (finish :: any)[field]
				if not isFiniteNumber(value) or value < 0 then
					fail(id, "presentation." .. entry.field .. "." .. field, "must be finite and non-negative")
				end
			end
			if finish.thicknessScale <= 0 or finish.sizeScale <= 0 then
				fail(id, "presentation." .. entry.field, "thickness and size scales must be positive")
			end
			for _, material in finish.materials do
				if typeof(material) ~= "EnumItem" then
					fail(id, "presentation." .. entry.field .. ".materials", "every entry must be a Material")
				end
			end
		end

		local fringe = presentation.icicleFringe
		if fringe == nil then
			fail(id, "presentation.icicleFringe", "every family must answer whether it fringes its openings")
		else
			for _, field in { "clustersPerRoom", "clustersPerDoorway", "spikesPerCluster", "rootThickness", "spread" } do
				local value = (fringe :: any)[field]
				if not isFiniteNumber(value) or value < 0 then
					fail(id, "presentation.icicleFringe." .. field, "must be finite and non-negative")
				end
			end
			if not isFiniteNumber(fringe.minLength) or fringe.minLength <= 0 or fringe.maxLength < fringe.minLength then
				fail(id, "presentation.icicleFringe", "minLength must be positive and no greater than maxLength")
			end
		end

		-- A GRADE MAY RECOLOUR A CAVE AND MAY NEVER BRIGHTEN ONE. Asserted here as well as clamped in
		-- the resolver, on the same footing as the atmosphere density floor: the clamp keeps a bad
		-- config playable, and this is what makes it visible at authoring time. A tint channel above 1
		-- amplifies the final image, which would raise what a player can see with no light source
		-- existing to account for it.
		local grade = presentation.colorGrade
		if grade == nil then
			fail(id, "presentation.colorGrade", "every family must say what its light looks like")
		else
			if typeof(grade.tintColor) ~= "Color3" then
				fail(id, "presentation.colorGrade.tintColor", "must be a Color3")
			else
				for _, entry in
					{
						{ name = "R", value = grade.tintColor.R },
						{ name = "G", value = grade.tintColor.G },
						{ name = "B", value = grade.tintColor.B },
					}
				do
					if not isFiniteNumber(entry.value) or entry.value < 0 or entry.value > 1 then
						fail(
							id,
							"presentation.colorGrade.tintColor." .. entry.name,
							"must be within [0, 1] — a grade may subtract light, never add it"
						)
					end
				end
			end
			for _, field in { "saturation", "contrast" } do
				local value = (grade :: any)[field]
				if not isFiniteNumber(value) or value < -1 or value > 1 then
					fail(id, "presentation.colorGrade." .. field, "must be within [-1, 1]")
				end
			end
		end

		-- THE DARKNESS IS NOT A FAMILY'S TO TRADE AWAY. Density below the shared floor would start to
		-- make an unlit room legible, and every other system in the game — threat light bands, the
		-- brightness dial, the whole reason wax matters — assumes it is not.
		if
			not isFiniteNumber(presentation.atmosphereDensity)
			or presentation.atmosphereDensity < MINIMUM_ATMOSPHERE_DENSITY
		then
			fail(
				id,
				"presentation.atmosphereDensity",
				string.format("must be finite and at least %.2f", MINIMUM_ATMOSPHERE_DENSITY)
			)
		end
		for _, field in { "atmosphereHaze", "atmosphereGlare" } do
			local value = (presentation :: any)[field]
			if not isFiniteNumber(value) or value < 0 then
				fail(id, "presentation." .. field, "must be finite and non-negative")
			end
		end

		-- THE FIXTURES A FLOOR IS SCORED BY. A family may build them out of anything it likes and may
		-- not leave a surface unauthored: a nil material resolves to Plastic and a nil colour to white,
		-- which in a game lit only by one candle is the single most visible mistake a config can make.
		local fixtures = presentation.fixtureStyle
		if fixtures == nil then
			fail(id, "presentation.fixtureStyle", "every family must dress its own three floor fixtures")
		else
			if fixtures.rig ~= "Timbered" and fixtures.rig ~= "Lashed" and fixtures.rig ~= "Chipped" then
				fail(id, "presentation.fixtureStyle.rig", "must be Timbered, Lashed or Chipped")
			end
			for _, field in { "frameColor", "deckColor", "lineColor", "vesselColor" } do
				if typeof((fixtures :: any)[field]) ~= "Color3" then
					fail(id, "presentation.fixtureStyle." .. field, "must be a Color3")
				end
			end
			for _, field in { "frameMaterial", "deckMaterial", "lineMaterial", "vesselMaterial" } do
				if typeof((fixtures :: any)[field]) ~= "EnumItem" then
					fail(id, "presentation.fixtureStyle." .. field, "must be a Material")
				end
			end
		end

		local creatures = presentation.creatures
		if creatures.growthCoverage < 0 or creatures.growthCoverage > 1 then
			fail(id, "presentation.creatures.growthCoverage", "must be within [0, 1]")
		end
		if not isFiniteNumber(creatures.growthSize) or creatures.growthSize < 0 then
			fail(id, "presentation.creatures.growthSize", "must be finite and non-negative")
		end
		if creatures.growthStyle == "None" then
			-- A family that dresses nothing must not also claim coverage. Two config rows disagreeing
			-- about whether anything is built is how a body ends up with invisible parts on it.
			if creatures.growthCoverage > 0 then
				fail(id, "presentation.creatures", "growthStyle None must carry no coverage")
			end
		elseif #creatures.growthPalette == 0 then
			fail(id, "presentation.creatures.growthPalette", "a family that dresses creatures needs colours")
		end
		-- THE HEAD IS NEVER DRESSED, in any family, ever. The crimson dark-hunter slits and the Drawn's
		-- warm halo are how a player decides what to do about the thing in front of them, and they have
		-- to be the first thing that resolves at range in every cave. This is a product invariant on the
		-- same footing as equal passive wax drain, not a taste judgement — so it is checked rather than
		-- left to whoever authors the next family.
		if not creatures.headExclusion then
			fail(id, "presentation.creatures.headExclusion", "a family may never dress a creature's head")
		end
	end

	return #issues == 0, issues
end

return CaveFamilyRules
