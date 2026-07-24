--!strict
-- ============================ STUB ============================
-- Party formation (DESIGN §19). Real version handles lobby grouping and TeleportService reserved
-- servers. Replace this one file. The stub takes the present players as input (keeping it pure)
-- and treats everyone on the server as one party, capped — so multi-client Studio testing works.
-- =============================================================

local Types = require(script.Parent.Parent.Types)

export type Party = {
	members: { Types.PlayerId },
}

export type PartyInterface = {
	getParty: (playerId: Types.PlayerId, presentIds: { Types.PlayerId }, cap: number) -> Party,
}

local Party: PartyInterface = {
	getParty = function(playerId, presentIds, cap)
		-- STUB: one party of everyone present, capped; the requesting player is always included.
		local members: { Types.PlayerId } = { playerId }
		for _, id in presentIds do
			if id ~= playerId and #members < cap then
				table.insert(members, id)
			end
		end
		return { members = members }
	end,
}

return Party
