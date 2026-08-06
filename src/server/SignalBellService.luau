--!strict
-- THE SIGNAL BELL (Config/LampNetwork.bell, LAMP-NETWORK.md N4). Server authority over ringing: who
-- may, what it costs, how often, and who hears it.
--
-- WHAT THIS NODE IS, and why it is a sound rather than a light. Getting separated in near-total
-- darkness is a feature — DESIGN §19 risk 5 watches for players getting lost rather than scared — so a
-- through-rock LIGHT would have solved the darkness the whole game is built on. A through-rock SOUND
-- solves separation only: you learn a bearing to your friend and nothing else about the room.
--
-- IT IS A TRADE, NOT A TOOL. Three prices, all server-owned:
--   * wax, because every cost in this game is paid in wax (DESIGN pillar 3);
--   * a cooldown, so it can never become a continuous position broadcast — which would quietly turn it
--     back into the beacon this design rejected;
--   * NOISE. The ring feeds the same field a fumbled pickaxe strike feeds (Logic/SoundField), so
--     dark-hunters come and look. Being findable and being found are the same act.
--
-- The bell is NOT a tool: it has no Config/Tools row, no hotbar slot, and no threat interaction. It
-- makes a noise and spends wax. Nothing here can repel, damage, or distract anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local LampRules = require(ReplicatedStorage.Shared.Logic.LampRules)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local EchoGateService = require(script.Parent.EchoGateService)
local NoiseService = require(script.Parent.NoiseService)
local DevTestSessionRegistry = require(script.Parent.DevTestSessionRegistry)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)

local SignalBellService = {}

-- The node whose purchase grants the bell. Read from the layer's own config rather than hardcoded, so
-- renaming the node cannot leave this pointing at nothing.
local BELL_NODE = "lamp.signal_bell"

-- os.clock() each player's next ring is allowed at. Server-side and authoritative; the client's own
-- cooldown is presentation only and is never trusted.
local nextRingAt: { [Types.PlayerId]: number } = {}

-- Everyone who should HEAR this ring: every other member of the expedition who is still in it.
--
-- The ringer is excluded — they already know where they are, and playing the bell back at them would
-- double the sound at its own source. A snuffed or burned-out player still hears it: being told where
-- the living are is exactly what a body on the floor wants, and it costs the ringer nothing extra.
local function listenersFor(ringerId: Types.PlayerId): { Player }
	local listeners: { Player } = {}
	for playerId in PlayerState.all() do
		if playerId == ringerId or DevTestSessionRegistry.isProtected(playerId) then
			continue
		end
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil then
			table.insert(listeners, player)
		end
	end
	return listeners
end

function SignalBellService.ring(player: Player): boolean
	local playerId = player.UserId
	local bell = Config.LampNetwork.bell
	-- Lab candles are deliberately isolated from expedition-wide communication and retain no bell
	-- cooldown after returning to the Landing.
	if DevTestSessionRegistry.isProtected(playerId) or not LampRules.isEnabled() or not bell.enabled then
		return false
	end
	-- Ownership is re-read server-side on every ring. A client that never bought the node cannot ring
	-- by asking nicely, and one that bought it and had the layer rolled back stops being able to.
	if not Interfaces.LampNetwork.owns(playerId, BELL_NODE) then
		return false
	end

	local state = PlayerState.get(playerId)
	-- A snuffed or burned-out candle cannot ring: the bell is on a belt, and there is nobody holding
	-- it up. This is also what stops a body from broadcasting its own position forever.
	if state == nil or not state.alive or state.finished or state.snuffedAt ~= nil then
		return false
	end

	local now = os.clock()
	if now < (nextRingAt[playerId] or 0) then
		return false
	end

	-- WAX FIRST, and only ring if it was actually paid. Routed through WaxAccounting with its own
	-- ledger source like every other wax movement, so the run summary can say what the bell cost
	-- rather than leaving an unattributed drain in it.
	--
	-- A candle too low to afford the cost simply cannot ring. Deliberately not clamped to whatever is
	-- left: a bell you can ring at 0.001 wax is a bell with no cost, and the cost is the point.
	if state.wax.current <= bell.waxCost then
		return false
	end
	local newWax, paid, spent = WaxAccounting.spend(state.wax, state.waxLedger, bell.waxCost, "SignalBellCost")
	if not paid or spent <= 0 then
		return false
	end
	state.wax = newWax
	nextRingAt[playerId] = now + math.max(bell.cooldownSeconds, 0)

	-- THE PRICE THE CAVE COLLECTS. Emitted at the ringer's position, into the same field every other
	-- noise in the game lands in, so nothing about the bell is invisible to the dark.
	NoiseService.emit("SignalBell", state.position, playerId)

	-- WHAT ELSE HEARD IT. An Echo Lock within range on this floor lifts, which is the only mechanical
	-- effect a ring has on the cave and the only reason the two nodes are bought in sequence.
	--
	-- Deliberately AFTER the wax and the noise, and deliberately not a condition of either: a ring
	-- beside no gate costs exactly the same and is heard by exactly the same things. The bell is never
	-- refunded for missing, or it would stop being a call and start being a key.
	local gatesOpened = EchoGateService.ringAt(state.depth, state.position)

	-- The cue itself. Position is sent because the SOUND is what carries through rock — the client
	-- plays it spatially from there, and the accompanying ripple is occluded by geometry like any
	-- other object, so a player without line of sight gets a bearing and nothing more.
	local payload = {
		ringerId = playerId,
		position = state.position,
		at = Workspace:GetServerTimeNow(),
		rippleSeconds = bell.rippleSeconds,
	}
	for _, listener in listenersFor(playerId) do
		Remotes.get("RunEvent"):FireClient(listener, "bellRing", payload)
	end
	-- The ringer gets their own confirmation, flagged so their client can skip the spatial playback and
	-- just show the ripple at their feet and the wax tick.
	Remotes.get("RunEvent"):FireClient(player, "bellRing", {
		ringerId = playerId,
		position = state.position,
		at = payload.at,
		rippleSeconds = bell.rippleSeconds,
		isSelf = true,
		waxSpent = spent,
	})

	Telemetry.event("bell_rung", playerId, {
		depth = state.depth,
		waxSpent = spent,
		listeners = #listenersFor(playerId),
		gatesOpened = gatesOpened,
	})
	return true
end

function SignalBellService.init()
	Remotes.get("BellRing").OnServerEvent:Connect(function(player: Player)
		if not RequestGuard.allow(player, "BellRing") then
			return
		end
		-- No payload at all, deliberately: there is nothing about a ring a client could usefully claim.
		-- Position comes from the server's own sampled state, so a bell can never be rung from a place
		-- its owner is not standing.
		SignalBellService.ring(player)
	end)
end

function SignalBellService.clear(playerId: Types.PlayerId)
	nextRingAt[playerId] = nil
end

function SignalBellService.reset()
	table.clear(nextRingAt)
end

return SignalBellService
