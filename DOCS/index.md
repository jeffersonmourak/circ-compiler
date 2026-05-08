# circ-compiler Documentation

`circ-compiler` is a Zig CLI that compiles `.circ` digital-logic source files into self-contained WebAssembly modules. Each compiled `.wasm` embeds a prebuilt simulation runtime plus the circuit's topology (as custom sections) and exposes a small fixed API — `init`, `run`, `setPin`, `getOutputState` — usable from any host that supports WebAssembly.

## What it does

Given a `.circ` source like:

```text
input a
not inv(in=a)
output out(in=inv.out)
```

`circ-compile inverter.circ -o inverter.wasm` produces a `.wasm` artifact whose exports simulate that exact circuit. Multi-file projects work the same way: the root file imports siblings; the compiler resolves the project, validates it, flattens the hierarchy, and serializes it into the resulting `.wasm` as `circ.topology.v0.min` (runtime) plus `circ.topology.v0.full` (tooling).

## Documents

| Document                                     | Contents                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------- |
| [getting-started.md](getting-started.md)     | New-user walkthrough: install, first `.circ`, compile, drive from Node  |
| [architecture.md](architecture.md)           | Pipeline, layers, build targets, prebuilt runtime model                 |
| [simulation-engine.md](simulation-engine.md) | Zig API reference for `lib/circuit.zig`: types, propagation, gate logic |
| [wasm-api.md](wasm-api.md)                   | Runtime API exposed by the compiled `.wasm`: imports, exports, sections |
| [circuit-format.md](circuit-format.md)       | `.circ` DSL syntax, grammar, file examples                              |
| [preview.md](preview.md)                     | `circ-compile --preview`: ASCII circuit schematic rendering             |
| [decisions/](decisions/index.md)             | Architectural decisions for the `.circ` compiler                        |
| [archive/](archive/index.md)                 | Archived implementation plans                                           |
| [prompts/ARCHIVE.md](prompts/ARCHIVE.md)     | How to archive a finished plan into `DOCS/archive/`                     |

## Quick start

```sh
# Build the CLI (one-time).
zig build circ-compile

# Compile a circuit to a self-contained .wasm.
zig-out/bin/circ-compile inverter.circ -o inverter.wasm

# Or inspect / preview without producing an artifact.
zig-out/bin/circ-compile inverter.circ --inspect
zig-out/bin/circ-compile inverter.circ --preview
```

Drive the compiled `.wasm` from any WebAssembly host. A minimal Node.js example:

```js
import fs from "node:fs";

const bytes = fs.readFileSync("inverter.wasm");
const mod   = await WebAssembly.compile(bytes);
const { exports: w } = await WebAssembly.instantiate(mod, {
  env: { debugEnabled: () => 0, onDebugLog: () => {} },
});

// Copy the topology custom section into the runtime's linear memory.
const [topo] = WebAssembly.Module.customSections(mod, "circ.topology.v0.min");
const ptr = w.topology_alloc(topo.byteLength);
new Uint8Array(w.memory.buffer).set(new Uint8Array(topo), ptr);

w.init();
w.setPin(0, 1);                    // drive input pin (id=0) high
w.run();
console.log(w.getOutputState(1));  // 0 = low (NOT of high)
```

See [wasm-api.md](wasm-api.md) for the full export contract.

## Repository layout

```text
cmd/
  circ-compile/main.zig    CLI entry point (parser → resolver → validator → topology → emit)

lib/
  circuit.zig              Pure Zig simulation engine (gates, events, propagation)
  log.zig                  Conditional logging bridge (extern → host onDebugLog)
  memory.zig               Allocator wrapper (wasm_allocator on WASM, GPA on native)
  transport.zig            State serialisation helpers
  parser.{c,h}             Vendored generated PEG parser (langlang output)
  grammar/proto-circ.peg   Source grammar for the .circ language
  syntax/                  Parse tree → AST translation, FFI to the C parser
  resolver/                scan_imports, import_cycle, resolve_bodies, builtins
  ir/                      Resolved IR (types, single-module resolver)
  validator/               Diagnostic codes (E001–E013, W001–W003) and passes
  topology/                Compact + full topology serializers, custom-section writer
  emit/                    Experimental --emit-zig path (standalone Zig output)
  preview/                 ASCII schematic layout + renderer for --preview
  cli/                     Argument parsing, --inspect dump

templates/                 The prebuilt runtime template — compiled once into
  main.zig                 zig-out/lib/circ-runtime.wasm and embedded in the CLI
  interpreter.zig          via @embedFile so end users never need Zig at runtime.

tests/                     Integration + e2e tests, golden fixtures
```

## Build

```sh
# CLI compiler
zig build circ-compile               # → zig-out/bin/circ-compile

# Prebuilt runtime template (regenerated by default zig build)
zig build                             # → zig-out/lib/circ-runtime.wasm

# Tests
zig build test                        # set CIRC_SKIP_PERF=1 to skip perf smoke
```
