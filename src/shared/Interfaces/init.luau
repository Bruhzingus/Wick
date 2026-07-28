--!strict
-- Aggregated replaceable system boundaries. Persistence, cave tiers, the Lamp Network, party state,
-- the cross-server deepest-floor leaderboard, and session remains are implemented; Lineage and
-- global/cross-server remains remain deferred.
--
-- The type re-exports below exist so a service can annotate a value it received from one of these
-- boundaries without reaching past the aggregate to require the module a second time.

local Persistence = require(script.Persistence)
local CaveTiers = require(script.CaveTiers)
local LampNetwork = require(script.LampNetwork)
local Leaderboard = require(script.Leaderboard)
local Lineage = require(script.Lineage)
local Remains = require(script.Remains)
local Party = require(script.Party)

export type Profile = Persistence.Profile
export type TransactionResult = Persistence.TransactionResult
export type CaveTier = CaveTiers.CaveTier
export type PurchaseResult = CaveTiers.PurchaseResult
export type LampNode = LampNetwork.LampNode
export type LampContract = LampNetwork.LampContract
export type LampPurchaseResult = LampNetwork.PurchaseResult
export type RemainsRecord = Remains.RemainsRecord
export type RemainsDeposit = Remains.RemainsDeposit

return {
	Persistence = Persistence,
	CaveTiers = CaveTiers,
	LampNetwork = LampNetwork,
	Leaderboard = Leaderboard,
	Lineage = Lineage,
	Remains = Remains,
	Party = Party,
}
