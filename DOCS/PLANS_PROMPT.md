# Plan Prompt — Self-Contained Compiler (No Zig at User Runtime)

## What Is Being Built

`circ-compile` currently requires Zig installed on the user's machine. The compile path shells out to `zig build` as a subprocess against a temporary working directory containing the emitted Zig IR and the vendored runtime sources. This initiative removes that dependency entirely: a user who downloads `circ-compile` can run `circ-compile foo.circ -o foo.wasm` on a machine with no Zig installation.

The approach replaces the subprocess with an interpreter-based pipeline. At `zig build circ-compile` time, the runtime (circuit.zig, memory.zig, and friends) is pre-compiled to a WASM binary and embedded in the CLI via `@embedFile`. A circuit interpreter is added to the runtime template so it can read a binary circuit topology description (`circ.topology` format) during `init()`. At circuit-compile time, the CLI serializes the resolved IR into that binary format and appends it as a WASM custom section to the pre-built runtime blob.

**Host protocol note:** WASM custom sections are opaque to the module itself — the module cannot read its own custom sections. The host (Node/browser) reads the `circ.topology` section via `WebAssembly.Module.customSections()`, calls the `topology_alloc(len)` export to get a writable pointer, copies the bytes into WASM linear memory, then calls `init()`. The TypeScript SDK handles this transparently; raw users follow the documented protocol. No subprocess, no temp directory, no `zig build` invocation.

The definition of done: `circ-compile foo.circ -o foo.wasm` on a Zig-free machine produces a `.wasm` that is functionally equivalent to what the current pipeline produces — same simulation behavior on all test fixtures. The `--emit-zig` and `--inspect` modes are unaffected.

## Tech Stack

- Language: Zig 0.15.x (CLI compilation and runtime compilation)
- WASM target: `wasm32-freestanding` (unchanged)
- Simulation engine: `lib/circuit.zig`, `lib/memory.zig`, `lib/log.zig`, `lib/transport.zig` (unchanged)
- Circuit topology format: project-defined binary format, custom section name `circ.topology`
- Parser: vendored C parser (`lib/parser.c` / `lib/parser.h`), langlang pinned at `go/v0.0.12`
- Test runner: `zig build test`
- Artifact validation: `WebAssembly.validate()` via Node.js in integration tests

## Architectural Constraints

- Zig is a build-time-only dependency for end users of `circ-compile`. It is never invoked at circuit-compile time. This is the non-negotiable goal of the initiative.
- The runtime is pre-compiled to WASM exactly once, at `zig build circ-compile` time, and embedded via `@embedFile`. If runtime sources change, the CLI must be rebuilt — this is intentional and matches the existing vendored-source model.
- The `circ.topology` binary format is locked at the end of Phase 0 and does not change after that. Format changes require updating the serializer and interpreter in lockstep and are out of scope for this initiative.
- Custom section append always happens at the tail of the WASM binary. No standard WASM sections are modified or rewritten. No function index fixup. No section merging. This is the invariant that makes Phase 2 reliable.
- The `--emit-zig` mode uses the existing `lib/emit/` path, which is untouched by this initiative.
- Do not embed the Zig compiler as a library. This was previously rejected in `DOCS/decisions/compiler-pipeline.md` and remains rejected.
- The sub-circuit hierarchy must be fully flattened by the serializer into a single ordered sequence of `createComponent` / `connect` operations. The runtime interpreter has no concept of sub-circuit boundaries or function calls. The resolver's project IR (`resolve_bodies`) provides the input; the serializer is responsible for the flattening.
- The test suite must pass at the end of every phase. No phase ships with a broken suite.

## Phase Index

| Phase | Name | What Ships |
|-------|------|------------|
| 0 | Runtime-as-WASM | Pre-built runtime WASM with circuit interpreter embedded in `circ-compile`; proven by a hand-crafted `circ.topology` custom section instantiating a valid circuit in a Node integration test |
| 1 | Topology Serializer | Zig module that translates the resolved IR (single file and project) into the `circ.topology` binary format; proven by serializing all test fixtures and driving the Phase 0 interpreter to produce correct simulation output |
| 2 | Custom Section Writer | Combines the pre-built runtime blob with the serialized topology into a single `.wasm`; proven by `WebAssembly.validate()` passing and all fixture behavioral tests matching the current pipeline output |
| 3 | CLI Wiring | Replaces `orchestrator.compile()` with the new path in `cmd/circ-compile/main.zig`; both old and new paths coexist; proven by `circ-compile foo.circ -o foo.wasm` producing a correct artifact without spawning a `zig` process |
| 4 | Cleanup | Removes `lib/orchestrator/` (subprocess, workspace, finalize), old `lib/orchestrator/embed.zig`, `templates/`; updates TypeScript SDK to handle `topology_alloc` protocol; proven by `zig build test` passing in full with all dead code removed and `--emit-zig` still working |

Phases are ordered by dependency, not by priority. Each phase must be fully shippable before the next begins.

## Working Loop

The execution agent follows this loop every session without exception.

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
**Tests:** added <names>, ran `<command>`, result <pass/fail>
**Next slice:** <one sentence>
**Notes:** <anything the next session needs that isn't obvious from the code>
```

## Recurring Traps

- **Format lock.** The `circ.topology` binary format must be fully defined and locked before Phase 1 begins. Any post-lock change requires updating the serializer and interpreter simultaneously — treat it like a wire protocol.
- **Runtime rebuild discipline.** The pre-built runtime WASM is embedded at CLI build time. Changes to `lib/circuit.zig`, `lib/memory.zig`, or the runtime template do not take effect until `zig build circ-compile` is re-run. Make this explicit in documentation so contributors don't debug phantom behavior mismatches.
- **Sub-circuit flattening.** The current Zig-source emitter handles sub-circuits via function calls compiled into the same WASM module. The topology serializer must flatten the entire resolved project graph — including all imported sub-circuits — into a single ordered flat sequence before serializing. Do not assume the runtime interpreter handles hierarchy.
- **Custom section position.** The WASM spec allows custom sections at various positions, but appending after all standard sections is always valid. Do not attempt to insert the custom section at any other position.
- **`--emit-zig` regression.** The cleanup in Phase 4 removes the orchestrator but must leave `lib/emit/` intact. The `--emit-zig` flag still uses it. Verify this mode explicitly before marking Phase 4 complete.
- **Concurrent compilation.** The old pipeline used random temp dirs to prevent compile collisions. The new pipeline has no temp dir. Concurrent `circ-compile` invocations are safe by construction — verify this holds if any temp state is introduced during Phase 2.
