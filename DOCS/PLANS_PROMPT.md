# Implementation entry-point

You are continuing the implementation of the `.circ` compiler for `circ-compiler` — a Zig CLI that consumes a `.circ` source file and produces a self-contained `.wasm` artifact simulating that specific circuit. Most of the planning is done. Your job is to pick up where the codebase is, finish the next reviewable slice, and stop for human review.

## What is being built

A Zig-based compiler that parses `.circ` source, validates it semantically, lowers it to a Zig intermediate representation (one `buildXxx` function per source file), and orchestrates `zig build` as a subprocess to produce a `.wasm` artifact. The artifact embeds the simulation engine plus circuit-specific construction code, exposes a fixed runtime API (`init`, `run`, `reset`, `setPin`, `getOutputState`, introspection, file info), and runs anywhere WebAssembly is supported.

Authoritative architecture: `DOCS/architecture.md`.
Authoritative compiler decisions: `DOCS/decisions/` (start with `index.md`).
Authoritative surface syntax: `DOCS/circuit-format.md`.
Authoritative runtime contract: `DOCS/simulation-engine.md` and `DOCS/wasm-api.md`.
If this prompt or a phase plan disagrees with those, the spec wins. Update the plan, not the spec.

## Read in this order on a cold start

1. `DOCS/architecture.md` — the layered view of the existing engine, WASM glue, and SDK.
2. `DOCS/decisions/index.md`, then every topic file under `DOCS/decisions/` — why each compiler choice was made.
3. `DOCS/circuit-format.md` — the language being compiled.
4. `DOCS/simulation-engine.md` — the runtime contract the emitter targets.
5. `DOCS/wasm-api.md` — the existing dynamic-API runtime, for context only. The compiled artifact does not inherit its callback-based shape; it is pull-based.
6. `DOCS/STATUS.md` — the rolling session log. The latest entry tells you where the previous session stopped and what the next slice should be. If this file does not exist yet, you are the first session — create it.
7. `DOCS/PLANS/PHASE_<N>_*.md` for the active phase only. If the active phase's plan does not exist yet, your first slice is to write it.

## Architectural anchors (do not break)

1. Compiled artifacts are fixed at compile time. No runtime topology mutation.
2. The simulation engine in `lib/circuit.zig` knows nothing about source files, hierarchy, or compilation. Source-path debug info lives outside the engine, exposed only by compiled artifacts.
3. langlang and Zig are the only build-time dependencies. Generated parser sources (`lib/parser.c`, `lib/parser.h`) are vendored in the repo. Day-to-day contributors do not need langlang installed.
4. The CLI binary is self-contained — runtime sources are embedded via `@embedFile` at the CLI's own build time and written to a temp directory at circuit-compile time.
5. Hard errors block emission. Partial or "best-effort" artifacts are never produced.
6. Each `.circ` file emits exactly one `buildXxx` function. Sub-circuit instances become call sites of these functions, never specialised per-instance emissions.

## Engineering rules

1. TDD: every phase ships with tests proving its slice. Failing builds do not ship. `zig build test` is the bar.
2. Golden-file fixtures live under `tests/fixtures/` organised by *artifact kind* (`tests/fixtures/circuits/`, `tests/fixtures/expected-zig/`, `tests/fixtures/expected-wasm/`), not by phase. The same `.circ` source may be referenced by multiple phases.
3. Every AST node carries a `Span` for diagnostics. No node without position info.
4. Diagnostics use stable codes (`E001`, `W001`, …). Tests assert on codes; the CLI formats messages. Code-to-message mapping is stable across versions.
5. Validation is multi-pass and accumulates all diagnostics in one run. Each pass is individually testable. Passes downstream of name resolution must be resilient to upstream failures (do not crash on unresolved references — skip the dependent check).
6. No allocations outside the project's arena allocator. The engine and compiler use the same allocation discipline.
7. Built-ins (`or`, `nand`, `nor`, `xor`, `xnor`) go through the same parse / validate / emit pipeline as user code. No special-case code paths in the resolver, validator, or emitter — built-ins live in a virtual `<builtin>/` filesystem mounted via `@embedFile`.
8. Hand-rolled CLI argument parser — no third-party arg-parsing dependency.

## Phase index

| Phase | Delivers |
|-------|----------|
| 0     | Project scaffolding: golden-file test helper (`std.testing` + helper, supports `--update-goldens`), `tests/fixtures/` layout, build target wiring. |
| 1     | Engine baseline: `output_pin` primitive (pass-through, both `in` and `out` ports) + tests for `output_pin`. Existing primitives are not retroactively backfilled in this phase. |
| 2     | Parser & AST/IR: typed AST with one type per syntactic construct, parser-driven from the langlang C parser, plus a separate resolution pass that produces the resolved IR consumed by later phases. Every node carries a `Span`. |
| 3     | Semantic validation: multi-pass validator (name resolution, port checks, multi-driver detection, combinational-loop detection, dead-code warnings) accumulating all diagnostics with stable codes. Diagnostics formatted as `<file>:<line>:<col>: <level>: <message>`. |
| 4     | IR → Zig source emission for single-file circuits, including all 11 runtime exports (`init`, `deinit`, `reset`, `run`, `stop`, `setPin`, `getOutputState`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer`). String-templated emission. Golden-Zig comparison tests *and* behavioural tests via `node` running the compiled `.wasm`. |
| 5     | Build orchestration: `@embedFile`-vendored runtime template (engine + `build.zig` + WASM entry point), temp dir layout (`/tmp/circ-compile-<rand>/` default, `--build-dir` override), `zig build` subprocess with stderr streamed verbatim under a header, output copying. End-to-end tests + unit tests for orchestration helpers. |
| 6     | CLI surface: hand-rolled arg parser, three modes (`-o <file>`, `--emit-zig`, `--inspect`), plus `--warnings-as-errors` and `--build-dir`. Binary name `circ-compile`, entry point at `cmd/circ-compile/main.zig`. `--inspect` output uses textual sections (`=== Parse Tree ===`, `=== Resolved IR ===`, `=== Diagnostics ===`) in pretty-printed Zig style. Unit tests for arg parsing + integration tests per mode. |
| 7     | Sub-circuit support: two-phase resolution (scan-then-parse), per-file IR + resolution table, import cycle detection in the resolver (separate from Phase 3's combinational-loop check). Comprehensive fixtures: two-file, diamond, deep-chain, name-overlap. |
| 8     | Built-in macro library: `or`, `nand`, `nor`, `xor`, `xnor` shipped as `.circ` source files embedded in the CLI binary, mounted at virtual `<builtin>/`, resolved via implicit auto-import. Macros may compose (`nor` reuses `or`). Truth-table tests per macro + composition tests (e.g. full adder from `xor` + `or`). |
| 9     | Integration test suite hardening: stress fixtures (~100+ components), edge cases (empty, single-component, deeply nested anonymous), regression fixtures from earlier-phase bugs, diagnostic snapshot tests for every error/warning code, canonical full-pipeline fixtures (half-adder, full-adder, ripple counter). Smoke perf test (compile budget for 100-component circuit). README + getting-started doc. |

## Working loop

For each session:

1. Read `DOCS/STATUS.md`. The latest entry says what was last shipped and what comes next. If the file does not exist, you are the first session — your first slice is to create `DOCS/STATUS.md` and the active phase plan under `DOCS/PLANS/`.
2. Run `git status` and `git log --oneline -10`. If `STATUS.md` claims a slice is committed but `git log` doesn't show it, the human hasn't committed yet — don't start a new slice on top.
3. Read the active phase plan under `DOCS/PLANS/PHASE_<N>_*.md`.
4. Implement the smallest reviewable next slice. TDD: write failing tests first when the shape allows, then implement to green.
5. Run `zig build test` for touched packages. Don't ship work that breaks the suite.
6. Append a STATUS entry (template below). Stop. Wait for human approval and commit.

You do not commit, push, or run any write `git` or `gh` command. Read-only `git` is fine.

## STATUS entry template

Append to `DOCS/STATUS.md` at the end of each session:

```
## YYYY-MM-DD — Phase N — <slice title>

**What shipped:** <one or two sentences>
**Files touched:** `<file>`, `<file>`, `<file>`
**Tests:** added <names>, ran `zig build test`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

The human commits this file along with the slice. Do not overwrite or edit previous entries.

## Recurring traps

- **Wires don't break combinational loops — only gates do.** Don't conflate "delay" (every component has one) with "breaks combinational cycles" (only gates qualify). A chain of wires looping back is still a combinational loop and a hard error.
- **The compiled artifact is pull-based.** No `onStateChange` FFI callback. Do not import the dynamic-API pattern from `lib/wasm.zig` into the compiled-artifact runtime entry point.
- **`output_pin` is a pass-through component, not a sink.** It has both `in` and `out` ports and behaves like a named wire in the parent's connection graph.
- **Component IDs are stable per artifact but not across compilations.** They're emitter-assigned, not derived from the source. Do not surface them as user-facing identifiers in any context where source stability matters.
- **LEDs and `output` declarations are different concepts.** LEDs are visualisation primitives; `output` declarations define the public interface of a sub-circuit. `getFileInfo()` lists them in separate categories.
- **Multi-driver on the same input port is a hard error in v0.** There is no implicit wired-OR. The dynamic engine in `lib/circuit.zig` has bus-resolution logic; the compiler refuses to emit such circuits.
- **Built-ins live at `<builtin>/` in a virtual filesystem.** Importing a built-in goes through the normal import resolver path, not a special-case branch. The resolver does not know that `<builtin>/and.circ` came from `@embedFile`.
- **`--build-dir` preserves on success;** the default temp dir cleans on success but preserves on failure. Do not invert this — users debugging a successful build with weird output need the dir, and users debugging a failure need it too.
- **FSMv2-style mistakes do not apply here** — this project has no FSM. Do not import patterns from other Zig+state-machine projects.
- **Import cycles and combinational cycles are different graphs.** Import-cycle detection lives in Phase 7 (the import resolver). Combinational-loop detection lives in Phase 3 (the connection-graph validator). Do not merge them.

## What this file is not

- Not a phase plan. It does not enumerate types, files, or tests. Each phase plan lives under `DOCS/PLANS/PHASE_<N>_*.md` and is written by the agent at the start of that phase.
- Not a duplicate of `architecture.md` or `decisions/`.
- Not authorization for commits, pushes, or destructive git actions.

Every phase, and every slice within a phase, is approved and committed by a human. Stop at the STATUS entry; do not commit on the human's behalf.
