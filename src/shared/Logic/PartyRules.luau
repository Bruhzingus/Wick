--!strict
-- Pure membership decisions for a lobby elevator party. Interfaces/Party stores the live roster;
-- this module answers the two rules that must stay identical on every mutation path: who may remove
-- somebody, and whether a removed player is still inside their temporary re-entry block.

local PartyRules = {}

export type PartyPhase = "Gathering" | "Voting" | "Launching"

function PartyRules.canKick(
	leaderId: number,
	members: { number },
	phase: PartyPhase,
	actorId: number,
	targetId: number
): boolean
	return phase ~= "Launching"
		and actorId == leaderId
		and targetId ~= actorId
		and table.find(members, actorId) ~= nil
		and table.find(members, targetId) ~= nil
end

function PartyRules.joinBlockRemaining(blockedUntil: number?, now: number): number
	if blockedUntil == nil then
		return 0
	end
	return math.max(0, blockedUntil - now)
end

return PartyRules
