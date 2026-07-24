--!strict
-- Forces the world dark at runtime (DESIGN §16: light is the only source of visual information).
-- Kept out of default.project.json so the place file stays a plain scaffold.

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

return EnvironmentSetup
