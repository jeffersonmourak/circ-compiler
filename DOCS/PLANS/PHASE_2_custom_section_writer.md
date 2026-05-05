# Phase 2 — Custom Section Writer

> **Dependencies:** Phase 0 (runtime blob in `lib/topology/runtime_embed.zig`; host protocol documented), Phase 1 (`lib/topology/serializer.zig` producing valid `circ.topology` payloads)
> **Warnings:** The custom section must be appended after all standard WASM sections. Never insert it between standard sections — doing so produces a malformed module. The runtime blob from Phase 0 is already a complete, valid WASM binary; do not modify any of its bytes.

## Goal

Once this phase is complete, calling `section_writer.combine(allocator, runtime_wasm, topology_payload)` returns a `[]u8` that is a structurally valid WASM module containing the runtime and the `circ.topology` custom section. `WebAssembly.validate()` passes on the result, and instantiating it in Node using the Phase 0 host protocol produces correct simulation output for all fixtures in `tests/fixtures/circuits/` and `tests/fixtures/projects/`.

## Scope

**In scope:**
- `lib/topology/section_writer.zig` with one public function: `combine(allocator, runtime_wasm, topology_payload) ![]u8`
- A minimal LEB128 unsigned integer encoder (only needs to encode values up to the size of the topology payload, so a general-purpose implementation is not required — a bounded loop is enough)
- Unit tests verifying the custom section byte structure
- Integration tests: `WebAssembly.validate()` + full behavioral fixture tests via Node

**Explicitly deferred:**
- Wiring `combine` into `cmd/circ-compile/main.zig` (Phase 3)
- Deletion of the old orchestrator path (Phase 4)
- TypeScript SDK update (Phase 4)

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|----------------|------|----------------|
| topology | `lib/topology/section_writer.zig` | Encodes the `circ.topology` payload as a WASM custom section and appends it to the runtime blob |

**Modified files:** None. This phase is purely additive.

**New dependencies:** None.

## Data & State

### Public API

```zig
pub fn combine(
    allocator: std.mem.Allocator,
    runtime_wasm: []const u8,
    topology_payload: []const u8,
) ![]u8
```

Returns a heap-allocated `[]u8` owned by the caller. The bytes are:

```
runtime_wasm bytes (unchanged)
custom section:
  [1 byte]  0x00                        — custom section id
  [N bytes] LEB128(section_body_length) — total bytes of name + payload
  [1 byte]  0x0D                        — name length (13 = len("circ.topology"))
  [13 bytes] "circ.topology"
  [M bytes] topology_payload
```

`section_body_length = 1 + 13 + topology_payload.len` (name-length byte + name + payload).

### LEB128 encoder (internal)

Encodes an unsigned integer as a WASM LEB128 variable-length integer into a fixed-size stack buffer. Only values up to `2^28` (268 MB) need to be supported — any topology larger than that is a serializer error, not a section writer concern.

```zig
fn writeLeb128(buf: *[5]u8, value: u32) u3 {
    // returns number of bytes written (1–5)
}
```

### Invariants

- The first 8 bytes of `runtime_wasm` must be the WASM magic (`\0asm`) and version (`\x01\x00\x00\x00`). The writer asserts this in debug builds and returns `error.InvalidRuntimeMagic` in release builds.
- `topology_payload.len` must be at least 9 bytes (minimum valid header). Returns `error.TopologyTooShort` otherwise.
- The function never modifies `runtime_wasm` or `topology_payload`.

## Execution & Concurrency Model

This phase is fully synchronous. `combine` allocates once (`runtime_wasm.len + section_overhead + topology_payload.len` bytes), copies the bytes, and returns. No background work, no shared state.

## Persistence & I/O

`combine` operates entirely in memory. No files are read or written. The integration tests write the combined bytes to a temp file to drive Node — that I/O is in the test harness, not the section writer.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Section writer + unit tests | `lib/topology/section_writer.zig` with `combine` and the LEB128 encoder; unit tests verify byte structure for known inputs | Unit tests green; a known-small topology payload produces a byte-exact output checked against a hand-computed expected buffer |
| 2 | Integration tests | `WebAssembly.validate()` passes on the combined output for every fixture; Node behavioral assertions match the current pipeline output | `zig build test` green for all circuits and project fixtures |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|-----------------|
| `test "section_writer: custom section bytes are correct"` | `lib/topology/section_writer.zig` | `combine` with a 4-byte dummy payload produces a buffer whose trailing bytes match the hand-computed custom section encoding: `[0x00, section_len_leb..., 0x0D, 'c','i','r','c','.','t','o','p','o','l','o','g','y', payload...]` |
| `test "section_writer: runtime bytes are preserved verbatim"` | `lib/topology/section_writer.zig` | The leading `runtime_wasm.len` bytes of the output equal `runtime_wasm` byte-for-byte |
| `test "section_writer: leb128 single byte"` | `lib/topology/section_writer.zig` | Values 0–127 encode as exactly 1 byte |
| `test "section_writer: leb128 multi byte"` | `lib/topology/section_writer.zig` | Value 128 encodes as `[0x80, 0x01]`; value 16383 encodes as `[0xFF, 0x7F]` |
| `test "section_writer: rejects invalid runtime magic"` | `lib/topology/section_writer.zig` | Passing a non-WASM byte slice as `runtime_wasm` returns `error.InvalidRuntimeMagic` |
| `test "section_writer: rejects short topology"` | `lib/topology/section_writer.zig` | A `topology_payload` shorter than 9 bytes returns `error.TopologyTooShort` |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| `test "phase2: combined wasm is structurally valid"` | `tests/` | For each fixture, `WebAssembly.validate()` returns `true` on the output of `combine` |
| `test "phase2: circuits fixtures behavioral correctness"` | `tests/` | For each `.circ` in `tests/fixtures/circuits/`: serialize → combine → Node instantiation with host protocol → simulation output matches expected values |
| `test "phase2: project fixtures behavioral correctness"` | `tests/` | For each root `.circ` in `tests/fixtures/projects/`: same end-to-end check |

Run command: `zig build test`

## Open Questions / Spikes

None — phase is fully specified.
