# Phase 0 — Topology Serialization

> **Dependencies:** None — this is the first phase.
> **Warnings:** A langlang upgrade may shift IR shape (`lib/parser.c`, `lib/parser.h`, `lib/syntax/*`). Before starting, run `git log -- lib/parser.c lib/parser.h lib/syntax/` and check for in-flight changes; if an upgrade is imminent, prefer landing it first to avoid retargeting golden artifacts twice. The schema in this phase is defined against IR *semantic content*, not IR field names — a re-port should be confined to slice 2's translator code.

## Goal

After this phase, the existing `.circ` → WASM compile pipeline produces a `.wasm` artifact that carries two named topology payloads on a single version axis: `circ.topology.v0.min` (the existing placeholder blob, label-renamed only) and `circ.topology.v0.full` (a new WASM custom section containing the full circuit's components, connections, and macro-origin chains). A round-trip test compiles a fixture `.circ` containing primitives and a macro, reads the resulting `.wasm` from disk, walks its sections, decodes `circ.topology.v0.full`, and asserts byte-for-byte that every IR component (including macro-expanded ones) appears with matching id, kind, name, origin chain, and connections. No CLI surface ships in this phase; the renderer subcommand is Phase 1.

## Scope

**In scope:**
- Rename the placeholder string emitted as today's `topology_blob` from `"debug-paths-v1"` to `"circ.topology.v0.min"`. Mechanism (export `getTopology()` returning a static bytes buffer) is unchanged. No new bytes in the artifact from this slice.
- Extend the IR component records with a `macro_origin: []const MacroFrame` chain and thread it through `lib/syntax/translate.zig` and `lib/ir/resolver.zig` so that every gate produced by macro expansion carries the chain of macro instances that produced it (outermost first; nested macros append to the chain).
- Define the `circ.topology.v0.full` binary wire format (magic + version + components + connections), implement encoder and decoder as pure Zig functions over byte slices, including LEB128 varint helpers and length-prefixed UTF-8 strings.
- Append the encoded `circ.topology.v0.full` payload to the compiled `.wasm` as a WASM custom section, by post-processing the byte stream emitted by `zig build` and writing it back atomically to its output path.
- Round-trip integration test plus 10 focused unit tests (schema, encode, decode, section writer, IR-origin extension).

**Explicitly deferred:**
- The `preview` CLI subcommand — Phase 1.
- Any consumer of the `v0.full` payload beyond tests — Phases 1–3.
- A non-placeholder schema for `circ.topology.v0.min`. It stays a marker string; if it ever grows real content, that's a future `v1.min` (or whatever the next version axis names).
- `circ.topology.v0.full` carrying anything beyond components, connections, and macro-origin chains. Source spans, port-ordering hints, layout hints, etc. can be added in a `v1.full` revision when a consumer needs them.
- Any change to `lib/circuit.zig` (Layer 1 simulation engine) or to the runtime WASM ABI (the eight existing exports). These are inviolable per `DOCS/PLANS_PROMPT.md`'s architectural constraints.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---|---|---|
| `lib/topology/` | `schema.zig` | In-memory Zig types: `ComponentKind`, `MacroKind`, `MacroFrame`, `Component`, `Connection`, `Topology`. Comptime check that `ComponentKind` integer values match the runtime ABI table from `DOCS/wasm-api.md`. |
| `lib/topology/` | `encode.zig` | Serialize a `Topology` struct to bytes. LEB128 varint helpers, length-prefixed UTF-8 string writer, magic-and-version preamble. |
| `lib/topology/` | `decode.zig` | Hand-rolled byte-slice reader. Returns `Topology` or a typed error for bad magic / unknown version / truncated input. |
| `lib/topology/` | `wasm_section.zig` | Walk a `.wasm` byte buffer's section list; append a custom section with given name + payload at the tail; locate a named custom section in an existing buffer. Pure byte manipulation; no WASM runtime is invoked. |
| `tests/` | `topology_roundtrip.zig` | Slice-3 and slice-4 unit tests plus the slice-4 end-to-end integration test. |
| `tests/fixtures/topology/` | `primitives.circ` | Fixture: only `input` + `and`/`not`/`led`/`wire`. Verifies non-macro path. |
| `tests/fixtures/topology/` | `xor_macro.circ` | Fixture: contains a single `xor` macro. Verifies macro-origin chain emission. |
| `tests/fixtures/topology/` | `xnor_nested.circ` | Fixture: `xnor` (which expands through `xor`). Verifies nested origin chains. |

**Modified files:**

| Module/Package | File | Change |
|---|---|---|
| `lib/emit/` | `main.zig` | Slice 1: change the placeholder string `"debug-paths-v1"` → `"circ.topology.v0.min"`. Slice 4: after the compiler's `.wasm` is on disk, read it, call `topology.encode.encode(...)` against the IR, call `topology.wasm_section.append(...)`, write to `<path>.tmp`, `std.fs.rename` to final path. |
| `lib/ir/` | `types.zig` | Slice 2: add `macro_origin: []const MacroFrame` field to component records; define `MacroFrame { instance_name: []const u8, kind: MacroKind }`. |
| `lib/ir/` | `resolver.zig` | Slice 2: propagate `macro_origin` through resolution. Resolver-introduced gates inherit the origin of their producing macro instance. |
| `lib/syntax/` | `translate.zig` | Slice 2: when translating a macro instance into its expanded gate set, push a `MacroFrame { instance_name, kind }` onto the chain inherited from the enclosing context. Anonymous nested macros use `instance_name = ""`. |

**New dependencies:** None. Pure Zig stdlib (LEB128 varints, byte slicing, file I/O, `std.fs.rename`).

## Data & State

The schema below is the canonical definition. Any drift between this spec and `lib/topology/schema.zig` is a bug in the implementation, not a planning gap.

```zig
// lib/topology/schema.zig

pub const ComponentKind = enum(u8) {
    input_pin = 0,
    not_gate  = 1,
    led       = 2,
    and_gate  = 3,
    wire      = 4,
};
// Comptime assertion: these values must match the runtime ABI table in
// DOCS/wasm-api.md. The unit test `topology_schema_kind_values_match_runtime_abi`
// enforces this; if the runtime ABI changes, this enum must be updated in lockstep.

pub const MacroKind = enum(u8) {
    or_macro   = 0,
    nand_macro = 1,
    nor_macro  = 2,
    xor_macro  = 3,
    xnor_macro = 4,
};

pub const MacroFrame = struct {
    instance_name: []const u8, // source instance name; "" for anonymous nested macros
    kind:          MacroKind,
};

pub const Component = struct {
    id:           u32,                 // emit-order index; universal tie-breaker for layout
    kind:         ComponentKind,
    name:         []const u8,          // source instance name; "" for anonymous nested gates
    macro_origin: []const MacroFrame,  // outermost-first; empty for non-macro-expanded gates
};

pub const Connection = struct {
    src_id:   u32,
    src_port: u8, // 0 = "out"
    dst_id:   u32,
    dst_port: u8, // 1 = "in", 2 = "a", 3 = "b" (matches DOCS/wasm-api.md)
};

pub const Topology = struct {
    components:  []const Component,
    connections: []const Connection,
};
```

**Wire format (`circ.topology.v0.full` custom-section payload):**

All multi-byte integers are LEB128 unsigned varints. Strings are length-prefixed UTF-8 (LEB128 length + bytes).

```
magic              : 4 bytes ASCII "CTPL"
schema_ver         : varint = 0
num_components     : varint
component[]:
  id               : varint
  kind             : u8
  name_len         : varint
  name             : name_len bytes UTF-8
  origin_len       : varint
  origin_frame[]:
    instance_name_len : varint
    instance_name     : utf-8 bytes
    kind              : u8
num_connections    : varint
connection[]:
  src_id           : varint
  src_port         : u8
  dst_id           : varint
  dst_port         : u8
```

**Pre-1.0 schema discipline.** This format is freely revvable. Any incompatible change bumps the `v0` in the section name and resets `schema_ver`; do not introduce reserved fields, padding, or compat shims. The decoder must reject any non-zero `schema_ver` with a clear typed error.

**`circ.topology.v0.min` content.** Stays a placeholder string `"circ.topology.v0.min"` returned via the existing `getTopology()` export. Not a custom section. No structural payload.

## Execution & Concurrency Model

This phase is fully synchronous. No background goroutines/threads/workers are introduced. All work happens inline on the compiler's existing single-threaded path: parse → resolve → translate → emit Zig → `zig build` → post-process bytes → atomic rename. No shared state is introduced; no locks, channels, or queues.

## Persistence & I/O

The only I/O introduced by this phase is in slice 4. After the compiler's existing `zig build` step writes a `.wasm` to its output path, slice 4:

1. Reads the `.wasm` bytes from that path into memory.
2. Calls `topology.encode.encode(ir_topology)` to produce the payload.
3. Calls `topology.wasm_section.append(wasm_bytes, "circ.topology.v0.full", payload)` to produce a new byte buffer with the section appended.
4. Writes the new buffer to `<path>.tmp`.
5. Calls `std.fs.rename(<path>.tmp, <path>)` for an atomic replace.

If any step fails, the original `.wasm` at `<path>` is unchanged (the failure happens before rename) — no partial-write corruption is possible. The `.tmp` file may be left behind; cleanup is best-effort and the existing build's success/failure cleanup policy applies.

No external systems, no network I/O, no registry, no telemetry. Slice 1, slice 2, and slice 3 introduce zero I/O.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|---|---|---|
| 1 | `min` placeholder rename | One-line content change in `lib/emit/main.zig`: `"debug-paths-v1"` → `"circ.topology.v0.min"`. Mechanism (export `getTopology()` over static bytes) unchanged. | Existing emit tests still pass. New: a focused test that compiles a trivial `.circ`, calls `getTopology()` on the resulting module (or reads the static-bytes literal directly from emitted Zig source), and asserts the value is `"circ.topology.v0.min"`. |
| 2 | IR macro-provenance extension | `MacroFrame` and `macro_origin` field added to `lib/ir/types.zig`; `lib/ir/resolver.zig` propagates origin; `lib/syntax/translate.zig` pushes a frame for each macro instance during expansion (anonymous macros get `instance_name = ""`). Slice 3 cannot start until this lands. | `ir_macro_origin_xor`, `ir_macro_origin_nested_xnor`, `ir_macro_origin_empty_for_primitives` (see Tests). |
| 3 | `circ.topology.v0.full` schema, encoder, decoder | New `lib/topology/{schema,encode,decode}.zig`. No `.wasm` integration — just pure functions over byte slices. Comptime assertion of kind-value mirroring. | `topology_schema_kind_values_match_runtime_abi`, `topology_encode_empty` (golden bytes), `topology_encode_decode_roundtrip_simple`, `topology_encode_decode_roundtrip_with_macros`, `topology_decode_rejects_bad_magic`, `topology_decode_rejects_unknown_version`. |
| 4 | WASM custom-section append + emit integration | New `lib/topology/wasm_section.zig` (append + locate). `lib/emit/main.zig` calls encode + append + atomic rename after `zig build` finishes producing the `.wasm`. | `wasm_section_append_then_walk`, `wasm_section_preserves_existing_sections`, and the integration test `phase0_full_pipeline_roundtrip`. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test name | Module | What it asserts |
|---|---|---|
| `topology_schema_kind_values_match_runtime_abi` | `lib/topology/schema.zig` | Comptime check: `ComponentKind` integer values exactly match the table in `DOCS/wasm-api.md` (`input_pin=0, not_gate=1, led=2, and_gate=3, wire=4`). Build fails if they drift. |
| `topology_encode_empty` | `lib/topology/encode.zig` | A `Topology` with zero components and zero connections encodes to a literal byte sequence (magic `0x43 0x54 0x50 0x4C` + `0x00` version + `0x00` num_components + `0x00` num_connections). Locks the wire format. |
| `topology_encode_decode_roundtrip_simple` | `lib/topology/encode.zig` + `decode.zig` | Hand-construct a `Topology` (3 components, 2 connections, no macros). Encode. Decode. Assert structural equality. |
| `topology_encode_decode_roundtrip_with_macros` | same | Hand-construct a `Topology` where two components share `macro_origin = [{instance_name="combine", kind=.xor_macro}]`. Encode. Decode. Assert origin chains survive byte-identically. |
| `topology_decode_rejects_bad_magic` | `lib/topology/decode.zig` | Input whose first 4 bytes are not `"CTPL"` returns a typed error (e.g. `error.BadMagic`); does not panic. |
| `topology_decode_rejects_unknown_version` | `lib/topology/decode.zig` | Input with valid magic but `schema_ver != 0` returns `error.UnsupportedVersion`. |
| `wasm_section_append_then_walk` | `lib/topology/wasm_section.zig` | Take a minimal valid `.wasm` byte sequence, append a custom section named `"test.section"` with payload `[0xDE, 0xAD]`, walk the result, find the section, assert payload bytes match. |
| `wasm_section_preserves_existing_sections` | same | On a `.wasm` that already contains code/data sections, append a custom section. Confirm pre-existing sections are byte-identical and the appended section is the last one. |
| `ir_macro_origin_xor` | `lib/ir/` | Parse `xor combine (a = pin1.out, b = pin2.out)`, run resolution, assert every gate in the resulting IR carries `[{instance_name="combine", kind=.xor_macro}]` in `macro_origin`. |
| `ir_macro_origin_nested_xnor` | `lib/ir/` | Parse `xnor outer (...)` (which expands through `xor`). Assert nested gates carry `[{instance_name="outer", kind=.xnor_macro}, {instance_name="", kind=.xor_macro}]` chains. Verifies nesting and anonymous handling. |
| `ir_macro_origin_empty_for_primitives` | `lib/ir/` | Parse a circuit with only `and`/`not`/`led`/`wire`/input pins. Assert every IR gate has `macro_origin.len == 0`. Confirms the non-macro path is untouched. |

**Integration tests:**

| Test name | Scope | What it asserts |
|---|---|---|
| `phase0_full_pipeline_roundtrip` | `cmd/circ-compile` end-to-end | Compile `tests/fixtures/topology/xor_macro.circ` through the full pipeline. Read the emitted `.wasm` from disk. Walk its sections. Find `circ.topology.v0.full`. Decode. Assert: (a) component count matches the IR, (b) every IR component appears with matching id+kind+name, (c) every connection appears in the decoded set, (d) the `xor` macro's expanded gates carry the correct `[{instance_name="<fixture-name>", kind=.xor_macro}]` origin chain. |

Run command: `zig build test`

## Open Questions / Spikes

- TODO(phase0): Confirm during slice 1 that `getTopology()` is genuinely the only consumer of the placeholder string today. If anything else in `lib/emit/` or downstream tooling parses the literal `"debug-paths-v1"`, the rename has a wider blast radius than slice 1 assumes.
- TODO(phase0): Confirm during slice 2 that anonymous nested macros (`xnor` expanding through an unnamed inner `xor`) actually produce a `MacroFrame { instance_name = "" }` rather than being elided entirely by the existing translator. If translate.zig currently flattens anonymous expansions, the test `ir_macro_origin_nested_xnor` will need its expected chain adjusted, or the translator extended to surface them.
- TODO(phase0): Confirm during slice 4 that `zig build` writes its `.wasm` to a single, known path that `lib/emit/main.zig` can re-read. If the build pipeline streams bytes through memory rather than persisting to a known path, slice 4's read-modify-write approach needs to be re-cut as an in-memory pipeline integration.
