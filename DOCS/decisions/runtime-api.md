# Runtime API

The compiled `.wasm` artifact exposes a fixed runtime API for hosts (browsers, Node, any WASM runtime). Consumers can simulate, query state, and introspect — but cannot extend the circuit at runtime.

### Settle-only `run()`

**Decision.** `run()` drains the event queue synchronously and returns when the circuit has settled. There is no continuous-time mode and no host-driven tick loop in v0.

**Rationale.** Settle-only matches the existing engine in `lib/circuit.zig` exactly — one `propagate()` call advances the circuit until quiescent. It's the simplest mental model for hosts: "I changed a pin, I want the circuit to react, then I read the result." Clocked simulation and free-running modes can be added later without breaking this API; they are additive.

**Alternatives.** Tick-based `run(ticks)` for clocked circuits and free-running modes were considered. Both require either a clock primitive in the engine or host-driven ticking, neither of which is in v0 scope. Adding them now would commit to a more complex API surface before the use case is concrete.

### Cold-start `reset()`

**Decision.** `reset()` returns the circuit to its post-`init()`-but-pre-settle state: every component's `output_state` is `undefined`, the event queue is empty, and `current_time` is zero. The host must drive pins again before any meaningful simulation, and call `run()` to settle.

**Rationale.** "All-undefined" is the most honest representation of "nothing has happened yet" — it doesn't pretend any pin has a value the host hasn't supplied. It mirrors what a real circuit looks like before power-on: indeterminate. Hosts that want a defined starting state can do `reset()` then drive their preferred pin values then `run()`.

**Alternatives.** Pins-low-then-settle (always lands in a defined state, easier for tests) and post-initial-settle (replays the boot sequence). Both bake host-policy into the runtime; cold-start lets the host decide.

### `stop()` retained as future-proofing no-op

**Decision.** `stop()` is exported but is a no-op in v0. Hosts can call it for symmetry with `run()`. Future engine modes (clocked, free-running) may give it real semantics.

**Rationale.** Adding the export now means hosts can write code that targets the long-term API shape today; removing or changing it later would be a breaking change. The cost of a no-op export is one line of glue.

**Alternatives.** Drop `stop()` entirely (leaner API today, breaking change later) or repurpose it as "abort propagation early" (adds a flag check to the propagation loop with no concrete use case). The no-op keeps the door open without paying for it.

### Introspection: snapshot, topology, pending events as separate exports

**Decision.** Three independent exports — `getStateSnapshot()`, `getTopology()`, `getPendingEvents()` — each returning a `(ptr, len)` tuple into WASM linear memory. Hosts call only what they need and call `freeBuffer(ptr, len)` afterwards.

**Rationale.** Different consumers have different needs: a UI just needs current state, a debugger needs the topology to render the graph, an event-stepper needs the pending queue. Separating the exports keeps the per-call payload small and makes the cost of each query explicit. Topology is mostly static — most consumers fetch it once at startup and cache it.

**Alternatives.** A single `getRawState()` returning everything bundled. Simpler API at the cost of always paying for what you don't use, and forcing the host to parse a richer schema for trivial state queries.

### File info as static Zig constants

**Decision.** Source-file metadata (file name, named input pins, named output pins, named sub-circuit instances, compile timestamp, compiler version) is emitted as Zig constants in the IR file and exposed via a `getFileInfo() → (ptr, len)` export that returns a pointer into a static data section.

**Rationale.** This data is immutable for the life of the artifact. Putting it in `.rodata` (via Zig constants) means zero runtime cost — no allocation, no marshalling, just a pointer. The compiler already needs to know all this metadata to emit the IR; surfacing it as constants is a one-line emission step per field.

**Alternatives.** A JSON blob in WASM memory, parsed by JS. More flexible for schema evolution but adds a JSON parse step on every consumer, and JSON isn't free to encode either. Schema evolution can be handled with a version field in the static struct just as well.

### Pin identification by component ID

**Decision.** `setPin(component_id, state)` and `getOutputState(component_id)` accept the component ID returned in `getFileInfo()`'s pin lists. There is no separate pin-index space.

**Rationale.** One identifier scheme is simpler than two. Component IDs are stable for the life of a compiled artifact (the IR fixes them at emission time), so they're as stable as a separate pin index would be. The host always has the component ID from `getFileInfo()` before it ever calls a pin function, so there's no ergonomic loss.

**Alternatives.** A separate pin index (0..N for inputs, 0..M for outputs). Decouples the pin API from internal IDs, but in this design the IDs are stable anyway, and the abstraction adds a translation table for no clear benefit.

### Full WASM export list (v0)

**Decision.** The compiled artifact exports exactly these functions:

```
Lifecycle:
  init()           → void
  deinit()         → void
  reset()          → void

Simulation:
  run()            → void
  stop()           → void          # no-op in v0

Pin I/O:
  setPin(component_id: i32, state: i32)         → void
  getOutputState(component_id: i32)             → i32

Introspection:
  getStateSnapshot()    → (ptr, len)
  getTopology()         → (ptr, len)
  getPendingEvents()    → (ptr, len)

Metadata:
  getFileInfo()         → (ptr, len)

Memory:
  freeBuffer(ptr, len)  → void
```

**Rationale.** This list covers every concrete need surfaced during design: lifecycle (init/deinit), simulation control (run/stop/reset), pin manipulation, debugging introspection, source metadata, and memory cleanup. Nothing is included speculatively except `stop()` (justified above as future-proofing).

**Alternatives.** A richer API with per-component event injection or runtime topology mutation. Both are explicit non-goals — the artifact is fixed at compile time for performance, and richer APIs can be added without breaking the v0 contract.

### Initial settle on `init()`

**Decision.** `init()` runs `propagate()` after constructing the circuit so that wires and gates with no host input have settled to their natural state before the host calls anything.

**Rationale.** Circuits with constant sub-graphs (e.g. a wire driven by another wire) should reach their settled value without the host having to call `run()` first. The cost is one `propagate()` call at startup; the alternative is making every host remember to settle before reading.

**Alternatives.** Lazy settle on first `getOutputState()` call. Adds a flag check to every read for a one-time saving. Not worth it.

### Pull-based with host-side event layer

**Decision.** The compiled artifact is purely pull-based — it does not call back into the host on state changes. The TypeScript SDK will provide an event layer on top by polling state after `run()` returns and emitting JS events for changed components.

**Rationale.** Removing the FFI callback keeps the WASM module self-contained — no host imports required to instantiate it, simpler embedding in environments that can't easily expose function tables. The TS SDK is the natural place for ergonomic event APIs because it can decide its own change-detection strategy without the WASM boundary in the way.

**Alternatives.** The existing `lib/wasm.zig` model with `onStateChange` callbacks. Works for the dynamic API but creates an instantiation prerequisite that complicates non-browser hosts.
