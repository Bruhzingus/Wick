--!strict
-- Server trust-boundary tuning. These values limit request spam and impossible character movement.

export type RateLimit = {
	burst: number,
	perSecond: number,
}

export type SecurityConfig = {
	remoteRateLimits: { [string]: RateLimit },
	movement: {
		sampleSeconds: number,
		trustWindowSeconds: number,
		slackMultiplier: number,
		teleportAllowance: number,
	},
	telemetryEnabled: boolean,
}

local Security: SecurityConfig = {
	remoteRateLimits = {
		SetBurnRate = { burst = 12, perSecond = 8 },
		ToolUse = { burst = 6, perSecond = 3 },
		BasinChoose = { burst = 3, perSecond = 1 },
		RestartRun = { burst = 2, perSecond = 0.25 },
		ReturnToLobby = { burst = 2, perSecond = 0.25 },
		LobbyAction = { burst = 5, perSecond = 2 },
		-- Selection and confirmation are local; only opening, buying, and changing an agreement cross
		-- this boundary. Headroom permits a quick tab refresh without making purchase spam useful.
		ShopAction = { burst = 8, perSecond = 4 },
		-- The client samples its camera at Config/AshamedLurker.gaze.sampleHz (10). Headroom above
		-- that, but far below what spamming the stare would need to be worth forging.
		LurkerGaze = { burst = 6, perSecond = 12 },
		-- One swing is two messages (begin + release) and the deposit enforces its own cooldown
		-- server-side, so honest play never approaches this. Spam is rejected before it can be used
		-- to shorten the three-strike sequence or to machine-gun noise into the sound field.
		MineStrike = { burst = 6, perSecond = 4 },
		-- Dynamite (Config/Dynamite). Tight, because the bag is the real gate and it is TINY: a player
		-- holds at most four sticks in a whole run, and every accepted throw or placement spends one.
		-- This exists only to stop a client burning server CPU on requests that will all be refused
		-- once the bag is empty, and to keep a forged `light` spam from hammering the door lookup.
		--
		-- `RequestGuard.allow` FAILS CLOSED on a missing row — every request would be silently dropped
		-- and the item would appear to do nothing — so this row is load-bearing, not optional.
		DynamiteAction = { burst = 4, perSecond = 2 },
		-- A ghost pressing the follow key. Nothing it can ask for costs anything or moves a living
		-- player, so this only bounds a client spamming the cycle; the anchor it produces carries its
		-- own server-side cooldown (Config/Spectator.follow.reanchorCooldownSeconds).
		SpectatorAction = { burst = 5, perSecond = 2 },
		-- Lobby PIN submission plus an occasional state sync. Diagnostics never accept gameplay values.
		DevDiagnostics = { burst = 4, perSecond = 1 },
		-- The test-lab remote can only sync or submit the PIN. Spawn controls are server-owned prompts,
		-- but this still bounds forged doorway submissions before proximity and lobby checks run.
		DevTestRoom = { burst = 4, perSecond = 1 },
	},
	movement = {
		sampleSeconds = 0.2,
		-- Keep a longer-lived trusted anchor so fixed replication slack cannot be spent again
		-- every sample to sustain an impossible speed.
		trustWindowSeconds = 1,
		-- Multiplies the maximum sustained run speed before a correction is considered.
		slackMultiplier = 1.5,
		-- Extra studs allowed for replication jitter. Authorized teleports reset the anchor.
		teleportAllowance = 2.5,
	},
	telemetryEnabled = true,
}

return Security
