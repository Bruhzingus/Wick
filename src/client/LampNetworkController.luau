--!strict
-- Lights the Lamp Network housings THIS player owns, and nobody else's.
--
-- WHY THIS EXISTS AS A CLIENT CONTROLLER AT ALL. Lamp ownership is per-player, but The Landing is one
-- shared room: four players standing at the same conduit own four different sets of nodes, so there
-- is no single correct lit state a server could replicate. The server therefore builds every housing
-- dark (server/LobbyRoomBuilder) and each client lights its own. This is diegetic hub geometry, not
-- an interface — there is no menu here, no board, and no input. The only thing a player can do to a
-- lamp is walk up to its ProximityPrompt and hold it.
--
-- It reads ownership off the ordinary LobbyState payload rather than a remote of its own, because
-- that payload is already per-recipient and is already re-sent on every purchase.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local LampNetworkController = {}
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

-- The node ids this client's own player owns. Empty until the first LobbyState arrives, which is the
-- correct starting point: unlit is the truthful state for a profile nobody has read yet.
local owned: { [string]: boolean } = {}
local housings: { [BasePart]: boolean } = {}
local started = false

local function applyTo(housing: BasePart, lit: boolean)
	local room = Config.LobbyRoom
	local flame = housing:FindFirstChild("LampFlame") :: BasePart?
	local light = housing:FindFirstChild("LampLight") :: PointLight?
	if flame ~= nil then
		flame.Transparency = if lit then 0 else 1
	end
	if light ~= nil then
		light.Enabled = lit
	end
	-- The housing itself warms when its lamp catches. Cheap, and it is what makes the unlit remainder
	-- of the line legible from across the room rather than only up close.
	housing.Color = if lit then room.lampHousingLitColor else room.lampHousingColdColor
end

local function addHousing(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local housing = instance :: BasePart
	housings[housing] = true
	local nodeId = housing:GetAttribute(LobbyVisualProtocol.attributes.lampNodeId)
	if typeof(nodeId) == "string" then
		applyTo(housing, owned[nodeId] == true)
	end
end

local function removeHousing(instance: Instance)
	if instance:IsA("BasePart") then
		housings[instance :: BasePart] = nil
	end
end

local function refreshAll()
	for housing in housings do
		local nodeId = housing:GetAttribute(LobbyVisualProtocol.attributes.lampNodeId)
		if typeof(nodeId) == "string" then
			applyTo(housing, owned[nodeId] == true)
		end
	end
end

function LampNetworkController.start()
	if started then
		return
	end
	started = true

	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: any })
		-- `any` is confined to this untyped RemoteEvent boundary; the list is checked before use.
		local list = state.ownedLampNodes
		if typeof(list) ~= "table" then
			return
		end
		table.clear(owned)
		for _, nodeId in list do
			if typeof(nodeId) == "string" then
				owned[nodeId] = true
			end
		end
		refreshAll()
	end)

	-- A housing can be tagged after the first state arrives (the client may load before the hub
	-- finishes building), so late arrivals adopt the ownership already known rather than staying dark
	-- until the next purchase.
	CollectionService:GetInstanceAddedSignal(LobbyVisualProtocol.lampHousingTag):Connect(addHousing)
	CollectionService:GetInstanceRemovedSignal(LobbyVisualProtocol.lampHousingTag):Connect(removeHousing)
	for _, instance in CollectionService:GetTagged(LobbyVisualProtocol.lampHousingTag) do
		addHousing(instance)
	end

	local room = Config.LobbyRoom
	RunService.RenderStepped:Connect(function()
		local player = Players.LocalPlayer
		if player == nil or player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
			return
		end
		-- Only lit lamps are touched, so an unowned line costs a cached table walk and nothing else.
		local now = os.clock()
		for housing in housings do
			local nodeId = housing:GetAttribute(LobbyVisualProtocol.attributes.lampNodeId)
			if typeof(nodeId) ~= "string" or owned[nodeId] ~= true then
				continue
			end
			local light = housing:FindFirstChild("LampLight") :: PointLight?
			if light == nil then
				continue
			end
			-- Phase-shifted by the housing's own position so neighbouring lamps are never in step,
			-- without any per-lamp state to keep.
			local phase = housing.Position.Z * 0.37
			local wave = math.sin(now * room.lampFlickerHz * math.pi * 2 + phase)
			light.Brightness = room.lampLitBrightness * (1 + room.lampFlickerDepth * wave)
		end
	end)

	-- Ask for the state we may already have missed. LobbyController sends its own "sync" on start,
	-- but controller start order is not a contract, so this one does not depend on that one.
	if Players.LocalPlayer ~= nil then
		Remotes.get("LobbyAction"):FireServer("sync")
	end
end

return LampNetworkController
