# Phase 1 — Preview Subcommand Skeleton

> **Dependencies:** Phase 0 complete. Specifically: `lib/topology/full_format.zig`, `lib/topology/full_serializer.zig` (with `buildFromProject` / `buildFromModule`), and `lib/topology/full_decoder.zig` are in place.
> **Warnings (post-Phase-0 review, 2026-05-06):** Two corrections from the original draft of this spec:
> - The plan-prompt phrasing "subcommand" was a planning artifact — the existing CLI is flag-based (`--inspect`, `--emit-zig`). Phase 1 ships a `--preview` *flag*, not a positional subcommand. Update `DOCS/PLANS_PROMPT.md` after this phase lands to replace "subcommand" with "flag" in the *What Is Being Built*, *Phase Index*, and *Architectural Constraints* sections so the corpus stays self-consistent.
> - The original spec described an encode-then-decode round-trip in memory (`topology.encode.encode → topology.decode.decode → dump`) and a `MacroFrame { instance_name, kind: MacroKind }` shape with a closed `MacroKind` enum. Phase 0 landed differently: macro provenance lives in the topology's `OriginFrame { alias, subcircuit, target_file }` (no enum — subcircuit is an open string), and the IR walk produces a `FullTopology` directly via `buildFromProject` / `buildFromModule` without needing the encode/decode round-trip. The data path simplifies accordingly.

## Goal

After this phase, a user running `circ-compile <foo.circ> --preview` sees a deterministic textual debug dump of the circuit's expanded topology written to stdout, with parse and resolution diagnostics (if any) on stderr. The dump lists every component (id, kind, source name, optional origin chain) and every connection (source/destination ids and decoded port names). The data path exercised is parse → resolve → translate → IR → `full_serializer.buildFromProject` (or `buildFromModule` for single-file inputs) → `preview.dump.dump`, entirely in memory: no `.wasm` is built, no `.zig` is emitted, no temp directory is touched. The phase ships no graphics, no layout logic, no ANSI color — only the textual dump that proves Phase 0's IR-walk produces a `FullTopology` consumable by a downstream renderer in Phase 2.

## Scope

**In scope:**
- New `Mode.preview` variant in `lib/cli/args.zig` and a `--preview` flag that selects it. Conflict checks: `--preview` is mutually exclusive with `--emit-zig` and `--inspect`; `-o` is rejected in preview mode (same rule as `--inspect`).
- New `lib/preview/dump.zig` exporting `pub fn dump(writer: anytype, topology: full_format.FullTopology) !void` — a pure formatting function over a `FullTopology` value (the same type Phase 0's `buildFromProject`/`buildFromModule` produce). Two-section output (header + Components table + Connections table). Deterministic ordering. No ANSI, no box-drawing.
- New preview branch in `cmd/circ-compile/main.zig`'s mode dispatch: parse → resolve → translate → `full_serializer.buildFromProject` (or `buildFromModule`) → `preview.dump.dump` → stdout.
- Widen `cmd/circ-compile/main.zig`'s existing `pub fn run() !u8` signature to `pub fn run(allocator, argv, stdout, stderr) !u8` so integration tests can drive the CLI in-process. The existing `main()` becomes a thin wrapper passing real argv and real streams.
- Three golden-file integration tests (one per existing fixture: primitives-only, single-macro, nested-macro) plus one negative test for the stderr/stdout split contract.

**Explicitly deferred:**
- Layout (`lib/preview/layout.zig`) — Phase 2.
- Glyph rendering and ANSI color (`lib/preview/render.zig`, `--color` flag, `--expand-macros` flag) — Phase 3.
- Reading topology from an on-disk `.wasm` artifact. Phase 1 calls `buildFromProject`/`buildFromModule` directly in memory; the on-disk decode path (parse WASM custom sections + `full_decoder.decode`) is already exercised by `tests/topology/full_emit_integration_test.zig` and by any future tooling that consumes a third-party `.wasm`.
- Pretty-printing diagnostics differently for preview mode. Diagnostics use the existing `printDiagnosticSet` path unchanged.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---|---|---|
| `lib/preview/` | `dump.zig` | `pub fn dump(writer: anytype, topology: full_format.FullTopology) !void`. Formats a `FullTopology` as the two-section debug dump. Pure function; no allocator owned, no I/O beyond the writer. |
| `tests/preview/` | `dump_test.zig` | Unit tests for `dump`. Hand-construct `FullTopology` values; capture into `ArrayList(u8)` writers; assert against literal expected strings. |
| `tests/preview/` | `cli_test.zig` | Integration tests. Drive `run(...)` in-process with synthetic argv and captured stdout/stderr. |
| `tests/fixtures/circuits/` | `builtin_xor.preview.golden`, `builtin_xnor.preview.golden`, `chain.preview.golden` (or another primitives-only fixture) | Locked dump text colocated with the existing source fixtures. |
| `tests/fixtures/circuits/` | `parse_error.circ` | Deliberately malformed `.circ` for the negative test (or reuse an existing diagnostics fixture under `tests/fixtures/circuits/E*.circ`). |

**Reused fixtures (no new source files needed):**

| Fixture | Path | Coverage |
|---|---|---|
| primitives-only | `tests/fixtures/circuits/chain.circ` (or similar — slice 4 picks) | Empty origin chains; verifies the "omit origin column when absent" rule. |
| single-macro | `tests/fixtures/circuits/builtin_xor.circ` | One-frame origin chain `g:xor`; verifies macro provenance survives the IR walk. |
| nested-macro | `tests/fixtures/circuits/builtin_xnor.circ` | Multi-frame origin chain (`xnor` expands through `xor` internally); verifies nested-frame rendering. |

**Modified files:**

| Module/Package | File | Change |
|---|---|---|
| `lib/cli/args.zig` | — | Add `Mode.preview` to the `Mode` enum. Parse `--preview`. Track `seen_preview` analogous to `seen_inspect` / `seen_emit_zig`. Return `error.ConflictingModes` if combined with either. Reject `-o` in preview mode at the appropriate validation point. |
| `cmd/circ-compile/main.zig` | — | Widen the existing `pub fn run() !u8` signature to `pub fn run(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8`. Existing `main()` keeps its current shape but calls `run` with `std.process.argsAlloc(...)`, `std.io.getStdOut().writer()`, and `std.io.getStdErr().writer()`. Add `args.mode == .preview` arm in the dispatch switch: invoke parse/resolve/translate (existing helpers), call `full_serializer.buildFromProject(allocator, &project)` (or `buildFromModule(allocator, &ir_module)` per `maybe_project`), call `preview.dump.dump(stdout, topology)`, then `topology.deinit(allocator)`. On parse/resolve errors, fall through the existing diagnostic path to stderr; return non-zero exit code. |

**New dependencies:** None. Pure Zig stdlib.

## Data & State

Phase 1 introduces zero new types. It consumes:

- `full_format.FullTopology { components: []FullComponentRecord, connections: []FullConnectionRecord }` from `lib/topology/full_format.zig` (Phase 0).
- `full_format.FullComponentRecord { id: u32, kind: ComponentKind, name: []const u8, origin: []const OriginFrame }`.
- `full_format.OriginFrame { alias: []const u8, subcircuit: []const u8, target_file: u32 }` — outermost-first chain. `alias` is the user's local instance name (e.g. `"g"` for `xor g(...)`); `subcircuit` is the imported subcircuit's alias (e.g. `"xor"`).
- `full_serializer.buildFromProject(allocator, project) !FullTopology` — Phase 0 slice 4 contract.
- `full_serializer.buildFromModule(allocator, module) !FullTopology` — Phase 0 slice 5 contract; errors on `sub_circuit_ref` (single-file no-import path).

The dump format is the only Phase-1-specific spec. Worked example for `tests/fixtures/circuits/builtin_xor.circ` (`input a, b` + `xor g(a=a, b=b)` + `output out(in=g.out)`):

```
Topology (v0.full)
  components: <N>
  connections: <M>

Components:
  [0] input_pin   "a"
  [1] input_pin   "b"
  [2] not_gate    "<inner>"    origin: g:xor
  [3] not_gate    "<inner>"    origin: g:xor
  [4] and_gate    "<inner>"    origin: g:xor
  ...
  [N-1] output_pin "out"

Connections:
  <src_id>.out -> <dst_id>.<port_name>
  ...
```

Concrete component count and per-component bytes are captured into goldens at slice 4 implementation time — the exact contents depend on the xor.circ macro source's internal naming, which the planner shouldn't speculate about. The format *rules* are locked here; the *literal output* is locked into the golden file when the test first runs.

Format rules (locked):

- **Header:** `Topology (v0.full)` then `  components: N` and `  connections: M`. Self-identifying when pasted into bug reports.
- **Components table:** sorted by `id` ascending. One row per component: `  [id] kind name [origin: chain]`.
  - `kind` is the snake_case enum name (`input_pin`, `not_gate`, `led`, `and_gate`, `wire`, `output_pin`) — the underlying enum variant from `full_format.ComponentKind`.
  - `name` is double-quoted; anonymous components render as `""` (faithful to `FullComponentRecord.name == ""`).
  - `origin:` column is **omitted entirely** when `origin.len == 0` (signals "no origin" by absence; subcircuit-expanded primitives are the exception, not the default).
  - For non-empty `origin`, frames are joined by ` > ` (with surrounding spaces, reads as "expanded into" left-to-right). Each frame renders as `alias:subcircuit`. Anonymous-alias frames render their `alias` as empty between separators (`g:xnor > :xor`).
  - **Note:** `target_file` is *not* rendered in the dump — it's an internal IR file index, not user-facing useful. Tests assert origin chain alias/subcircuit fields only.
- **Connections table:** in the order given by `topology.connections` (deterministic from Phase 0's emit-order). One row per connection: `  src_id.src_port_name -> dst_id.dst_port_name`.
  - `src_port` integer decodes via `full_format.PortName`: `out` is `3`.
  - `dst_port` integer decodes via `full_format.PortName`: `in`=`0`, `a`=`1`, `b`=`2`.

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
| 2 | `run(...)` signature widening | `cmd/circ-compile/main.zig`'s existing `pub fn run() !u8` is widened to `pub fn run(allocator, argv, stdout, stderr) !u8`. Existing `main()` is updated to call `run(...)` with `std.process.argsAlloc` plus the real stdout/stderr writers. No behaviour change for any existing mode — verified by the existing test suite remaining green. | All existing tests pass unchanged. New: a smoke test that calls `run(...)` with `--inspect` argv and captures stdout matches the previous behaviour byte-for-byte. |
| 3 | `preview.dump.dump` implementation | `lib/preview/dump.zig` with `pub fn dump(writer: anytype, topology: full_format.FullTopology) !void`. Implements the format spec exactly. Pure function; no allocator. | `preview_dump_primitives`, `preview_dump_with_origin`, `preview_dump_nested_origin`, `preview_dump_anonymous_component_name`, `preview_dump_port_decoding`, `preview_dump_deterministic_ordering` — all hand-construct `FullTopology` values, capture into `ArrayList(u8).writer()`, assert literal expected output. |
| 4 | CLI wiring + golden integration tests | Replace the slice-1 placeholder with the real preview branch: parse → resolve → translate → `full_serializer.buildFromProject` (or `buildFromModule`) → `preview.dump.dump` → stdout, plus `topology.deinit(allocator)`. Add the three golden integration tests and the parse-error negative test. Capture and check `tests/fixtures/circuits/*.preview.golden` files. | `phase1_preview_primitives_fixture`, `phase1_preview_xor_fixture`, `phase1_preview_xnor_fixture`, `phase1_preview_parse_error_to_stderr`. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test name | Module | What it asserts |
|---|---|---|
| `cli_args_parse_preview_flag` | `lib/cli/args.zig` | Parsing `circ-compile in.circ --preview` yields `Mode.preview`. |
| `cli_args_preview_rejects_emit_zig` | `lib/cli/args.zig` | `--preview --emit-zig` returns `error.ConflictingModes`. |
| `cli_args_preview_rejects_inspect` | `lib/cli/args.zig` | `--preview --inspect` returns `error.ConflictingModes`. |
| `cli_args_preview_rejects_output_path` | `lib/cli/args.zig` (or main-level validation) | `--preview -o out.wasm` is rejected with the same "usage error: -o is not valid in this mode" message used for `--inspect`. |
| `preview_dump_primitives` | `lib/preview/dump.zig` | Hand-constructed `FullTopology` with primitives only (no origin chains) renders to a literal expected string. Tests the "omit origin column when absent" rule. |
| `preview_dump_with_origin` | `lib/preview/dump.zig` | `FullTopology` with one one-frame origin chain renders the expanded gates with `origin: g:xor` suffix, omits the column on components whose `origin.len == 0`. |
| `preview_dump_nested_origin` | `lib/preview/dump.zig` | Two-frame origin chain (alias `g` of `xnor` containing an anonymous `xor` inner instance) renders `origin: g:xnor > :xor` with the correct ` > ` separator and an empty middle alias. |
| `preview_dump_anonymous_component_name` | `lib/preview/dump.zig` | Component with `name = ""` renders as `""` (not `<anon>` or omitted). |
| `preview_dump_port_decoding` | `lib/preview/dump.zig` | Connections with `dst_port = 0, 1, 2` decode to `in`, `a`, `b` (per `full_format.PortName`). `src_port = 3` decodes to `out`. |
| `preview_dump_deterministic_ordering` | `lib/preview/dump.zig` | Same `FullTopology` dumped twice yields byte-identical output. Components in id-ascending order; connections in input order. |

**Integration tests:**

| Test name | Scope | What it asserts |
|---|---|---|
| `phase1_preview_primitives_fixture` | `cmd/circ-compile` end-to-end via `run(...)` | Call `run(allocator, &[_][]const u8{ "circ-compile", "tests/fixtures/circuits/<primitives-only fixture>.circ", "--preview" }, stdout, stderr)`. Assert: stdout matches the colocated `*.preview.golden` byte-for-byte; stderr is empty; return value is 0. |
| `phase1_preview_xor_fixture` | same | Same shape, against `tests/fixtures/circuits/builtin_xor.circ` and `builtin_xor.preview.golden`. Verifies the IR-walk + dump path on a real parse including a single subcircuit instance. |
| `phase1_preview_xnor_fixture` | same | Same shape, against `tests/fixtures/circuits/builtin_xnor.circ` and `builtin_xnor.preview.golden`. Locks nested-origin rendering on a real parse (xnor.circ uses xor.circ internally). |
| `phase1_preview_parse_error_to_stderr` | same | Run preview on a parse-error fixture (existing `tests/fixtures/circuits/E*.circ` or a slice-4 minimal new fixture). Assert: stdout is empty; stderr contains the parse diagnostic (substring match for the diagnostic prefix); return value is non-zero. Locks the stream-split contract. |

Run command: `zig build test`

## Open Questions / Spikes

- TODO(phase1): During slice 4, confirm that the existing parse/resolve/translate helpers in `cmd/circ-compile/main.zig` are reachable as a shared sequence — or whether they're inlined in the `compile` / `inspect` / `emit_zig` arms. If inlined, slice 4 extracts a small helper before adding the preview arm. Avoids duplicating the parse-and-resolve sequence across four modes.
- TODO(phase1): During slice 1, decide whether `-o` in preview mode is rejected at parse time (`cli_args.parse` returns an error — the existing pattern is `args.zig:72` `if (args.mode != .inspect and args.output_path == null) return error.MissingOutput;` which would need extending to `if (args.mode != .inspect and args.mode != .preview ...)`), or at dispatch time (main.zig prints "usage error" and exits non-zero, matching the `--inspect` + `-o` rejection at `main.zig:105`). Keep symmetric with `--inspect`.
- TODO(phase1): During slice 4, decide what `circ-compile <primitives-only>.circ --preview` does for a fixture *without* any imports — must call `buildFromModule` (errors on `sub_circuit_ref`) versus `buildFromProject` (which needs a resolved `ir.Project`). The dispatch needs to mirror the existing `compile` arm's `maybe_project` switch. The fixture choice for `phase1_preview_primitives_fixture` may need to be a *project*-shape fixture (single root file with no imports compiles as a project still goes through `resolveBodies` even with empty `import_table`), or a true single-file path. Verify by running through the existing CLI dispatch.
- TODO(phase1): During slice 4, capture concrete component bytes for `builtin_xor.circ` and `builtin_xnor.circ` into goldens. The internal naming of primitives within the xor.circ / xnor.circ macro sources determines what shows up in the dump; the spec deliberately doesn't predict these so the goldens reflect the actual macro source rather than planner speculation.
- TODO(phase1): During slice 3, decide whether `dump`'s `kind` rendering uses the snake_case enum tag name (e.g. `not_gate`, via `@tagName`) or a curated short form (`not`, `and`, `pin`). Snake_case enum names are mechanical and free; curated names match Phase 3's intended visual style but lock the format earlier than needed. Default to `@tagName` unless slice-3 implementation reveals a problem.
