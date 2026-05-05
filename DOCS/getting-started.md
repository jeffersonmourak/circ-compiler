# Getting started with `circ-compile`

This walkthrough takes you from a fresh checkout to a working compiled circuit you can drive from Node. Each step has expected output so you can verify you are on track.

## 1. Install and verify the CLI

**Download a pre-built binary** from the [releases page](https://github.com/jeffersonmourak/circ-renderer-z/releases) (macOS arm64, Linux x86_64) and place it on your PATH. No Zig installation is required to use `circ-compile`.

**Or build from source** (requires [Zig](https://ziglang.org/) 0.15.x — only for building the CLI itself, not for compiling circuits):

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

The CLI runs the parser, validator, Zig source emitter, and in-process compiler end-to-end — no `zig` binary is required at circuit-compile time. On success it copies the resulting `.wasm` to the path given to `-o`. On failure it surfaces compiler errors and preserves the build directory for inspection.

Inspect the compiled circuit's interface:

```sh
zig-out/bin/circ-compile examples/inverter.circ --inspect
```

The relevant block tells you which component IDs to drive from JavaScript:

```
Inputs (1)
  id=0 name=a component=0
Outputs (1)
  id=0 name=out driver=1.out
```

`setPin` takes the **input pin's component id** (`0` for `a`). `getOutputState` takes the **driver component id** of the output (`1` here — the `not` gate that drives `out`), not the output_pin's own id.

## 4. Drive the compiled `.wasm` from Node

Create `examples/run.mjs`:

```js
import fs from "node:fs";

const bytes = fs.readFileSync(process.argv[2]);
const { instance } = await WebAssembly.instantiate(bytes, {
  env: { debugEnabled: () => 0, onDebugLog: () => {} },
});
const w = instance.exports;

w.init();
w.setPin(0, 0); w.run(); console.log("a=0 -> NOT a =", w.getOutputState(1));
w.setPin(0, 1); w.run(); console.log("a=1 -> NOT a =", w.getOutputState(1));
w.deinit();
```

Run it:

```sh
node examples/run.mjs examples/inverter.wasm
```

Expected:

```
a=0 -> NOT a = 1
a=1 -> NOT a = 0
```

`0` means low, `1` means high, `2` means undefined. The full export list (`init`, `deinit`, `reset`, `run`, `stop`, `setPin`, `getOutputState`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer`) is documented in `DOCS/wasm-api.md`. The two `env` callbacks (`debugEnabled` and `onDebugLog`) are required imports — supply the no-op stubs above unless you want debug logging.

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
  const v = w.getOutputState(i);
  if (v !== 2) console.log(`id=${i} -> ${v}`);
}
```

For a structured map use `getFileInfo()` (returns a binary blob in linear memory; layout in `DOCS/wasm-api.md`).

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

The compiler emits one `buildXxx` function per source file and call sites at instantiation points — sub-circuits are never specialised per-instance. Loading from JS uses the same pattern as step 4; discovering global IDs in deeper hierarchies is best done through `getFileInfo()`.

More worked project fixtures, including a full-adder built from two half-adders and a 4-bit AND/OR network, live under `tests/fixtures/projects/` and double as integration tests.

## Where to go next

- `DOCS/circuit-format.md` — the complete `.circ` language reference (declarations, ports, anonymous components, built-ins).
- `DOCS/wasm-api.md` — every export and import on the compiled artifact, including the `getFileInfo()` introspection blob layout.
- `DOCS/architecture.md` and `DOCS/decisions/` — design rationale, useful when contributing.
- `tests/fixtures/circuits/` and `tests/fixtures/projects/` — copy-and-modify templates for common circuit patterns.
