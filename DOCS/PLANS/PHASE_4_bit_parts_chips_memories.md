# Phase 4 — Bit parts, chips and memories

> **Dependencies:** Phase 3 (inset, tail and dot rules; `assets.offscreen`; the user-subcircuit fallthrough).
> **Warnings:** Decisions 10, 11, 12 and 13. The write indicator is a mirrored rule, not the engine's word; STATUS must say so when the gallery review looks at `ram-write-read`. `BitValue` masks are `bigint`; every width test in this phase runs at 4, 8, 16 and 32 bits.

## Goal

A slice draws the incoming word as a ruler, MSB on the left, with the tapped bits filled in the bus colour and the discarded bits muted, and a range bar instead of a ruler above 16 bits. A concat draws the assembled word as stacked bands with a numbered lane from each port. A user subcircuit is a chip with a purple header carrying its name in capitals and the instance name in the body. A ROM or RAM is the same chip with the declaration in the header, `addr → word` in the body, port labels inside the left edge for RAM, and a `wr ●` indicator that lights on the clock edge that the engine would write on. None of these carries the renderer's bus badge.

## Scope

**In scope:**
- `nsShell`, `nsSliceAsset` (with the range-bar branch), `nsConcatAsset`, `nsBitPart` (`circ-site-theme.js:730-842`, `:1437-1456`).
- `nsUserSubcircuit` (`:1004-1055`) replacing the labelled-box fallthrough kept in Phase 3.
- `nsMemory` for `rom` and `ram` (`:1066-1156`) with the header from `bitWidth` and `memory.addrWidth`, the body from `inputValues[0]` and `outputValue`, and the mirrored write rule.
- `drawSlice`, `drawConcat`, `drawSubcircuit` (user branch), `drawMemory` rewritten. The header is `MODE` on the left and `W×2^A` on the right, not the `rom code[8,4]` string, so the `memoryLabel` import leaves the theme and the "labelled by the renderer" case in `circ-theme-hover.test.ts` is retired with a note in STATUS.
- Goldens for `slice`, `concat`, `subcircuit`, `rom`, `ram` regenerated.

**Explicitly deferred:**
- The runtime write stamp (decision 11).
- A designed range bar beyond decision 13.

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/utils/circ-skins.mjs` | The five functions above; `ramEdgeState: WeakMap<object, Map<number, BitValue>>` keyed on `ctx.canvas ?? ctx`. |
| site | `site/test/canvas-record.ts` | The recorder exposes a stable `canvas` object so the edge state can be keyed in tests. |
| site | `site/test/circ-skins.test.ts` | Slice, concat, chip, memory cases; RAM edge sequence test; goldens regenerated. |
| site | `site/test/circ-theme-hover.test.ts` | Retire the `memoryLabel` import assertion; keep the ring and registration cases. |
| site | `DOCS/decisions/canvas-theme.md` | Decisions 10–13. |

**New dependencies:** None.

## Data & State

Slice: `inWidth = max(inputValues[0].width, slice.hi, 1)`; ruler when `inWidth ≤ 16`: `tickW = (rulerW − gap(inWidth − 1)) / inWidth`, bit `i` from the left is `inWidth − 1 − i`, taken when `lo ≤ bit < hi`; range bar when `inWidth > 16`: one `roundRect` spanning `rulerW` in `labelMuted` at alpha `0.38`, and the tapped span `[lo, hi)` mapped to `x = bx + padX + rulerW × (inWidth − hi) / inWidth`, width `rulerW × (hi − lo) / inWidth`, filled `wireBus`. Label `[lo:hi]` or `[n]` at `y0 + 0.74 h` in both branches.

Concat: `n = inPorts.length`, bands `segH = (barH − gap(n − 1)) / n`, lane from `bx + 0.78 cell` to `laneX = bx + 1.25 cell` then `arcTo` into the band, alpha `max(0.45, 1 − 0.2 i)`, index glyph at `bx + 0.42 cell`.

Memory body text: `addrText` from `inputValues[0]` (`?` unless fully defined, else hex padded to `ceil(A/4)`), `wordText` from `outputValue` (padded to `ceil(W/4)`), both through `nsHex` (Phase 1, `bigint`). Header right: `${W}×${2 ** A}` with `W = component.bitWidth`, `A = component.memory.addrWidth`.

RAM write rule, per draw:

```js
// ports in slot order: addr, din, we, clk (ports.ts / circ-scenes.js)
const now = inputValues[3], prev = state.get(component.id) ?? undefinedValue(1);
const rising = bit0High(now) && bit0Low(prev);        // bit0Low is false for undefined, as in circuit.zig:196
state.set(component.id, now);
const writing = rising && bit0High(inputValues[2]) && fullyDefined(inputValues[0]);
```

`bit0High(v) = (v.defined & 1n) === 1n && (v.value & 1n) === 1n`; `bit0Low(v) = (v.defined & 1n) === 1n && (v.value & 1n) === 0n`. The indicator lights for the draw in which `writing` is true; the next draw with an unchanged clock sees `prev === now` and does not fire.

## Execution & Concurrency Model

Fully synchronous. The edge state is per canvas element and per component id; `setTheme` keeps the element (`canvas.ts:194`), so a theme flip does not reset it. A rebuild of the canvas (a recompile in the playground) creates a new element and a fresh map.

## Persistence & I/O

Op-log goldens only.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Slice ruler and range bar | `nsShell`, `nsSliceAsset`, `nsBitPart`, `drawSlice`. | Width 8 `[0:4]`: eight `roundRect` ticks, the four rightmost filled `wireBus`; width 8 `[3]`: one filled; width 32 `[8:16]`: one bar plus one filled span at the mapped x and width; label text per branch. |
| 2 | Concat bands | `nsConcatAsset`, `drawConcat`. | 2, 3, 4 operands: `n` bands, `n` lanes each with one `arcTo`, alpha sequence `1, 0.8, 0.6, 0.45`, index glyphs `"0"…`; box height `2n + 1` from `concatSize`. |
| 3 | User-subcircuit chip | `nsUserSubcircuit`, the user branch of `drawSubcircuit`. | Log: `roundRect` shell in `macro` stroke and `surface` fill, `clip`, header `fillRect` at alpha `0.18`, rule at alpha `0.5`, name `fillText` uppercased at `y0 + 0.5 cell`, instance name in `label`; a builtin name still takes the recipe path. |
| 4 | ROM and RAM chips | `nsMemory`, `drawMemory`; `memoryLabel` import removed. | ROM `[8,4]` at addr `0x5` word `0x3C`: header `ROM` left and `8×16` right, body segments `0x5`, `→`, `0x3C` with the word in `wireBus`; undefined addr → `?` in `labelMuted`; name below the box. RAM: four port labels at the port rows, body one row above the name, `wr` glyph present. |
| 5 | The write indicator | Edge state and rule. | Sequence test on one recorder canvas: clk undefined→high (no fire), high→low→high with `we` high and addr defined (fires once), high again (no fire), rising with `we` low (no fire), rising with addr partly undefined (no fire). |
| 6 | Gallery review | The human reviews `rom-lookup`, `ram-write-read`, `demux-1to2`, `slice-and-concat`, `two-bit-adder` in both modes. | STATUS records the review; if the mirrored indicator misled, decision 11 is reopened as a follow-up, not fixed here. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `a slice ruler fills exactly the tapped bits, MSB left` | `circ-skins.test.ts` | Tick fill colours per bit at widths 4, 8, 16. |
| `a slice above 16 bits is a range bar` | same | One bar and one span at width 32; span x and width as in Data & State. |
| `concat draws one band and one lane per operand` | same | Counts and alpha sequence at 2, 3, 4. |
| `a user subcircuit is a chip with a header` | same | Op sequence as in slice 3. |
| `a memory shows addr → word from its values` | same | Text segments and colours; `?` when undefined. |
| `the RAM indicator fires on the engine's edge and only then` | same | The five-step sequence of slice 5. |
| `memories draw no bus pill` | same | `busValue` log empty (carried from Phase 2, now with the real skin). |
| `every skin's op log matches its golden` | same | Regenerated for the five kinds. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `bun --bun run build` + `bun run bundle` | site | Green. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase4)`: `PlacedComponent.memory` is `{ addrWidth }` (`circ-renderer/src/layout/types.ts:90`) and `bitWidth` is the data width; confirm at slice 4 that a collapsed macro containing a memory does not reach `drawMemory` (it is a `subcircuit` node in opaque mode) so the header never reads an undefined `memory`.
- `TODO(phase4)`: the memory body centres on `bx + bw/2 + 0.9 cell` for RAM to clear the port labels (`:1114`); at the minimum RAM width (`max(5, label + 4)`, label `ram x[8,4]` → 13 cells) confirm the three text segments fit at `cell 10`, else drop to `nsFont(cell, 600)` for the body and record it.
