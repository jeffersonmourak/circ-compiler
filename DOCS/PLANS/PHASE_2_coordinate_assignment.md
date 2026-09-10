# Phase 2 — Coordinate assignment

> **Dependencies:** Phase 0 (the goldens and the table) and Phase 1 (`LayeredGraph`, `Ordering`, `ports.zig`), both shipped.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions 6, 8 and 10 and the *The algorithm* traps. This phase replaces `place.zig` while **`route.zig` keeps running** over the `PlacedComponent` list it has always consumed, so renders keep working; channel widths are a stub equal to today's `COL_GUTTER` until Phase 3 supplies real ones. Box sizes and port tables do not change (they move files). Per-node rows replace per-grid rows: a layout may get taller, and `TODO(phase2)` in the plan prompt makes the human the judge of that before the goldens are pinned. No floats; no hash-map iteration order in outputs.

## Goal

After this phase every node has its own row, chosen so that the wire feeding its highest-priority input port arrives straight whenever the packing allows, instead of every node in a grid row sharing that row's top. `lib/preview/layout/coords.zig` walks layers left to right, gives each node its preferred `y` from the port row of its median predecessor, packs the layer top to bottom in the Phase 1 order with at least one free row between boxes, and then walks right to left once to pull a source level with its only sink where that breaks no earlier alignment; dummy nodes are height-1 rows aligned with their predecessor so a long wire runs straight through the columns it crosses. Column `x` positions come from cumulative box widths plus per-gap channel widths supplied by a `ChannelWidths` table (all `5` in this phase). `coords.zig` also owns the one feedback door Phase 3 needs: `insertSpacerRow(y)`. The measure is the invariants table's `S=` (straight wires of total): it rises against Phase 1's table and never falls on any row; `chain`, `single_gate` and `fan_out` render byte-identically to today; the per-fixture `size=` deltas are on record.

## Scope

**In scope:**
- `lib/preview/layout/boxes.zig`: `sizeOf`, `composeDisplayLabel`, `composeLedLabel` and `resolvePortCoords`, moved out of `place.zig` unchanged (the latter now reading `ports.zig`, whose tables Phase 1 proved equal).
- `lib/preview/layout/coords.zig`: `assign(arena, graph, layered, ordering, widths) !Coords`, `toPlaced(arena, graph, layered, coords) ![]PlacedComponent`, `insertSpacerRow(coords, y)`.
- `types.zig`: `Coords`, `ChannelWidths`.
- `orchestrator.zig`: `coords.assign` with a stub `ChannelWidths` of `COL_GUTTER`, then `toPlaced`, then the unchanged `route`.
- Goldens regenerated (twice: after slice 2 and after slice 3), the height spike, decisions entries.

**Explicitly deferred:**
- Real channel widths, spacer rows *used* (Phase 3 calls the door; this phase only builds it), return-lane rows.
- Any change to `route.zig`, render, sizes or port tables.
- Brandes–Köpf's four-orientation balancing: one direction plus one reverse pass is the whole of this phase's alignment.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| `preview_layout_boxes` | `lib/preview/layout/boxes.zig` | Box size, display label and port coordinates per node (from `place.zig`). |
| `preview_layout_coords` | `lib/preview/layout/coords.zig` | Rows and x per node, channel x ranges, the spacer door, and the `PlacedComponent` materialisation. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| `preview_layout_types` | `types.zig` | Add `Coords`, `ChannelWidths`. |
| `preview_layout_orchestrator` | `orchestrator.zig` | Replace `place` with `coords.assign` + `toPlaced`; `buildStages` (test hook) returns `Coords` too. |
| build | `build/frontend_modules.zig`, `build.zig` | Register `boxes`, `coords`; delete `place`; test steps. |
| tests | `layout_conformance_test.zig` | No new column; the `size=` column is what the spike reads. |
| deleted | `lib/preview/layout/place.zig` | In slice 2. |

**New dependencies:** None.

## Data & State

```zig
pub const ChannelWidths = struct {
    /// Width in cells of the gap after layer `k`, `k in 0 .. num_layers-1`.
    /// Includes the source marker cell, the sink marker cell and every track.
    after: []const u32,
};

pub const Coords = struct {
    /// Per LayerNode: top-left cell of a real node's box; the single row of a dummy.
    x: []u32,
    y: []u32,
    /// Per layer: left edge and width of the widest box in it.
    layer_x: []u32,
    layer_w: []u32,
    /// Per gap after layer k: first cell of the channel (`layer_x[k] + layer_w[k]`).
    channel_x: []u32,
    width: u32,
    height: u32,
};
```

Row assignment, left to right over layers `0 … n−1`, nodes in `Ordering.order[L]`:
1. **Preferred row.** For a real node with in-edges from layer `L−1`: take the in-edge whose destination port slot is lowest (`a` before `b`, `addr` before `din`; a dummy's single edge); its source's port row (`y[src] + ports.outputRow(src)` for a real source, `y[src]` for a dummy); the preferred top is that row minus the port's own offset (`ports.inputSlots(node)[slot].row`). Layer 0 nodes and nodes with no in-edge from `L−1` (back-edge-only destinations) have no preference. A dummy's preferred row is its predecessor's port row exactly.
2. **Packing.** Walk the layer's order top to bottom keeping `cursor` (the first free row, initially 0). A node is placed at `max(cursor, preferred)` when it has a preference and at `cursor` otherwise; `cursor = y + height + ROW_GUTTER` (`ROW_GUTTER = 1`; a dummy's height is 1). This never moves a node above the one before it, so the Phase 1 order is preserved and no two boxes touch.
3. **Reverse pass.** Walk layers `n−2 … 0`; for each node with exactly one out-edge to `L+1` and whose sink's preferred row was *not* satisfied in step 2, or whose own row is above where its sink's port would make it straight: move the node down to the row that makes that wire straight if the row is free (below the previous node's `cursor` and above the next node's `y − ROW_GUTTER − height`); otherwise leave it. Never move up (up could break an alignment made in step 1).
4. **Columns.** `layer_w[L] = max width of real boxes in L` (a dummy has width 0; a layer of only dummies has width 1 so its cell exists); `layer_x[0] = 0`, `layer_x[L+1] = layer_x[L] + layer_w[L] + widths.after[L]`; `x[node] = layer_x[L]` (boxes are left-aligned in their layer as today). `width` and `height` are the extents; `height` is `max(y + height)`.

`insertSpacerRow(coords, y)`: every node with `y[node] >= y` moves down one; `height += 1`. Phase 3 calls it for doglegs.

`toPlaced` materialises `PlacedComponent` exactly as `place.zig` does today (ports from `boxes.resolvePortCoords`, labels from `composeDisplayLabel`), real nodes only, in `VirtualGraph` order.

## Execution & Concurrency Model

This phase is fully synchronous. No background work is introduced.

## Persistence & I/O

None beyond the goldens.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | `boxes.zig` | The four functions moved; `place.zig` calls them; `ports.zig` is their port source. | All goldens byte-identical; `boxes: port coordinates equal the ports table plus the box origin`. |
| 2 | Rows from alignment, columns from widths | `coords.zig` steps 1, 2 and 4 with a stub `ChannelWidths`; `toPlaced`; `place.zig` deleted; goldens regenerated. | `S` never falls on any row against Phase 1's table (recorded in STATUS with the per-row diff); `chain`, `single_gate`, `fan_out` renders byte-identical; `coords: a NOT feeding an AND's b port sits two rows lower`; `coords: packing never overlaps and never reorders`; `coords: layer 0 packs from row 0`. |
| 3 | The reverse pass, dummies and the spacer door | Step 3; dummies aligned; `insertSpacerRow`; goldens regenerated; the height spike measured. | `S` never falls against slice 2; `coords: a lone source is pulled level with its sink`; `coords: a long edge's dummies stay on one row`; `coords: insertSpacerRow shifts every node at or below y and grows height by one`; STATUS carries the corpus `size=` deltas and the largest growth, for the human's call. |
| 4 | Close-out | Decisions entries (per-node rows from port alignment; the spacer door), STATUS close-out. | `zig build test-all` green; the table's I0–I3 deltas reported (they move because rows moved; they are not a gate yet). |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `boxes: port coordinates equal the ports table plus the box origin` | `boxes.zig` | For every kind. |
| `coords: a NOT feeding an AND's b port sits two rows lower` | `coords.zig` | The `and_of_not` shape: NOT (height 3, out row 1) → AND `b` (row 3): NOT's `y` = AND's `y + 2`. |
| `coords: packing never overlaps and never reorders` | `coords.zig` | Random-free hand-built layers with mixed heights. |
| `coords: layer 0 packs from row 0` | `coords.zig` | Inputs at rows 0, 4, 8 for three height-3 pins. |
| `coords: a lone source is pulled level with its sink` | `coords.zig` | Reverse pass. |
| `coords: a long edge's dummies stay on one row` | `coords.zig` | Two dummies, same `y`. |
| `coords: insertSpacerRow shifts …` | `coords.zig` | The door. |

**Integration tests:** the existing three, regenerated in slices 2 and 3.

Run command: `zig build test`; `zig build test-all` before commits.

## Open Questions / Spikes

- `TODO(phase2)`: the height budget — slice 3 reports `sum(height)` and `max(Δheight)` over the corpus against Phase 1; the human decides whether any fixture's growth is unacceptable before slice 4 pins the goldens. The expected offenders are the N-bit adders in expanded mode.
- `TODO(phase2)`: whether a sink with *two* in-edges (an `and`) should prefer its `a` or the median of both; the spec says lowest slot (`a`). If `S` on `full_adder_from_builtins expanded` is worse than the median rule on a one-off measurement, switch to the median and say so.
- `TODO(phase2)`: `route.zig`'s detour searches assume today's `COL_GUTTER` geometry; if a render golden shows a wire through a box after slice 2 that was clean before (I0 up on a row), that is Phase 3's to fix, not this phase's — record it and move on.
