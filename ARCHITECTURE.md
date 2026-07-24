# ARCHITECTURE — WICK

**Read `DESIGN.md` and this file before making any change.** DESIGN.md is the
source of truth. Never contradict it. If a request conflicts with DESIGN.md,
stop and flag it rather than implementing it. This file stays short on purpose —
it is read at the start of every session.

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

Filename convention:
- `Foo.server.luau` → a `Script`
- `Foo.client.luau` → a `LocalScript`
- `Foo.luau` → a `ModuleScript`

## Invariants — never violate

- **Wax is the only resource.** Never add a second core meter.
- **There is no combat.** Tools manipulate threats; they never damage them.
- **No code may assume exactly one player exists.** All player state lives in
  per-player tables keyed by userId — never singletons, never module-level
  variables. Solo is a player count, not an architecture. Party cap is 4.
- **Deferred systems get real interfaces backed by in-memory stubs.** Mark
  every stub clearly. Replacing a stub with a real implementation must touch
  exactly one file.
- **Content is data, not classes.** Threats, sacrifices, tools, wax types and
  room modules are entries in config tables consumed by generic systems.
  Adding one must never mean writing a new class.

## DO NOT BUILD

**Cut:** complementary sacrifices · combat · classes · extraction sequence

**Deferred (stub only):** remains/wax pools · lineage · contextual Basin
offers · public Basin · global brazier persistence · party formation ·
matchmaking · profile persistence · cave tier unlocks

**Never:** crafting · trading · PvP · housing · pets · dialogue trees · story ·
multiple biomes · a second core resource · guilds · seasonal content