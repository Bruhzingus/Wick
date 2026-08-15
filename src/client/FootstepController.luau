--!strict
-- YOUR OWN FEET. The local player's footfalls, paced from measured ground speed and voiced by the
-- surface actually underneath them.
--
-- WHY THIS EXISTS. Before it, the player made no sound at all. In a game whose stated design risk is
-- "horror lives on audio, and since you cannot see, hearing does all the work vision can't"
-- (DESIGN §19), the single most frequent event available — a footfall, several times a second, for
-- the whole run — was silence. A first-person body that makes no noise reads as a floating camera
-- rather than as a person standing in a cave, and it also meant all three cave families felt
-- identical to WALK through however different they looked.
--
-- SELF-AUDIBLE ONLY, AND THAT IS A DESIGN DECISION RATHER THAN A SHORTCUT. Nothing here touches
-- server/NoiseService. Config/Sound's emitter list is what the CAVE hears — mining, falling stone,
-- and dynamite — and walking is deliberately not on it. If footsteps were audible to threats,
-- every hearing row would hold a permanent track on every moving player, standing still would become
-- the dominant strategy, and the Cave Listener would stop being the price of working a seam and
-- become an unavoidable tax on existing. The player hears themselves; the cave does not.
--
-- PACED BY SPEED, NOT BY A TIMER. The interval is interpolated between the authored walk and run
-- values from the humanoid's own measured horizontal speed, so Cup-slowed movement is audibly slower
-- underfoot, a sprint is audibly faster, and a body that has stopped is silent. That makes the
-- cadence a readable signal about your own state rather than decoration.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local FootstepController = {}

local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local player = Players.LocalPlayer
local rng = Random.new()
local nextStepAt = 0
-- Which cave this run is in, read from the same "floor" message the ambience director and the camera
-- already bind to. Resolved through CaveFamilyRules, so an absent or unknown id still produces a real
-- surface rather than silence.
local caveFamilyId: string? = nil

local function config()
	return Config.Feel.footsteps
end

local function inExpedition(): boolean
	return player:GetAttribute(EXPEDITION_ATTRIBUTE) == true
end

local function localParts(): (Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid, if root ~= nil and root:IsA("BasePart") then root :: BasePart else nil
end

-- Are we wading? Asked of the Terrain directly rather than of any hazard record, because what a foot
-- lands in is a physical question and the answer has to hold on ground the planner never recorded a
-- pool for — a shallow puddle at the edge of a room, or water a player has walked into from a
-- neighbouring one.
local function standingInWater(root: BasePart): boolean
	local settings = config()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local characters: { Instance } = {}
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		if character ~= nil then
			table.insert(characters, character)
		end
	end
	params.FilterDescendantsInstances = characters

	-- Two probes from the same origin: one that stops at water and one that ignores it. When the water
	-- surface sits more than the threshold above the solid floor beneath it, the foot is IN water. A
	-- single probe cannot answer this — it would report the surface without knowing how deep it is.
	params.IgnoreWater = false
	local wet = Workspace:Raycast(root.Position, -Vector3.yAxis * settings.surfaceProbeDistance, params)
	if wet == nil or wet.Material ~= Enum.Material.Water then
		return false
	end
	params.IgnoreWater = true
	local solid = Workspace:Raycast(root.Position, -Vector3.yAxis * settings.surfaceProbeDistance, params)
	if solid == nil then
		return true
	end
	return wet.Position.Y - solid.Position.Y >= settings.waterDepthThreshold
end

-- Interval and level for the speed we are actually moving at. One `alpha` drives both, so a faster
-- body is heard both more often and more heavily — which is how weight reads in audio.
local function stepProfile(speed: number): (number, number)
	local settings = config()
	local walk = Config.Movement.walkSpeed
	local run = Config.Movement.runSpeed
	local span = math.max(run - walk, 0.001)
	local alpha = math.clamp((speed - walk) / span, 0, 1)
	local interval = settings.walkIntervalSeconds + (settings.runIntervalSeconds - settings.walkIntervalSeconds) * alpha
	local volume = settings.quietVolume + (settings.loudVolume - settings.quietVolume) * alpha
	return interval, volume
end

local function scheduleNext(now: number, interval: number)
	local jitter = math.clamp(config().intervalJitter, 0, 0.9)
	nextStepAt = now + interval * rng:NextNumber(1 - jitter, 1 + jitter)
end

local function step(now: number)
	local humanoid, root = localParts()
	if humanoid == nil or root == nil then
		return
	end
	-- Airborne bodies do not have feet on anything. Reading the humanoid's own floor state rather than
	-- guessing from velocity keeps a jump or a fall silent for exactly as long as it should be.
	if (humanoid :: Humanoid).FloorMaterial == Enum.Material.Air then
		return
	end

	local velocity = (root :: BasePart).AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if speed < config().minimumSpeed then
		-- Standing still is silent, and the next step is armed to land promptly once you move again
		-- rather than waiting out an interval that started while you were stationary.
		nextStepAt = now
		return
	end

	local interval, volume = stepProfile(speed)
	if now < nextStepAt then
		return
	end
	scheduleNext(now, interval)

	local cueName = CaveFamilyRules.footstepCue(caveFamilyId, standingInWater(root :: BasePart))
	-- Played at the ROOT rather than on the head: it is a spatial sound from the floor under you, and
	-- in third-person spectator views it still comes from the body it belongs to.
	AudioCues.playAt(cueName, root :: BasePart, nil, volume)
end

local function floorAnnounced(payload: { [string]: any })
	local declared = payload.familyId
	if type(declared) == "string" and CaveFamilyRules.isValidId(declared) then
		caveFamilyId = declared
		return
	end
	local tierId = tonumber(payload.tierId)
	local fromTier = if tierId ~= nil then CaveFamilyRules.fromLegacyTierId(tierId) else nil
	caveFamilyId = if fromTier ~= nil then fromTier.id else nil
end

function FootstepController.start()
	-- `any` is confined to this untyped RemoteEvent boundary; both fields are validated before use.
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind == "floor" and typeof(payload) == "table" then
			floorAnnounced(payload)
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not config().enabled or not inExpedition() then
			return
		end
		step(os.clock())
	end)
end

return FootstepController
