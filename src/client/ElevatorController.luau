--!strict
-- Renders the timestamped elevator descent locally. The server owns who rides, when the ride
-- starts, its curve inputs, and the final car/body transforms; each client reconstructs the same
-- analytic motion before Roblox's camera step so network replication cadence cannot make it judder.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CameraController = require(script.Parent.CameraController)

local ElevatorController = {}

type RiderVisual = {
	model: Model,
	carSpacePivot: CFrame,
}

type RideVisual = {
	tierId: number,
	riderIds: { number },
	riders: { [number]: RiderVisual },
	startedAt: number,
	duration: number,
	distance: number,
	restPivot: CFrame,
	isLocalRider: boolean,
}

local player = Players.LocalPlayer
local ride: RideVisual? = nil

local function taggedForTier(tag: string, tierId: number): Instance?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:GetAttribute(LobbyVisualProtocol.attributes.tierId) == tierId then
			return instance
		end
	end
	return nil
end

local function carForTier(tierId: number): Model?
	local instance = taggedForTier(LobbyVisualProtocol.carTag, tierId)
	return if instance ~= nil and instance:IsA("Model") then instance else nil
end

local function readoutLabelFor(tierId: number): TextLabel?
	local backing = taggedForTier(LobbyVisualProtocol.readoutTag, tierId)
	if backing == nil then
		return nil
	end
	local gui = backing:FindFirstChildOfClass("SurfaceGui")
	local label = if gui ~= nil then gui:FindFirstChild("Text") else nil
	return if label ~= nil and label:IsA("TextLabel") then label else nil
end

-- Read straight from config data, not Interfaces.CaveTiers: that server-side interface requires
-- persistence modules which cannot be loaded by a client.
local function tierName(tierId: number): string
	for _, tier in Config.CaveTiers do
		if tier.id == tierId then
			return string.upper(tier.displayName)
		end
	end
	return "THE CAVE"
end

local function resetReadouts()
	for _, backing in CollectionService:GetTagged(LobbyVisualProtocol.readoutTag) do
		local tierId = backing:GetAttribute(LobbyVisualProtocol.attributes.tierId)
		if typeof(tierId) == "number" then
			local label = readoutLabelFor(tierId)
			if label ~= nil then
				label.Text = tierName(tierId)
			end
		end
	end
end

local function resetRide()
	ride = nil
	CameraController.setElevatorOffset(Vector3.zero)
	resetReadouts()
end

-- Smoothstep: machinery eases off the brake, travels quickly through the shaft, then settles.
local function rideEase(progress: number): number
	local t = math.clamp(progress, 0, 1)
	return t * t * (3 - 2 * t)
end

local function captureRiderBodies(active: RideVisual)
	for _, playerId in active.riderIds do
		local existing = active.riders[playerId]
		if
			existing ~= nil
			and existing.model.Parent ~= nil
			and existing.model:GetAttribute(LobbyVisualProtocol.attributes.rideBody) == true
		then
			continue
		end
		active.riders[playerId] = nil
		local rider = Players:GetPlayerByUserId(playerId)
		local character = if rider ~= nil then rider.Character else nil
		if
			character ~= nil
			and character.PrimaryPart ~= nil
			and character:GetAttribute(LobbyVisualProtocol.attributes.rideBody) == true
		then
			active.riders[playerId] = {
				model = character,
				-- Keep the rider rigidly car-relative. This is deliberately stored in car space
				-- rather than as another independent world-space path.
				carSpacePivot = active.restPivot:ToObjectSpace(character:GetPivot()),
			}
		end
	end
end

local function applyShake(active: RideVisual, now: number)
	if not active.isLocalRider then
		CameraController.setElevatorOffset(Vector3.zero)
		return
	end
	local remainingFraction = math.clamp((active.startedAt + active.duration - now) / active.duration, 0, 1)
	local intensity = remainingFraction * 0.45 + 0.55
	local phase = now * Config.LobbyRoom.rideShakeHz * math.pi * 2
	local amplitude = Config.LobbyRoom.rideShakeStuds * intensity
	CameraController.setElevatorOffset(
		Vector3.new(math.sin(phase * 1.3) * amplitude, 0, math.cos(phase * 0.7) * amplitude * 0.5)
	)
end

local function renderRide()
	local active = ride
	if active == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local progress = math.clamp((now - active.startedAt) / active.duration, 0, 1)
	local offset = Vector3.new(0, -rideEase(progress) * active.distance, 0)
	local carPivot = active.restPivot + offset

	local car = carForTier(active.tierId)
	if car ~= nil then
		car:PivotTo(carPivot)
	end
	captureRiderBodies(active)
	for _, visual in active.riders do
		visual.model:PivotTo(carPivot * visual.carSpacePivot)
	end

	applyShake(active, now)
	local label = readoutLabelFor(active.tierId)
	if label ~= nil then
		label.Text = string.format(
			"DESCENDING\n%s\n%.0f",
			tierName(active.tierId),
			math.ceil(math.max(active.startedAt + active.duration - now, 0))
		)
	end

	if progress >= 1 then
		resetRide()
	end
end

function ElevatorController.start()
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		-- `any` is confined to this untyped RemoteEvent boundary; fields are validated before use.
		if kind == "elevatorRide" then
			local tierId = tonumber(payload.tierId)
			local startedAt = tonumber(payload.startedAt)
			local duration = tonumber(payload.duration)
			local distance = tonumber(payload.distance)
			local restPivot = payload.restPivot
			if
				tierId == nil
				or startedAt == nil
				or duration == nil
				or duration <= 0
				or distance == nil
				or distance < 0
				or typeof(restPivot) ~= "CFrame"
			then
				return
			end

			local riderIds: { number } = {}
			local rawRiders = payload.riderIds
			if typeof(rawRiders) == "table" then
				for _, rawId in rawRiders do
					if typeof(rawId) == "number" and rawId > 0 and rawId % 1 == 0 then
						table.insert(riderIds, rawId)
					end
				end
			end
			ride = {
				tierId = tierId,
				riderIds = riderIds,
				riders = {},
				startedAt = startedAt,
				duration = duration,
				distance = distance,
				restPivot = restPivot,
				isLocalRider = table.find(riderIds, player.UserId) ~= nil,
			}
			captureRiderBodies(ride :: RideVisual)
		elseif kind == "floor" and payload.depth == 1 then
			resetRide()
		end
	end)

	RunService:BindToRenderStep("WickElevatorRide", Enum.RenderPriority.Camera.Value - 1, renderRide)
end

return ElevatorController
