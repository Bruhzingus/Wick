--!strict
-- Prototype lobby and party flow. Live servers teleport ready parties into a reserved copy of
-- this place; Studio starts the same expedition locally because TeleportService is unavailable.

export type LobbyConfig = {
	minimumPlayers: number,
	teleportRetries: number,
	teleportRetryDelaySeconds: number,
	arrivalWaitSeconds: number,
}

local Lobby: LobbyConfig = {
	minimumPlayers = 1,
	teleportRetries = 2,
	-- Pause between a failed reserved-server teleport and the next retry attempt.
	teleportRetryDelaySeconds = 1,
	-- Reserved servers wait briefly for every teleported profile before beginning the countdown.
	arrivalWaitSeconds = 8,
}

return Lobby
