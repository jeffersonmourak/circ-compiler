# STATUS — Console polish

One entry per shipped slice, newest last. The plan is `DOCS/PLANS_PROMPT.md`; the phase specs are under `DOCS/PLANS/`. This plan follows the archived playground driver (`DOCS/archive/plan-playground-driver.md`) on the same branch, by the human's ask.

## 2026-09-11 — Phase 0 — events with their details

**What shipped:** `sim-session.ts`: `DriveAssign`; a `drive` event carries `assigns` (name, value, the mask the runtime received) beside `names`; a `memory` event says its `op` — `poke` with `addr`, `value`, `defined`; `clear`; `load` with `words`; `notifyExternal(assigns)` takes what the canvas drove, which `onPinChange` in the island now passes; `applyPreloads({ silent })` emits a `load` or a `clear` per image it applied unless silent, and the build and `reset` apply silently so the handshake stays the record of those moments.
**Files touched:** `site/src/scripts/sim-session.ts`, `site/src/components/Playground.astro`, `site/test/sim-session.test.ts`, `DOCS/STATUS.md`
**Tests:** the drive, eval, external-notify, memory and load cases assert the new payloads; added one (a face's `applyPreloads` reports a `load` of two words, an emptied image a `clear`, `silent` nothing); ran `bun test` over the session, artifact, executor, transcript and data-view files (43 pass), `bun --bun run typecheck` (0 errors), result pass
**Next slice:** the Memory panel through the session.
**Notes:** the `load` word count in a preload event is `bytes.length / bytesPerWord`, from the plan the session applied, not from the runtime.
