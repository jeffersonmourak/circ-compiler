# Architecture

`circ-renderer-z` is a digital logic circuit simulator compiled to WebAssembly. The project is structured as three distinct layers that communicate across the Zig/JavaScript boundary.

## Layer Overview

```
┌─────────────────────────────────────────────────────┐
│                  Browser / Host                     │
│  ┌──────────────┐    ┌───────────────────────────┐  │
│  │  TypeScript  │    │   Rendering Engine        │  │
│  │  SDK         │◄──►│   (Canvas 2D + Themes)    │  │
│  │  src/index   │    │   example/theme.ts        │  │
│  └──────┬───────┘    └───────────────────────────┘  │
│         │ WASM boundary (imports / exports)         │
│  ┌──────▼────────────────────────────────────────┐  │
│  │              lib/wasm.zig                     │  │
│  │         (WASM FFI / glue layer)               │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │                               │
│  ┌──────────────────▼────────────────────────────┐  │
│  │           lib/circuit.zig                     │  │
│  │      (simulation engine, pure Zig)            │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Layer 1 — Simulation Engine (`lib/circuit.zig`)

The simulation engine has no knowledge of WASM, JavaScript, or rendering. It models a digital circuit as a directed graph of components and advances time using an event priority queue.

### Component Model

All gate types share a common `Component` wrapper that holds:

- A unique integer ID
- The gate kind (a tagged union of `input_pin_gate`, `not_gate`, `and_gate`, `led`, `wire`)
- The current output state (`undefined | low | high`)
- An output adjacency map — maps port names to lists of downstream components
- An inputs map per gate — maps named ports to upstream components (stored inside the gate kind struct)

### Event-Driven Propagation

Simulation advances through discrete events rather than by re-evaluating the whole graph each tick.

```
propagateEvent(component, new_state)
    → enqueue Event { timestamp = now + gate_delay, component, new_state }

propagate()
    while queue not empty:
        event = pop_min(queue)
        current_time = event.timestamp
        component.output_state = event.new_state
        for each downstream of component:
            recalculateAndReschedule(downstream)

recalculateAndReschedule(component)
    new_out = evaluate(component.inputs)
    if new_out != component.output_state:
        enqueue Event { timestamp = current_time + delay(component) }
```

Propagation delays are compile-time constants:


| Component type | Delay (time units) |
| -------------- | ------------------ |
| Wire           | 1                  |
| Logic gate     | 5                  |


### Gate Logic


| Gate        | Output rule                                         |
| ----------- | --------------------------------------------------- |
| `input_pin` | Driven externally; no recalculation                 |
| `not_gate`  | `!input`                                            |
| `and_gate`  | `a AND b`                                           |
| `wire`      | Passes first defined input                          |
| `led`       | Captures input state (terminal; does not propagate) |


`calculateDominantState()` is a helper used by multi-input gates: returns `high` if any input is `high`, otherwise returns the first defined state among inputs.

## Layer 2 — WASM Glue (`lib/wasm.zig`)

This layer owns the WebAssembly boundary. It:

- Exports eight functions callable from JavaScript (see [wasm-api.md](wasm-api.md))
- Imports three callback functions from the JavaScript host
- Maintains a global `circuit` instance and a component hash map (`i32 → *Component`)
- Translates between JavaScript integer IDs and Zig pointer-based references
- Forwards simulation state changes to the JS host via `onStateChange()`

JavaScript imports the WASM module providing:


| JS export                    | Purpose                                  |
| ---------------------------- | ---------------------------------------- |
| `onStateChange()`            | Called when any component output changes |
| `debugEnabled()`             | Returns 1 to enable verbose logging      |
| `onDebugLog(ptr, len, type)` | Receives a log message from Zig          |


## Layer 3 — TypeScript SDK (`src/index.ts`) and Rendering (`example/`)

The SDK wraps the raw WASM exports in an idiomatic TypeScript class. It:

- Fetches and instantiates the WASM binary
- Wires up the three callback imports
- Exposes `CircRenderer` with a `circuit` sub-object for component operations
- Provides `refreshState()` to snapshot all component states from WASM memory

The rendering layer (`example/`) is a separate demo application. It uses a **theme** system where each component kind has a *skin* — a function that receives a canvas 2D context, component dimensions, and port signal values, and draws the component.

## Compiler / Parser (WIP)

A separate compilation path exists for parsing `.circ` text files:

```
.circ source
    → langlang PEG grammar (lib/grammar/proto-circ.peg)
    → generated C parser (lib/parser.c / parser.h)
    → lib/syntax/CParser.zig  (Zig FFI import)
    → lib/syntax/translate.zig  (parse tree walker)
    → lib/syntax/nodes/declaration.zig  (declaration handler)
    → lib/circuit.zig  (circuit construction) [not yet connected]
```

The parser recognises `input`, `output`, and `component` declarations but does not yet emit circuit construction calls. See [circuit-format.md](circuit-format.md) for the target DSL.

## Memory Management

All heap allocation inside the WASM module uses a single arena allocator (`lib/memory.zig`). This keeps memory management simple: the arena grows monotonically and is freed in one call when `deinit()` is exported to JavaScript. Log messages use a separate short-lived arena so they can be freed individually via `freeLogMessage()`.

## Build Targets

The `build.zig` produces three independent targets:


| Target              | Output                     | Purpose                    |
| ------------------- | -------------------------- | -------------------------- |
| `circ-renderer-lib` | `circ-renderer-lib.wasm`   | Browser simulation library |
| `compiler`          | native binary              | Parse `.circ` files (WIP)  |
| `logic-sim`         | native binary (`main.zig`) | CLI debug harness          |


