# Runtime API

The compiled `.wasm` artifact exposes a fixed runtime API for hosts (browsers, Node, any WASM runtime). Consumers can drive pins, settle the circuit, and read outputs — but cannot extend the circuit at runtime. For the full signature reference see [`../wasm-api.md`](../wasm-api.md); this file captures the load-bearing decisions behind that surface.

### Settle-only `run()`

**Decision.** `run()` drains the event queue synchronously and returns when the circuit has settled. There is no continuous-time mode and no host-driven tick loop.

**Rationale.** Settle-only matches the existing engine in `lib/circuit.zig` exactly — one `propagate()` call advances the circuit until quiescent. It's the simplest mental model for hosts: "I changed a pin, I want the circuit to react, then I read the result." Clocked simulation and free-running modes can be added later without breaking this API; they are additive.

**Alternatives.** Tick-based `run(ticks)` for clocked circuits and free-running modes were considered. Both require either a clock primitive in the engine or host-driven ticking, neither of which is in scope today. Adding them now would commit to a more complex API surface before the use case is concrete.

### Initial state is implicitly `undefined`; `init()` does not pre-settle

**Decision.** After `init()` runs, every component's stored state is the `BitVecState.undefined_(width)` value that `Circuit.allocateStateSlot` populates (`defined = 0`, `value = 0`). The host must drive pins via `setPin` and call `run()` before any output read is meaningful.

**Rationale.** "All-undefined" is the most honest representation of "nothing has happened yet" — it doesn't pretend any pin has a value the host hasn't supplied. It mirrors what a real circuit looks like before power-on: indeterminate. Hosts that want a defined starting state drive their preferred pin values and call `run()`.

**Alternatives.** A separate `reset()` export that re-establishes this state mid-life was considered and dropped: hosts that want to "restart" the circuit can re-instantiate the WASM module, which is what every host already does between simulation runs. Pins-low-then-settle (always lands in a defined state, easier for tests) and post-initial-settle inside `init()` (replays a boot sequence) bake host-policy into the runtime; the all-undefined start lets the host decide.

### Pin identification by component ID

**Decision.** `setPin(component_id, value, defined)` accepts the **input pin's** component ID. The paired `getOutputValue(component_id)` / `getOutputDefined(component_id)` getters accept the **driver** component ID — that is, the ID of the component whose `out` port feeds the `output` declaration, not the `output_pin`'s own ID. There is no separate pin-index space.

**Rationale.** One identifier scheme is simpler than two. Component IDs are dense `0..nodes.len` integers assigned by `Circuit.createComponent` and stable for the life of a compiled artifact (the topology serializer fixes them at emission time), so they're as stable as a separate pin index would be. The mapping from declaration name to component ID is printed under each module's `Inputs (...)` / `Outputs (...)` block by `circ-compile --inspect`, and the same information is encoded in the `circ.topology.v0.full` custom section for programmatic readers.

**Alternatives.** A separate pin index (`0..N` for inputs, `0..M` for outputs) decouples the host API from internal IDs, but in this design the IDs are already stable; the abstraction would add a translation table for no clear benefit.

### Paired BigInt exports for outputs

**Decision.** Output state crosses the WASM boundary as two `i64` (`BigInt`) calls — `getOutputValue(id)` returns the `BitVecState.value` bits, `getOutputDefined(id)` returns the `BitVecState.defined` mask. Hosts combine them however they want; the convention is `defined === 0n` ⇒ undefined, otherwise read `value`.

**Rationale.** Two simple calls returning JavaScript-native `BigInt`s avoid the alternatives' costs: no buffer allocation, no pointer arithmetic, no in-band encoding for endianness or alignment, no sentinel value for undefined. Each call carries up to 64 bits of state, enough for any legal `BitVecState` width (1–64). For typical hosts that read once per settle, the 2× call overhead is irrelevant; a future `getOutputStateBatch(ids_ptr, out_ptr, count)` could be added without breaking this API.

**Alternatives.** A single `getOutputState(id, out_ptr: i32)` that writes a 16-byte `BitVecState` into linear memory at `out_ptr`. Tighter on the wire but forces every host to allocate a scratch buffer and parse it; the paired-export shape is friendlier for the dominant "read one output after settle" use case. A scalar `getOutputState(id) -> i32` returning `0`/`1`/`2` predates multi-bit and can't represent bit-width-`N` state without information loss.

### `setPin` is symmetric with the output getters

**Decision.** `setPin(component_id: i32, value: i64, defined: i64) -> void`. The host writes the same `(value, defined)` shape it reads. Bits beyond the input pin's declared width are silently masked.

**Rationale.** Treating input and output state as the same data shape keeps host code symmetric ("read state, mutate state, write state"). Silent masking on input is consistent with the engine's existing behaviour for over-wide writes via `Pool.write`. Passing the ID of a non-input or out-of-range component is a no-op rather than a trap, which matches `getOutputValue`/`getOutputDefined`'s silent-zero behaviour and means hosts can scan ID ranges defensively.

**Alternatives.** A separate `setInputBit(id, bit_index, state)` for sparse updates was considered; rejected because the bit-parallel form covers the same cases, and the bit-by-bit form would require the host to read-modify-write (or for the engine to do it internally, adding allocations).

### Pull-based with no host callbacks beyond logging

**Decision.** The compiled artifact is purely pull-based — after `run()` returns, the host polls outputs via the paired getters. There is no `onStateChange` import, no event queue exposed to the host, and no listener registration. The only host imports are `debugEnabled` (returns whether log emission is wanted) and `onDebugLog` (receives UTF-8 log buffers).

**Rationale.** Removing the FFI callback keeps the WASM module self-contained — every required import is stub-able with two no-op JS functions, so instantiation works in any environment that supports WebAssembly. Change-notifications, debouncing, diffing — every flavour of "tell me when X changed" — belongs in host code, where the host can pick its own strategy without the WASM boundary in the way.

**Alternatives.** The original `lib/wasm.zig` prototype installed an `onStateChange` callback. That worked for the dynamic API but created an instantiation prerequisite that complicated non-browser hosts. The native engine still exposes a `listener` callback for in-process test harnesses; it's intentionally not surfaced through the WASM boundary.

### Topology section copied into linear memory at startup

**Decision.** The compiled `.wasm` carries the circuit topology as a `circ.topology.v0.min` custom section, not in linear memory. The host reads the section via `WebAssembly.Module.customSections`, calls `topology_alloc(byteLength)` to reserve a buffer in linear memory, copies the bytes, then calls `init()`. `init()` parses the buffer and constructs the circuit. The section name still starts with `v0` for backwards-compatible host code; the version byte inside (`0x03`) is the format axis that evolves.

**Rationale.** WASM custom sections are opaque to the module itself — there is no in-module API to read them. The three-call protocol (`topology_alloc` → `memcpy` → `init`) is the smallest portable bridge any JS host can implement without an SDK. Hosts that don't need rendering metadata can ignore the parallel `circ.topology.v0.full` section, which carries the same structural data plus per-component names and macro provenance.

**Alternatives.** Passing topology bytes through WASM imports at instantiation (rejected: `WebAssembly.instantiate` takes imports, not arbitrary data; topology can be hundreds of KB). Encoding topology in the module's data section so `init()` can read it directly (rejected: requires modifying the WASM binary structure, not just appending; the section-then-copy protocol works against the appended-section pipeline today).

### Things deliberately *not* exported

The artifact intentionally omits several exports that earlier drafts considered:

- `deinit()`, `reset()`, `stop()` — lifecycle controls. Re-instantiating the module covers every use case for `reset`/`deinit`; `stop` would only matter for non-settle-only run modes that don't exist.
- `getStateSnapshot()`, `getTopology()`, `getPendingEvents()` — bulk introspection returning `(ptr, len)` buffers. The paired getters cover the per-component state case; topology lives in custom sections that the host already has direct access to.
- `getFileInfo()` — pin-name / source-path metadata. Same information lives in the `circ.topology.v0.full` custom section and in `circ-compile --inspect` output.
- `freeBuffer()` — companion to the introspection exports above; not needed because no export currently returns an owned buffer.

A richer surface (`getStateSnapshot`, `getFileInfo`, `freeBuffer`, …) still exists in `lib/emit/runtime.zig`, the experimental `--emit-zig` pipeline. That path is not on the default compile and its export contract is not stable.
