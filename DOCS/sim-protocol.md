# `--sim` drive protocol (proto=1)

`circ-compile <input>.circ --sim` compiles the circuit, then serves a small
line-oriented request/response protocol over stdin/stdout. It lets an external
process (a test runner, a REPL, an editor) drive the circuit by pin name:
set inputs, settle, read outputs. It writes no file.

The mode runs the same native simulation engine as `--truth-table`, built from
the same resolved topology, so behavior matches the compiled `.wasm`. In fact
each command maps 1:1 onto the artifact's WASM exports (see
[`wasm-api.md`](wasm-api.md)): `set` → `setPin`, `run` → `run`,
`get` → `getOutputValue`/`getOutputDefined`.

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
validator codes (`E001`-`E016`, `W001`-`W003`).

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
| `reset` | `ok` | Rebuilds the circuit to its post-`init` state (all pins undefined). Per-scenario isolation without respawning. |
| `quit` | `ok bye` then exit | EOF on stdin does the same. |

**Error codes** (`err <CODE> <message>`): `E_PROTO` (unknown/malformed command),
`E_NOPIN` (no such pin), `E_NOTIN` (`set` target is not a top-level input),
`E_WIDTH` (bits beyond the pin width), `E_BADVAL` (not a valid integer literal).

## Settle model

`set` drives an input and settles the circuit in one step, exactly as the
shipped artifact's `setPin` does (the native engine's `propagateEvent` enqueues
and then drains to quiescence). There is no clock to pump: a single `set`
settles any combinational cascade. For sequential circuits, state persists
across commands, so a scenario is just `set`/`get` repeated; only `reset`
clears it. Because each `set` settles independently, an `eval`'s assignments are
applied in order, each settling, before its queries are read.

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
