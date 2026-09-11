repo: jeffersonmourak/circ-compiler
branch: main
path: site/src/utils

## Last sync

date: 2026-09-11T11:20:11Z

### Updated in this project

- Footer signature (Made with ♥︎ by @jeffersonmourak) reused from site/src/components/Footer.astro in every bench status bar

- Added 3e Schematic (--preview text on --code-bg, strict mono) and 3f Truth (live row tinted, cap as a toolbar chip) bench states

- Added 3d: the Hack ALU (8 inputs, 3 outputs) as user subcircuits, with the pin rail redesigned as a strip for many pins

- Added 3a/3b/3c bench states (workspace switcher, 2-bit adder, console + memory drawer) from console.ts, memory-panel.ts and the .pg-mem rules

- Added proposal 2a (canvas-first bench) to `Playground Upgrade.dc.html`; both proposals now show real circ grammar from site/src/content/tour.ts and a matching `nandScene`

- Mapped the playground page (workspace, editor + dock, output tabs, session drawer, status bar, splitters) and proposed a visual upgrade on CircDS tokens in `Playground Upgrade.dc.html`

- Proposed ROM and RAM assets (§11) from circ-compiler PR #79 (branch `memories`, head 2e15e97): footprints from memorySize, ports addr / addr·din·we·clk, addressed word in the body, write indicator on RAM
- Proposed subcircuit assets (§10): builtin macros reuse the gate recipe; user subcircuits get a header-band chip

- Reviewed extraction + proposal against circ-theme.mjs, LiveCanvas.astro, skins.ts, canvas.ts, theme.ts; fixed six proposal defects (rounded corners with crossings, transparent fan-out knock-out, blur-free halo, slice signal response, tint cache, proposed palette documented)

- Asset sheet built on the site's custom circ-renderer theme, ported verbatim from circ-theme.mjs
- Gate sprites copied from circ-assets.mjs rather than redrawn
- Nine documented gaps, including buses losing their color and idle wires out-shouting active ones
- A proposed upgrade to the site assets that keeps its language: tinted signal-aware sprites, skinned slice/concat, a real bus treatment, cell-relative strokes
- Proposed the missing ANSI gate set — BUFFER, OR, NAND, NOR, XOR, XNOR — composing NOR/XNOR from existing sprites plus an inversion bubble

## Screen map

| Screen | Repo files |
|---|---|
| Playground Upgrade.dc.html — 01 map | circ-compiler: site/src/components/Playground.astro, site/src/styles/global.css (.pg-* 546–1340, 1677–2074), site/src/scripts/pipeline.ts, settings-drawer.ts, ws-tree.ts, console.ts, memory-panel.ts |
| Playground Upgrade.dc.html — 3e schematic · 3f truth | circ-compiler: site/src/components/Playground.astro (runPreview, runTruth, input-bit cap), site/src/styles/global.css (.pg-table, .pg-preview) |
| Playground Upgrade.dc.html — 3c console + memory | circ-compiler: site/src/scripts/console.ts (helpLines, promptEcho), site/src/scripts/memory-panel.ts (formatWord, formatAddress, dumpRows), site/src/styles/global.css (.pg-mem-*) |
| Playground Upgrade.dc.html — 3a switcher · 3b adder | circ-compiler: site/src/components/Playground.astro (ws tree, diagnostics), site/src/content/tour.ts (grammar) |
| Playground Upgrade.dc.html — 2a bench · 1a headers (editor source) | circ-compiler: site/src/content/tour.ts |
| Playground Upgrade.dc.html — 1a proposed workbench | circ-compiler: site/src/components/Playground.astro (markup), site/src/styles/global.css (tokens); this project: circ-site-theme.js (site-next canvas) |
| Circ Renderer Assets - Site Theme.dc.html — 01 Color tokens | circ-compiler: site/src/utils/circ-theme.mjs |
| Circ Renderer Assets - Site Theme.dc.html — 02 Components | circ-compiler: site/src/utils/circ-theme.mjs, site/src/utils/circ-assets.mjs |
| Circ Renderer Assets - Site Theme.dc.html — 03 Wires, tails & marks | circ-compiler: site/src/utils/circ-theme.mjs |
| Circ Renderer Assets - Site Theme.dc.html — 04 Geometry | circ-compiler: site/src/components/LiveCanvas.astro, site/src/utils/circ-theme.mjs |
| Circ Renderer Assets - Site Theme.dc.html — 05 Demo circuit | circ-compiler: site/src/utils/circ-theme.mjs; circ-renderer: src/layout/place.ts |
| Circ Renderer Assets - Site Theme.dc.html — 06/07 Gaps + upgrade | circ-compiler: site/src/utils/circ-theme.mjs (analysis; upgrade is new design) |
| Circ Renderer Assets - Site Theme.dc.html — 08 Gate set | circ-compiler: site/src/utils/circ-assets.mjs (sprites); circ-renderer: src/wasm/topology.ts, src/layout/sizing.ts, src/layout/place.ts |
| circ-site-theme.js (verbatim port) | circ-compiler: site/src/utils/circ-theme.mjs |
| site/src/utils/circ-assets.mjs (copied as-is) | circ-compiler: site/src/utils/circ-assets.mjs |
| Circ Renderer Assets.dc.html — 01 Color tokens | circ-renderer: src/utils/theme.ts, README.md |
| Circ Renderer Assets.dc.html — 02 Components | circ-renderer: src/render/skins.ts, src/layout/types.ts, src/wasm/topology.ts |
| Circ Renderer Assets.dc.html — 03 Wires, ports & marks | circ-renderer: src/render/canvas.ts |
| Circ Renderer Assets.dc.html — 04 Geometry | circ-renderer: src/layout/sizing.ts, src/layout/place.ts |
| Circ Renderer Assets.dc.html — 05 Demo circuit | circ-renderer: src/layout/place.ts, src/render/canvas.ts, src/render/skins.ts |
| circ-skins.js (verbatim port) | circ-renderer: src/render/skins.ts, src/render/canvas.ts, src/utils/theme.ts |
| circ-scenes.js (layout fixtures) | circ-renderer: src/layout/sizing.ts, src/layout/place.ts |

## Additional sources

repo: jeffersonmourak/circ-renderer
branch: main
path: src
note: the library both sheets recreate; circ-compiler/site consumes it with a custom theme

## Sync history

- 2026-09-10T01:38:13Z — jeffersonmourak/circ-renderer@main — initial asset extraction from src/render, src/utils, src/layout
