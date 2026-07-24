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
		LobbyAction = { burst = 5, perSecond = 2 },
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
