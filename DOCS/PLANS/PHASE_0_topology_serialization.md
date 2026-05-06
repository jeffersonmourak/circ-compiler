# Phase 0 — Topology Serialization

> **Dependencies:** None — this is the first phase.
> **Warnings:** This spec was rewritten on 2026-05-06 after slice 1 committed. The original spec mis-modelled where macro expansion happens (assumed: IR; reality: serializer at serialization time) and wrongly conflated the runtime `topology_blob` placeholder string with the offline `circ.topology` custom section. The rewrite lands these decisions against the actual codebase. Slice 1's commit (`04422b4`) is retained but reframed below — it cleared up the placeholder marker but did not rename the custom section, which is what the original "min" rename intent referred to. The user's intent (separate `min` and `full` variants on a versioned axis) is preserved; the implementation strategy is rebuilt from the codebase as it actually exists.

## Existing Codebase Context (read this before slicing)

The codebase already contains substantial topology infrastructure that pre-dates this initiative. Phase 0's job is **not** to build that infrastructure from scratch but to extend it with renderer-facing fields and partition it onto the `circ.topology.v0.{min,full}` naming axis.

- **`lib/topology/format.zig`** defines today's wire format: magic `CIRC`, version `0x01`, `ComponentRecord{ id: u32, kind: u8 }`, `ConnectionRecord{ from_id: u32, to_id: u32, port: u8 }`, plus `ComponentKind` and `PortName` enums.
- **`lib/topology/serializer.zig`** has two entry points: `serializeModule(allocator, module)` (errors on `sub_circuit_ref`) and `serializeProjectFull(allocator, project)` (recursively expands every `sub_circuit_ref` into the referenced module's primitives, assigns fresh global IDs across the entire project tree, and emits a single flat primitive-only payload). Boundary connections (root inputs, sub-inputs, sub-outputs) are rewritten to use the global ID space.
- **`lib/topology/section_writer.zig`** appends a `circ.topology` (literal name today) WASM custom section to a runtime WASM byte stream. It includes LEB128 helpers, magic-and-version validation, and atomic byte assembly. The section name is a single hard-coded constant `SECTION_NAME = "circ.topology"`.
- **`cmd/circ-compile/main.zig:228–245`** calls `serializer.serializeProject` (or `serializeModule` for single-file inputs) and `section_writer.combine` during compile, so produced `.wasm` artifacts already carry the topology section.
- **`topology_blob` / `getTopology()`** in `lib/emit/main.zig:59` and `lib/emit/runtime.zig:158` is an *unrelated* runtime export: a static string baked into the *runtime WASM* and returned by `getTopology()` for a JS host. Today its content is the placeholder string `"circ.topology.v0.min"` (renamed from `"debug-paths-v1"` by slice 1).
- **Macros** (`or`, `nand`, `nor`, `xor`, `xnor`) live as embedded `.circ` source files under `lib/resolver/builtin_circ/`. They become `sub_circuit_ref` components in the IR, *not* inlined gate clusters. The flattening that produces a primitive-only graph happens only in `serializeProjectFull`.

## Goal

After this phase, every `.wasm` artifact produced by `circ-compile` carries two named topology custom sections sharing the `circ.topology.v0.*` versioned axis: **`circ.topology.v0.min`** (today's flat primitive payload — id, kind, connections — byte-equivalent to the existing `circ.topology` content) and **`circ.topology.v0.full`** (a new payload that additionally carries per-component instance names and per-component subcircuit-origin chains tracking the path from the root module's source to each expanded primitive). A hand-rolled reader for the `full` payload exists in-tree and a round-trip test compiles a fixture `.circ` that uses subcircuits, reads the resulting `.wasm` bytes from disk, walks its custom sections, decodes `circ.topology.v0.full`, and asserts that every primitive present in the flat expansion appears with the expected name and origin chain. The IR and the runtime WASM ABI are not modified. No CLI surface ships in this phase; the renderer subcommand is Phase 1.

## Scope

**In scope:**
- Slice 1 (already committed as `04422b4`): rename of the runtime `topology_blob` placeholder string from `"debug-paths-v1"` to `"circ.topology.v0.min"`. Reframed below — useful cleanup, but does not by itself accomplish the "min" intent.
- Rename the existing custom-section name from `"circ.topology"` to `"circ.topology.v0.min"` in `lib/topology/section_writer.zig`. Content of the section bytes is unchanged.
- Design the `circ.topology.v0.full` payload: extend or parallel today's format with `name` (length-prefixed UTF-8 string) per component and an `origin` chain (length-prefixed list of frames, each frame = subcircuit alias + module file_id) per component.
- Implement a full-payload serializer that walks `Project` like `serializeProjectFull` but records the active subcircuit-call stack and writes it onto each emitted primitive's record. The instance name source-of-truth is `ir.Component.instance_name` for user-written components; for components from inside an expanded subcircuit, the name is the subcircuit's local instance name plus the call chain encoded in `origin`.
- Implement a hand-rolled decoder for the full payload that returns a Zig struct `Topology` consumable by tests and (later) by the renderer.
- Wire the full serializer into `cmd/circ-compile/main.zig` so `circ.topology.v0.full` is appended alongside `min` to every produced `.wasm`.
- Update `lib/topology/section_writer.combine` (or factor it) so two custom sections can be appended to one runtime WASM: `circ.topology.v0.min` first, `circ.topology.v0.full` second.
- Round-trip integration test plus unit tests for: schema constants stability, full-encode/full-decode round-trip on a hand-built structure, full-decode error paths (bad magic, unknown version), origin-chain correctness on a subcircuit-using fixture.

**Explicitly deferred:**
- The `--preview` subcommand or any consumer of the `full` payload beyond tests — Phase 1.
- Any change to today's `serializeModule` / `serializeProjectFull` (the `min`-payload producers). Slice 2's section rename is the only modification to existing behaviour around `min`.
- Removing today's `topology_blob` runtime export. It stays in place; it is a separate consumer-pattern (runtime introspection from a JS host) that this initiative does not attempt to unify with the offline custom section.
- Migrating the existing format's magic/version (`CIRC` / `0x01`) to a different choice. The `min` payload's bytes do not change in this phase; only its section name does.
- Compatibility shims for tools reading the old `circ.topology` section name. Per the user's pre-1.0 stance, the rename is a clean break.
- Any change to `lib/circuit.zig` (Layer 1 simulation engine) or the runtime WASM ABI.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---|---|---|
| `lib/topology/` | `full_format.zig` | Wire format constants for `circ.topology.v0.full`: magic, version, schema for `name`/`origin` extensions. Plus the in-memory Zig types (`FullComponentRecord`, `OriginFrame`, `FullTopology`) consumed by tests and (later) the renderer. |
| `lib/topology/` | `full_serializer.zig` | Walks `ir.Project` mirroring `serializeProjectFull`'s expansion logic but threads the origin-chain stack through recursion. Produces a `circ.topology.v0.full` payload as `[]u8`. |
| `lib/topology/` | `full_decoder.zig` | Hand-rolled byte-slice reader. Returns a `FullTopology` or a typed error for bad magic / unknown version / truncated input. Used by tests; will later be used by the preview subcommand. |
| `tests/topology/` | `full_roundtrip_test.zig` | Slice-3 / slice-4 unit tests plus the slice-5 end-to-end integration test. |

**Modified files:**

| Module/Package | File | Change |
|---|---|---|
| `lib/topology/section_writer.zig` | — | Slice 2: change `SECTION_NAME` from `"circ.topology"` to `"circ.topology.v0.min"`. Slice 5: add a second entry point `combineTwo(allocator, runtime_wasm, min_payload, full_payload) ![]u8` that appends both custom sections. |
| `cmd/circ-compile/main.zig` | — | Slice 5: in addition to the existing `serializer.serializeProject(...)` + `section_writer.combine(...)`, also call `full_serializer.serializeProjectFull(...)` and use `combineTwo(...)` so both sections land in the produced `.wasm`. |
| Any test that grepped or asserted on the literal section name `"circ.topology"` | — | Slice 2: update the literal to `"circ.topology.v0.min"`. Discovered at slice time by `grep -rn '"circ.topology"' lib/ tests/`. |

**New dependencies:** None. Pure Zig stdlib.

## Data & State

**Existing types (unchanged in Phase 0):**

```zig
// lib/topology/format.zig — already exists
pub const MAGIC: [4]u8 = .{ 'C', 'I', 'R', 'C' };
pub const VERSION: u8 = 0x01;
pub const ComponentKind = enum(u8) { input_pin, not_gate, and_gate, wire, led, output_pin };
pub const PortName     = enum(u8) { in, a, b, out };
pub const ComponentRecord  = extern struct { id: u32, kind: u8 };
pub const ConnectionRecord = extern struct { from_id: u32, to_id: u32, port: u8 };
```

**New types (`lib/topology/full_format.zig`):**

```zig
pub const FULL_MAGIC: [4]u8 = .{ 'C', 'I', 'R', 'F' };  // distinct from CIRC; signals "full" payload variant
pub const FULL_VERSION: u8 = 0x01;

pub const OriginFrame = struct {
    alias:        []const u8,  // local instance name in the parent module (e.g. "combine")
    subcircuit:   []const u8,  // alias of the imported subcircuit (e.g. "xor")
    target_file:  u32,         // ir.FileId of the imported module
};

pub const FullComponentRecord = struct {
    id:     u32,                       // global ID matching the corresponding min-payload entry
    kind:   ComponentKind,             // mirrors min payload
    name:   []const u8,                // ir.Component.instance_name (or the subcircuit instance name when emitted from inside an expansion)
    origin: []const OriginFrame,       // outermost-first; empty for components written directly in the root module
};

pub const FullConnectionRecord = ConnectionRecord;  // reuse existing layout — connections need no new info

pub const FullTopology = struct {
    components:  []const FullComponentRecord,
    connections: []const FullConnectionRecord,
};
```

**Wire format (`circ.topology.v0.full` custom-section payload):**

All multi-byte integers little-endian; strings length-prefixed (u32 length + UTF-8 bytes); origin lists length-prefixed (u32 frame count).

```
magic              : 4 bytes ASCII "CIRF"
schema_ver         : 1 byte = 0x01
num_components     : u32 LE
component[]:
  id               : u32 LE
  kind             : u8
  name_len         : u32 LE
  name             : name_len bytes UTF-8
  origin_len       : u32 LE
  origin_frame[]:
    alias_len       : u32 LE
    alias           : alias_len bytes UTF-8
    subcircuit_len  : u32 LE
    subcircuit      : subcircuit_len bytes UTF-8
    target_file     : u32 LE
num_connections    : u32 LE
connection[]:
  from_id          : u32 LE
  to_id            : u32 LE
  port             : u8
```

**Pre-1.0 schema discipline.** The format is freely revvable; bump `FULL_VERSION` and update both encoder and decoder in one commit when the schema changes incompatibly. Do not add reserved fields or compat shims. The decoder rejects unknown versions with a typed error.

**Determinism contract.** Component-emission order in `full` exactly matches `min` (both use the global-id assignment order from the recursive expansion in `serializeProjectFull`). Connection-emission order also matches. A reader that parses both sections and zips them by index gets correctly paired records.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines/threads/workers are introduced. All allocation flows through caller-supplied allocators (matching today's `serializeProjectFull` pattern). The full serializer's recursive expansion uses the same call-stack-driven traversal as today's serializer — there is no parallelism opportunity, and introducing one would complicate determinism.

## Persistence & I/O

The only I/O introduced by this phase is in slice 5, which extends the existing CLI emit path. After `cmd/circ-compile/main.zig` produces a runtime WASM and the `min` topology payload, it now also produces the `full` payload and calls `combineTwo(...)` to append both custom sections to the output bytes. The existing atomic write semantics (whatever they are today — slice 5 must verify, not assume) carry through. No new file paths are introduced. No external systems, no network.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. Slice 1 is already committed (`04422b4`); slices 2–5 are new work.

| # | Slice Title | Deliverable | Test Proof |
|---|---|---|---|
| 1 | (DONE — `04422b4`) Runtime placeholder marker rename | `topology_blob` content changed from `"debug-paths-v1"` to `"circ.topology.v0.min"` in `lib/emit/main.zig` and `lib/emit/project.zig`; 9 expected-zig fixtures updated in lockstep. **Reframing note:** this is a clarifying rename of an unrelated runtime export, not the section rename the original spec described. The actual section rename is slice 2. | Existing `full_emitter_fixture_files` tests pass; new `emit topology_blob marker is circ.topology.v0.min` test added. |
| 2 | Custom-section rename: `circ.topology` → `circ.topology.v0.min` | One-line constant change in `lib/topology/section_writer.zig` (`SECTION_NAME`). Plus updates to any test or doc that grepped the old literal. Section payload bytes unchanged. | Run `grep -rn '"circ.topology"' lib/ tests/ cmd/` before and after; diff is exactly the renamed sites. Existing section_writer tests updated to assert the new name; an integration test reads a freshly compiled `.wasm` and asserts the section name is `circ.topology.v0.min`. |
| 3 | `circ.topology.v0.full` schema + encoder + decoder (pure functions, no IR walk yet) | `lib/topology/full_format.zig` (types + magic/version constants). `lib/topology/full_serializer.zig` exposes `pub fn encode(allocator, topology: FullTopology) ![]u8` operating over a hand-built struct (no IR walk yet). `lib/topology/full_decoder.zig` exposes `pub fn decode(allocator, bytes: []const u8) !FullTopology`. | Unit tests: `full_format_constants_stable` (magic/version are exact bytes), `full_encode_empty` (zero-component, zero-connection topology produces a known minimal byte sequence — golden bytes), `full_encode_decode_roundtrip_simple` (3 components, 2 connections, no origin), `full_encode_decode_roundtrip_with_origin` (origin chains survive byte-identically, including nesting), `full_decode_rejects_bad_magic`, `full_decode_rejects_unknown_version`. |
| 4 | `circ.topology.v0.full` IR-walk serializer | `lib/topology/full_serializer.zig` gains `pub fn serializeProjectFull(allocator, project: *const ir.Project) ![]u8`. Mirrors today's `serializer.serializeProjectFull` recursion but threads an `OriginFrame` stack and records names. The two project serializers (`min` and `full`) share global-id assignment so their components correspond by index. | Unit tests: `full_walk_primitives_have_empty_origin` (a project with no subcircuits produces zero-frame origin chains and component names matching `instance_name`), `full_walk_one_subcircuit_records_origin` (a project where root uses one subcircuit produces components with a one-frame origin chain), `full_walk_nested_subcircuits` (subcircuits nesting two deep produce correctly-ordered origin chains). |
| 5 | Two-section emit + end-to-end round-trip | `lib/topology/section_writer.zig` gains `combineTwo(...)`. `cmd/circ-compile/main.zig` calls the new full serializer and `combineTwo` so both sections land in the produced `.wasm`. | Integration test: compile `tests/fixtures/circuits/<a fixture using a subcircuit>.circ` through the full CLI path, read the resulting `.wasm` from disk, walk its custom sections, find both `circ.topology.v0.min` and `circ.topology.v0.full`, decode `full`, assert (a) component count matches `min`, (b) every component has a non-empty `name`, (c) at least one component carries a non-empty `origin` chain referencing the subcircuit alias, (d) connections array byte-matches `min`'s connections. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test name | Module | What it asserts |
|---|---|---|
| (existing — preserved) `full emitter fixture files` | `tests/emit/full_emit_test.zig` | Existing emit goldens still pass after slice 1's marker rename. Confirms slice 1 didn't break anything. |
| (existing — preserved) `emit topology_blob marker is circ.topology.v0.min` | `tests/emit/full_emit_test.zig` | Marker is greppable and reachable from emit. |
| `section_writer_uses_v0_min_name` | `tests/topology/section_writer_test.zig` (or wherever existing tests live) | After slice 2: emitted custom section's name in the produced WASM bytes is `circ.topology.v0.min`. |
| `full_format_constants_stable` | `lib/topology/full_format.zig` | Comptime check: `FULL_MAGIC == "CIRF"`, `FULL_VERSION == 0x01`. Build fails if either drifts. |
| `full_encode_empty` | `lib/topology/full_serializer.zig` | A `FullTopology` with zero components and zero connections encodes to a literal byte sequence (`'C''I''R''F' 0x01 0x00000000 0x00000000`). Locks the wire format. |
| `full_encode_decode_roundtrip_simple` | `full_serializer.zig` + `full_decoder.zig` | Hand-construct a `FullTopology` with 3 named components and 2 connections, no origin. Encode. Decode. Assert structural equality including names. |
| `full_encode_decode_roundtrip_with_origin` | same | Hand-construct a `FullTopology` where two components share a one-frame origin and one component has a two-frame origin. Encode. Decode. Assert origin chains survive byte-identically including alias, subcircuit, and target_file fields. |
| `full_decode_rejects_bad_magic` | `full_decoder.zig` | Input whose first 4 bytes are not `"CIRF"` returns `error.BadMagic`; does not panic. |
| `full_decode_rejects_unknown_version` | `full_decoder.zig` | Input with valid magic but `schema_ver != 1` returns `error.UnsupportedVersion`. |
| `full_walk_primitives_have_empty_origin` | `full_serializer.zig` | A project with no subcircuits produces components whose `origin.len == 0` and whose `name` equals the IR `instance_name`. |
| `full_walk_one_subcircuit_records_origin` | `full_serializer.zig` | A project where the root module uses one subcircuit produces components for the subcircuit's primitives with origin = one frame `{ alias, subcircuit, target_file }` matching the import. |
| `full_walk_nested_subcircuits` | `full_serializer.zig` | A subcircuit whose body uses another subcircuit produces components two levels deep with two-frame origin chains, outermost-first. |

**Integration tests:**

| Test name | Scope | What it asserts |
|---|---|---|
| `phase0_full_pipeline_roundtrip` | `cmd/circ-compile` end-to-end | Compile a fixture `.circ` (one that uses a subcircuit — likely `tests/fixtures/circuits/projects/and_pair/main.circ` or similar from existing fixtures) through the full pipeline. Read the emitted `.wasm` from disk. Walk its custom sections. Find both `circ.topology.v0.min` and `circ.topology.v0.full`. Decode `full`. Assert: (a) `full.components.len == min.components.len`, (b) every component has `name.len > 0`, (c) at least one component carries `origin.len > 0` referencing the subcircuit alias, (d) `full.connections` byte-matches `min.connections`. |

Run command: `zig build test`

## Open Questions / Spikes

- TODO(phase0): During slice 2, after grepping for `"circ.topology"` literal, audit each hit. Some may be doc-text references that should be updated to `circ.topology.v0.min` (or replaced with the more general `circ.topology.v0.*` family name, depending on context). Use judgment per-site.
- TODO(phase0): During slice 4, decide how the full serializer shares state with the existing `serializer.serializeProjectFull` for global-id assignment. Two viable approaches: (a) refactor existing serializer to expose its expansion as a generic `expandProject(visitor)` that both `min` and `full` consume; (b) keep them parallel and document that they must produce identical id sequences (maintenance burden but lower-risk diff). (a) is cleaner; (b) is faster to land. Resolve at slice time based on how much of `serializer.zig` (494 lines) is intertwined with payload writing.
- TODO(phase0): During slice 5, verify whether any *existing* consumer of the WASM artifact (downstream tooling, simulator, browser SDK) parses the section name `circ.topology` literally. If so, the slice-2 rename has a wider blast radius than `lib/`/`tests/`/`cmd/` and an out-of-tree compatibility note may be needed. The user's pre-1.0 stance applies, but consumers should be flagged before they discover the rename in the wild. Run `git log -- lib/topology/section_writer.zig` and inspect commit messages for hints about external consumers.
- TODO(phase0): Slice 1 was already committed under a misleading framing. Add a follow-up note in `DOCS/STATUS.md` (during slice 2) clarifying that slice 1's commit performed an unrelated cleanup that's still useful but does not by itself accomplish the "min" rename intent — slice 2 does. This avoids future confusion when someone reads the STATUS file and tries to map slice numbers to commits.
- TODO(phase0): During slice 3, if the encoder's signature ends up wanting an arena (because origin chains need short-lived intermediate allocations during encoding), pass it as a separate parameter rather than promoting to a struct of options. Keep encode/decode signatures minimal until a real consumer needs more.
