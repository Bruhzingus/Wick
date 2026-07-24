# NEXT PASS — validate the Phase 0–5 friend prototype

The earlier “Pass 3” build prompt has been completed and is superseded. Do not reimplement its
tests, loot, remains, threats, feel, security, persistence, cave tiers, or party flow.

## Read first

1. `AGENTS.md`
2. `DESIGN.md`
3. `ARCHITECTURE.md`
4. `CodeBreakdown.md`
5. `IMPLEMENTATION-ROADMAP.md`
6. `PUBLISH-CHECKLIST.md`

Use `CodeBreakdown.md` to read the smallest owning file set for any failure. Do not broadly scan
the repository unless evidence shows that the problem crosses systems.

## Current state

The grey-box prototype is implemented through Phase 5:

- 59 deterministic pure-rule tests with a Studio-only runner
- feel/audio plumbing and a visible desktop/touch control hotbar
- loot, free tool charges, session-local remains, and eight depth-weighted threats including VoidFly
- remote throttles, finite-payload checks, movement correction, and structured server logs
- ProfileStore player profiles plus three cave tiers
- one auto-joined party per lobby server and a same-place reserved expedition teleport
- a larger/slower/sparser 10-floor pacing surface and result-screen replay/lobby-return handling

Important limitations: Studio uses ProfileStore Mock and local expedition startup; the uploaded
menu/cave tracks still require live permission verification and one-shot cues are mostly unassigned;
the lobby is not full matchmaking; rejoin recovery and global remains are deferred.

## Next objective

Run `PUBLISH-CHECKLIST.md` in order and fix only evidence-backed blockers:

1. dependency/build/lint/format gates;
2. Studio test signal and solo smoke test;
3. Studio two-client relight/Basin/Brazier/remains test;
4. published two-account reserved-teleport and persistence test;
5. verify the uploaded project tracks and run a focused sound/feel pass.

Record the exact failing step, Output error, reproduction, and owning route before editing. Keep
server wax authoritative, preserve the no-combat/one-resource design, add regression coverage for
pure-rule bugs, and update `CodeBreakdown.md` whenever ownership/contracts change.

Do not start Lineage, global remains/braziers, full matchmaking, monetization, combat, classes, a
second resource, or other deferred/cut systems during this validation pass.
