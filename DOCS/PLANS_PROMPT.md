# Plan Prompt — Dead Code Removal

## What Is Being Built

This initiative removes all dead code, unnecessary code, and superseded implementations from the `circ-compiler` codebase. The project began life as `circ-renderer-z`, a dynamic browser rendering library, and was subsequently re-architected into a CLI compiler that produces self-contained `.wasm` artifacts. That evolution left behind a browser-facing dynamic API layer (`lib/wasm.zig`, `lib/transport.zig`), a hand-wired debug harness (`main.zig`), a prototype compiler binary (`lib/compiler.zig`), the full TypeScript/browser application (`src/`, `example/`, and frontend tooling), stubs and placeholder implementations inside otherwise-active modules, and commented-out dead build wiring throughout `build.zig`.

The initiative is complete when every symbol, file, and build target that is not reachable from `cmd/circ-compile/main.zig` or the active test suite has been deleted, `zig build test` passes clean, and `build.zig` contains no commented-out steps or unreachable targets.

Architectural anchors that must not be touched: the simulation engine (`lib/circuit.zig`) stays WASM/JS-agnostic; the compiler pipeline (`lib/syntax/` → `lib/ir/` → `lib/validator/` → `lib/emit/` → `lib/orchestrator/` → `cmd/circ-compile/`) is the production code path and must not regress; `lib/orchestrator/embed.zig` and its re-export shim (`orchestrator_embed_module.zig`) are used by the orchestrator test suite and are live.

## Tech Stack

- **Language:** Zig 0.15.x (compiler and simulation engine), TypeScript (example demo only — being removed)
- **Build system:** `zig build` (`build.zig`); active CLI target is `zig build circ-compile`
- **Test runner:** `zig build test` (runs all test binaries registered in `build.zig`)
- **Deployment target:** Native binary (`circ-compile`); compiled circuits target `wasm32-freestanding`
- **Parser:** langlang-generated C parser, sources vendored in `lib/parser.c` / `lib/parser.h`

## Architectural Constraints

- See `DOCS/decisions/compiler-pipeline.md`: one self-contained `.wasm` per `.circ` file; no shared runtime file; CLI shells out to `zig build` subprocess; vendored runtime embedded via `@embedFile`.
- See `DOCS/decisions/language.md`: built-ins (`or`, `nand`, `nor`, `xor`, `xnor`) are `.circ` modules on the virtual `<builtin>/` path — they must not be conflated with the legacy `lib/wasm.zig` primitives.
- See `DOCS/decisions/runtime-api.md`: compiled-artifact WASM exports are fixed (`init`, `deinit`, `reset`, `run`, `stop`, `setPin`, `getOutputState`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer`). Modifying exported names is out of scope.
- The simulation engine (`lib/circuit.zig`) has no knowledge of WASM or JavaScript. Changes to it that cross that boundary are out of scope.
- `lib/syntax/` is live (active compiler pipeline). Architecture.md describes it as "WIP" — that doc is stale; the syntax layer is fully connected and tested.
- Do not remove or rename diagnostic codes `E001`–`E013`, `W001`–`W003` — they are part of the frozen v0 API surface.

## Phase Index

| Phase | Name | What Ships |
|-------|------|-----------|
| 0 | Audit | A written dead-code inventory (`DOCS/PLANS/PHASE_0_audit.md`) mapping every suspect file, build target, and symbol to live/dead status — no code changes; proves scope before anything is deleted. |
| 1 | Browser layer removal | Delete `example/`, `src/`, TypeScript tooling (`package.json`, `tsconfig.json`, `bun.lock`, `node_modules/`), `lib/wasm.zig`, `lib/transport.zig`, and the `wasm` / `wasm_step` build targets from `build.zig`; `zig build test` still passes. |
| 2 | Legacy Zig binaries | Delete `main.zig` (root), `lib/compiler.zig`, and remove the `logic-sim`, `compiler`, `compiler:run`, and `run` build targets from `build.zig`; clean up any now-dead `b.installArtifact` calls; `zig build test` still passes. |
| 3 | Stubs and placeholders | Remove all commented-out lines in `build.zig` (parser-gen step wiring, `wasm_lib.linkSystemLibrary`, etc.); `zig build test` still passes. |
| 4 | Surgical dead symbols | Grep-and-verify pass over all active `.zig` files for unreferenced functions, unused imports, and orphaned test fixtures; remove each confirmed dead item; `zig build test` still passes. |

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
2. Run `zig build test` for the affected modules. Do not ship a slice that breaks the suite.
3. Append a STATUS entry (template below).
4. **Stop.** Wait for human review and commit before beginning the next slice.

### Git Rules

- Do **not** commit, push, or run any write `git` or `gh` command on the human's behalf.
- Read-only git commands (`status`, `log`, `diff`) are encouraged for situational awareness.

## STATUS Entry Template

Append to `DOCS/STATUS.md` at the end of every slice. Never overwrite or edit prior entries.

```
## YYYY-MM-DD — Phase N — <slice title>

**What shipped:** <one or two sentences>
**Files touched:** `<file>`, `<file>`
**Tests:** ran `zig build test`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

## Recurring Traps

- `orchestrator_embed_module.zig` re-exports from `lib/orchestrator/embed.zig` and is wired as a build module for the orchestrator test suite — do not delete it as part of Phase 1 or 2 without confirming the test wiring in `build.zig` around line 620.
- `lib/transport.zig` is imported by both `lib/wasm.zig` and `main.zig`. Confirm both are deleted before removing `transport.zig`; otherwise the build breaks on a missing import.
- `lib/wasm.zig` imports `lib/transport.zig` and `lib/circuit.zig`. Removing `wasm.zig` does not affect `circuit.zig`, which is live.
- The `parser_gen` / `generate_parser_cmd` step in `build.zig` generates `lib/parser.c` / `lib/parser.h` from the PEG grammar. These generated sources are vendored. The generation step is already commented out. Phase 3 may clean up the commented lines, but must not delete the vendored `lib/parser.c` / `lib/parser.h` — they are required at build time.
- `getTopology()` is a frozen export name in the compiled-artifact API surface. Its static placeholder payload is **intentional future-implementation scaffolding** — do not remove or replace it in any phase. Leave it exactly as-is.
- Architecture.md describes `lib/syntax/` as "WIP / not yet connected" — that description is stale. Do not treat those files as dead; update the doc instead.
