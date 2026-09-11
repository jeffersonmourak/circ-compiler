# Phase 2 — Pins and LEDs

> **Dependencies:** Phase 1 (helpers, palettes, wire hook).
> **Warnings:** Decisions 7, 8 and 9 of the plan prompt. The pill for a bus is drawn by `busValue`, never by a skin; the ring is drawn by `highlight`, never by a skin; the islands widen the gutter and the padding in the same slice as the pill, or a top-row pin's pill is clipped.

## Goal

An input or output pin shows its state by shape: a solid disc when HIGH, a hollow ring when LOW, a dashed outline when undefined, with its name in the centre and a pill above carrying `0`, `1`, `?` or the bus value in the reader's chosen base. Hovering an input pin draws a ring outside the circle and leaves the state visible. An LED lit HIGH glows under a pre-rendered halo; LOW is a hollow ring with a small core, undefined is dashed. Every canvas on the site leaves two rows between boxes and enough padding that a pill on the top row is never clipped.

## Scope

**In scope:**
- `nsPinCircle`, `nsValuePill`, `nsHoverRing` ported (`circ-site-theme.js:639-729`); `drawInputPin`/`drawOutputPin` rewritten on them (`nextSiteSkins.input_pin/output_pin`, `:844-899`), the `hovered` fill swap removed.
- `busValue` hook: draws `nsValuePill` above every `bitWidth > 1` component except `rom`/`ram`, using the hook's `text`; solid, fill `wireBus`, ink `busLabel`. Seat: pins at `cy − r − 0.5 cell`; every other kind at `y0 − 0.5 cell` (bottom edge of the pill).
- Single-bit pins draw their own `0`/`1`/`?` pill from the skin (`bitWidth === 1` only).
- `highlight` hook: `nsHoverRing` (circle at `r + 0.38 cell`) for `input_pin` and `output_pin`; today's rounded rectangle for every other kind.
- `led` skin ported (`:901-957`) with the HIGH halo through `nsVecHalo` (offscreen via `assets.offscreen`).
- `LiveCanvas.astro` and `Playground.astro`: `layoutOptions: { rowGutter: 2 }` and `padding: Math.ceil(cell * 1.5)` (`21` at `cell 14`); the `padding` prop of `LiveCanvas` defaults to that expression instead of `16`.
- `circ-theme-hover.test.ts` rewritten for the new policy.

**Explicitly deferred:**
- Gate, slice, concat, subcircuit, memory skins (Phases 3–4).
- A pill for `rom`/`ram` (never: the word is in the body, Phase 4).

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/utils/circ-skins.mjs` | `nsPinCircle`, `nsValuePill`, `nsHoverRing`, `nsVecHalo` (+ `vecHaloCache`), `drawInputPin`, `drawOutputPin`, `drawLed`, `busValue`, `highlight` (kind-dispatching). |
| site | `site/src/utils/circ-theme.mjs` | `busValue` and the new `highlight` in `sharedRenderers`. |
| site | `site/src/components/LiveCanvas.astro` | `padding` default, `layoutOptions`. |
| site | `site/src/components/Playground.astro` | `padding`, `layoutOptions` at the `renderCircuit` call (`:2792-2796`). |
| site | `site/test/circ-skins.test.ts` | Pin geometry cases, `busValue` cases, highlight cases, LED cases; goldens for pins and LEDs regenerated. |
| site | `site/test/circ-theme-hover.test.ts` | Ring policy (circle for pins, rectangle otherwise, one caller of each helper, no skin calls either); the input pin no longer reads `inputHover`. |
| site | `DOCS/decisions/canvas-theme.md` | Decisions 7, 8, 9. |

**New dependencies:** None.

## Data & State

Pill geometry, from `nsValuePill` (`:691-720`): height `h = 0.92 cell`, width `measureText(text).width + 0.7 cell`, radius `h/2`, top `bottomY − h`, text baseline `middle` at `y + h/2 + 0.03 cell`. Modes: `solid` (fill given), `outline` (fill `surface`, stroke given), `dashed` (fill `surface`, stroke `labelMuted`, dash `[0.26, 0.22] cell`).

Pin geometry, from `nsPinCircle`: `r = min(w, h)/2 − 0.08 cell`, `lw = max(2, 0.14 cell)`; LOW stroke `lw × 1.2`; dash `[0.28, 0.24] cell`. The pill's bottom for a pin is `cy − r − 0.5 cell`; its top is therefore `cy − r − 1.42 cell = y0 − 1.34 cell` for a 3-row box, which is why the gutter is 2 and the padding `1.5 cell`.

`busValue` hook context (renderer, unchanged): `{ ctx, theme, cell, component, value, text }`. The seat is computed from `component` alone: for `ComponentKind.InputPin`/`OutputPin`, `cy − r − 0.5 cell` with `r` as above; otherwise `component.y * cell − 0.5 cell`.

`vecHaloCache: Map<string, HTMLCanvasElement>` keyed `${key}|${w}x${h}|${color}|${spread}` (`:532-535`), filled through `assets.offscreen(w, h)`; under the stub it holds recorder canvases and the test asserts the key format, not pixels.

## Execution & Concurrency Model

Fully synchronous. The halo cache is module-level and grows with distinct `(key, size, colour, spread)`; sizes are cell-derived so a page with three cell sizes holds at most three entries per shape and colour.

## Persistence & I/O

Op-log goldens only.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Pin circle and single-bit pill | `nsPinCircle`, `nsValuePill`, `drawInputPin`, `drawOutputPin` for width 1. | Cases: HIGH → one filled `arc` at `r`; LOW → `fillStyle = surface` then stroke at `lw × 1.2`; undefined → `setLineDash` then `setLineDash([])`; pill `roundRect` height `0.92 cell` with bottom at `cy − r − 0.5 cell`; name `fillText` at `(cx, cy + 0.03 cell)`. |
| 2 | The bus pill through `busValue` | `busValue` hook, pins skip their own pill at width > 1. | Cases at width 8: the pin skin's log has no `roundRect`; the hook's log has one, fill `wireBus`, `fillText(text)` with the hook's `text` verbatim (a `'0b…'` string proves the format is the canvas's); `rom`/`ram` components produce an empty log. |
| 3 | The ring policy | `highlight` dispatching on kind; `nsHoverRing`; pin skins ignore `hovered`. | `circ-theme-hover.test.ts` rewritten: circle `arc(cx, cy, r + 0.38 cell)` for pins, `roundRect` for a gate; skins never call either helper; no `inputHover` read in any skin body. |
| 4 | LED | `drawLed` with halo, hollow LOW, dashed undefined. | Cases: HIGH → `drawImage` of a cached offscreen then `arc` fill `outputOn`; LOW → `surface` fill, `outputBorderOff` stroke, core `arc` at `r × 0.3`; undefined → dashed `labelMuted`. Cache key format asserted. |
| 5 | Islands: gutter and padding | `LiveCanvas.astro`, `Playground.astro`. | Source guard in `circ-skins.test.ts` (or a new `island-canvas-options.test.ts`): both islands pass `rowGutter: 2` and `padding: Math.ceil(cell * 1.5)`; `bun --bun run build` green; the human reviews `hero-half-adder`, `wide-not`, `two-bit-adder` at the three cell sizes and both modes. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `a pin's shape says its state` | `circ-skins.test.ts` | Fill/stroke/dash sequence per signal as in slice 1. |
| `the single-bit pill sits clear of the ring` | same | Pill bottom `≤ cy − r − 0.5 cell`; ring radius `r + 0.38 cell` leaves `≥ 0.1 cell` between ring and pill. |
| `a bus pill is the canvas's text` | same | `fillText` argument equals the `text` passed to `busValue`. |
| `memories get no pill` | same | `busValue` log empty for `Rom`/`Ram`. |
| `the ring is a circle for pins and a rectangle otherwise` | `circ-theme-hover.test.ts` | Op shapes per kind. |
| `no skin reads hovered for its fill` | same | Source guard over skin bodies. |
| `the LED halo is cached once per size and colour` | `circ-skins.test.ts` | Two draws at the same cell produce one `offscreen` call. |
| `islands pass the gutter and the padding` | `island-canvas-options.test.ts` | Regex over both `.astro` sources. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `bun --bun run build` + `bun run bundle` | site | Green, no ceiling raised. |

Run command: `cd site && bun test && bun --bun run typecheck && bun --bun run build && bun run bundle`.

## Open Questions / Spikes

- `TODO(phase2)`: the playground's memory panel and source-link highlight (`setHighlight`) mark `rom`/`ram` boxes with the rectangle; confirm in slice 3 that a highlighted memory still shows a ring after the kind dispatch (the test covers a gate, the human checks a memory in the review).
- `TODO(phase2)`: `LiveCanvas` cards that set an explicit `padding` prop (grep `padding=` in `site/src/pages` and `site/src/content` at slice 5) keep their value only if it is ≥ `1.5 cell`; otherwise raise it and say so in STATUS.
