--!strict
-- Enforces the Lamp Network contract rules that can only be judged WHILE a run is happening.
--
-- Most contracts need nothing here. Removing a tool, shrinking a candle and sealing the Basin are all
-- decided once, at the moment the run is built or the room is entered, and live in PlayerState and
-- BasinService respectively. Exactly one rule — Tethered — is a continuous fact about where people
-- are standing, and this file exists so that fact has one owner rather than being sampled from
-- whichever service happened to be looping over players already.
--
-- IT DECIDES NOTHING ABOUT MONEY. When a rule is broken it calls ExtractionService.voidContract and
-- stops; what a voided contract is worth is the extraction path's business. That keeps the payout
-- arithmetic reading from one place regardless of how a contract was lost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ContractRules = require(ReplicatedStorage.Shared.Logic.ContractRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local ExtractionService = require(script.Parent.ExtractionService)

local ContractWatchService = {}

-- How long each player has been continuously further from their nearest living teammate than their
-- contract permits. Reset to zero the instant they are back in range, so the grace period measures
-- one unbroken separation rather than a total across the run — stepping apart repeatedly is normal
-- play, and only genuinely leaving somebody behind should cost the contract.
local separatedFor: { [Types.PlayerId]: number } = {}
-- Players already warned about their current separation, so the warning fires on the way out and not
-- once per frame for as long as it lasts.
local warned: { [Types.PlayerId]: boolean } = {}

local function tell(playerId: Types.PlayerId, text: string)
	local Players = game:GetService("Players")
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = text })
	end
end

-- Distance to the nearest OTHER living, unfinished runner. Returns nil when there is nobody to be
-- near — a solo survivor cannot break a tether, and neither can the last player standing after their
-- party is gone. Punishing somebody for being alone when the alternative was taken away from them
-- would make the contract a lottery on other people's mistakes rather than on their own care.
local function distanceToNearestTeammate(state: Types.PlayerRunState): number?
	local nearest: number? = nil
	for otherId, other in PlayerState.all() do
		if otherId == state.playerId or not other.alive or other.finished then
			continue
		end
		local delta = other.position - state.position
		local distance = delta.Magnitude
		if nearest == nil or distance < nearest then
			nearest = distance
		end
	end
	return nearest
end

function ContractWatchService.tick(dt: number)
	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished then
			separatedFor[playerId] = nil
			warned[playerId] = nil
			continue
		end

		local effect = ContractRules.effectFor(ExtractionService.contractFor(playerId))
		if effect.tetherStuds <= 0 then
			continue
		end

		local nearest = distanceToNearestTeammate(state)
		if nearest == nil or nearest <= effect.tetherStuds then
			if warned[playerId] then
				tell(playerId, "Back in reach. The rope holds.")
			end
			separatedFor[playerId] = nil
			warned[playerId] = nil
			continue
		end

		local elapsed = (separatedFor[playerId] or 0) + dt
		separatedFor[playerId] = elapsed

		-- Warn once, on the way out, while there is still time to walk back. A rule that only ever
		-- announces itself by taking something away is a rule players learn by losing runs to it.
		if not warned[playerId] and effect.tetherGraceSeconds > 0 then
			warned[playerId] = true
			tell(playerId, string.format("Too far from your party. %d seconds.", math.ceil(effect.tetherGraceSeconds)))
		end

		if ContractRules.tetherIsBroken(effect, elapsed) then
			separatedFor[playerId] = nil
			warned[playerId] = nil
			ExtractionService.voidContract(playerId, "Tether")
			tell(playerId, "The rope is cut. Your contract pays nothing now.")
		end
	end

	-- Anybody who left the run entirely stops being tracked, so a rejoining player is never resumed
	-- mid-violation against a timer they cannot see.
	for playerId in separatedFor do
		if PlayerState.get(playerId) == nil then
			separatedFor[playerId] = nil
			warned[playerId] = nil
		end
	end
end

function ContractWatchService.reset()
	table.clear(separatedFor)
	table.clear(warned)
end

return ContractWatchService
