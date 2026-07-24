--!strict
-- Lightweight structured prototype telemetry. It intentionally writes server logs only; swapping
-- to AnalyticsService later stays isolated here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Telemetry = {}

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
