# Getting started with `circ-compile`

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
File [f0:1:1-4:1]
Imports (0)
Inputs (1)
  Input a [f0:1:1-1:8]
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

The not-gate's output fans out to both the LED and the `out` pin — `●` marks the branch point, and the two `▶` arrowheads show where each branch terminates. See [`preview.md`](preview.md) for `--expand-macros`, `--color`, and the rendering conventions.

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

`--truth-table` runs the resolver and validator first; circuits with combinational loops (E008) are rejected before any simulation, and so is any circuit containing a `ram` (stateful — drive it with `--sim` instead). The mode caps at 16 total input *bits* (an `input[4]` counts four; 2^16 = 65,536 rows) to avoid accidental blow-up; `--truth-table-cap=N` raises that to at most 24, and wider circuits should be exercised through the `.wasm` runtime instead.

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

The two i64 parameters cross the boundary as JavaScript `BigInt` values; `value` and `defined` each pack one bit per signal bit. A scalar pin uses `(0n, 1n)` for low, `(1n, 1n)` for high, and `(_, 0n)` for undefined. The core export list emitted by `circ-compile … -o out.wasm` is `topology_alloc`, `init`, `run`, `setPin`, `getOutputValue`, `getOutputDefined` (plus `memory`); every artifact also exports the memory family `getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, `getMemDefined`, meaningful only for the ids of `rom`/`ram` components (step 7 below); see [`DOCS/wasm-api.md`](wasm-api.md) for the full contract. The two `env` callbacks (`debugEnabled` and `onDebugLog`) are required imports — supply the no-op stubs above unless you want debug logging.

### Driving a multi-bit input

For a wider input declared as `input[4] a`, both `value` and `defined` use one bit per signal bit. To drive a 4-bit bus to the value `0b1010` with every bit defined:

```js
w.setPin(input_id, 0b1010n, 0b1111n);
w.run();
const v = w.getOutputValue(output_id);   // BigInt, e.g. 0b1010n for a passthrough
const d = w.getOutputDefined(output_id); // BigInt, 0b1111n
```

Bits set beyond the declared width are silently masked. See [`DOCS/wasm-api.md`](wasm-api.md) for the full `BitVecState` semantics.

## 5. Use a built-in macro (`xor`)

Built-in gates `or`, `nand`, `nor`, `xor`, and `xnor` are auto-imported whenever a file uses one: the compiler takes the project pipeline for any root that declares an import *or* instantiates a built-in, so a standalone file can write `xor x(a=a, b=b)` with no `import` line. The explicit import from the virtual `<builtin>/` filesystem remains valid and is the form used below:

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

> **v0 papercut.** `--inspect` alone stays in single-module mode and does not auto-import built-ins, so a bare `xor` shows up there as `E001: undeclared name 'xor'`. Compile (`-o`), `--emit-zig`, `--preview`, `--truth-table` and `--sim` all resolve it; add the explicit `import xor "<builtin>/xor.circ"` only if you want `--inspect`'s view of the file to be clean.

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

## 7. Loading a program into ROM and stepping a clocked circuit

`rom` and `ram` are built-in memories. A declaration gives only the *shape* — `[W, A]` is `W` bits per word and `2^A` words — and the contents are loaded at run time, so the same compiled circuit can run any program you hand it. This step authors an image, loads it three ways, and pulses a RAM's clock by hand.

### 7.1 The circuit

Save this as `prog_rom.circ` (it is `tests/fixtures/circuits/sim_rom_pc_walk.circ` verbatim): a 4-bit program counter, a 16-word ROM of 8-bit instructions, and the instruction at the counter as the output.

```text
input[4] pc
rom code[8, 4](addr = pc)
output[8] instr(in = code.out)
```

There is no register primitive yet, so the program counter is an input pin the host drives — "stepping" is `set pc N`.

### 7.2 Author an image

A memory image is a headerless raw file: `ceil(W/8)` bytes per word, little-endian, high padding bits zero, at most `2^A` words. For `W = 8` that is one byte per word, so four instructions are four bytes. `printf` with octal escapes writes them from any POSIX shell (`\xHH` escapes are a bash/zsh extension; the octal form is the portable one):

```sh
printf '\020\041\062\103' > prog.bin
xxd prog.bin
```

```
00000000: 1021 3243                                .!2C
```

Word 0 is `0x10`, word 1 `0x21`, word 2 `0x32`, word 3 `0x43`; words 4–15 are not in the file and will read as undefined.

### 7.3 Preload it and walk the counter with `--sim`

`--mem=<name>=<path>` loads an image into the memory declared with that name before the session starts. Type the lines after the handshake (or pipe them in):

```sh
zig-out/bin/circ-compile prog_rom.circ --sim --mem=code=prog.bin
```

```
ready proto=1 pins=2 warnings=0
pin pc in 4
pin instr out 8
set pc 0
ok
get instr
ok 0x10 0xff
set pc 3
ok
get instr
ok 0x43 0xff
mem code 0 4
cells 4
0x0 0x10 0xff
0x1 0x21 0xff
0x2 0x32 0xff
0x3 0x43 0xff
quit
ok bye
```

Every reply is a `value mask` pair in hex; a mask of `0xff` means all eight bits are defined. `mem code 0 4` dumps four cells starting at address 0. Try `set pc 4` and `get instr` to see an unloaded cell come back as `0x0 0x0` (undefined), and `load code other.bin` to swap programs without leaving the session. The full verb list is in `DOCS/sim-protocol.md`.

### 7.4 A RAM, stepped by hand

Save `tests/fixtures/circuits/sim_ram_write_read.circ` as `scratch_ram.circ`:

```text
input[4] a
input[8] d
input w, clk
ram data[8, 4](addr = a, din = d, we = w, clk = clk)
output[8] q(in = data.out)
```

A `ram` reads asynchronously — `q` always shows the word at `a` — and writes `d` into that word on a *defined low → high* edge of `clk` while `w` is high. The clock is an ordinary input pin, so a pulse is two `set`s. Because the first level after power-on is undefined, drive the clock low once before the first rising edge:

```sh
zig-out/bin/circ-compile scratch_ram.circ --sim
```

```
ready proto=1 pins=5 warnings=0
pin a in 4
pin d in 8
pin w in 1
pin clk in 1
pin q out 8
mems
mems 1
mem data ram 8 4
set a 2
ok
set d 0x2a
ok
set w 1
ok
set clk 0
ok
set clk 1
ok
get q
ok 0x2a 0xff
set a 3
ok
get q
ok 0x0 0x0
poke data 3 0x99
ok
get q
ok 0x99 0xff
save data ram.bin
ok words=16
quit
ok bye
```

`poke` writes a cell from the host side without a clock, and `q` follows at once because address 3 was being presented. `save` writes the whole memory as an image — undefined cells become `0x00`:

```sh
xxd ram.bin
```

```
00000000: 0000 2a99 0000 0000 0000 0000 0000 0000  ..*.............
```

`poke`-then-`save` is also the quickest way to author an image interactively for `--mem` later.

### 7.5 The same ROM from Node

A compiled artifact exposes the memory through the `mem*` exports. Compile `prog_rom.circ` and note the ids `--inspect` prints — `pc` is component `0` and `code` is `1` here (for multi-file projects, read them from the `circ.topology.v0.full` section, as [`DOCS/wasm-api.md`](wasm-api.md) describes):

```sh
zig-out/bin/circ-compile prog_rom.circ -o prog_rom.wasm
zig-out/bin/circ-compile prog_rom.circ --inspect | grep 'kind=rom'
#   id=1 name=code kind=rom[W=8,A=4] width=8
```

`run_rom.mjs` instantiates the module as in step 4, then loads the image through the staging buffer:

```js
import fs from "node:fs";

const bytes = fs.readFileSync(process.argv[2]);
const mod = await WebAssembly.compile(bytes);
const { exports: w } = await WebAssembly.instantiate(mod, {
  env: { debugEnabled: () => 0, onDebugLog: () => {} },
});

const [topoSection] = WebAssembly.Module.customSections(mod, "circ.topology.v0.min");
const topoBytes = new Uint8Array(topoSection);
const topoPtr = w.topology_alloc(topoBytes.length);
new Uint8Array(w.memory.buffer).set(topoBytes, topoPtr);
w.init();

const pc = 0, code = 1;                                 // ids from `circ-compile prog_rom.circ --inspect`
const info = w.getMemInfo(code);
if (info < 0) throw new Error("not a memory");
const W = (info >> 8) & 0xff, A = info & 0xff;
console.log(`code: W=${W} A=${A}`);

const img = fs.readFileSync(process.argv[3]);
const ptr = w.memBuffer(code);                          // may grow memory: re-view after
new Uint8Array(w.memory.buffer).set(img, ptr);
const rc = w.memLoad(code, img.length);
if (rc !== 0) throw new Error(`memLoad failed with ${rc}`);

for (const addr of [0n, 3n, 4n]) {
  w.setPin(pc, addr, 0xfn);                             // setPin settles; no run() needed
  console.log(`pc=${addr} -> instr=0x${w.getOutputValue(code).toString(16)} defined=0x${w.getOutputDefined(code).toString(16)}`);
}

const n = w.memStore(code);
fs.writeFileSync("rom-after.bin", new Uint8Array(w.memory.buffer, w.memBuffer(code), n).slice());
console.log(`stored ${n} bytes`);
```

```sh
node run_rom.mjs prog_rom.wasm prog.bin
xxd rom-after.bin
```

```
code: W=8 A=4
pc=0 -> instr=0x10 defined=0xff
pc=3 -> instr=0x43 defined=0xff
pc=4 -> instr=0x0 defined=0x0
stored 16 bytes
00000000: 1021 3243 0000 0000 0000 0000 0000 0000  .!2C............
```

`memStore` exports all `2^A` words, writing `value & defined` so the twelve undefined cells come out as zeros. Every mutator returns `0` on success or a negative status code (`-2` length not a whole number of words, `-3` a word with bits beyond `W`, …) — the table is in [`DOCS/wasm-api.md`](wasm-api.md). Read `getOutputValue(code)` directly on the memory's id, or on whatever it drives; the ROM's `out` is the same asynchronous read `instr` sees.

## Where to go next

- `DOCS/circuit-format.md` — the complete `.circ` language reference (declarations, ports, anonymous components, built-ins).
- `DOCS/language.md` §6.5 — the `rom`/`ram` reference: ports, X rules, the edge rule, and how contents get in.
- `DOCS/wasm-api.md` — every export and import on the compiled artifact, plus the topology custom-section layout.
- `DOCS/sim-protocol.md` — the `--sim` drive protocol, including `--mem` preloads and the memory verbs.
- `DOCS/architecture.md` and `DOCS/decisions/` — design rationale, useful when contributing.
- `tests/fixtures/circuits/` and `tests/fixtures/projects/` — copy-and-modify templates for common circuit patterns.
