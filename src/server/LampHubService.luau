--!strict
-- USING a lit Lamp Network machine, as opposed to buying one. ShopService owns the money; this owns
-- what a fixture DOES once its lamp is burning.
--
-- WHY THIS IS ITS OWN FILE. The whole point of the track is that a purchase turns a dead prop into a
-- working machine, so every fixture's prompt has two lives: a purchase point, then a machine. Letting
-- each node's hub behaviour leak into ShopService would make the purchase path — the one place real
-- currency moves — grow a branch per node, which is exactly how a payment path stops being auditable.
-- ShopService therefore never learns what a node is for, and this file never moves currency.
--
-- EVERY REPLY IS A TOAST through the lobby's own status line, the same surface the shop stall uses.
-- There is no menu, no board UI, and no client state: a machine is a prompt you hold and a line of
-- text you read back.
--
-- The two machines that take a CHOICE (the contract board, the wager board) work by cycling. Each
-- press advances to the next option and selects it immediately, so a player sets what they want by
-- pressing until the toast reads what they want. That is deliberately the least capable interaction
-- that can express a choice — anything richer would be the menu this design refuses to build.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local LampRules = require(ReplicatedStorage.Shared.Logic.LampRules)

local LampHubService = {}

type Notifier = (player: Player, message: string) -> ()
type PartySizeProvider = () -> number

local notify: Notifier? = nil
local partySizeProvider: PartySizeProvider? = nil

local function tell(player: Player, message: string)
	local notifier = notify
	if notifier ~= nil then
		notifier(player, message)
	end
end

local function partySize(): number
	local provider = partySizeProvider
	return if provider ~= nil then math.max(1, provider()) else 1
end

--------------------------------------------------------------------------------
-- N1 — The Pay Table
--------------------------------------------------------------------------------

-- Reads back the last extraction, and the value curve for the cave the player is nearest. Pure
-- display: it reads a profile field written by ExtractionService and decides nothing.
local function readPayTable(player: Player)
	local profile = Interfaces.Persistence.get(player.UserId)
	local last = profile.lastRunBreakdown
	if last == nil then
		tell(player, "The Pay Table is blank. Walk a bag of Raw Wax out of a cave and it will have something to say.")
		return
	end

	local parts = {
		string.format("%d units", last.units),
		string.format("worth %d before scaling", last.baseValue),
		string.format("cave x%.2f", last.cavePayoutPermille / 1000),
	}
	if last.contractPermille > 1000 then
		table.insert(parts, string.format("contract x%.2f", last.contractPermille / 1000))
	end
	if last.partyBonusPermille > 1000 then
		table.insert(parts, string.format("everyone came back x%.2f", last.partyBonusPermille / 1000))
	end
	table.insert(parts, string.format("PAID %d", last.total))
	tell(player, "Last run: " .. table.concat(parts, "  |  "))
end

--------------------------------------------------------------------------------
-- N2 / N8 — The Contract Board
--------------------------------------------------------------------------------

-- Advance to the next contract this player may sign and sign it. Wraps past the end to "none", so
-- backing out is always the same gesture as choosing — press until the board is clear.
local function cycleContract(player: Player)
	local playerId = player.UserId
	if not LampRules.contractsEnabled() then
		-- The contract layer is rolled back (Config/LampNetwork.contracts.enabled). Say so plainly
		-- rather than implying the player has failed some condition they could fix.
		tell(player, "The board is bare. Nothing is being offered here yet.")
		return
	end
	local available = Interfaces.LampNetwork.availableContracts(playerId, partySize())
	if #available == 0 then
		tell(player, "Nothing on the board you can sign for a party this size.")
		return
	end

	local current = Interfaces.Persistence.get(playerId).activeContractId
	local index = 0
	if current ~= nil then
		for position, contract in available do
			if contract.id == current then
				index = position
				break
			end
		end
	end

	-- Past the last row is deliberately "no contract" rather than looping straight back to the first:
	-- a player must always be able to reach the state where they have signed nothing.
	local nextIndex = index + 1
	if nextIndex > #available then
		Interfaces.LampNetwork.clearPending(playerId)
		tell(player, "Contract torn up. You descend under no agreement.")
		return
	end

	local contract = available[nextIndex]
	local result = Interfaces.LampNetwork.acceptContract(playerId, contract.id, partySize())
	if not result.ok then
		if result.failure == "PartyTooSmall" then
			tell(player, string.format("%s needs someone to go down with you.", contract.displayName))
		elseif result.failure == "ProfileNotLoaded" then
			tell(player, "Your profile is still loading. Try again in a moment.")
		else
			tell(player, "That contract could not be signed.")
		end
		return
	end
	tell(
		player,
		string.format(
			"SIGNED — %s (x%.2f). %s   [hold again for the next one]",
			contract.displayName,
			contract.payoutPermille / 1000,
			contract.rule
		)
	)
end

--------------------------------------------------------------------------------
-- N9 — The Wager Board
--------------------------------------------------------------------------------

-- Each press deepens the named target by one, starting at the shallowest legal bet — which is always
-- one floor deeper than this player has ever actually reached, so there is no such thing as a safe
-- wager. Wraps back to "no wager" a few steps past the minimum, so a player can always stand down.
local WAGER_STEPS = 8

local function cycleWager(player: Player)
	local playerId = player.UserId
	local minimum = Interfaces.LampNetwork.minimumWagerTarget(playerId)
	local current = Interfaces.Persistence.get(playerId).activeWagerDepth

	local target: number
	if current == nil or current < minimum then
		target = minimum
	elseif current >= minimum + WAGER_STEPS then
		Interfaces.LampNetwork.clearPending(playerId)
		tell(player, "Wager withdrawn. You descend owing nobody a number.")
		return
	else
		target = current + 1
	end

	local result = Interfaces.LampNetwork.acceptWager(playerId, target)
	if not result.ok then
		if result.failure == "ProfileNotLoaded" then
			tell(player, "Your profile is still loading. Try again in a moment.")
		else
			tell(player, "That wager could not be placed.")
		end
		return
	end
	tell(
		player,
		string.format(
			"WAGERED — mine at floor %d or deeper and everything pays x%.2f. Miss it and it pays nothing."
				.. "   [hold again to go deeper]",
			target,
			LampRules.wagerPermilleFor(target) / 1000
		)
	)
end

--------------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------------

-- What a lit fixture says when its prompt is held and its real effect lives down in the cave. A
-- prompt that answers with silence reads as broken, so every fixture answers something.
--
-- These read as PROMISES, and each one is gated by its own rollback flag in Config/LampNetwork. A
-- node whose layer is switched off says so instead, via `dormantReply` below — telling a player their
-- Twin Seams are cut into the rock while `depositRows.enabled` is false would be a lie the game
-- itself tells them.
local IN_CAVE_REPLIES: { [string]: string } = {
	["lamp.twin_seam"] = "Twin Seams are cut into the rock now. Take someone with you.",
	["lamp.signal_bell"] = "Your bell is on your belt. Ring it below and your party will hear it — so will the cave.",
	["lamp.deep_seam"] = "Deep Seams appear from floor 6 down. Nine strikes, and you cannot move while you make them.",
	["lamp.bright_seam"] = "Bright Seams only give at full burn. You will be the brightest thing down there.",
	["lamp.locked_store"] = "Locked Stores are sealed behind the vines from floor 5. Burn one open and take what is inside.",
}

-- Whether the layer a node belongs to is currently switched on comes from `LampRules.nodeIsLive`,
-- which reads the `layer` field on the config row. This used to be an if-chain of node ids here, and
-- that was a second copy of a mapping the config already owns — the kind of duplication that stays
-- correct exactly until somebody adds a node and updates only one of them.

-- True if this node's prompt was handled as a MACHINE. False means the player does not own it yet and
-- the caller should treat the press as a purchase attempt instead.
function LampHubService.use(player: Player, nodeId: string): boolean
	if not LampRules.isEnabled() then
		return false
	end
	if not Interfaces.LampNetwork.owns(player.UserId, nodeId) then
		return false
	end

	if nodeId == "lamp.pay_table" then
		readPayTable(player)
	elseif nodeId == "lamp.contract_board" or nodeId == "lamp.hard_contracts" then
		-- Both boards drive the same list; the hard rows simply become available on the same cycle.
		cycleContract(player)
	elseif nodeId == Config.LampNetwork.wager.unlockNode then
		cycleWager(player)
	elseif not LampRules.nodeIsLive(nodeId) then
		tell(player, "That lamp is lit, but its machinery is not running yet. Nothing has changed below.")
	else
		tell(player, IN_CAVE_REPLIES[nodeId] or "That lamp is lit. Its work is done below.")
	end
	return true
end

-- `onNotify` routes replies through whatever surface the lobby uses, and `onPartySize` answers how
-- many people are currently going down — both injected so this service never learns how the lobby
-- talks to clients or how a party is stored.
function LampHubService.init(onNotify: Notifier, onPartySize: PartySizeProvider)
	notify = onNotify
	partySizeProvider = onPartySize
end

-- A player who leaves the hub mid-decision keeps whatever they signed; there is deliberately no
-- per-player state here to clear. Present so the service matches the lifecycle shape of its
-- neighbours, and so a future machine that does hold state has an obvious place to release it.
function LampHubService.clear(_playerId: Types.PlayerId) end

return LampHubService
