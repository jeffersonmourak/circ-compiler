# Phase 3 — CLI Wiring

> **Dependencies:** Phase 0 (runtime embed), Phase 1 (serializer), Phase 2 (section writer)
> **Warnings:** The old orchestrator path is intentionally left in place. Do not delete any modules in this phase — that is Phase 4's job. The goal is a correct new path, not a clean codebase.

## Goal

Once this phase is complete, `circ-compile foo.circ -o foo.wasm` invokes the serializer and section writer instead of the orchestrator. No `zig` subprocess is spawned. The `--emit-zig` and `--inspect` modes are unaffected. The full `zig build test` suite passes.

## Scope

**In scope:**
- Add `serializer`, `section_writer`, and `runtime_embed` as module dependencies of the `circ-compile` build target in `build.zig`
- Replace the `orchestrator.compile()` call in the `.compile` branch of `cmd/circ-compile/main.zig` with: serialize IR → combine with runtime blob → write to output path
- The `emitted` Zig source is still computed eagerly (it is still needed for `--emit-zig`); in compile mode it is simply unused — leave this waste for Phase 4 to clean up
- `--build-dir` becomes silently ignored in compile mode; emit a stderr warning but do not error — Phase 4 will remove the flag entirely

**Explicitly deferred:**
- Removing the `orchestrator` import and `emitted` computation from the compile path (Phase 4)
- Removing `--build-dir` from `cli_args` (Phase 4)
- TypeScript SDK update for the host protocol (Phase 4)
- Deleting `lib/orchestrator/`, old `embed.zig`, `templates/` (Phase 4)

## File & Module Topology

**New files:** None.

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| build | `build.zig` | Add `topology_serializer`, `topology_section_writer`, `topology_runtime_embed` as module dependencies of the `circ-compile` executable |
| CLI | `cmd/circ-compile/main.zig` | Add imports for `serializer`, `section_writer`, `runtime_embed`; replace the `.compile` branch body; add `--build-dir` deprecation warning |

**New dependencies:** None beyond what Phases 0–2 introduced.

## Data & State

No new types. The CLI already holds the resolved IR (`ir_module` and `maybe_project`) from the parse/resolve step. The new compile branch reads those directly.

### New `.compile` branch (replaces `orchestrator.compile()` call)

```zig
.compile => {
    if (args.build_dir != null) {
        try stderr_writer.writeAll(
            "warning: --build-dir is unused in the new compile path and will be removed in a future release\n",
        );
    }

    const topology_bytes = blk: {
        if (maybe_project) |*project| {
            break :blk serializer.serializeProject(allocator, project) catch |err| {
                try stderr_writer.print("topology serialization failed: {s}\n", .{@errorName(err)});
                return 1;
            };
        }
        break :blk serializer.serializeModule(allocator, &ir_module) catch |err| {
            try stderr_writer.print("topology serialization failed: {s}\n", .{@errorName(err)});
            return 1;
        };
    };
    defer allocator.free(topology_bytes);

    const wasm_bytes = section_writer.combine(
        allocator,
        runtime_embed.runtime_wasm,
        topology_bytes,
    ) catch |err| {
        try stderr_writer.print("wasm assembly failed: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(wasm_bytes);

    writeFileAny(args.output_path.?, wasm_bytes) catch |err| {
        try stderr_writer.print("failed writing wasm output: {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
},
```

The `emitted` variable, the `orchestrator` import, and the old orchestrator call are left in place. They are dead code in the compile path after this change but are still reachable via `--emit-zig`.

## Execution & Concurrency Model

This phase is fully synchronous. The new compile path: serialize (in-memory) → combine (in-memory, one allocation) → write file. No subprocess, no temp directory, no background work.

## Persistence & I/O

- **Reads:** resolved IR already in memory from the parse/resolve step; `runtime_embed.runtime_wasm` is a compile-time constant embedded in the binary
- **Writes:** the combined `.wasm` to `args.output_path` via the existing `writeFileAny` helper
- **No temp directory.** Concurrent invocations of `circ-compile` are safe by construction — there is no shared mutable filesystem state.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Build wiring | Add the three new module dependencies to `build.zig`; `zig build circ-compile` succeeds with the new imports resolvable in `main.zig` | `zig build circ-compile` succeeds; the binary size increases by the embedded runtime blob |
| 2 | Compile branch replacement | Replace the `.compile` branch body in `main.zig` with the new path; add `--build-dir` warning | `circ-compile tests/fixtures/circuits/inverter.circ -o /tmp/test.wasm` produces a valid `.wasm`; Node instantiation with the Phase 0 host protocol produces correct output; `zig` process is not spawned |
| 3 | Full fixture regression | Run the complete `zig build test` suite; verify all CLI-level tests pass with the new path | `zig build test` green; `--emit-zig` and `--inspect` modes produce identical output to before |

## Tests

**Unit tests:** None new — the compile branch change is a composition of already-tested units (serializer, section_writer). Correctness is proven by integration.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| `test "phase3: circ-compile inverter end-to-end"` | `tests/` | `circ-compile inverter.circ -o out.wasm` exits 0; Node instantiation with host protocol asserts `a=0→1`, `a=1→0` |
| `test "phase3: circ-compile project end-to-end"` | `tests/` | `circ-compile` on a project fixture (half-adder or full-adder) exits 0; Node behavioral assertions pass |
| `test "phase3: --emit-zig output unchanged"` | `tests/` | `circ-compile foo.circ --emit-zig -o out.zig` produces byte-identical output to the pre-Phase-3 binary for the same input |
| `test "phase3: --inspect output unchanged"` | `tests/` | `circ-compile foo.circ --inspect` stdout is unchanged |
| `test "phase3: --build-dir emits warning not error"` | `tests/` | `circ-compile foo.circ -o out.wasm --build-dir /tmp/x` exits 0 and writes `warning:` to stderr |

Run command: `zig build test`

## Open Questions / Spikes

- **Host protocol in existing CLI tests:** the tests that drive the CLI-produced `.wasm` via Node currently call `init()` directly. After Phase 3, the compiled `.wasm` requires the `topology_alloc` + `init()` sequence. Audit `tests/` for any Node scripts that call `init()` without the host protocol and update them as part of Slice 3. If no such scripts exist yet, document this as a known gap for Phase 4.
