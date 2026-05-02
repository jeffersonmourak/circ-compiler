# circ-compiler

`circ-compiler` compiles `.circ` digital-logic source files into self-contained WebAssembly modules. Each compiled `.wasm` embeds the simulation engine plus circuit-specific construction code and exposes a fixed pull-based runtime API (`init`, `run`, `setPin`, `getOutputState`, …) usable from any host that supports WebAssembly. The compiler is written in Zig and ships as a single CLI: `circ-compile`.

## What it does

Given a `.circ` source like:

```text
input a
not inv(in=a)
output out(in=inv.out)
```

`circ-compile inverter.circ -o inverter.wasm` produces a `.wasm` whose exported `setPin` / `run` / `getOutputState` functions simulate that exact circuit. Multi-file projects work the same way — the root file imports siblings and the compiler emits one `buildXxx` function per source file:

```text
# half_adder.circ
input a, b
xor s(a=a, b=b)
and c(a=a, b=b)
output sum(in=s.out)
output carry(in=c.out)

# root.circ
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
- Optional: [langlang](https://github.com/clarete/langlang) — only needed if you want to regenerate `lib/parser.c` / `lib/parser.h` from `lib/grammar/proto-circ.peg`. The generated sources are vendored in the repo, so day-to-day contributors do not need langlang installed.

Build the CLI:

```sh
zig build circ-compile
```

The binary lands at `zig-out/bin/circ-compile`. Run the test suite with:

```sh
zig build test
```

(Set `CIRC_SKIP_PERF=1` to skip the smoke perf test in noisy CI environments.)

## Usage

`circ-compile` has three mutually exclusive modes:

| Invocation                                | Produces                                                 |
|-------------------------------------------|----------------------------------------------------------|
| `circ-compile input.circ -o out.wasm`     | A self-contained `.wasm` artifact (default mode).        |
| `circ-compile input.circ --emit-zig -o out.zig` | The generated Zig source that would be compiled to WASM. |
| `circ-compile input.circ --inspect`       | Pretty-printed parse tree, resolved IR, and diagnostics on stdout. |

Additional flags:

- `--warnings-as-errors` — promote warnings to hard errors (suppresses emission).
- `--build-dir <path>` — use this directory for the intermediate `zig build` invocation in default compile mode (default: a fresh `/tmp/circ-compile-<rand>/`). Preserved on success when explicitly set; the default temp dir cleans on success and is preserved on failure.

Hard errors block emission — partial or "best-effort" artifacts are never produced. Diagnostics use stable codes (`E001`–`E013`, `W001`–`W003`) so downstream tooling can match on them.

## Documentation

- `DOCS/getting-started.md` — write, compile, and run your first circuit (start here).
- `DOCS/circuit-format.md` — the `.circ` language reference.
- `DOCS/wasm-api.md` — runtime API exposed by the compiled `.wasm`.
- `DOCS/simulation-engine.md` — the engine the compiler targets.
- `DOCS/architecture.md` and `DOCS/decisions/` — design rationale for contributors.

## License

[GNU General Public License v3.0](LICENSE).
