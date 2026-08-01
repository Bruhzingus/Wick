--!strict
-- ProfileStore-backed player profiles. Studio always uses ProfileStore.Mock so local tests cannot
-- overwrite production data. This remains the single persistence boundary for gameplay systems.
--
-- PHASE 8 MADE THIS A LEDGER RATHER THAN A SCRATCHPAD. Currency used to be a plain field that any
-- caller could `get`, add to, and `save` back. That read-modify-write is fine exactly until two of
-- them interleave or one of them retries, at which point it either loses a payout or pays one twice.
-- Now every currency movement goes through `applyTransaction`, which:
--
--   * mutates the live session data DIRECTLY rather than through a get/save round trip, so there is
--     no window between reading a balance and writing it back;
--   * is keyed by a caller-supplied transaction id, recorded in the profile itself, so replaying the
--     same credit is a no-op that returns the ORIGINAL result rather than a second payment;
--   * refuses to run at all without an active session, so a payout can never land in the temporary
--     fallback cache and then be discarded when the real profile loads.
--
-- THAT LAST POINT IS THE ONE THAT MATTERS MOST. The old `save` quietly wrote into a fallback table
-- when ProfileStore had not finished loading. For cosmetic counters that is a harmless best-effort;
-- for currency it is a way to be paid into a table that is about to be thrown away. Transactions
-- therefore FAIL LOUDLY on an unloaded profile, and the caller is expected to keep the cargo rather
-- than pretend it was banked.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(script.Parent.Parent.Types)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

-- How many recent transaction ids a profile remembers. Deduplication only has to survive the window
-- in which a retry could plausibly arrive (one run, one reconnect), so this is deliberately a small
-- ring rather than unbounded history — an unbounded list on a profile is a DataStore size limit
-- waiting to be hit years from now.
local TRANSACTION_HISTORY = 32

-- One resolved extraction, kept only so The Pay Table can print the last one. Statistics, never
-- spent, never read by any rule.
export type RunBreakdown = {
	units: number,
	baseValue: number,
	cavePayoutPermille: number,
	partyBonusPermille: number,
	contractPermille: number,
	total: number,
}

export type Profile = {
	schemaVersion: number,
	currency: number,
	-- Caves bought outright, by STABLE FAMILY ID ("STONE" / "MOSS" / "ICE", Config/CaveFamilies).
	-- Unordered set.
	--
	-- WHY THE STRING AND NOT THE NUMERIC TIER. Access used to be recorded as a tier ordinal, which
	-- only means anything relative to the order the tier table happens to be written in. A stable id
	-- survives rows being reordered, renamed, or repriced, and it is the same id the family profile
	-- is keyed by — so what a player owns is described in the same vocabulary as what they own it of.
	-- The numeric id remains the ADDRESS a lobby elevator or a shop card uses; `Interfaces/CaveTiers`
	-- is the single place the two are translated.
	ownedCaveFamilies: { string },
	-- LAMP NETWORK nodes bought outright, by stable node id (Config/LampNetwork). Unordered set.
	--
	-- DELIBERATELY UNRELATED TO `ownedCaveFamilies`, and there is no mapping between them: cave tiers
	-- decide which cave and what admission costs, lamp nodes decide what a cave can CONTAIN and what
	-- you may agree to. A player who owns The Deep starts this track at zero nodes like everybody
	-- else. Nothing grants a node retroactively.
	--
	-- Written ONLY by `grantLampNode`, never by `save` — see both for why.
	ownedLampNodes: { string },
	-- The contract accepted for the next run, or nil. Consumed by the run that actually starts, and
	-- mutually exclusive with `activeWagerDepth`: one bet per run, never two.
	activeContractId: string?,
	-- The depth named at The Wager Board for the next run, or nil. Validated at acceptance against the
	-- player's own `deepestFloor`, so a wager is always a personal record attempt.
	activeWagerDepth: number?,
	-- What the last extraction actually paid, for The Pay Table to read back. Display only.
	lastRunBreakdown: RunBreakdown?,
	cosmetics: { string },
	runsCompleted: number,
	deepestFloor: number,
	totalWaxDelivered: number,
	-- Lifetime Raw Wax units actually walked out of a cave. A statistic, never spent — kept separate
	-- from `currency` precisely so that spending can never corrupt the record of what was earned.
	lifetimeRawWaxExtracted: number,
	-- Recent transaction ids, oldest first. THE deduplication mechanism (see `applyTransaction`).
	recentTransactions: { string },
	-- WHERE THIS PLAYER IS MID-RUN, if anywhere. Written when an expedition starts and cleared when it
	-- resolves; read on join to decide whether to send them back into it (see RejoinService).
	--
	-- Two identifiers because they answer different questions. `activeRunServer` is the reserved
	-- server's PrivateServerId, which the destination can compare against its own to know "am I
	-- already where I am supposed to be". `activeRunAccessCode` is the reservation token, which is the
	-- ONLY thing that can actually teleport somebody back into that specific server — and which
	-- Roblox never hands out unless you reserve the server explicitly (see PartyLobbyService).
	activeRunServer: string?,
	activeRunAccessCode: string?,
	activeRunId: string?,
	activeRunStartedAt: number?,
}

export type TransactionResult = {
	ok: boolean,
	-- Balance AFTER the transaction. On a replay this is the balance the ORIGINAL application left,
	-- which is what makes a retried credit safe to report to the player.
	balance: number,
	-- True when this id had already been applied and nothing changed.
	duplicate: boolean,
	-- Set when `ok` is false, so callers can distinguish "profile not loaded, keep the cargo" from
	-- "they genuinely could not afford it".
	failure: string?,
}

export type PersistenceInterface = {
	initPlayer: (player: Player) -> boolean,
	closePlayer: (playerId: Types.PlayerId) -> (),
	releaseForTeleport: (playerIds: { Types.PlayerId }) -> boolean,
	get: (playerId: Types.PlayerId) -> Profile,
	save: (playerId: Types.PlayerId, profile: Profile) -> (),
	isLoaded: (playerId: Types.PlayerId) -> boolean,
	applyTransaction: (playerId: Types.PlayerId, transactionId: string, delta: number) -> TransactionResult,
	hasTransaction: (playerId: Types.PlayerId, transactionId: string) -> boolean,
	grantLampNode: (playerId: Types.PlayerId, nodeId: string) -> boolean,
	ownsLampNode: (playerId: Types.PlayerId, nodeId: string) -> boolean,
}

local DEFAULT_PROFILE: Profile = {
	-- v1 -> v2: currency became the extracted-Raw-Wax balance, `unlockedCaveTier` (a derived
	-- threshold) became `ownedCaveTiers` (explicit purchases), and the transaction log arrived.
	-- v2 -> v3: the Lamp Network arrived. Four purely additive fields, all defaulting to
	-- empty/unpurchased. Nothing is granted retroactively and nothing existing changes meaning.
	-- v3 -> v4: cave tiers became cave FAMILIES. `ownedCaveTiers` (an ordinal) became
	-- `ownedCaveFamilies` (a stable id). A pure rename of what is already owned — see `migrate`.
	schemaVersion = 4,
	currency = 0,
	ownedCaveFamilies = {},
	ownedLampNodes = {},
	activeContractId = nil,
	activeWagerDepth = nil,
	lastRunBreakdown = nil,
	cosmetics = {},
	runsCompleted = 0,
	deepestFloor = 0,
	totalWaxDelivered = 0,
	lifetimeRawWaxExtracted = 0,
	recentTransactions = {},
	activeRunServer = nil,
	activeRunAccessCode = nil,
	activeRunId = nil,
	activeRunStartedAt = nil,
}

local function copyBreakdown(source: RunBreakdown?): RunBreakdown?
	if source == nil then
		return nil
	end
	return {
		units = source.units,
		baseValue = source.baseValue,
		cavePayoutPermille = source.cavePayoutPermille,
		partyBonusPermille = source.partyBonusPermille,
		contractPermille = source.contractPermille,
		total = source.total,
	}
end

local function copyProfile(source: Profile): Profile
	return {
		schemaVersion = source.schemaVersion,
		currency = source.currency,
		ownedCaveFamilies = table.clone(source.ownedCaveFamilies),
		ownedLampNodes = table.clone(source.ownedLampNodes),
		activeContractId = source.activeContractId,
		activeWagerDepth = source.activeWagerDepth,
		lastRunBreakdown = copyBreakdown(source.lastRunBreakdown),
		cosmetics = table.clone(source.cosmetics),
		runsCompleted = source.runsCompleted,
		deepestFloor = source.deepestFloor,
		totalWaxDelivered = source.totalWaxDelivered,
		lifetimeRawWaxExtracted = source.lifetimeRawWaxExtracted,
		recentTransactions = table.clone(source.recentTransactions),
		activeRunServer = source.activeRunServer,
		activeRunAccessCode = source.activeRunAccessCode,
		activeRunId = source.activeRunId,
		activeRunStartedAt = source.activeRunStartedAt,
	}
end

local function copyDefault(): Profile
	return copyProfile(DEFAULT_PROFILE)
end

-- MIGRATION, v1 -> v2. Runs against `profile.Data` in place, after ProfileStore's own `Reconcile`
-- has filled in any missing v2 fields with defaults.
--
-- The rules, and the reasoning for each:
--
--   * CURRENCY IS KEPT AS-IS. A v1 balance was earned under the Living Wax formula, which paid on a
--     scale roughly six times larger than Phase 8's. Rescaling it would be a defensible design call
--     and an indefensible engineering one: there is no way to distinguish a legitimately-earned
--     v1 balance from one that has already been partly spent, and quietly dividing someone's savings
--     is the kind of migration players never forgive. They keep what they earned.
--   * THE OLD DERIVED UNLOCK BECOMES A REAL PURCHASE. A v1 player who had reached `unlockedCaveTier`
--     N is granted outright ownership of tiers 2..N. They passed the bar that was in front of them
--     at the time, and taking that access back — or asking them to buy it a second time — would be
--     charging twice for the same thing.
--   * NOTHING IS EVER DROPPED. Unknown/legacy fields on `profile.Data` are left untouched rather
--     than pruned, so a rollback to a v1 server finds its own fields intact.
local function migrate(data: { [string]: any })
	local version = if typeof(data.schemaVersion) == "number" then data.schemaVersion else 1

	if version < 2 then
		if typeof(data.ownedCaveTiers) ~= "table" then
			data.ownedCaveTiers = {}
		end
		local legacyUnlock = data.unlockedCaveTier
		if typeof(legacyUnlock) == "number" and legacyUnlock > 1 then
			local owned: { number } = data.ownedCaveTiers
			for tierId = 2, math.floor(legacyUnlock) do
				if table.find(owned, tierId) == nil then
					table.insert(owned, tierId)
				end
			end
		end
		if typeof(data.lifetimeRawWaxExtracted) ~= "number" then
			data.lifetimeRawWaxExtracted = 0
		end
		if typeof(data.recentTransactions) ~= "table" then
			data.recentTransactions = {}
		end
	end

	-- MIGRATION, v2 -> v3: the Lamp Network. Purely additive, and deliberately the most boring
	-- migration in the file — every new field defaults to empty/unpurchased and NOTHING is granted
	-- retroactively.
	--
	-- There is specifically NO MAPPING FROM `ownedCaveTiers`. The two systems are unrelated: tiers
	-- decide which cave and what admission costs, lamp nodes decide what a cave can contain. Granting
	-- a lamp node for having bought a cave would be inventing a purchase nobody made, and the reverse
	-- would be charging twice for one thing. Every player, however far along, starts this track at
	-- zero nodes.
	if version < 3 then
		if typeof(data.ownedLampNodes) ~= "table" then
			data.ownedLampNodes = {}
		end
		-- `activeContractId`, `activeWagerDepth` and `lastRunBreakdown` are all legitimately nil on a
		-- fresh v3 profile, so there is nothing to fill in — Reconcile has already given them their
		-- absent defaults and writing explicit nils here would say nothing.
	end

	-- MIGRATION, v3 -> v4: cave tiers became cave FAMILIES.
	--
	-- THIS IS A RENAME, NOT A GRANT AND NOT A REVOCATION. Every numeric tier a player owned is mapped
	-- to the family that now occupies that row (Config/CaveTiers documents the projection): The
	-- Descent's row IS Moss, The Deep's row IS Ice. Nobody gains access they did not buy, nobody
	-- loses access they did, and no currency moves.
	--
	-- IDEMPOTENT BY CONSTRUCTION, in both directions. Re-running it cannot duplicate an entry (each
	-- id is checked before insertion), and it cannot re-grant a family a player has since had removed
	-- by some future tool, because `ownedCaveTiers` is only READ here — a v4 profile has already had
	-- its schema version stamped, so the block is skipped entirely on every subsequent load.
	--
	-- A LEGACY ROW THAT NO LONGER MAPS IS DROPPED DELIBERATELY. If a future config removes a family,
	-- there is nothing to own; recording an id with no profile would leave dead data in the save and
	-- an ownership check that can never be satisfied. Currency is untouched either way.
	--
	-- `ownedCaveTiers` is deliberately NOT deleted. Nothing is ever dropped from `profile.Data`, so a
	-- rollback to a v3 server finds its own field exactly as it left it.
	if version < 4 then
		local existing = if typeof(data.ownedCaveFamilies) == "table" then data.ownedCaveFamilies else {}
		local legacy = if typeof(data.ownedCaveTiers) == "table" then data.ownedCaveTiers else nil
		-- The rule itself is a pure function so it can be tested without a DataStore
		-- (Tests/CaveFamilyRulesTests). There is deliberately no second copy of it here.
		data.ownedCaveFamilies = CaveFamilyRules.migrateOwnedTiers(legacy, existing)
	end

	data.schemaVersion = DEFAULT_PROFILE.schemaVersion
end

-- True if `fallback` still equals a just-created default (i.e. no gameplay mutation ever landed on
-- it). Used only to decide whether a discarded fallback is worth a loud warning.
local function fallbackIsUnmutated(fallback: Profile): boolean
	return fallback.currency == DEFAULT_PROFILE.currency
		and #fallback.ownedCaveFamilies == 0
		and #fallback.ownedLampNodes == 0
		and fallback.runsCompleted == DEFAULT_PROFILE.runsCompleted
		and fallback.deepestFloor == DEFAULT_PROFILE.deepestFloor
		and fallback.totalWaxDelivered == DEFAULT_PROFILE.totalWaxDelivered
		and fallback.lifetimeRawWaxExtracted == DEFAULT_PROFILE.lifetimeRawWaxExtracted
		and #fallback.cosmetics == 0
end

local profileStore = ProfileStore.New("WickProfiles_v1", DEFAULT_PROFILE)
if RunService:IsStudio() then
	-- ProfileStore.Mock is deliberately ephemeral and isolated from live DataStore keys.
	profileStore = profileStore.Mock
end

type LoadedProfile = typeof(profileStore:StartSessionAsync(""))

local sessions: { [Types.PlayerId]: LoadedProfile } = {}
local fallbacks: { [Types.PlayerId]: Profile } = {}
local ending: { [Types.PlayerId]: boolean } = {}

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local Persistence: PersistenceInterface

Persistence = {
	initPlayer = function(player: Player): boolean
		if sessions[player.UserId] ~= nil then
			return true
		end
		ending[player.UserId] = nil

		local profile = profileStore:StartSessionAsync(tostring(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
		if profile == nil then
			return false
		end

		profile:AddUserId(player.UserId)
		profile:Reconcile()
		-- Reconcile first (so v2 fields exist with defaults), THEN migrate (so v1 data can be read
		-- and translated into them). Reversing this order would migrate against missing fields.
		migrate(profile.Data :: any)
		sessions[player.UserId] = profile

		-- A caller can only have mutated a fallback if gameplay ran before this session activated,
		-- which the current boot order (initPlayer must succeed before a player joins any party or
		-- run) should make unreachable. Warn instead of silently discarding or blindly overwriting
		-- real loaded progress with a guessed merge.
		local fallback = fallbacks[player.UserId]
		if fallback ~= nil and not fallbackIsUnmutated(fallback) then
			warn(
				string.format(
					"[WICK] Persistence: discarding a mutated fallback profile for user %d;"
						.. " gameplay mutated state before the ProfileStore session activated.",
					player.UserId
				)
			)
		end
		fallbacks[player.UserId] = nil

		profile.OnSessionEnd:Connect(function()
			sessions[player.UserId] = nil
			if ending[player.UserId] ~= true and player.Parent == Players then
				player:Kick("Your profile opened on another server. Please rejoin.")
			end
		end)

		if player.Parent ~= Players then
			ending[player.UserId] = true
			profile:EndSession()
			ending[player.UserId] = nil
			return false
		end
		return true
	end,

	closePlayer = function(playerId: Types.PlayerId)
		local profile = sessions[playerId]
		if profile ~= nil then
			ending[playerId] = true
			profile:EndSession()
		end
		fallbacks[playerId] = nil
	end,

	-- A same-place teleport starts the destination server before PlayerRemoving is guaranteed to run
	-- in the source server. Leaving release to PlayerRemoving therefore makes the destination collide
	-- with this server's still-active ProfileStore session and pay ProfileStore's 5/10-second conflict
	-- retry cadence. Release every party member in parallel and wait for the LAST save to finish before
	-- asking Roblox to move anybody. The caller must call initPlayer again if the teleport fails and the
	-- player remains here.
	releaseForTeleport = function(playerIds: { Types.PlayerId }): boolean
		local pending = 0
		local allLoaded = true
		local seen: { [Types.PlayerId]: boolean } = {}

		for _, playerId in playerIds do
			if seen[playerId] ~= true then
				seen[playerId] = true
				local profile = sessions[playerId]
				if profile == nil or not profile:IsActive() then
					allLoaded = false
				else
					pending += 1
					task.spawn(function()
						local lastSaveStarted = false
						local released = false
						local lastSaveConnection = profile.OnLastSave:Connect(function()
							lastSaveStarted = true
						end)
						local afterSaveConnection = profile.OnAfterSave:Connect(function()
							if lastSaveStarted and not profile:IsActive() then
								released = true
							end
						end)

						ending[playerId] = true
						profile:EndSession()
						repeat
							task.wait()
						until released

						lastSaveConnection:Disconnect()
						afterSaveConnection:Disconnect()
						if sessions[playerId] == profile then
							sessions[playerId] = nil
						end
						ending[playerId] = nil
						pending -= 1
					end)
				end
			end
		end

		repeat
			task.wait()
		until pending == 0
		return allLoaded
	end,

	-- Returns a defensive copy: callers may freely mutate the result, but nothing is persisted until
	-- it is passed back to `save`. This keeps `save` a real commit point rather than a no-op that
	-- only ever ran against a table it had already been handed by reference.
	--
	-- NOTE: `currency` on this copy is a READ-ONLY VIEW. Writing it back through `save` is ignored on
	-- purpose (see below) — money moves only through `applyTransaction`.
	get = function(playerId: Types.PlayerId): Profile
		local profile = sessions[playerId]
		if profile ~= nil and profile:IsActive() then
			return copyProfile(profile.Data :: any)
		end
		local fallback = fallbacks[playerId]
		if fallback == nil then
			fallback = copyDefault()
			fallbacks[playerId] = fallback
		end
		return copyProfile(fallback)
	end,

	-- Commits the NON-CURRENCY fields of a profile. Currency and the transaction log are deliberately
	-- NOT written here even though they are present on the passed table: `save` is a last-write-wins
	-- blind overwrite, and last-write-wins is exactly the wrong semantics for money. A caller who
	-- reads a balance, waits on anything, and saves it back would silently erase any credit that
	-- landed in between. Routing every balance change through `applyTransaction` — which mutates the
	-- live session directly and never round-trips — removes that window entirely.
	--
	-- `ownedLampNodes` IS EXCLUDED FOR THE SAME REASON, and this is the one place the Lamp Network
	-- deliberately does NOT copy how `ownedCaveTiers` works. A tier is granted by read-copy-mutate-save
	-- (see Interfaces/CaveTiers), which is safe today only because nothing yields between those calls —
	-- a fragile property of the current call sites rather than of the code. A node granted through
	-- `save` could be erased by any caller that had read a profile before the purchase and wrote it
	-- back after. `grantLampNode` mutates the live session directly instead, so a node, like a balance,
	-- can never be lost to a stale write.
	save = function(playerId: Types.PlayerId, data: Profile)
		local profile = sessions[playerId]
		if profile ~= nil and profile:IsActive() then
			local stored = profile.Data :: any
			stored.schemaVersion = DEFAULT_PROFILE.schemaVersion
			stored.ownedCaveFamilies = table.clone(data.ownedCaveFamilies)
			stored.activeContractId = data.activeContractId
			stored.activeWagerDepth = data.activeWagerDepth
			stored.lastRunBreakdown = copyBreakdown(data.lastRunBreakdown)
			stored.cosmetics = table.clone(data.cosmetics)
			stored.runsCompleted = data.runsCompleted
			stored.deepestFloor = data.deepestFloor
			stored.totalWaxDelivered = data.totalWaxDelivered
			stored.lifetimeRawWaxExtracted = data.lifetimeRawWaxExtracted
			stored.activeRunServer = data.activeRunServer
			stored.activeRunAccessCode = data.activeRunAccessCode
			stored.activeRunId = data.activeRunId
			stored.activeRunStartedAt = data.activeRunStartedAt
		else
			-- No active session yet: persist the mutation into the fallback cache so it is not lost
			-- while ProfileStore is still loading (see the fallback-discard warning above). Currency
			-- never reaches here, because `applyTransaction` refuses to run without a live session —
			-- and neither do lamp nodes, because `grantLampNode` refuses for the same reason.
			local cached = copyProfile(data)
			local existing = fallbacks[playerId]
			cached.currency = if existing ~= nil then existing.currency else DEFAULT_PROFILE.currency
			cached.recentTransactions = if existing ~= nil then table.clone(existing.recentTransactions) else {}
			cached.ownedLampNodes = if existing ~= nil then table.clone(existing.ownedLampNodes) else {}
			fallbacks[playerId] = cached
		end
	end,

	isLoaded = function(playerId: Types.PlayerId): boolean
		local profile = sessions[playerId]
		return profile ~= nil and profile:IsActive()
	end,

	ownsLampNode = function(playerId: Types.PlayerId, nodeId: string): boolean
		local profile = sessions[playerId]
		if profile == nil or not profile:IsActive() then
			return false
		end
		local owned = (profile.Data :: any).ownedLampNodes
		return typeof(owned) == "table" and table.find(owned, nodeId) ~= nil
	end,

	-- THE ONLY WAY A LAMP NODE IS EVER RECORDED.
	--
	-- WHY IT MUTATES `profile.Data` DIRECTLY, exactly like `applyTransaction`: a purchase is a charge
	-- and a grant, and those two must be indivisible. `applyTransaction` never yields, and neither
	-- does this, so a caller can perform both inside a single yield-free block and no autosave, no
	-- concurrent handler and no stale `save` can ever observe or overwrite the half-finished state
	-- where the money is gone and the node is not owned. Routing the grant through `get`/`save`
	-- instead would reintroduce exactly the read-modify-write window `applyTransaction` was written
	-- to eliminate.
	--
	-- IDEMPOTENT BY CONSTRUCTION. Granting an already-owned node is a no-op that still reports true,
	-- which is what lets a retried purchase converge: `applyTransaction` recognises the replay and
	-- charges nothing, and this completes the grant that the first attempt may not have reached. The
	-- retry path IS the repair path, and it is why the game needs no refund mechanic.
	--
	-- WHY AN UNLOADED PROFILE IS A HARD FAILURE: a node written into the fallback cache would look
	-- like a purchase and then be discarded when the real profile loads. Callers must treat `false`
	-- as "this did not happen" and refuse the sale rather than charging for it.
	grantLampNode = function(playerId: Types.PlayerId, nodeId: string): boolean
		if typeof(nodeId) ~= "string" or nodeId == "" then
			return false
		end
		local profile = sessions[playerId]
		if profile == nil or not profile:IsActive() then
			return false
		end
		local data = profile.Data :: any
		if typeof(data.ownedLampNodes) ~= "table" then
			data.ownedLampNodes = {}
		end
		local owned: { string } = data.ownedLampNodes
		if table.find(owned, nodeId) == nil then
			table.insert(owned, nodeId)
		end
		return true
	end,

	hasTransaction = function(playerId: Types.PlayerId, transactionId: string): boolean
		local profile = sessions[playerId]
		if profile == nil or not profile:IsActive() then
			return false
		end
		local log = (profile.Data :: any).recentTransactions
		return typeof(log) == "table" and table.find(log, transactionId) ~= nil
	end,

	-- THE ONLY WAY CURRENCY EVER MOVES.
	--
	-- `delta` may be positive (an extraction payout) or negative (a cave fee, a purchase). The
	-- transaction is applied at most once per `transactionId`, ever, for this profile's remembered
	-- history — so the caller is free to retry on any ambiguous failure without risking a double
	-- credit or a double charge.
	--
	-- WHY IT MUTATES `profile.Data` DIRECTLY: ProfileStore persists whatever that table holds when it
	-- next autosaves. Mutating it in place means the balance change is committed the instant this
	-- function returns, with no read-modify-write window for a concurrent caller to interleave into.
	-- There is no yield anywhere in this function, so it is atomic with respect to every other script
	-- on the server.
	--
	-- WHY AN UNLOADED PROFILE IS A HARD FAILURE: writing a payout into the fallback cache would look
	-- like success and then be discarded when the real profile loads. The caller MUST treat `ok ==
	-- false` as "this did not happen" and keep the cargo unspent.
	applyTransaction = function(playerId: Types.PlayerId, transactionId: string, delta: number): TransactionResult
		local profile = sessions[playerId]
		if profile == nil or not profile:IsActive() then
			return { ok = false, balance = 0, duplicate = false, failure = "ProfileNotLoaded" }
		end
		local data = profile.Data :: any
		if typeof(data.recentTransactions) ~= "table" then
			data.recentTransactions = {}
		end
		local log: { string } = data.recentTransactions

		-- The replay guard. Returns the balance the ORIGINAL application produced, so a retried
		-- credit reports the truth rather than looking like a fresh zero-value payout.
		if table.find(log, transactionId) ~= nil then
			return { ok = true, balance = data.currency, duplicate = true }
		end

		-- A payout is a whole number or it is a bug. Refusing NaN, infinities and fractions here — at
		-- the last gate before persistence — means no upstream arithmetic error can ever be written
		-- into a balance, however it got there.
		if not isFiniteNumber(delta) or delta % 1 ~= 0 then
			return { ok = false, balance = data.currency, duplicate = false, failure = "InvalidAmount" }
		end

		local current = if typeof(data.currency) == "number" and isFiniteNumber(data.currency) then data.currency else 0
		local updated = current + delta
		-- A balance can never go negative. A charge that would overdraw is refused outright rather
		-- than clamped to zero, because clamping would let a player buy something they cannot afford
		-- and pay whatever they happened to have.
		if updated < 0 then
			return { ok = false, balance = current, duplicate = false, failure = "InsufficientFunds" }
		end

		data.currency = updated
		table.insert(log, transactionId)
		while #log > TRANSACTION_HISTORY do
			table.remove(log, 1)
		end
		return { ok = true, balance = updated, duplicate = false }
	end,
}

return Persistence
