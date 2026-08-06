--!strict
-- PURE CAVE-VOTE TALLY. A party's party votes on which cave to descend into once everybody in the
-- car has readied up; this file decides which vote wins and nothing else. No Instances, no services,
-- no Player objects - it takes a table of votes and returns a tier id, so the whole rule is testable
-- cold (Tests/PartyVoteTests).
--
-- WHY A TALLY AND NOT "THE LEADER PICKS". Standing in a car is already a physical commitment, and a
-- party that has to agree on a cave has to talk about the cave. The leader is kept only as a
-- TIEBREAK, not as an authority: two players who disagree resolve it between themselves, and the
-- leader's vote settles a genuine deadlock rather than overriding a majority.
--
-- THIS FILE DECIDES NOTHING ABOUT AFFORDABILITY. A tier that wins the vote may still be one somebody
-- cannot pay for; PartyLobbyService re-checks every member's admission against the winning tier and
-- refuses the launch there. Keeping the two apart means the tally cannot silently drop a player's
-- vote because their wallet was short at the instant it ran, which would read as the UI lying.

local Types = require(script.Parent.Parent.Types)

local PartyVote = {}

export type VoteMap = { [Types.PlayerId]: number }

-- Votes from players who are no longer in the party are ignored rather than trusted: a member who
-- walked out of the car between the last tick and this one must not keep steering the cave.
--
-- `fallbackTierId` is returned only when the party cast no usable votes at all. Callers pass the
-- cheapest always-owned cave, so a silent party still gets a legal descent rather than tier 0.
function PartyVote.resolve(
	votes: VoteMap,
	members: { Types.PlayerId },
	leaderId: Types.PlayerId,
	fallbackTierId: number
): number
	local counts: { [number]: number } = {}
	local best = 0
	for _, memberId in members do
		local tierId = votes[memberId]
		if tierId == nil then
			continue
		end
		local total = (counts[tierId] or 0) + 1
		counts[tierId] = total
		if total > best then
			best = total
		end
	end
	if best == 0 then
		return fallbackTierId
	end

	-- Every tier holding the winning count. Collected rather than tracked during the loop above
	-- because a later tier can catch up to an earlier one and both then have to be considered.
	local tied: { number } = {}
	for tierId, total in counts do
		if total == best then
			table.insert(tied, tierId)
		end
	end
	if #tied == 1 then
		return tied[1]
	end

	-- Deadlock. The leader's own vote settles it when the leader backed one of the tied tiers.
	local leaderChoice = votes[leaderId]
	if leaderChoice ~= nil and table.find(tied, leaderChoice) ~= nil then
		return leaderChoice
	end
	-- Otherwise the shallowest tied cave: a party that cannot agree descends into the cheaper, safer
	-- of the options it deadlocked on rather than the one most likely to take somebody's admission.
	table.sort(tied)
	return tied[1]
end

-- How many members backed each tier, for the live tally the vote UI draws. Separate from `resolve`
-- so the display can never disagree with the decision: both read the same votes, and neither
-- recomputes the other's answer.
function PartyVote.tally(votes: VoteMap, members: { Types.PlayerId }): { [number]: number }
	local counts: { [number]: number } = {}
	for _, memberId in members do
		local tierId = votes[memberId]
		if tierId ~= nil then
			counts[tierId] = (counts[tierId] or 0) + 1
		end
	end
	return counts
end

return PartyVote
