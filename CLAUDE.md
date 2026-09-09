# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

`circ-compiler` is a one-shot compiler. It takes a `.circ` digital-logic source (plus any siblings it imports) and emits a self-contained `.wasm` artifact whose exports simulate that exact circuit. The compiler is pure Zig (the parser is `lib/parser/parser.zig`, generated from `lib/grammar/proto-circ.peg` by the maintainer's langlang fork and vendored); it also builds as a library — `zig build libcirc` (`libcirc.a` + `include/libcirc.h`) and `zig build libcirc-wasm` (`libcirc.wasm`, the module behind the site's `/playground`). There is no runtime SDK, no rendering layer, and no JavaScript in the build. Every compiled `.wasm` carries a vendored prebuilt runtime plus two custom sections (`circ.topology.v0.min`, `circ.topology.v0.full`) and exposes a fixed pull-based API: `topology_alloc`, `init`, `run`, `setPin(id, value, defined)`, `getOutputValue(id)`, `getOutputDefined(id)`. The two getters return paired `BitVecState` halves crossed as `i64`/`BigInt`.

## Analysis philosophy

> "Talk is cheap. Show me the code." — Linus Torvalds

When analyzing this codebase, ground every claim in the code. Prefer reading the
actual source and pointing at concrete `file:line` references over describing what
*should* be true in the abstract. When reasoning about engine behavior, propagation,
the topology format, or a diagnostic code, cite the lines that prove it rather than
asserting from memory — and when proposing a change, show the diff (or a minimal
repro/test) instead of narrating it. A proposal backed by the relevant lines beats a
confident summary.

## Toolchain prerequisites

- Zig 0.15.x.
- Node on `PATH` for the behavioral WASM harnesses in `zig build test` (including `tests/e2e/libcirc_wasm_test.zig`).
- langlang is only needed if you regenerate `lib/parser/parser.zig` from `lib/grammar/proto-circ.peg`. circ uses the maintainer's fork, which adds `-output-language zig` on top of upstream `go/v0.0.12`: `go install github.com/jeffersonmourak/langlang/go/cmd/langlang@v0.0.13-zig.2` (branch head: `@zig-parser-gen`; source and docs at https://github.com/jeffersonmourak/langlang, `go/zig/README.md`). Check with `langlang -version` (`Version: v0.0.13-zig.2 (github.com/jeffersonmourak/langlang/go)`); `zig build parser:gen` refuses any other version.

## Build and test commands

| Command | What it does |
| --- | --- |
| `zig build` | Default. Builds the runtime template into `zig-out/lib/circ-runtime.wasm` and installs the CLI. |
| `zig build circ-compile` | Builds the CLI to `zig-out/bin/circ-compile`. |
| `zig build test` | Fast suite (dev-loop default), aggregated from many per-module `addTest` artifacts in `build.zig`. Excludes the slow emit-zig behavioral smoke; circuit behavior on the production path is still fully covered via `tests/e2e/serializer_fixtures_test.zig`. |
| `zig build test-emit` | Emit-zig backend behavioral smoke (`tests/emit/{behavior,project_behavior}_test.zig`). Slow: every fixture spawns a nested `zig build wasm`. Guards the experimental `--emit-zig` pipeline only. |
| `zig build test-all` | `test` + `test-emit`. The full gate CI runs (see `.github/workflows/pr-tests.yml`). |
| `zig build bench` | Engine benchmark over the truth-table fixture corpus, compared against `tests/fixtures/bench/engine.bench.golden`. Counters are asserted; wall-clock is not. |
| `zig build parser:gen` | Regenerates `lib/parser/parser.zig` from `lib/grammar/proto-circ.peg`. Only when the grammar changes; requires the langlang fork (`v0.0.13-zig.2`) on `PATH`, and the step refuses any other version (upstream `go/v0.0.12` fails with `Output language \`zig\` not supported`). |
| `zig build e2e-linux-docker` | Runs `tests/e2e/linux-docker/run.sh`. Requires Docker. |
| `zig build libcirc` | Builds the compiler front end as a static C library: `zig-out/lib/libcirc.a` + `zig-out/include/libcirc.h` (see `DOCS/libcirc-api.md`). |
| `zig build libcirc-smoke` | Compiles `examples/c/analyze.c` against `libcirc.a` and runs it. |
| `zig build libcirc-wasm` | Builds the same C ABI for `wasm32-freestanding`: `zig-out/lib/libcirc.wasm` (ten `circ_*` exports + `memory`; follows `-Dwasm-optimize`). Driven by `tests/e2e/libcirc_wasm_test.zig` through Node. |

Both wasm artifacts (`zig-out/lib/circ-runtime.wasm` and `libcirc.wasm`) are built ReleaseSmall and stripped regardless of `-Doptimize`; `-Dwasm-optimize=Debug` keeps names and DWARF for bisecting.

Useful environment variables:

- `CIRC_SKIP_PERF=1` skips the perf smoke test (use in noisy CI).
- `UPDATE_GOLDENS=1` regenerates fixtures under `tests/fixtures/expected-*/` instead of comparing against them. Diff the result before committing.
- `NO_COLOR=1` strips ANSI from `--preview` output.

There is no `-Dtest-filter` flag wired into `build.zig`. To run a single test module in isolation, invoke `zig test <path>` against its root file (e.g. `zig test tests/validator/run_test.zig`). The `test` step is the fast dev-loop aggregator; `zig build test-all` adds the slow emit-zig smoke (`test-emit`) and is the full gate CI runs.

## CLI shape

`circ-compile` has the following mutually exclusive modes (dispatch lives in `cmd/circ-compile/main.zig`'s `run()`), plus an `--analyze` surface intercepted earlier in `main()` that takes a JSON request on stdin rather than a file path. Only the default mode writes a `.wasm`:

| Invocation | Output |
| --- | --- |
| `circ-compile in.circ -o out.wasm` | Self-contained `.wasm` artifact (default). |
| `circ-compile in.circ --emit-zig -o out.zig` | Standalone Zig source from the experimental emit pipeline (richer but unstable export surface). |
| `circ-compile in.circ --inspect` | Pretty-printed parse tree, resolved IR, diagnostics. |
| `circ-compile in.circ --preview` | ASCII schematic of the resolved circuit. |
| `circ-compile in.circ --truth-table` | Enumerated truth table. Pair with `--format=markdown\|csv\|json`. |
| `circ-compile in.circ --sim` | Interactive stdio drive protocol (proto=1): drive the circuit by pin name for testing/tooling; see `DOCS/sim-protocol.md`. |
| `echo '<json>' \| circ-compile --analyze` | JSON analysis (files, diagnostics, symbols, references) on stdout for editor tooling; see `DOCS/analyze-api.md`. |

Hard errors block emission; partial or "best-effort" artifacts are never produced. `--warnings-as-errors` (alias `-Werror`) promotes warnings.

## Pipeline (every compile takes this path)

```
.circ source
     │
     ▼
[lib/syntax + lib/parser]   langlang-generated Zig parser (lib/parser/parser.zig,
                            vendored; generated from lib/grammar/proto-circ.peg) → Zig AST
     │
     ▼
[lib/resolver]              scan_imports → import_cycle → resolve_bodies.
                            Auto-imports virtual <builtin>/ macros
                            (or, nand, nor, xor, xnor) for projects.
     │
     ▼
[lib/ir]                    Resolved IR (Module, Project, Component, Pin).
     │
     ▼
[lib/validator]             Stable diagnostic codes E001-E016, W001-W003.
                            Single-module: run.zig. Whole-project: run_project.zig.
     │
     ▼
[lib/topology]              serializer.zig       → circ.topology.v0.min  (runtime)
                            full_serializer.zig  → circ.topology.v0.full (tooling)
     │
     ▼
[lib/topology/section_writer.zig]
                            combineTwo() splices both sections into the
                            vendored prebuilt runtime WASM.
     │
     ▼
final .wasm  (no zig subprocess on the user's machine)
```

Two invariants the rest of the codebase leans on:

- **Sub-circuits are fully flattened at runtime.** The `.min` blob is a flat ordered list of primitive components and connections; there is no hierarchy at runtime. The `.full` blob carries per-file IDs, port names, aliases, and macro provenance for tooling that needs human-readable structure.
- **The runtime is prebuilt and embedded.** `templates/main.zig` and `templates/interpreter.zig` are compiled once into `zig-out/lib/circ-runtime.wasm`, then `@embedFile`-d into the CLI as `runtime_embed`. End users never need a Zig toolchain at runtime.

## Simulation engine (`lib/circuit.zig`)

The engine is pure Zig, oblivious to WebAssembly, JSON, or the topology format. It models a circuit as a directed graph of `Component`s and advances time with a min-heap event queue. The compiled `.wasm` runtime and the unit tests are both clients of the same `Circuit` API.

Eight component kinds (`ComponentType`): `input_pin_gate`, `not_gate`, `and_gate`, `wire`, `output_pin`, `led`, `slice`, `concat`. Their integer encoding in the topology format is fixed: `input_pin_gate=0`, `not_gate=1`, `led=2`, `and_gate=3`, `wire=4`, `output_pin=5`, `slice=6`, `concat=7`. Do not renumber. `slice` and `concat` are bit-shape kinds — the resolver lowers `a[lo..hi]`, `a[i]`, and `{a, b, ...}` into them; users never write them directly.

Facts that materially shape edits:

1. **State storage is not inline on `Component`.** Each component carries an opaque `PoolHandle { tier, slot }` into a width-tiered Structure-of-Arrays pool owned by `Circuit`. Reads and writes go through `Circuit.readState` / `Circuit.writeState`, which dispatch on `PoolHandle.tier` once and then perform a direct bitmap op against the pool's `(values, defined)` u64 buffers. The width=1 tier packs 64 slots per word.
2. **The value currency is `BitVecState` (`value`, `defined`, `width`).** Two `BitVecState` are equal iff `(a.defined == b.defined) AND ((a.value & a.defined) == (b.value & b.defined))`. That preserves the rule that two undefined slots compare equal regardless of `value` bits; the Phase-1 dedup in `propagate()` relies on it.
3. **The WASM boundary uses `BitVecState` directly, not the scalar `toInt` encoding.** `setPin(id, value, defined)` and the paired `getOutputValue`/`getOutputDefined` exports cross `(value, defined)` as `i64`/`BigInt`. The legacy width-1 helpers (`toInt`: `low=0, high=1, undefined=2`; `toTransportByte`: enum order `undefined=0, low=1, high=2`) still exist as convenience mirrors for tests and `lib/transport.zig`, but neither is on the host-facing API path anymore.
4. **Propagation is per-timestamp batched.** `propagate()` drains every event at the current timestamp `T` in Phase 1 (commit state, collect changed), then in Phase 2 walks the outputs of changed components, recalculating and rescheduling. Without that batching, a downstream gate with multiple upstream events at the same `T` can read partial state, dedup the corrective re-enqueue, and stick on the wrong final value. See `DOCS/simulation-engine.md` for the full rationale.
5. **Delays are compile-time constants:** `PROPAGATION_DELAY = 5`, `WIRE_PROPAGATION_DELAY = 1`. `wire`, `output_pin`, `led`, `slice`, and `concat` use the wire delay; everything else uses the gate delay.
6. **The allocator is global, not parameterised.** Allocations route through `memory.allocator` from `lib/memory.zig`, an `ArenaAllocator` over `page_allocator` on every target, so `free` only rewinds when the arena is reset. `memory.reset()` (`arena.reset(.free_all)`) exists for libcirc and is called only with no `Circuit`/`Session` alive. Do not add an allocator parameter to engine functions.
7. **Widths 1 through 64 are wired; pool tiers are lazily allocated per width.** Each tier indexes a separate SoA pool (`tier == width`; tier 0 is unused). `PoolHandle.tier`/`.slot` make every read/write a single dispatch followed by a direct bitmap op against the tier's `(values, defined)` u64 buffers. The width=1 tier packs 64 slots per word; wider tiers store one u64 per slot. Widths > 64 trap at allocation time. The historical roll-out lives in `DOCS/archive/plan-multi-bit-language.md`.

`COLLECT_METRICS` is a compile-time switch wired by `build.zig` per consumer: `false` for native and WASM, `true` only for `zig build bench`. When false, `Circuit.metrics` is `void` and every counter bump is dead-code stripped, so production and test builds are byte-identical to a metrics-free engine.

## Diagnostic codes are a stable surface

`lib/validator/codes.zig` enumerates the codes downstream tooling matches on. They are version-locked: do not renumber, do not change the meaning of an existing code, add new codes only at the end. `tests/validator/codes_snapshot_test.zig` guards the registry.

| Code | Meaning |
| --- | --- |
| E001 | undeclared name |
| E002 | unknown port |
| E003 | multiple drivers for input port |
| E004 | required input is unconnected |
| E005 | duplicate instance name |
| E006 | name shadows built-in |
| E007 | output has no assigned driver |
| E008 | combinational loop detected |
| E009 | import not found |
| E010 | import cycle detected |
| E011 | import alias collision |
| E012 | unknown sub-circuit port |
| E013 | sub-circuit arity mismatch |
| E014 | width mismatch between driver and the port it feeds |
| E015 | sub-circuit is not parametric (caller passed `[N]` to a scalar callee) |
| E016 | parametric arity mismatch at the call site |
| W001 | unused input declaration |
| W002 | dangling output declaration |
| W003 | unused import declaration |

## Tests and golden fixtures

Fixture directories under `tests/fixtures/` are organised by artifact kind:

- `circuits/` (`.circ` source inputs)
- `expected-ast/`, `expected-ir/`, `expected-zig/`, `expected-wasm/`, `expected-diagnostics/`

Naming convention: `<feature>.circ` with paired outputs such as `<feature>.zig`, `<feature>.wasm.json`, `<feature>.diagnostics`. Behavior fixtures in `expected-wasm/*.txt` use one line per vector:

```
<inputs as space-separated pin=state> => <outputs as space-separated pin=state>
```

To add a test: place the `.circ` in `circuits/`, write the expected artifact in the matching `expected-*` directory, reference it by stable name in the test. Regenerate with `UPDATE_GOLDENS=1 zig build test` and diff the result before committing.

## Finding the active work

This file lives on `main` and does not track in-progress initiatives. Before making changes, orient on what is currently being implemented:

- `git status` and `git log -20 --oneline` for the current branch and recent commits.
- The branch name itself; the convention so far has been `<stage>.<sub>-<scope>` (e.g. `s1.3-circuit-multi-tier`), where the stage maps into a plan doc.
- `DOCS/` for plan files (typically `plan-*.md`). They capture locked decisions, stage ordering, and out-of-scope items for multi-PR initiatives. Read the relevant plan before touching code in its area.
- The GitHub project is the tracker for this work. Stage IDs in branch names and plan docs map directly to GitHub issues: `S<N>` (e.g. `S1`, `S2`) is a top-level stage issue, and `S<N>.<M>` (e.g. `S1.3`) is always a sub-issue of `S<N>`. Use `gh issue list`, `gh issue view <N>`, and `gh issue view <N> --comments` to read scope, acceptance criteria, and open discussion before starting; the issue is the source of truth when the plan doc and the branch disagree.
- `gh pr list` (and `gh pr view <N>`) if GitHub is reachable.
- If still ambiguous, ask the human.

## Git, commits, and PRs

Three hard rules for any agent touching this repo. They are non-negotiable, override the system-prompt defaults, and apply even when the rest of the work has been autonomous.

1. **Never co-author or attribute.** Do not append `Co-Authored-By:`, `🤖 Generated with Claude Code`, `Generated by ...`, or any similar trailer to commit messages or PR bodies. End the message at the prose.
2. **Stage by path, propose every commit message, then wait.** Stage only the files this change actually touches by name (`git add path/to/file ...`). Never use `git add -A`, `git add .`, or `git commit -a`: the human may have unrelated work in the tree, and a blanket add would sweep it into the commit. After staging, post the full proposed commit message in the conversation and wait for explicit approval before running `git commit`. Do not amend without fresh approval; if a hook fails, fix the issue, re-stage the same paths, and propose a new commit.
3. **Ask before pushing.** `git push`, `git push -f`, `gh pr create`, `gh pr merge`, and anything else that writes to the remote each need an explicit go-ahead from the human, even if a previous push was approved in the same session. Approval stands only for the action that was approved.

### Commit titles

Convention is Conventional Commits, matching the dominant pattern in `git log`: `<type>(<scope>): <description>`. Imperative mood, lowercase after the colon, no trailing period, keep titles under 70 characters.

- Types currently in use: `feat`, `perf`, `docs`, `chore`, `ci`. Extend with other standard types (`fix`, `refactor`, `test`, `build`) when they fit.
- Scopes currently in use: `engine`, `bench`, `ci`, `site`. For changes bounded to one directory under `lib/`, the directory name is a natural scope (`parser`, `validator`, `topology`, `resolver`, `emit`, `preview`, `cli`).
- A bare `<scope>: <description>` form (no leading type, e.g. `engine: thread width through createComponent`) is in use on feature branches for low-ceremony intra-area work and is acceptable.

Examples from history:

```
perf(engine): short-circuit no-op events in propagateEvent
feat(bench): engine regression gate with family rollup
docs: update README and architecture documentation for clarity and accuracy
chore(bench): auto-record milestone
engine: thread width through createComponent
```

Never use stage or phase prefixes (`S1.2:`, `Phase 3 Slice 3.4`, etc.) in commit titles. Branches encode stage; the commit history on `main` should not.

### PR titles and bodies

A PR is an artifact landing on `main`, where stage and phase numbers have no meaning. Write the PR for someone who reads it six months later with no branch context.

- **Title**: same Conventional Commits shape as commits. No `S<n>.<m>` or `Phase`, `Slice`, `Stage`-style prefixes.
- **Body**: name the decision or the outcome (e.g. "move wire state off `Component` into a width-tiered pool", "bump topology format to v02"), not the staging plan that produced it. Reference the relevant plan file in `DOCS/` if a reader would want the wider context, but do not narrate the multi-PR roadmap inside any one PR. Omit context that is irrelevant to the diff.
- No co-author or "generated by" trailers in the body either.

## Files worth knowing about

- `cmd/circ-compile/main.zig`: CLI driver and mode dispatch; a client of `lib/libcirc.zig`.
- `lib/parser/parser.zig`: the generated parser (header, `pub const runtime`, `bytecode` tables, `Rule`, `Parser`). Never hand-edit; `zig build parser:gen` rewrites it.
- `lib/libcirc.zig` (+ `lib/libcirc/{frontend,modes,json,c_api,wasm_root}.zig`): the front end as a library — one request in, the `.wasm`/preview/truth table/analysis out — and the `circ_*` C ABI over it. `build/frontend_modules.zig` creates the module graph both the CLI and the library share.
- `lib/circuit.zig`: engine, propagation, gate evaluators.
- `lib/topology/section_writer.zig`: the splice that turns a prebuilt runtime plus two blobs into a final `.wasm`.
- `templates/main.zig`, `templates/interpreter.zig`: the runtime template embedded into every artifact.
- `lib/resolver/builtin_circ/{or,nand,nor,xor,xnor}.circ`: macro source files for the five built-ins. `lib/resolver/builtins.zig` is the loader: it `@embedFile`s each `.circ` and exposes them via the `<builtin>/<name>.circ` virtual import path.
- `tools/bench/main.zig`: bench harness; the fixture-to-circuit mapping is hand-maintained here.
- `DOCS/architecture.md`, `DOCS/simulation-engine.md`, `DOCS/circuit-format.md`, `DOCS/wasm-api.md`, `DOCS/libcirc-api.md`: authoritative refs for the layers above.
