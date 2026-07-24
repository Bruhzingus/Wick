--!strict
-- Relight prompts belong to a snuffed candle but are only actionable by another player. Roblox
-- displays server-created prompts to every nearby client, so hide an owner's impossible prompt
-- locally while leaving the exact same prompt visible to teammates.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local RelightPromptController = {}

local player = Players.LocalPlayer
local TARGET_ATTRIBUTE = "WickRelightTargetId"

local function hideIfOwner(prompt: ProximityPrompt)
	if prompt:GetAttribute(TARGET_ATTRIBUTE) == player.UserId then
		-- This property write is local to the prompt's owner client; the server-created prompt
		-- remains enabled for every teammate and server-side validation remains authoritative.
		prompt.Enabled = false
	end
end

function RelightPromptController.start()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		hideIfOwner(prompt)
	end)
end

return RelightPromptController
