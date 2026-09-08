# `--sim` drive protocol (proto=1)

`circ-compile <input>.circ --sim` compiles the circuit, then serves a small
line-oriented request/response protocol over stdin/stdout. It lets an external
process (a test runner, a REPL, an editor) drive the circuit by pin name:
set inputs, settle, read outputs. It writes no file.

The mode runs the same native simulation engine as `--truth-table`, built from
the same resolved topology, so behavior matches the compiled `.wasm`. In fact
each command maps 1:1 onto the artifact's WASM exports (see
[`wasm-api.md`](wasm-api.md)): `set` → `setPin`, `run` → `run`,
`get` → `getOutputValue`/`getOutputDefined`, and for memories `load` → `memLoad`,
`save` → `memStore`, `poke` → `setMemWord`, `peek` → `getMemValue`/`getMemDefined`,
`clear` → `memClear`.

## Transport and framing

- Line-oriented and synchronous: write one command per line to stdin; the
  process replies before you send the next.
- A reply is either a **status line** (`ok ...` / `err <CODE> <message>`) or a
  **counted block**: a header line ending in a count, followed by exactly that
  many record lines.
- Blank lines and lines starting with `#` are ignored and produce no reply
  (so a session can be driven by hand or from a script).
- EOF on stdin, or `quit`, shuts the process down.

## Handshake

The first output line is the handshake. On a circuit that compiles, with one
`pin` record per top-level pin and one `diag` line per warning:

```
ready proto=1 pins=3 warnings=0
pin a in 1
pin b in 1
pin out out 1
```

`pin <name> <in|out> <width>`. On a circuit with hard errors there is no session
to drive; the process emits the diagnostics and exits nonzero:

```
error diags=1
diag error E004 in.circ:3:1 required input 'b' is unconnected
```

`diag <error|warning> <CODE> <file>:<line>:<col> <message>`, reusing the stable
validator codes (`E001`-`E018`, `W001`-`W003`).

## Value and width encoding

| Aspect | Rule |
| --- | --- |
| Input literals | Decimal `12`, hex `0x0c`, binary `0b1100`, octal `0o14` (`_` separators ok). |
| Output literals | Lowercase hex, `0x`-prefixed (`0x0`, `0x1f`). |
| Value + mask | Every signal is a `(value, mask)` pair; mask bit 1 = defined, mask bit 0 = undefined (X). |
| Default mask | An omitted mask means fully defined (all bits of the pin's width). |
| Undefined bits | Value bits where the mask is 0 are emitted as 0, matching the engine's `BitVecState` equality. |
| Width | 1 to 64. A literal with bits set beyond the pin's width is an error (`E_WIDTH`), not silently masked. |

## Commands

| Command | Reply | Notes |
| --- | --- | --- |
| `pins` | `pins <N>` block + `pin` lines | Re-query of the handshake pin table. |
| `set <pin> <value> [<mask>]` | `ok` / `err` | Drives a top-level input and settles. `set a 0 0` is fully undefined; `set bus 0x5 0xf` is per-bit. |
| `get <pin>` | `ok <value> <mask>` / `err` | Reads current state (inputs or outputs). |
| `dump <in\|out\|all>` | `vals <N>` block + `<name> <value> <mask>` lines | Whole-vector read for snapshots. |
| `run` | `ok` | Drains the event queue. Redundant after `set` (which already settles); kept for 1:1 parity with the artifact's `run()`. |
| `eval <assign...> => <query...>` | `ok <name>=<value>/<mask> ...` / `err` | One-shot vector: `pin=value[/mask]` assignments, then the queried pins. Operates on current state (no implicit reset). |
| `reset` | `ok` | Rebuilds the circuit to its post-`init` state (all pins undefined), then re-applies any `--mem` preloads. Contents from mid-session `load`/`poke` are dropped. Per-scenario isolation without respawning. |
| `quit` | `ok bye` then exit | EOF on stdin does the same. |
| `mems` | `mems <N>` block + `mem <name> <rom\|ram> <W> <A>` lines | The root-level memories, in declaration order (decimal widths). The `ready` block never lists them. |
| `load <mem> <path>` | `ok words=<n>` / `err` | Replaces every cell from a raw image file; `n` is the words loaded, cells `n..2^A-1` become undefined (an empty file clears). `out` follows at once. |
| `save <mem> <path>` | `ok words=<2^A>` / `err` | Writes the whole memory as a raw image (`value & defined` per word; undefined bits become 0). |
| `peek <mem> <addr>` | `ok <value> <mask>` / `err` | Reads one cell. |
| `poke <mem> <addr> <value> [<mask>]` | `ok` / `err` | Writes one cell and settles, like `set`. An omitted mask means fully defined. |
| `mem <mem> [<start> [<count>]]` | `cells <N>` block + `<addr> <value> <mask>` lines | Dumps a range (default: the whole memory). `start` past the end is `E_ADDR`; `count` is clipped to the end; `count` 0 gives an empty block. |
| `clear <mem>` | `ok` | Every cell becomes undefined and the circuit settles. |

**Error codes** (`err <CODE> <message>`): `E_PROTO` (unknown/malformed command),
`E_NOPIN` (no such pin — including a memory name given to `set`/`get`),
`E_NOTIN` (`set` target is not a top-level input), `E_WIDTH` (bits beyond the
pin or memory width), `E_BADVAL` (not a valid integer literal), `E_NOMEM` (no
root-level memory of that name — including a pin name given to a memory verb),
`E_IO <path>: <error>` (`load`/`save` could not open, read, or write the file),
`E_MEMFMT <path>: <reason>` (the image breaks a raw-image rule: length not a
whole number of words, more words than the memory holds, a word with bits at
or above the data width, or a file over the 16 MiB read cap), `E_ADDR <mem>
<addr>` (address `>= 2^A`). `E_NOSETTLE` is declared for a settle cap that
`run` does not enforce (`run` swallows propagate errors and replies `ok`); it is
never emitted.

## Settle model

`set` drives an input and settles the circuit in one step, exactly as the
shipped artifact's `setPin` does (the native engine's `propagateEvent` enqueues
and then drains to quiescence). There is no clock to pump: a single `set`
settles any combinational cascade. For sequential circuits, state persists
across commands, so a scenario is just `set`/`get` repeated; only `reset`
clears it. Because each `set` settles independently, an `eval`'s assignments are
applied in order, each settling, before its queries are read.

## Memories

`rom`/`ram` components declare only their shape in source; their contents are
runtime state. `--sim` addresses a memory by its declared name, exactly as it
addresses pins, and exposes contents two ways:

- **`--mem=<name>=<path>` on the command line** (repeatable, up to 16, also
  accepted by `--truth-table`) loads a raw image before the handshake. Every
  flag is checked first — the name must be a root-level memory, the file must
  be readable, and the image must pass the format rules — and a failure prints
  one line to **stderr** and exits 2 before any handshake byte, so stdout stays
  a clean protocol channel:

  ```
  --mem code=prog.bin: no memory named 'code' (declared memories: rom boot[8, 4])
  --mem code=prog.bin: file not found
  --mem code=prog.bin: 17 words exceed capacity 16
  ```

  Because the pre-flight runs before the handshake, the warnings that would
  have appeared as `diag` lines are not printed on a preload failure; fix the
  flag and re-run.
- **The verbs above** (`load`, `save`, `peek`, `poke`, `mem`, `clear`) during a
  session.

The image format is the headerless raw image described in
[`wasm-api.md`](wasm-api.md#memory-exports-rom--ram): `ceil(W/8)` little-endian
bytes per word, bits at or above `W` clear, at most `2^A` words. Loading marks
every loaded word fully defined; unloaded and unwritten cells read undefined;
saving writes `value & defined`.

Paths are single whitespace-free tokens (the protocol tokenizer splits on
spaces and tabs; there is no quoting) and are resolved against the process
working directory, like the input path. Files are read with a 16 MiB cap, far
above the largest legal image (512 KiB). `load` and `save` are the only
commands that touch the filesystem; a `save` that fails mid-write may leave a
partial file.

Only root-level memories are addressable by name; a memory inside an imported
or macro sub-circuit is reachable from a compiled artifact by id but not from
`--sim`, mirroring the rule for pins.

A ram writes on the defined low → high edge of its `clk` port while `we` is
high, and `clk` is an ordinary input pin: pulse it with `set clk 0` then
`set clk 1`.

## Example session

```
$ circ-compile and_gate.circ --sim
ready proto=1 pins=3 warnings=0
pin a in 1
pin b in 1
pin out out 1
set a 1
ok
set b 1
ok
get out
ok 0x1 0x1
eval a=1 b=0 => out
ok out=0x0/0x1
quit
ok bye
```

A memory session on `input[4] addr` → `rom code[8, 4](addr = addr.out)` →
`output[8] out(in = code.out)` (this transcript is replayed verbatim by a test
in `lib/sim/loop.zig`, so it cannot drift from the code):

```
$ circ-compile rom.circ --sim
ready proto=1 pins=2 warnings=0
pin addr in 4
pin out out 8
mems
mems 1
mem code rom 8 4
poke code 3 0x2a
ok
set addr 3
ok
get out
ok 0x2a 0xff
peek code 4
ok 0x0 0x0
mem code 2 3
cells 3
0x2 0x0 0x0
0x3 0x2a 0xff
0x4 0x0 0x0
clear code
ok
get out
ok 0x0 0x0
reset
ok
quit
ok bye
```

Loading from and saving to files follows the same shape:

```
load code prog.bin
ok words=16
save code snapshot.bin
ok words=16
load code nope.bin
err E_IO nope.bin: FileNotFound
```
