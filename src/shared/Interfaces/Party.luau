--!strict
-- In-server lobby party. The expedition remains disposable; PartyLobbyService handles the
-- reserved-server teleport boundary. One party per small lobby server is intentional for v1.

local Types = require(script.Parent.Parent.Types)

export type Party = {
	leaderId: Types.PlayerId,
	members: { Types.PlayerId },
	ready: { [Types.PlayerId]: boolean },
	tierId: number,
}

export type PartyInterface = {
	join: (playerId: Types.PlayerId, cap: number) -> boolean,
	leave: (playerId: Types.PlayerId) -> (),
	setReady: (playerId: Types.PlayerId, isReady: boolean) -> boolean,
	setTier: (playerId: Types.PlayerId, tierId: number) -> boolean,
	adoptExpeditionTier: (tierId: number) -> (),
	snapshot: () -> Party?,
	allReady: (minimumPlayers: number) -> boolean,
}

local current: Party? = nil

local function contains(members: { Types.PlayerId }, playerId: Types.PlayerId): boolean
	return table.find(members, playerId) ~= nil
end

local PartyService: PartyInterface

PartyService = {
	join = function(playerId, cap)
		if current == nil then
			current = {
				leaderId = playerId,
				members = { playerId },
				ready = { [playerId] = false },
				tierId = 1,
			}
			return true
		end
		local party = current :: Party
		if contains(party.members, playerId) then
			return true
		end
		if #party.members >= cap then
			return false
		end
		table.insert(party.members, playerId)
		party.ready[playerId] = false
		return true
	end,

	leave = function(playerId)
		local party = current
		if party == nil then
			return
		end
		local index = table.find(party.members, playerId)
		if index ~= nil then
			table.remove(party.members, index)
		end
		party.ready[playerId] = nil
		if #party.members == 0 then
			current = nil
		elseif party.leaderId == playerId then
			party.leaderId = party.members[1]
		end
	end,

	setReady = function(playerId, isReady)
		local party = current
		if party == nil or not contains(party.members, playerId) then
			return false
		end
		party.ready[playerId] = isReady
		return true
	end,

	setTier = function(playerId, tierId)
		local party = current
		if party == nil or party.leaderId ~= playerId then
			return false
		end
		party.tierId = tierId
		for memberId in party.ready do
			party.ready[memberId] = false
		end
		return true
	end,

	-- Adopts a reserved-server's expedition tier onto a mid-arrival member without touching
	-- readiness (unlike setTier, which is a leader-only action that intentionally clears it).
	adoptExpeditionTier = function(tierId)
		local party = current
		if party ~= nil then
			party.tierId = tierId
		end
	end,

	snapshot = function()
		return current
	end,

	allReady = function(minimumPlayers)
		local party = current
		if party == nil or #party.members < minimumPlayers then
			return false
		end
		for _, memberId in party.members do
			if not party.ready[memberId] then
				return false
			end
		end
		return true
	end,
}

return PartyService
