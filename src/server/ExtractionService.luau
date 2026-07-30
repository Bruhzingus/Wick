--!strict
-- PHASE 8 — THE single authority over Raw Wax, from the swing that breaks a seam to the profile write
-- that makes it money. Every unit that enters the economy enters here, and every unit that leaves it
-- leaves here.
--
-- WHY ONE SERVICE OWNS BOTH ENDS: "two players credited for one seam", "one player credited twice for
-- one seam", and "one bag paid out twice" are the same bug wearing three hats, and it is the only bug
-- in this system that can mint currency out of nothing. Keeping the grant, the loss, and the payout in
-- one file means the latches that prevent them are all visible at once instead of trusting three
-- services to agree.
--
-- THE THREE LATCHES, each independent of the others:
--
--   1. `paidDeposits[depositId]` — a seam can be broken once, so it can pay cargo once. MiningService
--      already elects a single breaker with its own depletion flag; this is a SECOND, independent
--      latch, because a single guard is a single point of failure.
--   2. `run.extracted` — a run can cash out once. A duplicated remote, a replayed transition, or a
--      re-entrant commit finds this true and pays zero.
--   3. The profile transaction id — even if latches 1 and 2 were somehow bypassed, the persistence
--      layer refuses to apply the same transaction id twice (Interfaces/Persistence). This is the
--      one that survives a retry across a network failure.
--
-- HOW A FAILED PROFILE WRITE IS HANDLED, which is the question the whole design turns on: the cargo
-- is cleared from the bag ONLY after the credit is confirmed. If the write fails — an unloaded
-- profile, a session that ended underneath us — the player keeps their cargo, the `extracted` latch is
-- released, and they are told to try the brazier again. A player who is not paid must still be
-- carrying what they were not paid for, or the units have simply evaporated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local CargoRules = require(ReplicatedStorage.Shared.Logic.CargoRules)
local ExtractionValue = require(ReplicatedStorage.Shared.Logic.ExtractionValue)
local LampRules = require(ReplicatedStorage.Shared.Logic.LampRules)
local ContractRules = require(ReplicatedStorage.Shared.Logic.ContractRules)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

local ExtractionService = {}

-- Why a run lost cargo without being paid for it.
export type LossReason = "Death" | "Disconnect" | "Expired"

export type ExtractionOutcome = {
	ok: boolean,
	units: number,
	payout: number,
	balance: number,
	baseValue: number,
	cavePayoutPermille: number,
	failure: string?,
}

-- Deposits this run has already paid cargo for, keyed by "<depositId>:<playerId>". Run-scoped; cleared
-- on teardown alongside the ids themselves, so a recycled deposit id can never inherit a stale latch.
--
-- KEYED PER PLAYER, NOT PER DEPOSIT, since Twin Seam pays every miner standing at the break. The
-- guarantee it enforces is unchanged and is the one that matters: no single player can ever be paid
-- twice for one seam, however many times a grant is attempted. A row's `maxPaidMiners` bounds how many
-- DIFFERENT people one seam can pay, and MiningService applies that bound before calling in.
local paidDeposits: { [string]: boolean } = {}

local function depositLatchKey(depositId: number, playerId: Types.PlayerId): string
	return string.format("%d:%d", depositId, playerId)
end
-- Deposits each player landed at least one strike on, for "started" vs "abandoned".
local touchedDeposits: { [Types.PlayerId]: { [number]: boolean } } = {}
local depositsByDepth: { [number]: number } = {}
local emitted: { [Types.PlayerId]: boolean } = {}

-- The run's identity, stamped into every transaction id so that two different runs can never collide
-- on one, and a replayed transition from a previous run is rejected by the persistence log.
local currentRunId = ""
local currentTierId = 1
local currentPayoutPermille = 1000

-- THE PARTY BONUS LEDGER. Members of this expedition, who has resolved, and how.
local partyMembers: { [Types.PlayerId]: boolean } = {}
local partySize = 0
local anyoneDied = false
-- Players who extracted alive, and what their bag was worth, kept so the retroactive bonus can be
-- computed from the SAME numbers the base payout used rather than from a bag that no longer exists.
local extractedValues: { [Types.PlayerId]: number } = {}
-- The composed cave x contract scalar each player's base payout was actually settled at. The party
-- bonus is reconstructed arithmetically from `extractedValues` after the bag is gone, so it has to
-- reconstruct it at the SAME rate — otherwise a player who ran a contract would be paid a bonus
-- computed against a run they did not have, and the two credits would stop summing to one bonused
-- extraction. Defaults to the plain cave rate for anyone who signed nothing.
local extractedRunPermille: { [Types.PlayerId]: number } = {}
-- THE BET EACH MEMBER SIGNED, snapshotted at descent and cleared from their profile in the same
-- breath (see `beginRun`). "Consumed by the run that actually starts" is the rule, and a snapshot is
-- the only shape that holds it on every exit path at once: a death, a disconnect, an empty-handed
-- extraction and a normal cash-out all leave the profile field already blank, because it was blanked
-- on the way down rather than on the way out.
--
-- Reading it live from the profile instead — which is what this did first — leaked a contract into
-- the NEXT expedition every time a run ended any way other than a paying extraction.
local runBets: { [Types.PlayerId]: { contractId: string?, wagerDepth: number? } } = {}
local bonusPaid: { [Types.PlayerId]: boolean } = {}
-- A player may take their already-banked base payout back to the main lobby before the rest of the
-- expedition resolves. That is a deliberate exit, so only that player gives up the pending teamwork
-- credit; the remaining party is not punished for their choice.
local bonusForfeited: { [Types.PlayerId]: boolean } = {}
local resolved: { [Types.PlayerId]: boolean } = {}

local function transactionId(kind: string, playerId: Types.PlayerId): string
	return string.format("%s:%s:%d", currentRunId, kind, playerId)
end

-- Called by RunOrchestrator as an expedition begins. The run id must be unique per expedition on this
-- server for the transaction ids derived from it to be unique.
function ExtractionService.beginRun(runId: string, tierId: number, memberIds: { Types.PlayerId })
	currentRunId = runId
	currentTierId = tierId
	local tier = Interfaces.CaveTiers.get(tierId)
	currentPayoutPermille = if tier ~= nil then tier.payoutPermille else 1000
	table.clear(partyMembers)
	table.clear(extractedValues)
	table.clear(extractedRunPermille)
	table.clear(runBets)
	table.clear(bonusPaid)
	table.clear(bonusForfeited)
	table.clear(resolved)
	anyoneDied = false
	partySize = 0
	for _, playerId in memberIds do
		if not partyMembers[playerId] then
			partyMembers[playerId] = true
			partySize += 1
		end
	end

	-- TAKE EACH MEMBER'S BET AND BLANK IT ON THE PROFILE, in that order, before a single floor exists.
	-- After this loop the run owns the bet and the profile owns nothing, so there is no exit path —
	-- death, disconnect, empty-handed extraction, server crash — that can carry it into the next
	-- expedition.
	for playerId in partyMembers do
		local profile = Interfaces.Persistence.get(playerId)
		local contractId = profile.activeContractId

		-- RE-VALIDATE PARTY SIZE AT DESCENT, not only at signing. A player could sign "everyone must
		-- get out" alongside a friend and then descend alone once that friend left the lobby, which
		-- would pay a party contract for a run that cannot lose it. The size that matters is the one
		-- standing in the elevator.
		if contractId ~= nil then
			local contract = LampRules.getContract(contractId)
			if contract == nil or partySize < contract.minPartySize then
				contractId = nil
			end
		end

		runBets[playerId] = { contractId = contractId, wagerDepth = profile.activeWagerDepth }
		Interfaces.LampNetwork.clearPending(playerId)
	end
end

function ExtractionService.runId(): string
	return currentRunId
end

-- The contract this player is running under, from the descent snapshot. Nil once it has been voided,
-- which is what makes "the rule was broken" and "there was never a contract" the same thing to every
-- consumer downstream — no caller has to know which happened.
function ExtractionService.contractFor(playerId: Types.PlayerId): string?
	local bet = runBets[playerId]
	return if bet ~= nil then bet.contractId else nil
end

-- Lose this player's contract for the rest of the run. Irreversible on purpose: a rule you broke and
-- then stopped breaking is still a rule you broke, and a contract that could be un-voided would make
-- "step out of the tether for a moment" a free action.
--
-- The wager is deliberately untouched. It is not a rule you can break — you either mined deep enough
-- or you did not — so nothing that voids a contract should ever cost somebody their wager as well.
function ExtractionService.voidContract(playerId: Types.PlayerId, reason: string)
	local bet = runBets[playerId]
	if bet == nil or bet.contractId == nil then
		return
	end
	Telemetry.event("contract_voided", playerId, {
		runId = currentRunId,
		contract = bet.contractId,
		reason = reason,
	})
	bet.contractId = nil
end

function ExtractionService.noteDepositSpawned(depth: number)
	depositsByDepth[depth] = (depositsByDepth[depth] or 0) + 1
end

function ExtractionService.noteDepositTouched(playerId: Types.PlayerId, depositId: number)
	local touched = touchedDeposits[playerId]
	if touched == nil then
		touched = {}
		touchedDeposits[playerId] = touched
	end
	touched[depositId] = true
end

-- THE GRANT. Returns how many units were actually added — zero when this deposit already paid out or
-- when the carry cap is reached. The caller must have already established that this player is the one
-- who broke this seam.
-- `units` overrides the default per-seam yield, so a deposit row can be worth more or less than a
-- Standard one (Config/Mining.rows). Validated rather than trusted: a non-integer, negative or absurd
-- count falls back to the configured default instead of minting whatever it was handed.
function ExtractionService.grantForDeposit(
	playerId: Types.PlayerId,
	depositId: number,
	originGlobalDepth: number,
	units: number?
): number
	local state = PlayerState.get(playerId)
	if state == nil then
		return 0
	end
	-- Latch 1. A second grant for the same seam to the SAME player adds nothing, whatever called it.
	local latch = depositLatchKey(depositId, playerId)
	if paidDeposits[latch] then
		return 0
	end
	paidDeposits[latch] = true

	local fallback = CargoRules.unitsPerDeposit()
	local yield = fallback
	if units ~= nil and units == units and units > 0 and units % 1 == 0 and units <= CargoRules.maxCargoUnits() then
		yield = units
	end

	local run = state.rawWax
	local cargo, added = CargoRules.grant(run.cargo, originGlobalDepth, yield)
	run.cargo = cargo
	run.unitsAcquired += added
	if added > 0 then
		-- Grown with exactly what the bag accepted, so the two can never disagree about where a unit
		-- came from.
		run.acquiredByDepth = (CargoRules.grant(run.acquiredByDepth, originGlobalDepth, added))
	end
	return added
end

-- The deepest global depth this player actually mined at, from the origin stamps on what they
-- acquired. This — not where they happened to cash in — is what a Wager Board bet resolves against,
-- for the same reason a unit is priced by the floor it came out of: walking shallow cargo deeper
-- must never be worth anything.
local function deepestMinedDepth(run: Types.RawWaxRun): number
	local deepest = 0
	for _, stack in run.acquiredByDepth.stacks do
		if stack.units > 0 and stack.originDepth > deepest then
			deepest = stack.originDepth
		end
	end
	return deepest
end

-- The Lamp Network scalar this player's run settles at, resolved from the bet SNAPSHOTTED at descent
-- rather than from the profile — the profile's copy was blanked on the way down (see `beginRun`).
--
-- Nothing here decides whether a contract's RULE was kept. That is the run's business, and a broken
-- rule is expressed by clearing this player's `contractId` in `runBets`, never by this function
-- trying to reconstruct what happened in the cave.
-- This player's contract after every LIVE void condition is applied.
--
-- Two kinds of void exist and they are handled deliberately differently. A rule broken by an ACTION —
-- walking out of a tether — is voided the moment it happens, by clearing the snapshot
-- (`voidContract`), because the player should be told immediately rather than at the brazier. A rule
-- broken by a STATE — somebody in the party died — is evaluated here instead, because the state can
-- arrive after a member has already cashed out, and Both Lamps must be able to reach back and take
-- the contract off a player who was already home.
local function liveContractFor(playerId: Types.PlayerId): string?
	local bet = runBets[playerId]
	if bet == nil or bet.contractId == nil then
		return nil
	end
	local effect = ContractRules.effectFor(bet.contractId)
	if effect.voidsOnPartyDeath and anyoneDied then
		return nil
	end
	return bet.contractId
end

local function contractPermilleFor(playerId: Types.PlayerId, run: Types.RawWaxRun): number
	local bet = runBets[playerId]
	if bet == nil then
		return LampRules.resolvePermille(nil, nil, 0)
	end
	return LampRules.resolvePermille(liveContractFor(playerId), bet.wagerDepth, deepestMinedDepth(run))
end

-- The depth below which units stop paying under this player's contract, or nil. Read alongside the
-- scalar everywhere, because the two halves of The Long Descent — "shallow units are worth nothing"
-- and "everything else pays 1.6x" — are one rule and must never be applied separately.
local function payingDepthFor(playerId: Types.PlayerId): number?
	local effect = ContractRules.effectFor(liveContractFor(playerId))
	return if effect.minimumPayingDepth > 0 then effect.minimumPayingDepth else nil
end

-- What the player's bag is worth if they cashed out right now. Read-only: used by the brazier preview
-- and nothing else. Deliberately the same call the commit uses, so the number shown and the number
-- paid cannot drift apart — including the contract scalar, so a player under a contract sees the
-- contract's number at the brazier rather than a surprise on the results card.
function ExtractionService.previewValue(playerId: Types.PlayerId): ExtractionValue.ValueBreakdown?
	local state = PlayerState.get(playerId)
	if state == nil then
		return nil
	end
	return ExtractionValue.compute(
		state.rawWax.cargo,
		currentPayoutPermille,
		false,
		contractPermilleFor(playerId, state.rawWax),
		payingDepthFor(playerId)
	)
end

function ExtractionService.carriedUnits(playerId: Types.PlayerId): number
	local state = PlayerState.get(playerId)
	return if state ~= nil then state.rawWax.cargo.total else 0
end

-- What the "everyone came back" bonus WOULD add to this bag, if the whole party makes it out. Zero on
-- a solo run and zero once somebody has died — the moment the bonus becomes unreachable the preview
-- stops offering it, so the number at the brazier never promises money that cannot arrive.
function ExtractionService.potentialPartyBonus(playerId: Types.PlayerId): number
	local state = PlayerState.get(playerId)
	if state == nil then
		return 0
	end
	if not ExtractionValue.partyBonusApplies(partySize, anyoneDied) then
		return 0
	end
	-- At the same rate the base payout will settle at, contract included, so the brazier's preview of
	-- the bonus matches the credit that actually arrives afterwards.
	return ExtractionValue.partyBonusDelta(
		state.rawWax.cargo,
		currentPayoutPermille,
		contractPermilleFor(playerId, state.rawWax),
		payingDepthFor(playerId)
	)
end

function ExtractionService.hasUnresolvedPartyMember(playerId: Types.PlayerId): boolean
	for memberId in partyMembers do
		if memberId ~= playerId and not resolved[memberId] then
			return true
		end
	end
	return false
end

-- The still-pending group credit for a player who has already banked their base extraction. This is
-- display-only and reconstructed from the exact base/rate snapshot the eventual transaction uses.
function ExtractionService.pendingPartyBonus(playerId: Types.PlayerId): number
	if
		bonusPaid[playerId]
		or bonusForfeited[playerId]
		or not ExtractionValue.partyBonusApplies(partySize, anyoneDied)
	then
		return 0
	end
	local baseValue = extractedValues[playerId]
	if baseValue == nil or baseValue <= 0 then
		return 0
	end
	local runPermille = extractedRunPermille[playerId] or currentPayoutPermille
	local withCave = ExtractionValue.scale(baseValue, runPermille)
	local withBonus = ExtractionValue.scale(withCave, Config.Extraction.partyBonusPermille)
	return math.max(0, withBonus - withCave)
end

-- EXTRACTION. Called by the brazier commit AFTER it has validated that this player may cash out.
--
-- The order here is the whole design and must not be rearranged:
--   1. latch the run so a concurrent second commit cannot enter,
--   2. price the bag,
--   3. attempt the profile credit,
--   4. clear the bag ONLY if the credit landed; otherwise release the latch and keep it.
--
-- A duplicate transaction (the persistence layer recognising an id it has already applied) counts as
-- success: the money is genuinely in the account, and the correct response to a retry is to finish
-- the run rather than to pay again.
function ExtractionService.extract(playerId: Types.PlayerId, globalDepth: number): ExtractionOutcome
	local state = PlayerState.get(playerId)
	if state == nil then
		return {
			ok = false,
			units = 0,
			payout = 0,
			balance = 0,
			baseValue = 0,
			cavePayoutPermille = currentPayoutPermille,
			failure = "NoRunState",
		}
	end
	local run = state.rawWax
	-- Latch 2. A second commit for this run pays nothing.
	if run.extracted then
		return {
			ok = true,
			units = run.unitsExtracted,
			payout = run.currencyCredited,
			balance = Interfaces.Persistence.get(playerId).currency,
			baseValue = 0,
			cavePayoutPermille = currentPayoutPermille,
			failure = "AlreadyExtracted",
		}
	end
	run.extracted = true

	local contractPermille = contractPermilleFor(playerId, run)
	local breakdown =
		ExtractionValue.compute(run.cargo, currentPayoutPermille, false, contractPermille, payingDepthFor(playerId))
	if breakdown.units <= 0 then
		-- Nothing to bank. Still a completed extraction: the run is over and the latch stays set.
		run.unitsExtracted = 0
		run.extractionDepth = globalDepth
		resolved[playerId] = true
		return {
			ok = true,
			units = 0,
			payout = 0,
			balance = Interfaces.Persistence.get(playerId).currency,
			baseValue = 0,
			cavePayoutPermille = currentPayoutPermille,
		}
	end

	local id = transactionId("extract", playerId)
	local result = Interfaces.Persistence.applyTransaction(playerId, id, breakdown.total)
	if not result.ok then
		-- THE FAILURE PATH. The credit did not land, so the cargo must not be cleared and the run must
		-- not be marked extracted — the player keeps exactly what they were not paid for and may try
		-- the brazier again. This is the one branch that decides whether a bad write costs a player a
		-- run or costs the game its integrity.
		run.extracted = false
		Telemetry.event("extraction_failed", playerId, {
			runId = currentRunId,
			reason = result.failure,
			units = breakdown.units,
			wouldHavePaid = breakdown.total,
		})
		return {
			ok = false,
			units = 0,
			payout = 0,
			balance = result.balance,
			baseValue = breakdown.baseValue,
			cavePayoutPermille = currentPayoutPermille,
			failure = result.failure,
		}
	end

	-- Committed. Now, and only now, does the cargo leave the bag.
	local cleared, extractedUnits = CargoRules.clear(run.cargo)
	run.cargo = cleared
	run.unitsExtracted = extractedUnits
	run.extractionDepth = globalDepth
	run.extractionId = id
	run.currencyCredited = breakdown.total
	extractedValues[playerId] = breakdown.baseValue
	extractedRunPermille[playerId] = math.floor(currentPayoutPermille * breakdown.contractPermille / 1000)
	resolved[playerId] = true

	local profile = Interfaces.Persistence.get(playerId)
	profile.lifetimeRawWaxExtracted += extractedUnits
	-- What The Pay Table reads back in the hub (LAMP-NETWORK.md N1). Display only: it is written after
	-- the credit has already landed, so a failure to save it can cost a readout and never a payout.
	profile.lastRunBreakdown = {
		units = breakdown.units,
		baseValue = breakdown.baseValue,
		cavePayoutPermille = breakdown.cavePayoutPermille,
		partyBonusPermille = breakdown.partyBonusPermille,
		contractPermille = breakdown.contractPermille,
		total = breakdown.total,
	}
	-- No bet to clear here: it was taken off the profile at descent (see `beginRun`), which is what
	-- makes every other exit path safe too.
	Interfaces.Persistence.save(playerId, profile)

	Telemetry.event("extraction_paid", playerId, {
		runId = currentRunId,
		tier = currentTierId,
		units = extractedUnits,
		baseValue = breakdown.baseValue,
		payout = breakdown.total,
		duplicate = result.duplicate,
		globalDepth = globalDepth,
		origins = CargoRules.formatOrigins(run.acquiredByDepth),
	})

	return {
		ok = true,
		units = extractedUnits,
		payout = breakdown.total,
		balance = result.balance,
		baseValue = breakdown.baseValue,
		cavePayoutPermille = currentPayoutPermille,
	}
end

-- TERMINAL DEATH. Half the bag lands on the body for the party to salvage; half shatters. Returns
-- (dropped, shattered) so the caller can report both, and the cargo that drops is handed to the
-- remains deposit by the caller — this function only decides the split and empties the bag.
function ExtractionService.splitOnDeath(playerId: Types.PlayerId): (Types.RawWaxCargo, number, number)
	local state = PlayerState.get(playerId)
	if state == nil then
		return CargoRules.newCargo(), 0, 0
	end
	local run = state.rawWax
	if run.cargo.total <= 0 then
		return CargoRules.newCargo(), 0, 0
	end

	local dropped, shattered = CargoRules.split(run.cargo, Config.Extraction.deathDropPermille)
	run.cargo = CargoRules.newCargo()
	run.unitsDropped += dropped.total
	run.unitsLost += shattered.total
	Telemetry.event("cargo_death_split", playerId, {
		runId = currentRunId,
		dropped = dropped.total,
		shattered = shattered.total,
		origins = CargoRules.formatOrigins(dropped),
	})
	return dropped, dropped.total, shattered.total
end

-- DISCONNECT. The whole bag drops where they stood, owner-locked for the grace window. Nothing is
-- destroyed and nothing is held in memory: the pile IS the hold, which is what keeps the cargo in
-- exactly one place at every instant.
function ExtractionService.dropOnDisconnect(playerId: Types.PlayerId): (Types.RawWaxCargo, number)
	local state = PlayerState.get(playerId)
	if state == nil then
		return CargoRules.newCargo(), 0
	end
	local run = state.rawWax
	if run.cargo.total <= 0 then
		return CargoRules.newCargo(), 0
	end
	local dropped = run.cargo
	run.cargo = CargoRules.newCargo()
	run.unitsDropped += dropped.total
	Telemetry.event("cargo_disconnect_drop", playerId, {
		runId = currentRunId,
		units = dropped.total,
		graceSeconds = Config.Extraction.disconnectGraceSeconds,
		origins = CargoRules.formatOrigins(dropped),
	})
	return dropped, dropped.total
end

-- Absorb a recovered pile into a living player's bag. Returns how many units actually moved and what
-- would not fit, so the caller can leave the surplus on the ground.
function ExtractionService.receive(playerId: Types.PlayerId, incoming: Types.RawWaxCargo): (number, Types.RawWaxCargo)
	local state = PlayerState.get(playerId)
	if state == nil then
		return 0, incoming
	end
	local run = state.rawWax
	local combined, leftover, moved = CargoRules.merge(run.cargo, incoming)
	run.cargo = combined
	-- Recovered units count as acquired by THIS run, so the reconciliation identity still closes:
	-- acquired == lost + dropped + extracted + carried.
	run.unitsAcquired += moved
	return moved, leftover
end

-- How much more this player could carry, for a partial pile claim.
function ExtractionService.carryRoom(playerId: Types.PlayerId): number
	local state = PlayerState.get(playerId)
	if state == nil then
		return 0
	end
	return math.max(0, CargoRules.maxCargoUnits() - state.rawWax.cargo.total)
end

-- A death is the only thing that cancels the party bonus. Recorded separately from `resolved` because
-- the two answer different questions: "is this run over for them" and "did they make it".
function ExtractionService.noteDeath(playerId: Types.PlayerId)
	if partyMembers[playerId] then
		anyoneDied = true
	end
	resolved[playerId] = true
end

-- A disconnect resolves a player without cancelling the bonus for the rest of the party (see
-- Config/Extraction for why). They cannot receive it themselves if they leave mid-run — but the
-- players who did walk out are not punished for someone else's connection.
--
-- GUARDED FOR A PLAYER WHO ALREADY RESOLVED. A finished player stays in RunOrchestrator's runner set
-- until they actually leave the server, so "extract, then close the client" — an entirely ordinary
-- sequence — still runs the disconnect path afterwards. If this function unconditionally cleared
-- `extractedValues`, that would erase an already-earned party-bonus eligibility for someone who
-- genuinely made it out, the instant they closed the game. `resolved[playerId]` is only ever set true
-- by an EARLIER extraction or death, so finding it already true here means this disconnect is not the
-- thing that resolved them and must not touch their standing.
function ExtractionService.noteDisconnect(playerId: Types.PlayerId)
	if resolved[playerId] then
		return
	end
	resolved[playerId] = true
	extractedValues[playerId] = nil
	extractedRunPermille[playerId] = nil
	runBets[playerId] = nil
end

-- A resolved survivor has chosen to leave for the main lobby before the expedition finishes. Their
-- base extraction is already durable and untouched; only the separate, not-yet-paid party credit is
-- made permanently ineligible. Returns true exactly once so callers can deduplicate announcements.
function ExtractionService.forfeitPartyBonus(playerId: Types.PlayerId): boolean
	local state = PlayerState.get(playerId)
	if
		not partyMembers[playerId]
		or not resolved[playerId]
		or state == nil
		or not state.rawWax.extracted
		or bonusPaid[playerId]
		or bonusForfeited[playerId]
	then
		return false
	end
	local pendingBonus = ExtractionService.pendingPartyBonus(playerId)
	bonusForfeited[playerId] = true
	Telemetry.event("party_bonus_forfeited", playerId, {
		runId = currentRunId,
		pendingBonus = pendingBonus,
	})
	return true
end

-- THE RETROACTIVE PARTY BONUS. Called whenever a player resolves; pays out only once the LAST member
-- has, and only if nobody died.
--
-- Paid as a separate transaction per player, keyed by its own id, so it is independently idempotent:
-- calling this twice pays once, and a base payout that already landed is never recomputed. The amount
-- is `partyBonusDelta` of the SAME base value the original payout used, which is why
-- `extractedValues` holds that number rather than re-reading a bag that has since been emptied.
--
-- Returns a map of playerId -> bonus paid, for the caller to report.
function ExtractionService.settlePartyBonus(): { [Types.PlayerId]: number }
	local paid: { [Types.PlayerId]: number } = {}
	if partySize < Config.Extraction.partyBonusMinimumMembers then
		return paid
	end
	if not ExtractionValue.partyBonusApplies(partySize, anyoneDied) then
		return paid
	end
	-- Everyone must be done. A member still in the cave means the run is not over.
	for playerId in partyMembers do
		if not resolved[playerId] then
			return paid
		end
	end

	for playerId, baseValue in extractedValues do
		if
			bonusPaid[playerId]
			or not ExtractionValue.partyBonusApplies(partySize, anyoneDied, bonusForfeited[playerId])
			or baseValue <= 0
		then
			continue
		end
		-- The bonus is a function of the base value alone, so the delta is reconstructed arithmetically
		-- rather than from a bag — the bag was emptied when the base payout landed, and re-deriving the
		-- value from anything else is how the two credits would drift apart.
		-- At the rate this player's base payout actually settled at, contract included. Falling back to
		-- the plain cave rate covers anyone who signed nothing.
		local runPermille = extractedRunPermille[playerId] or currentPayoutPermille
		local withCave = ExtractionValue.scale(baseValue, runPermille)
		local withBonus = ExtractionValue.scale(withCave, Config.Extraction.partyBonusPermille)
		local delta = math.max(0, withBonus - withCave)
		if delta <= 0 then
			bonusPaid[playerId] = true
			continue
		end
		local result = Interfaces.Persistence.applyTransaction(playerId, transactionId("partybonus", playerId), delta)
		if result.ok then
			bonusPaid[playerId] = true
			paid[playerId] = delta
			local state = PlayerState.get(playerId)
			if state ~= nil then
				state.rawWax.partyBonusCredited = delta
			end
			Telemetry.event("party_bonus_paid", playerId, {
				runId = currentRunId,
				partySize = partySize,
				baseValue = baseValue,
				bonus = delta,
			})
		end
		-- A failed bonus write leaves `bonusPaid` false, so the next resolve attempt retries it. The
		-- transaction id is stable, so a retry that races a late success still pays exactly once.
	end
	return paid
end

-- What the results card shows for cargo.
function ExtractionService.resultsPayload(playerId: Types.PlayerId): { [string]: unknown }?
	local state = PlayerState.get(playerId)
	if state == nil then
		return nil
	end
	local run = state.rawWax
	return {
		acquired = run.unitsAcquired,
		extracted = run.unitsExtracted,
		dropped = run.unitsDropped,
		lost = run.unitsLost,
		carried = run.cargo.total,
		payout = run.currencyCredited,
		partyBonus = run.partyBonusCredited,
		originDepths = CargoRules.formatOrigins(run.acquiredByDepth),
	}
end

local function countDeposits(playerId: Types.PlayerId): (number, number)
	local touched = touchedDeposits[playerId]
	if touched == nil then
		return 0, 0
	end
	local started = 0
	local abandoned = 0
	for depositId in touched do
		started += 1
		if not paidDeposits[depositId] then
			abandoned += 1
		end
	end
	return started, abandoned
end

local function reachableDeposits(state: Types.PlayerRunState): number
	local total = 0
	for depth = 1, state.depth do
		total += depositsByDepth[depth] or 0
	end
	return total
end

-- One structured line per player per run. `reconciliationError` is the important field: non-zero
-- means units appeared or vanished outside CargoRules, which is the only way this system could mint
-- currency, and it should be alerted on rather than read.
function ExtractionService.emitRunSummary(
	playerId: Types.PlayerId,
	outcome: Types.WaxRunOutcome,
	livingWaxRemaining: number
)
	if emitted[playerId] then
		return
	end
	local state = PlayerState.get(playerId)
	if state == nil then
		return
	end
	emitted[playerId] = true
	local run = state.rawWax
	local started, abandoned = countDeposits(playerId)
	Telemetry.event("raw_wax_run", playerId, {
		runId = currentRunId,
		tier = currentTierId,
		outcome = outcome,
		startDepth = state.startDepth,
		endGlobalDepth = PlayerState.globalDepth(state),
		extractionDepth = run.extractionDepth,
		depositsReachable = reachableDeposits(state),
		depositsStarted = started,
		depositsAbandoned = abandoned,
		depositsCompleted = state.depositsMinedThisRun,
		acquired = run.unitsAcquired,
		dropped = run.unitsDropped,
		lost = run.unitsLost,
		extracted = run.unitsExtracted,
		carried = run.cargo.total,
		payout = run.currencyCredited,
		partyBonus = run.partyBonusCredited,
		originDepths = CargoRules.formatOrigins(run.acquiredByDepth),
		averageOriginDepth = string.format("%.2f", CargoRules.averageOriginDepth(run.acquiredByDepth)),
		livingWaxRemaining = string.format("%.2f", livingWaxRemaining),
		reconciliationError = run.unitsAcquired
			- run.unitsLost
			- run.unitsDropped
			- run.unitsExtracted
			- run.cargo.total,
	})
end

function ExtractionService.clear(playerId: Types.PlayerId)
	touchedDeposits[playerId] = nil
	emitted[playerId] = nil
end

function ExtractionService.reset()
	table.clear(paidDeposits)
	table.clear(touchedDeposits)
	table.clear(depositsByDepth)
	table.clear(emitted)
	table.clear(partyMembers)
	table.clear(extractedValues)
	table.clear(extractedRunPermille)
	table.clear(runBets)
	table.clear(bonusPaid)
	table.clear(bonusForfeited)
	table.clear(resolved)
	partySize = 0
	anyoneDied = false
	currentRunId = ""
	currentTierId = 1
	currentPayoutPermille = 1000
end

return ExtractionService
