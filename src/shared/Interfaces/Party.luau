--!strict
-- IN-SERVER PARTIES, ONE PER ELEVATOR PARTY. The Landing holds four elevator alcoves and each one is
-- an independent queue: its own roster, its own readiness, its own cave vote, its own descent. Up to
-- four players per party, so a full public lobby can be four parties that never interact.
--
-- THIS REPLACED A SINGLE SERVER-WIDE PARTY. Everyone in the server used to be auto-joined into one
-- party at connect time, and the elevators were tier buttons that party walked between. Two things
-- broke under that model and both are why this file is now a registry:
--   * Friends could not queue separately. A fifth player joining a server locked out or displaced
--     somebody, because there was exactly one roster.
--   * Readiness had no honest meaning. Standing in a car WAS being ready, so nobody could stand in a
--     car and think about it, and nobody could gather before committing.
--
-- YOU JOIN A PARTY BY WALKING INTO A CAR, and leave by walking out or using the panel's server-owned
-- ejection. A player loose in the hub is in no party at all, which is a state the old model could not
-- represent.
--
-- THE EXPEDITION PARTY IS SEPARATE FROM ALL OF THAT. A reserved expedition server holds exactly one
-- party (the one that teleported in) and no parties anybody can walk between. `expedition()` is that
-- party, `snapshot()` is kept as its alias, and everything on the run side (RunOrchestrator,
-- init.server) reads only those, so no expedition code had to learn that parties exist.

local Types = require(script.Parent.Parent.Types)
local PartyRules = require(script.Parent.Parent.Logic.PartyRules)

-- Gathering: players are arriving and readying. Voting: everyone present is ready and the cave is
-- being chosen. Launching: the vote resolved and the descent is committed, so the roster is frozen.
export type PartyPhase = PartyRules.PartyPhase

export type Party = {
	partyId: number,
	leaderId: Types.PlayerId,
	members: { Types.PlayerId },
	ready: { [Types.PlayerId]: boolean },
	-- Per-member cave choice, tallied by Logic/PartyVote. Absent means "has not voted yet".
	votes: { [Types.PlayerId]: number },
	-- A leader removal blocks only this player from only this car until the server-clock deadline.
	-- It is session-local protection against an immediate rejoin, never a ban from the lobby.
	joinBlockedUntil: { [Types.PlayerId]: number },
	-- The winning tier once the vote resolves. Meaningless before that, and deliberately not
	-- defaulted to a real cave: a party that has not voted must not read as having chosen tier 1.
	tierId: number,
	phase: PartyPhase,
}

export type PartyInterface = {
	join: (playerId: Types.PlayerId, partyId: number, cap: number, now: number) -> boolean,
	leave: (playerId: Types.PlayerId) -> (),
	kick: (leaderId: Types.PlayerId, targetId: Types.PlayerId, blockedUntil: number) -> boolean,
	joinBlockRemaining: (playerId: Types.PlayerId, partyId: number, now: number) -> number,
	get: (partyId: number) -> Party?,
	list: () -> { Party },
	forPlayer: (playerId: Types.PlayerId) -> Party?,
	setReady: (playerId: Types.PlayerId, isReady: boolean) -> boolean,
	setVote: (playerId: Types.PlayerId, tierId: number) -> boolean,
	setPhase: (partyId: number, phase: PartyPhase) -> (),
	setTier: (partyId: number, tierId: number) -> (),
	allReady: (party: Party, minimumPlayers: number) -> boolean,
	joinExpedition: (playerId: Types.PlayerId, cap: number) -> boolean,
	markExpedition: (partyId: number) -> (),
	expedition: () -> Party?,
	snapshot: () -> Party?,
	adoptExpeditionTier: (tierId: number) -> (),
	clear: () -> (),
}

-- Keyed by party id. A party with nobody in it holds no table at all, so "is anyone queuing here"
-- is a nil check rather than a member count that can drift.
local parties: { [number]: Party } = {}
-- Which party this server is actually running an expedition for. Nil means no expedition; zero is a
-- REAL party id reserved for arrivals in a destination server and must never be used as the sentinel.
local expeditionPartyId: number? = nil
-- The party reserved-server arrivals are collected into. Never walked into by anybody; it exists so
-- an expedition server can hold its one party in the same structure a lobby uses.
local EXPEDITION_PARTY_ID = 0

local PartyService: PartyInterface

local function removeFrom(party: Party, playerId: Types.PlayerId)
	local index = table.find(party.members, playerId)
	if index ~= nil then
		table.remove(party.members, index)
	end
	party.ready[playerId] = nil
	party.votes[playerId] = nil
	-- A changed roster invalidates the ballot. Remaining ready flags stay intact, so a party whose
	-- remaining members are still committed may open a fresh vote on the next elevator tick.
	if party.phase == "Voting" then
		party.phase = "Gathering"
		table.clear(party.votes)
		party.tierId = 0
	end
	if #party.members == 0 then
		parties[party.partyId] = nil
		if expeditionPartyId == party.partyId then
			expeditionPartyId = nil
		end
	elseif party.leaderId == playerId then
		party.leaderId = party.members[1]
	end
end

local function createParty(partyId: number, playerId: Types.PlayerId): Party
	local party: Party = {
		partyId = partyId,
		leaderId = playerId,
		members = { playerId },
		ready = { [playerId] = false },
		votes = {},
		joinBlockedUntil = {},
		tierId = 0,
		phase = "Gathering",
	}
	parties[partyId] = party
	return party
end

PartyService = {
	-- Walking into a car. A player already queuing somewhere else is pulled out of that party first,
	-- so a player is never in two parties and never counted twice against a cap.
	--
	-- Refuses while the target party is Launching: its car has committed and its roster is frozen.
	join = function(playerId, partyId, cap, now)
		local existing = parties[partyId]
		if existing ~= nil and table.find(existing.members, playerId) ~= nil then
			return true
		end
		if existing ~= nil then
			local blockRemaining = PartyRules.joinBlockRemaining(existing.joinBlockedUntil[playerId], now)
			if blockRemaining > 0 or existing.phase == "Launching" or #existing.members >= cap then
				return false
			end
			existing.joinBlockedUntil[playerId] = nil
		end
		PartyService.leave(playerId)
		-- Re-read: `leave` deletes the party's table when it empties, and the player who just left
		-- could have been the last member of THIS party in a same-party rejoin race.
		existing = parties[partyId]
		if existing == nil then
			createParty(partyId, playerId)
			return true
		end
		table.insert(existing.members, playerId)
		existing.ready[playerId] = false
		-- A new arrival un-resolves a vote in progress: the party that was choosing a cave is not the
		-- party that is choosing it now, and a member who never voted must not be launched by a
		-- tally they were not part of.
		if existing.phase == "Voting" then
			existing.phase = "Gathering"
			table.clear(existing.votes)
			existing.tierId = 0
		end
		return true
	end,

	-- Reserved-server arrivals, which have no party to stand in. Kept separate from `join` so the
	-- lobby's cap/phase rules cannot accidentally refuse a player Roblox has already teleported.
	joinExpedition = function(playerId, cap)
		local party = parties[EXPEDITION_PARTY_ID]
		if party == nil then
			createParty(EXPEDITION_PARTY_ID, playerId)
			expeditionPartyId = EXPEDITION_PARTY_ID
			return true
		end
		if table.find(party.members, playerId) ~= nil then
			return true
		end
		if #party.members >= cap then
			return false
		end
		table.insert(party.members, playerId)
		party.ready[playerId] = false
		expeditionPartyId = EXPEDITION_PARTY_ID
		return true
	end,

	leave = function(playerId)
		local party = PartyService.forPlayer(playerId)
		if party ~= nil then
			removeFrom(party, playerId)
		end
	end,

	-- Leader-only removal. The caller supplies the server-owned deadline from Config/Lobby; keeping
	-- duration out of this state store makes the rule testable without teaching an interface config.
	kick = function(leaderId, targetId, blockedUntil)
		local party = PartyService.forPlayer(leaderId)
		if party == nil or not PartyRules.canKick(party.leaderId, party.members, party.phase, leaderId, targetId) then
			return false
		end
		removeFrom(party, targetId)
		party.joinBlockedUntil[targetId] = blockedUntil
		return true
	end,

	joinBlockRemaining = function(playerId, partyId, now)
		local party = parties[partyId]
		if party == nil then
			return 0
		end
		local remaining = PartyRules.joinBlockRemaining(party.joinBlockedUntil[playerId], now)
		if remaining <= 0 then
			party.joinBlockedUntil[playerId] = nil
		end
		return remaining
	end,

	get = function(partyId)
		return parties[partyId]
	end,

	list = function()
		local result: { Party } = {}
		for _, party in parties do
			table.insert(result, party)
		end
		-- Stable order, so a UI drawing the hub's parties never reshuffles between frames.
		table.sort(result, function(a: Party, b: Party): boolean
			return a.partyId < b.partyId
		end)
		return result
	end,

	forPlayer = function(playerId)
		for _, party in parties do
			if table.find(party.members, playerId) ~= nil then
				return party
			end
		end
		return nil
	end,

	setReady = function(playerId, isReady)
		local party = PartyService.forPlayer(playerId)
		if party == nil or party.phase == "Launching" then
			return false
		end
		party.ready[playerId] = isReady
		-- Un-readying during a vote takes the party back to gathering: the cave question is only open
		-- while everybody standing in the car still wants to go.
		if not isReady and party.phase == "Voting" then
			party.phase = "Gathering"
			table.clear(party.votes)
			party.tierId = 0
		end
		return true
	end,

	-- A vote is only meaningful once the party has reached the voting phase, and readiness is what
	-- earns a member the right to cast one. Both are checked here rather than at the call site so no
	-- remote path can vote a party into a cave it never opened the question on.
	setVote = function(playerId, tierId)
		local party = PartyService.forPlayer(playerId)
		if party == nil or party.phase ~= "Voting" or party.ready[playerId] ~= true then
			return false
		end
		party.votes[playerId] = tierId
		return true
	end,

	setPhase = function(partyId, phase)
		local party = parties[partyId]
		if party == nil then
			return
		end
		party.phase = phase
		if phase == "Gathering" then
			-- Leaving the vote clears it. A stale ballot carried back into a later vote would let a
			-- member who has since walked out keep a say in it.
			table.clear(party.votes)
			party.tierId = 0
		end
	end,

	setTier = function(partyId, tierId)
		local party = parties[partyId]
		if party ~= nil then
			party.tierId = tierId
		end
	end,

	-- Takes the party rather than reading a global, because "all ready" is a question about one
	-- party and there are now several. A party below the minimum is never ready however many of its
	-- members have pressed the button.
	allReady = function(party, minimumPlayers)
		if #party.members < minimumPlayers then
			return false
		end
		for _, memberId in party.members do
			if not party.ready[memberId] then
				return false
			end
		end
		return true
	end,

	markExpedition = function(partyId)
		expeditionPartyId = partyId
	end,

	expedition = function()
		local partyId = expeditionPartyId
		if partyId == nil then
			return nil
		end
		return parties[partyId]
	end,

	-- The run side's name for the expedition party. Kept so RunOrchestrator, init.server and the
	-- expedition half of PartyLobbyService did not have to learn that parties exist at all.
	snapshot = function()
		return PartyService.expedition()
	end,

	adoptExpeditionTier = function(tierId)
		local party = PartyService.expedition()
		if party ~= nil then
			party.tierId = tierId
		end
	end,

	clear = function()
		table.clear(parties)
		expeditionPartyId = nil
	end,
}

return PartyService
