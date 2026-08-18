# ARCHITECTURE — WICK

**Read `DESIGN.md` and this file before making any change.** DESIGN.md is the
source of truth. Never contradict it. If a request conflicts with DESIGN.md,
stop and flag it rather than implementing it. This file stays short on purpose —
it is read at the start of every session.

**Current implementation:** the grey-box prototype is implemented through Phase 5. Session-local
remains, ProfileStore-backed profiles, cave families, and independent elevator-party/reserved-server
flows are real prototype implementations. `Lineage` is the only remaining interface stub.

Caves are described by `Config/CaveFamilies` and interpreted by `Logic/CaveFamilyRules`.
`Config/CaveTiers` is a DERIVED projection of those rows onto the numeric tier id the lobby, shop,
party and elevator layers already speak; ownership is persisted by stable family id.

## Coding rules

- `--!strict` at the top of every `.luau` file. No exceptions. No `any` without
  a comment explaining why.
- One responsibility per file. If a file does two things, split it.
- All tunable values live in config tables under `src/shared/Config/` — never
  hardcoded in logic. A bare number in a logic file is a bug.
- Pure game logic must not touch Roblox Instances. Wax math, reward
  calculation, sacrifice application and threat decisions are pure functions
  taking state and returning state. Instance manipulation lives in thin
  adapter layers that call into them.
- The server is authoritative for every wax value. The client displays; the
  server decides.

## Folder map

- `src/server` → ServerScriptService. Authority, validation, persistence.
- `src/client` → StarterPlayerScripts. Input, camera, visuals.
- `src/shared` → ReplicatedStorage. Types, config data, pure math.
- `src/replicatedfirst` → ReplicatedFirst. Only the earliest-possible boot screen; runs before
  `ReplicatedStorage.Shared` is guaranteed available, so it cannot depend on shared modules.

Filename convention:
- `Foo.server.luau` → a `Script`
- `Foo.client.luau` → a `LocalScript`
- `Foo.luau` → a `ModuleScript`

## Invariants — never violate

- **Wax is the only resource.** Never add a second core meter. Consumable COUNTS (Match charges, free
  tool charges, dynamite sticks) are not meters: nothing drains them over time, the HUD draws no bar
  for them, and no rule converts one to or from wax.
- **Tools manipulate threats; they never damage them.** The three tools are still the whole tool set
  and this still binds every one of them. **Dynamite is the single authored exception to "there is no
  combat"** (owner decision, DESIGN §6a): it is a rare found consumable, not a `ToolId`, it can kill,
  and it damages the player who used it. The exception is bounded by numbers in `Config/Dynamite`
  (supply schedule, carry cap, self-damage, floor-wide noise) rather than by convention — widen those
  and you are widening the exception, so treat them as design surface, not tuning. The Grub Queen boss
  floor (`Config/GrubQueen`, DESIGN §9a) is a second, narrower exception in the same family: her
  descent ladder refuses a rider until she is dead, which is the one hazard in the game a party cannot
  simply route around. Everything else a threat or hazard system adds must remain something a party may
  choose to avoid entirely.
- **No code may assume exactly one player exists.** All player state lives in
  per-player tables keyed by userId — never singletons, never module-level
  variables. Solo is a player count, not an architecture. Party cap is 4.
- **Deferred or replaceable backends keep focused interfaces.** Mark true stubs clearly.
  Persistent/session storage belongs behind `shared/Interfaces`; Roblox Instance adapters and UI
  belong in focused services/controllers. Do not let a backend API leak across gameplay systems.
- **A cave family is data, not a code path.** Wick supports a small fixed set of mechanically
  distinct cave families (Stone, Moss, Ice). Every family must change topology, environmental
  pressure, threat ecology, or another existing system; cosmetic-only duplication is prohibited. All
  families share one generator, one validator, one survival resource and the same no-combat rules,
  and all begin at global depth 1. `Config/CaveFamilies` is the only place a family is described and
  `Logic/CaveFamilyRules` the only place that description is interpreted — no service, planner or
  builder may branch on a family id. A family owns what a cave CONTAINS (threats, formations, sounds)
  and what it is MADE OF (rock, cover, creature dressing). It never owns a stat, a radius, a speed, a
  perception value or a cue's gain — those are identical in every cave, which is what keeps "this cave
  is different" from becoming "this cave hides things from you."
- **A family-exclusive creature is a weight of zero, not a branch.** Signature creatures live in the
  ordinary `Config/Floors` allow-lists and the ordinary spawn roll; the families they do not belong to
  weight them to zero, which the planner already reads as "not here". The same is true of
  family-exclusive falling formations and ambient sound events. If a new kind of content ever seems to
  need `if familyId == ...`, it needs a resolver on `CaveFamilyRules` instead.
- **Content is data, not classes.** Threats, sacrifices, tools, wax types and
  room modules are entries in config tables consumed by generic systems.
  Adding one must never mean writing a new class.
- **The floor planner owns horizontal gameplay placement.** Once an X/Z has passed the room-footprint,
  route, water and mutual-clearance checks, `FloorBuilder` carves/reserves that exact footprint and a
  runtime adapter may reconcile only its built-Terrain Y and tangent normal. It may not relocate the
  object into an unplanned hub/ring slot, discard another reservation, or spawn a manufactured fallback
  after a surface probe fails. Rigid loot/ore receives a small blended shelf at its natural local
  elevation; the cave remains uneven everywhere outside that contact patch. `FloorBuilder` must cross
  one simulation boundary after its final Terrain mutation and before any built-Terrain query; the
  orchestrator serializes floor builds across that yield so no consumer can observe a partial floor.
- **Between-floor descent is physical and one-way.** A successor floor's world origin aligns its
  entry below the previous completion elevator while its grid remains floor-local. The lower landing
  has no call control: riders leave, are gently ejected if necessary, and the cage returns empty.
  Enemy exclusion is temporary and scoped from gate closure through post-arrival grace; it must not
  become a general safe-room or invulnerability system.

## Scope boundaries

**Cut:** complementary sacrifices · combat · classes · extraction sequence

**Implemented for the Phase 0–5 prototype:** session-local remains · ProfileStore player
profiles · cave tier unlocks/selection · independent party queues formed by entering elevator cars ·
same-place reserved expedition teleport

**Still deferred:** lineage · contextual Basin offers · public Basin · global/cross-server
remains · global brazier persistence · full matchmaking/invites/party browser · disconnect/rejoin
recovery

**Never:** crafting · trading · PvP · housing · pets · dialogue trees ·
cosmetic-only biome duplication · a second core resource · guilds · a second lethal item
(dynamite is the one authored exception and is not a precedent)
