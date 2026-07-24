--!strict
-- Aggregated stub interfaces (DESIGN §16 deferred systems). Every entry here is an in-memory STUB.
-- Replacing any one with a real implementation must touch exactly that one file (ARCHITECTURE invariant).

return {
	Persistence = require(script.Persistence),
	CaveTiers = require(script.CaveTiers),
	Lineage = require(script.Lineage),
	Remains = require(script.Remains),
	Party = require(script.Party),
}
