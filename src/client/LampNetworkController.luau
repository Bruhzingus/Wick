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

-- The node ids this client's own player owns. Empty until the first LobbyState arrives, which is the
-- correct starting point: unlit is the truthful state for a profile nobody has read yet.
local owned: { [string]: boolean } = {}
local started = false

-- A lit housing breathes rather than sitting at a fixed brightness, so the line reads as nine small
-- flames rather than nine indicator LEDs. Deterministic from the housing's own position so every
-- lamp is slightly out of phase with its neighbours without needing any per-lamp state.
local FLICKER_HZ = 1.7
local FLICKER_DEPTH = 0.14

local function applyTo(housing: BasePart, lit: boolean)
	local flame = housing:FindFirstChild("LampFlame") :: BasePart?
	local light = housing:FindFirstChild("LampLight") :: PointLight?
	if flame ~= nil then
		flame.Transparency = if lit then 0 else 1
	end
	if light ~= nil then
		light.Enabled = lit
	end
	-- The housing itself warms slightly when its lamp catches: cold iron when dead, iron with a
	-- fire in it when lit. Cheap, and it is what makes the unlit remainder of the line legible from
	-- across the room rather than only up close.
	housing.Color = if lit then Color3.fromRGB(96, 82, 66) else Color3.fromRGB(58, 56, 54)
end

local function refreshAll()
	for _, instance in CollectionService:GetTagged(LobbyVisualProtocol.lampHousingTag) do
		local housing = instance :: BasePart
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
	CollectionService:GetInstanceAddedSignal(LobbyVisualProtocol.lampHousingTag):Connect(function(instance)
		local housing = instance :: BasePart
		local nodeId = housing:GetAttribute(LobbyVisualProtocol.attributes.lampNodeId)
		if typeof(nodeId) == "string" then
			applyTo(housing, owned[nodeId] == true)
		end
	end)

	local room = Config.LobbyRoom
	RunService.RenderStepped:Connect(function()
		-- Only lit lamps are touched, so an unowned line costs a tag lookup and nothing else.
		local now = os.clock()
		for _, instance in CollectionService:GetTagged(LobbyVisualProtocol.lampHousingTag) do
			local housing = instance :: BasePart
			local nodeId = housing:GetAttribute(LobbyVisualProtocol.attributes.lampNodeId)
			if typeof(nodeId) ~= "string" or owned[nodeId] ~= true then
				continue
			end
			local light = housing:FindFirstChild("LampLight") :: PointLight?
			if light == nil then
				continue
			end
			local phase = housing.Position.Z * 0.37
			local wave = math.sin(now * FLICKER_HZ * math.pi * 2 + phase)
			light.Brightness = room.lampLitBrightness * (1 + FLICKER_DEPTH * wave)
		end
	end)

	-- Ask for the state we may already have missed. LobbyController sends its own "sync" on start,
	-- but controller start order is not a contract, so this one does not depend on that one.
	if Players.LocalPlayer ~= nil then
		Remotes.get("LobbyAction"):FireServer("sync")
	end
end

return LampNetworkController
