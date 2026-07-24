# Implementation Roadmap — WICK

This file records what the Phase 0–5 prototype actually implements and ranks the work that remains.
It is not permission to expand scope: `DESIGN.md` and `ARCHITECTURE.md` remain authoritative.

“Implemented” means the code path exists and passed command-line parse/lint/build validation. Roblox
runtime behavior still requires the Studio and live checks in `PUBLISH-CHECKLIST.md`.

## Phase status

| Phase | Scope | Prototype status | Important limitation |
| --- | --- | --- | --- |
| P0 | Deterministic tests and repeatable diagnostics | **Implemented** | Studio must still show `[WICK TESTS] PASS: 54 deterministic tests`; the CLI cannot execute Roblox runtime code. |
| P1 | Feel, readability, audio plumbing, visible controls | **Implemented** | Audio cue IDs are intentionally empty, so the sound layer is a safe no-op until approved assets are supplied. |
| P2 | Loot, session remains, expanded threats, depth scaling | **Implemented** | Remains survive only later runs in the same server; pickups/models remain primitive. |
| P3 | Remote hardening, movement sanity, telemetry | **Implemented for prototype** | Movement correction is heuristic and telemetry is server-log-only, not a production anti-cheat or analytics pipeline. |
| P4 | ProfileStore persistence and cave tiers | **Implemented for prototype** | Studio always uses isolated mock data; live persistence must be verified after publishing. |
| P5 | Party lobby and reserved expedition flow | **Implemented for friend testing** | One auto-joined party per server, using the same place as lobby and expedition. No invite codes, multi-party hub, queue matchmaking, or rejoin recovery. |
| P6 | Lineage and optional Basin variants | **Not started; deferred** | Lineage remains underspecified and must not become inherited raw power. |
| P7 | Global remains/braziers, production assets/ops, monetization | **Not started; deferred** | Requires product, abuse, expiry, and operations decisions. |

## What each implemented phase contains

### P0 — tests and diagnostics

- Dependency-free, config-derived suites cover WaxDrain, BrightnessMap, LightField, ThreatBrain,
  RoomNavigation, HazardRules, SacrificeRules, RewardMath, FloorPlanner, CandleGeometry, ToolRules,
  LootRules, and TokenBucket.
- `StudioTestRunner.server.luau` runs 54 deterministic cases in Studio only.
- Death results include a cause breakdown, and a resolved party can request an immediate run
  restart instead of waiting for the automatic reset.

### P1 — player-facing feel

- Low-wax pulse, dial snap, local flame flicker, and draft/water/near-threat feedback.
- A config-backed audio adapter; empty or invalid asset IDs fail safely.
- Threat labels are behind a debug flag and default off.
- Desktop/touch controls and free tool charges are visible in a hotbar sourced from the real
  bindings.

### P2 — run variety

- Deterministic wax-profile and prepared Flare/Cast pickups.
- Free activations travel through the normal tool validation/cooldown path.
- Session-local remains deposit, later-floor placement, Drawn-attracting light, and atomic
  capacity-limited recovery that preserves overflow.
- Seven depth-weighted threat rows, including Hollow, Ash Moth, and a Snuffer.
- Generic reciprocal-doorway routing lets every threat cross rooms without cutting through walls;
  the Basin is excluded from perception, contact, and navigation.
- Ten-floor planning data with larger rooms, longer wax life, lower threat budgets, and slower
  enemies for a longer prototype loop.

### P3 — public-prototype boundaries

- Every inbound RemoteEvent is type/finite-value validated and protected by a per-player token
  bucket.
- Basin and Brazier actions are rechecked against authoritative position/state.
- Movement accumulates from a one-second trusted anchor against sustained run speed plus a fixed
  jitter margin. Approved dodge/slide distances are allowed once; impossible displacement is
  corrected.
- Deaths, floor reach, Basin decisions, cash-outs, restarts, teleports, and corrections emit
  structured `[WICK]` server-log events.

### P4 — durable progression

- `Interfaces/Persistence.luau` owns a ProfileStore-backed `WickProfiles_v1` schema with session
  locking, reconciliation, lifecycle close, and a safe Studio Mock.
- Profiles contain currency, unlocked cave tier, cosmetics, runs completed, deepest floor, and
  total wax delivered. Starting wax is not increased.
- Shallows, Descent, and Deep tiers control maximum floor, threat-budget multiplier, and reward
  multiplier. Currency thresholds unlock access.

### P5 — prototype co-op session flow

- All players in a small public lobby auto-join one party, capped at four.
- The party tracks leader, member readiness, and selected cave tier; a tier change clears readiness.
- Every member must be ready and have the tier unlocked before the leader starts.
- Studio starts the expedition locally. A published server uses `TeleportAsync` with
  `ShouldReserveServer` and passes expedition/tier/member data to another server of the same place.
- The reserved server shows a waiting lobby until every expected member has loaded, or for at most
  eight seconds. It then begins the run countdown; a slower late arrival can still join the run.
- The expedition remains disposable; only player profiles are durable.

## Interface status and remaining stubs

| Interface | Current state | Importance | Next work / caution |
| --- | --- | --- | --- |
| `Persistence.luau` | **Implemented (P4):** ProfileStore live, Mock in Studio. | High for any public progression test. | Verify live load/save/session release with two accounts. Add explicit migrations before changing schema meaning; never use raw DataStore from gameplay code. |
| `CaveTiers.luau` | **Implemented (P4):** evaluates persistent access against three config-owned, gameplay-driving tiers. | Medium/high. | Tune rows in `Config/CaveTiers.luau` from live data; do not turn access progression into a larger starting candle. |
| `Party.luau` | **Implemented (P5):** one in-server party with leader/readiness/tier state. | High for friend tests. | A future multi-party/matchmaking design will need a broader contract; do not pretend this prototype is matchmaking. |
| `Remains.luau` | **Implemented (P2):** bounded session-local records and atomic partial claims. | Medium. | Claims preserve wax above the collector's capacity. Global/cross-server remains are P7 and require expiry, ownership, anti-duplication, and moderation semantics. |
| `Lineage.luau` | **STUB:** generation 1, no inherited trait, no consumer. | Low / P6. | Design the non-power-creep carryover first. Do not add persistence or UI until the open design question is settled. |

`Lineage` is the only true remaining interface stub. Global remains are not an unfinished
session-remains feature; they are a separate deferred backend/operations problem.

## Ranked work after Phase 5

1. **Run the publish gate.** Complete the Studio solo and two-client checks, then the live
   two-account teleport/persistence check in `PUBLISH-CHECKLIST.md`. Fix blockers before adding
   systems.
2. **Supply and tune sound.** Audio is still the largest product risk. Add approved asset IDs in
   `Config/Audio.luau`, then test whether cues are frightening, readable, and non-spammy.
3. **Playtest pacing and threat balance.** Measure actual completion/death times against the
   10–20 minute target. Watch for one dominant brightness setting, rooms that feel empty rather
   than tense, and movement correction false positives.
4. **Harden live session recovery.** Add a deliberate teleport failure/retry UX, disconnect and
   rejoin policy, profile-load failure observation, and operational analytics before broader access.
5. **Replace grey-box assets only where they improve the fear loop.** Prioritize sound, threat
   silhouette readability, hazard cues, and prompt accessibility over decorative content.
6. **Design P6 before coding it.** Decide whether Lineage or optional Basin variants add decisions
   without power creep. Leaving them deferred is valid.
7. **Treat P7 as separate production work.** Cross-server remains/braziers, monetization, voice,
   full matchmaking, and global operations each need their own approved design.

## Playtest questions

1. Does the brightness dial create meaningful choices, or does one setting dominate?
2. Can players understand the death breakdown and name a better choice next time?
3. Are silhouettes and audio readable without threat labels?
4. Does the longer/scarcer pacing build dread, or merely add walking time?
5. Does the Basin create a painful decision rather than a mandatory heal?
6. Do wisps remain engaged without making burnout strategically desirable?
7. Can two friends reliably form, teleport, cash out, restart, and retain progress?

## Explicitly out of scope

Do not add combat, classes, crafting, trading, PvP, housing, pets, dialogue, multiple biomes, a
second core resource, guilds, seasonal content, or an extraction sequence. Full matchmaking,
global remains, Lineage, and global braziers remain deferred until explicitly designed.
