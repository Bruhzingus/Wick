--!strict
-- Lightweight structured prototype telemetry. It intentionally writes server logs only; swapping
-- to AnalyticsService later stays isolated here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Telemetry = {}

-- Replicated loading diagnostics for the bodyless reserved-server handoff. ReplicatedFirst cannot
-- read server Output, so it reports these two attributes through its existing client-side stall
-- warning. This changes no loading decision and carries no player data.
function Telemetry.loadingStage(stage: string)
	Workspace:SetAttribute("WickLoadingStage", stage)
	Workspace:SetAttribute("WickLoadingStageSince", Workspace:GetServerTimeNow())
	Telemetry.event("loading_stage", nil, { stage = stage })
end

function Telemetry.event(name: string, playerId: number?, fields: { [string]: unknown }?)
	if not Config.Security.telemetryEnabled then
		return
	end
	local segments = { "[WICK]", name }
	if playerId ~= nil then
		table.insert(segments, "player=" .. tostring(playerId))
	end
	if fields ~= nil then
		local keys = {}
		for key in fields do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			table.insert(segments, key .. "=" .. tostring(fields[key]))
		end
	end
	print(table.concat(segments, " "))
end

return Telemetry
