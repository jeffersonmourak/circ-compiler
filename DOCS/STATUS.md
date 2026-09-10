# Status — layout rewrite

Append-only log, one entry per shipped slice. Newest at the bottom. See `DOCS/PLANS_PROMPT.md` for the phase index and `DOCS/PLANS/PHASE_<N>_*.md` for each phase's spec.

## 2026-09-10 — Phase 0 — Slice 1: revive the JSON dump and start the log

**What shipped:** `lib/preview/dump_json.zig` — `dumpLayoutJson(writer, grid)`, the camelCase common-subset projection of a `LayoutGrid` — restored byte for byte from the discarded attempt (`git show layout-v1-attempt:lib/preview/dump_json.zig`, commit `4fb480e`), with its `build.zig` module and test step placed after `preview_dump_mod`. `DOCS/decisions/preview-layout.md` created with "The parity contract is a JSON projection, not either side's native type" and registered in `DOCS/decisions/index.md`. This file. No layout code touched; no golden touched.
**Files touched:** `lib/preview/dump_json.zig` (new), `build.zig`, `DOCS/decisions/preview-layout.md` (new), `DOCS/decisions/index.md`, `DOCS/STATUS.md` (new).
**Tests:** `dump_json: emits the contract shape and parses back as JSON`, `dump_json: empty grid and escaped names` (both from the revived file); ran `zig build test` (pass), `zig build test-all` (pass); `git diff --stat tests/fixtures` empty.
**Invariants:** not measured yet (slice 4 puts the table on record).
**Next slice:** Slice 2 — `lib/preview/layout/invariants.zig`, the render-free I0–I3 checker with its unit tests.
**Notes:** The attempt's `build.zig` diff also stripped every pre-existing trailing-whitespace line; only the module block was carried, per the plan prompt's *Build and goldens* trap. The renderer's `host-pin-api` still sits at the attempt's tip `3f16380` (backup branch `layout-v1-attempt` created there today); the reset to `62d0def` is the human's and gates slice 5 only.
