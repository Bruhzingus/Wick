--!strict
-- Replicated presentation contract for the Unlittius encounter (Config/Unlittius, DESIGN §9b).
--
-- SERVER WRITES STATE AND TIMESTAMPS; CLIENTS RECONSTRUCT MOTION. The same contract the unstable
-- dripstone, the mining rail and the descent elevator already use, and it is the reason this
-- encounter needs no new RemoteEvent: a boulder is an anchored part carrying its origin, direction,
-- speed and launch time, and every client draws it from `workspace:GetServerTimeNow()` rather than
-- being told where it is twenty times a second. The server's own logical projectile is the only thing
-- that decides a hit.
--
-- WHY ATTRIBUTES AND TAGS RATHER THAN A REMOTE. A remote reaches only the clients that are listening
-- when it fires. A player who walks into the chamber halfway through the fight has to see a boss
-- whose rune is already dimmed to three eighths, four already-lit candles and a boulder in the air —
-- and attributes replicate that state to a late joiner for free.

local UnlittiusVisualProtocol = {
	-- The boss himself. Carries his action, its start time, and how much of him is left.
	boss = {
		tag = "WickUnlittius",
		attributes = {
			-- One of `Logic/UnlittiusRules.ActionId`, plus "Idle", "Recoil", "Banish".
			action = "WickUnlittiusAction",
			actionStartedAt = "WickUnlittiusActionStartedAt",
			candlesLit = "WickUnlittiusCandlesLit",
			-- 0..1. Everything cosmetic scales off this: eye glow, particle rate, hum gain.
			power = "WickUnlittiusPower",
			-- Set once, when the banish begins, so a late joiner does not replay the sequence.
			banishStartedAt = "WickUnlittiusBanishStartedAt",
			depth = "WickUnlittiusDepth",
		},
	},

	-- One conjured boulder. Analytic: position is `origin + direction * speed * (now - firedAt)`,
	-- which is the same arithmetic the server is stepping, so the visual and the collision cannot
	-- drift apart no matter what the frame rate is at either end.
	boulder = {
		tag = "WickUnlittiusBoulder",
		attributes = {
			origin = "WickBoulderOrigin",
			direction = "WickBoulderDirection",
			speed = "WickBoulderSpeed",
			-- While this is in the future the stone is still assembling out of fragments at its spawn
			-- attachment and has not left his hand's influence.
			conjuredAt = "WickBoulderConjuredAt",
			firedAt = "WickBoulderFiredAt",
			radius = "WickBoulderRadius",
		},
	},

	-- A dripstone impact zone, marked on the floor before anything falls.
	telegraph = {
		tag = "WickUnlittiusTelegraph",
		attributes = {
			markedAt = "WickTelegraphMarkedAt",
			impactAt = "WickTelegraphImpactAt",
			radius = "WickTelegraphRadius",
		},
	},

	-- One of the eight encounter candles.
	candle = {
		tag = "WickUnlittiusCandle",
		attributes = {
			index = "WickCandleIndex",
			lit = "WickCandleLit",
			litAt = "WickCandleLitAt",
			depth = "WickCandleDepth",
		},
	},

	actions = {
		idle = "Idle",
		dripstone = "Dripstone",
		boulder = "BoulderBurst",
		summon = "SummonGnawers",
		melee = "Melee",
		recoil = "Recoil",
		banish = "Banish",
	},
}

return table.freeze(UnlittiusVisualProtocol)
