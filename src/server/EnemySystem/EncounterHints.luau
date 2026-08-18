--!strict
-- First-sighting hints for the wick-pack enemies (WaxGrub, StoneGnawer, Longarm, GrubQueen): the
-- first time a player is attacked by one — or, for the Queen, first comes within range of her, since
-- she has no attack of her own — a short on-screen line explains what it does and how to counter it.
-- Fired once per player, ever.
--
-- ROUTED THROUGH `itemHints`, NOT `tutorialHints` (Config/Feel.luau). `HintController.resolve()`
-- treats `itemHints` as `oneShot` and exempt from `tutorialHints.maxDepth` (3); these four creatures
-- are all mid-to-late-game and would never appear inside that cap, so a `tutorialHints` row would be
-- claimed server-side and then silently dropped on the client every time. See the comment on
-- `AshamedLurker` in Config/Feel.luau for the same mistake already made once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local EncounterHints = {}

-- `hintId` must have a row in `Config.Feel.itemHints.messages`. Safe to call on every hit/tick —
-- `claimFirstSighting` is a test-and-set on the profile, so only the first call for a given
-- (player, hintId) ever actually reaches the client.
function EncounterHints.announce(playerId: Types.PlayerId, hintId: string)
	if not Config.Feel.itemHints.enabled or Config.Feel.itemHints.messages[hintId] == nil then
		return
	end
	local player = Players:GetPlayerByUserId(playerId)
	if player == nil then
		return
	end
	if Interfaces.Persistence.claimFirstSighting(playerId, "encounter." .. hintId) then
		Remotes.get("TutorialHint"):FireClient(player, hintId)
	end
end

return EncounterHints
