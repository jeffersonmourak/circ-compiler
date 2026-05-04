# Initiative status — Dead code removal

## 2026-05-04 — Phase 2 — Strip dead build targets

**What shipped:** Removed `logic-sim` executable, `compiler` executable, and the `compiler`, `compiler:run`, and `run` steps plus their `installArtifact` / run wiring from `build.zig`. Kept the temporary `main.zig` test root (`exe_debug_mod` + `unit_tests`) until Slice 2.

**Files touched:** `build.zig`

**Tests:** ran `zig build test`, result pass; `zig build logic-sim` → no step named `logic-sim`.

**Next slice:** Phase 2 — Delete `main.zig`, `lib/compiler.zig`, remove root `unit_tests` from `test` step.

**Notes:** None.

## 2026-05-04 — Phase 2 — Delete legacy source files

**What shipped:** Deleted `main.zig` (repo root) and `lib/compiler.zig`. Removed `unit_tests` / `run_unit_tests` and their `test` step dependency (the old root had no `test` declarations). **`lib/transport.zig` kept** — `lib/circuit.zig` depends on `transport.encodeState`. Updated `DOCS/PLANS/PHASE_2_legacy_zig_binaries.md` and audit rows in `DOCS/PLANS/PHASE_0_audit.md` to match.

**Files touched:** `build.zig`, `main.zig` (deleted), `lib/compiler.zig` (deleted), `DOCS/PLANS/PHASE_2_legacy_zig_binaries.md`, `DOCS/PLANS/PHASE_0_audit.md`

**Tests:** ran `zig build test`, result pass.

**Next slice:** Phase 3 — remove commented-out dead wiring in `build.zig` per `DOCS/PLANS/PHASE_3_stubs_and_placeholders.md`.

**Notes:** `zig build compiler`, `zig build run`, `zig build compiler:run` all report missing steps as expected.

## 2026-05-04 — Phase 0 — Audit inventory (retroactive)

**What shipped:** Completed `DOCS/PLANS/PHASE_0_audit.md`: baseline note, **Known Suspects** and **Newly Discovered Items** tables with full schema, audit sign-off block (human approval still pending), and Open Questions spike for **Phase 2 vs `lib/transport.zig`**. No code or `build.zig` edits.

**Files touched:** `DOCS/PLANS/PHASE_0_audit.md`

**Tests:** ran `zig build test`, result pass.

**Next slice:** Phase 3 — `build.zig` comment cleanup; or formal human sign-off on Phase 0 when convenient.

**Notes:** Phase 2 landed 2026-05-04 after this entry was written; `transport.zig` retained per `circuit` dependency.

## 2026-05-04 — Phase 1 — Frontend tree removal

**What shipped:** Removed the tracked browser/TypeScript surface: `src/`, `package.json`, `tsconfig.json`, `bun.lock`, and `node_modules/` (via `rm -rf`). The `example/` demo directory was already gitignored locally and was deleted from the working tree for consistency with the phase goal.

**Files touched:** `src/index.ts`, `package.json`, `tsconfig.json`, `bun.lock` (deleted); `node_modules/`, `example/` (removed locally, not tracked in git).

**Tests:** ran `zig build test`, result pass.

**Next slice:** Phase 1 — Zig WASM library removal (`lib/wasm.zig` + `wasm` / `wasm_step` wiring in `build.zig`).

**Notes:** `DOCS/STATUS.md` did not exist at session start; Phase 0 audit tables in `DOCS/PLANS/PHASE_0_audit.md` are still TODO placeholders if you want a formal sign-off pass.

## 2026-05-04 — Phase 1 — Zig WASM library removal

**What shipped:** Deleted `lib/wasm.zig` and removed the `wasm32-freestanding` target query, the `circ-renderer-lib-wasm` executable, `b.installArtifact` for it, and the `wasm` step (including install paths under `zig-out` and the former `example/` wasm copy). `zig build wasm` now fails with `no step named 'wasm'`.

**Files touched:** `build.zig`, `lib/wasm.zig` (deleted).

**Tests:** ran `zig build test`, result pass.

**Next slice:** Phase 2 — Strip legacy build targets from `build.zig` (Slice 1 per `DOCS/PLANS/PHASE_2_legacy_zig_binaries.md`).

**Notes:** `DOCS/PLANS/PHASE_2_legacy_zig_binaries.md` plans deleting `lib/transport.zig`, but `lib/circuit.zig` calls `transport.encodeState` (live simulation path). Before Slice 2 of Phase 2, either relocate that encoding or revise the phase spec—dropping `transport.zig` as written would break the build.
