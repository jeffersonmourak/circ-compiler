# WASM API & TypeScript SDK

## WASM Module Interface

The WASM module (`circ-renderer-lib.wasm`) is instantiated with an import object that provides three host callbacks. It exposes eight exported functions.

### Imports (JavaScript → WASM)

The host must supply these three functions when instantiating the module:

```typescript
const importObject = {
  env: {
    onStateChange: () => void,
    debugEnabled:  () => number,   // 0 = disabled, 1 = enabled
    onDebugLog:    (ptr: number, len: number, logType: number) => void,
  }
};
```

| Callback         | When called                                    | Notes |
|-----------------|------------------------------------------------|-------|
| `onStateChange` | After any component's output state changes     | Stateless; caller should call `refreshState()` to read new values |
| `debugEnabled`  | Checked before each log emission               | Return `1` to receive log messages |
| `onDebugLog`    | When the Zig code logs a message               | `ptr` + `len` point into WASM linear memory; read before returning. `logType`: `0`=debug, `1`=info, `2`=warn, `3`=error. Call `freeLogMessage(ptr, len)` after reading. |

### Exports (WASM → JavaScript)

```typescript
type CircRenderWasmExports = {
  memory:              WebAssembly.Memory;
  init:                ()                         => void;
  deinit:              ()                         => void;
  createComponent:     (kind: number)             => number;
  connect:             (comp1: number, port1: number, comp2: number, port2: number) => void;
  propagateEvent:      (comp_id: number, state: number) => void;
  propagate:           ()                         => void;
  getComponentState:   (comp_id: number)          => number;
  freeLogMessage:      (ptr: number, len: number) => void;
};
```

#### `init(): void`

Initialises the global circuit and component map. Must be called once before any other function.

#### `deinit(): void`

Frees all circuit memory. After this call the module must not be used until `init()` is called again.

#### `createComponent(kind: number): number`

Creates a new component and returns its integer ID (`>= 0`). Returns `-1` on allocation failure.

`kind` values:

| Value | Component       |
|-------|----------------|
| `0`   | `InputPinGate` |
| `1`   | `NotGate`      |
| `2`   | `Led`          |
| `3`   | `AndGate`      |
| `4`   | `Wire`         |

#### `connect(comp1, port1, comp2, port2): void`

Connects the output port of `comp1` to the input port of `comp2`.

Port encoding per component type:

| Component  | Port name | Integer |
|-----------|-----------|---------|
| Any        | `"out"`   | `0`     |
| Any        | `"in"`    | `1`     |
| `AndGate` | `"a"`     | `2`     |
| `AndGate` | `"b"`     | `3`     |

Typical call: connect `comp1`'s output (`port1 = 0`) to `comp2`'s input (`port2 = 1`).

#### `propagateEvent(comp_id, state): void`

Injects a state change into `comp_id`. Enqueues an event but does not advance simulation. Call `propagate()` afterwards to settle the circuit.

`state` values: `0` = low, `1` = high, `2` = undefined.

#### `propagate(): void`

Drains the event queue until the circuit settles. Triggers `onStateChange()` for every component whose output changes during propagation.

#### `getComponentState(comp_id): number`

Returns the current output state of the component. Same integer encoding as `propagateEvent`.

#### `freeLogMessage(ptr, len): void`

Releases the memory allocated for a log message previously delivered via `onDebugLog`. Must be called once per `onDebugLog` invocation before the callback returns or immediately after.

---

## TypeScript SDK

Source: [src/index.ts](../src/index.ts)

### Enumerations

```typescript
export enum ComponentKind {
  InputPinGate = 0,
  NotGate      = 1,
  Led          = 2,
  AndGate      = 3,
  Wire         = 4,
}

export enum State {
  Low       = 0,
  High      = 1,
  Undefined = 2,
}
```

### `initializeWasm(wasmPath): Promise<CircRenderer>`

Fetches, compiles, and instantiates the WASM module. Sets up all three host callbacks. Returns a ready-to-use `CircRenderer`.

```typescript
import { initializeWasm, ComponentKind, State } from './src/index';

const renderer = await initializeWasm('./circ-renderer-lib.wasm');
```

An optional `onStateChange` callback can be provided in the options object; it fires after `propagate()` settles the circuit.

### `CircRenderer`

```typescript
class CircRenderer {
  circuit: {
    createComponent(kind: ComponentKind): number;
    connect(
      fromId: number, fromPort: number,
      toId: number,   toPort: number,
    ): void;
    propagateEvent(compId: number, state: State): void;
    propagate(): void;
    getComponentState(compId: number): State;
  };

  refreshState(): void;
  printState(): void;
}
```

#### `circuit.createComponent(kind)`

Creates a component and returns its ID. IDs are stable for the lifetime of the module.

#### `circuit.connect(fromId, fromPort, toId, toPort)`

Wires two components. Use port values from the table in the WASM exports section above.

#### `circuit.propagateEvent(compId, state)`

Drives an input pin to `low` or `high`. Call `circuit.propagate()` after to advance simulation.

#### `circuit.propagate()`

Runs the simulation until all events are resolved.

#### `circuit.getComponentState(compId)`

Returns the settled output state of a component.

#### `refreshState()`

Reads all component states from WASM memory and stores them in the renderer's internal snapshot. Useful for bulk reads after `propagate()` without calling `getComponentState` for each component individually.

#### `printState()`

Logs the current state snapshot to the browser console. Intended for debugging.

---

## Logging

When `debugEnabled()` returns `1`, the Zig runtime forwards all `std.log` calls to `onDebugLog`. The TypeScript SDK decodes the message from WASM linear memory using `TextDecoder` and calls `freeLogMessage` before returning.

Log type byte to level mapping:

| Byte | Level |
|------|-------|
| `0`  | debug |
| `1`  | info  |
| `2`  | warn  |
| `3`  | error |

---

## Minimal Integration Example

```typescript
import { initializeWasm, ComponentKind, State } from './src/index';

const renderer = await initializeWasm('./circ-renderer-lib.wasm');
const { circuit } = renderer;

// Build a NOT gate circuit: pin → not → led
const pin = circuit.createComponent(ComponentKind.InputPinGate);
const not = circuit.createComponent(ComponentKind.NotGate);
const led = circuit.createComponent(ComponentKind.Led);

circuit.connect(pin, 0, not, 1);   // pin.out → not.in
circuit.connect(not, 0, led, 1);   // not.out → led.in

// Drive the pin high and settle
circuit.propagateEvent(pin, State.High);
circuit.propagate();

console.log(circuit.getComponentState(led)); // State.Low (NOT of High)

// Drive low
circuit.propagateEvent(pin, State.Low);
circuit.propagate();

console.log(circuit.getComponentState(led)); // State.High (NOT of Low)
```
