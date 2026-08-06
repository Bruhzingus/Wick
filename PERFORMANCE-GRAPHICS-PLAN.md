# WICK — Performance & Graphics Plan

Full-codebase performance and rendering audit (269 files, ~78k lines of Luau), plus a cleanup pass
and a phased roadmap. Written so perf work and visual-quality work can proceed together without
undoing each other — every phase below states its effect on both axes.

**Method:** four parallel research passes (server perf, client perf, rendering/graphics, dead-code)
followed by manual verification of every claim against the actual source (grep for real call sites,
not just pattern-matching) before anything was either fixed or written down here. Nothing below is
speculative; each finding cites the file and line it was confirmed at, as of this pass. Line numbers
drift as the file changes — treat them as "look here," not a permanent address.

---

## Part 0 — What this pass already fixed

Everything in this section is **done, verified with `selene` (0 warnings/errors) and `stylua --check`
(clean), and safe** — each item was confirmed to have zero external callers (no dynamic dispatch, no
bracket-indexed calls, no doc-claimed usage) before removal, or is a one-line property fix matching an
established sibling pattern in the same file.

### Lint-detected dead code (4)
| File | What |
|---|---|
| `src/client/MusicController.luau` | `currentCueName` — write-only local, assigned 5×, read 0×. Removed. |
| `src/client/ShopController.luau` | `gui` — write-only local (`gui = screen`, never read). Removed. |
| `src/client/ShopController.luau` | `renderCaveList`: an `if`/`elseif` with identical bodies (`if IsA("GuiObject") then Destroy() elseif IsA("UIListLayout") or IsA("UIPadding") then Destroy()`) merged into one `or`-joined condition. |
| `src/shared/Logic/EchoGateRules.luau` | Unused `local Types = require(...)`. Removed. |

### Rendering bug: 3 lights missing `Shadows = false` (graphics + perf win, zero visual cost)
Every other decorative `PointLight` in this codebase explicitly sets `Shadows = false` (confirmed
pattern in `ToolService.luau`, `ThreatService.luau`, `FloorBuilder.luau`). These three didn't, so they
silently defaulted to Roblox's `Shadows = true` — meaning, on `Lighting.Technology = "Future"`, each
one opens a real-time shadow map. The client already enforces "exactly one shadow-casting light per
client, the player's own candle" (`CandleLightController.luau`); these were the leak in that budget.

| File | Light | Why it matters |
|---|---|---|
| `src/server/RemainsService.luau` (`PointLight` on a death pile) | missing `Shadows` (defaulted true) | Remains are session-local and accumulate across a run — an uncapped source of extra shadow lights until picked up. Fixed: `Shadows = false`. |
| `src/server/LobbyRoomBuilder.luau` (`LampLight` on each Lamp Network node) | missing `Shadows` (defaulted true) | Every node a party unlocks turns one more of these on, permanently, for the rest of the lobby session. Its own sibling lights (`wallCandle`, `ceilingLamp`) in the same file already pass `false` — this one was just missed. Fixed. |
| `src/server/VineService.luau` (`VineFireLight` on a burning doorway curtain) | **explicit** `Shadows = true` | Up to 3 curtains per floor can ignite together within a 30-stud spread radius — up to 4 concurrent shadow maps (3 vines + the player's own candle) at once. `MossFireService` sells the identical "this is burning" read with **no PointLight at all** (just a `Fire` instance) — a cheaper pattern already proven elsewhere in this file set. Fixed: `Shadows = false`. |

**Left as-is, needs a decision, not a bug fix:** `src/server/BrazierService.luau`'s ignition light also
defaults to `Shadows = true`. Unlike the three above, this is a once-per-player, end-of-run cinematic
moment, so a deliberate shadow may be intended. Recommendation: either add `Shadows = false` for
consistency, or keep `true` and add a one-line comment saying so on purpose — right now it reads as an
accident either way. Low priority; a party extracting individually could in principle stack a couple of
these, but the base rate is far lower than the vine-fire case.

### A real bug found while hunting dead code: `ShopService.reset()` was never called
`RunOrchestrator.teardown()` calls `.reset()` on every one of its ~24 sibling services
(`ThreatService`, `DripstoneService`, `VineService`, `WaxService`, `ExtractionService`, …) at the end
of every run — except `ShopService`. `ShopService.reset()` exists, clears three per-player tables
(`openSessions`, `inFlight`, `latestMessage`), and had **zero callers anywhere in the repo**. That's
not dead code to delete — every sibling proves the intended pattern is "wire it into teardown," and
this one was dropped. **Fixed:** added the require and the `.reset()` call to `RunOrchestrator.luau`,
in the same place and same style as its neighbors. Before this fix, stale shop session/rate-limit state
could survive across a run boundary. Verify in Studio: open the shop, trigger a purchase, complete a
run, and confirm no leftover "in flight" rejection on the next run's first shop interaction.

### Confirmed-dead exported functions removed (16, across 15 files)
Each was verified with a targeted grep across the whole repo (`\.functionName\(`) that matched **only
the definition line** — i.e., truly zero callers, not a false positive from bracket-indexed dispatch or
an aliased local. Two additional cases were exported aliases of locals that ARE used internally, just
never through the exported name (`RejoinService.clearMarker`/`.destinationFor`,
`ExtractionValue.isNonNegativeInteger`) — only the dead alias line was removed, the underlying logic is
untouched and still runs exactly as before.

| Symbol | File |
|---|---|
| `AmbientRockfallController.isActive()` | `src/client/AmbientRockfallController.luau` |
| `AudioCues.getMasterGroup()` | `src/client/AudioCues.luau` |
| `AudioCues.stopAll()` | `src/client/AudioCues.luau` |
| `CursorController.isReleased()` | `src/client/CursorController.luau` |
| `SignalBellController.stop()` | `src/client/SignalBellController.luau` (ripples already self-clean per-frame in `stepRipples`; this wasn't a missing-wireup case) |
| `CharacterService.hasSpectator()` | `src/server/CharacterService.luau` |
| `ExtractionService.runId()` | `src/server/ExtractionService.luau` |
| `ExtractionService.carriedUnits()` | `src/server/ExtractionService.luau` |
| `PartyLobbyService.tierId()` | `src/server/PartyLobbyService.luau` |
| `RejoinService.graceSeconds()` | `src/server/RejoinService.luau` (its only reason to require `Config` — the require was removed too once this was gone) |
| `RejoinService.clearMarker` / `.destinationFor` (export aliases only) | `src/server/RejoinService.luau` |
| `AshamedLurkerRules.isOnTrapHalf()` | `src/shared/Logic/AshamedLurkerRules.luau` |
| `LampRules.contracts()` | `src/shared/Logic/LampRules.luau` |
| `OreRules.tiers()` | `src/shared/Logic/OreRules.luau` |
| `ExtractionValue.isNonNegativeInteger` (export alias only) | `src/shared/Logic/ExtractionValue.luau` |
| `Cave.drapery()`, `.flowstone()`, `.rimstonePool()`, `.scatter()` (+ its `ScatterOptions` type) | `src/shared/NewModelsAndObjects/CaveKit.luau` — 4 full formation-builder functions, ~230 lines, confirmed unused by every one of `CaveKit`'s 4 real consumers (`FloorBuilder`, `DevTestRoomService`, `AmbientRockfallController`, `UnstableDripstone`) and not referenced anywhere in any design doc either |
| `Config.Mining.deposit.modelId` | `src/shared/Config/Mining.luau` — a single unused data field (`"RawWaxDeposit"`), leftover from an earlier clone-a-model deposit system since replaced by procedural construction; all 7 real consumers of `.deposit` never read it |

**Deliberately NOT touched — flagged instead of deleted:**
- `src/server/EchoGateService.luau`'s `allOpen()` has zero callers but carries its own comment ("never
  read by gameplay") — reads as intentional diagnostic scaffolding, not an oversight. Left alone.
- **`UITheme.wordmark()` / `UITheme.candleGlyph()` / the `attachFlicker` RenderStepped loop behind them**
  (`src/client/UITheme.luau`, ~250 lines) have zero callers anywhere in `src/client/`. Normally that
  would put them in the delete list above — except `CodeBreakdown.md`'s own routing table (the "Shared
  UI palette... composited WICK wordmark/candle-glyph widgets" row) explicitly claims these are used by
  "every themed UI controller (LobbyController, PartyPanelController, BasinPrompt, ResultsText,
  SettingsController, WaxBar, HotbarController)." None of those seven files call it. That's a real
  discrepancy — either the WICK wordmark logo has silently disappeared from every UI surface that was
  supposed to show it (a content regression, not dead code), or it was deliberately pulled and the
  routing doc just never got updated. **This needs a product decision, not a code deletion — see Part 6.**

---

## Part 1 — The one big thing: floors are never retired

This is the highest-impact finding in the whole pass, independently verified by direct code reading
(not just the research agent's report):

- `RunOrchestrator.luau`: every floor a party builds is stored in `floors[plan.depth] = runtime` the
  moment it's carved. The **only** place anything is ever removed from that table is
  `table.clear(floors)` inside `teardown()` — i.e., full run end. There is no per-floor retirement as a
  party descends past a floor.
- `workspace.Terrain:Clear()` — same story: only called at `startRun()` and `teardown()`, never per
  floor. Every carved-terrain voxel from floor 1 is still fully resident while the party is on floor
  100.
- `default.project.json` sets `Workspace.StreamingEnabled = false` — confirmed. Nothing about this is
  mitigated by Roblox's streaming system; every old floor's parts and terrain stay fully loaded and
  simulated for every client, for the whole run, no matter how deep the party has gone.
- This is compounded because **every per-floor subsystem follows the identical "register on build,
  never unregister" pattern**, and each one's tick iterates *every floor ever built*, not just the
  party's current floor:
  - `ThreatService.tick()` walks `instances` (grows forever) every Heartbeat, running full AI — light-field
    calc, room navigation, 2–4 raycasts per threat (ground probe, wall-obstruction probe, and a roof
    probe for ambush/ceiling rows) — for every threat from every floor the party has ever visited.
    `Config/Floors.threatBudgetPerFloor` (1.2–4.4, further scaled by cave-family multipliers) means low
    hundreds of permanently-ticking threats by floor 50–100.
  - `DripstoneService.tick()` iterates `runtimesByDepth` — all depths, forever.
  - `VineService` and `MossFireService` (`sources()`, called every frame via `LightSources.collect`) —
    same full-history walk, and **neither has a `clearDepth` function at all** (confirmed by grep — no
    match in either file).
  - `AshamedLurkerService` runs three separate full-depth-history loops per tick.
  - `StoneWardenSystem/StoneWardenAnimator.lua` opens a **dedicated per-Warden `Heartbeat` connection**
    that runs procedural animation math every frame until the model is destroyed.
    `StoneWardenBehavior.lua`'s `_updateLoop` is a **per-Warden `while true do task.wait(...) end`**
    coroutine with the same exit condition. The code's own comment says *"RunOrchestrator destroys the
    whole floor model between runs"* — the developers assumed per-floor teardown that was never actually
    built. Every Warden ever encountered keeps its connection and coroutine alive for the rest of the run.
- `LightSources.collect` (called once per Heartbeat from `ThreatService.tick`) rebuilds its list from
  `MossFireService.sources()`, `RemainsService.sources()`, `ToolService.decoySources()`, and all lit
  players, every frame — inheriting the same unbounded-history cost from `MossFireService`.

**Net effect:** since depth is explicitly uncapped by design (`Logic/DepthRules.luau`), every one of
these costs grows without bound for the life of a run. A run that goes deep enough doesn't just get
slower — every subsystem above degrades simultaneously, and it never recovers until the run ends.

### Why this belongs in a plan, not a same-session autopilot fix
Implementing floor retirement is a genuine feature, not a compaction. It touches run-critical state
(what happens to a party member who walks back up a floor? a spectator following a teammate near a
retirement boundary? the elevator/replay path?) and needs real testing in Studio with a live multi-floor
run — which isn't available in this environment. It's written up here as a concrete, scoped design
instead.

### Proposed design
1. **Retirement policy.** Once no living runner's `state.depth` is within `N` floors of a built floor
   (and it isn't the current lookahead build target), that floor is eligible for retirement. `N` should
   be small (1–2) to allow a player who briefly backtracks (if that's ever possible) without punishing
   them, but otherwise as aggressive as gameplay allows — the whole point is bounding history length.
   Check this once per `RunOrchestrator` tick, alongside the existing lookahead-queue drain, so it costs
   nothing extra architecturally.
2. **Central teardown call, reusing what already exists.** `DripstoneService.clearDepth(depth)` and
   `AshamedLurkerService.clearDepth(depth)` already exist (currently only called from the dev test
   room) — reuse them directly.
3. **New `clearDepth(depth)` needed on:**
   - `VineService` — no equivalent exists today.
   - `MossFireService` — no equivalent exists today.
   - `ThreatService` — needs a "despawn every threat whose floor is `<= depth`" that destroys the
     instance's model and removes it from `instances`. This is also what transitively fixes the Warden
     Animator/`_updateLoop` leak (both already check `Parent == nil`/ancestry, so destroying the floor
     model that owns a Warden's rig ends its connection and coroutine on its own — no separate fix
     needed there once floor teardown calls through to it).
4. **Terrain.** Clear only the retired floor's own voxel region (`FloorBuilder` already knows each
   floor's Y-band/footprint from carving it — reuse that bound) rather than the whole `Terrain:Clear()`
   used today at full teardown. A targeted per-region clear keeps floors still in play untouched.
5. **Client-side.** Once server-side instances are destroyed, replication already removes them from
   every client for free — no separate client-side cleanup path should be needed, but verify no
   controller (e.g. `ThreatVisualController`, `LightSources`-derived UI) holds a stale reference past a
   `Destroy()` without checking `Parent == nil`/`AncestryChanged` (most already do, per the client-perf
   findings in Part 3, since disconnection-on-destroy is an existing pattern here).
6. **Do NOT flip `StreamingEnabled` as a substitute.** Streaming would band-aid the *rendering* side for
   clients standing still, but does nothing for the *server's* per-tick simulation cost (raycasts,
   navigation, Warden loops), which is the larger share of this problem. Floor retirement fixes both;
   streaming alone fixes neither on the server and would need careful tuning (spawn/load distances) to
   not itself introduce pop-in that hurts the "this cave is dark and close" visual identity. Revisit
   `StreamingEnabled` only after retirement ships, as a possible client-memory refinement, not instead
   of it.

### Test plan (for whoever implements this in Studio)
- Multi-floor descent (10+ floors) with a `DevDiagnostics` panel open, watching live threat/instance
  counts (`server/DevDiagnosticsService.luau` already surfaces server stats) before and after — instance
  count should plateau instead of climbing linearly with depth.
- Confirm a Warden encountered on floor 3 stops ticking (no more Heartbeat cost) once the party passes
  floor 5–6, by checking `StoneWardenAnimator`'s connection is gone (e.g. temporarily log on
  connect/disconnect during the Studio test, remove before commit).
- Confirm nothing currently reads a `floors[depth]` for a retired depth (grep `floors\[` call sites in
  `RunOrchestrator` — `firstFloor = floors[1]` at two call sites will need explicit handling once floor
  1 itself can retire on a long enough run).
- Confirm a mid-air/backtracking player (if ever possible) doesn't get stranded by a retired floor
  disappearing under them — this is exactly what the `N`-floor trailing margin in step 1 is for; tune it
  empirically.

---

## Part 2 — Server performance backlog (beyond floor retirement)

Everything here is either subsumed by Part 1 (gets fixed for free once floors retire) or independent.
Marked accordingly.

| # | Finding | File | Subsumed by Part 1? |
|---|---|---|---|
| 2.1 | `ThreatService.tick()` raycasts (ground/wall/roof probes) run per-threat per-Heartbeat with no distance/relevance pre-filter — currently the dominant per-tick CPU cost, multiplied by unbounded threat count | `src/server/ThreatService.luau` (`tick`, `groundPositionFor`, wall/roof probes) | **Yes, mostly.** Bounding threat count via retirement resolves the majority of this; a same-room/distance pre-filter is still worth adding afterward for the *current* floor's threats if profiling still shows cost. |
| 2.2 | `StoneWardenBehavior._trackNearestPlayer` allocates a fresh `PathfindingService:CreatePath` object every `pathRefreshSeconds` while a Warden is active, rather than reusing one | `src/server/StoneWardenSystem/StoneWardenBehavior.lua` (~line 430) | No — independent, low priority. Only worth batching if Studio profiling shows it matters; gated correctly by `state.depth == self.Depth` already so it's not a cost on abandoned floors even today. |
| 2.3 | `LightSources.collect` walks all-history `MossFireService.sources()` every frame | `src/server/LightSources.luau` | **Yes**, fully — goes away once `MossFireService` has depth-scoped state. |
| 2.4 | Remote traffic (`WaxService.replicate` full-snapshot `StateSync:FireAllClients`) | `src/server/WaxService.luau` | N/A — already fine. Throttled by `Config.Run.stateReplicationHz`, not every physics tick, and the 4-player cap keeps payload/frequency reasonable. **No action needed**; only revisit if the party cap ever changes. |
| 2.5 | No problematic `Instance.new`/`:Destroy()` churn found in mining/wax/light hot paths | — | N/A — confirmed clean, nothing to do. |

**Sequencing note:** do 2.1's distance pre-filter *after* Part 1 ships, not before — it's cheap insurance
on top of a bounded threat count, but implementing it first without bounding count first only delays
hitting the real ceiling, it doesn't remove it.

---

## Part 3 — Client performance backlog

These are independent of Part 1 (they cost frame time on the *current* floor's content, which floor
retirement doesn't change) and are safe to schedule in parallel with it. Ordered by impact.

### 3.1 Creature skin/eye repaint runs every frame regardless of whether anything changed
`ThreatVisualController.render` (bound to `RenderStepped`) calls each creature's `.update(...)`
unconditionally for everything within the 120-stud cull distance
(`Config/Threats.luau` `visuals.procedural`), every frame. That wrapper always calls `setIllumination`
(writes `.Color` on ~30–45 tracked parts per `DarkCrawler`-class creature) and `setAware` (which itself
calls `refreshEyes` a *second* time in the same frame) — even though the underlying
illumination/awareness values are server-replicated and change far less than 60Hz. Repeats across
`CaveListener`, `Knotwalker`, `CaveMoth`, `CeilingFly`, `Calver` (`src/shared/NewModelsAndObjects/*.luau`).

This is the single costliest client finding: it scales with creature count × parts-per-creature × 60fps,
and — once Part 1 ships — creature count itself stops growing with depth, but *current-floor* creature
count still climbs with `threatBudgetPerFloor`, so this is worth fixing regardless.

**Fix (preserves visuals exactly):** cache the last-applied illumination/aware value per tracked entry;
early-return from `setIllumination`/`setAware` (and skip the redundant second `refreshEyes` call) when
the incoming value hasn't materially changed (`math.abs(delta) < epsilon`). The lerp/animation still
reads live values on every call that *does* change — nothing about the visible motion changes, only the
no-op repaints are skipped.

**Secondary, same area:** the 120-stud cull distance is larger than a candle's actual light radius —
creatures the player can't see are still fully repainted. Worth revisiting downward once the repaint fix
above is in, as a second independent saving.

### 3.2 Mining's per-frame deposit scan double-works and allocates fresh objects every frame
`MiningController.update` (bound to `RenderStepped`) and `MiningWorldPresentation.updateGlow` each run
their **own independent** `CollectionService:GetTagged(depositTag)` walk over every tagged deposit in
the game every frame — not filtered to the current floor before the per-candidate work starts. For every
candidate within range, `MiningController.canSeeDeposit` builds a **brand-new `RaycastParams`** and a
**brand-new `Players:GetPlayers()`-derived table**, every frame, then fires a raycast.

**Fix:**
- Merge the two `GetTagged` walks (prompt-selection and glow) into one shared pass.
- Throttle both to ~10–15Hz — nearest-deposit prompt and glow are presentation polish, imperceptible
  below 60Hz.
- Hoist `RaycastParams` and the `characters` exclude-list out of the per-candidate loop; rebuild only
  when `Players:GetPlayers()` actually changes (a `PlayerAdded`/`CharacterAdded` cache invalidation,
  same pattern recommended for 3.5 below).

Files: `src/client/MiningController.luau` (`canSeeDeposit`, `findNearestDeposit`, `update`),
`src/client/MiningWorldPresentation.luau` (`updateGlow`).

### 3.3 Lamp-housing flicker never stops, even mid-expedition
`LampNetworkController.luau`'s `RenderStepped` connection walks every tagged lamp fixture in the lobby
(~two dozen rows) and reads an attribute off each, unconditionally, for the entire client session —
unlike every comparable controller (`SprintFeedbackController`, `MiningController`, etc.), this one is
never gated by the `WickInExpedition` attribute. A player deep in a cave floor still pays a full
tag-list rebuild + attribute-read pass every frame for a lobby decoration nobody can see.

**Fix:** early-return when `player:GetAttribute("WickInExpedition") == true`, or better, cache the
tagged-instance list and refresh only on `GetInstanceAddedSignal`/`RemovedSignal` instead of re-querying
`GetTagged` every frame regardless of state.

### 3.4 Shop UI does a full teardown + rebuild on every server push, not just relevant changes
`ShopController.renderCaveList` destroys and recreates every cave card (new `TextButton`, `UIStroke`,
`UIScale`, sub-widgets, event connections) on **every** `ShopState` push — including pushes triggered by
an unrelated action (e.g. buying a lamp node rebuilds the cave list too, even though it didn't change).
Lower severity than 3.1–3.3 since it's event-driven, not per-frame, but a clean example of "full
rebuild where an incremental diff would do."

**Fix:** diff `caveOffers` against the previously rendered set; only touch cards whose
`owned`/`purchasable`/`price` actually changed; keep unaffected card `Instance`s alive across pushes.

### 3.5 Minor / batch these opportunistically
- `CameraController.luau`: loops `character:GetChildren()` every `RenderStepped` frame to set
  `LocalTransparencyModifier` on `Flame`/`Wick` — these parts don't change identity after spawn; do this
  once in `bindToCurrentCharacter` instead.
- `AudioCues.applyOcclusion`: allocates a fresh `RaycastParams` + `Players:GetPlayers()`-derived
  exclude table on every occluded spatial sound play (footsteps, wingbeats, idle voices all route
  through this). Already correctly once-per-play rather than per-frame, but for high-frequency cues
  it's avoidable churn — cache the exclude list, invalidate on `PlayerAdded`/`CharacterAdded`.
- `CandleLightController.luau`: bounded by the 4-player cap so low absolute cost, but every teammate
  candle runs full multi-layer `FlameFlicker.sample` noise math every frame regardless of whether it's
  actually visible/near enough to matter. Not urgent given the cap; note for later if the cap ever rises.
- `WaxBar.luau`, `SprintFeedbackController.luau`, `FeelController.luau`: single-instance, local-player-only
  decorative per-frame loops. Trivial individually; not worth touching in isolation.

---

## Part 4 — Graphics & visual quality backlog

The engine choice itself (`Lighting.Technology = "Future"`, `GlobalShadows = true`) is **not** a problem
to walk back — it's well-justified by what's already built, and walking it back would cost more visual
identity than it would save. Confirmed already-correct, no action needed:
- `CandleLightController.luau` already enforces "exactly one shadow-casting light per client" (the
  player's own candle) — Part 0's three fixes closed the actual leaks in that budget.
- `Lighting.Brightness = 2` in `default.project.json` is a **Studio edit-mode convenience only** —
  `EnvironmentSetup.apply()` forces it to `0` the instant a server actually starts. Not a live setting.
- No `UnionOperation`/`NegateOperation` anywhere in the codebase (confirmed by grep) — cave geometry is
  plain `Part`/`WedgePart`/Terrain throughout, which is the cheap-to-render choice already.
- Materials are correctly resolved per cave family (`Slate`/`Basalt`/`Concrete`/`Rock`/`Glacier`/`Ice`/`Mud`)
  — no `SmoothPlastic`/`Plastic` anywhere on cave rock.
- Decorative dressing is consistently `CanCollide = false, CanQuery = false` with separate cheap
  invisible colliders carrying the actual physics (`CaveKit.luau`, `FloorBuilder.luau`).
- Terrain carving (`FloorBuilder.luau`, roof via `RoofGeometry.luau`) computes ground/roof/mask fields
  once per column rather than per voxel layer — already a bounded, one-time-per-room cost, not a
  per-frame or per-tick one.
- `MossFireService` is hard-capped by `maxActivePerFloor` across the whole expedition — genuinely can't
  runaway even with multiple simultaneous clusters. Vine embers, dripstone dust, and loot mist particle
  emitters are all low-rate, short-lifetime, bounded by low placement counts.
- Bloom/color-grade values in `Config/Light.luau` match the ART-BIBLE's documented recipe exactly.

### 4.1 (done) Shadow-casting light leaks — see Part 0
Remains, Lamp Network node lights, and vine fire all fixed. Brazier ignition light left as an explicit
decision point.

### 4.2 `ColorCorrectionEffect` proliferation — consolidate, don't just count
Five separate `ColorCorrectionEffect` instances currently coexist in `Lighting` simultaneously:
`CandleLightController.luau` (near-always enabled while lit), `FeelController.luau` (two — wading and
Basin sight-sacrifice), `AshamedLurkerController.luau`, `DripstoneController.luau`. Roblox composites
every *enabled* one as a separate full-screen pass; because each defines overlapping properties
(Brightness/Contrast/Saturation/Tint), two enabling at once (e.g. wading near a threat encounter) stacks
unpredictably instead of blending intentionally. Cost is modest on its own (post-effects are cheap next
to a shadow-mapped light), but it's both a small perf saving and a correctness fix at once.

**Fix:** consolidate to 1–2 shared `ColorCorrectionEffect` instances that each controller writes its
target values into (with an explicit blend/priority rule for when two want the screen at once) rather
than each owning its own instance. This is a genuine multi-file refactor — plan it as one, don't
speed-run it; the risk is entirely in getting the blend rule right, not in the mechanical change.

### 4.3 (quality experiment, not a fix) `ShadowSoftness = 0.8`
Near-maximum softness on the one light that uses it. Cheap in aggregate now that the shadow budget is
down to one light per client, but worth an A/B in Studio at `0.5–0.6` — a small, constantly flickering
flame's penumbra differences are hard to perceive in motion, so a lower softness (fewer blur samples)
may be visually indistinguishable while shaving a little off the one shadow pass every client pays every
frame. Untested hypothesis; cheap to try, revert if it reads worse.

### 4.4 (quality experiment, perf-neutral-to-positive) Dial light curve
`Config/Light.luau`'s `falloffExponent = 1.0` makes the brightness dial's range/brightness curve purely
linear. DESIGN's "useful middle band" means players spend most of a run in the low-to-mid dial range.
A mildly super-linear curve (`1.2–1.4`) would keep the flame dimmer/smaller through more of the ordinary
dial and reserve the dramatic range/brightness jump for the top — reading as a more convincing "small,
precious point of light in true dark" per the ART-BIBLE, while likely *reducing* average rendered light
radius across a session (less time spent near max range/brightness) — a rare case where the visual
change and the performance change point the same direction. Pure tuning-value change, zero code risk;
worth an in-Studio taste test.

---

## Part 5 — Combined phased roadmap

The point of doing this as one roadmap instead of two separate lists: several perf fixes are also
graphics fixes, and none of the remaining graphics recommendations cost meaningful performance, so there's
no real tension to manage — mostly a sequencing question of "what unlocks what."

**Phase 1 — Done this pass.** Dead-code cleanup, the 3 shadow-light bug fixes, the `ShopService.reset()`
wiring fix. Zero behavior risk beyond the reset fix (which restores *intended* behavior and is worth a
specific Studio smoke-test per Part 0).

**Phase 2 — Floor retirement (Part 1).** The foundational fix. Do this before investing further in
threat/Warden-specific micro-optimizations (2.1, 2.2) — it bounds the problem those would otherwise be
chasing. This is also implicitly a graphics change: it's what makes `StreamingEnabled` reconsideration
possible later without fighting an already-unbounded scene graph, though don't combine the two changes —
ship retirement alone first, verify it, then evaluate streaming separately if still warranted.

**Phase 3 — Creature/threat rendering (3.1) + current-floor threat raycast pre-filtering (2.1).** Do
these together since they touch the same subsystems (`ThreatVisualController` client-side,
`ThreatService` server-side) and both are pure "skip redundant work" changes with no visual delta.

**Phase 4 — Interaction-loop cleanup (3.2 mining scan, 3.3 lamp flicker gating, 3.4 shop rebuild).**
Independent of everything above; schedule whenever convenient, lowest risk of the perf items since each
is scoped to one controller.

**Phase 5 — Visual quality experiments (4.2 ColorCorrection consolidation, 4.3 shadow softness, 4.4
dial curve).** Tune/refactor these last, once the perf work isn't also touching the same lighting/camera
code — easier to isolate what changed if a Studio playtest says something looks different.

**Phase 6 (opportunistic, no urgency) — Part 6 backlog below.**

---

## Part 6 — Remaining cleanup backlog (flagged, not yet applied — needs a decision or a bigger refactor)

### 6.1 `UITheme.wordmark`/`candleGlyph` — decide, don't just delete
See Part 0. Either the WICK logo widget is missing from UI surfaces that are supposed to show it (check
`LobbyController`, `PartyPanelController`, `BasinPrompt`, `ResultsText`, `SettingsController`, `WaxBar`,
`HotbarController` against what's actually on screen in Studio), in which case wire it back in, or it
was deliberately removed, in which case delete the ~250 dead lines in `UITheme.luau` (including the
`attachFlicker` `RenderStepped` loop, which currently never runs since nothing reaches it) **and** update
`CodeBreakdown.md`'s routing row to stop claiming it's used. Either resolution is fine; leaving it
split between "claims to be load-bearing" and "actually dead" is the only bad state.

### 6.2 Duplicated weighted-random selection — consolidation candidate, not urgent
The same cumulative-sum weighted-pick algorithm (NaN-guard, `math.clamp(roll, 0, 0.9999999) * total`,
`cumulative += weight; if target < cumulative then return`) is independently reimplemented in
`CaveFamilyRules.luau`, `DripstoneRules.luau`, `MiningRules.luau` (**twice**, in the same file),
`OreRules.luau`, `SacrificeRules.luau`, and six separate local functions inside `FloorPlanner.luau`
(`weightedModule`, `weightedDryModule`, `weightedWaterModule`, `weightedThreat`, `weightedLoot`,
`weightedDripstoneVariant`). No shared helper currently exists. A new `src/shared/Logic/WeightedPick.luau`
is the obvious home — but each call site has slightly different pre-filtering (skip `weight <= 0`,
fallback behavior on an empty list), so this needs careful parameterized extraction and a full pass of
the existing `Tests/` suite afterward, not a blind mechanical merge. Worth doing for maintainability, not
performance — the actual runtime cost of the duplication itself is negligible.

### 6.3 Duplicated horizontal-distance pattern — lower priority, wider blast radius
`Vector3.new(v.X, 0, v.Z)`-style flattened distance/heading math is inlined 25+ times across 15+ files.
Two files already independently named this exact operation
(`MovementSanityService.horizontalDistance`, `ContractWatchService.distanceToNearestTeammate`) without
either becoming the shared version. Real duplication, but many call sites use the flattened vector for
different follow-on purposes (not just a distance check), so consolidating safely means touching a lot
of files for a purely stylistic win. Lowest priority item in this document.

### 6.4 `EchoGateService.allOpen()` — leave as-is
Zero callers, but has its own "never read by gameplay" comment. Reads as deliberate diagnostic
scaffolding. No action recommended.

---

## Appendix — How to verify any of this yourself

This environment can't launch Roblox Studio, so nothing above was verified by actually running the game
— only by reading the source and cross-referencing every call site. Before trusting a specific fix in a
live build:

- `selene src` and `stylua --check src` both pass clean as of this pass (0 errors/warnings) — rerun
  after any further change.
- `src/server/StudioTestRunner.server.luau` runs everything in `shared/Tests/` in Studio only — run it
  after any `Logic/`-layer change (the weighted-random consolidation in 6.2 especially).
- For the floor-retirement work in Part 1 specifically: there's no substitute for a real multi-floor
  Studio playtest with `DevDiagnosticsService`'s live counters open, watching instance/threat counts as
  depth increases before and after the change.
- For the graphics items (4.2–4.4): these are subjective-by-nature (post-effect blending, shadow
  softness, light curve feel) — treat the recommendations as starting points for an in-Studio taste
  pass, not settled values.
