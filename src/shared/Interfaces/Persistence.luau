--!strict
-- ============================ STUB ============================
-- In-memory persistence. Replace with ProfileStore later (DESIGN §19: never raw DataStore).
-- This is the ONLY file that should change when swapping in the real thing (ARCHITECTURE invariant).
-- No session locking, no DataStore. Data lives in a module table and is lost on server restart.
-- =============================================================

local Types = require(script.Parent.Parent.Types)

export type Profile = {
	unlockedCaveTier: number,
	currency: number,
	cosmetics: { string },
}

export type PersistenceInterface = {
	get: (playerId: Types.PlayerId) -> Profile,
	save: (playerId: Types.PlayerId, profile: Profile) -> (),
}

local DEFAULT_PROFILE: Profile = {
	unlockedCaveTier = 1,
	currency = 0,
	cosmetics = {},
}

local store: { [Types.PlayerId]: Profile } = {}

local Persistence: PersistenceInterface = {
	get = function(playerId)
		return store[playerId] or DEFAULT_PROFILE
	end,
	save = function(playerId, profile)
		store[playerId] = profile
	end,
}

return Persistence
