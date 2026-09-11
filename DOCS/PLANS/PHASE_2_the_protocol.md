# Phase 2 — The protocol

> **Dependencies:** Phase 0 (the session).
> **Warnings:** Decisions 2, 4, 10 and 11. This phase ships no UI. Its proof is byte-for-byte parity with `tests/fixtures/expected-sim/*.txt`, which only `UPDATE_GOLDENS=1 zig build test` may change; a site test never writes them. Read `lib/sim/protocol.zig` (`parseLine`, `parseValue`) and `lib/sim/loop.zig` (`serve`, every `do*`) before writing a line: the reply strings are copied, not paraphrased.

## Goal

A line of protocol text goes into `parseLine` and comes out as a command or one of three parse failures; a command goes into the executor with a session and a file source and comes out as the exact lines `--sim` would print. Replaying `tests/fixtures/sim/sim_and_gate.script`, `sim_rom_pc_walk.script` (with its preload), `sim_ram_write_read.script` and `sim_mem_errors.script` through the executor over artifacts compiled from the fixtures' `.circ` sources by the committed `libcirc.wasm` yields the four golden transcripts byte for byte, handshake included.

## Scope

**In scope:**
- `site/src/scripts/sim-protocol.ts`: `parseValue` (the `std.fmt.parseInt(u64, text, 0)` grammar over `bigint`), `parseLine`, `writeHex`, the `Command` union, `ErrorCode`.
- `site/src/scripts/sim-executor.ts`: `handshake(session, fileName)`, `execute(session, files, line): string[]` (one reply per line; a counted block is its header plus records), the `FileSource` interface, a `MemoryFileSource` over a `Map<string, Uint8Array>`.
- `site/src/utils/rom-image.ts`: `validateImageBytes(bytes, mem)` (the three checks over bytes, in the compiler's order) and `imageErrorReason(kind, mem, len)` with the compiler's wording (`writeImageError`).
- `site/test/sim-protocol.test.ts`, `site/test/sim-executor.test.ts` (stub session), `site/test/sim-transcripts.test.ts` (real artifacts, the four goldens; `SKIP_LIBCIRC_TEST` honoured).

**Explicitly deferred:**
- The console element and its drop box (Phase 3): this phase's `FileSource` is a map.
- `E_NOSETTLE` (never emitted by the CLI); `E_PROTO command line exceeds limit` (the browser has no 8 KiB line buffer; recorded as a difference in Phase 3's doc section).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| site | `site/src/scripts/sim-protocol.ts` | Grammar in, commands out. No session, no I/O. |
| site | `site/src/scripts/sim-executor.ts` | Commands in, reply lines out, over a session and a file source. |
| site | `site/test/sim-protocol.test.ts` | The grammar. |
| site | `site/test/sim-executor.test.ts` | Every verb's reply over the Phase 0 stub session. |
| site | `site/test/sim-transcripts.test.ts` | The four goldens over real artifacts. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| site | `site/src/utils/rom-image.ts` | `validateImageBytes`, `imageErrorReason`; `parseRomImage` unchanged. |
| site | `site/src/scripts/sim-session.ts` | `loadImage` validates through `validateImageBytes` and returns `{ ok: false, code: 'E_MEMFMT', arg: <reason> }` with the compiler's wording; `storeImage` unchanged. |
| site | `DOCS/decisions/playground.md` | Entries for decisions 2, 4, 10, 11. |

**New dependencies:** None.

## Data & State

```ts
// sim-protocol.ts
export type Command =
  | { verb: 'pins' } | { verb: 'run' } | { verb: 'reset' } | { verb: 'quit' } | { verb: 'mems' }
  | { verb: 'set'; pin: string; value: bigint; mask: bigint | null }
  | { verb: 'get'; pin: string }
  | { verb: 'dump'; which: 'in' | 'out' | 'all' }
  | { verb: 'eval'; assigns: { pin: string; value: bigint; mask: bigint | null }[]; queries: string[] }
  | { verb: 'load'; mem: string; path: string } | { verb: 'save'; mem: string; path: string }
  | { verb: 'peek'; mem: string; addr: bigint }
  | { verb: 'poke'; mem: string; addr: bigint; value: bigint; mask: bigint | null }
  | { verb: 'mem'; mem: string; start: bigint | null; count: bigint | null }
  | { verb: 'clear'; mem: string };
export type ParseOutcome = { ok: true; command: Command } | { ok: false; reason: 'empty' | 'malformed' | 'badval' };
export function parseLine(raw: string): ParseOutcome;
/** `0x`/`0o`/`0b` prefixes, `_` between digits, decimal default, no sign, ≤ 64 bits; null on anything else. */
export function parseValue(text: string): bigint | null;
export function writeHex(v: bigint): string;   // '0x' + lowercase, no padding

// sim-executor.ts
export interface FileSource {
  /** The bytes at `path`, or the reason it could not be read (`FileNotFound`, `FileTooBig`, …), spelled as Zig's `@errorName`. */
  read(path: string): { ok: true; bytes: Uint8Array } | { ok: false; error: string };
  write(path: string, bytes: Uint8Array): { ok: true } | { ok: false; error: string };
}
export class MemoryFileSource implements FileSource { constructor(files?: Map<string, Uint8Array>); }
export function handshake(session: SimSession, fileName: string): string[];   // ready, pin lines, diag lines
export function execute(session: SimSession, files: FileSource, line: string): Promise<string[]>; // async for reset
```

Grammar facts the parser holds, from `parseLine`: tokens split on spaces and tabs; a line that is empty after trimming or starts with `#` is `empty`; `pins`, `run`, `reset`, `quit` take no arguments but ignore extras (the Zig parser does not check them — copy that); `mems`, `load`/`save`, `peek`, `clear`, `get`, `dump` refuse extras; `set` and `poke` take an optional mask; `mem` takes optional start then count; `eval` is `pin=value[/mask]` tokens until `=>` then query names, and `=>` must appear exactly once; an unknown verb is `malformed`; a bad literal anywhere is `badval` and wins over a later `malformed` only where the Zig code parses the value first (copy the order per verb).

Reply strings the executor holds, from `loop.zig`: `ok`, `ok bye`, `ok <hex> <hex>`, `ok <pin>=<hex>/<hex> …`, `ok words=<n>`, `err E_PROTO malformed command`, `err E_BADVAL invalid integer literal`, `err E_NOPIN <name>`, `err E_NOTIN <name>`, `err E_WIDTH <name>`, `err E_NOMEM <name>`, `err E_ADDR <mem> <hex>`, `err E_IO <path>: <error>`, `err E_MEMFMT <path>: <reason>`, `pins <N>` + `pin <name> <in|out> <w>`, `vals <N>` + `<name> <hex> <hex>`, `mems <N>` + `mem <name> <rom|ram> <W> <A>`, `cells <N>` + `<hex addr> <hex> <hex>`. Reasons for `E_MEMFMT`, from `writeImageError`: `length <len> is not a multiple of <bpw> byte(s)`, `<n> words exceed capacity <cap>`, `a word has bits set beyond data width <W>`, `image exceeds 16 MiB`. `load` reads the file first (`E_IO` on failure, `E_MEMFMT …: image exceeds 16 MiB` on `FileTooBig`), validates, then applies; `save` stores the image and writes it (`E_IO` on failure), replying `ok words=<2^A>`.

## Execution & Concurrency Model

`execute` is `async` only because `reset` and `quit` await the session's rebuild; every other verb resolves synchronously. The transcript test awaits each line in order, as the CLI is line-synchronous.

## Persistence & I/O

The transcript test's `FileSource` reads `tests/fixtures/mem/<name>` from the repository through `node:fs` (`readFileSync`; `ENOENT` → `FileNotFound`) and refuses writes (no script saves). The page's source is Phase 3's.

## Slices

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | The grammar | `parseValue`, `parseLine`, `writeHex`. | `sim-protocol.test.ts`: every verb parses to its command; `eval a=3 b=0xf/0xf => out cout` matches the Zig test's expectations; `eval a=1` is `malformed`; `set a zz` is `badval`; `0b1100`, `0o14`, `1_000`, `0x_ff` parse; `-1`, `1e3`, a 65-bit literal are null; `writeHex(0n)` is `0x0`. |
| 2 | Pin verbs and the first transcript | `execute` for `pins`, `run`, `set`, `get`, `dump`, `eval`, `reset`, `quit`; `handshake`; `sim-transcripts.test.ts` with `sim_and_gate`. | Executor unit cases over the stub; `sim_and_gate.txt` byte for byte. |
| 3 | Memory verbs and the file source | `mems`, `load`, `save`, `peek`, `poke`, `mem`, `clear`; `FileSource`, `MemoryFileSource`; `validateImageBytes`, `imageErrorReason`; the session's `loadImage` wording. | `sim_rom_pc_walk` (preload) and `sim_ram_write_read` byte for byte. |
| 4 | The error transcript | The file source's `FileNotFound` and `FileTooBig` spellings; every `E_*` path. | `sim_mem_errors.txt` byte for byte: `E_NOMEM nosuch`, `E_IO tests/fixtures/mem/does_not_exist.bin: FileNotFound`, `E_MEMFMT tests/fixtures/mem/too_many_words.bin: 17 words exceed capacity 16`, `E_ADDR data 0x10`, `E_WIDTH data`, `E_NOPIN data` twice, `E_PROTO malformed command`. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `parseValue is std.fmt.parseInt(u64, text, 0)` | `sim-protocol.test.ts` | The literal table above. |
| `parseLine mirrors lib/sim/protocol.zig` | same | One case per verb plus the malformed/badval ordering. |
| `every reply is the loop's string` | `sim-executor.test.ts` | Per verb over the stub session, including the error arms. |
| `the handshake counts warnings and lists pins` | same | `ready proto=1 pins=3 warnings=1` with one `diag warning W001 main.circ:2:1 …`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `the four --sim transcripts replay byte for byte` | `sim-transcripts.test.ts` | Each fixture's compiled artifact + script → golden, with the repository's `tests/fixtures/mem/` as the file source. |

Run command: `cd site && bun test`.

## Open Questions / Spikes

- `TODO(phase2)`: `sim_mem_errors` runs `load nosuch tests/fixtures/mem/rom_pc_walk.bin` first: the loop resolves the memory *before* reading the file (`E_NOMEM` wins over a readable path). Copy that order.
- `TODO(phase2)`: the goldens' `diag` lines name the fixture's path as the CLI was given it (`tests/fixtures/circuits/…`); the four fixtures compile warning-free, so `warnings=0` and no `diag` line appears — the handshake's file name is exercised only by the executor unit test.
- `TODO(phase2)`: `get` on a root input in the CLI reads the engine's input node state; in the browser `readValue(id)` of an `input_pin` goes through `getOutputValue`, which for an input pin is its driven value. Slice 2's transcript (`get out` only) does not exercise `get <input>`; the executor unit test does, over the stub, and the `and_gate` integration case in Phase 0 asserts it over the real runtime.
