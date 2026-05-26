---
layout: ../../layouts/DocsLayout.astro
title: "Getting Started"
description: "Install the compiler, write your first circuit, and drive it from Node."
---

This walkthrough takes you from a fresh checkout to a working compiled circuit you can drive from Node. Each step has expected output so you can verify you are on track.

## 1. Install and verify the CLI

You need [Zig](https://ziglang.org/) 0.15.x. Build the compiler:

```sh
zig build circ-compile
```

The binary lands at `zig-out/bin/circ-compile`. Verify it works by compiling a fixture from the test suite:

```sh
zig-out/bin/circ-compile tests/fixtures/circuits/inverter.circ --inspect | head -8
```

Expected:

```
=== Parse Tree ===
File [f0:1:1-3:23]
Imports (0)
Inputs (1)
  Input a [f0:1:7-1:8]
Outputs (1)
  Output out [f0:3:1-3:23]
    NamedRef inv.out [f0:3:15-3:22]
```

If you see that, the compiler is working.

## 2. Write your first `.circ` file

Create `examples/inverter.circ`:

```text
input a
not inv(in=a)
led l(in=inv.out)
output out(in=inv.out)
```

This declares one input pin `a`, drives it through a `not` gate, mirrors the result on an `led` (visualisation primitive), and exposes the inverted signal as an `output` pin. See `DOCS/circuit-format.md` for the full language reference.

## 3. Compile it to WebAssembly

```sh
zig-out/bin/circ-compile examples/inverter.circ -o examples/inverter.wasm
```

The CLI runs the parser, validator, and topology serializer end-to-end, then appends the serialized circuit as `circ.topology.v0.min` and `circ.topology.v0.full` custom WASM sections to the pre-built runtime blob. No `zig` subprocess is spawned. On success it writes the combined `.wasm` to the path given to `-o`.

Inspect the compiled circuit's interface:

```sh
zig-out/bin/circ-compile examples/inverter.circ --inspect
```

Or visualise the circuit as an ASCII schematic without producing any artifact:

```sh
zig-out/bin/circ-compile examples/inverter.circ --preview
```

Expected:

```
╭───╮     ╭───╮     ╭───╮  
│ a ├○───▶┤NOT├○●──▶┤LED│  
╰───╯     ╰───╯ │   ╰───╯  
                │          
                │   ╭─────╮
                ╰──▶┤ out │
                    ╰─────╯
```

The not-gate's output fans out to both the LED and the `out` pin — `●` marks the branch point, and the two `▶` arrowheads show where each branch terminates. See [`preview.md`](/reference/preview) for `--expand-macros`, `--color`, and the rendering conventions.

Or enumerate the circuit's behaviour against every input combination as a Markdown truth table:

```sh
zig-out/bin/circ-compile examples/inverter.circ --truth-table
```

```
| a | out |
|---|-----|
| 0 | 1   |
| 1 | 0   |
```

`--truth-table` runs the resolver and validator first; circuits with combinational loops (E008) are rejected before any simulation. The mode caps at 16 inputs (2^16 = 65,536 rows) to avoid accidental blow-up — wider circuits should be exercised through the `.wasm` runtime instead.

The relevant block tells you which component IDs to drive from JavaScript:

```
Inputs (1)
  id=0 name=a component=0
Outputs (1)
  id=0 name=out driver=1.out
```

`setPin(id, value, defined)` takes the **input pin's component id** (`0` for `a`) along with a `(value, defined)` `BitVecState` pair. The paired output reads `getOutputValue(id)` and `getOutputDefined(id)` take the **driver component id** of the output (`1` here — the `not` gate that drives `out`), not the output_pin's own id.

## 4. Drive the compiled `.wasm` from Node

The compiled `.wasm` contains the runtime and a `circ.topology.v0.min` custom section. The host must load that section into WASM linear memory before calling `init()`. Create `examples/run.mjs`:

```js
import fs from "node:fs";

const bytes = fs.readFileSync(process.argv[2]);
const mod = await WebAssembly.compile(bytes);
const { exports: w } = await WebAssembly.instantiate(mod, {
  env: {
    debugEnabled: () => 0,
    onDebugLog: () => {},
  },
});

// Load the circ.topology.v0.min custom section into WASM linear memory
const [topoSection] = WebAssembly.Module.customSections(mod, "circ.topology.v0.min");
const topoBytes = new Uint8Array(topoSection);
const ptr = w.topology_alloc(topoBytes.length);
new Uint8Array(w.memory.buffer).set(topoBytes, ptr);

w.init();

const read = (id) =>
  w.getOutputDefined(id) === 0n
    ? "undefined"
    : w.getOutputValue(id) === 0n ? "low" : "high";

w.setPin(0, 0n, 1n); w.run(); console.log("a=0 -> NOT a =", read(1));
w.setPin(0, 1n, 1n); w.run(); console.log("a=1 -> NOT a =", read(1));
```

Run it:

```sh
node examples/run.mjs examples/inverter.wasm
```

Expected:

```
a=0 -> NOT a = high
a=1 -> NOT a = low
```

The two i64 parameters cross the boundary as JavaScript `BigInt` values; `value` and `defined` each pack one bit per signal bit. A scalar pin uses `(0n, 1n)` for low, `(1n, 1n)` for high, and `(_, 0n)` for undefined. The full export list emitted by `circ-compile … -o out.wasm` today is exactly `topology_alloc`, `init`, `run`, `setPin`, `getOutputValue`, `getOutputDefined` (plus `memory`); see [`DOCS/wasm-api.md`](/reference/wasm-api) for the full contract. The two `env` callbacks (`debugEnabled` and `onDebugLog`) are required imports — supply the no-op stubs above unless you want debug logging.

### Driving a multi-bit input

For a wider input declared as `input[4] a`, both `value` and `defined` use one bit per signal bit. To drive a 4-bit bus to the value `0b1010` with every bit defined:

```js
w.setPin(input_id, 0b1010n, 0b1111n);
w.run();
const v = w.getOutputValue(output_id);   // BigInt, e.g. 0b1010n for a passthrough
const d = w.getOutputDefined(output_id); // BigInt, 0b1111n
```

Bits set beyond the declared width are silently masked. See [`DOCS/wasm-api.md`](/reference/wasm-api) for the full `BitVecState` semantics.

## 5. Use a built-in macro (`xor`)

Built-in gates `or`, `nand`, `nor`, `xor`, and `xnor` are auto-imported when a file is part of a project — i.e. when the parser sees at least one `import` declaration. To use a built-in in an otherwise standalone file, add an explicit import to the virtual `<builtin>/` filesystem:

```text
// examples/xor_demo.circ
import xor "<builtin>/xor.circ"
input a, b
xor x(a=a, b=b)
output out(in=x.out)
```

Compile and inspect:

```sh
zig-out/bin/circ-compile examples/xor_demo.circ -o examples/xor.wasm
zig-out/bin/circ-compile examples/xor_demo.circ --inspect
```

> **v0 papercut.** When the file has no user imports, single-file mode does not auto-import built-ins, so a bare `xor` raises `E001: undeclared name 'xor'`. The explicit `import xor "<builtin>/xor.circ"` is the workaround until the CLI is updated to run the project pipeline unconditionally.

Once a file participates in the project pipeline, root-pin component IDs are assigned in a flat layout that includes the built-in macro's expanded gates. The simplest way to discover them is to scan in JS:

```js
for (let i = 0; i < 64; i++) {
  if (w.getOutputDefined(i) !== 0n) {
    console.log(`id=${i} -> value=${w.getOutputValue(i)} defined=${w.getOutputDefined(i)}`);
  }
}
```

For a structured map, parse the `circ.topology.v0.full` custom section in JS — it carries per-file IDs, component aliases, and macro provenance. (A future runtime release may surface this through a `getFileInfo()` export, but it is not present in today's compiled artifacts.)

## 6. Compose with a sub-circuit import

Sub-circuits live in their own `.circ` files and are imported by alias. The half-adder is a canonical two-file project:

```text
// examples/half_adder/half_adder.circ
input a, b
xor s(a=a, b=b)
and c(a=a, b=b)
output sum(in=s.out)
output carry(in=c.out)
```

```text
// examples/half_adder/root.circ
import half_adder "half_adder.circ"
input a, b
half_adder ha(a=a, b=b)
output sum(in=ha.sum)
output carry(in=ha.carry)
```

Compile from the root:

```sh
zig-out/bin/circ-compile examples/half_adder/root.circ -o examples/half_adder.wasm
```

Sub-circuits are fully flattened by the serializer into a single ordered sequence of primitive components — no function calls, no hierarchy in the runtime. Loading from JS uses the same `topology_alloc` + `init()` pattern as step 4; discovering global IDs in deeper hierarchies is currently easiest via `circ-compile --inspect`, which prints the resolved IR with each `Inputs (...)` / `Outputs (...)` block annotated with component IDs. (The `circ.topology.v0.full` custom section carries the same information for programmatic readers.)

More worked project fixtures, including a full-adder built from two half-adders and a 4-bit AND/OR network, live under `tests/fixtures/projects/` and double as integration tests.

## Where to go next

- `DOCS/circuit-format.md` — the complete `.circ` language reference (declarations, ports, anonymous components, built-ins).
- `DOCS/wasm-api.md` — every export and import on the compiled artifact, plus the topology custom-section layout.
- `DOCS/architecture.md` and `DOCS/decisions/` — design rationale, useful when contributing.
- `tests/fixtures/circuits/` and `tests/fixtures/projects/` — copy-and-modify templates for common circuit patterns.
