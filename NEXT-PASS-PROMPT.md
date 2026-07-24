# PROMPT — Pass 3: content, tests, feel, and hardening

Read in this order before writing anything: DESIGN.md, ARCHITECTURE.md, STRUCTURE.md,
TUNING.md, IMPLEMENTATION-NOTES.md, then skim src/shared/ (Types, Config, Logic, Interfaces,
Net) and src/server/. Do not start until you can state, from those files, how a tool activation
travels from ToolController to a threat's next decision.

## Context

The vertical slice is playable: every v1 system exists and interacts (see STRUCTURE.md for the
as-built map, IMPLEMENTATION-NOTES.md for deviations and trust boundaries). It has survived one
playtest round. This pass makes the slice *complete, testable, and robust* — it does NOT add
the hub, persistence, or any deferred system. A later pass does those.

## Non-negotiable rules (unchanged, will be checked)

1. `--!strict` everywhere; no `any` without a justifying comment.
2. Every new number lives in `src/shared/Config/` with a one-line comment stating what it does
   and which direction is harder, plus a row in TUNING.md under the right feel-question group.
   A bare number in a logic file is a failure.
3. Content is data. A new threat, loot item, or sacrifice must be a config row consumed by the
   existing generic systems. If you write a class or a per-item branch, stop.
4. Pure logic stays in `src/shared/Logic` and never touches an Instance. New rules
   (loot placement, spawn weighting, flicker curves) follow the same split: pure module +
   thin adapter.
5. All wax mutations remain server-side, routed through the existing single points
   (WaxService.drainExternal, the drain pipeline, validated action charges).
6. Per-player state stays in PlayerState keyed by userId. Party cap 4. No singletons.
7. Deferred systems are called only via `shared/Interfaces` stubs. You may make a stub's
   in-memory behaviour richer (see Remains below); you may not add DataStore/Teleport/
   MessagingService calls anywhere.

## Workstream 0 — playtest fixes

[I will paste my current bug/feel list here before you start. Fix these first; they gate
everything else.]

## Workstream 1 — pure-logic test suite (highest priority after fixes)

DESIGN §19 mandates tests on the combinatorial systems; none exist yet. Every module in
`src/shared/Logic` is already pure — cover them:

- Add TestEZ via Wally dev-dependencies (`wally.toml` [dev-dependencies], run `wally install`;
  Packages/ is already gitignored). Colocate specs as `Foo.spec.luau` next to each Logic module.
- A `TestRunner.server.luau` in src/server that runs only in Studio
  (`RunService:IsStudio()`) and prints a pass/fail summary on boot; document how to read it.
- Required coverage (table-driven cases, exact numbers from Config so specs survive retuning):
  - WaxDrain: idle vs bright drain, exponent curve, movement modes, cup upkeep, draft/water
    contributions, burnout clamp at exactly 0, movementModeForSpeed cutoffs.
  - BrightnessMap: endpoints, falloff exponent, wax-type and cup multipliers.
  - LightField: falloff to zero at range, summation, strongestSourceNear excluding
    non-attracting sources for the drawn.
  - ThreatBrain: drawn seeks brightest attractor / ignores cold wax; hunter flees above repel
    threshold, hunts below hunt threshold, follows freshest trail, wanders otherwise.
  - HazardRules: waterAssessment boundaries (exactly at lethal fraction), draftThreatens.
  - SacrificeRules: applicability filtering, weighted roll without replacement, depth decay,
    penalty divisor, every handler's modifier output, Tool resolution from owned set.
  - RewardMath: formula, depth clamp, group term with 0..3 additional players.
  - FloorPlanner: same seed → identical plans; room counts; basin/brazier/entry distinctness;
    no threat/hazard in entry or basin rooms; doorways always reciprocal.
  - CandleGeometry & ToolRules: boundary cases (zero wax, cooldown edge, relight delay edge).

## Workstream 2 — in-run loot (DESIGN §15)

Loot placement is plan-driven: extend FloorPlanner (pure) to emit `lootSpawns` from a new
`Config/Loot.luau`, and a small server LootService to build pickups (ProximityPrompt) and
apply them. All rows in config:

- **Wax types**: pickups that set `state.waxTypeId`. The profiles already drive all math —
  placement is the only missing piece. Cold wax must be rare (weight in config).
- **Consumables**: spare flare charges and pre-made decoys. Semantics (decided): a charge is
  one activation of that tool with `waxCost = 0`; charges are consumed before wax is spent.
  Reintroduce a `toolCharges: { [ToolId]: number }` field on PlayerRunState, checked and
  decremented inside the existing ToolService/ToolRules path — no parallel activation route.
- **Loot budget per floor** in config (like threatBudgetPerFloor); deeper = slightly more and
  better-weighted loot.

## Workstream 3 — Remains, made real within the stub's contract

`Interfaces/Remains` currently returns nothing. Make its in-memory implementation actually
store deposits for the server session and have RunOrchestrator spawn remains pickups on floor
build (light source + recoverable wax via prompt, amounts already computed via
`Death.remainsWaxFraction`). The interface file stays the single swap point for a future
cross-server version. Remains must also enter the light field (they are light sources —
LightSources is the hook).

## Workstream 4 — threat roster and depth scaling

- Add one more threat row per category (aim: a slow area-denial dark-hunter; a fast, fragile-
  feeling drawn that overshoots) and a **Snuffer** row (`contactEffect = "Snuff"`,
  `waxDamagePerSecond = 0`) — the system already supports it; this is config + room allowlists.
- Depth-based spawn weighting: extend Floors config so deeper floors weight nastier rows
  (a `spawnWeightsByTier` table, pure change in FloorPlanner). Threat variety must remain
  a data statement, not code.

## Workstream 5 — feel pass (config-driven, zero assets)

- **Flame flicker**: subtle noise on light Range/Brightness (client-side, cosmetic; a pure
  flicker curve module + client adapter). Flicker intensifies while in a draft — this is the
  draft warning. Parameters in a new `Config/Feel.luau`.
- **Low-wax warning**: wax bar pulse below a config threshold. Nothing else on screen.
- **Snap feedback**: brief brightness blip when the dial crosses a snap point.
- **Threat labels**: gate the BillboardGui name labels behind a `Config/Feel.debugLabels`
  boolean (default true for now). DESIGN §16 wants unlabeled silhouettes eventually.

## Workstream 6 — audio skeleton (wiring only — the #1 risk in DESIGN §20)

No sound assets. Build the plumbing so a sound designer ships by editing one file:
- `Config/Audio.luau`: every game event mapped to `{ soundId = "", volume, category }` rows.
- A client AudioCues module subscribing to existing remotes/events: snuff, relight, flare,
  cast, cup start/end, basin offer/accept, brazier preview/commit, descent, hunt-start
  (threat acquires a player — needs one new field on an existing replication payload, not a
  new remote), water wading, draft exposure, burnout, death.
- SoundGroups per category (SFX/ambience/UI) on SoundService.
- Empty `soundId` rows must no-op silently.

## Workstream 7 — server hardening

- **Rate limiting**: a small shared token-bucket module; apply per-player per-remote caps in
  every OnServerEvent handler (caps in config). Excess requests are dropped silently.
- **Movement sanity**: per tick, if a character's displacement exceeds
  `maxSpeed × dt × slack` (config), snap it back to the last good position. Slack must be
  generous enough for dodges and slides — compute from Movement config, don't guess.
- **Audit**: every remote payload field type/NaN-checked (most are; verify all).

## Explicitly out of scope for this pass

Hub place, party formation UI, TeleportService/reserved servers, MessagingService, ProfileStore
persistence, cave tiers, meta progression spends, lineage, monetization, art, animation, sound
assets, and everything on ARCHITECTURE.md's DO NOT BUILD list. If a workstream seems to need
one of these, flag it and stop rather than building it.

## Deliverables

1. All workstreams implemented, `selene` and `stylua --check` clean, `rojo build` passing.
2. Every new tunable in Config + TUNING.md (right feel-group, harder-direction noted).
3. STRUCTURE.md updated for new modules; IMPLEMENTATION-NOTES.md updated with deviations and
   a fresh manual test script covering: loot pickup/charge consumption, remains recovery,
   snuffer read, depth-scaled spawns, flicker-as-draft-warning, rate-limit behavior, and the
   test-runner output.
4. A gameplay test checklist at the end of your report, ordered so I can verify in one
   two-client session.

## Process

Show me your implementation plan and file-change list FIRST — including your proposed
`Config/Loot.luau` and `Config/Feel.luau` shapes and the two new threat rows with their
numbers — and wait for my confirmation before writing code. Build in workstream order
(0 → 7). Tests before content: Workstream 1 locks the rules the rest builds on.
