# Phase 1 — Preview Subcommand Skeleton

> **Dependencies:** Phase 0 (`lib/topology/{schema,encode,decode}.zig` and the IR `macro_origin` extension must be in place; `lib/topology/wasm_section.zig` is *not* required for Phase 1).
> **Warnings:** The plan-prompt phrasing "subcommand" was a planning artifact — the existing CLI is flag-based (`--inspect`, `--emit-zig`). Phase 1 ships a `--preview` *flag*, not a positional subcommand. Update `DOCS/PLANS_PROMPT.md` after this phase lands to replace "subcommand" with "flag" in the *What Is Being Built*, *Phase Index*, and *Architectural Constraints* sections so the corpus stays self-consistent.

## Goal

After this phase, a user running `circ-compile <foo.circ> --preview` sees a deterministic textual debug dump of the circuit's decoded topology written to stdout, with parse and resolution diagnostics (if any) on stderr. The dump lists every component (id, kind, source name, optional macro-origin chain) and every connection (source/destination ids and decoded port names). The data path exercised is parse → resolve → translate → IR → `topology.encode.encode` → `topology.decode.decode` → `preview.dump.dump`, entirely in memory: no `.wasm` is built, no `.zig` is emitted, no temp directory is touched. The phase ships no graphics, no layout logic, no ANSI color — only the textual dump that proves the encode/decode pipeline composes correctly with the IR and is consumable by a downstream renderer in Phase 2.

## Scope

**In scope:**
- New `Mode.preview` variant in `lib/cli/args.zig` and a `--preview` flag that selects it. Conflict checks: `--preview` is mutually exclusive with `--emit-zig` and `--inspect`; `-o` is rejected in preview mode (same rule as `--inspect`).
- New `lib/preview/dump.zig` exporting `pub fn dump(writer: anytype, topology: Topology) !void` — a pure formatting function over a decoded `Topology`. Two-section output (header + Components table + Connections table). Deterministic ordering. No ANSI, no box-drawing.
- New preview branch in `cmd/circ-compile/main.zig`'s mode dispatch: parse → resolve → translate → encode → decode → dump → stdout.
- Refactor `cmd/circ-compile/main.zig` to expose a callable `pub fn run(allocator, argv, stdout, stderr) !u8` so integration tests can drive the CLI in-process. The current `main()` becomes a thin wrapper.
- Three golden-file integration tests (one per Phase 0 fixture) plus one negative test for the stderr/stdout split contract.

**Explicitly deferred:**
- Layout (`lib/preview/layout.zig`) — Phase 2.
- Glyph rendering and ANSI color (`lib/preview/render.zig`, `--color` flag, `--expand-macros` flag) — Phase 3.
- Reading topology from an on-disk `.wasm` artifact. Phase 1 uses encode→decode entirely in memory; the on-disk path is exercised by Phase 0's `phase0_full_pipeline_roundtrip` test and by any future tooling that consumes a third-party `.wasm`.
- Pretty-printing diagnostics differently for preview mode. Diagnostics use the existing `printDiagnosticSet` path unchanged.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---|---|---|
| `lib/preview/` | `dump.zig` | `pub fn dump(writer: anytype, topology: Topology) !void`. Formats a decoded `Topology` as the two-section debug dump. Pure function; no allocator owned, no I/O beyond the writer. |
| `tests/` | `preview_dump.zig` | Unit tests for `dump`. Hand-construct `Topology` values; capture into `ArrayList(u8)` writers; assert against literal expected strings. |
| `tests/` | `preview_cli.zig` | Integration tests. Drive `run(...)` in-process with synthetic argv and captured stdout/stderr. |
| `tests/fixtures/topology/` | `primitives.preview.golden` | Locked dump text for `primitives.circ`. |
| `tests/fixtures/topology/` | `xor_macro.preview.golden` | Locked dump text for `xor_macro.circ`. |
| `tests/fixtures/topology/` | `xnor_nested.preview.golden` | Locked dump text for `xnor_nested.circ`. |
| `tests/fixtures/topology/` | `parse_error.circ` | Deliberately malformed `.circ` for the negative test. |

**Modified files:**

| Module/Package | File | Change |
|---|---|---|
| `lib/cli/args.zig` | — | Add `Mode.preview` to the `Mode` enum. Parse `--preview`. Track `seen_preview` analogous to `seen_inspect` / `seen_emit_zig`. Return `error.ConflictingModes` if combined with either. Reject `-o` in preview mode at the appropriate validation point. |
| `cmd/circ-compile/main.zig` | — | Factor body into `pub fn run(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8`. Existing `main()` calls `run` with real argv and real streams, returns its exit code. Add `args.mode == .preview` arm in the dispatch switch: invoke parse/resolve/translate (existing helpers), call `topology.encode.encode(allocator, ir_module)`, call `topology.decode.decode(allocator, encoded_bytes)`, call `preview.dump.dump(stdout_writer, decoded_topology)`. On parse/resolve errors, fall through the existing diagnostic path to stderr; return non-zero exit code. |

**New dependencies:** None. Pure Zig stdlib.

## Data & State

Phase 1 introduces zero new types. It consumes:

- `topology.schema.Topology` (and its constituent `Component`, `Connection`, `MacroFrame`, `ComponentKind`, `MacroKind`) — Phase 0.
- `topology.encode.encode(allocator, ir_module: ir.Module) ![]u8` — Phase 0 slice 3 contract; **note:** Phase 1 depends on this signature accepting an IR module, not just a `Topology`. Surface in the Phase 0 spec if not already explicit.
- `topology.decode.decode(allocator, bytes: []const u8) !Topology` — Phase 0 slice 3.

The dump format is the only Phase-1-specific spec. Worked example for `xor_macro.circ` (assuming `input pin1, pin2`, `xor combine (a = pin1.out, b = pin2.out)`, `led result (in = combine.out)`):

```
Topology (v0.full)
  components: 7
  connections: 6

Components:
  [0] input_pin   "pin1"
  [1] input_pin   "pin2"
  [2] not_gate    ""           origin: combine:xor_macro
  [3] not_gate    ""           origin: combine:xor_macro
  [4] and_gate    ""           origin: combine:xor_macro
  [5] and_gate    ""           origin: combine:xor_macro
  [6] led         "result"

Connections:
  0.out -> 2.in
  1.out -> 3.in
  0.out -> 4.a
  3.out -> 4.b
  2.out -> 5.a
  1.out -> 5.b
```

Format rules (locked):

- **Header:** `Topology (v0.full)` then `  components: N` and `  connections: M`. Confirms the version axis was decoded as expected; self-identifying when pasted into bug reports.
- **Components table:** sorted by `id` ascending. One row per component: `  [id] kind name [origin: chain]`.
  - `kind` is the snake_case enum name (`input_pin`, `not_gate`, `led`, `and_gate`, `wire`).
  - `name` is double-quoted; anonymous components render as `""` (faithful to schema).
  - `origin:` column is **omitted entirely** when `macro_origin.len == 0` (signals "no origin" by absence; macros are the exception, not the default).
  - For non-empty `macro_origin`, frames are joined by `>` (reads as "expanded into" left-to-right). Each frame renders as `instance_name:macro_kind`. Anonymous frames render their `instance_name` as empty between separators (`outer:xnor_macro>:xor_macro`).
- **Connections table:** in the order given by `topology.connections` (which is itself deterministic from Phase 0's emit-order index). One row per connection: `  src_id.src_port_name -> dst_id.dst_port_name`.
  - `src_port` integer is decoded to `out` (only valid value `0` today).
  - `dst_port` integer decoded to `in` (1), `a` (2), `b` (3).

No ANSI color, no box-drawing characters. This is a *debug* dump, not a *visual preview*; the schematic-styled output is Phase 3.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines/threads/workers are introduced. The data path is a straight-line sequence of synchronous calls inside the existing single-threaded CLI: parse → resolve → translate → encode → decode → dump → write-to-stdout. No shared state is introduced; no locks, channels, or queues.

## Persistence & I/O

Phase 1's I/O surface:

- **Input:** `.circ` source file at the path passed as positional argument. Read via the existing CLI file-load path used by `--inspect` and `--emit-zig` — no new I/O code added in this phase.
- **Output:** the dump text written to `stdout` via the writer passed into `preview.dump.dump`. CLI passes `std.io.getStdOut().writer()`; tests pass `std.ArrayList(u8).writer()` to capture.
- **Stream split (contractual):** the dump text goes to stdout; parse/resolve diagnostics go to stderr via the existing `printDiagnosticSet` path. Asserted by the negative integration test. This makes preview output safely pipeable (`circ-compile foo.circ --preview | grep led`).
- **No persistent artifacts written.** No `.wasm`, no `.zig`, no temp directory, no atomic-rename logic, no `--build-dir` interaction. Those are `--emit-zig` / default-compile concerns; `--preview` skips the entire emit-and-build pipeline.
- **No external systems.** No network, no registry, no telemetry.

This phase has no persistence or external I/O beyond what prior phases established.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|---|---|---|
| 1 | `--preview` flag plumbing | `Mode.preview` added to `lib/cli/args.zig`; `--preview` parsed; conflict checks against `--emit-zig` and `--inspect`; `-o` rejected in preview mode. No actual preview behaviour yet — a `Mode.preview` switch arm in `main.zig` is a temporary placeholder that returns "preview not implemented" on stderr and exits non-zero. | `cli_args_parse_preview_flag`, `cli_args_preview_rejects_emit_zig`, `cli_args_preview_rejects_inspect`, `cli_args_preview_rejects_output_path`. |
| 2 | `run(...)` refactor | `cmd/circ-compile/main.zig` body extracted into `pub fn run(allocator, argv, stdout, stderr) !u8`. Existing `main()` becomes a wrapper passing real argv and real streams. No behaviour change for any existing mode — verified by the existing test suite remaining green. | All existing tests pass unchanged. New: a smoke test that calls `run(...)` with `--inspect` argv and captures stdout matches the previous behaviour byte-for-byte. |
| 3 | `preview.dump.dump` implementation | `lib/preview/dump.zig` with `pub fn dump(writer: anytype, topology: Topology) !void`. Implements the format spec exactly. Pure function; no allocator. | `preview_dump_primitives`, `preview_dump_with_macro`, `preview_dump_nested_macro`, `preview_dump_anonymous_component_name`, `preview_dump_port_decoding`, `preview_dump_deterministic_ordering` — all hand-construct `Topology` values, capture into `ArrayList(u8).writer()`, assert literal expected output. |
| 4 | CLI wiring + golden integration tests | Replace the slice-1 placeholder with the real preview branch: parse → resolve → translate → encode → decode → dump → stdout. Add the three golden integration tests and the parse-error negative test. Capture and check `tests/fixtures/topology/*.preview.golden` files. | `phase1_preview_primitives_fixture`, `phase1_preview_xor_macro_fixture`, `phase1_preview_xnor_nested_fixture`, `phase1_preview_parse_error_to_stderr`. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test name | Module | What it asserts |
|---|---|---|
| `cli_args_parse_preview_flag` | `lib/cli/args.zig` | Parsing `circ-compile in.circ --preview` yields `Mode.preview`. |
| `cli_args_preview_rejects_emit_zig` | `lib/cli/args.zig` | `--preview --emit-zig` returns `error.ConflictingModes`. |
| `cli_args_preview_rejects_inspect` | `lib/cli/args.zig` | `--preview --inspect` returns `error.ConflictingModes`. |
| `cli_args_preview_rejects_output_path` | `lib/cli/args.zig` (or main-level validation) | `--preview -o out.wasm` is rejected with the same "usage error: -o is not valid in this mode" message used for `--inspect`. |
| `preview_dump_primitives` | `lib/preview/dump.zig` | Hand-constructed `Topology` with primitives only (no macros) renders to a literal expected string. Tests the "omit origin column when absent" rule. |
| `preview_dump_with_macro` | `lib/preview/dump.zig` | `Topology` with one `xor` macro (single-frame origin chain) renders the expanded gates with `origin: combine:xor_macro` suffix, omits the column on `pin1`/`led`. |
| `preview_dump_nested_macro` | `lib/preview/dump.zig` | Nested chain (anonymous `xor` inside `xnor outer`) renders `origin: outer:xnor_macro>:xor_macro` with the correct `>` separator and the empty middle frame name. |
| `preview_dump_anonymous_component_name` | `lib/preview/dump.zig` | Component with `name = ""` renders as `""` (not `<anon>` or omitted). |
| `preview_dump_port_decoding` | `lib/preview/dump.zig` | Connections with `dst_port = 1, 2, 3` decode to `in`, `a`, `b`. `src_port = 0` decodes to `out`. |
| `preview_dump_deterministic_ordering` | `lib/preview/dump.zig` | Same `Topology` dumped twice yields byte-identical output. Components in id-ascending order; connections in input order. |

**Integration tests:**

| Test name | Scope | What it asserts |
|---|---|---|
| `phase1_preview_primitives_fixture` | `cmd/circ-compile` end-to-end via `run(...)` | Call `run(allocator, &[_][]const u8{ "circ-compile", "tests/fixtures/topology/primitives.circ", "--preview" }, stdout, stderr)`. Assert: stdout matches `tests/fixtures/topology/primitives.preview.golden` byte-for-byte; stderr is empty; return value is 0. |
| `phase1_preview_xor_macro_fixture` | same | Same shape, against `xor_macro.circ` and `xor_macro.preview.golden`. Verifies encode→decode→dump on a real parse including a macro. |
| `phase1_preview_xnor_nested_fixture` | same | Same shape, against `xnor_nested.circ` and `xnor_nested.preview.golden`. Locks nested-origin rendering on a real parse. |
| `phase1_preview_parse_error_to_stderr` | same | Run preview on `parse_error.circ`. Assert: stdout is empty; stderr contains the parse diagnostic (substring match for the diagnostic prefix); return value is non-zero. Locks the stream-split contract. |

Run command: `zig build test`

## Open Questions / Spikes

- TODO(phase1): Confirm during slice 3 that `topology.encode.encode`'s signature accepts an IR module directly (i.e. the caller hands it the IR and the encoder walks it to produce `Topology` + bytes) versus requiring the caller to construct a `Topology` first. The Phase 0 spec describes encode as taking a `Topology`; Phase 1 needs the IR-walking step somewhere. If Phase 0's encoder doesn't include the IR walk, Phase 1 introduces a small `lib/topology/from_ir.zig` helper to build a `Topology` from an IR module before encoding. Resolve in slice 3 by reading the Phase 0 implementation; do not pre-decide.
- TODO(phase1): Confirm during slice 4 that the existing parse/resolve/translate helpers in `cmd/circ-compile/main.zig` are reachable as a shared sequence — or whether they're inlined in the `compile` / `inspect` arms. If inlined, slice 4 extracts a small `prepareIrModule(allocator, source) !ir.Module` helper before adding the preview arm. Avoids duplicating the parse-and-resolve sequence across three modes.
- TODO(phase1): Decide during slice 1 whether `-o` in preview mode is rejected at parse time (`cli_args.parse` returns an error) or at dispatch time (main.zig prints "usage error" and exits non-zero), matching wherever `--inspect`'s `-o` rejection currently lives. Keep symmetric with `--inspect`.
