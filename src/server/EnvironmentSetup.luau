--!strict
-- Forces the world dark at runtime (DESIGN §16: light is the only source of visual information).
-- default.project.json also pins some Lighting/Atmosphere/Workspace properties directly (editor
-- ambience, `Technology`, which scripts cannot set, and values this module never touches). Its
-- `Lighting.Brightness = 2` is deliberately left bright for level-editing in Studio's edit mode;
-- `apply()` below always overrides it to 0 the moment a server actually starts, so the two values
-- are not a conflict — Studio's static default and this runtime override serve different moments.
-- `Workspace.FallenPartsDestroyHeight` works the same way: the project file pins a deep static value
-- so an edit-mode place is never wrong, and `reserveDepth` below owns it once a run is live.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local EnvironmentSetup = {}

-- Studs of engine headroom held below the deepest thing the world contains. It only has to be deeper
-- than anything a body can legitimately reach, and it stays FINITE on purpose: genuinely runaway
-- debris should still eventually be collected, and RunOrchestrator's stranded-runner watchdog
-- catches a falling player within a frame — long before they could travel this far.
local FALL_DESTROY_MARGIN = 1024

-- THE ENGINE DELETES WHAT FALLS TOO FAR, AND THIS CAVE GOES DOWN FOREVER.
--
-- Roblox destroys any unanchored part that ends up below `Workspace.FallenPartsDestroyHeight`, which
-- defaults to -500. An expedition stacks its floors downward at `Config.Floors.geometry.floorGap`
-- studs each, so floor 7 sits at -576 and every floor past it is inside that zone. Arriving there
-- destroyed the candle's parts where they stood: the cave, the HUD and every remote still worked, so
-- the player could look around and use tools while having no body to walk with. Nothing in the game
-- could see it, because PlayerState reads "alive" from the wax and the wax was fine.
--
-- Called with each floor's base height as it is built rather than set once to a guessed constant,
-- because depth is deliberately uncapped (Logic/DepthRules) — a fixed number would only move the
-- same cliff further down.
function EnvironmentSetup.reserveDepth(lowestY: number)
	-- LOWERS ONLY, against the live value rather than a remembered one, so a place that already pins
	-- something deeper — the project file's static plane, or a place with the boundary switched off
	-- entirely, which reads as negative infinity — is never raised to meet us.
	local wanted = lowestY - FALL_DESTROY_MARGIN
	if wanted >= Workspace.FallenPartsDestroyHeight then
		return
	end
	Workspace.FallenPartsDestroyHeight = wanted
end

function EnvironmentSetup.apply()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0
	-- The world origin plane covers the hub (Config/LobbyRoom.origin sits well above it) and floor 1
	-- before any expedition exists. Each floor built afterwards extends it downward itself.
	EnvironmentSetup.reserveDepth(0)
end

-- The cave family's "shade": retints the one global Atmosphere (default.project.json's
-- WickAtmosphere) toward this family's configured colour and decay. Ambient stays pinned at black by
-- apply() above; Atmosphere is the only global left to tint, which is what makes this the cheapest
-- and most visible per-family identity in the game — two property writes, no new instance, and it
-- reverts by passing another family's pair.
--
-- WHAT IT MAY NOT DO: emit anything. ART-BIBLE §4 still holds in every family — the fog takes the
-- family's hue but never its own brightness, because the moment the cave lights itself the darkness
-- has stopped being the thing the game is about.
--
-- Called once per expedition from server/RunOrchestrator, which is the one place a run learns which
-- cave it is. Anything else a family needs chosen ONCE rather than per floor belongs at that call
-- site too; per-floor flavour belongs in FloorBuilder's resolved palette instead.
function EnvironmentSetup.applyCaveFamily(atmosphereColor: Color3, atmosphereDecay: Color3)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere == nil then
		return
	end
	atmosphere.Color = atmosphereColor
	atmosphere.Decay = atmosphereDecay
end

return EnvironmentSetup
