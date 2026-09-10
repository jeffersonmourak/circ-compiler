# Phase 3 — Channel routing

> **Dependencies:** Phases 0, 1 and 2, all shipped: the goldens and the table, `LayeredGraph`/`Ordering`, `Coords` with `insertSpacerRow` and `ChannelWidths`.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions 7–11 and the *The algorithm* traps in full; the attempt's list of local rules that failed is the list of things not to write. This phase deletes `route.zig` and turns I0–I3 into hard zeros; until its switch-over slice the old router keeps rendering. Render does not change (decision 3): `render.zig` reads `segments` for rails and corners, `crossings` for `●`/`┼` (step 5, with `isSplitPoint`/`isMergePoint` deciding which), and the wire's first/last cells for `○` and the sink arrow — so the emitted shape must satisfy those readers exactly. The gallery review at the end is the human's; every render golden changes in this phase.

## Goal

After this phase every wire is routed by `lib/preview/layout/channels.zig`, per inter-layer gap, globally. For each gap the nets crossing it (a source and all its sinks in the next layer, dummies included) are extracted; a net whose terminals share a row is a straight horizontal; every other net gets a vertical track assigned by the left-edge algorithm under the gap's horizontal constraint graph; constraint cycles are broken by doglegs on rows free of terminals, or by a spacer row requested from `coords.zig`; fan-out taps are the net's own `●`; back edges leave their source, drop to a return row below the diagram, run left and rise to their sink; a net the dogleg loop cannot place goes through a bounded A* over the channel's cells with a bend penalty, and every such use is counted. Channel widths are the number of tracks plus three, fed back into coordinate assignment, so `COL_GUTTER` disappears. `RoutedWire.segments` and `crossings` are produced in the exact shape `render.zig` reads. The invariants table shows I0=0, I1=0, I2=0, I3=0 on every one of the 223 rows and the test asserts it; `DOCS/preview.md` describes the algorithm that ships; the seven named fixtures are reviewed by the human once and pinned.

## Scope

**In scope:**
- `lib/preview/layout/channels.zig`: `plan`, `emit`, the constraint graph, doglegs, taps, return lanes, the A* fallback, `crossings` from the table.
- `types.zig`: `ChannelTable`, `Gap`, `Net`, `Terminal`, `Track`, `RoutePlan`.
- `orchestrator.zig`: the two-pass pipeline (`coords.assign` with stub widths → `channels.plan` → spacer rows → `coords.assign` with real widths → `channels.emit`), bounded.
- `layout_conformance_test.zig`: the invariants flipped to `== 0`; an `F=` column (fallback count) and the existing columns kept.
- `DOCS/preview.md` "Where the data comes from" and "Known limitations" rewritten; decisions entries; every golden regenerated; the gallery review.

**Explicitly deferred:**
- Crossing minimisation as a gate (`X` is reported); render changes; return lanes above rather than below (`TODO(phase3)` in the plan prompt); anything about the renderer.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| `preview_layout_channels` | `lib/preview/layout/channels.zig` | `plan(arena, graph, layered, ordering, coords) !RoutePlan`, `emit(arena, graph, layered, coords, plan) !RouteResult`, `countFallbacks(plan) u32`. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| `types.zig` | | The channel types below. |
| `orchestrator.zig` | | The two-pass pipeline; `buildStages` returns the plan. |
| `coords.zig` | | `assign` takes real `ChannelWidths`; `insertSpacerRow` used; `reserveReturnRows(n)` added (append `n` rows at the bottom). |
| `build/frontend_modules.zig`, `build.zig` | | Register `channels`; delete `route`. |
| `layout_conformance_test.zig` | | `F=` column; the `== 0` assertions. |
| `DOCS/preview.md` | | Two sections rewritten. |
| deleted | `lib/preview/layout/route.zig` | In slice 5. |

**New dependencies:** None.

## Data & State

```zig
pub const Terminal = struct { node: u32, port: u8, row: u32 }; // LayerNode index; row is the port's absolute y
pub const Net = struct {
    id: u32,            // index into `originals` of the first segment's original edge (src identity)
    src: Terminal,      // on the left edge of the gap
    sinks: []Terminal,  // on the right edge, ascending row
    lo: u32, hi: u32,   // row interval the vertical must cover (min/max over src and sinks)
    track: ?u32,        // 0-based track inside the gap; null for a straight net
    dogleg: ?Dogleg,    // second track and the jog row when the net was split
    fallback: bool,     // routed by A* (segments stored on the net)
    back: bool,         // a return-lane net (see below)
    segments: []const layout.Segment, // filled by emit
};
pub const Dogleg = struct { track2: u32, jog_row: u32 };
pub const Gap = struct {
    after_layer: u32,
    nets: []Net,        // sorted by (lo, id)
    tracks: u32,        // tracks used
    width: u32,         // tracks + 3
};
pub const RoutePlan = struct {
    gaps: []Gap,
    return_rows: u32,   // one per back edge
    spacer_rows: []u32, // rows inserted, in insertion order (for the tests)
    fallbacks: u32,
};
```

**Net extraction** (slice 1). For gap `k`, every `LayerEdge` from layer `k` to `k+1` belongs to the net of its source node and source port; a dummy's out-edge belongs to the net of the original it carries. `src.row` is `coords.y[src] + ports.outputRow(src)` (a dummy: its row); each sink's row is `coords.y[dst] + inputSlots(dst)[slot].row` (a dummy: its row). Nets are sorted by `(lo, id)`.

**Tracks** (slice 2). Track `t` is at `x = channel_x[k] + 1 + t` (cell `channel_x[k]` is the source marker column `○`, the last cell of the gap is the sink marker column `▶`). A net with all terminals on one row has `track = null`. The horizontal constraint graph has an arc `A → B` (A's track must be left of B's) whenever A has a *source* terminal on row `r` and B has a *sink* terminal on the same row `r` — A's rail from the left edge to its track and B's rail from its track to the right edge would otherwise overlap on `r`. Left-edge assignment: nets in topological order of the constraint graph, ties by `(lo, id)`; each net takes the lowest track `t` such that no net already on `t` has an overlapping `[lo, hi]` (touching at one row is overlapping — a shared cell is a shared cell) and every constraint predecessor of the net sits on a track `< t`. `tracks = max t + 1`, `width = tracks + 3` (at least today's 5 when `tracks ≤ 2`, so narrow channels do not shrink below what render's `○───▶` needs).

**Doglegs and spacers** (slice 3). A cycle in the constraint graph (detected by the topological sort failing) is broken by splitting the net with the widest `[lo, hi]` on the cycle: its vertical runs on `track` from `lo` to `jog_row`, jogs horizontally to `track2`, and continues to `hi`. `jog_row` is a row in `(lo, hi)` on which no net of this gap has a terminal and no already-placed jog lies; if none exists, `insertSpacerRow` is called at the row that separates the two conflicting terminals, the gap's nets are re-extracted from the new rows, and assignment restarts. Bounded: at most one spacer per net per gap, so at most `nets` restarts per gap; assert the bound.

**Return lanes** (slice 4). Each back edge (an `OriginalEdge` with `back`) becomes two half-nets and a lane: in the gap after its source's layer, a net from the source's port row down to `return_row` on a track of its own (assigned with the forward nets, interval `[src.row, return_row]`); in the gap before its sink's layer, a net from `return_row` up to the sink's port row, likewise; and a horizontal on `return_row` from the first track to the second. `return_row = coords.height + i` for the `i`-th back edge in ascending `(src id, dst id)` order, reserved through `reserveReturnRows`. The return row's horizontal crosses every gap between the two layers below every box, so it needs no track there and shares no cell with a forward net (forward nets never go below `coords.height − 1`).

**Fallback** (slice 6). A net that still cannot be placed after the spacer loop (the assertion above would otherwise fire) is routed by A* over the gap's cells (`channel_x[k] .. channel_x[k] + width − 1`, rows `0 .. height − 1`) from its source cell to each sink cell in turn, cost `1` per step and `3` per turn, over cells no other net occupies; the result is stored on the net, `fallback = true`, and `plan.fallbacks += 1`. The `F=` column shows the count per fixture-mode; the totals line makes a non-zero corpus count visible.

**Emission** (slice 5). One `RoutedWire` per original edge, `src_id`/`dst_id` the real ids, segments from the source port cell (`out_port` of the placed source: `x + width`, the marker column) to the sink port cell (`in_port.coord`), in order: horizontal to the track, vertical on the track (both halves of a dogleg with the jog between), horizontal to the sink — collinear pieces merged, so an aligned wire is one segment. A dummy chain is one wire whose segments continue through every gap; the dummy's row in each intermediate layer is a horizontal across that layer's box column (`layer_x[L] .. layer_x[L] + layer_w[L]`, which no box occupies on a dummy's row because packing gave the dummy its own row). Fan-out: every sink's wire shares the trunk cells from the source cell to the row where it leaves the track; the cell where it leaves is listed in `crossings` of both the leaving wire and one trunk wire (render's `isSplitPoint` then stamps `●`). Perpendicular crossings between two different nets — a net's horizontal on row `r` across a track column `x` that another net's vertical covers — are computed from the table (track intervals vs rails) and listed in both wires' `crossings`. Nothing else goes into `crossings`.

**Orchestration.** `coords.assign(stub)` → `channels.plan` (may insert spacer rows and reserve return rows) → `coords.assign(widths from plan)` (rows are kept from the first pass plus the spacers; only `x` recomputes) → `channels.emit`. Since widths do not change rows and rows do not depend on widths, two passes suffice; assert that a third pass would change nothing (a test).

## Execution & Concurrency Model

Fully synchronous, arena-allocated. The spacer loop and the A* search are bounded as stated; both bounds are asserted, not hoped for.

## Persistence & I/O

None beyond the goldens.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Nets and the channel table | Types; `extractNets` for every gap over `Coords`; `plan` returning a table with no tracks yet. | `channels: a fan-out is one net with two sinks`; `channels: a dummy chain is one net per gap`; `channels: nets are sorted by (lo, id)`; corpus: every original edge appears in exactly one net per gap it crosses (a test over the corpus). Old router still emits; goldens unchanged. |
| 2 | Left-edge tracks under the constraint graph | Track assignment, widths. | `channels: two disjoint intervals share a track`; `channels: overlapping intervals get distinct tracks`; `channels: a source on row r is left of a sink on row r`; `channels: width is tracks plus three, at least five`; corpus: the plan is computed for every fixture-mode without error (cycles reported, not yet broken — the test counts them). Goldens unchanged. |
| 3 | Doglegs and spacer rows | Cycle breaking, `insertSpacerRow` use, the bound. | `channels: a two-net constraint cycle is broken by one dogleg on a free row`; `channels: with no free row a spacer row is inserted and the plan restarts`; corpus: zero unresolved cycles. Goldens unchanged (spacers are computed, not yet applied to the emitted layout). |
| 4 | Return lanes | Back-edge half-nets and rows. | `channels: a back edge gets two tracks and a return row below the diagram`; `clean_gated_feedback`, `parallel_leftward_detours`, `regression_led_out_drives_gate` have their return rows in the plan. Goldens unchanged. |
| 5 | Emission and the switch-over | `emit`, `crossings`, the two-pass orchestrator, `route.zig` deleted, `COL_GUTTER` gone, all goldens regenerated. | The invariants table: I0–I3 zero on every row except where `F > 0`; `X` and `B` reported; the seven named fixtures' renders posted in STATUS for review; `render.zig` untouched; `channels: an aligned wire is one segment`; `channels: fan-out crossings name the tap cell on both wires`; `channels: a third coords pass changes nothing`. |
| 6 | The A* fallback | `fallback` routing and the `F=` column. | `channels: a net no track can hold is routed by A* and counted`; corpus `F` totals recorded; any fixture with `F > 0` named in STATUS with why. |
| 7 | Zero, the gallery and the docs | The `== 0` assertions, the human's review of the seven fixtures pinned, `DOCS/preview.md`, decisions entries, STATUS close-out. | `corpus_layout_invariants` asserts I0–I3 zero corpus-wide; `zig build test-all` green; `stress_grid_10x10` preview time recorded. |

## Tests

**Unit tests:** as named per slice, all in `channels.zig` on hand-built `Coords`/`LayeredGraph` inputs (a small builder in the test section constructs them from a list of `(layer, row, height, out_row, in_rows)` tuples).

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `channels_corpus_plan` | new, corpus | Every gap planned; every edge in exactly one net per gap; unresolved cycles zero (from slice 3). |
| `corpus_layout_invariants` | existing | I0–I3 zero from slice 7; `F=` added. |
| `layout_conformance_corpus`, `layout_determinism` | existing | Regenerated / still green. |

Run command: `zig build test`; `zig build test-all` before commits.

## Open Questions / Spikes

- `TODO(phase3)`: the plan prompt's seam list puts taps and crossings before return lanes; this spec puts return lanes before emission because the switch-over cannot leave back edges unrouted. The seven seams are otherwise the prompt's.
- `TODO(phase3)`: return lanes below versus above (plan prompt). Decide on the first render of `regression_led_out_drives_gate` and apply to all back edges.
- `TODO(phase3)`: multi-bit fan-in onto one gate column (`and_4bit`, `concat_four_bits`) — expected zero under per-net tracks; if not, the spike says why before any exception.
- `TODO(phase3)`: whether the `tracks + 3` width should keep a blank column between adjacent tracks whose intervals overlap for legibility (`││` versus `│ │`); measure on `stress_grid_10x10` and `demux_3bit_1to2` and let the human choose at the gallery review. The default is no blank column.
