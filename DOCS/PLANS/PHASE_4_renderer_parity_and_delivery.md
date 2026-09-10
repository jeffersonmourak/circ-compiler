# Phase 4 — Renderer parity and delivery

> **Dependencies:** Phases 0–3 shipped; the Zig pipeline is final (`layering`, `ordering`, `coords`, `channels`, `boxes`, `ports`) and the 223 JSON goldens describe it. Phase 0's renderer harness is on `circ-renderer` `host-pin-api` at `fe40266` (over `62d0def`), not pushed.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions 5, 12, 13 and 14 and the *Cross-repository work* traps. Every renderer command names its directory (`cd /Users/jeffersonmourak/circus/circ-renderer && …`). The TypeScript files are transliterations: same stage boundaries, same names, same tie-breaks, integer arithmetic. `collapse.ts` is **not** a transliteration and stays as it is — it keeps `slice`/`concat` as drawable nodes where `collapse.zig` folds them, a deliberate difference the canvas depends on — so parity is asserted over the vendored corpus, which contains no slice/concat fixture, and the manifest says so. The renderer push and the site's pin bump are the human's; slice 4 is a hard stop. Site gates: `bun test`, `bun --bun run typecheck`, `bun --bun run build`, `bun run bundle`; plain `bun run build` fails on this machine.

## Goal

After this phase `circ-renderer`'s `buildLayout()` produces, for every vendored fixture-mode, the same `LayoutGrid` projection as the compiler's JSON — the `MATCHES_TODAY` and `TS_TODAY` lists are gone and every parity case is a plain equality — and its own invariant rows are all zeros. The canvas draws the new layouts with no painter change beyond one filter: `crossings` now carries fan-out tap cells as well as perpendicular crossings (what the ASCII renderer needs), and the wire tracer skips a crossing point that lies on another wire of the same source so it draws jump arcs only where two nets cross. The site pins the pushed renderer sha, `site/public/wasm/libcirc.wasm` and every example artifact and preview string are regenerated from the compiler at this branch's head, and `/playground`'s Preview tab shows the new `and_of_not` from the committed module. `DOCS/preview.md` and the decisions ledger are final.

## Scope

**In scope:**
- `circ-renderer/src/layout/{ports,layering,ordering,boxes,coords,channels}.ts` transliterated from the Zig files; `columns.ts`, `rows.ts`, `place.ts`, `route.ts` deleted; `src/layout/index.ts` composing the new stages with the two-pass orchestration; `types.ts` extended with the same intermediate types.
- The wire tracer's tap filter (`src/render/wire-path.ts` or wherever `traceWire` lives) and its test.
- `test/layout-parity.test.ts` reduced to equality over every vendored fixture-mode; `test/layout-invariants.test.ts`'s `TS_TODAY` replaced by an all-zero assertion; the vendored corpus re-vendored from the final compiler commit (JSON, `.wasm`, `invariants.txt`, `MANIFEST.md`).
- Site delivery per decision 14.

**Explicitly deferred:**
- Porting `collapse.zig`'s slice/concat folding (the canvas draws them); any renderer feature; the renderer's PR into its `main` (the maintainer's).

## File & Module Topology

**New files (renderer):**

| Module | File | Responsibility |
|--------|------|---------------|
| layout | `src/layout/ports.ts` | `inputSlots`, `outputRow` — from `ports.zig`. |
| layout | `src/layout/layering.ts` | `layer(graph)` — from `layering.zig`. |
| layout | `src/layout/ordering.ts` | `order(graph, layered)`, `countCrossings` — from `ordering.zig`. |
| layout | `src/layout/boxes.ts` | Sizes, labels, port coordinates — from `boxes.zig`, but keeping the renderer's `sliceSize`/`concatSize` and slice/concat port rules (the one place the two sides differ, by design). |
| layout | `src/layout/coords.ts` | `assign`, `toPlaced`, `insertSpacerRow`, `reserveReturnRows` — from `coords.zig`. |
| layout | `src/layout/channels.ts` | `plan`, `emit` — from `channels.zig`. |
| test | `test/layering.test.ts`, `test/ordering.test.ts`, `test/coords.test.ts`, `test/channels.test.ts` | The Zig unit tests, one to one. |

**Modified files (renderer):** `src/layout/index.ts`, `src/layout/types.ts`, the wire tracer and its test, `test/layout-parity.test.ts`, `test/layout-invariants.test.ts`, `test/layout-helpers.ts` (unchanged API), `test/fixtures/**` (re-vendored), `README.md`, `package.json` (version bump to the next alpha).

**Deleted (renderer):** `src/layout/columns.ts`, `rows.ts`, `place.ts`, `route.ts`.

**Modified files (this repository, slice 4):** `site/package.json`, `site/bun.lock`, `site/src/utils/renderer-versions.ts`, `site/public/wasm/libcirc.wasm`, `site/public/wasm/libcirc.manifest.json`, `site/public/wasm/*.wasm` (the example artifacts), `site/src/content/examples.ts` (preview strings), `site/scripts/.compiled.json` if tracked, `DOCS/preview.md` (final read-through), `DOCS/decisions/preview-layout.md`, `DOCS/STATUS.md`.

**New dependencies:** None on either side.

## Data & State

The TypeScript types mirror `types.zig` field for field (`LayerNode`, `OriginalEdge`, `LayerEdge`, `LayeredGraph`, `Ordering`, `ChannelWidths`, `Coords`, `Terminal`, `Net`, `Dogleg`, `Gap`, `RoutePlan`) with `number` for every integer and arrays for slices; barycenters are `[sum, count]` tuples compared as `sumA * countB < sumB * countA`; no `Map` or `Set` iteration reaches an output (iterate index arrays; sort keys before use). `RoutedWire.realSrcId` (renderer-only) keeps its current derivation from the original edge. The `LayoutGrid` contract is unchanged.

## Execution & Concurrency Model

Synchronous on both sides. The renderer's canvas rebuild path is untouched.

## Persistence & I/O

Vendoring copies files between the two repositories by hand (the manifest records the commit); the site delivery slice writes the committed artifacts through the existing scripts. No other I/O.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Ports, layering, ordering | The three modules and their tests; `columns.ts`/`rows.ts` deleted; `index.ts` composes them through the same adapter Phase 1 used, over the old `place.ts`/`route.ts`. | The transliterated unit tests green; `bun test` + `bun run typecheck` green; parity lists updated (measured) and recorded in STATUS. |
| 2 | Boxes and coordinates | `boxes.ts`, `coords.ts`; `place.ts` deleted; the stub widths. | Unit tests green; parity lists updated. |
| 3 | Channels, the switch-over, the tap filter | `channels.ts`; `route.ts` deleted; the two-pass `index.ts`; the wire tracer filter; re-vendor from the final compiler commit; `MATCHES_TODAY`/`TS_TODAY` deleted. | Every vendored fixture-mode equal after projection; every TS invariant row all zeros; the tracer test proves a tap cell draws no jump while a true crossing still does; `bun test` + `bun run typecheck` green. Renderer committed; **hard stop**: the human pushes `host-pin-api` and names the sha. |
| 4 | Site delivery | `bun add circ-renderer@github:jeffersonmourak/circ-renderer#<sha>`, `RENDERER_PIN_VERSION`, `zig build circ-compile`, `cd site && bun run libcirc`, `bun run scripts/compile-content.ts`, the four site gates, `DOCS/preview.md` final, decisions, STATUS close-out for the initiative. | `site/test/renderer-pin.test.ts` green against the new sha; `bun run bundle` green; `git diff --stat site/src/content/examples.ts` shows every preview string moved; `zig build test-all` green; the manual check "open `/playground`, pick `and-not`, read the Preview tab" recorded as run or unrun. |

## Tests

**Unit tests (renderer):** the Zig tests of Phases 1–3, transliterated one to one, plus `wire tracer: a fan-out tap is not a jump`.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `layout parity` | renderer | Equality on every vendored fixture-mode. |
| `layout invariants` | renderer | The checker reproduces the compiler's rows over the compiler's grids (all zeros now) and this port's rows are all zeros. |
| `renderer pin` | site | The installed package, the lock and `RENDERER_PIN_VERSION` agree; the probes still find `getLayout`, `setHighlight` and the rest. |
| `island-smoke`, `content-artifacts`, `adders` | site | Unchanged and green after the regeneration. |

Run commands: `cd /Users/jeffersonmourak/circus/circ-renderer && bun test && bun run typecheck`; in `site/`: `bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`; here: `zig build test-all`.

## Open Questions / Spikes

- `TODO(phase4)`: whether the site's `source-link.ts` name join needs a change — it reads `getLayout()` for box positions only, so it should not; confirm with `site/test/source-link.test.ts` against the new pin before declaring the slice done.
- `TODO(phase4)`: the six circuits excluded from vendoring by name collision (`and_4bit`, `bit_index_a2`, `concat_four_bits`, `half_adder`, `inverter`, `slice_then_concat`) — vendor them under `parity-<name>.wasm` in slice 3 if the collision was the only reason, so the corpus on the renderer side grows rather than shrinks; the slice/concat ones stay out (the `collapse.ts` difference).
- `TODO(phase4)`: the renderer's own layout tests (`test/layout.test.ts`, `test/wire-path.test.ts`, `test/canvas.test.ts`) pin positions from the old router; each is updated to the new numbers with the reason in the commit, never deleted.
