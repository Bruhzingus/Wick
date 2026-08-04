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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)

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

-- THE AIR OF THIS CAVE: retunes the one global Atmosphere (default.project.json's WickAtmosphere) to
-- this family's colour, decay, density, haze and glare. Ambient stays pinned at black by apply()
-- above; Atmosphere is the only global left, which is what makes this the cheapest and most visible
-- per-family identity in the game — five property writes, no new instance, and it reverts by passing
-- another family's id.
--
-- IT USED TO BE COLOUR AND DECAY ONLY, and that was the largest remaining hole in cave identity: all
-- three families breathed identical air, so a flame reached exactly as far in Moss's choked wet warren
-- as in Ice's open glacier halls and the difference between the caves was a gel over the same space.
-- Density is what a player actually feels, because how far your light reaches IS how big the world
-- feels when light is the only thing showing you any of it.
--
-- WHAT IT MAY NOT DO: emit anything, or thin the dark. ART-BIBLE §4 still holds in every family — the
-- fog takes the family's hue but never its own brightness — and `CaveFamilyRules.atmosphere` clamps
-- density above a shared floor so no family can make an unlit room legible. A family changes how far
-- your flame carries. It never changes whether you need one.
--
-- Called once per expedition from server/RunOrchestrator, which is the one place a run learns which
-- cave it is. Anything else a family needs chosen ONCE rather than per floor belongs at that call
-- site too; per-floor flavour belongs in FloorBuilder's resolved palette instead.
function EnvironmentSetup.applyCaveFamily(familyId: string?)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere == nil then
		return
	end
	local settings = CaveFamilyRules.atmosphere(familyId)
	atmosphere.Color = settings.color
	atmosphere.Decay = settings.decay
	-- DENSITY IS THE ONE A PLAYER ACTUALLY FEELS. It decides how far the candle reaches before the dark
	-- closes, which in a game where light is the only source of visual information is the same question
	-- as how big the cave feels. Moss is the thickest air and Ice the thinnest, and the resolver clamps
	-- both above a shared floor so no family can thin the air enough to make an unlit room legible.
	atmosphere.Density = settings.density
	-- Haze is depth: how much distant geometry washes toward the atmosphere colour instead of ending at
	-- a hard edge into black. It is what gives Ice's long halls a readable far end.
	atmosphere.Haze = settings.haze
	-- Glare is the small bloom around a light — moisture in Moss, ice crystals in Ice. Stone has none.
	-- It is the only one of the three that touches the flame itself rather than the space around it.
	atmosphere.Glare = settings.glare
end

return EnvironmentSetup
