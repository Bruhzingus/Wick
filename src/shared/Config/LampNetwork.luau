--!strict
-- THE LAMP NETWORK — the first finite progression track bought with Raw Wax. Nine nodes and eight
-- contracts, all of it data. See LAMP-NETWORK.md for the approved design, the economy derivation and
-- the sign-off record; this file is only the tuning surface.
--
-- THE ONE-SENTENCE MODEL: the caves were worked before you and whoever did it left a dead lamp line;
-- every node relights one piece of that rig, and each restored piece re-opens a way of working the
-- cave that you currently cannot.
--
-- WHAT THIS TRACK IS NOT, and must never quietly become: a power track. No node changes starting
-- wax, maximum wax, drain, brightness range, light radius, tool costs, tool cooldowns, damage taken,
-- threat behaviour, threat counts, or revive rules. A lit lamp never makes your candle stronger — it
-- makes a different kind of run possible. Cave tiers keep sole ownership of where a run starts and
-- every difficulty multiplier; nothing here touches Config/CaveTiers or Config/Depth.
--
-- CONTRACTS ARE THE ONLY THING THAT MOVES A GAMEPLAY VALUE, and they only ever move it AGAINST the
-- player, by that player's choice, for exactly one run. That asymmetry is the whole reason contracts
-- can exist inside a track that forbids upgrades.
--
-- COSTS AND MULTIPLIERS ARE INTEGERS. Costs are whole Raw Wax because currency is persisted and a
-- persisted float is an argument waiting to happen (Config/Extraction). Contract payouts are PERMILLE
-- integers for the same reason, composed into the extraction arithmetic by integer
-- multiply-then-divide with exactly one floor (Logic/ExtractionValue).

-- Which rollback switch a node's effect lives behind. "always" means the node has no switch because
-- it cannot change cave behaviour at all (only The Pay Table qualifies — it reads a profile field and
-- prints it).
--
-- THIS IS NOT DECORATION: a node whose layer is off is UNPURCHASABLE, not merely inert. A rollback
-- flag that keeps selling the thing it disabled would take real currency for a lamp that lights and
-- does nothing, which is a worse outcome than the bug the rollback was protecting against.
export type LampLayer = "always" | "contracts" | "depositRows" | "generation" | "bell" | "wager"

export type LampNode = {
	id: string,
	displayName: string,
	layer: LampLayer,
	-- The one-clause effect statement shown on the purchase prompt beside the name and the price.
	-- THIS IS LOAD-BEARING, not flavour: it is how "immediately understandable at the point of
	-- purchase" is met structurally rather than by hoping a two-word name carries the meaning.
	promptClause: string,
	cost: number,
	-- Node ids that must ALL be owned first. Empty means the node is available immediately.
	requires: { string },
	-- Node ids of which at least `requiresAnyCount` must be owned, on top of `requires`. This exists
	-- for exactly one node (the hard-contract gate) and is the track's only real branch point: three
	-- ways to reach the same door, so two players who bought different things both arrive.
	requiresAny: { string },
	requiresAnyCount: number,
}

-- WHAT A CONTRACT ACTUALLY DOES TO A RUN. Every row states its rule as data in exactly these terms,
-- so `Logic/ContractRules` can apply any of them without a branch per contract and adding a ninth row
-- is a config edit rather than a new code path.
--
-- Every field's neutral value leaves the run untouched, so a row only has to state what it changes.
-- Nothing in here can make a run EASIER: tools are only ever removed, wax is only ever multiplied
-- down (clamped in `ContractRules`), and the two "voids" fields can only take a payout away.
export type LampContractEffect = {
	-- Tool ids unavailable for the whole run. Rides `SacrificeModifiers.lostTools`, the same mechanism
	-- the Basin already uses to take a tool, so `ToolRules` needs no contract-specific branch at all.
	lostTools: { string },
	-- Fraction of the normal starting wax a candle is lit with. 1 = untouched.
	startingWaxMultiplier: number,
	-- Fraction of the normal MAXIMUM wax. 1 = untouched. Distinct from the above: a smaller tank makes
	-- Basin grants overflow and puts the candle at a shorter body height from the first room, which is
	-- what makes water lethal earlier (Logic/CandleGeometry).
	maxWaxMultiplier: number,
	-- The Basin offers nothing and takes nothing. Its descent pad still works.
	sealsBasin: boolean,
	-- Units mined ABOVE this global depth are worth zero. 0 = every depth pays normally.
	minimumPayingDepth: number,
	-- Maximum studs any party member may be from their nearest teammate. 0 = no tether.
	tetherStuds: number,
	-- How long a tether may be broken before the contract is lost. Prevents a doorway or a bad frame
	-- from voiding a run that nobody actually abandoned.
	tetherGraceSeconds: number,
	-- One death anywhere in the party loses the contract for everyone, including members who already
	-- cashed out.
	voidsOnPartyDeath: boolean,
}

export type LampContract = {
	id: string,
	displayName: string,
	effect: LampContractEffect,
	-- What the rule actually is, in the player's words. Shown at the board and on the results card.
	rule: string,
	-- Payout scalar, permille. 1000 would be no change; every row here is above it because a contract
	-- is always a cost taken on for more money.
	payoutPermille: number,
	-- Smallest party this row may be accepted in. 1 for solo-legal rows; 2 for rows whose rule is
	-- about other people and would be meaningless or free alone.
	minPartySize: number,
	-- Which node sells it. Purely for gating and display; the board reads it to decide what to list.
	unlockNode: string,
}

export type LampNetworkConfig = {
	enabled: boolean,
	contracts: { enabled: boolean, rows: { LampContract } },
	depositRows: { enabled: boolean },
	generation: { enabled: boolean },
	bell: { enabled: boolean, waxCost: number, noiseRadius: number, cooldownSeconds: number },
	wager: {
		enabled: boolean,
		unlockNode: string,
		minimumTarget: number,
		basePermille: number,
		permillePerDepth: number,
		maximumPermille: number,
	},
	nodes: { LampNode },
}

local LampNetwork: LampNetworkConfig = {
	-- MASTER ROLLBACK. False takes the whole track out of the game: no fixtures are built, no prompt
	-- exists, no contract may be accepted, and any node already owned becomes inert and harmless
	-- rather than erroring. Ownership is never revoked — a rollback must not cost anybody a purchase.
	enabled = true,

	contracts = {
		-- ON. Every row's rule is enforced, and each one is enforced by the system that already owns the
		-- thing it takes away rather than by a contract-shaped special case bolted alongside it:
		--
		--   lostTools           -> SacrificeModifiers.lostTools, read by Logic/ToolRules (Unlit, Naked
		--                          Flame). The Basin already removes tools this way; a contract is just
		--                          another reason the set is non-empty.
		--   starting / max wax  -> server/PlayerState.freshState, BEFORE the candle exists, so a Short
		--                          Wick or Hollow Wick candle is never briefly the wrong height.
		--   sealsBasin          -> server/BasinService.presentOffers (Sealed Basin).
		--   minimumPayingDepth  -> Logic/ExtractionValue.baseValue (The Long Descent).
		--   tetherStuds         -> server/ContractWatchService, the one rule that has to be judged
		--                          continuously (Tethered).
		--   voidsOnPartyDeath   -> server/ExtractionService.liveContractFor (Both Lamps), evaluated at
		--                          payout so it can reach a member who already cashed out.
		--
		-- THE BAR FOR TURNING THIS OFF AGAIN, if a row ever misbehaves: a contract that pays without
		-- costing anything is a pure payout increase for no downside, which is exactly the pure-power
		-- upgrade this whole track forbids. Better to disable the layer than to ship one free row.
		enabled = true,
		-- ONE CONTRACT PER RUN, EVER. Accepted at the board before descending, recorded on the profile,
		-- consumed by the run that actually starts.
		--
		-- THE RULE EVERY ROW MUST OBEY: a contract may never cap the number of units you can bank. It
		-- may only cost safety, time, or capability. This is arithmetic, not taste — a multiplier on
		-- quantity cannot pay back a loss of quantity. A proposed "break exactly one deposit all run"
		-- row at 1700 permille was cut during review because at floor 8 the best possible play banks
		-- 2 units x 43 = 86 against 517 unrestricted, needing 6000 permille to break even.
		--
		-- `contract.long_descent` looks like a violation and is not: it gates units behind a goal the
		-- player CHOOSES whether to reach, rather than capping them absolutely. Gating conditionally is
		-- legal. Capping is not.
		--
		-- Break-even figures below are against the cumulative base-value curve in LAMP-NETWORK.md §6.2
		-- (floor 8 = 517, floor 10 = 1,050).
		rows = {
			-----------------------------------------------------------------------------------------
			-- STANDING — sold by The Contract Board.
			-----------------------------------------------------------------------------------------
			{
				id = "contract.unlit",
				effect = {
					lostTools = { "Flare" },
					startingWaxMultiplier = 1,
					maxWaxMultiplier = 1,
					sealsBasin = false,
					minimumPayingDepth = 0,
					tetherStuds = 0,
					tetherGraceSeconds = 0,
					voidsOnPartyDeath = false,
				},
				displayName = "Unlit",
				rule = "Flare is unavailable for the whole run.",
				-- Costs no units and no time — only the single thing that repels a dark-hunter and the
				-- only interrupt for a VoidFly dive. Pure danger, so the multiplier is modest.
				payoutPermille = 1250,
				minPartySize = 1,
				unlockNode = "lamp.contract_board",
			},
			{
				id = "contract.naked_flame",
				effect = {
					lostTools = { "Cup" },
					startingWaxMultiplier = 1,
					maxWaxMultiplier = 1,
					sealsBasin = false,
					minimumPayingDepth = 0,
					tetherStuds = 0,
					tetherGraceSeconds = 0,
					voidsOnPartyDeath = false,
				},
				displayName = "Naked Flame",
				rule = "Cup is unavailable for the whole run — you can never go dark.",
				-- The deliberate MIRROR of Unlit. Losing Flare disarms you against dark-hunters; losing
				-- Cup disarms you against the Drawn. Each takes away one half of the threat taxonomy, so
				-- the two want opposite play from the same player and neither is ever the obvious pick.
				-- Slightly dearer than Unlit because going dark is a held state you lean on constantly.
				payoutPermille = 1300,
				minPartySize = 1,
				unlockNode = "lamp.contract_board",
			},
			{
				id = "contract.short_wick",
				effect = {
					lostTools = {},
					startingWaxMultiplier = 0.7,
					maxWaxMultiplier = 1,
					sealsBasin = false,
					minimumPayingDepth = 0,
					tetherStuds = 0,
					tetherGraceSeconds = 0,
					voidsOnPartyDeath = false,
				},
				displayName = "Short Wick",
				rule = "You start at 70% wax.",
				-- Costs roughly half a floor of reach. Was authored at 1350 and raised: at that rate a
				-- floor-8 run came out within noise of break-even, which is not a decision, it is a coin
				-- flip with extra steps. At 1450 it is about +23% at floor 8.
				payoutPermille = 1450,
				minPartySize = 1,
				unlockNode = "lamp.contract_board",
			},
			{
				id = "contract.both_lamps",
				effect = {
					lostTools = {},
					startingWaxMultiplier = 1,
					maxWaxMultiplier = 1,
					sealsBasin = false,
					minimumPayingDepth = 0,
					tetherStuds = 0,
					tetherGraceSeconds = 0,
					voidsOnPartyDeath = true,
				},
				displayName = "Both Lamps",
				rule = "Every party member must extract alive. One death and nobody's contract pays.",
				-- Costs nothing up front; it is a bet on the party rather than a handicap. Expected value
				-- is base x (1 + 0.6 x P(everyone gets out)) — about +36% for a shaky pair and +48% for a
				-- good one, so it pays for being good together rather than for being careful alone.
				-- Raised from 1500 for the same reason as Short Wick.
				payoutPermille = 1600,
				-- Solo is a player count, not a lesser mode — but "everyone came back" is not a wager a
				-- party of one can lose, and paying for it would make the row meaningless everywhere.
				minPartySize = 2,
				unlockNode = "lamp.contract_board",
			},

			-----------------------------------------------------------------------------------------
			-- HARD — sold by The Hard Contracts.
			-----------------------------------------------------------------------------------------
			{
				id = "contract.hollow_wick",
				effect = {
					lostTools = {},
					startingWaxMultiplier = 1,
					maxWaxMultiplier = 0.6,
					sealsBasin = false,
					minimumPayingDepth = 0,
					tetherStuds = 0,
					tetherGraceSeconds = 0,
					voidsOnPartyDeath = false,
				},
				displayName = "Hollow Wick",
				rule = "Your maximum wax is 60% for the whole run.",
				-- The best row in the set. A smaller TANK, not a lower start: Basin grants overflow and
				-- are wasted, and Logic/CandleGeometry puts you at the body height of a half-burned
				-- candle from the first room — so water that is normally safe to wade is lethal on floor
				-- 1. It weaponises the game's best emergent mechanic (DESIGN §9) immediately, and it
				-- costs reach rather than units. Roughly 1-1.5 floors, so +7% to +31% at floor 8.
				payoutPermille = 1900,
				minPartySize = 1,
				unlockNode = "lamp.hard_contracts",
			},
			{
				id = "contract.tethered",
				effect = {
					lostTools = {},
					startingWaxMultiplier = 1,
					maxWaxMultiplier = 1,
					sealsBasin = false,
					minimumPayingDepth = 0,
					tetherStuds = 30,
					tetherGraceSeconds = 5,
					voidsOnPartyDeath = false,
				},
				displayName = "Tethered",
				rule = "No one may be more than 30 studs from another member for over 5 seconds.",
				-- The co-op capstone, and it costs the single biggest efficiency gain multiplayer has:
				-- splitting up to find the Brazier, the Basin and the seams. About a floor of reach, so
				-- roughly +25% at floor 8. It never touches units, never touches capability — it only
				-- takes time.
				payoutPermille = 1800,
				minPartySize = 2,
				unlockNode = "lamp.hard_contracts",
			},
			{
				id = "contract.long_descent",
				effect = {
					lostTools = {},
					startingWaxMultiplier = 1,
					maxWaxMultiplier = 1,
					sealsBasin = false,
					minimumPayingDepth = 6,
					tetherStuds = 0,
					tetherGraceSeconds = 0,
					voidsOnPartyDeath = false,
				},
				displayName = "The Long Descent",
				rule = "Units mined above floor 6 are worth nothing.",
				-- The highest-variance row. Break-even is around floor 7.5: -7% if you turn back at 7,
				-- +14% at 8, +37% at 10, and a total wipe if you bail early. Authored first at "above
				-- floor 8" and moved shallower — at 8 the break-even sat past floor 9, which made it a
				-- bet almost nobody was in a position to take.
				payoutPermille = 1600,
				minPartySize = 1,
				unlockNode = "lamp.hard_contracts",
			},
			{
				id = "contract.sealed_basin",
				effect = {
					lostTools = {},
					startingWaxMultiplier = 1,
					maxWaxMultiplier = 1,
					sealsBasin = true,
					minimumPayingDepth = 0,
					tetherStuds = 0,
					tetherGraceSeconds = 0,
					voidsOnPartyDeath = false,
				},
				displayName = "Sealed Basin",
				rule = "The Basin gives you nothing and takes nothing.",
				-- Pure endurance: no grant, no sacrifice, and the descent pad still works, so the room
				-- keeps its job and only the pool goes cold. Zero unit cost, which is exactly why it is
				-- legal. FLAGGED AS THE LEAST CERTAIN ROW: its real cost depends on how load-bearing the
				-- Basin grant is, which is unmeasured. Retune the multiplier or cut the row.
				payoutPermille = 1600,
				minPartySize = 1,
				unlockNode = "lamp.hard_contracts",
			},
		},
	},

	-- Rollback for the extra seam kinds (Twin / Deep / Bright). False means only the ordinary seam ever
	-- generates; the deposit COUNT curve in Config/Mining is unaffected either way.
	--
	-- OFF: the rows are specified but MiningRules does not yet select between seam kinds. Unlike the
	-- contracts above this is merely unfinished rather than exploitable — an unowned seam kind simply
	-- never appears — but leaving it true would advertise a purchase that changes nothing.
	depositRows = { enabled = false },

	-- Rollback for room-generation nodes. False means no Locked Store is ever planned. OFF for the
	-- same reason: the planner does not yet emit the room.
	generation = { enabled = false },

	bell = {
		-- OFF: no bell exists in the cave yet.
		enabled = false,
		-- Pillar 3: every cost is paid in wax. Small enough that ringing is never agonised over, large
		-- enough that spamming it is visibly spending your run.
		waxCost = 0.03,
		-- THE DOWNSIDE, and the reason this is a trade rather than a solution. The ring feeds the same
		-- noise field a fumbled pickaxe strike does (Logic/SoundField), so dark-hunters come and look.
		-- Being findable and being found are the same act.
		noiseRadius = 42,
		-- Long enough that the bell cannot become a continuous position broadcast, which would quietly
		-- turn it into the through-rock beacon this design deliberately rejected.
		cooldownSeconds = 6,
	},

	wager = {
		-- ON, unlike `contracts.enabled` above, because a wager has no rule to enforce. Its entire
		-- mechanic is "did you mine at or below the depth you named", which ExtractionService already
		-- answers from the origin stamps on the cargo the player actually walked out with. There is no
		-- half of this feature waiting on the run to cooperate.
		enabled = true,
		unlockNode = "lamp.wager_board",
		-- Never a shallow bet. On top of this floor, THE TARGET MUST BE STRICTLY DEEPER THAN THIS
		-- PLAYER'S RECORDED `deepestFloor` (enforced in Interfaces/LampNetwork, not here, because it is
		-- per-profile). That single rule is what stops the wager being free money for naming a depth
		-- you were going to reach anyway, and it makes the bet self-scaling: a better player always
		-- faces a harder target, forever, with no extra tuning.
		minimumTarget = 6,
		basePermille = 1000,
		permillePerDepth = 150,
		-- Reached at target 15. Depth is uncapped in this game, so the multiplier must not be.
		maximumPermille = 2500,
	},

	-- THE NODES. Costs are a near-free opener, one deliberate 3.2x jump to the node that actually
	-- changes the game, then a steady ~1.35x ramp with no wall in it. Total 24,150 — roughly 48 runs,
	-- deliberately comparable to the 20,250 of cave unlocks so neither dominates as a savings goal.
	nodes = {
		{
			id = "lamp.pay_table",
			displayName = "The Pay Table",
			layer = "always",
			promptClause = "Read what your last run paid",
			-- Two free Shallows runs. The track must be visible to a new player in their first session,
			-- and the first thing anyone buys must DO something they can see.
			cost = 250,
			requires = {},
			requiresAny = {},
			requiresAnyCount = 0,
		},
		{
			id = "lamp.contract_board",
			displayName = "The Contract Board",
			layer = "contracts",
			promptClause = "Take a harder run for more pay",
			-- The 3.2x step, and the spine of the track: everything except the seams hangs off it and it
			-- is the only node that adds a decision to EVERY future run.
			cost = 800,
			requires = { "lamp.pay_table" },
			requiresAny = {},
			requiresAnyCount = 0,
		},
		{
			id = "lamp.twin_seam",
			displayName = "Twin Seam",
			layer = "depositRows",
			promptClause = "Two miners, double pay",
			cost = 1200,
			requires = { "lamp.contract_board" },
			requiresAny = {},
			requiresAnyCount = 0,
		},
		{
			id = "lamp.signal_bell",
			displayName = "The Signal Bell",
			layer = "bell",
			promptClause = "Ring to be found — the cave hears it too",
			cost = 1500,
			requires = { "lamp.contract_board" },
			requiresAny = {},
			requiresAnyCount = 0,
		},
		{
			id = "lamp.deep_seam",
			displayName = "Deep Seam",
			layer = "depositRows",
			promptClause = "Deep floors only — nine strikes, six units",
			cost = 2000,
			requires = { "lamp.twin_seam" },
			requiresAny = {},
			requiresAnyCount = 0,
		},
		{
			id = "lamp.bright_seam",
			displayName = "Bright Seam",
			layer = "depositRows",
			promptClause = "Only workable at full burn",
			cost = 2800,
			requires = { "lamp.deep_seam" },
			requiresAny = {},
			requiresAnyCount = 0,
		},
		{
			id = "lamp.locked_store",
			displayName = "The Locked Store",
			layer = "generation",
			promptClause = "Burn open a sealed room for its stock",
			cost = 3600,
			requires = { "lamp.contract_board" },
			requiresAny = {},
			requiresAnyCount = 0,
		},
		{
			id = "lamp.hard_contracts",
			displayName = "The Hard Contracts",
			layer = "contracts",
			promptClause = "Four brutal runs for much more pay",
			cost = 5000,
			requires = { "lamp.contract_board" },
			-- The track's only branch point. Three roads in, two needed — so a player who went down the
			-- seam branch and a player who bought the Locked Store both arrive, and neither had to buy
			-- the other's path. It also guarantees real engagement with deep play before the hardest
			-- rules open.
			requiresAny = { "lamp.deep_seam", "lamp.bright_seam", "lamp.locked_store" },
			requiresAnyCount = 2,
		},
		{
			id = "lamp.wager_board",
			displayName = "The Wager Board",
			layer = "wager",
			promptClause = "Name a depth deeper than you have ever been",
			-- The terminus, and the only node that is infinitely re-decidable as well as infinitely
			-- repeatable. Taking a wager BLOCKS taking a contract that run, so it competes against all
			-- eight of them — that opportunity cost is its entire teeth, and it needs no punishment.
			cost = 7000,
			requires = { "lamp.hard_contracts" },
			requiresAny = {},
			requiresAnyCount = 0,
		},
	},
}

return LampNetwork
