# circ-compiler

`circ-compiler` compiles `.circ` digital-logic source files into self-contained WebAssembly modules. Each compiled `.wasm` embeds the simulation engine plus circuit-specific construction code and exposes a fixed pull-based runtime API (`init`, `run`, `setPin`, paired `getOutputValue` / `getOutputDefined`, and a `memLoad` / `memStore` family for `rom` / `ram` contents, …) usable from any host that supports WebAssembly. The compiler is written in Zig and ships as a single CLI: `circ-compile`.

## What it does

Given a `.circ` source like:

```text
input a
not inv(in=a)
output out(in=inv.out)
```

`circ-compile inverter.circ -o inverter.wasm` produces a `.wasm` whose exported `setPin` / `run` / `getOutputValue` / `getOutputDefined` functions simulate that exact circuit. The two getters return paired `BitVecState` halves (value bits + defined-bits) crossed as `i64` / `BigInt`. Circuits that declare `rom` / `ram` memories also export `getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, and `getMemDefined`, so the host loads and reads back memory contents at runtime (see `DOCS/wasm-api.md`). Multi-file projects work the same way — the root file imports siblings and the compiler flattens every sub-circuit into a single ordered topology before serializing it into the `.wasm`:

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
- [Go](https://go.dev/) 1.21+ — used to compile the langlang-generated parser into a CGo c-archive that links into the Zig binary. Every build runs `go build` once to (re)produce `lib/parser/parser.a`.
- Optional: [langlang](https://github.com/clarete/langlang) `v0.0.12` — only needed if you want to regenerate `lib/parser/parser.go` from `lib/grammar/proto-circ.peg`. The generated source is vendored in the repo, so contributors who don't touch the grammar do not need langlang installed. Install with `go install github.com/clarete/langlang/go/cmd/langlang@v0.0.12`.

Build the CLI:

```sh
zig build circ-compile
```

The binary lands at `zig-out/bin/circ-compile`. Run the test suite with:

```sh
zig build test
```

This is the fast dev-loop suite. `zig build test-all` additionally runs the slow emit-zig backend smoke (`test-emit`, a nested `zig build wasm` per fixture) and is what CI runs. (Set `CIRC_SKIP_PERF=1` to skip the smoke perf test in noisy CI environments.)

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

Hard errors block emission — partial or "best-effort" artifacts are never produced. Diagnostics use stable codes (`E001`–`E018`, `W001`–`W003`) so downstream tooling can match on them.

## Documentation

- `DOCS/getting-started.md` — write, compile, and run your first circuit (start here).
- `DOCS/circuit-format.md` — the `.circ` language reference.
- `DOCS/wasm-api.md` — runtime API exposed by the compiled `.wasm`.
- `DOCS/simulation-engine.md` — the engine the compiler targets.
- `DOCS/architecture.md` and `DOCS/decisions/` — design rationale for contributors.

## License

[GNU General Public License v3.0](LICENSE).
