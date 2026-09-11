# Archived plan: home-page

**Canonical commit:** `b6e341466f178a110882599c251813c76e3915e4` (`b6e3414 feat(site): redesign the playground as a canvas-first workbench (#86)`)
**Archived on:** 2026-09-11
**Plan duration:** 2026-09-11 → 2026-09-11

> This file is a highlight view. The full plan prompt, every phase plan, every STATUS entry and the deleted design handoff are preserved in the canonical commit. Read the full prompt with `git show b6e341466f178a110882599c251813c76e3915e4:DOCS/PLANS_PROMPT.md`; the handoff is under `DOCS/design/design_handoff_home_page/` in that same tree.

## Goal & scope

Redraw the landing page around a live half-adder, followed by a compact language card, the `--preview` figure, three gallery thumbnails and an install section. Reuse the existing Astro site, renderer lifecycle, token palette, example artifacts and Markdown-mirror build. The compiler and renderer package remain unchanged; `circ-renderer` stays pinned at `2d973b4` (`2.3.0-alpha.4`). The home-page work shared PR #86 with the preceding playground-bench initiative. Its squash merge is the canonical state; the branch-local commit IDs in STATUS are historical references, not separate commits on main.

## Phase-by-phase highlights

### Phase 0 — Handoff and hero

Lead with a usable simulation and its source rather than a static figure.

- Track the trimmed design handoff and plan bundle; remove 32 unused TTFs and a stale asset copy.
- Add `pin-line.ts`: `rootPins`, `pinLineParts` and `pinLine`, with kind values injected from the lazy renderer.
- Extend `LiveCanvas.astro` with optional source, values, label, link and parent-fit surfaces.
- Add the headline, calls and download chip; use an `OpenInPlayground` slot for the checked hero link.
- Correct inherited pre styles, doubled source-line spacing, compounded padding and a collapsed narrow canvas after browser review.

The initial structural tests did not establish visual fidelity, so browser review and basic stacking moved forward from Phase 3. The required handoff/plan bundle exceeded the estimated 400 KB after trimming. Gallery attributes and child order are guarded; literal HTML byte identity was not established.

### Phase 1 — Language and preview

Replace three prose sections with vocabulary and a compile/run pipeline; restore the schematic in its own section.

- Four vocabulary rows and three numbered steps replace `.landing-prose`.
- Correct illustrative syntax to `a[0..2]` and `import adder "adder.circ"`.
- Frame the existing `CodePreview` with heading, lede, checked link and status row.
- Rewrite `emitLandingTwin` and `llms.txt`; test matching page/twin headings.
- Restore strict monospace sizing and constrain preview panes so long lines scroll locally.

The user widened main to 1500px, reordered and right-aligned navigation, and retained the two-panel preview presentation. These reviewed changes supersede the original board geometry.

### Phase 2 — Gallery tiles

Show three shipped examples through deferred, fixed-cell thumbnails.

- Add `tile-meta.ts` tests for pin counts, binding commas, memory capacity and unsupported source shapes.
- Select `two-bit-adder`, `four-bit-adder` and `rom-lookup`; fail the build if an artifact is absent.
- Load the ROM's source-owned image through the shared `applyMemory` path.
- Draw native-width canvases at cells 5/6/6 inside 150px slots, without pin interaction or navigation.
- Use one anchor per tile and an inert loading span; update the Markdown twin.

The user chose separate cards with 2rem gaps, individual borders and hover feedback. The planned nested button became a span to avoid interactive content inside a link. Short circuits center vertically; oversized circuits crop from the top. Markdown links omit fragments because title-derived anchors differ from HTML slugs.

### Phase 3 — Install, responsive layout and record

Finish the install surface, verify the page and record the design decisions.

- Add the install heading, platform/license line and full-width download row.
- Stack the install row below 800px and guard home-page selector scopes.
- Preserve the user's removal of lineage and remove it from the Markdown twin.
- Capture the production build at 1100/1440/700px in both themes; verify pin toggles and deferred native-size thumbnails.
- Complete `DOCS/decisions/home-page.md` and its map of all fifteen locked decisions.

The final phase recorded 629 passing site tests; typecheck had zero errors and warnings, with 21 existing hints. Build, bundle and `zig build test-all` passed. After lineage removal, a fresh build and 51 relevant tests passed. Browser checks used a locally served production build rather than the planned dev server. A navigation timeout in an earlier verification run was followed by a completed run without runtime exceptions.

### Final review and merge

- New playground users start in Live, including initial markup; saved view choices and legacy migrations retain their behavior.
- An Elements of Style review made the pipeline parallel, replaced vague capability claims, and shortened the preview and gallery descriptions in both HTML and Markdown.
- The approved copy and default-view changes were tested and merged with PR #86.

The landing and gallery eager JavaScript graphs grew from 3,869 B raw / 2,006 B gzip before the initiative to 5,354 B / 2,660 B. The 10,240 B gzip ceiling was not raised. Archive cleanup happened on main after the merge at the user's request; `DOCS/design/` and the active plan files were deleted rather than moved.

## API surface frozen by the plan

| Surface | Contract |
| --- | --- |
| `LiveCanvas` | Optional `label`, `source`, `values`, `link`, `fit: 'parent'`, `thumbnail`; checked links can occupy `values-link` |
| `rootPins(topology, read, kinds)` | Root inputs then outputs, in group declaration order; no renderer import |
| `pinLine` / `pinLineParts` | Bit digits, formatted buses, `?` for any undefined bit; parts mark names |
| `tileMeta` / `tileMetaLabel` | Single-file declaration counts and one optional memory capacity; file markers and multiple memories rejected |
| `OpenInPlayground` | Optional replacement `class`; catalogue ID validation retained |
| Playground defaults | Fresh state selects Live; valid saved views and legacy migration choices are preserved |
| Compiler/runtime | No CLI flags, diagnostic codes, WASM exports or artifact bytes changed |

## Known papercuts carried forward

- Markdown gallery links deliberately land at the page rather than reader-dependent heading fragments.
- Narrow-screen behavior is usable stacking, not a separate mobile design.
- Browser evidence was saved in session scratch storage, not a committed screenshot suite. Structural tests alone do not establish pixel fidelity.
- The handoff's dimensions and some copy differ from reviewed user changes; use the recorded decisions and canonical source when comparing them.
- Renderer parent fit remains at cell 14 for the hero; thumbnail cells remain 5/6/6. A future renderer change needs fresh checks for cropping and hit testing.

## Decisions & specs that survived the plan

- [Home-page decisions](../decisions/home-page.md): component variants, pin text, metadata, responsive layout and reviewed departures.
- [Playground-bench archive](plan-playground-bench.md): the preceding initiative merged in the same PR.
- `site/test/island-smoke.test.ts`, `site/test/canvas-memory.test.ts`: built-page structure and source-owned memory checks.
- `site/test/pin-line.test.ts`, `site/test/tile-meta.test.ts`: pure formatting and metadata contracts.
- `site/test/bench-tokens.test.ts`, `site/test/app-layout.test.ts`: token and scope guards.
- `site/scripts/build-llm-mirror.ts`: the landing Markdown twin and LLM index descriptions.
- `site/bundle-budget.json`: unchanged per-route JavaScript ceilings.
