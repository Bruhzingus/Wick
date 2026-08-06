--!strict
-- Lobby and party flow. Live servers teleport ready parties into a reserved copy of this place;
-- Studio starts the same expedition locally because TeleportService is unavailable.
--
-- THE FLOW THESE NUMBERS PACE, in order: players walk into an elevator car and become a party
-- (Interfaces/Party), each readies up, then once everybody standing in the car is ready the cave
-- vote opens, the tally resolves (Logic/PartyVote), and the car descends. Every step before the
-- descent is reversible by walking out, which is what makes standing in a car safe to do while
-- undecided.

export type LobbyConfig = {
	minimumPlayers: number,
	teleportRetries: number,
	teleportRetryDelaySeconds: number,
	arrivalWaitSeconds: number,
	voteSeconds: number,
	launchCountdownSeconds: number,
	kickRejoinBlockSeconds: number,
}

local Lobby: LobbyConfig = {
	-- One. A party of one is a solo run, and Config/Run.soloAllowed is what actually decides whether
	-- that is legal. Never raise this to force grouping: four parties exist so people CAN group, not
	-- so a lone player is locked out of the hub they are standing in.
	minimumPlayers = 1,
	teleportRetries = 2,
	-- Pause between a failed reserved-server teleport and the next retry attempt.
	teleportRetryDelaySeconds = 1,
	-- Reserved servers wait briefly for every teleported profile before beginning the countdown.
	arrivalWaitSeconds = 8,

	-- HOW LONG THE CAVE VOTE STAYS OPEN once every member of a party has readied. It closes early the
	-- moment everybody has voted, so this is the ceiling on one undecided player holding up a party,
	-- not the length of a normal vote. Long enough to read three admission prices and talk about
	-- them, short enough that an idle member cannot stall a party indefinitely.
	voteSeconds = 20,
	-- The committed window between a resolved vote and the car actually leaving. The roster is frozen
	-- here (Party phase "Launching"), so this is deliberately short: it is the "we are going" beat,
	-- not another chance to change your mind.
	launchCountdownSeconds = 3,
	-- A party leader may remove another rider while the roster is still reversible. The removed
	-- player stays in the hub but cannot step back into that same car during this window.
	kickRejoinBlockSeconds = 20,
}

return Lobby
