# Circuit File Format (.circ)

`.circ` files describe a digital circuit as a set of named components and their connections. The format is a simple declarative DSL designed to map directly onto the simulation engine's component and connection model.

> **Status**: Parsing, semantic validation, and compilation to Zig/WASM exist for the supported surface below (`zig build`-produced WASM per sub-circuit and built-in macros).

## Syntax Overview

A `.circ` file contains a sequence of top-level declarations. Each declaration either names input pins or instantiates a component with named port connections.

```
input <name> [, <name> ...]

<type> <name> (
    <port> = <signal> [,
    <port> = <signal> ...]
)
```

## Comments

Line comments start with `//` and run to end of line (see `Annotation` in `lib/grammar/proto-circ.peg`). Hash (`#`) is not a comment starter in `.circ`.

## Declarations

### Input Pins

```
input pin1, pin2
```

Declares one or more named input pins for the circuit. Input pins are driven externally (by the JavaScript host) and have no input ports of their own.

### Component Instances

```
<type> <instance-name> (
    <input-port> = <signal>,
    ...
)
```

`<type>` is the gate kind. Recognised types:

| Type     | Ports    | Description                                                         |
|----------|----------|---------------------------------------------------------------------|
| `and`    | `a`, `b` | AND gate                                                            |
| `not`    | `in`     | NOT gate (inverter)                                                 |
| `led`    | `in`     | Output indicator                                                    |
| `wire`   | `in`     | Pass-through                                                        |
| `output` | `in`     | Externally observable output pin (special-cased declaration kind)   |

`input` is a sibling pin declaration with its own syntax (no port list), described above.

**Built-in macro gates** expand at compile time to nested `and` / `not` (and optionally other macros). They use **`a`** and **`b`** as input ports and expose **`out`**. Unlike `and`/`not`, **no `import`** is required — the compiler behaves as if `import … from "<builtin>/<name>.circ"` were present.

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
- An inline component expression (see nested components below)

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

The compiled `.wasm` does not expose a programmatic graph-construction API — the topology is baked into the artifact as a custom section and materialised by the embedded runtime at `init()`. Hosts only see the fixed export surface (`setPin`, `run`, `getOutputState`, …) described in [`wasm-api.md`](wasm-api.md); the component IDs they need are emitted by `circ-compile --inspect` under each module's `Inputs (...)` / `Outputs (...)` block.

## Grammar

The parser is generated from a PEG grammar at `lib/grammar/proto-circ.peg` using the `langlang` tool. The generated C parser is at `lib/parser.c` / `lib/parser.h` and is imported into Zig via `lib/syntax/CParser.zig`.

Parse tree node types used by `lib/syntax/translate.zig`:

| Node type            | Meaning                               |
|---------------------|---------------------------------------|
| `LL_NODE_SEQUENCE`  | Ordered list of child nodes           |
| `LL_NODE_NODE`      | Named grammar rule match              |
| `LL_NODE_STRING`    | Matched literal text (identifier, etc.) |
| `LL_NODE_ERROR`     | Parse failure at this position        |

`lib/syntax/nodes/declaration.zig` handles `Declaration` rule nodes and recognises the sub-rules `input`, `output`, and `component` to determine declaration kind.
