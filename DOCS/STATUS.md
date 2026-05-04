# Initiative status — Dead code removal

## 2026-05-04 — Phase 0 — Audit inventory (retroactive)

**What shipped:** Completed `DOCS/PLANS/PHASE_0_audit.md`: baseline note, **Known Suspects** and **Newly Discovered Items** tables with full schema, audit sign-off block (human approval still pending), and Open Questions spike for **Phase 2 vs `lib/transport.zig`**. No code or `build.zig` edits.

**Files touched:** `DOCS/PLANS/PHASE_0_audit.md`

**Tests:** ran `zig build test`, result pass.

**Next slice:** Human sign-off on Phase 0 inventory; then continue **Phase 2 slice 1** per plan (after Phase 1 commit), after revising Phase 2 if `transport.zig` must stay.

**Notes:** Phase 0 was supposed to precede Phase 1 per dependency order; inventory documents **Phase 1 (shipped)** rows for browser/wasm removals already merged in the tree.

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
