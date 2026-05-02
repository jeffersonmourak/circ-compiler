# circ-compiler Documentation

A digital logic circuit simulator written in Zig, compiled to WebAssembly for use in the browser.

## What it does

`circ-compiler` simulates digital logic circuits in real time using an event-driven propagation model. Circuits are built programmatically by creating components (gates, pins, LEDs) and connecting their ports. When an input pin changes state, the simulator propagates the signal through the graph with per-gate delays and notifies the host when outputs settle.

## Documents

| Document                                     | Contents                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------- |
| [getting-started.md](getting-started.md)     | New-user walkthrough: install, first `.circ`, compile, load from Node   |
| [architecture.md](architecture.md)           | Layer overview, component model, build targets, memory management       |
| [simulation-engine.md](simulation-engine.md) | Zig API reference: types, functions, propagation algorithm, gate logic  |
| [wasm-api.md](wasm-api.md)                   | WASM exports/imports, TypeScript SDK, integration example               |
| [circuit-format.md](circuit-format.md)       | `.circ` DSL syntax, grammar, file examples                              |
| [decisions/](decisions/index.md)             | WIP architectural decisions for the `.circ` compiler                    |

## Quick start

```typescript
import { initializeWasm, ComponentKind, State } from './src/index';

const renderer = await initializeWasm('./circ-renderer-lib.wasm');
const { circuit } = renderer;

const pin = circuit.createComponent(ComponentKind.InputPinGate);
const not = circuit.createComponent(ComponentKind.NotGate);
const led = circuit.createComponent(ComponentKind.Led);

circuit.connect(pin, 0, not, 1);  // pin.out → not.in
circuit.connect(not, 0, led, 1);  // not.out → led.in

circuit.propagateEvent(pin, State.High);
circuit.propagate();
// led is now Low (inverted)
```

## Repository layout

```text
lib/            Zig simulation core and WASM glue
  circuit.zig   Simulation engine (components, events, propagation)
  wasm.zig      WASM export/import layer
  memory.zig    Arena allocator
  log.zig       Conditional logging (WASM ↔ native)
  transport.zig State serialisation
  compiler.zig  CLI entry point for .circ compiler
  syntax/       PEG parser integration and parse tree walker
  grammar/      PEG grammar source for .circ format
src/
  index.ts      TypeScript SDK wrapping the WASM module
example/
  index.ts      Interactive demo application
  theme.ts      Canvas 2D rendering skins per component type
  assets.ts     Base64-encoded gate images
  circuits/     Example .circ files
build.zig       Zig build configuration (three targets)
main.zig        CLI debug harness
```

## Build

```sh
# WASM library (browser target)
zig build

# CLI debug simulator
zig build run

# .circ file compiler
zig build compiler:run -- example/circuits/demo_input.circ
```
