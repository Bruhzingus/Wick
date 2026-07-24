--!strict
-- Session-local remains implementation. Records survive run teardown but disappear when this
-- server closes. Cross-server/global remains remain deferred behind this same interface.

local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config.Remains)

export type RemainsDeposit = {
	playerId: Types.PlayerId,
	depth: number,
	position: Vector3,
	wax: Types.WaxAmount,
}

export type RemainsRecord = {
	id: number,
	playerId: Types.PlayerId,
	depth: number,
	position: Vector3,
	wax: Types.WaxAmount,
}

export type RemainsInterface = {
	listForFloor: (depth: number) -> { RemainsRecord },
	deposit: (remains: RemainsDeposit) -> RemainsRecord?,
	claim: (id: number, maximumWax: Types.WaxAmount?) -> (RemainsRecord?, Types.WaxAmount),
}

local recordsByFloor: { [number]: { RemainsRecord } } = {}
local nextId = 1

local function copyRecord(record: RemainsRecord): RemainsRecord
	return {
		id = record.id,
		playerId = record.playerId,
		depth = record.depth,
		position = record.position,
		wax = record.wax,
	}
end

local function listForFloor(depth: number): { RemainsRecord }
	local copies: { RemainsRecord } = {}
	local floorRecords = recordsByFloor[depth]
	if floorRecords == nil then
		return copies
	end
	for _, record in floorRecords do
		table.insert(copies, copyRecord(record))
	end
	return copies
end

local function deposit(remains: RemainsDeposit): RemainsRecord?
	if remains.wax < Config.minimumWax then
		return nil
	end

	local depth = math.max(1, math.floor(remains.depth))
	local record: RemainsRecord = {
		id = nextId,
		playerId = remains.playerId,
		depth = depth,
		position = remains.position,
		wax = remains.wax,
	}
	nextId += 1

	local floorRecords = recordsByFloor[depth]
	if floorRecords == nil then
		floorRecords = {}
		recordsByFloor[depth] = floorRecords
	end
	table.insert(floorRecords, record)
	while #floorRecords > Config.maxStoredPerFloor do
		table.remove(floorRecords, 1)
	end
	return copyRecord(record)
end

local function claim(id: number, maximumWax: Types.WaxAmount?): (RemainsRecord?, Types.WaxAmount)
	local limit = math.max(maximumWax or math.huge, 0)
	if limit <= 0 then
		return nil, 0
	end
	for _, floorRecords in recordsByFloor do
		for index, record in floorRecords do
			if record.id == id then
				local claimedWax = math.min(record.wax, limit)
				local remainingWax = math.max(record.wax - claimedWax, 0)
				local claimed = copyRecord(record)
				claimed.wax = claimedWax
				if remainingWax <= 1e-9 then
					table.remove(floorRecords, index)
				else
					record.wax = remainingWax
				end
				return claimed, remainingWax
			end
		end
	end
	return nil, 0
end

local Remains: RemainsInterface = {
	listForFloor = listForFloor,
	deposit = deposit,
	claim = claim,
}

return Remains
