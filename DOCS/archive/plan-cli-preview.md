# Archived plan: cli-preview

**Canonical commit:** `ffe92ac79b4ae3a7df2ab8de744146766ae0a123` (`ffe92ac Plan prompt: record post-Phase-3 future-cleanup traps`). Absent from this repository's history: the work landed squashed as `ea8fff9`.
**Archived on:** 2026-05-06
**Plan duration:** 2026-05-06 → 2026-05-06

> This file is a highlight view. The plan bundle (plan prompt, phase plans, STATUS log) lived on a branch that the squash merge `ea8fff9` (`Add ASCII circuit preview to circ-compile (#5)`) replaced, so the commit named above is absent from this repository's history and the unabridged source is lost.

## Goal & scope

Add `circ-compile <foo.circ> --preview` — a flag that renders a digital circuit as a styled ASCII schematic to stdout, with optional ANSI color and macro expansion control. The renderer compiles the `.circ` source in-memory through the existing parse → IR → resolver pipeline, walks the resolved IR into a richer topology (`circ.topology.v0.full`) carrying per-component names + subcircuit-origin chains, lays the gate graph out deterministically on a character grid, and draws it with line-art glyphs (`╭╮╰╯─│●▷○◉`) plus per-kind color tags.

Architectural anchors that constrained the work: Layer 1 (`lib/circuit.zig`) and the runtime WASM ABI stay unmodified; rendering lives entirely on the CLI side. The full topology payload is carried as a new `circ.topology.v0.full` WASM custom section *alongside* the existing `circ.topology.v0.min` (today's flat id+kind+connections payload, byte-equivalent to the prior `circ.topology` content under the renamed identifier). `min` and `full` are independent variants on a versioned axis; pre-1.0 schemas are freely revvable. Determinism is contractual: every layout decision uses ascending node id as the universal tie-breaker; hash-map iteration is forbidden as an ordering source. The IR→section serializer is the only place that depends on IR shape — all downstream code consumes the decoded section so a langlang upgrade's blast radius stays bounded.

## Phase-by-phase highlights

### Phase 0 — Topology serialization (5 slices)

Two new WASM custom sections shipped alongside today's payload, one stable rename and one new richer variant. End-to-end integration test compiles a real subcircuit fixture and round-trips both sections through the wire format.

- Renamed the runtime `topology_blob` static-bytes marker (returned by `getTopology()` in emitted Zig) from `"debug-paths-v1"` to `"circ.topology.v0.min"`. Touched `lib/emit/main.zig:59`, `lib/emit/project.zig:736`, plus 9 expected-zig fixtures under `tests/fixtures/expected-zig/`. New focused test: `emit topology_blob marker is circ.topology.v0.min`.
- Renamed the WASM custom-section identifier in `lib/topology/section_writer.zig` from `"circ.topology"` to `"circ.topology.v0.min"`. Section bytes unchanged. Updated 14 sites across 5 files (1 constant + 3 comments + 4 hardcoded byte counts in `section_writer: custom section bytes are correct` + 6 e2e references in JS string literals).
- New `lib/topology/full_format.zig`: `FULL_MAGIC = "CIRF"`, `FULL_VERSION = 0x01`, `OriginFrame { alias, subcircuit, target_file: u32 }`, `FullComponentRecord { id, kind, name, origin: []OriginFrame }`, `FullTopology { components, connections, deinit(allocator) }`. Reuses `format.{ComponentKind, PortName, ConnectionRecord}`.
- New `lib/topology/full_serializer.zig` with `encode`, `serializeProjectFull`, `serializeModuleFull`, `buildFromProject`, `buildFromModule`. The IR-walk mirrors `lib/topology/serializer.zig:expandModule` (recursion, `local_to_global`/`sub_output_map`, boundary rewiring) but threads an `OriginFrame` stack: pushes a frame on entry into a `sub_circuit_ref`, pops on return, copies the current stack into each emitted primitive's `origin` chain. Parallel implementation by design — the spec's TODO chose (b) over extracting a generic visitor; both serializers must produce identical global-id sequences (documented contract, not enforced).
- New `lib/topology/full_decoder.zig` with `Cursor` helper for bounded byte reads. Errors: `error.BadMagic`, `error.UnsupportedVersion`, `error.Truncated`, `error.UnknownComponentKind`. `errdefer` chain handles partial-allocation cleanup correctly across all three nested levels (components, origin frames, connections).
- `lib/topology/section_writer.zig` gained `combineTwo(allocator, runtime_wasm, min_payload, full_payload)` appending both custom sections in order. `cmd/circ-compile/main.zig`'s compile branch now produces both payloads.
- `tests/topology/full_emit_integration_test.zig` exercises the full pipeline against `tests/fixtures/projects/and_pair/` (which uses imported `paired_and` subcircuit with two instances `p1`/`p2`); walks the resulting WASM custom sections via an inline LEB128 walker; asserts component count parity + non-empty names + at least one origin chain referencing `paired_and` + byte-identical connections across `min` and `full`.

**Mid-phase spec rewrite:** the original Phase 0 spec assumed `lib/topology/` was a new module to build from scratch and that macros were inlined at the IR level. The first deep dive into the codebase showed `lib/topology/` already existed (with `serializer`/`format`/`section_writer`) and that macros are *not* inlined in the IR — they're `sub_circuit_ref` components that get flattened inside `serializeProjectFull`. Slice 1's commit (`04422b4`) renamed an unrelated marker and is retained as-committed; slice 2 is the actual section-name rename the original "min" intent referred to. The rewritten Phase 0 spec at commit `f0efe23` reflects what shipped.

### Phase 1 — `--preview` flag + textual topology dump (4 slices)

`circ-compile <file> --preview` produces a deterministic textual debug dump of the expanded topology to stdout, with diagnostics on stderr. End-to-end CLI integration tests with golden file capture.

- Added `Mode.preview` to `lib/cli/args.zig` with parse-time mutual-exclusion checks against `--emit-zig` and `--inspect` (`error.ConflictingModes`) and parse-time rejection of `-o` in preview mode (`error.InvalidFlagValue`). `MissingOutput` validation extended so neither `--inspect` nor `--preview` requires `-o`.
- Widened `cmd/circ-compile/main.zig`'s `fn run()` to `pub fn run(allocator, argv, stdout_writer, stderr_writer) !u8` so integration tests drive the CLI in-process. Existing `main()` orchestrates arena/argv/writers and calls the widened `run`. Build adds a `circ_compile_tests` target picking up test blocks inside main.zig.
- New `lib/preview/dump.zig` with `pub fn dump(writer, topology: FullTopology)`. Format: header `Topology (v0.full)` + counts; `Components:` table with `[id] kind "name" [origin: chain]` rows (kind via `@tagName`, anonymous names render as `""`, origin column omitted when `origin.len == 0`); `Connections:` table with `src_id.out -> dst_id.<port_name>` rows. Origin chains use ` > ` as frame separator with each frame as `alias:subcircuit`; `target_file` is omitted from output.
- Replaced the slice-1 placeholder dispatch arm with the real preview branch. Dispatch gate `has_imports and args.mode != .inspect` widened to `(has_imports or args.mode == .preview) and args.mode != .inspect` so preview always goes through the project pipeline (catches builtin macros via `scan_imports`'s `implicit_builtin` path). Compile/emit_zig keep the cheaper gate to preserve the 100-component perf budget.
- Integration tests: `phase1_preview_primitives_fixture` (chain.circ), `phase1_preview_xor_fixture` (builtin_xor.circ → 19-component dump with two-frame origin chains like `g:xor > o:or`), `phase1_preview_xnor_fixture`, `phase1_preview_parse_error_to_stderr` (E001_undeclared.circ → exit non-zero, stdout empty, stderr non-empty). Golden files under `tests/fixtures/circuits/*.preview.golden`.

### Phase 2 — Layout pipeline (6 slices, split as 6a/6b)

Five-stage deterministic layout pipeline (`collapse → assignColumns → assignRows → place → route`) producing a typed `LayoutGrid`. Two render modes: opaque (subcircuits as virtual nodes) and expanded (`--expand-macros`). The CLI surface is intentionally invisible during Phase 2; tests are the proof.

- Public types in `lib/preview/layout.zig`: `PortCoord`, `PortSlot`, `NodeKind = union(enum) { primitive: ComponentKind, subcircuit: []const u8 }`, `PlacedComponent`, `Segment`, `RoutedWire`, `LayoutGrid`, `LayoutOptions { expand_macros }`. Internal pipeline types in `lib/preview/layout/types.zig`: `InputEdge`, `OutputEdge`, `VirtualNode`, `VirtualGraph`, `ColumnAssignment`, `RowAssignment`. Per-kind cell sizes locked in `lib/preview/layout/sizing.zig`: `input_pin/output_pin = 6×1`, `not_gate/and_gate = 5×3`, `led = 3×3`, `wire = 0×0` sentinel; `macroSize(label_width) = max(8, label_width+2) × 3`. New `--expand-macros` flag with parse-time rejection outside `--preview` mode.
- Stage 1 `lib/preview/layout/collapse.zig`: wire transitive-closure (driver chain walk capped at depth 64); opaque-mode subcircuit grouping by outermost `OriginFrame.subcircuit` + `alias`; synthetic ids allocated above `max(component.id) + 1`. Internal connections (both endpoints in same group) are dropped. Tests `collapse_drops_wire_primitives`, `collapse_chains_of_wires`, `collapse_opaque_subcircuit`, `collapse_expanded_subcircuit`.
- Stage 2 `lib/preview/layout/columns.zig`: longest-path layering. Input pins pinned at column 0; `column_of[n] = 1 + max(column_of[upstream])`; sinks (`led`, `output_pin`) forced to `num_columns - 1`. Tests `columns_longest_path`, `columns_diamond`, `columns_input_pins_at_zero`, `columns_leds_rightmost`.
- Stage 3 `lib/preview/layout/rows.zig`: barycenter-method row assignment with two sweeps (L→R, R→L). Tie-break by ascending node id with float comparison without epsilon. Tests `rows_barycenter_simple`, `rows_deterministic_tie_break`.
- Stage 4 `lib/preview/layout/place.zig`: per-node cell sizing, per-column max-width and per-row max-height, cumulative absolute coords with `COL_GUTTER = 4` and `ROW_GUTTER = 1`. Per-kind port-slot resolution (`a` top-left of AND, `b` bottom-left, `out` middle-right; etc.). Tests `place_cell_sizing`, `place_port_coords_and_gate`, `place_macro_label_width`.
- Stage 5 `lib/preview/layout/route.zig`: 3-leg L-shaped paths per wire (horizontal source → track_x, vertical at track_x, horizontal track_x → destination); interval-greedy track allocation per source-x channel. Crossings detected pairwise with **inclusive bounds** (corner-touch counts as a crossing because the renderer has to pick a glyph). Tests `route_segments_are_axis_aligned`, `route_two_wires_no_crossing`, `route_two_wires_with_crossing`.
- Orchestrator `lib/preview/layout/orchestrator.zig:build(arena, topology, opts)` composes the five stages. Lives in its own module to avoid a cyclic build-graph dependency (stages already import `layout` for types). `dumpLayout(writer, grid)` debug formatter added to `lib/preview/dump.zig` — three-section format `LayoutGrid <W>x<H>` + `Components:` (with `subcircuit:<sub>` rendering for opaque virtual nodes) + `Wires:` + optional `Crossings:`. Six golden integration tests under `tests/preview/layout_integration_test.zig`: `phase2_layout_{primitives_opaque,builtin_xor_opaque,builtin_xor_expanded,builtin_xnor_opaque,builtin_xnor_expanded,deterministic}` against `chain.circ`/`builtin_xor.circ`/`builtin_xnor.circ`.

### Phase 3 — ASCII rendering + color (5 slices)

Composes Canvas + glyph drawing + wire rendering into the rendered schematic. Final cutover: `cmd/circ-compile/main.zig`'s preview branch now emits ASCII art instead of the textual topology dump.

- New `lib/preview/render/color.zig`: `ColorMode = enum { auto, always, never }`, `ColorTag = enum(u8) { none, input_pin, not_gate, and_gate, led, macro, wire, crossing }` (8 values), `ANSI_RESET`, `ansiFor(tag)`, and the pure resolution function `shouldColor(mode, stdout_handle: ?std.fs.File.Handle, no_color_value: ?[]const u8) bool` — `--color=always` overrides `NO_COLOR`, `--color=never` always off, `--color=auto` requires real TTY *and* no `NO_COLOR`. New `--color=auto|always|never` flag in `lib/cli/args.zig`. `Args.color` defaults to `.auto`.
- New `lib/preview/render/canvas.zig`: `Canvas { width, height, cells: [][]const u8, color: []ColorTag }` with parallel cell-content and color arrays (each cell stores a `[]const u8` slice — typically a static UTF-8 string literal). Methods `init`, `setCell`, `drawHSegment`, `drawVSegment`, `writeOut(writer, use_color)`. ANSI escapes interleave at tag transitions; `ANSI_RESET` emitted at every end-of-row so color never leaks across newlines.
- New `lib/preview/render/glyphs.zig`: `drawComponent` dispatcher + per-kind drawing functions. **Locked glyph art (concrete bytes captured into goldens at slice time):** input pin = `name──`; output pin = `──name` (mirror); NOT gate = `─▷○──` on middle row, blank above/below; AND gate = `─╮ … │─── … ─╯` (D-shape silhouette); LED = `─◉ ` middle row; macro box = `╭─...─╮ │ centered [<sub>:<alias>] │ ╰─...─╯`. Triangle `▷` (U+25B7) + bubble `○` (U+25CB) + fisheye `◉` (U+25C9). The `wire` primitive is `unreachable` because wires are collapsed before placement.
- New `lib/preview/render.zig:render(arena, writer, grid, opts)` with `RenderOptions { color, stdout_handle, no_color_value }`. Seven-step orchestration: init Canvas → draw component glyphs → draw wire rails (`─`/`│`) → patch corners at intra-wire segment junctions via `pickCornerGlyph` (4-direction connection model selects `╭╮╰╯`) → fan-out tap detection (sources used by ≥3 wires get `●`) → apply jump-arcs at every `RoutedWire.crossings` cell (idempotent — crossing cell becomes `│`, neighbours become `╯`/`╰`) → resolve `use_color` via `shouldColor` → `writeOut`.
- CLI cutover. `cmd/circ-compile/main.zig`'s preview branch now calls `layout_orchestrator.build` then `preview_render.render` — replaces the Phase-1 `preview_dump.dump(topology)` call. `NO_COLOR` is read via `std.process.getEnvVarOwned`, real stdout handle from `std.fs.File.stdout().handle`. Four new fixtures: `single_gate.circ` (pin → not → output), `fan_out.circ` (one pin to three nots), `fan_in.circ` (two pins to AND), `multi_led.circ` (three pins to three outputs). 7 new render goldens captured via `UPDATE_GOLDENS=1`. The Phase-1 `*.preview.golden` files (`chain.preview.golden`, `builtin_xor.preview.golden`, `builtin_xnor.preview.golden`) had their *content* replaced with rendered schematics — test names retained per the "git history of these golden files is the chronological record of how `--preview` evolved" discipline. Color-on golden `single_gate.render.color.golden` locks the ANSI escape emission. Tests `phase3_render_{single_gate,fan_out,fan_in,multi_led,builtin_xor_expanded,builtin_xnor_expanded,color_always,color_never_no_escapes}`.

**Downstream-spec patch discipline.** After Phase 0's mid-implementation spec rewrite (`f0efe23`), each downstream phase had its spec patched against the now-verified codebase before its slices began: Phase 1 (`2a93330`), Phase 2 (`31d4301`), Phase 3 (`2f98a7d`). Each patch corrected type names (`MacroFrame` → `OriginFrame`, no `MacroKind` enum), fixture paths (`tests/fixtures/topology/` → `tests/fixtures/circuits/`), and test names. No structural design change — all patches concentrated in naming and paths.

## API surface frozen at this archive

### CLI flags (additions; existing untouched)

| Flag | Mode | Notes |
|------|------|-------|
| `--preview` | new `Mode.preview` | mutually exclusive with `--emit-zig`/`--inspect`; rejects `-o` at parse time |
| `--expand-macros` | only valid with `--preview` | rejected at parse time outside preview mode |
| `--color=auto\|always\|never` | usable with any mode (no-op outside preview) | defaults to `auto`; `auto` requires TTY + no `NO_COLOR`; `always` overrides `NO_COLOR` |

### WASM custom sections in compiled `.wasm`

| Section name | Magic | Version | Contents |
|--------------|-------|---------|----------|
| `circ.topology.v0.min` | `CIRC` | `0x01` | flat primitive components (id, kind) + connections (from_id, to_id, port). Renamed from `circ.topology`; bytes unchanged. |
| `circ.topology.v0.full` | `CIRF` | `0x01` | adds per-component name (length-prefixed UTF-8) + origin chain (length-prefixed list of `OriginFrame { alias, subcircuit, target_file }`). |

### Public Zig API (new modules)

- `lib/topology/full_format.zig` — types: `FULL_MAGIC`, `FULL_VERSION`, `OriginFrame`, `FullComponentRecord`, `FullTopology`, `FullConnectionRecord`. Reuses `format.{ComponentKind, PortName}`.
- `lib/topology/full_serializer.zig` — `encode(allocator, FullTopology) ![]u8`, `buildFromProject(allocator, *Project) !FullTopology`, `buildFromModule(allocator, *Module) !FullTopology`, `serializeProjectFull(allocator, *Project) ![]u8`, `serializeModuleFull(allocator, *Module) ![]u8`.
- `lib/topology/full_decoder.zig` — `decode(allocator, []const u8) !FullTopology`.
- `lib/topology/section_writer.zig` — `combineTwo(allocator, runtime_wasm, min_payload, full_payload) ![]u8`.
- `lib/preview/dump.zig` — `dump(writer, FullTopology) !void`, `dumpLayout(writer, LayoutGrid) !void`.
- `lib/preview/layout.zig` — types `PortCoord`, `PortSlot`, `NodeKind`, `PlacedComponent`, `Segment`, `RoutedWire`, `LayoutGrid`, `LayoutOptions`. Stub `pub fn layout(...) !LayoutGrid` returns `error.NotImplemented`.
- `lib/preview/layout/orchestrator.zig` — `build(arena, FullTopology, LayoutOptions) !LayoutGrid`.
- `lib/preview/layout/{collapse,columns,rows,place,route,sizing,types}.zig` — per-stage public functions.
- `lib/preview/render.zig` — `render(arena, writer, LayoutGrid, RenderOptions) !void`, `RenderOptions { color, stdout_handle, no_color_value }`.
- `lib/preview/render/{color,canvas,glyphs}.zig` — color resolution, in-memory grid, per-kind drawing.

### Test name prefixes

`emit_*`, `full_format_*`, `full_encode_*`, `full_decode_*`, `full_walk_*` (Phase 0); `cli_args_parse_preview_flag`, `cli_args_preview_*`, `phase1_preview_*` (Phase 1); `cli_args_*_expand_macros*`, `collapse_*`, `columns_*`, `rows_*`, `place_*`, `route_*`, `phase2_layout_*` (Phase 2); `cli_args_*_color*`, `color_resolution_*`, `canvas_*`, `glyphs_draws_*`, `render_*`, `phase3_render_*` (Phase 3).

## Known papercuts carried forward

- **Renderer's `+` fallback glyph at 3-way junctions.** `lib/preview/render.zig:pickCornerGlyph` returns `"+"` when a corner cell connects to ≥3 directions because the 2-direction logic doesn't pick a T-glyph. Visible in `tests/fixtures/circuits/fan_in.render.golden`. Fix: detect per-cell direction set across all wires and pick from `┤`/`┬`/`┴`/`├` for 3 directions, `┼` for 4. Goldens lock current behaviour; any improvement produces a reviewable diff.
- **Compile/emit_zig modes miss builtin-macro single-file fixtures.** Dispatch gate uses `has_imports` (explicit imports only). Single-file `.circ` sources using builtin macros without an explicit `import` go through the single-module path where the resolver may emit unresolved-name errors. Phase 1 slice 4 widened preview mode (`(has_imports or args.mode == .preview) and args.mode != .inspect`); compile/emit_zig left unchanged to preserve the 100-component perf-budget test on the integration grid.
- **Two parallel topology serializers must produce identical id sequences** (`lib/topology/serializer.zig:serializeProjectFull` for the min payload and `lib/topology/full_serializer.zig:buildFromProject` for the full). Documented contract, not enforced. If they ever diverge silently, the symptom is wrong wires in the rendered preview.
- **Unused `layout()` stub in `lib/preview/layout.zig`.** Returns `error.NotImplemented`; Phase 2 slice 6b preserved it to keep slice 1's test green. Future cleanup: delete it, or have it delegate to `orchestrator.build`.
- **`preview_dump.dump(topology)`** (the Phase 1 textual-dump function in `lib/preview/dump.zig`) is no longer called from the CLI but is still in the public surface for tests and future tooling.
- **Two-sweep barycenter row assignment** may not fully minimize crossings on harder graphs (fan-in/fan-out at multiple levels). Spec called for two sweeps; current goldens are the fixed point. If Phase 3-style render reveals layout sub-optimality on a larger fixture, bumping to 3+ sweeps is a tunable.
- **Tap detection misses fan-out mid-graph.** `lib/preview/render.zig` counts source endpoints (cells used as `segments[0].from` by ≥3 wires) but doesn't catch fan-out at a non-source cell mid-wire. For typical `.circ` routing where sources are the only fan-out points, adequate; if a future routing change introduces mid-graph splits, the detection needs broadening.

## Decisions & specs that survived this plan

This archival pass removes the plan-process artefacts (`PLANS_PROMPT.md`, `PLANS/`, `STATUS.md`). The living specs that remain authoritative for future readers:

- [`DOCS/architecture.md`](../architecture.md) — three-layer model (simulation engine / WASM glue / SDK + rendering); this initiative added rendering as a CLI-side consumer of the `circ.topology.v0.full` payload, leaving Layer 1 untouched.
- [`DOCS/circuit-format.md`](../circuit-format.md) — `.circ` DSL syntax. Untouched by this initiative.
- [`DOCS/wasm-api.md`](../wasm-api.md) — runtime WASM exports/imports. Untouched.
- [`DOCS/simulation-engine.md`](../simulation-engine.md) — Zig API of `lib/circuit.zig`. Untouched.
- [`DOCS/decisions/cli.md`](../decisions/cli.md) — CLI design conventions. New flags follow the explicit-flag style established here (no magic-extension dispatch).
- [`DOCS/decisions/compiler-pipeline.md`](../decisions/compiler-pipeline.md) — parse → IR → emit pipeline shape. Preview mode reuses this verbatim; only the post-resolve consumer differs.
