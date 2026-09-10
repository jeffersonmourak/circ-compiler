# Phase 1 — Layering and ordering

> **Dependencies:** Phase 0 (`DOCS/PLANS/PHASE_0_measure_before_moving.md`, shipped at `c43b360`): the JSON conformance goldens, the invariants table and `tests/preview/corpus.zig` are this phase's regression net and its measure.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions 2–5 and the *The algorithm* traps first. This phase replaces `columns.zig` and `rows.zig` but **keeps `place.zig` and `route.zig` running behind an adapter**, so every render golden still renders and the only intended change is the row order. No floating point anywhere (decision 5): barycenters are `(sum, count)` pairs compared by cross-multiplication. No hash-map iteration order may reach an output. `collapse.zig`, `sizing.zig` and the port tables in `place.zig` are inputs, not things to edit. Every golden regeneration is argued in STATUS with `git diff --stat tests/fixtures` and the table's deltas; `zig build test-all` before every commit.

## Goal

After this phase the layout pipeline is `collapse → layering → ordering → (adapter) → place → route`. `lib/preview/layout/layering.zig` assigns layers the way `columns.zig` assigned columns (longest path, input pins at layer 0, root sinks at the last layer, back edges detected by DFS and excluded), and additionally splits every edge spanning more than one layer into layer-adjacent segments through dummy nodes, so the graph the next stages see has an edge between adjacent layers for every wire and nothing else. `lib/preview/layout/ordering.zig` orders every layer, real and dummy nodes alike, by barycenter sweeps that read the *port row* of each neighbour (an `and`'s `a` sits above its `b`), repeated down and up until a round stops reducing the bilayer crossing count or four rounds have run, followed by a transpose pass to a fixed point. The invariants table gains a `C=` column, the bilayer crossing count of the ordering, measured first under today's row order (the baseline) and then under the new one; over the corpus `C` never goes up on any row. The rest of the table — I0–I3, `X`, `B`, `S` — moves only because rows moved, and the phase's STATUS entries say by how much. Nothing a reader sees is meant to improve yet; the point is that the next two phases stand on a graph that knows where every wire goes.

## Scope

**In scope:**
- `lib/preview/layout/ports.zig`: the per-kind input-port order and row offsets, and the output-port row offset, as data both `ordering.zig` (order) and Phase 2's `coords.zig` (rows) read. Extracted from `place.zig`'s `resolvePortCoords`, which keeps its own copy until Phase 2 deletes it; a unit test asserts the two agree for every kind.
- `types.zig`: `LayeredGraph`, `LayerNode`, `LayerEdge`, `Ordering`.
- `layering.zig` (replaces `columns.zig`): longest path, pinned first and last layers, back-edge detection, the orphan-back-edge-destination rule (`columns.zig:43-56`, kept so `route.zig`'s detour still has its west gutter until Phase 3), dummy insertion.
- `ordering.zig` (replaces `rows.zig`): initial order, port-aware barycenter sweeps, transpose, `countCrossings`.
- `orchestrator.zig`: the adapter from `(LayeredGraph, Ordering)` to `(ColumnAssignment, RowAssignment)` over real nodes only, feeding the unchanged `place.zig` and `route.zig`.
- The `C=` column in `layout_conformance_test.zig`'s table; a determinism test; the decisions entries.

**Explicitly deferred:**
- Network-simplex layering; any change to placement or routing; using dummies for anything but ordering (Phase 2 gives them rows, Phase 3 routes through them).
- Ordering by "model order" tie-breaks other than ascending id.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| `preview_layout_ports` | `lib/preview/layout/ports.zig` | `inputSlots(node) []const Slot` (port name, `dst_port` byte, row offset from the box top, in border order) and `outputRow(node, height) u32`; the tables now in `place.zig:resolvePortCoords`, including the subcircuit rule (active inputs in `a`, `in`, `b` order on rows `1, 3, 5…`) and `ram`'s four inputs. |
| `preview_layout_layering` | `lib/preview/layout/layering.zig` | `layer(arena, graph) !LayeredGraph`. |
| `preview_layout_ordering` | `lib/preview/layout/ordering.zig` | `order(arena, graph, layered) !Ordering`, `countCrossings(layered, ordering) u64`. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| `preview_layout_types` | `lib/preview/layout/types.zig` | Add the four types below. |
| `preview_layout_orchestrator` | `lib/preview/layout/orchestrator.zig` | Call `layer` and `order`; build `ColumnAssignment`/`RowAssignment` from them for `place`/`route`. |
| build | `build/frontend_modules.zig`, `build.zig` | Register `ports`, `layering`, `ordering` modules (each with `full_format`, `layout`, `layout_types` imports as needed); delete the `columns`/`rows` modules and their test steps; add test steps for the three new modules. |
| tests | `tests/preview/layout_conformance_test.zig` | `C=` column from `countCrossings` over the same `LayeredGraph`/`Ordering` the orchestrator used (the orchestrator exposes `buildStages` returning the intermediate results, used by tests only). |
| tests | `tests/preview/layout_integration_test.zig` | Imports `layering`/`ordering` instead of `columns`/`rows` if it references them; its five text goldens regenerate with the rest. |
| deleted | `lib/preview/layout/columns.zig`, `lib/preview/layout/rows.zig` | Gone in the slice that replaces each. |

**New dependencies:** None.

## Data & State

```zig
// types.zig additions
pub const LayerNode = struct {
    /// Index into `VirtualGraph.nodes` for a real node; null for a dummy.
    real: ?usize,
    layer: u32,
    /// For a dummy: which original edge it carries (index into `LayeredGraph.originals`).
    carries: ?u32,
};

/// One original wire, as collapse produced it, kept for the adapter, the
/// router and the tests.
pub const OriginalEdge = struct {
    src: usize, // VirtualGraph node index
    src_port: u8,
    dst: usize,
    dst_port: u8,
    back: bool, // closes a cycle; reversed for layering, excluded from ordering
};

/// A layer-adjacent segment: `src` sits in layer `L`, `dst` in `L + 1`.
/// Back edges are not segmented and do not appear here (see `originals`).
pub const LayerEdge = struct {
    src: u32, // LayerNode index
    dst: u32,
    src_port: u8, // 0 on a dummy source
    dst_port: u8, // 0 on a dummy sink
    original: u32, // index into `originals`
};

pub const LayeredGraph = struct {
    nodes: []const LayerNode, // real nodes first in `VirtualGraph` order, then dummies in `originals` order, layer by layer
    edges: []const LayerEdge, // in `originals` order, then by segment
    originals: []const OriginalEdge, // node order, then `VirtualNode.outputs` order
    num_layers: u32,
};

pub const Ordering = struct {
    /// Per layer, `LayerNode` indices top to bottom.
    order: []const []const u32,
    /// Position of every node inside its layer (the inverse of `order`).
    pos: []const u32,
};
```

Layering rules, in order: (1) `originals` are enumerated from `graph.nodes` in order and each node's `outputs` in order, with the DFS of `columns.zig:detectBackEdges` marking `back`; (2) the longest-path sweep of `columns.zig` over non-back originals, input pins at 0, the orphan-back-edge-destination bump to 1, sinks forced to the last layer — so `layer(real)` equals today's `column_of` exactly; (3) every non-back original whose `layer(dst) − layer(src) = k > 1` gets `k − 1` dummies in layers `src+1 … dst−1`, appended in `originals` order, and `k` `LayerEdge`s; every non-back original with `k == 1` gets one `LayerEdge`; `k == 0` cannot happen for a non-back edge (assert). A back edge produces no dummies and no `LayerEdge`.

Ordering rules: initial order per layer is real nodes by ascending id, then dummies by `originals` index. A sweep in direction down visits layers `1 … n−1` and sorts each by the barycenter over the node's in-edges: for each `LayerEdge` into it, the neighbour's key is `pos(neighbour) * 16 + slot`, where `slot` is the neighbour's output-port slot (0) for a down sweep and the node's own input-port slot index from `ports.inputSlots` for the up sweep's mirror; the barycenter is `(sum, count)`; nodes with no edges keep their current position; a stable sort with `(sum_a * count_b < sum_b * count_a)` and a final tie on current position. An up sweep mirrors it over out-edges. One round is a down sweep then an up sweep; after each round `countCrossings` is compared with the best so far and the best ordering is kept; at most four rounds, stopping early when a round does not improve. Then transpose: for each layer, for each adjacent pair, swap if the crossings with both neighbouring layers strictly decrease; repeat over all layers until a full pass swaps nothing or 16 passes have run. `countCrossings` is the sum over adjacent layer pairs of the number of edge pairs `(e, f)` with `pos(e.src) < pos(f.src)` and `key(e.dst) > key(f.dst)` (or the mirror), where `key` uses the input-port slot so two edges into the same node's `a` and `b` count as crossing when their sources are ordered the other way. O(E²) per layer pair is fine for this corpus (largest layer ~100 nodes, one adjacent pair at a time).

Adapter: `column_of[real i] = layer`, `num_columns = num_layers`; `row_of[real i]` = the node's index among the *real* nodes of its layer in `order`, `num_rows` = the largest such count. `place.zig` and `route.zig` are untouched.

## Execution & Concurrency Model

This phase is fully synchronous. No background work is introduced. All allocation is in the caller's arena.

## Persistence & I/O

This phase has no persistence or external I/O beyond what Phase 0 established (the golden files under `tests/fixtures/preview/`).

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Ports and the layered types | `ports.zig` with the tables and `types.zig` with the four types; build wiring. | `ports: every kind agrees with place.zig's resolvePortCoords` (drives both over one node per kind, including a three-input subcircuit and a `ram`, and compares names, `dst_port` bytes and rows); `ports: input slots are in border order`. All goldens byte-identical. |
| 2 | Layering with dummies | `layering.zig`; `columns.zig` deleted; orchestrator adapter over real nodes; `layout_integration_test.zig` repointed. | `layering: layers equal the old column assignment` (over every corpus fixture-mode, `layer(real)` equals the values the JSON goldens imply from component `x` order — checked by regenerating nothing: all 223 JSON goldens, the 27 render goldens and the invariants table stay **byte-identical**); `layering: a three-layer edge gets two dummies and three segments`; `layering: a back edge is flagged and gets no dummy`; `layering: input pins are layer 0 and sinks the last layer`. |
| 3a | The crossing count, baseline | `countCrossings` in `ordering.zig` (the rest of the file is a shim returning the adapter's order from today's `rows.zig`), the `C=` column in the table. | Table regenerated with only the new column added; every other value byte-identical (asserted by a script diff in STATUS); `ordering: countCrossings on a hand-built crossing pair is 1 and on the uncrossed pair is 0`; `ordering: a and b ports crossed by source order count`. |
| 3b | Port-aware sweeps and transpose | The real `order` in `ordering.zig`; `rows.zig` deleted; goldens regenerated. | `C` never up on any of the 223 rows against 3a's table (a test compares the two tables' `C` columns: `tests/preview/layout_conformance_test.zig` reads the committed previous table from git? No — the comparison is done once in the slice and recorded in STATUS; the golden is the new state); `ordering: equal barycenters keep the current order`; `ordering: the sweep stops when a round does not improve`; `ordering: transpose reaches a fixed point`. |
| 4 | Determinism and close-out | `layout_determinism` test (two full pipeline runs per corpus fixture-mode, byte-identical JSON), decisions entries (layering with dummies; port-aware ordering with integer barycenters), STATUS close-out with the table deltas. | The determinism test green over the corpus; `zig build test-all` green. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `ports: every kind agrees with place.zig's resolvePortCoords` | `ports.zig` | Names, bytes and rows match for every `NodeKind`. |
| `ports: input slots are in border order` | `ports.zig` | Rows strictly increase within a node. |
| `layering: a three-layer edge gets two dummies and three segments` | `layering.zig` | Dummy count, layers, `carries`, edge chain. |
| `layering: a back edge is flagged and gets no dummy` | `layering.zig` | Cross-coupled pair: one `back`, zero dummies for it, its destination bumped to layer 1. |
| `layering: input pins are layer 0 and sinks the last layer` | `layering.zig` | Pinning rules. |
| `ordering: countCrossings …` (two cases) | `ordering.zig` | Bilayer count on hand-built graphs, port-aware. |
| `ordering: equal barycenters keep the current order` | `ordering.zig` | Stability. |
| `ordering: the sweep stops when a round does not improve` | `ordering.zig` | Round counter observable through a returned `rounds` field on `Ordering` (test-only, `u8`). |
| `ordering: transpose reaches a fixed point` | `ordering.zig` | A layer that transpose can improve ends improved; a second call changes nothing. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `layout_conformance_corpus` | existing | JSON goldens, regenerated in 3b. |
| `corpus_layout_invariants` | existing, `C=` added | The table, regenerated in 3a and 3b. |
| `layout_determinism` | new | Two runs, byte-identical JSON, every fixture-mode. |

Run command: `zig build test` (and `UPDATE_GOLDENS=1 zig build test`); `zig build test-all` before each commit.

## Open Questions / Spikes

- `TODO(phase1)`: slice 2's byte-identity claim rests on the adapter reproducing `row_of` as `rows.zig` produces it today; if `rows.zig`'s barycenter over `node.inputs` including back edges produces an order the shim cannot reproduce from real-nodes-only data, slice 2 keeps `rows.zig` in the pipeline untouched (the adapter only replaces columns) and the identity holds by construction. Decide on the first run.
- `TODO(phase1)`: the constant `16` in the port-slot key must exceed the largest input-port count (a `ram` has 4, a subcircuit at most 3 active); assert it in `ports.zig`.
- `TODO(phase1)`: whether the transpose pass is worth its cost on `stress_grid_10x10` (100 nodes in one layer, O(n²) per pass, ≤16 passes); measure the conformance step's time before and after and record it.
