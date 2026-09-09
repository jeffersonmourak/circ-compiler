# circ-compiler

`circ-compiler` compiles `.circ` digital-logic source files into self-contained WebAssembly modules. Each compiled `.wasm` embeds the simulation engine plus circuit-specific construction code and exposes a fixed pull-based runtime API (`init`, `run`, `setPin`, paired `getOutputValue` / `getOutputDefined`, …) usable from any host that supports WebAssembly. The compiler is written in Zig and ships as a single CLI: `circ-compile`.

## What it does

Given a `.circ` source like:

```text
input a
not inv(in=a)
output out(in=inv.out)
```

`circ-compile inverter.circ -o inverter.wasm` produces a `.wasm` whose exported `setPin` / `run` / `getOutputValue` / `getOutputDefined` functions simulate that exact circuit. The two getters return paired `BitVecState` halves (value bits + defined-bits) crossed as `i64` / `BigInt`. Multi-file projects work the same way — the root file imports siblings and the compiler flattens every sub-circuit into a single ordered topology before serializing it into the `.wasm`:

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

Built-in macros (`or`, `nand`, `nor`, `xor`, `xnor`) are auto-imported from a virtual `<builtin>/` filesystem and compose like any user sub-circuit. See `DOCS/circuit-format.md` for the full surface.

## Install

Prerequisites:

- [Zig](https://ziglang.org/) 0.15.x.
- Optional: [langlang](https://github.com/jeffersonmourak/langlang) — only needed if you want to regenerate `lib/parser/parser.zig` from `lib/grammar/proto-circ.peg`. The generated source is vendored in the repo, so contributors who don't touch the grammar do not need langlang installed. circ uses the maintainer's fork, which adds a Zig output language on top of upstream `go/v0.0.12`. Install with `go install github.com/jeffersonmourak/langlang/go/cmd/langlang@v0.0.13-zig.2` and confirm with `langlang -version`; `zig build parser:gen` checks the version before regenerating.

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

The compiler front end is also available as a C library — `zig build libcirc` produces `zig-out/lib/libcirc.a` and `zig-out/include/libcirc.h`, and `zig build libcirc-smoke` builds and runs `examples/c/analyze.c` against it; `zig build libcirc-wasm` builds the same API as a freestanding `zig-out/lib/libcirc.wasm` for browsers and Node. See `DOCS/libcirc-api.md`.

## Usage

`circ-compile` has the following mutually exclusive modes:

| Invocation                                       | Produces                                                                                       |
|--------------------------------------------------|------------------------------------------------------------------------------------------------|
| `circ-compile input.circ -o out.wasm`            | A self-contained `.wasm` artifact (default mode).                                              |
| `circ-compile input.circ --emit-zig -o out.zig`  | The generated standalone Zig source for the experimental emit pipeline.                        |
| `circ-compile input.circ --inspect`              | Pretty-printed parse tree, resolved IR, and diagnostics on stdout.                             |
| `circ-compile input.circ --preview`              | ASCII schematic of the resolved circuit on stdout (no artifact written).                       |
| `circ-compile input.circ --truth-table`          | Markdown truth table enumerating every input vector against the simulated circuit, on stdout.  |
| `circ-compile input.circ --sim`                  | Interactive stdio drive protocol; drive the circuit by pin name for testing/tooling. See `DOCS/sim-protocol.md`. |

In default compile mode, `circ-compile` runs the parser, resolver, validator, and topology serializers in-process and splices the resulting `circ.topology.v0.min` and `circ.topology.v0.full` blobs into a vendored prebuilt runtime `.wasm` (embedded in the CLI via `@embedFile`). No `zig` toolchain or subprocess is required at user runtime.

Additional flags:

- `--warnings-as-errors` (alias `-Werror`) — promote warnings to hard errors (suppresses emission).
- `--expand-macros` — only valid with `--preview`; renders builtin macros (`xor`, `nand`, …) as their expanded primitive sub-circuits.
- `--color=auto|always|never` — only valid with `--preview`; controls ANSI styling of the schematic. Default is `auto` (on when stdout is a TTY; the `NO_COLOR` env var also disables colour).
- `--format=markdown|csv|json` — only valid with `--truth-table`; selects the output format. Default is `markdown`. CSV uses `0`/`1`/`?` cells; JSON encodes undefined cells as `null` so consumers can branch on type.
- `--strict` — only valid with `--truth-table`; promotes any `?` (undefined) output cell into a hard exit-1 with one diagnostic line per offending row on stderr. The table itself still renders. Useful as a CI gate — a regression that introduces a dangling output now fails the build instead of silently producing `?` rows.

Hard errors block emission — partial or "best-effort" artifacts are never produced. Diagnostics use stable codes (`E001`–`E016`, `W001`–`W003`) so downstream tooling can match on them.

## Documentation

- `DOCS/getting-started.md` — write, compile, and run your first circuit (start here).
- `DOCS/circuit-format.md` — the `.circ` language reference.
- `DOCS/wasm-api.md` — runtime API exposed by the compiled `.wasm`.
- `DOCS/simulation-engine.md` — the engine the compiler targets.
- `DOCS/architecture.md` and `DOCS/decisions/` — design rationale for contributors.

## License

[GNU General Public License v3.0](LICENSE).
