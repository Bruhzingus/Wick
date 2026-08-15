--!strict
-- Session-local remains implementation. Records survive run teardown but disappear when this server
-- closes. Cross-server/global remains remain deferred behind this same interface.
--
-- PHASE 8 GAVE REMAINS A SECOND PAYLOAD. A pool of candle remains now holds Raw Wax cargo as well as
-- wax, because the two things that leave a body behind — the light someone can relight from, and the
-- haul they were carrying — belong on one object with one prompt rather than two piles to hoover up.
--
-- THE OWNER LOCK IS THE ANTI-DUPLICATION MECHANISM. A disconnect drops the player's bag immediately,
-- visibly, but claimable only by that player until `ownerLockUntil` passes. This is what lets
-- "it drops, and if you come back it's yours" be true without ever taking cargo back from someone who
-- already picked it up: at every instant the cargo is in exactly one place, and the transition
-- between places is a single claim that either succeeds or does not.
--
-- CARGO NEVER CROSSES A RUN BOUNDARY. Wax remains deliberately outlive an expedition (that is the
-- whole point of finding a stranger's candle), but cargo that survived teardown would be free money
-- deposited into the next run — so `clearAllCargo` strips it during teardown while leaving the wax.

local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config.Remains)
local CargoRules = require(script.Parent.Parent.Logic.CargoRules)

export type RemainsDeposit = {
	playerId: Types.PlayerId,
	depth: number,
	position: Vector3,
	wax: Types.WaxAmount,
	cargo: Types.RawWaxCargo?,
	-- os.clock() until which only `playerId` may take the cargo. Omitted/zero means anyone may.
	ownerLockUntil: number?,
}

export type RemainsRecord = {
	id: number,
	playerId: Types.PlayerId,
	depth: number,
	position: Vector3,
	wax: Types.WaxAmount,
	cargo: Types.RawWaxCargo,
	ownerLockUntil: number,
}

export type RemainsInterface = {
	listForFloor: (depth: number) -> { RemainsRecord },
	deposit: (remains: RemainsDeposit) -> RemainsRecord?,
	claim: (id: number, maximumWax: Types.WaxAmount?) -> (RemainsRecord?, Types.WaxAmount),
	-- Claim the cargo half. Returns what was granted and whether the record still holds any. Refuses
	-- entirely while the owner lock is live and the requester is not the owner.
	claimCargo: (
		id: number,
		requesterId: Types.PlayerId,
		now: number,
		maximumGrams: number
	) -> (Types.RawWaxCargo, boolean),
	-- True if this record currently holds cargo the requester is allowed to take.
	cargoAvailableTo: (id: number, requesterId: Types.PlayerId, now: number) -> boolean,
	clearAllCargo: () -> (),
}

local recordsByFloor: { [number]: { RemainsRecord } } = {}
local nextId = 1

local function copyCargo(cargo: Types.RawWaxCargo): Types.RawWaxCargo
	local stacks: { Types.RawWaxStack } = table.create(#cargo.stacks)
	for index, stack in cargo.stacks do
		stacks[index] = { originDepth = stack.originDepth, grams = stack.grams }
	end
	return { stacks = stacks, total = cargo.total }
end

local function copyRecord(record: RemainsRecord): RemainsRecord
	return {
		id = record.id,
		playerId = record.playerId,
		depth = record.depth,
		position = record.position,
		wax = record.wax,
		cargo = copyCargo(record.cargo),
		ownerLockUntil = record.ownerLockUntil,
	}
end

local function findRecord(id: number): ({ RemainsRecord }?, number?)
	for _, floorRecords in recordsByFloor do
		for index, record in floorRecords do
			if record.id == id then
				return floorRecords, index
			end
		end
	end
	return nil, nil
end

-- A record is worth keeping while it holds either payload. Removing it the moment its wax runs out
-- would delete cargo nobody had collected yet.
local function isEmpty(record: RemainsRecord): boolean
	return record.wax <= 1e-9 and record.cargo.total <= 0
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
	local cargo = if remains.cargo ~= nil then copyCargo(remains.cargo) else CargoRules.newCargo()
	-- A body with no wax but a real haul still leaves something behind, and a body with neither leaves
	-- nothing. Checking both payloads is what lets a player who burned out completely still drop the
	-- cargo they died carrying.
	if remains.wax < Config.minimumWax and cargo.total <= 0 then
		return nil
	end

	local depth = math.max(1, math.floor(remains.depth))
	local record: RemainsRecord = {
		id = nextId,
		playerId = remains.playerId,
		depth = depth,
		position = remains.position,
		wax = remains.wax,
		cargo = cargo,
		ownerLockUntil = remains.ownerLockUntil or 0,
	}
	nextId += 1

	local floorRecords = recordsByFloor[depth]
	if floorRecords == nil then
		floorRecords = {}
		recordsByFloor[depth] = floorRecords
	end
	table.insert(floorRecords, record)
	-- The per-floor cap evicts oldest-first. Prefer evicting a record that has already given up its
	-- cargo, so a busy floor cannot silently delete someone's unrecovered haul to make room.
	while #floorRecords > Config.maxStoredPerFloor do
		local evictIndex = 1
		for index, candidate in floorRecords do
			if candidate.cargo.total <= 0 then
				evictIndex = index
				break
			end
		end
		table.remove(floorRecords, evictIndex)
	end
	return copyRecord(record)
end

local function claim(id: number, maximumWax: Types.WaxAmount?): (RemainsRecord?, Types.WaxAmount)
	local limit = math.max(maximumWax or math.huge, 0)
	if limit <= 0 then
		return nil, 0
	end
	local floorRecords, index = findRecord(id)
	if floorRecords == nil or index == nil then
		return nil, 0
	end
	local record = floorRecords[index]
	local claimedWax = math.min(record.wax, limit)
	local remainingWax = math.max(record.wax - claimedWax, 0)
	local claimed = copyRecord(record)
	claimed.wax = claimedWax
	record.wax = remainingWax
	if isEmpty(record) then
		table.remove(floorRecords, index)
	end
	return claimed, remainingWax
end

local function cargoAvailableTo(id: number, requesterId: Types.PlayerId, now: number): boolean
	local floorRecords, index = findRecord(id)
	if floorRecords == nil or index == nil then
		return false
	end
	local record = floorRecords[index]
	if record.cargo.total <= 0 then
		return false
	end
	-- The lock. Someone else's dropped bag is untouchable until their window closes.
	if now < record.ownerLockUntil and requesterId ~= record.playerId then
		return false
	end
	return true
end

-- The single claim that moves cargo out of the world. Removing it from the record BEFORE returning it
-- is what makes two simultaneous prompt triggers safe: the second finds nothing left.
local function claimCargo(
	id: number,
	requesterId: Types.PlayerId,
	now: number,
	maximumGrams: number
): (Types.RawWaxCargo, boolean)
	if not cargoAvailableTo(id, requesterId, now) then
		return CargoRules.newCargo(), false
	end
	local floorRecords, index = findRecord(id)
	if floorRecords == nil or index == nil then
		return CargoRules.newCargo(), false
	end
	local record = floorRecords[index]

	-- A non-finite or fractional capacity claims nothing rather than everything.
	local finite = maximumGrams == maximumGrams and maximumGrams < math.huge and maximumGrams > -math.huge
	local room = if finite then math.max(0, math.floor(maximumGrams)) else 0
	if room <= 0 then
		return CargoRules.newCargo(), true
	end

	local granted: Types.RawWaxCargo
	local left: Types.RawWaxCargo
	if room >= record.cargo.total then
		granted, left = CargoRules.take(record.cargo)
	else
		-- Partial pickup: hand over as close to the claimant's room as the split can express. `split`
		-- apportions by ratio and owns the integer arithmetic, so this converts a gram count into the
		-- ratio that yields it.
		--
		-- ROUNDING UP FIRST, THEN CORRECTING DOWN, and both halves matter. The ceiling is what stops a
		-- floored ratio systematically handing over less than the player could carry; the correction is
		-- what stops the ceiling handing over MORE. Overshooting used to be impossible when a bag held
		-- fewer than a thousand units, so the old ceiling stood alone — a pile now measured in tens of
		-- thousands of grams can overshoot by a hundred, and the surplus would be split off the record
		-- only to bounce off the claimant's cap and be destroyed. `split` conserves, so re-splitting is
		-- free of any leak: the second call simply divides the untouched original the other way.
		local total = record.cargo.total
		local permille = math.ceil(room * 1000 / total)
		granted, left = CargoRules.split(record.cargo, permille)
		if granted.total > room then
			granted, left = CargoRules.split(record.cargo, math.floor(room * 1000 / total))
		end
	end
	record.cargo = left
	if isEmpty(record) then
		table.remove(floorRecords, index)
	end
	return granted, left.total > 0
end

-- Teardown. Strips every record's cargo while leaving its wax, so candle remains still outlive an
-- expedition (which is the point of them) but no haul is ever deposited into the next run.
local function clearAllCargo()
	for _, floorRecords in recordsByFloor do
		for index = #floorRecords, 1, -1 do
			local record = floorRecords[index]
			record.cargo = CargoRules.newCargo()
			record.ownerLockUntil = 0
			if isEmpty(record) then
				table.remove(floorRecords, index)
			end
		end
	end
end

local Remains: RemainsInterface = {
	listForFloor = listForFloor,
	deposit = deposit,
	claim = claim,
	claimCargo = claimCargo,
	cargoAvailableTo = cargoAvailableTo,
	clearAllCargo = clearAllCargo,
}

return Remains
