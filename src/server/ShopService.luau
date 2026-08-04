--!strict
-- Server-authoritative General Store and Lamp Network boundary. The client may name only an action
-- and an id/depth; prices, prerequisites, party rules, ownership, profile readiness, and every
-- currency movement are re-derived here or in the focused shared interfaces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local LampRules = require(ReplicatedStorage.Shared.Logic.LampRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)

local ShopService = {}

type Notifier = (player: Player, message: string) -> ()
type ChangedNotifier = (status: string?) -> ()
type LobbyClosedProvider = () -> boolean
type PartySizeProvider = () -> number

local notify: Notifier? = nil
local notifyChanged: ChangedNotifier? = nil
local lobbyClosedProvider: LobbyClosedProvider? = nil
local partySizeProvider: PartySizeProvider? = nil

-- A shop session can only be created by the server-owned General Store ProximityPrompt. A modified
-- client therefore cannot open a purchase surface from inside an expedition or across the lobby.
local openSessions: { [Types.PlayerId]: boolean } = {}
local inFlight: { [string]: boolean } = {}
local latestMessage: { [Types.PlayerId]: string } = {}

local function flightKey(playerId: Types.PlayerId, intent: string): string
	return string.format("%d|%s", playerId, intent)
end

local function lobbyIsClosed(): boolean
	local provider = lobbyClosedProvider
	return provider ~= nil and provider()
end

local function partySize(): number
	local provider = partySizeProvider
	return if provider ~= nil then math.max(1, provider()) else 1
end

local function tell(player: Player, message: string)
	latestMessage[player.UserId] = message
	local notifier = notify
	if notifier ~= nil then
		notifier(player, message)
	end
end

local function changed()
	local callback = notifyChanged
	if callback ~= nil then
		callback(nil)
	end
end

local function purchaseTransactionId(playerId: Types.PlayerId, tierId: number): string
	return string.format("unlock:%d:%d", playerId, tierId)
end

local function lampTransactionId(playerId: Types.PlayerId, nodeId: string): string
	return string.format("lamp:%d:%s", playerId, nodeId)
end

--------------------------------------------------------------------------------
-- Server-authored display state
--------------------------------------------------------------------------------

function ShopService.offersFor(playerId: Types.PlayerId): { { [string]: unknown } }
	local offers: { { [string]: unknown } } = {}
	local profile = Interfaces.Persistence.get(playerId)
	local loaded = Interfaces.Persistence.isLoaded(playerId)
	for _, tier in Interfaces.CaveTiers.list() do
		if tier.permanentUnlockPrice <= 0 then
			continue
		end
		local owned = Interfaces.CaveTiers.owns(playerId, tier.id)
		local affordable = profile.currency >= tier.permanentUnlockPrice
		table.insert(offers, {
			tierId = tier.id,
			displayName = tier.displayName,
			description = string.format(
				"Own this cave permanently instead of paying its %d Raw Wax admission each descent.",
				tier.entryFee
			),
			price = tier.permanentUnlockPrice,
			entryFee = tier.entryFee,
			owned = owned,
			affordable = affordable,
			purchasable = loaded and not owned and affordable and not lobbyIsClosed(),
		})
	end
	return offers
end

function ShopService.lampOffersFor(playerId: Types.PlayerId): { { [string]: unknown } }
	local offers: { { [string]: unknown } } = {}
	if not Interfaces.LampNetwork.isEnabled() then
		return offers
	end
	local balance = Interfaces.Persistence.get(playerId).currency
	for _, node in Interfaces.LampNetwork.list() do
		local check = Interfaces.LampNetwork.canPurchase(playerId, node.id)
		table.insert(offers, {
			nodeId = node.id,
			displayName = node.displayName,
			description = node.description,
			promptClause = node.promptClause,
			iconId = node.iconId,
			treeColumn = node.treePosition.X,
			treeRow = node.treePosition.Y,
			price = node.cost,
			requires = table.clone(node.requires),
			requiresAny = table.clone(node.requiresAny),
			requiresAnyCount = node.requiresAnyCount,
			owned = Interfaces.LampNetwork.owns(playerId, node.id),
			live = LampRules.nodeIsLive(node.id),
			affordable = balance >= node.cost,
			purchasable = check.ok and not lobbyIsClosed(),
			failure = check.failure,
			missingNode = check.missingNode,
		})
	end
	return offers
end

function ShopService.stateFor(player: Player): { [string]: unknown }
	local playerId = player.UserId
	local profile = Interfaces.Persistence.get(playerId)
	local contracts: { { [string]: unknown } } = {}
	for _, contract in Interfaces.LampNetwork.availableContracts(playerId, partySize()) do
		table.insert(contracts, {
			contractId = contract.id,
			displayName = contract.displayName,
			rule = contract.rule,
			payoutPermille = contract.payoutPermille,
			minPartySize = contract.minPartySize,
			unlockNode = contract.unlockNode,
			selected = profile.activeContractId == contract.id,
		})
	end
	local minimumWager = Interfaces.LampNetwork.minimumWagerTarget(playerId)
	return {
		currency = profile.currency,
		profileLoaded = Interfaces.Persistence.isLoaded(playerId),
		lampOffers = ShopService.lampOffersFor(playerId),
		caveOffers = ShopService.offersFor(playerId),
		contracts = contracts,
		partySize = partySize(),
		activeContractId = profile.activeContractId,
		activeWagerDepth = profile.activeWagerDepth,
		activeAgreement = if profile.activeContractId ~= nil
			then { kind = "contract", contractId = profile.activeContractId }
			elseif profile.activeWagerDepth ~= nil
			then { kind = "wager", depth = profile.activeWagerDepth }
			else nil,
		minimumWagerTarget = minimumWager,
		minimumWagerPermille = LampRules.wagerPermilleFor(minimumWager),
		-- THE PAY TABLE IS GATED HERE, not only in the panel that draws it. The client already hides the
		-- breakdown until the node is owned, but a UI that declines to render something it was sent is a
		-- courtesy, not a gate — the node is the purchase, so the data has to be withheld by the server
		-- that charges for it.
		--
		-- Explicitly `false` rather than absent when there is nothing to show: the client treats a missing
		-- field as "no news" and keeps what it last held, which would leave a stale breakdown on screen
		-- for a player who has not bought the node.
		lastRunBreakdown = if Interfaces.LampNetwork.owns(playerId, "lamp.pay_table")
			then profile.lastRunBreakdown or false
			else false,
	}
end

local function pushState(player: Player, kind: string, result: { [string]: unknown }?)
	local payload = ShopService.stateFor(player)
	payload.kind = kind
	payload.message = latestMessage[player.UserId] or ""
	payload.result = result
	Remotes.get("ShopState"):FireClient(player, payload)
end

function ShopService.open(player: Player)
	if lobbyIsClosed() then
		openSessions[player.UserId] = nil
		Remotes.get("ShopState"):FireClient(player, { kind = "close", message = "The store is closed during a descent." })
		return
	end
	openSessions[player.UserId] = true
	latestMessage[player.UserId] = nil
	pushState(player, "open", nil)
end

--------------------------------------------------------------------------------
-- Permanent purchases
--------------------------------------------------------------------------------

function ShopService.purchase(player: Player, tierId: number): boolean
	local playerId = player.UserId
	if lobbyIsClosed() then
		tell(player, "The store is closed while an expedition is beginning.")
		return false
	end
	local key = flightKey(playerId, "cave:" .. tostring(tierId))
	if inFlight[key] then
		return false
	end
	local tier = Interfaces.CaveTiers.get(tierId)
	if tier == nil then
		return false
	end
	if tier.permanentUnlockPrice <= 0 then
		tell(player, string.format("%s cannot be bought.", tier.displayName))
		return false
	end
	if Interfaces.CaveTiers.owns(playerId, tierId) then
		tell(player, string.format("You already own %s.", tier.displayName))
		return false
	end
	if not Interfaces.Persistence.isLoaded(playerId) then
		tell(player, "Your profile is still loading. Try again in a moment.")
		return false
	end

	inFlight[key] = true
	local result = Interfaces.CaveTiers.purchasePermanent(playerId, tierId, purchaseTransactionId(playerId, tierId))
	inFlight[key] = nil
	Telemetry.event("shop_purchase", playerId, {
		tier = tierId,
		price = tier.permanentUnlockPrice,
		ok = result.ok,
		failure = result.failure,
		balance = result.balance,
	})
	if not result.ok then
		if result.failure == "InsufficientFunds" then
			tell(
				player,
				string.format(
					"%s costs %d Raw Wax. You have %d.",
					tier.displayName,
					tier.permanentUnlockPrice,
					result.balance
				)
			)
		else
			tell(player, "That purchase could not be completed.")
		end
		return false
	end
	tell(player, string.format("%s is yours. You will never pay its toll again.", tier.displayName))
	changed()
	return true
end

function ShopService.purchaseLamp(player: Player, nodeId: string): boolean
	local playerId = player.UserId
	if lobbyIsClosed() then
		tell(player, "The store is closed while an expedition is beginning.")
		return false
	end
	local key = flightKey(playerId, "lamp:" .. nodeId)
	if inFlight[key] then
		return false
	end
	local check = Interfaces.LampNetwork.canPurchase(playerId, nodeId)
	if not check.ok then
		local node = Interfaces.LampNetwork.get(nodeId)
		local name = if node ~= nil then node.displayName else "That"
		if check.failure == "AlreadyOwned" then
			tell(player, string.format("%s is already lit.", name))
		elseif check.failure == "MissingPrerequisite" then
			local blocker = if check.missingNode ~= nil then Interfaces.LampNetwork.get(check.missingNode) else nil
			tell(
				player,
				if blocker ~= nil
					then string.format("Light %s first.", blocker.displayName)
					else string.format("%s is not ready to be lit yet.", name)
			)
		elseif check.failure == "InsufficientFunds" then
			tell(
				player,
				string.format(
					"%s costs %d Raw Wax. You have %d.",
					name,
					if node ~= nil then node.cost else 0,
					check.balance
				)
			)
		elseif check.failure == "ProfileNotLoaded" then
			tell(player, "Your profile is still loading. Try again in a moment.")
		elseif check.failure == "LayerDisabled" then
			tell(player, string.format("%s is dormant while its cave machinery is unavailable.", name))
		elseif check.failure ~= "UnknownNode" and check.failure ~= "Disabled" then
			tell(player, "That purchase could not be completed.")
		end
		return false
	end

	inFlight[key] = true
	local result = Interfaces.LampNetwork.purchaseNode(playerId, nodeId, lampTransactionId(playerId, nodeId))
	inFlight[key] = nil
	local node = Interfaces.LampNetwork.get(nodeId)
	Telemetry.event("lamp_purchase", playerId, {
		node = nodeId,
		price = if node ~= nil then node.cost else 0,
		ok = result.ok,
		failure = result.failure,
		balance = result.balance,
	})
	if not result.ok then
		if result.failure == "InsufficientFunds" then
			tell(
				player,
				string.format(
					"%s costs %d Raw Wax. You have %d.",
					if node ~= nil then node.displayName else "That",
					if node ~= nil then node.cost else 0,
					result.balance
				)
			)
		else
			tell(player, "That purchase could not be completed.")
		end
		return false
	end
	tell(
		player,
		string.format("%s is lit. %d Raw Wax left.", if node ~= nil then node.displayName else "It", result.balance)
	)
	changed()
	return true
end

--------------------------------------------------------------------------------
-- Owned board actions
--------------------------------------------------------------------------------

local function setContract(player: Player, contractId: string): boolean
	local result = Interfaces.LampNetwork.acceptContract(player.UserId, contractId, partySize())
	local contract = Interfaces.LampNetwork.getContract(contractId)
	if not result.ok then
		if result.failure == "PartyTooSmall" and contract ~= nil then
			tell(player, string.format("%s needs a larger party.", contract.displayName))
		elseif result.failure == "Locked" then
			tell(player, "Light the board that carries this contract first.")
		elseif result.failure == "ProfileNotLoaded" then
			tell(player, "Your profile is still loading. Try again in a moment.")
		else
			tell(player, "That contract could not be signed.")
		end
		return false
	end
	tell(
		player,
		string.format(
			"Signed %s — x%.2f if you keep the rule.",
			if contract ~= nil then contract.displayName else "contract",
			if contract ~= nil then contract.payoutPermille / 1000 else 1
		)
	)
	changed()
	return true
end

local function setWager(player: Player, targetDepth: number): boolean
	local result = Interfaces.LampNetwork.acceptWager(player.UserId, targetDepth)
	if not result.ok then
		if result.failure == "TargetTooShallow" then
			tell(
				player,
				string.format(
					"Name floor %d or deeper — a wager must beat your record.",
					Interfaces.LampNetwork.minimumWagerTarget(player.UserId)
				)
			)
		elseif result.failure == "Locked" then
			tell(player, "Light The Wager Board first.")
		elseif result.failure == "ProfileNotLoaded" then
			tell(player, "Your profile is still loading. Try again in a moment.")
		else
			tell(player, "That wager could not be placed.")
		end
		return false
	end
	tell(
		player,
		string.format(
			"Wager set: mine on floor %d or deeper for x%.2f.",
			targetDepth,
			LampRules.wagerPermilleFor(targetDepth) / 1000
		)
	)
	changed()
	return true
end

local function clearAgreement(player: Player): boolean
	if not Interfaces.Persistence.isLoaded(player.UserId) then
		tell(player, "Your profile is still loading. Try again in a moment.")
		return false
	end
	Interfaces.LampNetwork.clearPending(player.UserId)
	tell(player, "Agreement cleared. You descend under no contract or wager.")
	changed()
	return true
end

--------------------------------------------------------------------------------
-- Remote and lifecycle
--------------------------------------------------------------------------------

function ShopService.init(
	onNotify: Notifier,
	onChanged: ChangedNotifier,
	onLobbyClosed: LobbyClosedProvider,
	onPartySize: PartySizeProvider
)
	notify = onNotify
	notifyChanged = onChanged
	lobbyClosedProvider = onLobbyClosed
	partySizeProvider = onPartySize

	Remotes.get("ShopAction").OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		if not RequestGuard.allow(player, "ShopAction") or typeof(action) ~= "string" then
			return
		end
		local actionName = action :: string
		if actionName == "close" then
			openSessions[player.UserId] = nil
			return
		end
		if openSessions[player.UserId] ~= true then
			return
		end
		if lobbyIsClosed() then
			openSessions[player.UserId] = nil
			Remotes.get("ShopState"):FireClient(player, {
				kind = "close",
				message = "The store closed as the expedition began.",
			})
			return
		end

		latestMessage[player.UserId] = nil
		if actionName == "sync" or actionName == "readPayTable" then
			pushState(player, "update", nil)
			return
		end

		local ok = false
		if actionName == "buyCave" and RequestGuard.finiteNumber(value) then
			local tierId = value :: number
			if tierId % 1 == 0 then
				ok = ShopService.purchase(player, tierId)
			end
		elseif actionName == "buyLamp" and typeof(value) == "string" and value ~= "" then
			ok = ShopService.purchaseLamp(player, value :: string)
		elseif actionName == "setContract" and typeof(value) == "string" and value ~= "" then
			ok = setContract(player, value :: string)
		elseif actionName == "setWager" and RequestGuard.finiteNumber(value) then
			local target = value :: number
			if target % 1 == 0 and target >= 1 and target <= 1_000_000 then
				ok = setWager(player, target)
			end
		elseif actionName == "clearAgreement" then
			ok = clearAgreement(player)
		else
			return
		end
		pushState(player, "update", {
			action = actionName,
			ok = ok,
		})
	end)
end

function ShopService.clear(playerId: Types.PlayerId)
	openSessions[playerId] = nil
	latestMessage[playerId] = nil
	local prefix = tostring(playerId) .. "|"
	for key in inFlight do
		if string.sub(key, 1, #prefix) == prefix then
			inFlight[key] = nil
		end
	end
end

function ShopService.reset()
	table.clear(openSessions)
	table.clear(inFlight)
	table.clear(latestMessage)
end

return ShopService
