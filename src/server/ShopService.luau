--!strict
-- The only place currency is deliberately SPENT, as opposed to charged automatically at a descent.
-- It sells two kinds of thing:
--
--   * PERMANENT CAVE ACCESS — stop paying a cave's admission every run (Phase 8).
--   * LAMP NETWORK NODES — relight a piece of the abandoned rig (LAMP-NETWORK.md).
--
-- WHAT THIS IS NOT, and must not quietly become: a power shop. Nothing here sells wax, capacity, burn
-- rate, tools, or any other advantage inside the cave. Buying a cave outright changes what a descent
-- COSTS and nothing about how it plays — a player who owns The Deep and a player paying their way in
-- run the identical expedition. A lamp node changes what a cave can CONTAIN and what you may agree
-- to, never how strong your candle is. The moment something on this list makes a candle stronger, the
-- economy has become pay-to-win against itself and the tuning in Config/Extraction stops meaning
-- anything.
--
-- WHY THE VALIDATION LIVES HERE AND NOT IN THE PROMPT: the shop stall is a lobby prop that answers a
-- ProximityPrompt. Prompts are client-triggered, so everything a purchase depends on — what it costs,
-- whether you can afford it, whether you already own it — is re-derived server-side from config and
-- profile at the moment of the click. The client sends an intent and a tier id, and nothing else; it
-- cannot name a price.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)

local ShopService = {}

type Notifier = (player: Player, message: string) -> ()

local notify: Notifier? = nil

-- Purchases already in progress on this server, so a held prompt that fires twice cannot open two
-- charges against one intent. The persistence layer's transaction log is the real guarantee — this is
-- the cheap first line that stops the second attempt before it ever reaches a DataStore.
--
-- Keyed by player AND intent, because the Lamp Network gives one player several prompts standing a
-- few studs apart: a single per-player flag would make buying two nodes in quick succession fail the
-- second one for no reason a player could understand.
local inFlight: { [string]: boolean } = {}

local function flightKey(playerId: Types.PlayerId, intent: string): string
	return string.format("%d|%s", playerId, intent)
end

local function tell(player: Player, message: string)
	local notifier = notify
	if notifier ~= nil then
		notifier(player, message)
	end
end

-- A stable, replay-proof identity for one player's purchase of one tier. Deliberately NOT
-- time-based: if a purchase is somehow attempted twice, both attempts derive the same id and the
-- second is recognised as a replay and charges nothing. A player who legitimately wants to buy a
-- second cave is buying a DIFFERENT tier, which produces a different id.
local function purchaseTransactionId(playerId: Types.PlayerId, tierId: number): string
	return string.format("unlock:%d:%d", playerId, tierId)
end

-- What this player can currently buy, for the lobby to display. Server-derived in full: the client is
-- never told a price it then sends back.
function ShopService.offersFor(playerId: Types.PlayerId): { { [string]: unknown } }
	local offers: { { [string]: unknown } } = {}
	local balance = Interfaces.Persistence.get(playerId).currency
	for _, tier in Interfaces.CaveTiers.list() do
		if tier.permanentUnlockPrice <= 0 then
			continue
		end
		table.insert(offers, {
			tierId = tier.id,
			displayName = tier.displayName,
			price = tier.permanentUnlockPrice,
			entryFee = tier.entryFee,
			owned = Interfaces.CaveTiers.owns(playerId, tier.id),
			affordable = balance >= tier.permanentUnlockPrice,
		})
	end
	return offers
end

function ShopService.purchase(player: Player, tierId: number): boolean
	local playerId = player.UserId
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
	-- A purchase must never land while the profile is still loading: the charge would go into a
	-- fallback cache that is about to be discarded, and the player would have "bought" nothing.
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
	return true
end

--------------------------------------------------------------------------------
-- The Lamp Network
--------------------------------------------------------------------------------

-- A stable, replay-proof identity for one player's purchase of one node. Deliberately NOT
-- time-based, exactly like the cave id above: if a purchase is somehow attempted twice, both
-- attempts derive the same id, the second is recognised as a replay, and it charges nothing. That
-- property is load-bearing — Interfaces.LampNetwork.purchaseNode relies on a repeated attempt being
-- able to finish a grant that a previous one started, which is what makes a refund feature
-- unnecessary rather than merely absent.
local function lampTransactionId(playerId: Types.PlayerId, nodeId: string): string
	return string.format("lamp:%d:%s", playerId, nodeId)
end

-- What this player can currently see on the lamp line, for the hub to display. Fully server-derived:
-- the client is never told a price it then sends back.
function ShopService.lampOffersFor(playerId: Types.PlayerId): { { [string]: unknown } }
	local offers: { { [string]: unknown } } = {}
	if not Interfaces.LampNetwork.isEnabled() then
		return offers
	end
	local balance = Interfaces.Persistence.get(playerId).currency
	for _, node in Interfaces.LampNetwork.list() do
		table.insert(offers, {
			nodeId = node.id,
			displayName = node.displayName,
			promptClause = node.promptClause,
			price = node.cost,
			owned = Interfaces.LampNetwork.owns(playerId, node.id),
			missingNode = Interfaces.LampNetwork.missingPrerequisite(playerId, node.id),
			affordable = balance >= node.cost,
		})
	end
	return offers
end

function ShopService.purchaseLamp(player: Player, nodeId: string): boolean
	local playerId = player.UserId
	local key = flightKey(playerId, "lamp:" .. nodeId)
	if inFlight[key] then
		return false
	end

	-- Ask before acting, so the refusal a player reads names the actual reason rather than a generic
	-- failure. The same validation runs again inside `purchaseNode`; this pass exists only to produce
	-- a good message, and it is never the thing that authorises the charge.
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
			local price = if node ~= nil then node.cost else 0
			tell(player, string.format("%s costs %d Raw Wax. You have %d.", name, price, check.balance))
		elseif check.failure == "ProfileNotLoaded" then
			tell(player, "Your profile is still loading. Try again in a moment.")
		elseif check.failure == "LayerDisabled" then
			-- The node exists and is on the wall, but whatever it drives is not running. Say so plainly
			-- rather than refusing silently: the fixture is deliberately still built and still lit-able
			-- later, so the unlit line keeps showing the shape of the track.
			tell(player, string.format("%s is not ready to be lit. Nothing behind it is running yet.", name))
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
		-- The gap between `canPurchase` above and the charge is not zero (another handler could have
		-- spent this player's balance in between), so a refusal here is real rather than impossible.
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
	return true
end

-- `onNotify` routes player-facing messages back through whatever surface the lobby uses, so this
-- service never has to know how the lobby talks to clients.
function ShopService.init(onNotify: Notifier)
	notify = onNotify
	Remotes.get("LobbyAction").OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		if not RequestGuard.allow(player, "LobbyAction") then
			return
		end
		if action == "buyCave" then
			-- The client supplies a tier id and nothing else. Everything about what that costs is read
			-- server-side from config.
			if not RequestGuard.finiteNumber(value) then
				return
			end
			local tierId = value :: number
			if tierId % 1 ~= 0 then
				return
			end
			ShopService.purchase(player, tierId)
		elseif action == "buyLamp" then
			-- Same contract, different key space: the client names a node id and nothing else. An id
			-- that is not a string, or not a node, is dropped by `purchaseNode`'s own validation rather
			-- than trusted here — but the type check happens first so a table or a NaN never reaches a
			-- string format.
			if typeof(value) ~= "string" or value == "" then
				return
			end
			ShopService.purchaseLamp(player, value :: string)
		end
	end)
end

-- Drops any purchase this player had open. Called when they leave, so a disconnect mid-charge cannot
-- leave a key set that blocks their next session's first purchase.
function ShopService.clear(playerId: Types.PlayerId)
	local prefix = tostring(playerId) .. "|"
	for key in inFlight do
		if string.sub(key, 1, #prefix) == prefix then
			inFlight[key] = nil
		end
	end
end

function ShopService.reset()
	table.clear(inFlight)
end

return ShopService
