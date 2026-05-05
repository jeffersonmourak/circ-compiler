# Phase 4 — Cleanup

> **Dependencies:** Phase 3 (CLI wiring complete and verified; no code path reaches the orchestrator at runtime)
> **Warnings:** `templates/main.zig` is the runtime template modified in Phase 0. It is NOT deleted in this phase. Only `templates/build.zig` and the empty `templates/builtins/` directory are removed. Deleting `templates/main.zig` would break the pre-built runtime build step.

## Goal

Once this phase is complete, `lib/orchestrator/` and all dead code it dragged in are gone. `cmd/circ-compile/main.zig` no longer references the orchestrator or computes the emitted Zig source in compile mode. `--build-dir` is an unknown flag. The `getting-started.md` host protocol reflects the `topology_alloc` + `init()` sequence. `zig build test` passes in full; `--emit-zig` and `--inspect` are unchanged.

## Scope

**In scope:**
- Remove the `orchestrator` import and the now-unreachable `emitted` Zig source computation from the compile path in `cmd/circ-compile/main.zig`; move `emitted` computation inside the `.emit_zig` branch where it is actually needed
- Remove `--build-dir` from `lib/cli_args.zig` (becomes `error.UnknownFlag`)
- Remove orchestrator module declarations from `build.zig`
- Delete `lib/orchestrator/` (main.zig, subprocess.zig, workspace.zig, finalize.zig, embed.zig)
- Delete `orchestrator_embed_module.zig` (root-level re-export shim)
- Delete `templates/build.zig` and `templates/builtins/` (old orchestrator workspace template; empty directory)
- Update `getting-started.md` step 3 and step 4 with the new Node instantiation protocol (`topology_alloc` + `init()`)
- Update `DOCS/decisions/compiler-pipeline.md` to replace the "zig build invoked as a subprocess" section with the new pipeline description
- Verify and update any Node test scripts in `tests/` that call `init()` without the `topology_alloc` step

**Explicitly deferred:**
- Nothing — this is the terminal phase.

## File & Module Topology

**New files:** None.

**Deleted files:**

| File | Reason |
|------|--------|
| `lib/orchestrator/main.zig` | Orchestrator entry point — replaced by serializer + section_writer |
| `lib/orchestrator/subprocess.zig` | Zig subprocess runner — no longer invoked |
| `lib/orchestrator/workspace.zig` | Temp directory management — no longer needed |
| `lib/orchestrator/finalize.zig` | Output copy and cleanup — no longer needed |
| `lib/orchestrator/embed.zig` | Source-file embed list — replaced by `lib/topology/runtime_embed.zig` |
| `orchestrator_embed_module.zig` | Root-level re-export shim for the old embed |
| `templates/build.zig` | Orchestrator workspace build template |
| `templates/builtins/` | Empty directory, left over from orchestrator era |

**Modified files:**

| File | Change |
|------|--------|
| `cmd/circ-compile/main.zig` | Remove `orchestrator` import; remove eager `emitted` computation; move emit call inside `.emit_zig` branch; remove `--build-dir` handling |
| `build.zig` | Remove orchestrator module declarations and their dependencies from the `circ-compile` build target |
| `lib/cli_args.zig` | Remove `build_dir` field and `--build-dir` parsing; its presence now falls through to `error.UnknownFlag` |
| `DOCS/getting-started.md` | Update step 3 compile description and step 4 Node instantiation example with `topology_alloc` host protocol |
| `DOCS/decisions/compiler-pipeline.md` | Replace "zig build invoked as a subprocess" and "vendored runtime template" sections with the new interpreter-based pipeline description |

**New dependencies:** None.

## Data & State

No new types or data structures. The only state change is the simplification of `cmd/circ-compile/main.zig`:

### `run()` after Phase 4 — compile mode shape

```zig
// emitted is no longer computed here; it moves inside .emit_zig below

switch (args.mode) {
    .emit_zig => {
        const emitted = blk: {
            if (maybe_project) |*project| {
                break :blk emit_main.emitProjectSource(...) catch |err| { ... };
            }
            break :blk emit_main.emitModuleSource(...) catch |err| { ... };
        };
        writeFileAny(args.output_path.?, emitted) catch |err| { ... };
        return 0;
    },
    .compile => {
        // serialize → combine → write  (as established in Phase 3)
        ...
        return 0;
    },
    .inspect => unreachable,
}
```

The `--build-dir` field on `Args` is removed. The `BuildDirInWrongMode` error in `cli_args.zig` is also removed since the flag no longer exists.

## Execution & Concurrency Model

This phase is fully synchronous. No new runtime behaviour is introduced — only dead code is removed.

## Persistence & I/O

No new I/O. Documentation files are updated on disk.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | CLI and build.zig cleanup | Remove orchestrator import and eager `emitted` from `main.zig`; move emit inside `.emit_zig`; remove `--build-dir` from `cli_args.zig`; remove orchestrator module declarations from `build.zig` | `zig build circ-compile` succeeds; `--emit-zig` produces correct output; `--build-dir` returns exit code 2 with a usage error |
| 2 | Dead file deletion | Delete `lib/orchestrator/`, `orchestrator_embed_module.zig`, `templates/build.zig`, `templates/builtins/` | `zig build test` green; no dangling imports; `git status` shows only deleted and modified files, no unexpected changes |
| 3 | Host protocol and docs | Update all Node test scripts in `tests/` to use the `topology_alloc` + `init()` protocol; update `getting-started.md` and `DOCS/decisions/compiler-pipeline.md` | `zig build test` green; manual verification that `getting-started.md` step 4 snippet runs correctly against a freshly compiled inverter |

Slices are ordered by dependency. Slice 2 cannot begin until Slice 1 compiles cleanly — deleting files before removing their import sites causes build errors.

## Tests

**Unit tests:** None new — this phase removes code, not adds it.

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| `test "phase4: --build-dir is rejected"` | `tests/` | `circ-compile foo.circ -o out.wasm --build-dir /tmp/x` exits 2 with a usage error on stderr |
| `test "phase4: --emit-zig still works"` | `tests/` | `circ-compile foo.circ --emit-zig -o out.zig` exits 0 and produces a non-empty `.zig` file |
| `test "phase4: full fixture suite"` | `tests/` | All circuits and project fixtures compile and pass Node behavioral assertions using the updated host protocol |

Run command: `zig build test`

## Open Questions / Spikes

- **`emit_main` usage after cleanup:** once `emitted` is moved inside the `.emit_zig` branch, `emit_main` is only imported for that mode. Verify that moving the import to be conditional (or keeping it at the top and trusting dead-code elimination) does not trigger unused-import warnings in Zig 0.15. If it does, the import stays at the top — Zig's `@import` is not conditional.
- **Builtin circuit paths in the new pipeline:** `templates/builtins/` is empty now, but check whether any builtin sub-circuits (xor, nand, etc.) are resolved via file paths that point into `templates/builtins/`. If so, those files need to move before the directory is deleted. Based on the current state (directory is empty), this is not an issue, but confirm before Slice 2.
