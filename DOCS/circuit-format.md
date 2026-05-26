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

`input` is a sibling pin declaration with its own syntax (no port list), described above. All primitives accept an optional `[N]` width annotation; absent it, width is 1.

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

The compiled `.wasm` does not expose a programmatic graph-construction API — the topology is baked into the artifact as a custom section and materialised by the embedded runtime at `init()`. Hosts only see the fixed export surface (`setPin`, `run`, paired `getOutputValue` / `getOutputDefined`, …) described in [`wasm-api.md`](wasm-api.md); the component IDs they need are emitted by `circ-compile --inspect` under each module's `Inputs (...)` / `Outputs (...)` block.

## Grammar

The parser is generated from a PEG grammar at `lib/grammar/proto-circ.peg` using the `langlang` tool. The generated Go parser is at `lib/parser/parser.go`; a hand-written CGo shim at `lib/parser/shim/shim.go` exposes it as a C-callable archive (`lib/parser/parser.a` + `lib/parser/parser.h`) that Zig links via `lib/syntax/CParser.zig`.

Parse tree node types used by `lib/syntax/translate.zig`:

| Node type           | Meaning                                  |
|---------------------|------------------------------------------|
| `NodeType_Sequence` | Ordered list of child nodes              |
| `NodeType_Node`     | Named grammar rule match                 |
| `NodeType_String`   | Matched literal text (identifier, etc.)  |
| `NodeType_Error`    | Parse failure at this position           |

`lib/syntax/nodes/declaration.zig` handles `Declaration` rule nodes and recognises the sub-rules `input`, `output`, and `component` to determine declaration kind.

## Topology Format Version

Compiled `.wasm` artifacts embed the resolved circuit as a custom section. The current format identifier is `CIRC` (v02), bumped from the v01 format that preceded multi-bit support. Each serialised component now carries a `width: u8` byte; the runtime materialises the corresponding pool tier on `init()`. See [`wasm-api.md`](wasm-api.md) for the host-facing ABI and `lib/topology/serializer.zig` for the wire layout.

## Diagnostic Codes

The stable validator surface (E001–E016, W001–W003) is enumerated in [`language.md`](language.md) §4.2 and `lib/validator/codes.zig`. The multi-bit codes added with v02 are:

| Code | Meaning |
| --- | --- |
| E014 | width mismatch between a driver and the port it feeds |
| E015 | sub-circuit is not parametric (caller passed `[N]` call-widths to a scalar callee) |
| E016 | parameter count mismatch (wrong number of `[w0, w1, ...]` call-widths at the call site) |
