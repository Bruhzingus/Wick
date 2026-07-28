--!strict
-- Forces the world dark at runtime (DESIGN §16: light is the only source of visual information).
-- default.project.json also pins some Lighting/Atmosphere/Workspace properties directly (editor
-- ambience, `Technology`, which scripts cannot set, and values this module never touches). Its
-- `Lighting.Brightness = 2` is deliberately left bright for level-editing in Studio's edit mode;
-- `apply()` below always overrides it to 0 the moment a server actually starts, so the two values
-- are not a conflict — Studio's static default and this runtime override serve different moments.

local Lighting = game:GetService("Lighting")

local EnvironmentSetup = {}

function EnvironmentSetup.apply()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0
end

-- Cave-tier "shade": retints the one global Atmosphere (default.project.json's WickAtmosphere)
-- toward the tier's configured color/decay, so a harder tier reads as a visibly darker cave.
-- Ambient stays pinned at black by apply() above; Atmosphere is the only global left to darken.
--
-- TODO (PHASE 10 HOOK 1 of 4 — `CaveTier.biomeId`, Config/CaveTiers): this is the cheapest and most
-- visible place a per-tier BIOME identity would land. Fog colour and decay already vary by tier here,
-- so a biome's hue is two more property writes on an Atmosphere that already exists — no new system,
-- no new instance, and it reverts by passing the tier's existing values.
--
-- The signature would take the tier row (or its `biomeId`) rather than two loose colours, and the
-- biome would select the pair. It is deliberately NOT written that way today: an unused parameter is
-- a promise, and this phase is scaffolding, not a promise.
--
-- BLOCKED ON A DOCUMENTATION CONFLICT before any of this is implemented — "multiple biomes" is on the
-- NEVER list in DESIGN.md §16 and GAME-BRIEF.md §19, and ART-BIBLE.md §12 calls the caves "never a
-- themed biome". Read the full note at `NEUTRAL_BIOME` in Config/CaveTiers first.
function EnvironmentSetup.applyCaveTier(atmosphereColor: Color3, atmosphereDecay: Color3)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere == nil then
		return
	end
	atmosphere.Color = atmosphereColor
	atmosphere.Decay = atmosphereDecay
end

return EnvironmentSetup
