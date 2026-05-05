# Phase 1 — Topology Serializer

> **Dependencies:** Phase 0 (format types in `lib/topology/format.zig` must exist and be locked)
> **Warnings:** Component IDs are local to each `ir.Module` — they restart from 0 per file. The expander must assign globally-unique IDs across all expanded modules. Never pass a local `ComponentId` directly into a `ConnectionRecord`; always route through the expander's `id_map`.

## Goal

Once this phase is complete, calling `serializer.serializeModule(allocator, &module)` or `serializer.serializeProject(allocator, &project)` produces a `[]u8` that is a valid `circ.topology` payload. Appending that payload as a custom section to the Phase 0 embedded runtime WASM and instantiating the result in Node produces the correct simulation output for every circuit fixture in `tests/fixtures/circuits/` and `tests/fixtures/projects/`.

## Scope

**In scope:**
- `lib/topology/serializer.zig` with two public entry points: `serializeModule` (single-file, no imports) and `serializeProject` (multi-file with sub-circuit hierarchy)
- Recursive expander inside the serializer that flattens `sub_circuit_ref` components into primitive records with globally-unique IDs and rewires boundary connections
- Port name string → `format.PortName` enum conversion with an explicit error on unknown port names
- Unit tests covering the encoding and the expander's ID remapping and boundary wiring
- Integration tests that drive the Phase 0 interpreter via Node for all existing fixtures

**Explicitly deferred:**
- Wrapping the serialized payload in a WASM custom section (Phase 2)
- Wiring the serializer into `cmd/circ-compile/main.zig` (Phase 3)
- Deletion of the old emit layer and orchestrator (Phase 4)

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|----------------|------|----------------|
| topology | `lib/topology/serializer.zig` | Public API (`serializeModule`, `serializeProject`); internal expander state and recursion |

**Modified files:** None. This phase is purely additive.

**New dependencies:** None beyond `lib/topology/format.zig` (Phase 0) and `ir_types`.

## Data & State

### Public API

```zig
pub fn serializeModule(
    allocator: std.mem.Allocator,
    module: *const ir.Module,
) ![]u8

pub fn serializeProject(
    allocator: std.mem.Allocator,
    project: *const ir.Project,
) ![]u8
```

Both return a heap-allocated `[]u8` owned by the caller. The bytes are a complete `circ.topology` payload (header + component records + connection records), ready to be wrapped in a custom section.

### Internal expander state

```zig
const ExpanderState = struct {
    allocator: std.mem.Allocator,
    project: *const ir.Project,
    components: std.ArrayList(format.ComponentRecord),
    connections: std.ArrayList(format.ConnectionRecord),
    next_global_id: u32,
};
```

`next_global_id` is a monotonic counter shared across all recursive calls. It is the single source of global IDs — no module-local IDs ever appear in output records.

### Per-module expansion context (stack-allocated per recursive call)

```zig
// Maps module-local ComponentId.value → globally-unique u32
local_to_global: std.AutoHashMap(u32, u32),

// Maps sub-circuit-instance ComponentId.value → { output_name → global_driver_id }
// Used to resolve parent connections whose `from` references a sub-circuit output port.
sub_output_map: std.AutoHashMap(u32, std.StringHashMap(u32)),
```

Both maps are allocated from the expander's allocator and freed before the recursive call returns.

### Boundary rewiring algorithm

For each `sub_circuit_ref` component in the module being expanded:

1. Find the child `ir.Module` via `project.import_table` (match `importing_file == current_file_id` and `alias == sub_circuit_ref.name`).
2. Collect parent connections whose `to.component == sub_circuit_instance_id` — these feed the sub-circuit's inputs. Build a map: `port_name → { global_from_id, from_port }`.
3. Recursively call `expandModule` on the child module. The child's components and connections are added to the shared `ExpanderState` lists with freshly assigned global IDs.
4. **Input boundary:** for each `ir.InputPin` in the child module, look up its name in the map from step 2. If found, emit a `ConnectionRecord` from the parent's source to the child's `input_pin` component (`port = .in`).
5. **Output boundary:** for each `ir.OutputPin` in the child module, record `sub_output_map[sub_circuit_instance_id][output.name] = global_id_of(output.driver.component)`. The parent's connections whose `from.component == sub_circuit_instance_id` resolve their `from_global_id` through this map.

For parent connections not involving a sub-circuit instance:

- `from.component` is always a primitive: use `local_to_global`.
- `to.component` is always a primitive: use `local_to_global` and convert `to.port` string to `format.PortName` enum.
- Connections to sub-circuit instances are skipped here; they were consumed in step 2 above.

## Execution & Concurrency Model

This phase is fully synchronous. The serializer and expander are pure functions (no globals, no shared state outside of the `ExpanderState` passed by pointer through the recursion). No background workers or threads are introduced.

## Persistence & I/O

The serializer produces bytes entirely in memory. No files are read or written during serialization. The integration tests write a combined WASM to a temp file and spawn Node — that I/O is in the test harness, not the serializer itself.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|------------|
| 1 | Single-file serializer | `serializeModule` encodes a flat `ir.Module` (no `sub_circuit_ref` components) into `circ.topology` bytes; header, component records, and connection records are correct | Unit tests for encoding: inverter (not-gate), single and-gate; bytes decoded against `format.zig` types match expected records |
| 2 | Recursive expander + project serializer | `serializeProject` walks the root module, expands sub-circuit instances recursively, remaps IDs, rewires input/output boundaries | Unit tests: two-file project (half-adder), three-file project (full-adder); assert flat component count, global ID uniqueness, and boundary connections present |
| 3 | Integration tests against all fixtures | Zig tests serialize each fixture, append as custom section to the embedded runtime blob, spawn Node, assert simulation output matches expected values | `zig build test` green for all circuits in `tests/fixtures/circuits/` and all projects in `tests/fixtures/projects/` |

Slices are ordered by dependency. Each slice must be fully reviewable on its own.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|-----------------|
| `test "serialize: inverter module bytes"` | `lib/topology/serializer.zig` | `serializeModule` on a hand-constructed inverter `ir.Module` produces correct magic, version, counts, and one `ComponentRecord` + two `ConnectionRecord`s |
| `test "serialize: and-gate module bytes"` | `lib/topology/serializer.zig` | Single and-gate with two inputs; asserts `component_count=3` (two input_pins + one and_gate), `connection_count=2` |
| `test "serialize: unknown port name returns error"` | `lib/topology/serializer.zig` | A connection with `port = "xyz"` returns `error.UnknownPortName` |
| `test "serialize: half-adder project flat"` | `lib/topology/serializer.zig` | Two-module project (root + half_adder sub-circuit); asserts all global IDs are unique, no `sub_circuit_ref` IDs appear in output, boundary connections present |
| `test "serialize: two instances same sub-circuit get distinct IDs"` | `lib/topology/serializer.zig` | A root module instantiating the same sub-circuit twice; asserts the two expansions use non-overlapping ID ranges |
| `test "serialize: output boundary resolves to child driver"` | `lib/topology/serializer.zig` | A parent connection whose `from` references a sub-circuit output port resolves to the correct child driver component's global ID |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|-----------------|
| `test "phase1: circuits fixtures via Node"` | `tests/` | For each `.circ` in `tests/fixtures/circuits/`: serialize, wrap in custom section, append to runtime blob, instantiate in Node, assert simulation output matches the fixture's expected values |
| `test "phase1: project fixtures via Node"` | `tests/` | For each root `.circ` in `tests/fixtures/projects/`: same end-to-end check via Node |

Run command: `zig build test`

## Open Questions / Spikes

- **`output_pin` in serialized output:** `ir.Module.outputs` contains `OutputPin` with a `driver` endpoint but the `output_pin` component itself also appears in `module.components` as a primitive. Verify whether `output_pin` components should be included in the `circ.topology` payload — they are currently in the engine but act as terminal sinks. If the interpreter already handles them correctly via the existing engine API, include them; if not, document the omission.
- **Implicit builtins in the import table:** `resolveBodies` injects implicit builtin imports (e.g., `xor`, `or`) into the import table with `implicit_builtin = true`. The expander must handle these the same as explicit imports. Verify the import lookup works for builtin file paths (they are real paths in `tests/fixtures/` or similar; confirm their `ir.Module`s appear in `project.files`).
