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
function EnvironmentSetup.applyCaveTier(atmosphereColor: Color3, atmosphereDecay: Color3)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere == nil then
		return
	end
	atmosphere.Color = atmosphereColor
	atmosphere.Decay = atmosphereDecay
end

return EnvironmentSetup
