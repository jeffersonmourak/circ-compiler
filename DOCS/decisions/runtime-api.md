# Runtime API

The compiled `.wasm` artifact exposes a fixed runtime API for hosts (browsers, Node, any WASM runtime). Consumers can drive pins, settle the circuit, and read outputs — but cannot extend the circuit at runtime. For the full signature reference see [`../wasm-api.md`](../wasm-api.md); this file captures the load-bearing decisions behind that surface.

### Settle-only `run()`

**Decision.** `run()` drains the event queue synchronously and returns when the circuit has settled. There is no continuous-time mode and no host-driven tick loop.

**Rationale.** Settle-only matches the existing engine in `lib/circuit.zig` exactly — one `propagate()` call advances the circuit until quiescent. It's the simplest mental model for hosts: "I changed a pin, I want the circuit to react, then I read the result." Clocked simulation and free-running modes can be added later without breaking this API; they are additive.

**Alternatives.** Tick-based `run(ticks)` for clocked circuits and free-running modes were considered. Both require either a clock primitive in the engine or host-driven ticking, neither of which is in scope today. Adding them now would commit to a more complex API surface before the use case is concrete.

### Initial state is implicitly `undefined`; `init()` does not pre-settle

**Decision.** After `init()` runs, every component's stored state is the `BitVecState.undefined_(width)` value that `Circuit.allocateStateSlot` populates (`defined = 0`, `value = 0`). The host must drive pins via `setPin` and call `run()` before any output read is meaningful.

**Rationale.** "All-undefined" is the most honest representation of "nothing has happened yet" — it doesn't pretend any pin has a value the host hasn't supplied. It mirrors what a real circuit looks like before power-on: indeterminate. Hosts that want a defined starting state drive their preferred pin values and call `run()`.

**Alternatives.** A separate `reset()` export that re-establishes this state mid-life was considered and dropped: hosts that want to "restart" the circuit can re-instantiate the WASM module, which is what every host already does between simulation runs. Pins-low-then-settle (always lands in a defined state, easier for tests) and post-initial-settle inside `init()` (replays a boot sequence) bake host-policy into the runtime; the all-undefined start lets the host decide.

### Pin identification by component ID

**Decision.** `setPin(component_id, value, defined)` accepts the **input pin's** component ID. The paired `getOutputValue(component_id)` / `getOutputDefined(component_id)` getters accept the **driver** component ID — that is, the ID of the component whose `out` port feeds the `output` declaration, not the `output_pin`'s own ID. There is no separate pin-index space.

**Rationale.** One identifier scheme is simpler than two. Component IDs are dense `0..nodes.len` integers assigned by `Circuit.createComponent` and stable for the life of a compiled artifact (the topology serializer fixes them at emission time), so they're as stable as a separate pin index would be. The mapping from declaration name to component ID is printed under each module's `Inputs (...)` / `Outputs (...)` block by `circ-compile --inspect`, and the same information is encoded in the `circ.topology.v0.full` custom section for programmatic readers.

**Alternatives.** A separate pin index (`0..N` for inputs, `0..M` for outputs) decouples the host API from internal IDs, but in this design the IDs are already stable; the abstraction would add a translation table for no clear benefit.

### Paired BigInt exports for outputs

**Decision.** Output state crosses the WASM boundary as two `i64` (`BigInt`) calls — `getOutputValue(id)` returns the `BitVecState.value` bits, `getOutputDefined(id)` returns the `BitVecState.defined` mask. Hosts combine them however they want; the convention is `defined === 0n` ⇒ undefined, otherwise read `value`.

**Rationale.** Two simple calls returning JavaScript-native `BigInt`s avoid the alternatives' costs: no buffer allocation, no pointer arithmetic, no in-band encoding for endianness or alignment, no sentinel value for undefined. Each call carries up to 64 bits of state, enough for any legal `BitVecState` width (1–64). For typical hosts that read once per settle, the 2× call overhead is irrelevant; a future `getOutputStateBatch(ids_ptr, out_ptr, count)` could be added without breaking this API.

**Alternatives.** A single `getOutputState(id, out_ptr: i32)` that writes a 16-byte `BitVecState` into linear memory at `out_ptr`. Tighter on the wire but forces every host to allocate a scratch buffer and parse it; the paired-export shape is friendlier for the dominant "read one output after settle" use case. A scalar `getOutputState(id) -> i32` returning `0`/`1`/`2` predates multi-bit and can't represent bit-width-`N` state without information loss.

### `setPin` is symmetric with the output getters

**Decision.** `setPin(component_id: i32, value: i64, defined: i64) -> void`. The host writes the same `(value, defined)` shape it reads. Bits beyond the input pin's declared width are silently masked.

**Rationale.** Treating input and output state as the same data shape keeps host code symmetric ("read state, mutate state, write state"). Silent masking on input is consistent with the engine's existing behaviour for over-wide writes via `Pool.write`. Passing the ID of a non-input or out-of-range component is a no-op rather than a trap, which matches `getOutputValue`/`getOutputDefined`'s silent-zero behaviour and means hosts can scan ID ranges defensively.

**Alternatives.** A separate `setInputBit(id, bit_index, state)` for sparse updates was considered; rejected because the bit-parallel form covers the same cases, and the bit-by-bit form would require the host to read-modify-write (or for the engine to do it internally, adding allocations).

### Pull-based with no host callbacks beyond logging

**Decision.** The compiled artifact is purely pull-based — after `run()` returns, the host polls outputs via the paired getters. There is no `onStateChange` import, no event queue exposed to the host, and no listener registration. The only host imports are `debugEnabled` (returns whether log emission is wanted) and `onDebugLog` (receives UTF-8 log buffers).

**Rationale.** Removing the FFI callback keeps the WASM module self-contained — every required import is stub-able with two no-op JS functions, so instantiation works in any environment that supports WebAssembly. Change-notifications, debouncing, diffing — every flavour of "tell me when X changed" — belongs in host code, where the host can pick its own strategy without the WASM boundary in the way.

**Alternatives.** The original `lib/wasm.zig` prototype installed an `onStateChange` callback. That worked for the dynamic API but created an instantiation prerequisite that complicated non-browser hosts. The native engine still exposes a `listener` callback for in-process test harnesses; it's intentionally not surfaced through the WASM boundary.

### Topology section copied into linear memory at startup

**Decision.** The compiled `.wasm` carries the circuit topology as a `circ.topology.v0.min` custom section, not in linear memory. The host reads the section via `WebAssembly.Module.customSections`, calls `topology_alloc(byteLength)` to reserve a buffer in linear memory, copies the bytes, then calls `init()`. `init()` parses the buffer and constructs the circuit. The section name still starts with `v0` for backwards-compatible host code; the version byte inside (`0x03`) is the format axis that evolves.

**Rationale.** WASM custom sections are opaque to the module itself — there is no in-module API to read them. The three-call protocol (`topology_alloc` → `memcpy` → `init`) is the smallest portable bridge any JS host can implement without an SDK. Hosts that don't need rendering metadata can ignore the parallel `circ.topology.v0.full` section, which carries the same structural data plus per-component names and macro provenance.

**Alternatives.** Passing topology bytes through WASM imports at instantiation (rejected: `WebAssembly.instantiate` takes imports, not arbitrary data; topology can be hundreds of KB). Encoding topology in the module's data section so `init()` can read it directly (rejected: requires modifying the WASM binary structure, not just appending; the section-then-copy protocol works against the appended-section pipeline today).

### Things deliberately *not* exported

The artifact intentionally omits several exports that earlier drafts considered:

- `deinit()`, `reset()`, `stop()` — lifecycle controls. Re-instantiating the module covers every use case for `reset`/`deinit`; `stop` would only matter for non-settle-only run modes that don't exist.
- `getStateSnapshot()`, `getTopology()`, `getPendingEvents()` — bulk introspection returning `(ptr, len)` buffers. The paired getters cover the per-component state case; topology lives in custom sections that the host already has direct access to.
- `getFileInfo()` — pin-name / source-path metadata. Same information lives in the `circ.topology.v0.full` custom section and in `circ-compile --inspect` output.
- `freeBuffer()` — companion to the introspection exports above; not needed because no export currently returns an owned buffer.

A richer surface (`getStateSnapshot`, `getFileInfo`, `freeBuffer`, …) still exists in `lib/emit/runtime.zig`, the experimental `--emit-zig` pipeline. That path is not on the default compile and its export contract is not stable.

The list above is a list of *omissions*, not a promise that the six original exports are the whole surface: topology v03 added the memory export family (`getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, `getMemDefined`) as the first additive extension — see `## Native memories` below.

The `circ_alloc`/`circ_free`/`circ_version`/`circ_analyze`/`circ_compile`/`circ_preview`/`circ_truth_table`/`circ_result_ptr`/`circ_result_len`/`circ_reset` exports belong to the *library* module `libcirc.wasm` ([libcirc.md](libcirc.md)), never to a compiled artifact; an artifact's import set stays `env.debugEnabled`/`env.onDebugLog`.

---

## Native memories

The entries below record the engine, format, runtime and tooling half of the native-memory initiative; the numbered decisions they cite are the eleven locked in `DOCS/PLANS_PROMPT.md`. The language half is in [language.md](language.md) `## Native memories`. The host-facing reference is `DOCS/wasm-api.md` "Memory exports"; the `--sim` reference is `DOCS/sim-protocol.md`.

### One engine kind with a mode; two wire kinds; one IR variant

**Decision.** The engine has a single `ComponentType.memory` whose payload carries `mode: enum { rom, ram }`. The wire format keeps two kinds (`rom = 8`, `ram = 9`), and the IR one variant, `ComponentKind.memory { mode, data_width, addr_width }`. Every *policy* site — cycle-breaking, required ports, truth-table rejection, preview glyph — dispatches on the IR or wire kind; inside the engine the two modes differ only in which ports `connect` accepts and one `if (mode == .ram)` block in the recalc arm.

**Rationale.** Decision 1. Read-side behaviour (cells, async `out`, host hooks, image codec) is identical for both, so two engine kinds would have duplicated everything but the edge rule. Keeping two *wire* kinds preserves the format's one-byte-kind-per-record convention and lets readers that never touch the engine (`--preview`, `full_decoder`, `circ-renderer`) tell them apart without an aux byte.

**Alternatives.** Two engine kinds (`rom`, `ram`) — clean in isolation but every hook and test doubles. One wire kind plus a mode flag in aux — saves nothing (the record needs an aux byte for `addr_width` anyway) and makes the kind byte lie to tooling.

### Cells are two `[]u64` planes on the payload

**Decision.** A memory's cells live in two heap-allocated planes on the component payload, `values: []u64` and `defined: []u64`, one entry per address (`2^A` entries, `A ≤ 16`), allocated in `createComponent`. Cells are not stored in the width-tiered state pools.

**Rationale.** The pools are sized for one `BitVecState` per component and are capped at 64 bits; a memory is `2^A` such states. Separate planes keep the pool layout, the `PoolHandle` scheme, and every existing state-slot invariant untouched, and they make the image codec a straight loop over one array. This was a choice, not a necessity: the plan review showed the pools *could* host cells behind a range handle, at the price of teaching every pool consumer about ranges.

**Alternatives.** Pool-hosted cells (rejected as above). A single interleaved `[]BitVecState` — half the allocations but twice the stride for the codec's hot loop and the `defined` scan `memStore` does. Lazy allocation on first write — saves memory for unused address space but makes `getMemValue` on an untouched memory a branch on every read.

### Headerless raw image, `ceil(W/8)` bytes per word, strict padding

**Decision.** Contents cross every boundary (WASM `memLoad`/`memStore`, `--mem`, `load`/`save`) as a headerless raw image: word `i` occupies bytes `[i·bpw, (i+1)·bpw)` with `bpw = ceil(W/8)`, little-endian; the length must be a whole number of words and at most `2^A` words; every bit at or above `W` must be zero (`WordExceedsWidth`). Definedness is not representable on disk: loading marks every loaded word fully defined, storing writes `value & defined`. The codec is `lib/memimage.zig`. There is no magic-number sniffing, ever.

**Rationale.** Decision 2. A raw image is what `printf`, `xxd`, `dd` and every assembler already produce, so a student can author one without a tool from this repo. Strict padding is the only wrong-width symptom detectable without a header, so it is an error rather than silently masked. Sniffing was ruled out because a legal raw image may begin with any bytes — any magic would collide with real data.

**Alternatives.** Intel HEX / Logisim `v2.0 raw` text — human-readable, but needs a parser in the runtime and a converter is a small external tool anyway (see the Logisim note). A header carrying `W`/`A` — self-describing, but the artifact already knows both and the header would just be a second place for them to disagree.

### Load is replace-all

**Decision.** `memLoad`, `--mem`, and `load` replace the whole memory: cells `0..n-1` take the image, cells `n..2^A-1` become undefined. An empty image is `clear`. `setMemWord`/`poke` are the only partial writes.

**Rationale.** Decision 3. "After a load the memory contains exactly this image" is the only rule a reader can verify by looking at the file; a merge would make the result depend on what was there before, which `--sim`'s `reset` semantics (back to the configured initial state) could not honour.

**Alternatives.** Merge-load with an offset (`load code prog.bin 0x100`) — useful for overlays, deferred until a use case appears; it can be added as a new verb/export without changing this one.

### Eight memory exports with status codes

**Decision.** The artifact adds `getMemInfo(id) → (kind << 16) | (W << 8) | A` (or `-1`), `memBuffer(id) → ptr` to a per-memory staging buffer of `bpw << A` bytes allocated once lazily (hosts re-view `memory.buffer` after the call), `memLoad(id, len)`, `memStore(id) → bytes written`, `memClear(id)`, `setMemWord(id, addr, value, defined)`, and the paired `getMemValue(id, addr)` / `getMemDefined(id, addr)` returning `i64` (0 on error, like the pin getters). Mutators return `0` on success or `-1` bad id / not a memory, `-2` length not a word multiple, `-3` word exceeds width, `-4` too many words (unreachable through `memLoad`, whose staging buffer is exactly `2^A` words), `-5` `len` exceeds the staging size, `-6` `memBuffer` never called, `-7` address out of range.

**Rationale.** Decision 4. The pin API is pull-based with silent-zero getters, and the memory getters follow it; but `init()` swallows errors and a host has no other signal, so every *mutator* reports a status. Staging through a host-visible buffer is the same "copy bytes into linear memory, then call" protocol the topology already uses (`topology_alloc` → memcpy → `init`), so a host that can load a circuit can load a memory with no new idiom. Ids are the same positional component ids `setPin` uses; a host finds a memory's id from its `.full` record.

**Alternatives.** Returning `(ptr, len)` owned buffers from `memStore` — would need the `freeBuffer` this API deliberately omits. Per-word getters only (no bulk load/store) — 65 536 calls to fill a `[8, 16]` memory. A `memLoadFrom(ptr, len)` taking an arbitrary pointer — lets the host skip the staging copy but makes the runtime trust host pointers.

### Topology v03 memory records

**Decision.** `format.VERSION`/`FULL_VERSION` are `0x03`. A `.min` memory record is `id u32 | kind u8 | width u8 (= W) | addr_width u8` — 7 bytes, dispatched by kind exactly as slice's 2-byte suffix is, with `ComponentRecord.aux_lo` carrying `addr_width`; the `.full` record adds `Aux.memory { addr_width }`. `PortName` gains `addr = 4`, `din = 5`, `we = 6`, `clk = 7`; connection records are unchanged (the port byte is a `PortName`, never an operand index). Contents never travel in the topology. v02 payloads are rejected.

**Rationale.** Decision 10. The record needs exactly one more byte than a gate (`A`; `W` already rides in `width`), so extending the existing per-kind suffix rule costs less than a variable-length record. Pre-1.0 the version byte is freely revvable and the section name keeps its `v0` prefix, so hosts' `customSections()` lookups are stable while readers fail loudly on the wrong format.

**Alternatives.** Carrying `A` only in the `.full` section — would force the runtime to read the tooling section. A generic key/value aux block — flexible but the format's whole point is a fixed-stride byte parser in the runtime.

### `--sim` preloads by declared name; verbs are additive at proto=1

**Decision.** `--sim` and `--truth-table` accept `--mem=<name>=<path>` (repeatable, up to 16; split at the first `=` after the prefix so paths may contain `=`). Preloads are resolved after the topology is built and **before any handshake byte**: an unknown name, an unreadable file or a malformed image prints one line to stderr (`--mem <name>=<path>: no memory named '<name>' (declared memories: …)`, `file not found`, or the codec reason) and exits 2 with nothing on stdout. The protocol stays `proto=1` and the `ready` block is byte-identical for every circuit; memories are discovered with `mems` and driven with `load`, `save`, `peek`, `poke`, `mem`, `clear`, with new codes `E_NOMEM`, `E_IO`, `E_MEMFMT`, `E_ADDR` (and `E_WIDTH`/`E_BADVAL`/`E_PROTO` reused). Paths are whitespace-free tokens resolved against the cwd. `reset` re-applies the CLI preloads and drops mid-session `load`/`poke`. Only root-level memories (empty origin, mirroring pins) are addressable by name; nested ones stay id-addressable from a WASM host.

**Rationale.** Decision 7. A test runner already speaking proto=1 must keep working unchanged, which is why nothing new appears in the handshake and the version is not bumped: every addition is a new verb or a new reply to a new verb. Failing preloads before the handshake keeps stdout a clean protocol channel — a driver never has to parse an error out of a half-started session. Mirroring the pin rule for names keeps "what `--sim` can address" one sentence long.

**Alternatives.** Listing memories in the `ready` block (`mem code rom 8 4` lines) — informative, but changes the handshake's line count and breaks the byte-identity guarantee. Reporting preload failures as `diag` lines inside `ready` — but then a bad `--mem` produces a live session the driver might not notice is empty. Quoted paths — would need a tokenizer change for a case (spaces in fixture paths) the repo does not have.

### Tooling policy: truth-table ROM-only, preview boxes, emit-zig rejects

**Decision.** `--truth-table` tabulates a circuit with `rom`s (with `--mem` preloads; unloaded cells render `?` and `--strict` fails them) and refuses any circuit containing a `ram` — root-level or nested — at `builder.build` pre-flight with `error.StatefulComponent` and a one-line explanation naming the ram. `--preview` draws a `rom` as a one-input box and a `ram` as a four-input box on the existing gate/macro port pattern, labelled `rom code[8,4]`. `--inspect` prints `kind=rom[W=8,A=4]` and `widths=[8, 4]`. `--analyze` reports `rom`/`ram` symbol kinds with hover and an `addr_width` field. `--emit-zig` rejects memories at pre-flight (`--emit-zig does not support rom/ram; compile to .wasm instead`), permanently.

**Rationale.** Decision 8 (and 9 for `--inspect`). A truth table enumerates inputs and reads outputs; a `ram`'s `clk`/`we` would be enumerated as inputs and every row would depend on the visiting order — the table would be wrong, not just large — so the refusal names the ram and points at `--sim`. A `rom` under a preload is a lookup table and tabulates honestly. `--emit-zig` is the experimental standalone-Zig pipeline with its own runtime that has no memory support and is not on the default path; rejecting is cheaper and more honest than a half port.

**Alternatives.** Tabulating a `ram` "as if combinational" (treat `clk` as an input, hope) — produces a plausible-looking wrong table. Porting memories to `lib/emit/runtime.zig` — doubles the engine work for a pipeline whose export contract is declared unstable.

### `--inspect` prints widths, not global ids

**Decision.** `--inspect` shows a memory as the IR line `kind=rom[W=8,A=4]` and the AST line `widths=[8, 4]`, nothing more. It does not print a name → global-component-id table for memories.

**Rationale.** Decision 9. `--inspect`'s ids are resolver-local and are not the positional ids a WASM host passes to `getMemInfo`; printing them under a "global id" heading would be a lie for any project with imports. Hosts learn memory ids from the `.full` section (a kind 8/9 record with the declared `name` and an empty origin), which is already the documented way to map pins.

**Alternatives.** A dedicated name → global id listing for hosts (memories *and* pins) is a worthwhile follow-up, but it belongs to a mode that runs the serializer, not to `--inspect`.
