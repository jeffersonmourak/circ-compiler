# Archived plan: zig-free-cli

**Canonical commit:** `f2f43c7f496407f9ee601f02377baca0eed3c53c` (`f2f43c7 Make linux-docker e2e Zig-free in the runtime image`)
**Archived on:** 2026-05-06
**Plan duration:** 2026-05-05 → 2026-05-06

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show <full-sha>:DOCS/PLANS_PROMPT.md`, etc.) when you need the unabridged source.

## Goal & scope

Remove Zig as a runtime dependency of `circ-compile`. The previous pipeline shelled out to `zig build` as a subprocess against a temp workspace containing emitted Zig sources plus a vendored runtime template — every end user needed Zig 0.15.x installed. The new pipeline pre-compiles the runtime (engine + circuit interpreter) to a `wasm32-freestanding` blob exactly **once**, at `zig build circ-compile` time, and embeds it via `@embedFile`. At circuit-compile time the CLI serializes the resolved IR into a `circ.topology` binary payload and appends it as a WASM custom section to the embedded blob. No `zig` subprocess, no temp directory, no `--build-dir`.

Architectural anchors that constrained the work: the `circ.topology` format is locked at end of Phase 0 and treated as a wire protocol; sub-circuit hierarchy is fully flattened by the serializer (interpreter has no concept of scope or function calls); custom section append always happens at the tail of the WASM binary (no standard sections rewritten, no function index fixup); `--emit-zig` and `--inspect` modes are untouched (preserved verbatim, including the legacy `tests/helpers/wasm_run.zig` + `tests/harness/loader.js` harness that drives them).

## Phase-by-phase highlights

### Phase 0 — Runtime-as-WASM

Pre-built runtime WASM with a circuit interpreter, embedded in `circ-compile`; proven by a hand-crafted `circ.topology` custom section instantiating in Node.

- Locked the `circ.topology` binary format in `lib/topology/format.zig`: `MAGIC = "CIRC"`, `VERSION = 0x01`, `ComponentKind` enum (`input_pin`, `not_gate`, `and_gate`, `wire`, `led`, `output_pin`), `PortName` enum (`in`, `a`, `b`, `out`), `ComponentRecord` (5 bytes), `ConnectionRecord` (9 bytes), all little-endian.
- Implemented `templates/interpreter.zig`: validates magic/version/length, decodes records, calls `createComponent` / `connect` on `circuit.zig`. Errors surface as `error.InvalidMagic`, `error.UnsupportedVersion`, `error.TruncatedPayload`.
- Added `topology_alloc(len: i32) -> i32` export and `topo_ptr` / `topo_len` globals to `templates/main.zig`; `init()` calls the interpreter when topology was loaded. Conditionally added the generic WASM API (`init`, `run`, `setPin`, `getOutputState`) on the pre-built path; old orchestrator path unchanged.
- New `build.zig` step compiles the runtime template to `zig-out/lib/circ-runtime.wasm`; `lib/topology/runtime_embed.zig` exposes `pub const runtime_wasm: []const u8` via `@embedFile`.
- `tests/e2e/topology_protocol_test.zig` (originally `phase0_node_test.zig`) hand-crafts an inverter payload, appends it as a custom section, drives via Node using the host protocol, asserts `setPin(0,0); run(); getOutputState(1) == 1` and inverse.

### Phase 1 — Topology Serializer

Zig module that translates resolved IR (single-file or project) into `circ.topology` bytes, proven against every fixture.

- `lib/topology/serializer.zig` exposes `serializeModule`, `serializeProject`, and `serializeProjectFull` (the last returns `ProjectTopology { payload, input_ids, output_ids }` with root-pin name → global ID mappings; needed by tests to drive `setPin`/`getOutputState` without hard-coding IDs).
- Recursive expander flattens sub-circuit hierarchy: `next_global_id` is a single monotonic counter; each recursive call uses `local_to_global` (`u32 → u32`) and `sub_output_map` (`u32 → StringHashMap(u32)`) for boundary rewiring. Input boundary: parent connection feeding a sub-circuit instance is rewired to the child's `input_pin` component (`port = .in`). Output boundary: parent connections sourcing from a sub-circuit output port resolve through `sub_output_map` to the child's driver component.
- `tests/e2e/serializer_fixtures_test.zig` runs the full pipeline (`scan_imports → analyzeImports → resolveBodies → validator_run_project → serializeProjectFull → buildCombinedWasm → Node`) for 20 circuit fixtures and 12 project fixtures (including stress fixtures: `stress_chain_100.circ`, `stress_grid_10x10.circ`, `stress_deep_subcircuit/`).
- **Load-bearing bug fix in `lib/circuit.zig`**: `State.flip(.undefined)` was returning Zig's `undefined` keyword (uninitialized memory) instead of the `.undefined` enum variant; the AND gate treated both-undefined inputs as HIGH instead of `.undefined`. Both bugs were silent until nested builtins (XOR = AND(OR, NAND), with OR/NAND themselves built on AND/NOT) were exercised — sequential `setPin` calls during multi-step tests produced wrong intermediate states that persisted. `regression_led_out_drives_gate.circ` and `full_adder_from_builtins.circ` exercise the path.

### Phase 2 — Custom Section Writer

`lib/topology/section_writer.zig` combines the runtime blob with a topology payload into a structurally valid WASM.

- `combine(allocator, runtime_wasm, topology_payload) ![]u8` validates the WASM magic + version on `runtime_wasm[0..8]`, requires `topology_payload.len >= 9` (minimum valid header), allocates one buffer, writes the section ID byte (`0x00`), the LEB128-encoded section body length, the name length byte (`0x0D = 13`), the literal `"circ.topology"`, then the payload. Errors: `error.InvalidRuntimeMagic`, `error.TopologyTooShort`.
- Internal `writeLeb128(buf: *[5]u8, value: u32) u3` returns bytes written; supports values up to 2^28 (a stack-allocated `[5]u8` is the upper bound for any value the section length will ever encode).
- `tests/e2e/section_writer_fixtures_test.zig` runs `WebAssembly.validate()` on the combined output for all 32 fixtures and replays the full behavioral suite via `section_writer.combine` instead of an inline helper. `WebAssembly.validate()` is invoked synchronously at the top of every Node script — catches section-framing regressions independently of circuit logic.

### Phase 3 — CLI Wiring

`circ-compile` calls the new pipeline; no `zig` subprocess at compile time.

- `cmd/circ-compile/main.zig` `.compile` branch: serialize via `serializer.serializeProject` / `serializer.serializeModule`, combine via `section_writer.combine`, write via the existing `writeFileAny`. Fully synchronous, single allocation, no temp directory.
- `tests/e2e/cli_e2e_test.zig` (originally `phase3_cli_test.zig`) drives the actual `circ-compile` binary as a subprocess. Wired via `b.addOptions().addOption([]const u8, "circ_compile_path", b.getInstallPath(.bin, "circ-compile"))` exposed as `build_options` to the test module. Covers: inverter end-to-end, half-adder project end-to-end, `--emit-zig` produces valid Zig source, `--inspect` outputs Parse Tree + Resolved IR, `--build-dir` rejection.
- Old orchestrator path intentionally left as dead code in this phase (kept reachable from the `.emit_zig` branch via `emitted` block and the `orchestrator_main` import); cleanup deferred to Phase 4.

### Phase 4 — Cleanup

All orchestrator dead code deleted; docs updated; flag surface tightened.

- Deleted: `lib/orchestrator/{main,subprocess,workspace,finalize,embed}.zig`, `orchestrator_embed_module.zig`, `templates/build.zig`, `templates/builtins/`, `tests/orchestrator/` (all 5 test files). 871 lines removed, 73 added.
- `lib/cli/args.zig`: removed `build_dir` field, `BuildDirInWrongMode` error, and `--build-dir` parsing — flag now hits the `error.UnknownFlag` fallthrough.
- `cmd/circ-compile/main.zig`: removed `orchestrator_main` import and eager `emitted` computation; emit call now lives only inside the `.emit_zig` branch.
- `build.zig`: removed all orchestrator module declarations and `test_step` dependencies (drops 16 orchestrator unit tests; suite goes from 137 → 121).
- Docs: `DOCS/getting-started.md` step 3 (pipeline description) and step 4 (Node example with `topology_alloc` host protocol) updated; `DOCS/decisions/compiler-pipeline.md` "zig build subprocess" and "vendored runtime template" sections replaced with the new interpreter-based pipeline description and host protocol decision.
- Preserved verbatim: `--emit-zig` mode and its test harness (`tests/helpers/wasm_run.zig`, `tests/harness/loader.js`). Those WASMs still call `init()` directly because they're emitted from the old Zig-source pipeline; that's correct for their format.

### Follow-ups (post-phase)

- Renamed `tests/e2e/phase{0,1,2,3}_*` to descriptive names: `topology_protocol_test.zig`, `serializer_fixtures_test.zig`, `section_writer_fixtures_test.zig`, `cli_e2e_test.zig`. Phases are temporary; the test surface is permanent.
- `tests/e2e/linux-docker/` rebuilt as a true Zig-free proof: host builds the Linux ELF, stages binary + fixture + tests into a temp build context, `Dockerfile` baked from `node:22-bookworm-slim` with `COPY` (no Zig install, no volume mounts at runtime), `container-e2e.sh` first asserts `! command -v zig` (load-bearing — if Zig leaks back in, this fails), `drive-inverter.mjs` updated to the new `topology_alloc` host protocol with the runtime's required `env` stubs (`print`, `printFmt`, `flushBuffer`, `_log`, `_log_flush`, `_log_set_name`, `debugEnabled`, `onDebugLog`).

## API surface frozen by this plan

| Surface | Value |
|---------|-------|
| Custom section name | `circ.topology` |
| Format magic | `"CIRC"` (4 bytes) |
| Format version | `0x01` |
| Component kinds | `input_pin=0`, `not_gate=1`, `and_gate=2`, `wire=3`, `led=4`, `output_pin=5` |
| Port names | `in=0`, `a=1`, `b=2`, `out=3` |
| `ComponentRecord` layout | `id: u32_le`, `kind: u8` (5 bytes) |
| `ConnectionRecord` layout | `from_id: u32_le`, `to_id: u32_le`, `port: u8` (9 bytes) |
| New runtime exports (pre-built path) | `topology_alloc(len: i32) -> i32`, `init()`, `run()`, `setPin(id, state)`, `getOutputState(id) -> i32`, `memory` |
| Required host `env` imports | `print`, `printFmt`, `flushBuffer`, `_log`, `_log_flush`, `_log_set_name`, `debugEnabled`, `onDebugLog` |
| CLI flags (compile mode) | `-o <path>`, `--warnings-as-errors` / `-Werror` |
| CLI modes | default `.compile`, `--emit-zig`, `--inspect` |
| Removed flags | `--build-dir` (now `error.UnknownFlag`) |
| `cli_args.ParseError` | `MissingInput`, `MissingOutput`, `UnknownFlag`, `ConflictingModes`, `InvalidFlagValue` |
| New section_writer errors | `error.InvalidRuntimeMagic`, `error.TopologyTooShort` |
| New interpreter errors | `error.InvalidMagic`, `error.UnsupportedVersion`, `error.TruncatedPayload` |
| Topology min payload size | 9 bytes (header only) |
| LEB128 max encoded value | 2^28 (4 bytes; `[5]u8` stack buffer is the upper bound) |
| Modules wired into `circ-compile` | `serializer` (= `lib/topology/serializer.zig`), `section_writer` (= `lib/topology/section_writer.zig`), `runtime_embed` (= `lib/topology/runtime_embed.zig`) |

## Known papercuts carried forward

- **`emit_main` is still imported in `cmd/circ-compile/main.zig`** for the `.emit_zig` branch only. Zig's `@import` is not conditional, so the import stays at the top. If `--emit-zig` is ever removed, `emit_main` and the entire `tests/helpers/wasm_run.zig` + `tests/harness/loader.js` harness can be deleted in lockstep.
- **Two test harnesses coexist.** `loader.js` calls `init()` directly (correct for `--emit-zig`-derived WASMs). New-pipeline WASMs require the `topology_alloc` + `init()` host protocol. There is no shared loader. If `--emit-zig` goes away, consolidate.
- **No programmatic root-pin ID helper from the CLI side.** The IDs are stable per circuit (assigned monotonically during expansion) but discovery is currently manual (via `--inspect` output or scanning `getOutputState(i)` for non-`undefined` returns). `serializer.serializeProjectFull` exposes the mapping in-tree; surface it as a CLI dump or a separate file alongside the `.wasm` if v1 needs it.
- **`circuit.zig` undefined-state semantics** are now load-bearing. AND gate returns `.undefined` only when neither input is `.low` and at least one is `.undefined`; `State.flip(.undefined) = .undefined`. Future gate primitives (XOR, NAND, NOR, XOR, XNOR if ever inlined into the runtime) must follow the same convention or the nested-builtin tests regress.
- **Custom section append assumes the runtime blob is unmodified.** `section_writer.combine` never rewrites or merges standard sections — appending only. If the runtime ever needs a second custom section, append it after `circ.topology`; never insert between standard sections.

## Decisions & specs that survived the plan

The archive captures the plan; the living specs stay where they are.

- `DOCS/decisions/compiler-pipeline.md` — the four current decisions (artifact shape, pipeline shape, IR shape, runtime distribution) reflect the post-plan world. Read this first when picking up the project cold.
- `DOCS/getting-started.md` — step 3 (compile description) and step 4 (Node example with host protocol) are the canonical user-facing reference for the new pipeline.
- `DOCS/wasm-api.md` — every export and import on the compiled artifact, including the introspection blob.
- `DOCS/circuit-format.md` — the `.circ` language reference (declarations, ports, anonymous components, built-ins).
- `DOCS/architecture.md`, `DOCS/simulation-engine.md` — design rationale and engine semantics; unchanged by this plan.
