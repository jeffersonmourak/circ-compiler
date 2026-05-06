# Plan Prompt — ASCII Circuit Preview (`circ-compile preview`)

## What Is Being Built

A new CLI subcommand, `circ-compile preview <foo.circ>`, that renders a digital circuit as a styled ASCII schematic to stdout. The renderer compiles the `.circ` source in memory through the existing parse → IR → emit pipeline, decodes a new versioned topology payload embedded in the compiled WebAssembly artifact, lays out the gate graph deterministically on a character grid, and draws it with schematic-style line art (`╭╮╰╯─│●` junctions, per-kind gate glyphs) and optional ANSI color.

The motivation is to give users a fast, dependency-free way to *see* what they just compiled — closing the loop between source and behaviour without leaving the terminal. The output is designed to evoke a hand-drawn schematic rather than a debug box-and-arrow diagram, so the diagram is useful for code review, documentation, and teaching.

The observable definition of done: for every compilable `.circ` file in the test suite, `circ-compile preview <file>` produces a deterministic, byte-stable ASCII rendering of the circuit's gate graph, with macros shown as opaque labeled blocks by default and as their full expansion under `--expand-macros`. ANSI color is gated behind `--color=auto|always|never` (auto = isatty + `NO_COLOR` respect). Layer 1 (`lib/circuit.zig`) and the runtime WASM ABI are not modified.

## Tech Stack

- **Language:** Zig (matches the rest of the project; no new languages introduced).
- **Build system:** `build.zig` — the renderer extends the existing `compiler` target rather than adding a new binary.
- **Entry point:** `cmd/circ-compile/` — new `preview` subcommand alongside the existing `-o`, `--emit-zig`, `--inspect` modes.
- **Compilation path:** in-memory only — parse via `lib/syntax/`, resolve via `lib/ir/`, emit via `lib/emit/`, decode the topology payload directly from the resulting bytes. No temp files, no subprocess.
- **Topology serialization:** WASM custom section(s) — `circ.topology.v0.min` (rename of today's `topology_blob` placeholder; content unchanged) and `circ.topology.v0.full` (new payload introduced by this initiative).
- **Test runner:** `zig build test` (existing).
- **Deployment target:** native CLI binary, same as the current `circ-compile`.
- **Runtime dependencies:** none added. Pure Zig, hand-rolled section parser, hand-rolled layout, hand-rolled glyph renderer.

## Architectural Constraints

- **Layer 1 (`lib/circuit.zig`) is untouched.** The simulation engine knows nothing about rendering. The renderer is a CLI-side consumer of the topology payload, not a runtime feature.
- **Runtime WASM ABI is untouched.** No new exports, no new imports, no new callbacks across the JS boundary. The browser keeps loading the same eight exports it loads today.
- **Strategy 3 — custom-section topology.** The compiled `.wasm` carries its own renderable description as a WASM custom section. Readers parse bytes; they do not instantiate the module. See `DOCS/architecture.md` for the layered model this preserves.
- **Pre-1.0 Zig philosophy: schemas are freely revvable.** Bump `circ.topology.vN.{min,full}` rather than carrying compatibility shims, dual decoders, or migration code. The version *number* moves only when a payload's shape changes incompatibly; the variant suffix (`min` / `full`) is the experimentation surface within a version.
- **`min` and `full` are independent payloads on one version axis.** `min` is a stable "this is a circ-compiled wasm" marker (today's `topology_blob`, label-renamed only). `full` is the rendering-grade payload introduced by this initiative.
- **Macro provenance is a schema-level concern.** `circ.topology.v0.full` carries, per component, an optional macro-origin chain (instance name + macro kind + nesting depth) so the renderer can collapse expanded gates back into their source macro. Without this, opaque-mode rendering is impossible.
- **The IR→section serializer is the only place that depends on IR shape.** All downstream code (reader, layout, renderer, tests) consumes the decoded section, never the IR directly. This isolates the upcoming langlang upgrade's blast radius (see Recurring Traps).
- **No heavy dependencies.** No Graphviz, no ELK, no third-party WASM runtimes, no layout libraries. Section parsing and layout are hand-rolled in Zig.
- **Determinism.** A given `.circ` file must render byte-identically on every run. Emit-order index from the topology payload is the universal tie-breaker for layout decisions.
- **CLI shape.** New `preview` subcommand on the existing `circ-compile` binary, matching the explicit-flag style established in `DOCS/decisions/cli.md`. No magic-extension dispatch.

## Phase Index

| Phase | Name | What Ships |
|-------|------|-----------|
| 0 | Topology serialization | `circ.topology` renamed to `circ.topology.v0.min` (content unchanged); `circ.topology.v0.full` schema designed and emitted from `lib/emit/` with macro-provenance chains; hand-rolled WASM custom-section reader; round-trip test (emit → decode → compare to IR semantics) green. |
| 1 | Preview subcommand skeleton | `circ-compile preview <foo.circ>` parses, runs the in-memory pipeline, decodes `v0.full`, and prints a textual `(id, kind, name, macro-origin, edges)` debug dump. End-to-end data path proven; no graphics yet. |
| 2 | Layout pass | Typed `LayoutGrid` data structure produced from a decoded payload via: longest-path column assignment, barycenter-method row assignment (two sweeps), per-kind cell sizing, port-coordinate resolution, interval-greedy channel routing for orthogonal wires. Two render modes: opaque (default — macro-origin groups collapsed to single virtual nodes) and expanded (`--expand-macros`). Tested via grid-coordinate assertions, no glyphs yet. |
| 3 | ASCII rendering + color | Per-kind gate glyphs, `╭╮╰╯─│●` junction line art, crossing rendering (jump arcs over `┼`), ANSI styling via `--color=auto\|always\|never` (auto = isatty + `NO_COLOR` respect), golden-file tests covering: single gate, fan-out, fan-in, opaque `xor` macro, same with `--expand-macros`, nested macros, multi-LED. |

Phases are ordered by dependency, not by priority. Each phase must be fully shippable before the next begins.

## Working Loop

The execution agent follows this loop every session without exception:

### On Cold Start

1. Read this file (`DOCS/PLANS_PROMPT.md`) in full.
2. Read `DOCS/STATUS.md` (if it exists). The latest entry defines what was last shipped and what comes next.
3. Run `git log --oneline -10` and `git status`. If STATUS claims a slice is committed but it does not appear in `git log`, the human has not committed yet — **do not begin a new slice**. Stop and say so.
4. Read the active phase plan (`DOCS/PLANS/PHASE_<N>_<name>.md`) for the current phase.
5. Implement the next slice per the phase plan. Do not start a second slice until the first is reviewed and committed.

### Each Slice

1. Implement the full slice as specified. Do not stop mid-slice.
2. Run the project's test command for the affected modules. Do not ship a slice that breaks the suite.
3. Append a STATUS entry (template below).
4. Stage the slice's files (`git add <files>`).
5. Display the proposed commit message and **stop**. Wait for explicit human approval before running `git commit`. Do not begin the next slice until the commit is confirmed and made.

### Git Rules

- Read-only git commands (`status`, `log`, `diff`) are encouraged for situational awareness.
- **Committing:** At the end of a slice — and only at the end of a slice — the agent stages the slice's files (`git add <files>`), then displays the full proposed commit message to the human and waits for explicit approval before running `git commit`. Staging first lets the human inspect the diff in any git client before approving. Do not commit without that confirmation.
- Do **not** push, force-push, amend, rebase, reset, delete branches, or run any other write `git` or `gh` command under any circumstances.

## STATUS Entry Template

Append to `DOCS/STATUS.md` at the end of every slice. Never overwrite or edit prior entries.

```
## YYYY-MM-DD — Phase N — <slice title>

**What shipped:** <one or two sentences>
**Files touched:** `<file>`, `<file>`
**Tests:** added <names>, ran `<command>`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

## Recurring Traps

- **Pending langlang upgrade may shift the IR.** `lib/parser.c` / `lib/parser.h` are auto-generated by langlang and feed `lib/syntax/CParser.zig` → `lib/syntax/translate.zig` → `lib/ir/`. A grammar/runtime-side bump can change which IR nodes appear or how they are named. Before starting Phase 0, run `git log -- lib/parser.c lib/parser.h lib/syntax/` and check for recent langlang-related commits or in-flight branches; if an upgrade is imminent, prefer landing it *before* Phase 0 to avoid retargeting golden artifacts twice. Mitigation in design: the `v0.full` schema is defined against IR *semantic content* (gate kinds, names, connections, macro provenance), not IR field names. The IR→section serializer is the single rewrite point if the IR shifts.
- **`circ.topology.v0.min` content is unchanged.** Phase 0's slim slice is a label rename only. Today's placeholder bytes (`"debug-paths-v1"`) stay as-is. Do not "improve" `min` while you are in there — its job is to be a stable marker, not a payload.
- **Macros nest.** `xnor` expands through `xor` which expands through `or`. The macro-origin chain in `v0.full` must be a list of frames per component, not a single field. Phase 2 opaque-mode collapses by the *outermost* frame; deeper frames are surfaced only under `--expand-macros`.
- **Wires are not nodes.** The `wire` component is a runtime pass-through; in the rendered diagram it is the line, not a box. Layout collapses wires into the edges they represent; do not assign them columns.
- **Determinism is contractual.** Every layout decision needs a stable tie-breaker, anchored on the topology payload's emit order. Avoid hash-map iteration as a tie-breaker — Zig hash-map order is not stable across versions.
- **`min` / `full` are not a hierarchy.** They are independent custom sections under one version axis. A reader picks the variant it understands. Both can coexist in the same artifact. Do not introduce inheritance, fallback, or "promote min to full" logic.
- **No WASM runtime in the CLI.** Topology decoding parses `.wasm` bytes for custom-section headers (preamble + LEB128 + section ID loop). It never instantiates the module. Resist the temptation to "just call `init()` and read state" — that path was rejected (Strategy 1) precisely because it requires embedding a runtime.
- **Renderer's `+` fallback glyph (post-Phase-3).** `lib/preview/render.zig:pickCornerGlyph` returns `"+"` when a corner cell connects to ≥3 directions (the 2-direction logic doesn't pick a T-glyph). This fires occasionally in real layouts at fan-out junctions and 3-way joins — visible in `tests/fixtures/circuits/fan_in.render.golden`. Fix is to detect the per-cell direction set across all wires and pick from `┤`/`┬`/`┴`/`├` for 3 directions and `┼` for 4. Out of Phase 3's scope; flagged as a future cleanup. The current goldens lock the present behaviour, so any improvement produces a reviewable golden diff.
- **Compile mode and builtin-macro single-file fixtures (post-Phase-1).** The dispatch gate at `cmd/circ-compile/main.zig` uses `has_imports` (explicit imports only) for compile/emit_zig modes. Single-file `.circ` sources that use builtin macros (`xor`, `xnor`, etc.) without an explicit `import` statement go through the single-module path, where the resolver may emit unresolved-name errors. Preview mode was widened in Phase 1 slice 4 to always go through the project pipeline; compile/emit_zig were left unchanged to preserve the perf-budget test on the 100-component grid. A latent bug — flagged for future cleanup if a fixture exposes it.
