--!strict
-- Aggregated replaceable system boundaries. Persistence, cave tiers, party state, and session
-- remains are implemented; Lineage and global/cross-server remains remain deferred.

return {
	Persistence = require(script.Persistence),
	CaveTiers = require(script.CaveTiers),
	Lineage = require(script.Lineage),
	Remains = require(script.Remains),
	Party = require(script.Party),
}
