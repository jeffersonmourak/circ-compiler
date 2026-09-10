# Status — layout rewrite

Append-only log, one entry per shipped slice. Newest at the bottom. See `DOCS/PLANS_PROMPT.md` for the phase index and `DOCS/PLANS/PHASE_<N>_*.md` for each phase's spec.

## 2026-09-10 — Phase 0 — Slice 1: revive the JSON dump and start the log

**What shipped:** `lib/preview/dump_json.zig` — `dumpLayoutJson(writer, grid)`, the camelCase common-subset projection of a `LayoutGrid` — restored byte for byte from the discarded attempt (`git show layout-v1-attempt:lib/preview/dump_json.zig`, commit `4fb480e`), with its `build.zig` module and test step placed after `preview_dump_mod`. `DOCS/decisions/preview-layout.md` created with "The parity contract is a JSON projection, not either side's native type" and registered in `DOCS/decisions/index.md`. This file. No layout code touched; no golden touched.
**Files touched:** `lib/preview/dump_json.zig` (new), `build.zig`, `DOCS/decisions/preview-layout.md` (new), `DOCS/decisions/index.md`, `DOCS/STATUS.md` (new).
**Tests:** `dump_json: emits the contract shape and parses back as JSON`, `dump_json: empty grid and escaped names` (both from the revived file); ran `zig build test` (pass), `zig build test-all` (pass); `git diff --stat tests/fixtures` empty.
**Invariants:** not measured yet (slice 4 puts the table on record).
**Next slice:** Slice 2 — `lib/preview/layout/invariants.zig`, the render-free I0–I3 checker with its unit tests.
**Notes:** The attempt's `build.zig` diff also stripped every pre-existing trailing-whitespace line; only the module block was carried, per the plan prompt's *Build and goldens* trap. The renderer's `host-pin-api` still sits at the attempt's tip `3f16380` (backup branch `layout-v1-attempt` created there today); the reset to `62d0def` is the human's and gates slice 5 only.

## 2026-09-10 — Phase 0 — Slice 2: the invariant checker

**What shipped:** `lib/preview/layout/invariants.zig` — `Report { body, shared, junction, tree, crossings, bends, straight, wires }` and `check(arena, grid)`, the render-free counter of decision 10. A net is `(src_id, src_port)`; every wire cell is claimed with its orientation and whether the wire passes straight through it; a cell two or more nets cover is `shared` when every claim has one orientation, a `crossing` when exactly two nets each pass straight through it perpendicularly, and a `junction` otherwise; a net is counted under `tree` when its wires' segment chains are not contiguous and axis-aligned, when its wires do not all start at one source cell, or when its cells are not 4-connected from that cell. Registered as `preview_layout_invariants` in `build/frontend_modules.zig`; its test step is `preview_layout_invariants_tests` in `build.zig`. No layout code touched.
**Files touched:** `lib/preview/layout/invariants.zig` (new), `build/frontend_modules.zig`, `build.zig`, `DOCS/STATUS.md`.
**Tests:** added ten cases — empty grid; a single straight wire; body cells with port cells excluded (5 of a 16-cell run); two nets sharing a row (5 cells); a perpendicular pass-through as a crossing; a corner on another net's cell as a junction plus its shared run; three nets in one cell; a fan-out sharing its own trunk reporting nothing but bends; a broken chain and a two-source net both counted under `tree`; and a hand-built copy of `and_of_not`'s fused cells reporting `shared > 0` and `junction > 0`. Ran `zig build test` (pass, `preview_layout_invariants_tests 10 passed`), `zig build test-all` (pass); `git diff --stat tests/fixtures` empty.
**Invariants:** not yet measured on the corpus (slice 4).
**Next slice:** Slice 3 — `tests/preview/corpus.zig` and the JSON conformance goldens over the corpus through `libcirc.frontend.run(.project)`.
**Notes:** A corner cell is claimed twice by its own wire, once per orientation, so a corner sitting on another net's straight leg classifies as a junction rather than as a crossing; the classification never looks at rendered glyphs, which is what makes it usable from TypeScript in slice 5 unchanged. Two Zig-shadowing compile errors on the first run (test helpers named `seg` and `grid` collided with parameter names) — renamed, not silenced.
