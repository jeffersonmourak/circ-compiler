# Plan Prompt — Embed Zig Compiler for Self-Contained circ-compile

## What Is Being Built

The current `circ-compile` pipeline shells out to `zig build` as a subprocess to compile emitted Zig IR into a `.wasm` artifact. This makes Zig a runtime dependency — end-users must have Zig installed and in PATH. The goal of this initiative is to eliminate that dependency by embedding Zig's self-hosted compiler directly into the `circ-compile` binary, calling its compilation API in-process. The result is a single, fully self-contained `circ-compile` binary that can compile `.circ → .wasm` on a machine with no Zig installation at all.

The definition of done: `circ-compile <input.circ> -o <output.wasm>` succeeds on a clean machine (no Zig in PATH, no Zig cache seeded) on macOS and Linux. The output `.wasm` is byte-for-byte equivalent to what the current subprocess path produces.

The initiative deliberately revisits the decision in `DOCS/decisions/compiler-pipeline.md` that previously rejected embedding Zig as a library due to API instability. The accepted tradeoff is that upgrading Zig versions will require integration work; the benefit is a zero-dependency distributable binary. The self-hosted WASM backend (no LLVM required) is what makes this tractable — if LLVM turns out to be required for the WASM target, the strategy must be reconsidered before proceeding past Phase 0.

## Tech Stack

- **Language:** Zig 0.15.x (project source and vendored compiler source)
- **Compiler source:** Zig self-hosted compiler (`src/Compilation.zig` and dependencies from the Zig source tree), WASM backend only
- **Parser:** langlang `go/v0.0.12`, generated C parser vendored in `lib/parser.c` / `lib/parser.h`
- **Build system:** `zig build` (for building `circ-compile` itself; not used at circuit-compile time after this initiative)
- **Runtime template:** Vendored Zig source files embedded via `@embedFile` into the CLI binary
- **Test runner:** `zig build test`
- **Deployment target:** Self-contained native binary for macOS (arm64/x86_64) and Linux (x86_64)

## Architectural Constraints

- The compiled WASM artifact must remain a single self-contained file per `.circ` source — no change to the output contract. See `DOCS/decisions/compiler-pipeline.md` (Output artifact shape).
- The Zig compiler source vendored here is pinned to the Zig 0.15.x version used to build `circ-compile` itself. Version upgrades require explicit re-vendoring.
- Only the WASM-output path of the Zig compiler is in scope. LLVM backend linkage must not be introduced — if the self-hosted WASM backend requires LLVM at runtime, Phase 0 is a hard stop.
- The `--emit-zig` and `--inspect` CLI modes must continue to work unchanged; they bypass the compilation step entirely.
- The `--build-dir` flag behaviour (preserve on success when specified, preserve on failure always) must be preserved — the in-process compilation path may still write intermediates to a temp dir.
- No git write commands (commit, push, branch creation) are performed by the agent. All git operations are read-only.

## Phase Index

| Phase | Name | What Ships |
|-------|------|-----------|
| 0 | Spike | A standalone Zig test binary calls `Compilation.create()` in-process, emits a trivial WASM artifact using the self-hosted backend, and exits cleanly — proving the embedding approach works without LLVM; spike binary and findings documented in `DOCS/STATUS.md`. |
| 1 | Vendor | A curated subset of the Zig 0.15.x compiler source (WASM path only) is checked into `vendor/zig-compiler/` with a `build.zig` module definition; `circ-compile` builds against it and all existing tests pass. |
| 2 | Integrate | The `zig build` subprocess call in the CLI is replaced with an in-process call to the vendored compilation API; `circ-compile` produces identical `.wasm` output and passes the full test suite. |
| 3 | Harden | End-to-end tests run on a machine with no Zig in PATH (CI matrix: macOS arm64, Linux x86_64); `DOCS/decisions/compiler-pipeline.md` updated to record the revised decision; `DOCS/getting-started.md` updated to remove the Zig installation prerequisite. |

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
**Tests:** added <names>, ran `<command>`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

## Recurring Traps

- **LLVM dependency is a hard stop.** If `Compilation.create()` for the WASM target pulls in LLVM symbols at link time, the embedding strategy fails. Confirm LLVM-free linkage in Phase 0 before any vendoring work begins.
- **Zig compiler API is not stable.** Internal APIs (`Compilation`, `Module`, `Package`, etc.) change between patch releases. The vendored source must be pinned to the exact Zig version used to build `circ-compile`, not just the minor version.
- **Zig's compiler assumes it is the root process.** It may call `std.process.exit()`, use global state, or set signal handlers. These assumptions must be audited and neutralised before in-process use is safe.
- **Temp dir logic was designed for the subprocess model.** The current code in the CLI that manages `/tmp/circ-compile-<random>/` exists to give `zig build` a working directory. In-process compilation may still need a temp dir for intermediates — or it may not. Do not assume the existing temp dir logic carries over unchanged.
- **Cross-compilation of the WASM target.** The self-hosted WASM backend cross-compiles from native (macOS/Linux) to `wasm32-freestanding`. Confirm the target triple and CPU feature flags match what the current `zig build` subprocess uses; mismatches produce silently incorrect WASM.
- **Cache seeding.** Zig's compilation cache (`~/.cache/zig/`) may be required for in-process compilation to locate builtin modules. Test on a machine with a completely empty Zig cache to ensure the embedded compiler does not silently depend on a pre-seeded cache.
