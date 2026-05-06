# Phase 3 — ASCII Rendering + Color

> **Dependencies:** Phase 0 (`lib/topology/`), Phase 1 (`lib/preview/dump.zig`, `--preview` flag, widened `run(...)` signature), Phase 2 (`lib/preview/layout/`, `LayoutGrid`, `--expand-macros` flag) must all be complete.
> **Warnings (post-Phase-0 review, 2026-05-06):** This phase is the **user-visible cutover**. `--preview` stops printing the Phase-1 `FullTopology` dump and starts printing rendered schematics. The Phase-1 integration test names are kept (note: per the Phase 1 spec patch, the canonical names are `phase1_preview_primitives_fixture`, `phase1_preview_xor_fixture`, `phase1_preview_xnor_fixture` — not the originally-planned `_xor_macro_` / `_xnor_nested_` variants); their golden file *contents* are replaced. Resist renaming the tests — git history of the golden files is the chronological record of how `--preview` evolved.
>
> Two corrections from the original draft of this spec:
> - Render path is `parse → resolve → translate → buildFromProject (or buildFromModule) → layout → render → stdout`. The original plan's encode-then-decode round-trip was dropped in the Phase 1 review (Phase 0's IR walk produces a `FullTopology` directly).
> - Fixture paths were `tests/fixtures/topology/` (doesn't exist) and used names like `xor_macro.circ` / `xnor_nested.circ`. Real fixtures live at `tests/fixtures/circuits/builtin_xor.circ` and `builtin_xnor.circ`. New fixtures introduced by this phase land alongside them in `tests/fixtures/circuits/`.

## Goal

After this phase, running `circ-compile <foo.circ> --preview` prints a styled ASCII schematic of the circuit to stdout, with optional ANSI color controlled by `--color=auto|always|never`. The schematic uses `╭╮╰╯─│●` line art for wires and junctions, jump-arc rendering (`─╯╰─`) for crossings, per-kind glyphs for components (input pins, NOT, AND, LED, opaque subcircuit boxes), and per-kind color tags when color is enabled. The render path is `parse → resolve → translate → buildFromProject (or buildFromModule) → layout → render → stdout`, fully synchronous over a single arena. The phase ships golden-file integration tests covering single gates, fan-out, fan-in, multi-LED, opaque and expanded subcircuit modes, and both color modes, plus per-component-type unit tests for glyph correctness, canvas semantics, and color resolution. Phase 1's `dump(topology)` function survives as a callable library function (still used by tests) but is no longer wired to the CLI.

## Scope

**In scope:**
- New `lib/preview/render.zig` with public entry `pub fn render(writer: anytype, grid: LayoutGrid, opts: RenderOptions) !void`. Walks a `LayoutGrid`, populates an in-memory `Canvas`, then writes it out with optional ANSI styling.
- New `lib/preview/render/` subdirectory:
  - `glyphs.zig` — per-kind component drawing functions; concrete glyph designs implemented at slice time, not in this spec.
  - `color.zig` — `ColorMode` enum, `shouldColor(mode, stdout_handle, no_color_value)` pure resolution function, per-`ColorTag` ANSI escape constants.
  - `canvas.zig` — in-memory character grid abstraction with cell setters, segment drawers, and a single `writeOut(writer, use_color)` pass.
- New `--color=auto|always|never` flag in `lib/cli/args.zig`. Defaults to `auto`. Rejects unknown values with `error.InvalidFlagValue`. Only meaningful in `--preview` mode (analogous to `--expand-macros`).
- Replacement of the Phase-1 preview branch in `cmd/circ-compile/main.zig`: build `LayoutGrid` via `layout(...)` honoring `args.expand_macros`, then `render(stdout, grid, .{ .color = args.color, .stdout_handle = std.io.getStdOut().handle })`. The Phase-1 `dump(topology)` call is removed from the CLI dispatch path.
- Update of the three Phase-1 golden files (locations carried over from the Phase 1 spec patch — under `tests/fixtures/circuits/`: the primitives-only fixture's `*.preview.golden`, `builtin_xor.preview.golden`, and `builtin_xnor.preview.golden`) — content replaced with rendered schematics, file paths and test names retained.
- Four new fixtures (`single_gate.circ`, `fan_out.circ`, `fan_in.circ`, `multi_led.circ`) plus their render goldens, all under `tests/fixtures/circuits/`.
- Color-on and color-off golden coverage for at least one fixture (locks the ANSI emission behaviour).
- Jump-arc crossing rendering: at every `RoutedWire.crossings` cell, the *horizontal* wire deflects (`─╯` / `╰─`); the vertical wire renders continuously.

**Explicitly deferred:**
- Signal-class wire coloring (color rails based on which input pin drives them). Future initiative.
- State-aware coloring (high signals red, low signals blue). Requires running the simulation; out of phase scope.
- Live preview / watch mode.
- Configurable glyph designs via flag or config file. Glyphs are locked at slice-time captures.
- Configurable cell sizes. Sizing table from Phase 2 is inherited unchanged.
- Any change to `lib/circuit.zig`, the runtime WASM ABI, the topology wire format, the layout pipeline, or the IR.
- Removal of Phase 1's `dump(topology)`. It stays in `lib/preview/dump.zig` as a library function.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---|---|---|
| `lib/preview/` | `render.zig` | Public orchestrator. Defines `RenderOptions`, `ColorMode` re-export, `pub fn render(writer, grid, opts) !void`. Calls `Canvas.init`, draws components via `glyphs`, draws wire segments and crossings, calls `canvas.writeOut`. |
| `lib/preview/render/` | `canvas.zig` | `Canvas` struct (cells + parallel color tags), `setCell`, `drawHSegment`, `drawVSegment`, `writeOut(writer, use_color)`. Handles ANSI escape interleaving at write time. Defines `ColorTag` enum. |
| `lib/preview/render/` | `glyphs.zig` | `pub fn drawComponent(canvas, placed)` dispatching on `NodeKind`. Per-kind drawing functions: `drawInputPin`, `drawNotGate`, `drawAndGate`, `drawLed`, `drawMacroBox`. Concrete byte content captured at slice time. |
| `lib/preview/render/` | `color.zig` | `pub const ColorMode = enum { auto, always, never };` `pub fn shouldColor(mode, stdout_handle: ?std.fs.File.Handle, no_color_value: ?[]const u8) bool;` Per-`ColorTag` ANSI escape constants. |
| `tests/` | `preview_render.zig` | All Phase-3 unit and integration tests. |
| `tests/fixtures/circuits/` | `single_gate.circ` | One input pin → one NOT → one LED. Minimal frame for per-kind glyph correctness. |
| `tests/fixtures/circuits/` | `fan_out.circ` | One input pin driving multiple gates. Stresses tap rendering. |
| `tests/fixtures/circuits/` | `fan_in.circ` | Multiple pins → one gate. Stresses inbound channel routing. |
| `tests/fixtures/circuits/` | `multi_led.circ` | Multiple LEDs in the rightmost column. Stresses vertical packing. (Note: LEDs may need to be encoded as `output_pin` in the IR — slice 5 verifies the fixture parses cleanly.) |
| `tests/fixtures/circuits/` | `single_gate.render.golden`, `fan_out.render.golden`, `fan_in.render.golden`, `multi_led.render.golden` | Captured rendered output per new fixture (color-off). |
| `tests/fixtures/circuits/` | `builtin_xor.render.opaque.golden`, `builtin_xor.render.expanded.golden`, `builtin_xnor.render.opaque.golden` | Mode-specific render goldens for existing single-file subcircuit fixtures. |
| `tests/fixtures/circuits/` | `single_gate.render.color.golden` | Same fixture rendered with `--color=always`. Locks ANSI escape emission. |

**Modified files:**

| Module/Package | File | Change |
|---|---|---|
| `lib/cli/args.zig` | — | Add `color: ColorMode = .auto` field. Parse `--color=<value>`. Validate value against `auto`/`always`/`never`. Reject outside `--preview` mode (same pattern as `--expand-macros`). |
| `cmd/circ-compile/main.zig` | — | Preview branch rewritten: parse → resolve → translate → `full_serializer.buildFromProject` (or `buildFromModule`) → `layout(arena, topology, .{ .expand_macros = args.expand_macros })` → `render(stdout, grid, .{ .color = args.color, .stdout_handle = stdout_handle })`. Replace the Phase-1 `dump(topology)` call. |
| `lib/preview/dump.zig` | — | No code change. The `dump` function remains; it is no longer called from the CLI dispatch path but stays in the public surface for tests and future tooling. |
| `tests/fixtures/circuits/<primitives>.preview.golden` | — | Content replaced with rendered schematic. Path retained. |
| `tests/fixtures/circuits/builtin_xor.preview.golden` | — | Same. |
| `tests/fixtures/circuits/builtin_xnor.preview.golden` | — | Same. |
| `tests/preview_cli.zig` | — | The `phase1_preview_*_fixture` tests are *kept* under their existing names; only the byte content of their expected goldens changes. The `phase1_preview_parse_error_to_stderr` test is unchanged (parse errors still go to stderr; preview produces no stdout on parse failure). |

**New dependencies:** None. Pure Zig stdlib (`std.posix.isatty`, `std.process.getEnvVarOwned` for `NO_COLOR`).

## Data & State

**Public types (`lib/preview/render.zig`):**

```zig
pub const ColorMode = enum { auto, always, never };

pub const RenderOptions = struct {
    color:         ColorMode = .auto,
    stdout_handle: ?std.fs.File.Handle = null,  // null = treated as not-a-TTY for `auto` resolution
};

pub fn render(writer: anytype, grid: LayoutGrid, opts: RenderOptions) !void;
```

**Internal types (`lib/preview/render/canvas.zig`):**

```zig
pub const ColorTag = enum(u8) {
    none = 0,
    input_pin,
    not_gate,
    and_gate,
    led,
    macro,
    wire,
    crossing,
};

pub const Canvas = struct {
    width:  u32,
    height: u32,
    cells:  []u8,           // row-major UTF-8 bytes (each "cell" may be a multi-byte char)
    color:  []ColorTag,     // parallel; one tag per cell

    pub fn init(arena, w, h) !Canvas;
    pub fn setCell(self, x, y, ch_bytes: []const u8, tag: ColorTag) void;
    pub fn drawHSegment(self, from_x, to_x, y, ch_bytes, tag) void;
    pub fn drawVSegment(self, x, from_y, to_y, ch_bytes, tag) void;
    pub fn writeOut(self, writer: anytype, use_color: bool) !void;
};
```

**Color resolution (`lib/preview/render/color.zig`):**

```zig
pub fn shouldColor(
    mode:           ColorMode,
    stdout_handle:  ?std.fs.File.Handle,
    no_color_value: ?[]const u8,
) bool;
```

Resolution table (locked):

| `mode`   | TTY?       | `NO_COLOR` set? | Result   |
|----------|-----------|-----------------|----------|
| `always` | any       | any             | true     |
| `never`  | any       | any             | false    |
| `auto`   | yes       | no              | true     |
| `auto`   | yes       | yes             | false    |
| `auto`   | no / null | any             | false    |

Notes:
- `--color=always` deliberately overrides `NO_COLOR`. Rationale: explicit user flag beats env hint; matches `git`, `ls`, `grep` convention.
- `NO_COLOR` is honored when *set to any value*, including empty string, per [no-color.org](https://no-color.org/).
- A null `stdout_handle` is treated as "not a TTY" — gives tests deterministic uncolored output under `auto` without mocking syscalls.

**Wire rendering convention (locked):**

- Horizontal segment: `─`. Vertical segment: `│`. (Both UTF-8 multi-byte.)
- Corners between perpendicular segments: `╭╮╰╯` selected by direction.
- Tap (3+ wires meeting at a cell): `●`.
- Crossings: the *horizontal* wire jumps with `─╯` (entering crossing) and `╰─` (exiting); the *vertical* wire renders continuously as `│`. This rule is unconditional — no per-crossing decision.

**Glyph design constraints (principles, not concrete art):**

- **Input pins** render their name followed by an outgoing rail: `name──`. Cell width = 6, height = 1 (locked from Phase 2 sizing).
- **NOT gates** render with a triangle shape and a bubble on the output side, fitting in 5×3.
- **AND gates** render with a D-shape, fitting in 5×3.
- **LEDs** render as a compact terminal cap fitting in 3×3. Either a directional indicator or a plain output marker; designer's call at slice time.
- **Macro boxes** render as a labeled box with the label `[<kind>:<name>]` centered in a 3-row cell. Box border uses `╭╮╰╯─│` glyphs. Width = `max(8, label_width + 2)` per Phase 2 sizing.
- All glyph designs target a fixed-width terminal font (no assumed proportional spacing). Multi-byte UTF-8 line-art characters count as one display column.

Concrete glyph art is captured at slice time and locked into goldens. Reviewing the resulting art happens at PR review of the slice that introduces it.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines/threads/workers are introduced. All allocation flows through the same caller-supplied arena allocator that Phase 2's `layout(...)` uses; the `Canvas` is allocated once and freed when the arena drops. The render path is a straight-line sequence over the arena: `Canvas.init → for each component: drawComponent → for each wire: drawHSegment/drawVSegment → for each crossing: overlay jump-arc glyphs → canvas.writeOut(writer, use_color)`. No I/O occurs until `writeOut`, which is a single sequential pass.

## Persistence & I/O

Phase 3's I/O surface:

- **Input:** `.circ` source path, read via the existing CLI file-load path. No new I/O code.
- **Output:** rendered schematic to stdout via the writer passed to `render(...)`. CLI passes `std.io.getStdOut().writer()`; tests pass `ArrayList(u8).writer()`.
- **isatty check:** `std.posix.isatty(std.io.getStdOut().handle)` invoked when resolving `--color=auto` (only if `mode == .auto`). Tests pass a null handle to bypass.
- **`NO_COLOR` env read:** `std.process.getEnvVarOwned(...)` with `error.EnvironmentVariableNotFound` treated as "not set." Resolved at the CLI boundary; the value is passed into `shouldColor` so the function itself stays pure.
- **Stream split (unchanged from Phase 1):** rendered output to stdout; parse/resolve diagnostics to stderr via existing `printDiagnosticSet` path.
- **No persistent artifacts written.** No `.wasm`, no `.zig`, no temp directory.
- **No external systems.** isatty and `NO_COLOR` are local; no network, no IPC.

This phase has no persistence beyond what prior phases established.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|---|---|---|
| 1 | `--color` flag + color resolution | `lib/preview/render/color.zig` complete (pure `shouldColor` + ANSI constants). `--color` flag parsed in `lib/cli/args.zig` with validation and outside-preview rejection. No rendering yet. | `cli_args_parse_color_auto`, `cli_args_parse_color_always`, `cli_args_parse_color_never`, `cli_args_color_default_is_auto`, `cli_args_color_rejects_invalid_value`, `color_resolution_always_overrides_no_color`, `color_resolution_never_always_off`, `color_resolution_auto_no_tty`, `color_resolution_auto_no_color_env`. |
| 2 | `Canvas` | `lib/preview/render/canvas.zig` complete: cell storage, segment drawers, color-aware write-out. | `canvas_set_cell`, `canvas_draw_h_segment`, `canvas_draw_v_segment`, `canvas_write_out_no_color`, `canvas_write_out_with_color`. |
| 3 | Glyphs | `lib/preview/render/glyphs.zig` complete with one drawing function per `NodeKind`. Concrete art captured into glyph-level unit-test expectations. | `glyphs_draws_input_pin`, `glyphs_draws_not_gate`, `glyphs_draws_and_gate`, `glyphs_draws_led`, `glyphs_draws_macro_box`. |
| 4 | `render(...)` orchestration + line-art and crossings | `lib/preview/render.zig` orchestrator. Wire segment routing translated into `Canvas` segment draws. Corner glyph selection (`╭╮╰╯`) based on segment direction. Tap detection (3+ wires meeting → `●`). Jump-arc rendering at every `RoutedWire.crossings` cell. | `render_single_segment_horizontal`, `render_corner_glyphs`, `render_tap_at_fanout`, `render_jump_arc_horizontal_over_vertical`. |
| 5 | CLI cutover + golden update + new fixtures | `cmd/circ-compile/main.zig`'s preview branch swapped from `dump(topology)` to `layout → render`. Four new fixtures + their goldens added. Phase-1 `*.preview.golden` files have their content replaced with rendered output (test names retained). Color-on golden for at least one fixture. | `phase3_render_single_gate`, `phase3_render_fan_out`, `phase3_render_fan_in`, `phase3_render_builtin_xor_opaque`, `phase3_render_builtin_xor_expanded`, `phase3_render_builtin_xnor_opaque`, `phase3_render_multi_led`, `phase3_render_color_always`, `phase3_render_color_never_no_escapes`, plus the updated `phase1_preview_primitives_fixture`, `phase1_preview_xor_fixture`, `phase1_preview_xnor_fixture` (Phase 1's revised test names). |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 5 is the largest; it could be split into 5a (CLI cutover + Phase-1 golden updates) and 5b (new fixtures + new goldens) if review surface gets uncomfortable — defer that judgment to the executor.

## Tests

**Unit tests:**

| Test name | Module | What it asserts |
|---|---|---|
| `cli_args_parse_color_auto` | `lib/cli/args.zig` | `--color=auto` parses to `ColorMode.auto`. |
| `cli_args_parse_color_always` | same | `--color=always` parses to `.always`. |
| `cli_args_parse_color_never` | same | `--color=never` parses to `.never`. |
| `cli_args_color_default_is_auto` | same | Omitting `--color` defaults to `.auto`. |
| `cli_args_color_rejects_invalid_value` | same | `--color=rainbow` returns `error.InvalidFlagValue`. |
| `color_resolution_always_overrides_no_color` | `lib/preview/render/color.zig` | `shouldColor(.always, any_handle, "1")` returns true. |
| `color_resolution_never_always_off` | same | `shouldColor(.never, any_handle, any_no_color)` returns false. |
| `color_resolution_auto_no_tty` | same | `shouldColor(.auto, null, null)` returns false. |
| `color_resolution_auto_no_color_env` | same | `shouldColor(.auto, fake_tty_handle, "")` returns false (empty string honored per no-color.org). |
| `canvas_set_cell` | `lib/preview/render/canvas.zig` | After `setCell(2, 1, "X", .none)`, the cell at (2, 1) reads `"X"` and tag `.none`. |
| `canvas_draw_h_segment` | same | `drawHSegment(0, 4, 2, "─", .wire)` writes `─` to cells (0..4, 2) tagged `.wire`. |
| `canvas_draw_v_segment` | same | Vertical equivalent. |
| `canvas_write_out_no_color` | same | A canvas with mixed tags writes plain bytes when `use_color = false` — output contains no ESC bytes (`\x1b`). |
| `canvas_write_out_with_color` | same | Same canvas with `use_color = true` interleaves the expected ANSI escape sequence at every tag boundary; output bytes match a captured literal. |
| `glyphs_draws_input_pin` | `lib/preview/render/glyphs.zig` | Drawing an `input_pin` named "pin1" at (0, 0) width=6 produces a captured byte sequence in the canvas. |
| `glyphs_draws_not_gate` | same | NOT gate drawing produces captured bytes. |
| `glyphs_draws_and_gate` | same | AND gate drawing produces captured bytes. |
| `glyphs_draws_led` | same | LED drawing produces captured bytes. |
| `glyphs_draws_macro_box` | same | Macro box `[xor:combine]` drawing produces captured bytes. |
| `render_single_segment_horizontal` | `lib/preview/render.zig` | A `LayoutGrid` with one wire of one horizontal segment renders as a row of `─` glyphs at the correct y, no junctions. |
| `render_corner_glyphs` | same | Wire with horizontal-then-vertical segments uses `╭` / `╮` / `╰` / `╯` at the corner per direction-detection rules. Test parameterizes all four corner cases. |
| `render_tap_at_fanout` | same | Three wires meeting at a cell produce `●`. |
| `render_jump_arc_horizontal_over_vertical` | same | Two crossing wires with locked geometry render the horizontal one with the `─╯` / `╰─` arc; the vertical renders continuously as `│`. |

**Integration tests:**

| Test name | Scope | What it asserts |
|---|---|---|
| `phase3_render_single_gate` | new fixture, color off | `single_gate.circ` renders to `single_gate.render.golden`. |
| `phase3_render_fan_out` | new fixture, color off | `fan_out.circ` renders to `fan_out.render.golden`. Verifies tap rendering. |
| `phase3_render_fan_in` | new fixture, color off | `fan_in.circ` renders to `fan_in.render.golden`. Verifies inbound channel routing. |
| `phase3_render_multi_led` | new fixture, color off | `multi_led.circ` renders to `multi_led.render.golden`. Verifies rightmost-column packing. |
| `phase3_render_builtin_xor_opaque` | `builtin_xor.circ`, opaque mode, color off | The `xor` subcircuit renders as one labeled box (e.g. `[xor:g]`). |
| `phase3_render_builtin_xor_expanded` | `builtin_xor.circ`, expanded mode, color off | xor's primitive children render separately with appropriate crossings. (Exact gate count captured at slice 5 implementation time.) |
| `phase3_render_builtin_xnor_opaque` | `builtin_xnor.circ`, opaque mode, color off | Outer `xnor` collapses to one box; inner `xor` is hidden inside it. |
| `phase3_render_color_always` | `single_gate.circ`, `--color=always` | Output matches `single_gate.render.color.golden` byte-for-byte (includes ANSI escapes). |
| `phase3_render_color_never_no_escapes` | any fixture, `--color=never` | Output contains zero `\x1b` bytes. |
| `phase1_preview_primitives_fixture` (golden updated) | primitives-only fixture via `run(...)` | Stdout matches the *new* `<primitives>.preview.golden` (rendered schematic, not topology dump). |
| `phase1_preview_xor_fixture` (golden updated) | `builtin_xor.circ` via `run(...)` | Stdout matches new `builtin_xor.preview.golden`. |
| `phase1_preview_xnor_fixture` (golden updated) | `builtin_xnor.circ` via `run(...)` | Stdout matches new `builtin_xnor.preview.golden`. |

Run command: `zig build test`

## Open Questions / Spikes

- TODO(phase3): During slice 1, decide where `NO_COLOR` is read — at the CLI boundary in `cmd/circ-compile/main.zig` (cleaner: `shouldColor` stays pure, gets a resolved value) or inside `color.zig` itself (slightly less testable but more colocated). Spec assumes CLI-boundary resolution; confirm at slice time.
- TODO(phase3): During slice 3, glyph designs are captured into `glyphs_draws_*` test expectations. The actual byte content per kind is a design choice made then, not now. Reviewers of slice 3's PR see the concrete art for the first time and that is the intended review surface.
- TODO(phase3): During slice 4, decide how taps are *detected* from the routed wire data. Two approaches: (a) post-process the rendered Canvas to find cells with 3+ wire glyphs and overlay `●`, (b) compute taps during routing in Phase 2 and store them on `RoutedWire`. (a) keeps Phase 2 unchanged; (b) is cleaner but reopens Phase 2's API. (a) is preferred unless implementation reveals it can't reliably distinguish a tap from a crossing.
- TODO(phase3): During slice 4, the jump-arc rendering needs precise glyph choice when the crossing happens *at* a cell where the horizontal wire would otherwise be drawing `─`. Verify the `─╯`/`╰─` two-cell deflection fits within available column width and doesn't collide with adjacent component bounding boxes. If a crossing lands at a column edge, fallback may be needed (e.g. `┼` for that one case). Resolve empirically when the first crossing fixture renders.
- TODO(phase3): During slice 5, when updating Phase-1 goldens, capture and review the new content carefully. The fixture inputs are stable, so the diff between old (topology dump) and new (rendered schematic) is the entire intended user-visible change of this initiative — that diff is a strong PR review signal and should be inspected line-by-line, not glossed over.
