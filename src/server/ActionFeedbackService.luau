--!strict
-- Converts server-owned action cooldown state into immediate, synchronized client feedback.
-- StateSync remains the recovery/reconciliation path; this adapter only removes visible latency
-- and prevents rejected requests from looking successful.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local CooldownRules = require(ReplicatedStorage.Shared.Logic.CooldownRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local ActionFeedbackService = {}

function ActionFeedbackService.send(
	player: Player,
	state: Types.PlayerRunState,
	actionId: string,
	accepted: boolean,
	now: number,
	reason: string?
)
	local status = CooldownRules.forAction(state, actionId, now)
	local remaining = if status ~= nil then status.remaining else 0
	local duration = if status ~= nil then status.duration else 0
	Remotes.get("ActionFeedback")
		:FireClient(player, actionId, accepted, Workspace:GetServerTimeNow() + remaining, duration, reason)
end

return ActionFeedbackService
