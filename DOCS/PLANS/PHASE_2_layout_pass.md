# Phase 2 — Layout Pass

> **Dependencies:** Phase 0 (`lib/topology/full_format.zig` types — `FullTopology`, `FullComponentRecord`, `OriginFrame`, `ComponentKind`) and Phase 1 (`lib/preview/dump.zig`, the `--preview` flag, the widened `run(...)` CLI signature) must be complete.
> **Warnings (post-Phase-0 review, 2026-05-06):** This spec was patched after Phase 0 landed. Two corrections from the original draft:
> - The original spec referenced `Topology` from a hypothetical `lib/topology/schema.zig` plus a `MacroKind` enum (`xor_macro`, `xnor_macro`, ...) and `MacroFrame { instance_name, kind: MacroKind }`. Phase 0 landed differently: macros are open strings (import aliases) rather than a closed enum, and the canonical type is `FullTopology` from `lib/topology/full_format.zig` carrying `OriginFrame { alias, subcircuit, target_file }` chains. The opaque-mode collapse logic still works — it just groups by the outermost-frame `subcircuit` string instead of by `MacroKind` value.
> - Fixture paths were `tests/fixtures/topology/` (doesn't exist). Real fixtures live under `tests/fixtures/circuits/` and the existing `builtin_xor.circ` / `builtin_xnor.circ` cover the single-macro and nested-macro cases without needing new source files.
>
> Phase 2 itself is **invisible to the CLI surface**. `--preview` continues to print Phase 1's textual dump throughout Phase 2; the layout pipeline runs only through tests. Phase 3 is the cutover. Resist the temptation to wire `dumpLayout` to the CLI mid-phase — it would force two waves of golden-file churn for no user benefit.

## Goal

After this phase, the codebase contains a deterministic, pure-function layout pipeline that converts a `FullTopology` into a typed `LayoutGrid` describing where every component sits on a character grid and where every wire's segments and crossings land. The pipeline supports two modes selected via `LayoutOptions.expand_macros`: opaque (default — primitives sharing an outermost-frame `subcircuit` collapse into a single virtual subcircuit node) and expanded (every primitive produced by subcircuit expansion appears separately, preserving its full origin chain). Both modes share the same five-stage pipeline (`collapse → columns → rows → place → route`) and the same `LayoutGrid` output shape, differing only in the virtual-node set fed into stage 1. The phase ships with a `dumpLayout(writer, grid)` function that produces a testable textual rendering of the grid, golden-file integration tests across three existing fixtures in both modes, per-stage unit tests, and a `--expand-macros` flag in the CLI argument parser. The CLI dispatch path is unchanged; Phase 3 cuts `--preview` over to the rendered output.

## Scope

**In scope:**
- New `lib/preview/layout/` module with five stage files plus shared types and per-kind sizing constants. Public entry: `pub fn layout(allocator: std.mem.Allocator, topology: FullTopology, opts: LayoutOptions) !LayoutGrid`.
- Stage 1 (`collapse.zig`): drop `wire` primitives by short-circuiting the edges they pass through; in opaque mode, group primitives sharing the same outermost `OriginFrame.subcircuit` (and `alias`) into one virtual subcircuit node with a synthetic id allocated above the maximum component id in the input topology. In expanded mode, every primitive becomes its own virtual node preserving its real id and full origin chain.
- Stage 2 (`columns.zig`): longest-path layering. `column_of[node] = 1 + max(column_of[upstream])`; input pins force column 0; LEDs land in `num_columns - 1`.
- Stage 3 (`rows.zig`): barycenter-method row assignment with two sweeps (left-to-right then right-to-left). Deterministic tie-breaker by ascending node id when barycenter values are equal.
- Stage 4 (`place.zig`): per-kind cell sizing per the locked table; absolute (x, y) computation accounting for column gutters; per-component port-coordinate resolution producing `PortSlot` lists for inputs and a `PortCoord` for the output.
- Stage 5 (`route.zig`): interval-greedy channel-track allocation; orthogonal segment computation (each wire becomes a sequence of axis-aligned segments); crossing detection writing `crossings: []PortCoord` onto each `RoutedWire`.
- New `dumpLayout(writer, grid: LayoutGrid) !void` function added to `lib/preview/dump.zig` for textual debugging of layout results. Used by tests; not wired to the CLI.
- New `--expand-macros` boolean flag in `lib/cli/args.zig`. Only meaningful in `--preview` mode; rejected outside it. The flag is parsed and stored in `Args` but **not used by the CLI dispatch** during Phase 2 — it sits dormant until Phase 3 wires it in.
- Golden-file integration tests covering all three Phase-0 fixtures in both modes (six goldens total).
- Per-stage unit tests covering correctness of each stage on minimal hand-built inputs.

**Explicitly deferred:**
- Glyph rendering, ANSI color, `--color` flag, the `render(...)` function — Phase 3.
- CLI dispatch change. `--preview` continues to print Phase 1's textual `FullTopology` dump until Phase 3.
- Wiring `--expand-macros` into the CLI's actual behaviour. The flag is parsed in Phase 2 but only consumed in Phase 3.
- Any tunable parameter for cell sizes (the table is locked in `sizing.zig` constants; Phase 3 may rev it but no `LayoutOptions` field exposes it).
- Sophisticated crossing-minimization beyond the two-sweep barycenter method (e.g. Sugiyama with median or hybrid). For typical `.circ` sizes (rarely >50 components), barycenter is overkill-quality.
- Any change to `lib/circuit.zig`, the runtime WASM ABI, or the topology wire format.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---|---|---|
| `lib/preview/` | `layout.zig` | Public orchestrator. Defines public types: `LayoutGrid`, `PlacedComponent`, `PortSlot`, `PortCoord`, `NodeKind`, `Segment`, `RoutedWire`, `LayoutOptions`. Public entry `pub fn layout(...)`. Calls each stage in order over a caller-supplied arena. |
| `lib/preview/layout/` | `types.zig` | Internal pipeline types: `VirtualNode`, `InputEdge`, `OutputEdge`, `VirtualGraph`, `ColumnAssignment`, `RowAssignment`. These are the inter-stage contract; not part of the public API. |
| `lib/preview/layout/` | `sizing.zig` | Per-kind cell-size constants. `primitive_sizing: std.EnumArray(ComponentKind, PrimitiveSize)` plus `macroSize(name_len, kind) PrimitiveSize`. |
| `lib/preview/layout/` | `collapse.zig` | Stage 1: `pub fn collapse(arena, topology, opts) !VirtualGraph`. Drops `wire` primitives; collapses macro groups in opaque mode. |
| `lib/preview/layout/` | `columns.zig` | Stage 2: `pub fn assignColumns(arena, graph) !ColumnAssignment`. Longest-path layering. |
| `lib/preview/layout/` | `rows.zig` | Stage 3: `pub fn assignRows(arena, graph, columns) !RowAssignment`. Barycenter sweep. |
| `lib/preview/layout/` | `place.zig` | Stage 4: `pub fn place(arena, graph, columns, rows) ![]PlacedComponent`. Cell sizing + absolute coords + port resolution. |
| `lib/preview/layout/` | `route.zig` | Stage 5: `pub fn route(arena, graph, placed) ![]RoutedWire`. Channel allocation + segment computation + crossing detection. Returns wires plus the final grid `width`/`height`. |
| `tests/` | `preview_layout.zig` | All Phase-2 unit and integration tests. |
| `tests/fixtures/circuits/` | `<primitives>.layout.opaque.golden` | Locked `dumpLayout` output for the chosen primitives-only fixture (slice 6 picks; e.g. `chain.layout.opaque.golden`). |
| `tests/fixtures/circuits/` | `builtin_xor.layout.opaque.golden` | `builtin_xor.circ` opaque (subcircuit collapsed to one virtual node). |
| `tests/fixtures/circuits/` | `builtin_xor.layout.expanded.golden` | `builtin_xor.circ` expanded (xor's primitive children laid out individually). |
| `tests/fixtures/circuits/` | `builtin_xnor.layout.opaque.golden` | `builtin_xnor.circ` opaque (outermost xnor collapsed; inner xor hidden). |
| `tests/fixtures/circuits/` | `builtin_xnor.layout.expanded.golden` | `builtin_xnor.circ` expanded (both nesting levels visible). |

**Modified files:**

| Module/Package | File | Change |
|---|---|---|
| `lib/preview/dump.zig` | — | Add `pub fn dumpLayout(writer: anytype, grid: LayoutGrid) !void`. Same writer-as-anytype idiom Phase 1 established. Existing `dump(writer, topology)` unchanged. |
| `lib/cli/args.zig` | — | Add `expand_macros: bool = false` field to `Args`. Parse `--expand-macros`. Validate: rejected with `error.InvalidFlagValue` (or a dedicated error) if used outside `--preview` mode. **Phase 2 does not consume this flag** in dispatch; it just plumbs the field through. |

**New dependencies:** None. Pure Zig stdlib.

## Data & State

**Public types (defined in `lib/preview/layout.zig`):**

```zig
pub const PortCoord = struct { x: u32, y: u32 };

pub const PortSlot = struct {
    port_name: []const u8,    // "in", "a", "b" — decoded port name
    coord:     PortCoord,
};

pub const NodeKind = union(enum) {
    primitive:  full_format.ComponentKind,
    subcircuit: []const u8,                 // import alias of the collapsed subcircuit (opaque mode); e.g. "xor"
};

pub const PlacedComponent = struct {
    id:        u32,                         // real FullTopology id, or synthetic id above topology.max_id for opaque virtual subcircuit nodes
    kind:      NodeKind,
    name:      []const u8,
    origin:    []const full_format.OriginFrame, // for opaque virtual nodes: the collapsed outermost frame's tail. For expanded gates: full chain inherited from FullComponentRecord.origin
    x:         u32,
    y:         u32,
    width:     u32,
    height:    u32,
    in_ports:  []const PortSlot,
    out_port:  PortCoord,
};

pub const Segment = struct {
    from: PortCoord,
    to:   PortCoord,                        // axis-aligned: from.x == to.x OR from.y == to.y
};

pub const RoutedWire = struct {
    src_id:    u32,
    src_port:  u8,                          // matches full_format.PortName: out = 3
    dst_id:    u32,
    dst_port:  u8,                          // matches full_format.PortName: in=0, a=1, b=2
    segments:  []const Segment,             // ordered head→tail; corner = segment[N].to == segment[N+1].from
    crossings: []const PortCoord,           // cells where this wire visually crosses another wire
};

pub const LayoutGrid = struct {
    width:      u32,                        // total grid width in characters
    height:     u32,
    components: []const PlacedComponent,
    wires:      []const RoutedWire,
};

pub const LayoutOptions = struct {
    expand_macros: bool = false,
};
```

**Internal pipeline types (defined in `lib/preview/layout/types.zig`):**

```zig
pub const InputEdge = struct {
    src_id:   u32,
    src_port: u8,    // matches full_format.PortName: out = 3 today
    dst_port: u8,    // matches full_format.PortName: in=0, a=1, b=2
};

pub const OutputEdge = struct {
    dst_id:   u32,
    src_port: u8,    // out = 3
    dst_port: u8,
};

pub const VirtualNode = struct {
    id:      u32,                       // real id OR synthetic above topology.max_id
    kind:    NodeKind,
    name:    []const u8,
    origin:  []const full_format.OriginFrame,
    inputs:  []const InputEdge,
    outputs: []const OutputEdge,
};

pub const VirtualGraph = struct {
    nodes:   []const VirtualNode,        // sorted by id ascending for deterministic iteration
    next_id: u32,                        // first available synthetic id (for tests)
};

pub const ColumnAssignment = struct {
    column_of:   []const u32,            // indexed by VirtualGraph.nodes index
    num_columns: u32,
};

pub const RowAssignment = struct {
    row_of:   []const u32,
    num_rows: u32,
};
```

**Cell-sizing table (locked, `lib/preview/layout/sizing.zig`):**

| Kind | Width | Height | Notes |
|---|---|---|---|
| `input_pin` | 6 | 1 | One-line `name──` style |
| `not_gate` | 5 | 3 | Triangle + bubble glyph fits |
| `and_gate` | 5 | 3 | D-shape glyph |
| `led` | 3 | 3 | Compact terminal cap |
| `wire` | — | — | Collapsed; never placed |
| Subcircuit (opaque) | `max(8, label_width + 2)` | 3 | Label = `[<subcircuit>:<alias>]` plus padding (e.g. `[xor:g]`) |

These values are locked for Phase 2 to give golden coordinates a stable basis. Phase 3 may rev the table when glyphs are designed; that revision is a single deliberate commit that updates `sizing.zig` and re-captures the goldens.

**Synthetic id allocation:** `next_virtual_id = max(topology.components[*].id) + 1` allocated upward. Plain `u32`, no tagged union. A debugger printing `PlacedComponent.id = 1247` against a 12-component topology immediately reads as a virtual node.

**Determinism contract:** every layout decision uses `node.id` (ascending) as the universal tie-breaker. Hash-map iteration order is forbidden as a tie-breaker — Zig hash-map order is not stable across versions. Any place that needs to iterate "all nodes in some column" iterates a presorted slice, never a hash map.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines/threads/workers are introduced. All allocation flows through a caller-supplied arena allocator; stage outputs live until the arena is dropped. Each stage is a synchronous pure function from its input data to its output data; the orchestrator (`layout.zig`) calls them in order over the same arena and assembles the final `LayoutGrid` from the last two stages' outputs (`place` produces `[]PlacedComponent`; `route` produces `[]RoutedWire` plus `width`/`height`).

## Persistence & I/O

This phase has no persistence or external I/O beyond what prior phases established. The CLI dispatch path is unchanged — `--preview` continues to print Phase 1's textual `FullTopology` dump throughout Phase 2; tests exercise the layout pipeline directly via `layout(...)` and assert against golden files via `dumpLayout(...)`. No `.wasm` is read or written, no temp directories are touched, no network I/O occurs. Phase 1's three preview goldens (`*.preview.golden` under `tests/fixtures/circuits/`) stay green throughout this phase.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|---|---|---|
| 1 | Public types + sizing constants + flag plumbing | `lib/preview/layout.zig` skeleton with all public types defined and `pub fn layout(...)` returning a stub error (`error.NotImplemented`). `lib/preview/layout/types.zig` and `sizing.zig` complete. `--expand-macros` flag parsed and stored in `Args`, with rejection-when-not-preview-mode validation. No actual stages implemented. | `cli_args_parse_expand_macros_flag`, `cli_args_expand_macros_rejects_outside_preview`, plus a comptime test that the public types compile and round-trip through `@TypeOf` introspection. Existing tests stay green. |
| 2 | Stage 1 — collapse | `collapse.zig` complete. Produces a `VirtualGraph` from a `FullTopology` honoring `LayoutOptions.expand_macros`. Drops wires, collapses opaque subcircuit groups (by outermost `OriginFrame.subcircuit`+`alias`), allocates synthetic ids correctly. | `collapse_drops_wire_primitives`, `collapse_chains_of_wires`, `collapse_opaque_subcircuit`, `collapse_expanded_subcircuit`. |
| 3 | Stage 2 — columns | `columns.zig` complete. Longest-path layering over a `VirtualGraph`. | `columns_longest_path`, `columns_diamond`, `columns_input_pins_at_zero`, `columns_leds_rightmost`. |
| 4 | Stage 3 — rows | `rows.zig` complete. Barycenter sweep with deterministic tie-break. | `rows_barycenter_simple`, `rows_deterministic_tie_break`. |
| 5 | Stage 4 — place | `place.zig` complete. Cell sizing + absolute coords + port resolution. | `place_cell_sizing`, `place_port_coords_and_gate`, `place_macro_label_width`. |
| 6 | Stage 5 — route + `dumpLayout` + integration | `route.zig` complete. `dumpLayout(...)` added to `lib/preview/dump.zig`. `layout(...)` orchestrator wired up to call all five stages. All six golden integration tests pass. | `route_two_wires_no_crossing`, `route_two_wires_with_crossing`, `route_segments_are_axis_aligned`; `phase2_layout_primitives_opaque`, `phase2_layout_builtin_xor_opaque`, `phase2_layout_builtin_xor_expanded`, `phase2_layout_builtin_xnor_opaque`, `phase2_layout_builtin_xnor_expanded`, `phase2_layout_deterministic`. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 6 is the largest; it could be split into `route` + `dumpLayout` + `integration` if review surface gets uncomfortable — defer that judgment to the executor.

## Tests

**Unit tests:**

| Test name | Module | What it asserts |
|---|---|---|
| `cli_args_parse_expand_macros_flag` | `lib/cli/args.zig` | `circ-compile in.circ --preview --expand-macros` parses with `expand_macros = true`. |
| `cli_args_expand_macros_rejects_outside_preview` | `lib/cli/args.zig` | `circ-compile in.circ --emit-zig -o out.wasm --expand-macros` returns a typed error. |
| `collapse_drops_wire_primitives` | `lib/preview/layout/collapse.zig` | `FullTopology` `pin → wire → led` produces a `VirtualGraph` with 2 nodes and 1 direct edge. |
| `collapse_chains_of_wires` | `collapse.zig` | `pin → wire → wire → wire → led` collapses to one direct edge. |
| `collapse_opaque_subcircuit` | `collapse.zig` | A `FullTopology` containing primitives whose `origin[0]` shares `(subcircuit = "xor", alias = "g")` (i.e. produced by expanding one `xor g(...)` instance) under opaque mode produces 1 virtual subcircuit node with synthetic id and `kind = .subcircuit("xor")`; external connections remap to its published ports. The exact primitive count depends on `lib/resolver/builtin_circ/xor.circ`'s body — captured at slice 2 implementation time, not pre-specified. |
| `collapse_expanded_subcircuit` | `collapse.zig` | Same topology under expanded mode produces N virtual nodes (N = primitive count from xor.circ's body) preserving real ids and full origin chains. |
| `columns_longest_path` | `lib/preview/layout/columns.zig` | `pin → not → and → led` → columns `[0, 1, 2, 3]`. |
| `columns_diamond` | `columns.zig` | Fan-out + fan-in graph assigns the inner pair the same column index. |
| `columns_input_pins_at_zero` | `columns.zig` | All input pins land in column 0 regardless of graph shape. |
| `columns_leds_rightmost` | `columns.zig` | All LEDs land in `num_columns - 1`. |
| `rows_barycenter_simple` | `lib/preview/layout/rows.zig` | A two-column graph that crosses under naive ordering produces non-crossing layout after barycenter sweep. |
| `rows_deterministic_tie_break` | `rows.zig` | Equal barycenters resolve to ascending id order. Same input → byte-identical output across runs. |
| `place_cell_sizing` | `lib/preview/layout/place.zig` | A `not_gate` placed at (column=1, row=0) gets `width=5, height=3` and the expected absolute (x, y) computed from column gutters. |
| `place_port_coords_and_gate` | `place.zig` | An `and_gate` at known (x, y) exposes ports `a` at `(x, y)`, `b` at `(x, y+2)`, `out` at `(x+4, y+1)`. |
| `place_macro_label_width` | `place.zig` | Opaque macro with instance name `"longish_combine"` sizes wider than 8 to fit `[xor:longish_combine]`. |
| `route_two_wires_no_crossing` | `lib/preview/layout/route.zig` | Two wires with disjoint y-intervals share track 0 in the channel; each `RoutedWire.crossings` is empty. |
| `route_two_wires_with_crossing` | `route.zig` | Two wires with overlapping y-intervals get different tracks; their geometry crosses; both wires' `crossings` field contains the crossing point. |
| `route_segments_are_axis_aligned` | `route.zig` | Every `Segment` has `from.x == to.x` (vertical) or `from.y == to.y` (horizontal). No diagonals. |

**Integration tests:**

| Test name | Scope | What it asserts |
|---|---|---|
| `phase2_layout_primitives_opaque` | `layout(primitives_topology, .{ .expand_macros = false })` | `dumpLayout(...)` output matches `tests/fixtures/circuits/<primitives-fixture>.layout.opaque.golden` byte-for-byte. Slice 6 picks the fixture; e.g. `chain.circ`. |
| `phase2_layout_builtin_xor_opaque` | `layout(xor_topology, .{ .expand_macros = false })` | The `xor` subcircuit collapses to one virtual node; matches `tests/fixtures/circuits/builtin_xor.layout.opaque.golden`. |
| `phase2_layout_builtin_xor_expanded` | `layout(xor_topology, .{ .expand_macros = true })` | xor's primitive children render separately; matches `tests/fixtures/circuits/builtin_xor.layout.expanded.golden`. |
| `phase2_layout_builtin_xnor_opaque` | `layout(xnor_topology, .{ .expand_macros = false })` | Outermost `xnor` subcircuit collapses; nested `xor` inside it is hidden. Matches `tests/fixtures/circuits/builtin_xnor.layout.opaque.golden`. |
| `phase2_layout_builtin_xnor_expanded` | same, `expand_macros = true` | Both nesting levels expanded; matches `tests/fixtures/circuits/builtin_xnor.layout.expanded.golden`. |
| `phase2_layout_deterministic` | any fixture | Run `layout(...)` twice on the same topology; assert `dumpLayout` output is byte-identical. Locks the determinism contract end-to-end. |

Run command: `zig build test`

## Open Questions / Spikes

- TODO(phase2): During slice 1, decide where exactly the `--expand-macros` rejection-outside-preview happens — at parse time in `lib/cli/args.zig` (cleaner) or at dispatch time in `cmd/circ-compile/main.zig` (matches existing `-o`-rejection patterns). Match wherever `--inspect` and `-o` exclusivity currently lives. Either is correct; consistency matters more than the choice.
- TODO(phase2): During slice 2, confirm that the IR's `wire` primitive can have multiple inputs in practice. Per `DOCS/architecture.md`, `wire` "passes first defined input" — this implies wires may have multiple input ports despite typical usage. If so, `collapse.zig` must short-circuit *all* upstream connections, not just one. Test `collapse_chains_of_wires` covers chains; if multi-input wires are reachable from `.circ` syntax, add a test for fan-in collapse.
- TODO(phase2): During slice 3, decide column-assignment behaviour for unreachable nodes (a component with no path to or from any input pin or LED). Treat as column 0? Skip? Error? `.circ` syntax may not produce these in practice, but the algorithm needs to be deterministic if it does.
- TODO(phase2): During slice 5, the macro-label width formula `max(8, label_width + 2)` assumes label width = `len("[<kind>:<name>]")`. Confirm during implementation that the label-rendering convention chosen here matches what Phase 3 will actually print. If Phase 3 changes the label format (e.g. drops the brackets or adds padding), the cell width and golden coordinates need to be re-captured.
- TODO(phase2): During slice 6, judge whether the slice's review surface (route + dumpLayout + 9 tests) is uncomfortably large. If so, split into 6a (route + 3 unit tests) and 6b (dumpLayout + 6 integration tests). The integration tests genuinely depend on `dumpLayout` existing, so 6b must follow 6a; but they're independently reviewable.
