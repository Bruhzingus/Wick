# THE LAMP NETWORK — approved specification

**Status:** approved by the project owner. Phase 9B implementation in progress.
**Currency:** Raw Wax (`Config/Extraction.currencyName`), the game's one persistent currency.
**Scope:** 9 nodes, 8 contracts, one wager. Finite. Purchased from physical fixtures in The Landing.

> Authority order is unchanged: `DESIGN.md` (product) → `ARCHITECTURE.md` (engineering) →
> `TUNING.md` (numbers) → this file. Where this file and those disagree, they win.

---

## 1. Fictional and visual purpose

**The caves were worked before you.** Whoever did it strung a lamp line — an iron conduit and a row
of housings — from the surface down the shafts and out along the galleries. Then it went out, and no
one says why. `DESIGN.md` §20 leaves "why are the caves dark?" open on purpose; the Lamp Network
answers it with infrastructure rather than story. The caves are dark because the lamps went out.
Nothing explains that, and nothing should.

**You are not buying power. You are relighting somebody else's rig.** Every node restores one piece
of abandoned working equipment, and each restored piece re-opens a way of working the cave that the
previous candles used and you currently cannot. That framing is what keeps the track inside
`DESIGN.md` §13's "reward DEPTH, not POWER" — a lit lamp never makes your candle stronger, it makes
a different kind of run possible.

### The physical object

One continuous **brass-and-iron conduit** at head height, entering the hub above the shop counter
(`LobbyRoom.shopOffset`), running the west wall, crossing the back wall behind the three elevator
alcoves, and terminating in a housing that points straight down the middle shaft. Nine dark **lamp
housings** hang off it, each above the machine it feeds.

- **Unlit:** cold iron, matte, no emission. The machine below is visibly seized — a chained board, a
  bell with no rope, a bolted door.
- **Lit:** the housing's flame catches, the conduit warms to the ember palette (`ART-BIBLE` ember
  255,150,66), and the machine below it visibly starts.
- **The payoff is the machine, not the lamp.** The lamp is the ownership indicator; the machine
  starting is the reward.

No new hues. The conduit is the game's only continuous warm line, which makes the unlit remainder of
it a permanent visible statement of what you have not bought yet.

### Ownership is per-player, so the hub renders per-player

`ProximityPrompt.Enabled` is one shared Instance property (see `server/ElevatorService.luau:387`),
and hub geometry is shared. Two players in The Landing own different node sets. **Lamp lighting is
rendered client-side, per viewer**, from that client's own replicated `ownedLampNodes` list. One
thin controller (`client/LampNetworkController.luau`) sets housing emission and machine pose and
does nothing else. Diegetic hub geometry, not a menu — but it is launch-critical, because without it
no purchase has a visible payoff.

---

## 2. The nodes

| # | Node ID | Name | Cost | Prereq |
|---|---|---|---|---|
| N1 | `lamp.pay_table` | The Pay Table | 250 | — |
| N2 | `lamp.contract_board` | The Contract Board | 800 | N1 |
| N3 | `lamp.twin_seam` | Twin Seam | 1,200 | N2 |
| N4 | `lamp.signal_bell` | The Signal Bell | 1,500 | N2 |
| N5 | `lamp.deep_seam` | Deep Seam | 2,000 | N3 |
| N6 | `lamp.bright_seam` | Bright Seam | 2,800 | N5 |
| N7 | `lamp.locked_store` | The Locked Store | 3,600 | N2 |
| N8 | `lamp.hard_contracts` | The Hard Contracts | 5,000 | N2 + any 2 of {N5, N6, N7} |
| N9 | `lamp.wager_board` | The Wager Board | 7,000 | N8 |

**Total: 24,150 Raw Wax ≈ 48 runs ≈ 12 hours.**

Node IDs are stable strings and are the contract between config, profile, and every consumer. They
never change once shipped; a retired node's id is never reused.

```
                 N1  The Pay Table              250
                  ▼
                 N2  The Contract Board         800
        ┌─────────┼──────────────────┐
        ▼         ▼                  ▼
   N3 Twin      N4 The Signal    N7 The Locked
      Seam         Bell             Store
      1,200        1,500            3,600
        ▼                              │
   N5 Deep Seam 2,000                  │
        ▼                              │
   N6 Bright Seam 2,800                │
        └───────────┬──────────────────┘
                    ▼  (N2 + any two of N5 / N6 / N7)
           N8 The Hard Contracts       5,000
                    ▼
           N9 The Wager Board          7,000
```

### N1 — The Pay Table · 250

Prints your last run's full extraction breakdown as a toast — units by origin depth, per-unit value
at each, cave scalar, party bonus, contract scalar, total — plus the value-per-unit curve for the
cave you are standing in front of. Pure information; nothing in the cave changes. It exists because
`Extraction.valuePerUnitByDepth` is the number that decides whether one more floor is worth it, and
right now a player has to infer it. Affordable after ~2 free runs, so the track is visible in a new
player's first session.

### N2 — The Contract Board · 800

Unlocks the four standing contracts (§4). Accept one before descending; it is recorded on your
profile, consumed by the next run that actually starts, and scales that run's extraction payout.
**One contract per run, ever.** This is the track's repeatable layer.

### N3 — Twin Seam · 1,200

Adds a deposit row with two working faces. **Two miners** planted simultaneously (both lit, both
uncovered): 3 clean strikes each, and it yields **2 units to each**. **Alone:** 6 clean strikes for
the ordinary 2 units — same pay, twice the time standing immobile and uncovered. The clearest "bring
a friend" purchase in the game, and a verb rather than a bonus.

### N4 — The Signal Bell · 1,500

Every party member carries one. Ringing costs **0.03 wax**.

- **The sound carries through rock** — positional, true direction, real falloff. In near-total
  darkness it is the only thing that tells you where your friend actually is.
- **The visual does not.** A brief warm ripple at the ringer's position, occluded by geometry like
  everything else, emitting no light and creating no `PointLight`. Line of sight gets you a
  confirmation; no line of sight gets you a bearing and nothing more.
- **The cave hears it.** The ring feeds the existing noise field (`Logic/SoundField` /
  `server/NoiseService`). Dark-hunters investigate.

A through-rock *light* would have solved darkness, which the game wants unsolved (`DESIGN.md` §19
risk 5). A through-rock *sound* solves separation only, and does it on the axis §19 risk 1 names as
the project's largest.

### N5 — Deep Seam · 2,000

A deposit row eligible only at **global depth ≥ 6**. Nine clean strikes, **6 units**. The pay rate
per strike is exactly the ordinary rate; what changes is that it is one unbroken ~25-second block of
standing planted, lit, and uncovered on a floor where 25 seconds is a long time.

### N6 — Bright Seam · 2,800

A deposit row workable only with the dial at **≥ 90% of max burn rate** (a Flare counts). **4 units
in 3 clean strikes.** For those five seconds you are the brightest thing in the cave, standing still
and unable to move. This is the burning-vine logic applied to mining: the dial becomes a key, not
just a lighting trade. A Basin brightness cap (×0.6) locks you out entirely — a real self-inflicted
consequence — but a teammate without the cap can work it beside you.

### N7 — The Locked Store · 3,600

The track's only room-generation node. On floors ≥ 5 a rare optional store-room may generate
**behind a vine curtain** (existing system), holding a guaranteed deposit *and* a guaranteed loot
pickup. Opening it means holding ~96% burn for 3.2 continuous seconds in a deep cave.

It inherits the planner's existing vine invariants — a vined doorway is never a room's only
entrance and never sits on the entry → Brazier → Basin route — so it is off-route optional content
by construction. A player with a Basin brightness cap cannot open one alone; a teammate can open it
for them.

**Party scope.** A floor is shared, so this cannot be per-player. **The floor is planned from the
union of every party member's owned generation nodes**, resolved server-side from profiles at run
start.

### N8 — The Hard Contracts · 5,000

Unlocks the four hard contracts (§4) on the same board. The "any two of three" prerequisite is the
track's one real branch point: two players who bought different things both arrive here, and it
guarantees engagement with deep play before the hardest rules open.

### N9 — The Wager Board · 7,000

Instead of a contract, name a **target depth**. It must be **strictly deeper than your profile's
`deepestFloor`**, and at least 6 — so it is a stretch by construction and self-scales with skill
rather than being free money for naming a depth you would have hit anyway.

Extract having mined at least one unit at or below the target and your whole payout scales by
`1000 + 150 × (target − 5)` permille, capped at 2500‰. Miss it — extract shallower, or die — and it
pays nothing extra.

**Its teeth are opportunity cost, not punishment.** Taking a wager **blocks taking a contract that
run**, so it competes against all eight. Infinitely repeatable, adds zero power, and it is the
machine you will still be using in a hundred runs.

---

## 3. Where the co-op value lives

Every co-op payoff is something you *do* in the cave. No payout bonuses.

| Hook | Node / contract | What two players actually do |
|---|---|---|
| Twin Seam | N3 | Both plant at one rock, uncovered, at the same time |
| The Signal Bell | N4 | Ring to be found, and pay wax and noise for it |
| Both Lamps | contract | One death voids the contract for everybody |
| Tethered | contract | Nobody may get more than 30 studs from anyone else |
| Opening a Locked Store for a capped teammate | N7 | A Basin-capped player physically cannot burn the vine; you can |

---

## 4. The contracts

**One contract per run.** Accepted at the board before descending, recorded on the profile, consumed
by the run that starts. The payout scalar is a permille integer composed into the extraction
arithmetic exactly once (§7).

### Standing — unlocked by N2

| ID | Name | Rule | Pays |
|---|---|---|---|
| `contract.unlit` | **Unlit** | Flare is unavailable all run | ×1.25 |
| `contract.naked_flame` | **Naked Flame** | Cup is unavailable all run — you can never go dark | ×1.30 |
| `contract.short_wick` | **Short Wick** | You start at 70% wax | ×1.45 |
| `contract.both_lamps` | **Both Lamps** | Every party member must extract alive; one death and nobody's contract pays. Party ≥2 | ×1.60 |

**Unlit and Naked Flame are a deliberate mirrored pair.** Losing Flare removes the only thing that
repels dark-hunters. Losing Cup removes the only way to go dark and hide from the Drawn. Each
disarms you against exactly one half of the threat taxonomy, so the two want opposite play from the
same player and neither is ever the obvious pick.

### Hard — unlocked by N8

| ID | Name | Rule | Pays |
|---|---|---|---|
| `contract.hollow_wick` | **Hollow Wick** | Your **maximum** wax is 60% all run | ×1.90 |
| `contract.tethered` | **Tethered** | No member may be more than 30 studs from another for over 5 continuous seconds. Party ≥2 | ×1.80 |
| `contract.long_descent` | **The Long Descent** | Units mined above floor 6 are worth **zero** | ×1.60 |
| `contract.sealed_basin` | **Sealed Basin** | The Basin gives you nothing and takes nothing | ×1.60 |

**Hollow Wick** is a smaller *tank*, not a lower start: Basin grants overflow and are wasted, and
you begin at the body height of a half-burned candle, so `CandleGeometry` puts water that is
normally safe at lethal height from floor 1. It weaponizes the game's best emergent mechanic
immediately.

**Sealed Basin** still lets you walk in and use the descent pad — the pool is simply cold. No grant,
no sacrifice.

---

## 5. THE RULE EVERY CONTRACT MUST OBEY

> **A contract may never cap the number of units you can bank. It may only cost safety, time, or
> capability.**

A multiplier on quantity cannot pay back a loss of quantity. This is not a guideline; it is
arithmetic, and it killed a proposed contract during review:

*One Seam* ("break exactly one deposit all run", ×1.70). At floor 8 the best possible play is
breaking the single deepest seam: **2 units × 43 = 86**, against **517** unrestricted. Break-even
would need **×6.0**. Cut.

The Long Descent looks like a violation and is not: it gates units behind a goal *you choose whether
to reach*, rather than capping them absolutely. Gating conditionally is legal; capping is not.

Two further rows were cut in review for non-arithmetic reasons, recorded so they are not re-proposed:

- **Blackout** ("dial capped at 0.45") — this is the Basin's existing brightness-cap sacrifice
  wearing a contract's hat. Duplicating a sacrifice is not a new decision.
- **Rope Line** ("all extract within 20 s at one brazier") — trivially satisfied by walking to the
  brazier together, which is what a party does anyway, and it duplicates Both Lamps.

---

## 6. Economy — the arithmetic of record

### 6.1 The deposit-count change

Owner decision: **0–3 deposits per floor, 3 only on deeper floors** (previously `maxPerFloor = 1`
with a flat 65% chance). This supersedes the "a second deposit turns a detour into a route" note in
`Config/Mining`. Every existing placement safety rule still binds: dry footprint, hazard and threat
separation, never the entry/Basin/Brazier room, never on the guaranteed route, never behind a vine.
A floor that cannot place its rolled count places fewer — the count drops, never the safety rules.

`unitsPerDeposit` drops **3 → 2** in the same change. Without it, deep income roughly triples.

| Depth | Count weights | E(deposits) |
|---|---|---|
| 1–3 | 0:35, 1:65 | 0.65 |
| 4 | 0:20, 1:50, 2:30 | 1.10 |
| 5–6 | 1:60, 2:40 | 1.40 |
| 7–9 | 1:35, 2:45, 3:20 | 1.85 |
| 10+ | 2:55, 3:45 | 2.45 |

### 6.2 Base value by depth (E × 2 units × `valuePerUnitByDepth`)

| Depth | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Per floor | 13 | 14 | 18 | 40 | 64 | 78 | 130 | 159 | 200 | 333 |
| **Cumulative** | 13 | 27 | 46 | 85 | **149** | 228 | 357 | **517** | 716 | **1,050** |

**Both of TUNING's documented anchors survive.** A 5-floor Shallows run pays **149** against the
authored ~152. A 5-floor Deep run nets **−327** against the documented −316. Only the deep end gets
richer, which is the point: shallow floors now yield *fewer* units than before and deep floors more,
so the deposit curve reinforces the depth push instead of being flat against it.

| Cave | Floor 5 | Floor 8 | Floor 10 |
|---|---|---|---|
| Shallows (1000‰, no fee) | +149 | +516 | +1,049 |
| Descent (2500‰, −350) | +23 | +941 | +2,273 |
| Deep (4500‰, −1000) | −328 | +1,324 | +3,722 |

*Every figure in §6.2 and §6.3 was computed from the shipped configs and the real
`MiningRules.targetCount`, not by hand.*

### 6.3 Contract break-evens, against the table above

| Contract | Cost in floors | At floor 8 | Verdict |
|---|---|---|---|
| Unlit ×1.25 | none (danger only) | +25% | worth it |
| Naked Flame ×1.30 | none (danger only) | +30% | worth it |
| Short Wick ×1.45 | ~0.5 | +23% | worth it |
| Both Lamps ×1.60 | none; EV = base × (1 + 0.6 × P) | +36% at P=0.6, +48% at P=0.8 | scales with how good you are together |
| Hollow Wick ×1.90 | ~1–1.5 | +7% to +31% | worth it |
| Tethered ×1.80 | ~1 (no splitting up to search) | +25% | worth it |
| The Long Descent ×1.60 | conditional | −7% at D7, **+14% at D8**, +37% at D10 | break-even ≈ floor 7.5 |
| Sealed Basin ×1.60 | endurance only, no unit cost | — | needs playtest; the least certain row |
| ~~One Seam ×1.70~~ | **caps units at 2** | 146 vs 516 → **−72%** | **cut — needs ×6.0** |

### 6.4 The mining wax shard

More seams at depth also means more wax returned by perfect strikes. `TUNING.md` calls
`waxPerPerfectStrike` the economy's most sensitive lever and warns that much past 0.03 mining becomes
a net wax fountain that deletes the survival pressure the game is built on.

At the old 0.025, deep floors would return `2.45 × 3 × 0.025 = 0.18` wax against a ~0.070 traversal
cost — exactly that fountain. **Dropped to 0.012:**

| Depth band | Wax returned per floor | Traversal cost |
|---|---|---|
| 1–3 | 0.023 | ~0.070 |
| 5–6 | 0.050 | ~0.070 |
| 7–9 | 0.067 | ~0.070 |
| 10+ | 0.088 | ~0.070 |

Shallow floors are a net wax loss, deep floors roughly break even. The margin TUNING describes is
preserved, and the wax reward now tracks depth alongside the currency reward.

### 6.5 Pacing

| Milestone | Cumulative | Runs | Wall clock |
|---|---|---|---|
| First node (N1) | 250 | ~2 free | ~30 min |
| Trunk (N1+N2) | 1,050 | ~7 free / 3 Descent | ~1.5 h |
| Through N6 | 8,550 | ~15 from trunk | ~5 h |
| **Terminus (N9)** | **24,150** | **~48** | **~12 h** |

Track (24,150) and cave unlocks (20,250) are deliberately comparable, so neither dominates as a
savings goal. Completing both is ~44,000 ≈ 85 runs ≈ 21 hours.

---

## 7. Payout arithmetic

`Logic/ExtractionValue` gains a `contractPermille`. The integer guarantee that file exists to hold
is not weakened:

- Scalars **compose by integer multiply-then-divide into one permille**, then a **single floor** is
  applied to the subtotal. Never a floor per scalar; never per-stack (per-stack rounding would let a
  player raise their own payout by splitting units across more stacks).
- The party bonus stays a separate retroactive credit, exactly as today.
- `maxSinglePayout` still binds. Worst legitimate case: Deep 4500‰ × Hollow Wick 1900‰ × party
  1500‰.
- A wager and a contract are mutually exclusive, so at most one of them contributes.

---

## 8. Profile schema

**Additive only. Every new field defaults to empty/unpurchased. No retroactive granting.**

```luau
schemaVersion = 3,                    -- was 2
ownedLampNodes: { string },           -- default {}
activeContractId: string?,            -- default nil
activeWagerDepth: number?,            -- default nil; mutually exclusive with activeContractId
lastRunBreakdown: { ... }?,           -- default nil; statistics only, for the Pay Table
```

**Migration v2 → v3:** fill the four fields with defaults if absent, set `schemaVersion = 3`.
Nothing else is touched.

**No migration mapping from existing tier ownership is required, and none may be written.**
`ownedCaveTiers` and `ownedLampNodes` are unrelated: cave tiers decide *which cave* and *what
admission costs*; lamp nodes decide *what a cave can contain and what you may agree to*. A player
who owns The Deep starts the Lamp Network at zero nodes like everyone else. Balances, tier
purchases, the transaction log and the existing v1→v2 migration are all untouched.

**One deliberate deviation from `ownedCaveTiers`.** `CaveTiers.purchasePermanent` grants via
`get` → mutate copy → `save`, which is safe today only because nothing yields between the three
calls. Lamp nodes get **`Persistence.grantLampNode`**, which mutates `profile.Data` **directly** —
the discipline `applyTransaction` already uses, for the same reason. `save` must **not** write
`ownedLampNodes`.

---

## 9. Purchase interaction and failure rules

**Reuses the existing shop-stub pattern exactly. No menu, no board UI, no client shop.**

One `ProximityPrompt` per node fixture, built by `server/LobbyRoomBuilder`, exposed rather than
answered there:

```
ObjectText   = "Twin Seam"
ActionText   = "Two miners, double pay — 1,200 Raw Wax"
HoldDuration = 1.2          -- the hold IS the confirmation; a tap does nothing
```

The name plus a one-clause effect statement, both visible before you commit — this is how
"immediately understandable at the point of purchase" is met structurally rather than by hoping a
name carries it alone. Triggering fires `LobbyAction("buyLamp", nodeId)`, the identical remote and
rate-limit path `buyCave` uses. The client names a node id and nothing else. Prompts stay enabled
for everyone (`Enabled` is shared); per-player gating happens in the server handler.

### The purchase sequence — the whole contract

1. Validate server-side with no yields: known node id; not already owned; every prerequisite owned;
   `Persistence.isLoaded` true.
2. `applyTransaction(playerId, "lamp:<userId>:<nodeId>", -price)`.
3. **`ok == false`:** grant nothing, toast the reason. Nothing was charged.
4. **`ok == true`:** `grantLampNode` immediately, same yield-free block. Set-insert, idempotent.
5. **`ok == true and duplicate == true`: still grant, do not abort.** The transaction id is derived,
   not generated, so a retry of a purchase that charged but failed to grant charges nothing a second
   time and completes the grant. **The retry path is the repair path** — which is what makes the
   absence of a player-facing refund correct.

There is no refund verb, no respec, no sell-back. Atomic transaction safety is the entire failure
story.

---

## 10. Rollback flags

One per real behaviour switch, all in `Config/LampNetwork`:

| Flag | Off means | Shipping state |
|---|---|---|
| `enabled` | Whole track off: prompts absent, owned nodes inert and harmless | **on** |
| `contracts.enabled` | No contract may be accepted; `contractPermille` is always 1000 | **off** — see below |
| `depositRows.enabled` | Only the ordinary seam ever generates | **off** — rows not yet selected by `MiningRules` |
| `generation.enabled` | No Locked Store is ever planned | **off** — planner does not yet emit the room |
| `bell.enabled` | The bell cannot be rung | **off** — no bell exists in the cave yet |
| `wager.enabled` | No wager may be placed; a placed one pays nothing | **on** — it has no in-cave rule to enforce |

N1 needs no flag — it is read-only display and cannot change cave behaviour.

**A rolled-back node is UNPURCHASABLE, not merely inert.** Each node names its `layer` in config, and
`LampRules.nodeIsLive` refuses the sale while that layer is off. Purchases are final and there is no
refund mechanic, so taking currency for a lamp whose effect is switched off would be unrecoverable.
Ownership is never revoked by a rollback — the gate only stops *new* sales, and an owner pressing the
prompt is told the machinery is not running rather than being sold it twice. An unrecognised layer
fails **closed**: refusing to sell costs a player nothing, selling a dead node costs them real wax.

**Consequence for the shipped state, measured from the real config: exactly one node (The Pay Table,
250) is reachable, out of 24,150.** The Wager Board's layer is live but it sits behind The Hard
Contracts, which is not. The track is not playable until effects land — see §12.

**Why `contracts.enabled` ships off, and what turns it on.** The payout half is finished and tested:
a signed run composes its scalar into the extraction arithmetic and the results card explains it. The
**rule** half is not — nothing yet removes Flare for `contract.unlit`, caps starting wax for
`contract.short_wick`, or seals the Basin for `contract.sealed_basin`. Enabled in that state every row
is a pure payout increase for no downside, which is precisely the pure-power upgrade §11 forbids and
worse than any node rejected during design. Turn it on when each row's rule is enforced by the run and
a broken rule reports `nil` to `ExtractionValue.compute`.

The wager is on because it has no rule to enforce: "did you mine at or below the depth you named" is
answered from the origin stamps on the cargo the player actually walked out with.

---

## 11. Non-goals

The Lamp Network is **not**, and must not become:

- **A skill tree.** Nine nodes, one trunk, three short branches, one gate. No levels, no points, no
  respec.
- **A power track.** No node changes starting wax, max wax, wax drain, brightness range, light
  radius, tool costs, tool cooldowns, damage taken, threat behaviour, threat counts, or revive
  rules. No node makes any enemy weaker or any hazard rarer. *(Contracts move these values, always
  against the player, always by choice, always for one run.)*
- **A payout bonus track.** Cut in review. Every node is access, a decision, or a verb.
- **A second way to change where a run starts.** Cave tiers own `startDepth` and every difficulty
  multiplier, exclusively. No node touches `Config/CaveTiers` or `Config/Depth`.
- **A leaderboard.** Categories are Phase 9C and are free — never wax-gated.
- **A new client UI.** Prompts and toasts only. The one new client file is a diegetic hub-lighting
  controller with no interface surface.
- **A refundable purchase.**
- **A migration event.** Every player starts at zero nodes.
- **A second currency.** Raw Wax buys everything. Living Wax stays flavour for the survival resource
  and is never spent, banked, or converted.
- **Party-shared.** Nodes are per-player and permanent. There is no shared pool and no way to buy a
  node for someone else — the co-op nodes work because you both use them in the cave.

---

## 12. Implementation sequence

Each step is one change with one `Config/Version.luau` bump.

1. This document. *(done)*
2. `Config/Mining` — deposit-count curve, `unitsPerDeposit` 2, `waxPerPerfectStrike` 0.012.
3. `Config/LampNetwork` — nodes, costs, prerequisites, all eight contracts, rollback flags.
4. `Interfaces/Persistence` — v3, four fields, migration, `grantLampNode`, `save` exclusion.
5. `Interfaces/LampNetwork` — evaluation and atomic `purchaseNode`.
6. `ShopService` — `buyLamp` handler.
7. `LobbyRoomBuilder` + `Config/LobbyRoom` — nine fixtures and prompts; `PartyLobbyService` answers.
8. `client/LampNetworkController` — per-viewer housing and machine state.
9. N1 Pay Table — `lastRunBreakdown` on extraction; the prompt prints it.
10. N2 Contract Board + four standing contracts; `ExtractionValue.contractPermille`.
11. N3 Twin Seam — `Mining.depositRows`, `MiningRules` selection, `requiredMiners`.
12. N4 The Signal Bell — wax cost, noise-field entry, positional cue, occluded ripple.
13. N5 Deep Seam, N6 Bright Seam.
14. N7 The Locked Store — vine-gated room, `PlanRequest.unlockedModules`, party-union resolution.
15. N8 The Hard Contracts (four rows), N9 The Wager Board.
16. Docs — `DESIGN.md` §13, `TUNING.md`, `CodeBreakdown.md`, `GAME-BRIEF.md` §14, `ARCHITECTURE.md`.

Steps 2–12 are the launch build: the information layer, the repeatable layer, and two co-op verbs.

---

## 13. Open risks

| # | Risk | Mitigation | Fallback |
|---|---|---|---|
| 1 | **Sealed Basin** is the least certain contract — its cost depends on the Basin grant being load-bearing, which is unmeasured | Ship it and watch | Retune the multiplier, or cut the row |
| 2 | Payout explosion from stacked scalars | One composed permille, one floor, once; `maxSinglePayout` binds | Lower hard-contract multipliers |
| 3 | 0–3 deposits makes a floor a mining route rather than a detour | Placement safety rules unchanged; count drops before any rule relaxes | Lower the depth-band weights |
| 4 | Party-union generation changes a new player's floors without their consent | The Locked Store relocates content but never adds threat or dripstone budget on top of tier × depth | Leader-only instead of union |
| 5 | Twin Seam is thin for solo, and solo is first-class | Solo-workable at 2× strikes for 1× yield — slower and louder, never locked out | Small solo bump, at the cost of the co-op hook |
| 6 | ~48 runs still too long | Every cost is one integer in one file | Halve the table |
