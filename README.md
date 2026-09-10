# circ-compiler

`circ-compiler` compiles `.circ` digital-logic source files into self-contained WebAssembly modules. Each compiled `.wasm` embeds a prebuilt simulation runtime plus the circuit's topology as two custom sections, and exposes a fixed pull-based runtime API (`init`, `run`, `setPin`, paired `getOutputValue` / `getOutputDefined`, and a `memLoad` / `memStore` family for `rom` / `ram` contents, …) usable from any host that supports WebAssembly. The compiler is written in Zig and ships as a single CLI: `circ-compile`. It also builds as a library — `libcirc.a` for native hosts and, for the browser, `libcirc.wasm`, which powers the site's `/playground`.

## What it does

Given a `.circ` source like:

```text
input a
not inv(in=a)
output out(in=inv.out)
```

`circ-compile inverter.circ -o inverter.wasm` produces a `.wasm` whose exported `setPin` / `run` / `getOutputValue` / `getOutputDefined` functions simulate that exact circuit. The two getters return paired `BitVecState` halves (value bits + defined-bits) crossed as `i64` / `BigInt`. Every artifact also exports the memory family — `getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, and `getMemDefined` — which acts only on the ids of `rom` / `ram` components, so the host loads and reads back memory contents at runtime (see `DOCS/wasm-api.md`). Multi-file projects work the same way: the root file imports siblings, and the compiler flattens every sub-circuit into a single ordered topology before serializing it into the `.wasm`:

```text
// half_adder.circ
input a, b
xor s(a=a, b=b)
and c(a=a, b=b)
output sum(in=s.out)
output carry(in=c.out)

// root.circ
import half_adder "half_adder.circ"
input a, b
half_adder ha(a=a, b=b)
output sum(in=ha.sum)
output carry(in=ha.carry)
```

The compiler auto-imports the built-in macros (`or`, `nand`, `nor`, `xor`, `xnor`) from a virtual `<builtin>/` filesystem; they compose like any user sub-circuit. See `DOCS/language.md` for the full surface.

## Install

Prerequisites:

- [Zig](https://ziglang.org/) 0.15.x.
- [Node](https://nodejs.org/) on `PATH` — tests only (the behavioural WASM harnesses).
- Optional: [langlang](https://github.com/jeffersonmourak/langlang) — needed only to regenerate `lib/parser/parser.zig` from `lib/grammar/proto-circ.peg`. The repo vendors the generated source, so only contributors who change the grammar need langlang installed. circ uses the maintainer's fork, which adds a Zig output language on top of upstream `go/v0.0.12`. Install with `go install github.com/jeffersonmourak/langlang/go/cmd/langlang@v0.0.13-zig.2` and confirm with `langlang -version`; `zig build parser:gen` checks the version before regenerating.

Build the CLI:

```sh
zig build circ-compile
```

The binary lands at `zig-out/bin/circ-compile`. Run the test suite with:

```sh
zig build test
```

This is the fast dev-loop suite. `zig build test-all` additionally runs the slow emit-zig backend smoke (`test-emit`, a nested `zig build wasm` per fixture) and is what CI runs. (Set `CIRC_SKIP_PERF=1` to skip the smoke perf test in noisy CI environments.)

The embedded runtime (`zig-out/lib/circ-runtime.wasm`) is always ReleaseSmall and stripped; `-Dwasm-optimize=<mode>` changes that for both wasm artifacts without touching the CLI's own `-Doptimize`.

The compiler front end is also available as a C library: `zig build libcirc` produces `zig-out/lib/libcirc.a` and `zig-out/include/libcirc.h`, and `zig build libcirc-smoke` builds and runs `examples/c/analyze.c` against it. `zig build libcirc-wasm` builds the same API as a freestanding `zig-out/lib/libcirc.wasm` for browsers and Node. See `DOCS/libcirc-api.md`.

## Usage

`circ-compile` has the following mutually exclusive modes:

| Invocation                                       | Produces                                                                                       |
|--------------------------------------------------|------------------------------------------------------------------------------------------------|
| `circ-compile input.circ -o out.wasm`            | A self-contained `.wasm` artifact (default mode).                                              |
| `circ-compile input.circ --emit-zig -o out.zig`  | The generated standalone Zig source for the experimental emit pipeline.                        |
| `circ-compile input.circ --inspect`              | Pretty-printed parse tree, resolved IR, and diagnostics on stdout.                             |
| `circ-compile input.circ --preview`              | ASCII schematic of the resolved circuit on stdout (no artifact written).                       |
| `circ-compile input.circ --truth-table`          | Markdown truth table enumerating every input vector against the simulated circuit, on stdout.  |
| `circ-compile input.circ --sim`                  | Interactive stdio drive protocol; drive the circuit by pin name and load/inspect `rom`/`ram` contents (`--mem=<name>=<path>`, `load`/`save`/`peek`/`poke`). See `DOCS/sim-protocol.md`. |
| `echo '<json>' \| circ-compile --analyze`        | JSON analysis (files, diagnostics, symbols, references) on stdout for editor tooling; the request comes on stdin, not as a file path. See `DOCS/analyze-api.md`. |

In default compile mode, `circ-compile` runs the parser, resolver, validator, and topology serializers in-process and splices the resulting `circ.topology.v0.min` and `circ.topology.v0.full` blobs into a vendored prebuilt runtime `.wasm` (embedded in the CLI via `@embedFile`). Users need no `zig` toolchain or subprocess at runtime.

Additional flags:

- `--warnings-as-errors` (alias `-Werror`) — promote warnings to hard errors (suppresses emission).
- `--expand-macros` — only valid with `--preview`; renders builtin macros (`xor`, `nand`, …) as their expanded primitive sub-circuits.
- `--color=auto|always|never` — only valid with `--preview`; controls ANSI styling of the schematic. Default is `auto` (on when stdout is a TTY; the `NO_COLOR` env var also disables colour).
- `--format=markdown|csv|json` — only valid with `--truth-table`; selects the output format. Default is `markdown`. CSV uses `0`/`1`/`?` cells; JSON encodes undefined cells as `null` so consumers can branch on type.
- `--strict` — only valid with `--truth-table`; promotes any `?` (undefined) output cell into a hard exit-1 with one diagnostic line per offending row on stderr. The table itself still renders. Useful as a CI gate — a regression that introduces a dangling output now fails the build instead of silently producing `?` rows.
- `--truth-table-format=binary|hex|decimal`, `--truth-table-cap=N` (default 16, max 24 input bits), and `--verbose` (per-vector engine traces on stderr) — only valid with `--truth-table`.
- `--expand-display` — only valid with `--preview`; renders a multi-bit `led[N]` (widths 2..7) as a row of `·` indicator glyphs instead of the `0x?` hex display.
- `--mem=<name>=<path>` — valid with `--sim` and `--truth-table`; preloads a raw image file into the root memory declared as `<name>`. Repeatable, up to 16.
- `--help`/`-h` and `--version`/`-v`. `circ-compile --help` is the authoritative flag list.

Hard errors block emission: the compiler never produces partial or "best-effort" artifacts. Diagnostics use stable codes (`E001`–`E018`, `W001`–`W003`) so downstream tooling can match on them.

### Library

The same front end is available without the process: `zig build libcirc` produces `zig-out/lib/libcirc.a` + `zig-out/include/libcirc.h`, and `zig build libcirc-wasm` produces `zig-out/lib/libcirc.wasm` for browsers and Node. Ten `circ_*` exports take one JSON request (root, in-memory files, options) and return the `.wasm` artifact, the preview text, the truth table, or the analysis JSON with a status code. See `DOCS/libcirc-api.md`.

## Documentation

- `DOCS/getting-started.md` — write, compile, and run your first circuit (start here).
- `DOCS/language.md` — the `.circ` language reference.
- `DOCS/circuit-format.md` — syntax overview, the topology format version, and the diagnostic-code catalogue.
- `DOCS/preview.md` — `--preview` schematics; `DOCS/sim-protocol.md` — the `--sim` drive protocol; `DOCS/analyze-api.md` — the `--analyze` JSON.
- `DOCS/wasm-api.md` — runtime API exposed by the compiled `.wasm`.
- `DOCS/libcirc-api.md` — the compiler as a library (`libcirc.a`, `libcirc.wasm`): request, status codes, C ABI.
- `DOCS/simulation-engine.md` — the engine the compiler targets.
- `DOCS/architecture.md` and `DOCS/decisions/` — design rationale for contributors.

## License

[GNU General Public License v3.0](LICENSE).
