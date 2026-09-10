# Circuit File Format (.circ)

`.circ` files describe a digital circuit as a set of named components and their connections. The format is a simple declarative DSL designed to map directly onto the simulation engine's component and connection model.

> **Status**: Parsing, semantic validation, and compilation to WASM exist for the supported surface below. A single root `.circ` (plus any sibling files it imports) produces one self-contained `.wasm` artifact via the in-process topology-splice pipeline; the runtime is prebuilt and embedded.

## Syntax Overview

A `.circ` file contains a sequence of top-level declarations. Each declaration either names input pins or instantiates a component with named port connections. Every signal-carrying declaration may carry an optional width annotation `[N]` where `N` is in `[1, 64]`; a missing `[N]` means width 1.

```
input  [<width>] <name> [, <name> ...]
output [<width>] <name> [, <name> ...]

<type> [<width>] <instance-name> [<call-widths>] (
    <port> = <signal> [,
    <port> = <signal> ...]
)
```

`<width>` is a literal `[N]` (or a parameter inside a parametric sub-circuit; see [`language.md`](language.md) §6.3). `<call-widths>` is a comma-separated list `[w0, w1, ...]` that pins the width parameters of an imported sub-circuit at the call site.

For the full language reference (parametric sub-circuits, slice/index/concat signals, the `<W>` introduction form, built-in parametric macros, and diagnostic semantics) see [`language.md`](language.md).

## Comments

Line comments start with `//` and run to end of line (see `Annotation` in `lib/grammar/proto-circ.peg`). Hash (`#`) is not a comment starter in `.circ`.

## Declarations

### Input Pins

```
input pin1, pin2
input[4] addr
input<W>[W] data
```

Declares one or more named input pins for the circuit. Input pins are driven externally (by the host) and have no input ports of their own. An optional `[N]` after `input` makes the pin `N` bits wide; the parametric form `input<W>[W]` declares both a width parameter and an input of that width (see [`language.md`](language.md) §6.3).

### Component Instances

```
<type> <instance-name> (
    <input-port> = <signal>,
    ...
)
```

`<type>` is the gate kind. Recognised types:

| Type     | Ports    | Width rule                                                                    | Description                                                         |
|----------|----------|-------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `and`    | `a`, `b` | bit-parallel; both inputs must match the instance width                       | AND gate                                                            |
| `not`    | `in`     | bit-parallel; input must match the instance width                             | NOT gate (inverter)                                                 |
| `led`    | `in`     | input must match the instance width; widths `> 1` render as a numeric display | Output indicator                                                    |
| `wire`   | `in`     | input must match the instance width                                           | Pass-through                                                        |
| `output` | `in`     | input must match the instance width                                           | Externally observable output pin (special-cased declaration kind)   |
| `rom`    | `addr`   | declared `[W, A]` (data width, address width); `addr` is `A` wide, `out` is `W` wide | Read-only memory of `2^A` words; contents are loaded at runtime, see [`language.md`](language.md) §6.5 |
| `ram`    | `addr`, `din`, `we`, `clk` | declared `[W, A]`; `addr` is `A`, `din`/`out` are `W`, `we`/`clk` are 1  | Read/write memory; writes `din` on the rising edge of `clk` when `we` is high; contents loaded at runtime, see [`language.md`](language.md) §6.5 |

`input` is a sibling pin declaration with its own syntax (no port list), described above. All primitives accept an optional `[N]` width annotation; absent it, width is 1 — except memories, which take exactly two, `[W, A]`, after the instance name.

**Built-in macro gates** expand at compile time to nested `and` / `not` (and optionally other macros). They use **`a`** and **`b`** as input ports and expose **`out`**. Unlike `and`/`not`, **no `import`** is required — the compiler behaves as if `import … from "<builtin>/<name>.circ"` were present. Each macro is parametric: `or[8] g(a=x, b=y)` produces a bit-parallel 8-bit OR.

| Type   | Ports    | Expansion |
|--------|----------|-----------|
| `or`   | `a`, `b` | OR from `not`/`and`            |
| `nand` | `a`, `b` | NAND                           |
| `nor`  | `a`, `b` | NOR (uses internal `or` macro)|
| `xor`  | `a`, `b` | XOR                            |
| `xnor` | `a`, `b` | XNOR (uses internal `xor` macro)|

`<input-port>` is the name of the port being driven (e.g. `a`, `b`, `in`).

`<signal>` is one of:
- `<instance-name>.out` — the output of a named component or primitive with a single implicit output `.out`.
- `<instance-name>.<port>` — the output pin of an imported subcircuit that exposes `<port>` (`sum`, `carry`, etc.).
- `<signal>[i]` — single-bit index into a multi-bit signal (yields width 1).
- `<signal>[lo..hi]` — half-open slice `[lo, hi)` of a multi-bit signal (yields width `hi - lo`).
- `{<signal>, <signal>, ...}` — concatenation, **low operand on the left**, so `{a, b}` puts `a` in the low bits and `b` in the high bits.
- An inline component expression (see nested components below).

See [`language.md`](language.md) §4 and §6 for the full signal grammar and width-checking rules.

## Signal References

A signal reference connects a port to the output of a previously declared name:

```
a = pin1.out
```

This wires port `a` to the output of the component named `pin1`.

## Nested Component Expressions

Components may be defined inline as the value of a port connection. The nested component has no instance name but its `.out` output is wired immediately to the enclosing port:

```
and combine (
    a = pin1.out,
    b = not (
        in = pin2.out
    ).out
)
```

Here a `not` gate is instantiated anonymously; its output is connected to port `b` of `combine`.

## Full Example

```
input pin1, pin2

and combine (
    a = pin1.out,
    b = not (
        in = pin2.out
    ).out
)

led result (
    in = combine.out
)
```

This circuit computes `pin1 AND (NOT pin2)` and displays the result on an LED.

The compiled `.wasm` does not expose a programmatic graph-construction API — the topology is baked into the artifact as a custom section and materialised by the embedded runtime at `init()`. Hosts only see the fixed export surface (`setPin`, `run`, paired `getOutputValue` / `getOutputDefined`, …) described in [`wasm-api.md`](wasm-api.md); the component IDs they need come from the `circ.topology.v0.full` section (each record carries the component's name and kind); `circ-compile --inspect` prints resolver-local ids that match the artifact's only for a single-file circuit without sub-circuits.

## Grammar

The parser is generated from a PEG grammar at `lib/grammar/proto-circ.peg` by the maintainer's langlang fork (`-output-language zig`); the generated file is vendored at `lib/parser/parser.zig` and walked by `lib/syntax/translate.zig`.

Parse tree node types used by `lib/syntax/translate.zig`:

| Node type (`parser.runtime.NodeType`) | Meaning                                  |
|---------------------------------------|------------------------------------------|
| `.sequence`                           | Ordered list of child nodes              |
| `.node`                               | Named grammar rule match                 |
| `.string`                             | Matched literal text (identifier, etc.)  |
| `.err`                                | A recovered parse error at this position |

## Topology Format Version

Compiled `.wasm` artifacts embed the resolved circuit as a custom section. The current format identifier is `CIRC` (v03). v02 added a `width: u8` byte to every serialised component (the runtime materialises the corresponding pool tier on `init()`); v03 adds the memory kinds `rom = 8` and `ram = 9`, whose records carry one trailing `addr_width` byte, and the port bytes `addr`/`din`/`we`/`clk`. Memory contents are not part of the topology — they are loaded at runtime. See [`wasm-api.md`](wasm-api.md) for the host-facing ABI and `lib/topology/serializer.zig` for the wire layout.

## Diagnostic Codes

The stable validator surface (E001–E018, W001–W003) is registered in `lib/validator/codes.zig`; the rules behind each code are in [`language.md`](language.md) §4.1. The full catalogue follows, with each code's default message:

| Code | Meaning |
| --- | --- |
| E001 | undeclared name |
| E002 | unknown port (also an out-of-range or inverted slice, and an unknown memory port) |
| E003 | multiple drivers for input port |
| E004 | required input is unconnected |
| E005 | duplicate instance name |
| E006 | name shadows built-in (`and`, `not`, `wire`, `led`, `rom`, `ram`, `input_pin`, `output_pin`, …) |
| E007 | output has no assigned driver |
| E008 | combinational loop detected |
| E009 | import not found |
| E010 | import cycle detected |
| E011 | import alias collision (with another import or a built-in name) |
| E012 | unknown sub-circuit port |
| E013 | sub-circuit arity mismatch (a required sub-circuit input left unconnected) |
| E014 | width mismatch between a driver and the port it feeds (added with v02) |
| E015 | sub-circuit is not parametric (caller passed `[N]` call-widths to a scalar callee; v02) |
| E016 | parameter count mismatch (wrong number of `[w0, w1, ...]` call-widths at the call site; v02) |
| E017 | memory parameter list malformed (a `rom`/`ram` declaration without exactly two instance-position width arguments `[W, A]`; v03) |
| E018 | memory width out of range (`W` outside `1..64` or `A` outside `1..16`; v03) |
| W001 | unused input declaration |
| W002 | dangling output declaration |
| W003 | unused import declaration |
