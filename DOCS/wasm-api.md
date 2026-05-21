# WASM Runtime API

Each `.wasm` produced by `circ-compile <input>.circ -o <out>.wasm` is a self-contained module: it embeds a prebuilt simulation runtime plus this circuit's topology as a custom section. The host loads the module, copies the topology bytes into linear memory, calls `init()`, and then drives the circuit through the small fixed export surface below.

This document is the contract for the **default compile path** (the artifact actually shipped to hosts). The optional `--emit-zig` path generates a standalone Zig source with a richer experimental export surface; that surface is not stable and not described here.

## Imports (host → WASM)

The host must supply two functions in the `env` namespace at instantiation time:

| Import        | Signature                                  | Purpose                                                          |
|---------------|--------------------------------------------|------------------------------------------------------------------|
| `debugEnabled`| `() => i32`                                | Return `1` to receive log callbacks, `0` to suppress them.       |
| `onDebugLog`  | `(ptr: i32, len: i32, logType: i32) => void` | Receives a UTF-8 log message in linear memory. `logType`: `0` debug, `1` info, `2` warn, `3` error. The buffer is owned by the runtime — do not call back into the runtime to free it. |

If `debugEnabled` returns `0`, `onDebugLog` is never called, but **both imports must be present** or instantiation will fail. Provide no-op stubs when you don't care about logs.

## Exports (WASM → host)

```
memory:          WebAssembly.Memory
topology_alloc:  (len: i32) => i32     // host buffer for topology bytes; returns ptr (or -1 on OOM)
init:            ()        => void    // construct circuit from the topology buffer
run:             ()        => void    // drain the event queue until the circuit settles
setPin:          (id: i32, state: i32) => void
getOutputState:  (id: i32) => i32
```

`state` integer encoding (matches `engine.State.toInt`/`fromInt` in `lib/circuit.zig`):

| Integer | State        |
|---------|--------------|
| `0`     | low          |
| `1`     | high         |
| `2`     | undefined    |

### `topology_alloc(len)` and `init()`

The compiled `.wasm` carries the circuit topology as a `circ.topology.v0.min` custom section, **not** in linear memory. The host is responsible for copying those bytes into the runtime's linear memory before `init()` runs. The protocol is:

1. Read the section: `WebAssembly.Module.customSections(module, "circ.topology.v0.min")`.
2. Call `topology_alloc(byteLength)`. The runtime allocates a buffer in linear memory and returns its pointer (or `-1` on allocation failure).
3. Copy the section bytes to that pointer in `memory.buffer`.
4. Call `init()`. The runtime parses the buffer, builds the circuit graph, and marks itself initialised.

`init()` is idempotent: calling it after the runtime is initialised is a no-op. It silently bails out if no topology was loaded or the topology fails to parse, so always copy the section before calling `init`.

### `run()`

Drains the engine's event queue until empty. Settling delays are `5` time-units per gate and `1` per wire/output_pin (see `lib/circuit.zig`); a single `run()` call is enough to settle any cascade — there is no "tick" semantics to worry about.

`run()` is a no-op if `init()` has not run successfully.

### `setPin(component_id, state)`

Drives a top-level input pin. `component_id` is the global integer ID of an `input_pin_gate`; passing the ID of a non-input or out-of-range component is a silent no-op (it does not throw or trap).

`setPin` only enqueues the change — call `run()` after to propagate it.

### `getOutputState(component_id)`

Returns the current `output_state` of the component with the given ID, encoded as the integer above. Returns `2` (undefined) if the runtime is not initialised or the ID is out of range. The argument is the **driver component ID**, not an output-pin index — for an `output out(in=inv.out)` declaration, you pass `inv`'s component ID, not `out`'s pin ID. The `--inspect` output of the compiler prints this mapping under its `Outputs (...)` block.

## Custom sections

| Section name              | Contents                                                            |
|---------------------------|---------------------------------------------------------------------|
| `circ.topology.v0.min`    | Compact topology consumed by `init()`. Required.                    |
| `circ.topology.v0.full`   | Verbose topology used by tooling (`circ-compile --inspect`, preview rendering). The runtime never reads it. |
| `name`                    | Standard Zig-emitted name section. Useful for debuggers, ignored at runtime. |

The `.full` section is not required for execution. Hosts that only run circuits can ignore it; tools that need names, hierarchy, or per-port labels should read `.full`.

## Minimal Node integration

```js
import fs from "node:fs";

const bytes = fs.readFileSync(process.argv[2]);
const mod   = await WebAssembly.compile(bytes);

const { exports: w } = await WebAssembly.instantiate(mod, {
  env: {
    debugEnabled: () => 0,
    onDebugLog:   () => {},
  },
});

// 1. Copy the topology section into linear memory.
const [topoSection] = WebAssembly.Module.customSections(mod, "circ.topology.v0.min");
const topoBytes = new Uint8Array(topoSection);
const ptr = w.topology_alloc(topoBytes.length);
new Uint8Array(w.memory.buffer).set(topoBytes, ptr);

// 2. Build the circuit and drive it.
w.init();
w.setPin(0, 1);                  // pin id=0 → high
w.run();
console.log(w.getOutputState(1)); // 0 = low (NOT of high)
```

## Things that are *not* exports today

Earlier drafts of this project anticipated additional exports — `deinit`, `reset`, `stop`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer` — and a separate `onStateChange` import. None of these are present in the artifact produced by `circ-compile … -o out.wasm` today. The extra exports survive only in `lib/emit/runtime.zig`, the experimental `--emit-zig` pipeline; the `onStateChange` import was never wired into any pipeline and exists nowhere in the codebase. Either may appear in a future runtime version. If your host needs change-notifications, poll `getOutputState` after each `run()`.
