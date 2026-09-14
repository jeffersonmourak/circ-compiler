# `--sim` drive protocol (proto=1)

`circ-compile <input>.circ --sim` compiles the circuit, then serves a small
line-oriented request/response protocol over stdin/stdout. It lets an external
process (a test runner, a REPL, an editor) drive the circuit by pin name:
set inputs, settle, read outputs. It writes no artifact (only the `save`
verb touches the filesystem, to write a memory image).

The mode runs the same native simulation engine as `--truth-table`, built from
the same resolved topology, so behavior matches the compiled `.wasm`. Each
command maps 1:1 onto the artifact's WASM exports (see
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
- The process ignores blank lines and lines starting with `#` and replies to
  neither (so you can drive a session by hand or from a script).
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

`pin <name> <in|out> <width>`. A circuit with hard errors leaves no session to
drive; the process emits the diagnostics and exits nonzero:

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
| `reset` | `ok` | Rebuilds the circuit to its post-`init` state (all pins undefined), then re-applies any `--mem` preloads. The rebuild drops contents from mid-session `load`/`poke`. Per-scenario isolation without respawning. |
| `quit` | `ok bye` then exit | EOF on stdin does the same. |
| `mems` | `mems <N>` block + `mem <name> <rom\|ram> <W> <A>` lines | The root-level memories, in declaration order (decimal widths). The `ready` block never lists them. |
| `load <mem> <path>` | `ok words=<n>` / `err` | Replaces every cell from a raw image file; `n` is the words loaded; cells `n..2^A-1` become undefined (an empty file clears). `out` follows at once. |
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
<addr>` (address `>= 2^A`). `E_NOSETTLE` means the circuit exhausted its
settling work budget. `set`, `eval`, `run`, and memory mutations can report it.
Afterward, reset the session before driving, reading values, or exporting memory.
`pins`, `mems`, `reset`, and `quit` remain available.

## Settle model

`set` drives an input and settles the circuit in one step, exactly as the
shipped artifact's `setPin` does (the native engine's `propagateEvent` enqueues
and then drains to quiescence). The protocol has no clock to pump: a single
`set` settles any combinational cascade. For sequential circuits, state persists
across commands, so a scenario is just `set`/`get` repeated; only `reset`
clears it. Because each `set` settles independently, `eval` applies its
assignments in order, each settling, before reading its queries.

Each settle permits at most 1,000,000 work units: one per popped event and
one per downstream evaluation. Exhaustion returns
`err E_NOSETTLE settle work budget exceeded; reset required`, discards pending
events, and invalidates the session's values until reset. Earlier writes in
an `eval` may already have occurred; this is not a rollback. The cap is a
deterministic safety budget, not a wall-clock deadline or proof of oscillation.
Gate feedback remains legal for latches; passing `E008` validation does not
guarantee that every input sequence settles.

## Memories

`rom`/`ram` components declare only their shape in source; their contents are
runtime state. `--sim` addresses a memory by its declared name, exactly as it
addresses pins, and exposes contents two ways:

- **`--mem=<name>=<path>` on the command line** (repeatable, up to 16, also
  accepted by `--truth-table`) loads a raw image before the handshake. Every
  flag is checked first: the name must be a root-level memory, the file must
  be readable, and the image must pass the format rules. A failure prints one
  line to **stderr** and exits 2 before any handshake byte, so stdout stays a
  clean protocol channel:

  ```
  --mem code=prog.bin: no memory named 'code' (declared memories: rom boot[8, 4])
  --mem code=prog.bin: file not found
  --mem code=prog.bin: 17 words exceed capacity 16
  ```

  Because the pre-flight runs before the handshake, a preload failure prints
  none of the warnings that would have appeared as `diag` lines; fix the flag
  and re-run.
- **The verbs above** (`load`, `save`, `peek`, `poke`, `mem`, `clear`) during a
  session.

The image format is the headerless raw image described in
[`wasm-api.md`](wasm-api.md#memory-exports-rom--ram): `ceil(W/8)` little-endian
bytes per word, bits at or above `W` clear, at most `2^A` words. Loading marks
every loaded word fully defined; unloaded and unwritten cells read undefined;
saving writes `value & defined`.

Paths are single whitespace-free tokens (the protocol tokenizer splits on
spaces and tabs and offers no quoting) and resolve against the process
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
`output[8] out(in = code.out)` (a test in `lib/sim/loop.zig` replays this
transcript verbatim, so it cannot drift from the code):

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

## The protocol in the browser

In Live and Truth, the playground's console sits in the drawer below the
source and canvas. It speaks this protocol to the circuit the page compiled.
The grammar is
the CLI's (`site/src/scripts/sim-protocol.ts` copies `parseLine` and
`parseValue` verb by verb), the replies are the CLI's
(`site/src/scripts/sim-executor.ts` copies the strings of `lib/sim/loop.zig`),
and `site/test/sim-transcripts.test.ts` replays every script in
`tests/fixtures/sim/` through both and matches `tests/fixtures/expected-sim/`
byte for byte. What follows is the list of differences, all of them about the
browser having no process, no working directory and no stdin.

- **The handshake prints when the session is built**, which is the first
  time the Live view, Data panel or a Truth-table action needs the compiled
  circuit's runtime, and again
  after every `reset`, whichever face caused it. Its `<file>` is the root
  file's name, which is the selected editor file in a multi-file project.
  Its `warnings` count and `diag` lines come from the analysis
  the page ran on the same source.
- **The log records every face.** A pin clicked on the canvas, a value typed
  in the Data panel, a cell written or a memory cleared in the memory panel, and a
  Reset pressed anywhere are logged as the line that would have done the
  same — `> set a 0x1`, `> poke data 0x2 0x5a`, `> clear data`, `> reset` —
  followed by the reply the session gave, in the order they happened. A
  partly-known value carries its mask (`> set a 0x1 0x3`). A ROM image edited
  or loaded in the memory panel is applied as a `--mem` preload, not as a
  `load`, so it is logged as a comment naming the memory and the word count.
- **The page boots low.** Before the first `reset` the circuit is in the
  state the canvas has always shown: every root input driven to 0 and
  settled once. `reset` (and `quit`) leave every pin undefined, as after
  `init()`, so from then on the session is a fresh `--sim` process. A script
  that depends on floating pins begins with `reset`.
- **`quit` prints `ok bye` and is otherwise `reset`.** There is no process to
  end; the prompt stays live.
- **`load` and `save` use the memory panel.** The page has no working
  directory, so both verbs are refused in the protocol's own shape, and the
  reason says where to go:

  ```
  load code prog.bin
  err E_IO prog.bin: load images in the memory panel
  save code snapshot.bin
  err E_IO snapshot.bin: save images from the memory panel
  ```

  The memory panel's `Load image…` opens the ROM file picker and hex editor;
  `Save` downloads `<mem>.bin` with the bytes `save` would
  write. Preloads are the memory panel's ROM images: they are applied when the
  session is built and again on every `reset`, as `--mem` is.
- **`help` is a browser-only verb.** It prints the command table as `#`
  comment lines. The CLI answers `help` itself with `err E_PROTO malformed
  command`, so a copied script that contains it prints one error and goes on.
- **No line-length cap.** The CLI's `err E_PROTO command line exceeds limit`
  is never printed; a browser line has no 8 KiB buffer to overflow.
- **The log is a transcript; `Copy script` is the script.** Every line in
  the Console's scrollback is a reply, the echo of a line (`> …`) or a comment
  (`# …`). The CLI would refuse an echo as written (`> set a 1` is a malformed
  command), so the console's `Copy script` button copies the lines `--sim`
  accepts — each echo without its `> `, and the comments — and drops every
  reply. Saved as a `.script` and fed to `circ-compile <file>.circ --sim`,
  it replays what the reader did; `Copy log` copies the whole scrollback.

The closed terminal line shows the last command and reply. Click it or focus
it to open the drawer; its height is resizable and saved. Declared memories
appear beside the console, or below it on a narrow screen. A defined address
highlights its word in the grid. Close folds the drawer; Escape in a nonempty
prompt clears the line, and Escape in an empty prompt folds it.
Schematic hides the whole console/memory row. Returning to Live or Truth
restores its previous open/closed state and height.

Selecting another source file starts a fresh circuit and console for that
file. Its sibling files remain available for imports, so an imported circuit
can be exercised on its own. Pin state resets on this switch; ROM images stay
with their source file and initialize each imported instance at build and
reset. Changing only the output view keeps the same session. Images are saved
with the project when they fit the saved-state budget; the page reports when
they are too large to survive a reload. Console memory commands still address
only memories declared in the selected root file.

## Agent simulation controls

The playground agent contract uses the same session as the canvas, Data panel,
memory panel, and console. `circ_drive` has the ordering of `eval`: assignments
settle one at a time. It accepts and returns canonical lowercase `0x` strings
for values and defined masks so 64-bit states do not cross JSON as numbers.
`circ_reset` is the protocol reset and creates a new session identity. Root
memory pages and mutations map to `peek`/`mem`, `poke`, `clear`, and `load`;
source ROM preloads are separately addressed by project/file/declaration.

`circ_run_verification` uses disposable sessions and writes no visible console
records. It can run ordered vectors and stateful scenarios, but cannot read or
copy live state. See `agent-playground.md` for revision preconditions, limits,
and result paging.
