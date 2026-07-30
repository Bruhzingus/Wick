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
		MovementAction = { burst = 12, perSecond = 8 },
		BasinChoose = { burst = 3, perSecond = 1 },
		RestartRun = { burst = 2, perSecond = 0.25 },
		ReturnToLobby = { burst = 2, perSecond = 0.25 },
		LobbyAction = { burst = 5, perSecond = 2 },
		-- The client samples its camera at Config/AshamedLurker.gaze.sampleHz (10). Headroom above
		-- that, but far below what spamming the stare would need to be worth forging.
		LurkerGaze = { burst = 6, perSecond = 12 },
		-- One swing is two messages (begin + release) and the deposit enforces its own cooldown
		-- server-side, so honest play never approaches this. Spam is rejected before it can be used
		-- to shorten the three-strike sequence or to machine-gun noise into the sound field.
		MineStrike = { burst = 6, perSecond = 4 },
		-- The bell carries its own multi-second cooldown and a wax cost server-side, so this exists only
		-- to stop a client burning CPU on rings that will all be refused anyway. Deliberately tighter
		-- than the cooldown itself: there is no honest reason to ask twice.
		BellRing = { burst = 2, perSecond = 0.5 },
		-- A ghost pressing the follow key. Nothing it can ask for costs anything or moves a living
		-- player, so this only bounds a client spamming the cycle; the anchor it produces carries its
		-- own server-side cooldown (Config/Spectator.follow.reanchorCooldownSeconds).
		SpectatorAction = { burst = 5, perSecond = 2 },
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
