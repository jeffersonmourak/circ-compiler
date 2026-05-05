# Phase 0 — Runtime-as-WASM

> **Dependencies:** None
> **Warnings:** This phase locks the `circ.topology` binary format. Any post-lock change requires updating both the serializer (Phase 1) and the interpreter simultaneously — treat it like a wire protocol. Read the "Recurring Traps" section of `DOCS/PLANS_PROMPT.md` before starting.

## Goal

Once this phase is complete, the pre-built runtime WASM (simulation engine + circuit interpreter) is embedded in `circ-compile`. A developer can construct a `circ.topology` custom section by hand, append it to the embedded runtime blob, and instantiate the combined `.wasm` in Node — the simulation runs correctly with no `zig build` subprocess. The existing compile path (orchestrator + subprocess) is untouched.

## Scope

**In scope:**
- Define the `circ.topology` binary format as Zig types and constants in `lib/topology/format.zig` (shared by interpreter and future serializer)
- Implement `templates/interpreter.zig`: reads and validates the `circ.topology` payload; calls `createComponent`/`connect` for each record
- Add `topology_alloc(len: i32) -> i32` export to the runtime (allocates a buffer from the arena and records the pointer/length for the interpreter)
- Modify `templates/main.zig` `init()` to call the interpreter if a topology was loaded via `topology_alloc`
- Add a `build.zig` step that compiles the runtime template to `wasm32-freestanding` WASM before building the CLI
- Embed the pre-built runtime WASM in `circ-compile` via a new `lib/topology/runtime_embed.zig` (`@embedFile`); this is separate from the existing `lib/orchestrator/embed.zig`
- Integration test (inside `zig build test`): hand-craft an inverter `circ.topology` payload, wrap it in a custom section, append to the embedded runtime blob, spawn Node, assert correct simulation output

**Explicitly deferred:**
- Serializer that translates resolved IR to `circ.topology` bytes (Phase 1)
- Automated custom section writer and append logic (Phase 2)
- Replacing `orchestrator.compile()` in the CLI with the new path (Phase 3)
- Deleting the old orchestrator, old `embed.zig`, and `templates/` (Phase 4)
- TypeScript SDK update for the `topology_alloc` host protocol (Phase 4)

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|----------------|------|----------------|
| topology | `lib/topology/format.zig` | Binary format constants and types: magic, version, `ComponentKind` enum, `PortName` enum, `ComponentRecord`, `ConnectionRecord` |
| runtime template | `templates/interpreter.zig` | Reads and validates the `circ.topology` payload from a pointer/length; calls engine `createComponent`/`connect` for each record |
| runtime embed | `lib/topology/runtime_embed.zig` | `@embedFile` of the pre-built runtime WASM; exposes `pub const runtime_wasm: []const u8` |

**Modified files:**

| Module/Package | File | Change |
|----------------|------|--------|
| runtime template | `templates/main.zig` | Add `topology_alloc(len: i32) -> i32` export; two new module-level globals (`topo_ptr`, `topo_len`); call interpreter from `init()` when `topo_ptr != null` |
| build | `build.zig` | New build step: compile runtime template to `zig-out/lib/circ-runtime.wasm` (wasm32-freestanding); wire as dependency of the `circ-compile` build so `@embedFile` in `runtime_embed.zig` resolves |

**New dependencies:** None.

## Data & State

### `lib/topology/format.zig`

```zig
pub const MAGIC: [4]u8 = .{ 'C', 'I', 'R', 'C' };
pub const VERSION: u8 = 0x01;

pub const ComponentKind = enum(u8) {
    input_pin  = 0,
    not_gate   = 1,
    and_gate   = 2,
    wire       = 3,
    led        = 4,
    output_pin = 5,
};

pub const PortName = enum(u8) {
    in  = 0,
    a   = 1,
    b   = 2,
    out = 3,
};

// `port` is the input port on `to_id` that receives the signal from `from_id`.
pub const ComponentRecord = extern struct {
    id:   u32,  // little-endian
    kind: u8,   // ComponentKind
};

pub const ConnectionRecord = extern struct {
    from_id: u32,  // little-endian
    to_id:   u32,  // little-endian
    port:    u8,   // PortName
};
```

### `circ.topology` payload layout

Inside the WASM custom section body (after the section's name string):

```
[4]u8  magic             = "CIRC"
u8     version           = 0x01
u32    component_count   (little-endian)
u32    connection_count  (little-endian)
[component_count  × 5 bytes] ComponentRecord[]
[connection_count × 9 bytes] ConnectionRecord[]
```

All multi-byte integers are little-endian. Records are fixed-width and tightly packed with no padding.

### Runtime globals (in `templates/main.zig`)

```zig
var topo_ptr: ?[*]const u8 = null;
var topo_len: u32 = 0;

export fn topology_alloc(len: i32) i32 {
    const buf = allocator.alloc(u8, @intCast(len)) catch return -1;
    topo_ptr = buf.ptr;
    topo_len = @intCast(len);
    return @intCast(@intFromPtr(buf.ptr));
}
```

`init()` checks `topo_ptr != null` before calling the interpreter. If no topology was loaded, `init()` is a no-op (existing behavior for the `circ-renderer-lib` use case).

## Execution & Concurrency Model

This phase is fully synchronous. The interpreter runs during `init()`, which is a synchronous WASM export. WASM is single-threaded by default; no locking or guarding is required. No background workers or threads are introduced.

## Persistence & I/O

**Build time:** `build.zig` compiles the runtime template to `zig-out/lib/circ-runtime.wasm`. `lib/topology/runtime_embed.zig` references this path via `@embedFile`. The CLI build depends on this step completing first — `build.zig` must express this dependency explicitly so parallel builds are correct.

**Test time:** The integration test constructs a combined WASM blob in memory (embedded runtime bytes + hand-appended custom section), writes it to a temp file, spawns a Node subprocess, reads Node's stdout for the assertion values, then deletes the temp file regardless of pass/fail.

**Host protocol (required for any consumer of the compiled `.wasm`):**

WASM custom sections are opaque to the module itself. The host must bridge the topology data into WASM linear memory before `init()`:

```js
// 1. Instantiate the module (do not call init() yet)
const mod = await WebAssembly.compile(wasmBytes);
const instance = await WebAssembly.instantiate(mod, { env: { ... } });

// 2. Read the circ.topology custom section
const topoBytes = new Uint8Array(
    WebAssembly.Module.customSections(mod, 'circ.topology')[0]
);

// 3. Allocate space in WASM memory and copy the bytes
const ptr = instance.exports.topology_alloc(topoBytes.length);
new Uint8Array(instance.exports.memory.buffer).set(topoBytes, ptr);

// 4. Now init() can run the interpreter
instance.exports.init();
```

This protocol is an addition, not a change to the `init()` signature. The TypeScript SDK will wrap it transparently in Phase 4. Raw users must follow the above pattern until then.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Format spec | `lib/topology/format.zig` with all enums, record types, and constants; no runtime logic | `zig build test` compiles cleanly; a dedicated test asserts each enum tag's integer value is stable |
| 2 | Interpreter + runtime changes | `templates/interpreter.zig`; `topology_alloc` export and `topo_ptr`/`topo_len` globals in `templates/main.zig`; `init()` calls interpreter when topology is loaded | Zig unit test: construct a minimal `circ.topology` byte slice in-process, call the interpreter directly, assert the expected components and connections exist in the circuit |
| 3 | Pre-built runtime embed | New `build.zig` step compiles runtime to `zig-out/lib/circ-runtime.wasm`; `lib/topology/runtime_embed.zig` embeds it; `circ-compile` builds successfully | `zig build circ-compile` succeeds; a compile-time `comptime std.debug.assert(runtime_embed.runtime_wasm.len > 0)` guards against an empty embed |
| 4 | Node integration test | Zig test that hand-crafts an inverter `circ.topology` payload (one `not_gate`, two connections), wraps it in a WASM custom section, appends to the embedded runtime blob, spawns Node with an inline assertion script, asserts `a=0→1` and `a=1→0` | `zig build test` green; test emits a clear skip (not fail) if Node is not on PATH |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|-----------------|
| `test "format: ComponentKind values are stable"` | `lib/topology/format.zig` | Each tag has its expected integer value; guards against accidental reordering |
| `test "format: PortName values are stable"` | `lib/topology/format.zig` | Each tag has its expected integer value |
| `test "interpreter: single not-gate topology"` | `templates/interpreter.zig` | Feed one `ComponentRecord` (not_gate, id=0) and one `ConnectionRecord`; assert circuit has one not-gate and one connection without error |
| `test "interpreter: rejects wrong magic"` | `templates/interpreter.zig` | Payload with wrong magic bytes returns `error.InvalidMagic` |
| `test "interpreter: rejects unknown version"` | `templates/interpreter.zig` | Payload with version ≠ `0x01` returns `error.UnsupportedVersion` |
| `test "interpreter: rejects truncated payload"` | `templates/interpreter.zig` | Payload shorter than the header returns `error.TruncatedPayload` |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| `test "phase0: inverter round-trip via Node"` | `tests/` | Hand-crafted inverter topology in a custom section appended to the embedded runtime; Node instantiates using the host protocol above; `setPin(0,0); run(); getOutputState(1) == 1` and `setPin(0,1); run(); getOutputState(1) == 0` |

Run command: `zig build test`

## Open Questions / Spikes

- **Arena initialization order:** `topology_alloc` allocates from the arena. Verify the arena in `lib/memory.zig` is initialized at module instantiation time (not inside `init()`), so `topology_alloc` is callable before `init()`. If the arena requires `init()` to run first, extract arena setup into a separate export or initialize it lazily on first allocation.
- **Initial WASM memory pages:** Confirm the default page count (64 KB/page) in the runtime build is sufficient to hold the runtime's own static data plus the topology buffer for the largest existing test fixture. If not, increase the minimum page count in the runtime's `build.zig` template.
