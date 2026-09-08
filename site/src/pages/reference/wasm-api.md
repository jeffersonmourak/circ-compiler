---
layout: ../../layouts/DocsLayout.astro
title: "WASM Runtime API"
description: "The export and import contract for every compiled .wasm artifact."
---

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
memory:             WebAssembly.Memory
topology_alloc:     (len: i32) => i32                      // host buffer for topology bytes; returns ptr (or -1 on OOM)
init:               ()        => void                       // construct circuit from the topology buffer
run:                ()        => void                       // drain the event queue until the circuit settles
setPin:             (id: i32, value: i64, defined: i64) => void
getOutputValue:     (id: i32) => i64                        // BitVecState.value of the component's output
getOutputDefined:   (id: i32) => i64                        // BitVecState.defined of the component's output

// Memory family — meaningful only for ids of rom/ram components (see "Memory exports")
getMemInfo:         (id: i32) => i32                        // (kind << 16) | (W << 8) | A, or -1
memBuffer:          (id: i32) => i32                        // pointer to the memory's staging buffer, or -1
memLoad:            (id: i32, len: i32) => i32              // replace every cell from staging[0..len]; status
memStore:           (id: i32) => i32                        // export every cell into the staging buffer; bytes written or a negative status
memClear:           (id: i32) => i32                        // every cell becomes undefined; status
setMemWord:         (id: i32, addr: i32, value: i64, defined: i64) => i32   // write one word; status
getMemValue:        (id: i32, addr: i32) => i64             // BitVecState.value of one cell (0 on any error)
getMemDefined:      (id: i32, addr: i32) => i64             // BitVecState.defined of one cell (0 on any error)
```

The i64 fields cross the JS↔WASM boundary as `BigInt`. A component's state is a `BitVecState`-shaped `(value, defined)` pair where each bit of `defined` says whether the corresponding bit of `value` is meaningful:

| `defined` bit | `value` bit | Interpretation |
|---------------|-------------|----------------|
| `1`           | `0`         | low            |
| `1`           | `1`         | high           |
| `0`           | (ignored)   | undefined      |

For a width-`W` component, only the low `W` bits of each i64 are meaningful; bits beyond `W` are zero on read and silently dropped on write.

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

### `setPin(component_id, value, defined)`

Drives a top-level input pin to the BitVecState `(value, defined)`. `component_id` is the global integer ID of an `input_pin_gate`; passing the ID of a non-input or out-of-range component is a silent no-op (it does not throw or trap).

For width-1 inputs the usual encodings are `setPin(id, 0n, 1n)` for low, `setPin(id, 1n, 1n)` for high, and `setPin(id, 0n, 0n)` for undefined. For wider inputs each bit of `value` and `defined` corresponds to a bit position; bits set beyond the component's declared width are masked silently.

`setPin` settles the circuit before returning (it enqueues the change and drains the event queue itself), so outputs can be read immediately. Calling `run()` afterwards is a harmless no-op; the examples below keep it to make the drive/settle/read rhythm explicit.

### `getOutputValue(component_id)` and `getOutputDefined(component_id)`

Paired exports. Each call returns one of the two `BitVecState` fields of the component's current output. Returns `0n` for both if the runtime is not initialised or the ID is out of range — the host distinguishes "definitely low" from "undefined" by checking `getOutputDefined` first. The argument is the **driver component ID**, not an output-pin index — for an `output out(in=inv.out)` declaration, you pass `inv`'s component ID, not `out`'s pin ID. The `--inspect` output of the compiler prints this mapping under its `Outputs (...)` block.

#### Why paired exports instead of one out-pointer call

A previous draft considered a single-call shape: `getOutputState(id, out_ptr: i32)` that wrote a 16-byte `BitVecState` into linear memory at `out_ptr`. Two reasons the paired-export shape won:

- **Simpler host code.** Two function calls return BigInts that the host combines directly. No buffer allocation, no pointer arithmetic, no in-band encoding to standardise (endianness, alignment, sentinel for undefined).
- **The 2× call overhead is irrelevant in practice.** Hosts typically read once after settle, not in a hot loop. If a future use case needs batched reads, a sibling export (`getOutputStateBatch(ids_ptr, out_ptr, count)`) can be added without breaking the paired API.

## Memory exports (`rom` / `ram`)

A memory declares only its shape in source (`rom code[8, 4](addr = pc.out)`, `ram data[8, 4](addr = …, din = …, we = …, clk = …)`); its contents are runtime state that the host loads and reads back through the eight `mem*`/`getMem*` exports. Ids are the same positional component ids `setPin` uses. A memory's id is the id of its record in the `circ.topology.v0.full` section (kind `8` for `rom`, `9` for `ram`, matched by `name`); `getMemInfo` confirms the id and returns the widths, so a host can validate its mapping once up front.

A memory's `out` is its asynchronous read port — `getOutputValue(mem_id)` / `getOutputDefined(mem_id)` return the word at the currently presented address, exactly like any other component's output. Cells that were never loaded or written read as undefined (`defined = 0`). A `ram` additionally writes `din` into the addressed cell on a *defined low → defined high* transition of `clk` while `we` is high; the clock is an ordinary input pin the host pulses with `setPin` (`setPin(clk, 0n, 1n)` then `setPin(clk, 1n, 1n)`).

### Image format

Contents cross the boundary as a **headerless raw image**: word `i` occupies bytes `[i * bpw, (i + 1) * bpw)` with `bpw = ceil(W / 8)`, little-endian, and every bit at or above `W` must be zero. The image length must be a whole number of words and at most `2^A` words. A shorter image leaves the remaining cells undefined; an empty image clears the memory. Definedness is not representable on disk: `memLoad` marks every loaded word fully defined, and `memStore` writes `value & defined` (undefined bits become `0`).

### Staging protocol

`memBuffer(id)` returns a pointer to a per-memory staging buffer sized for one full image (`bpw << A` bytes). It is allocated once and reused for every later call; the allocation may grow linear memory, so **re-take your `Uint8Array` view of `memory.buffer` after each `memBuffer` call**.

- **Load:** `ptr = memBuffer(id)`; copy the image bytes to `ptr`; `rc = memLoad(id, bytes.length)`; treat any `rc !== 0` as a failure (codes below). The whole memory is replaced.
- **Export:** `n = memStore(id)`; the image is `memory.buffer[memBuffer(id) .. +n]`.
- **Single words:** `setMemWord(id, addr, value, defined)` writes one cell (masked to `W`, canonicalised to `value & defined`); `getMemValue`/`getMemDefined(id, addr)` read one cell.
- **Clear:** `memClear(id)` makes every cell undefined.

Every mutator re-presents the memory's `out` before returning: after `memLoad`, `setMemWord`, or `memClear`, `getOutputValue` on the memory — or on anything it drives — already reflects the new contents, with no `run()` needed. A load or write that leaves the currently presented word unchanged does not advance simulated time.

### Status codes

`memLoad`, `memStore`, `memClear`, and `setMemWord` return `0` on success, or:

| Code | Meaning |
|------|---------|
| `-1` | runtime not initialised, id out of range, or the id is not a `rom`/`ram` |
| `-2` | image length is not a whole number of words |
| `-3` | a word has a bit set at or above the data width `W` |
| `-4` | more words than the memory holds (`> 2^A`) |
| `-5` | `len` is negative or exceeds the staging buffer |
| `-6` | `memBuffer` was never called for this memory |
| `-7` | `addr` is negative or `>= 2^A` |

`memStore` returns the number of bytes written (`bpw << A`) on success. `getMemInfo` returns `-1` for anything that is not a memory. `-4` cannot occur through `memLoad` — the staging buffer is exactly one full image, so an oversize `len` is reported as `-5` before the image is parsed — but the same image rules apply to file-backed loading in `--sim`, where it is reported as an `E_MEMFMT` reason. These codes matter because `init()` swallows its own errors: a mutator's status is the host's one diagnostic.

### Node example

```js
const mem = 1;                                          // id of the kind-8/9 record named "code" in circ.topology.v0.full
const info = w.getMemInfo(mem);
if (info < 0) throw new Error("not a memory");
const W = (info >> 8) & 0xff, A = info & 0xff;          // data width, address width

// Load a raw image (here: word i = i * 0x11).
const image = new Uint8Array(1 << A).map((_, i) => i * 0x11);
const ptr = w.memBuffer(mem);                           // may grow memory: re-view after
new Uint8Array(w.memory.buffer).set(image, ptr);
const rc = w.memLoad(mem, image.length);
if (rc !== 0) throw new Error(`memLoad failed with ${rc}`);

w.setPin(pc_id, 3n, 0xfn);                              // present address 3
console.log(w.getOutputValue(mem), w.getOutputDefined(mem)); // 0x33n 0xffn

w.setMemWord(mem, 3, 0x77n, 0xffn);                     // out follows at once, no run() needed
const n = w.memStore(mem);                              // export: value & defined per word
const dump = new Uint8Array(w.memory.buffer, w.memBuffer(mem), n).slice();
```

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
w.setPin(0, 1n, 1n);                            // pin id=0 → high (value=1, defined=1)
w.run();
const value   = w.getOutputValue(1);            // BigInt
const defined = w.getOutputDefined(1);          // BigInt
console.log(defined === 0n
  ? "undefined"
  : value === 0n ? "low" : "high");             // "low" (NOT of high)
```

For wider inputs, the helper pattern is:

```js
// Drive a width-4 input bus to the value 0b1010, all four bits defined.
w.setPin(input_id, 0b1010n, 0b1111n);
w.run();
const v = w.getOutputValue(output_id);  // e.g. 0b1010n for a passthrough
const d = w.getOutputDefined(output_id); // 0b1111n
```

To collapse a paired read back into the legacy 3-state encoding when integrating with code that still uses it:

```js
const readScalar = (id) =>
  w.getOutputDefined(id) === 0n
    ? 2                               // undefined
    : w.getOutputValue(id) === 0n ? 0 : 1; // low / high
```

## Things that are *not* exports today

Earlier drafts of this project anticipated additional exports — `deinit`, `reset`, `stop`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer` — and a separate `onStateChange` import. None of these are present in the artifact produced by `circ-compile … -o out.wasm` today. The extra exports survive only in `lib/emit/runtime.zig`, the experimental `--emit-zig` pipeline; the `onStateChange` import was never wired into any pipeline and exists nowhere in the codebase. Either may appear in a future runtime version. If your host needs change-notifications, poll `getOutputValue` / `getOutputDefined` after each `run()`.
