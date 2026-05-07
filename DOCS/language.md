# The circ Language

`circ` is a small declarative language for describing digital logic circuits. A
program is a flat list of declarations: each declaration either names an
external pin or instantiates a component and wires its input ports to signals
produced by other components. The compiler (`circ-compile`) parses the source,
resolves names, validates the resulting graph, and lowers it to a self-contained
WebAssembly module.

This document is the language reference. For an end-to-end tutorial see
[`getting-started.md`](getting-started.md); for the runtime API exposed by the
compiled artifact see [`wasm-api.md`](wasm-api.md).

> **Status.** This reference covers the v0 surface: imports, input/output pins,
> primitive components (`and`, `not`, `led`, `wire`), the auto-imported macro
> family (`or`, `nand`, `nor`, `xor`, `xnor`), anonymous nested components, and
> sub-circuit instantiation. Anything not mentioned here is not part of the
> language yet.

---

## 1. Abstract Grammar

The grammar below uses the conventions of EBNF: *italics* mark non-terminals,
**bold** marks literal terminals, `[ x ]` is optional, `{ x }` is zero or more,
and `|` separates alternatives. The authoritative PEG source lives at
`lib/grammar/proto-circ.peg`; this presentation is a slightly normalised
reading of it.

```
program     = { item } .
item        = comment
            | import
            | input-decl
            | output-decl
            | component-decl .

comment     = "//" { any-char-except-newline } newline .

import      = "import" alias string-literal .
alias       = identifier .

input-decl  = "input" identifier { "," identifier } .
output-decl = "output" identifier "(" "in" "=" signal ")" .

component-decl
            = type identifier "(" port-binding { "," port-binding } ")" .
type        = "and" | "not" | "led" | "wire"
            | "or" | "nand" | "nor" | "xor" | "xnor"
            | identifier .            (* user-defined sub-circuit alias *)

port-binding = identifier "=" signal .

signal      = qualified-ref
            | anonymous-component "." identifier .
qualified-ref
            = identifier [ "." identifier ] .   (* "name" or "name.port" *)
anonymous-component
            = type "(" port-binding { "," port-binding } ")" .

identifier  = ( letter | "_" ) { letter | digit | "_" } .
string-literal
            = '"' { any-char-except-double-quote } '"' .
```

A few intentional shapes to note in the grammar:

* The order of items in a program is irrelevant for *semantics* (the validator
  resolves names globally) but parsing is strictly left-to-right line-oriented.
* There is no statement terminator. Items are separated by whitespace; a single
  declaration may span multiple lines as long as its parentheses balance.
* `output` is technically a component-shaped declaration (it has one port,
  `in`), but it is special-cased above to make the asymmetry with `input`
  explicit.

---

## 2. Lexical Structure

### 2.1 Whitespace

Spaces, tabs, carriage returns, and newlines are insignificant outside of
string literals and identifiers. They may appear between any two tokens.

### 2.2 Comments

`circ` has one comment form, the C++-style line comment:

```
// this is a comment, ignored to end of line
```

`#` is **not** a comment introducer. Block comments (`/* … */`) are not
supported.

### 2.3 Identifiers

Identifiers match `[A-Za-z_][A-Za-z0-9_]*` and are case-sensitive. They are
used for component instance names, port names, input/output pin names, and
import aliases. There is no distinction between "user" and "system"
identifiers — but type keywords (`input`, `output`, `and`, `not`, `wire`, etc.)
are reserved when used in declaration position.

### 2.4 String Literals

String literals appear only in `import` declarations and are double-quoted with
no escape processing. They name a path on disk (or a virtual path beginning
with `<builtin>/`).

```
import xor "<builtin>/xor.circ"
import half_adder "half_adder.circ"
```

Paths are resolved relative to the directory of the file containing the import.

---

## 3. Declarations

A `circ` program is a sequence of declarations. The four kinds are described
below.

### 3.1 Input Pins

```
input a
input clk, reset
```

`input` declares one or more externally driven pins. An input pin has no input
ports of its own; its single output is referenced as **`<name>`** or
equivalently **`<name>.out`** elsewhere in the program. Input pins are driven
from the host via `setPin(component_id, value)` after compilation.

### 3.2 Output Pins

```
output sum(in = adder.out)
```

`output` declares a named externally observable pin and binds its single port
`in` to a signal. Output pins are read from the host via
`getOutputState(driver_id)` (note: the driver's id, not the output pin's own
id; see [`wasm-api.md`](wasm-api.md)).

### 3.3 Component Instances

A component is instantiated by writing its **type**, an instance **name**, and
a parenthesised list of **port bindings**:

```
and gate1(a = pin1, b = pin2)
not inv (in = clk.out)
```

The available primitive types are:

| Type   | Input ports | Output | Notes                                  |
| ------ | ----------- | ------ | -------------------------------------- |
| `and`  | `a`, `b`    | `out`  | 2-input AND gate.                      |
| `not`  | `in`        | `out`  | Inverter.                              |
| `led`  | `in`        | —      | Visualisation sink. No `.out`.         |
| `wire` | `in`        | `out`  | Pass-through. See §5.                  |

The auto-imported macro family expands at compile time to nested `and`/`not`
gates. They share a common port shape:

| Type   | Input ports | Output | Expansion                          |
| ------ | ----------- | ------ | ---------------------------------- |
| `or`   | `a`, `b`    | `out`  | `not(and(not a, not b))`           |
| `nand` | `a`, `b`    | `out`  | `not(and a b)`                     |
| `nor`  | `a`, `b`    | `out`  | `not(or a b)`                      |
| `xor`  | `a`, `b`    | `out`  | `or(and a !b, and !a b)`           |
| `xnor` | `a`, `b`    | `out`  | `not(xor a b)`                     |

A user-defined sub-circuit is referenced by the alias bound in its `import`
declaration. Its ports are exactly the names declared as `input`/`output` in
the imported file (e.g. the `half_adder` sub-circuit exposes input ports `a`,
`b` and output ports `sum`, `carry`).

### 3.4 Imports

```
import half_adder "half_adder.circ"
```

`import` makes a sibling `.circ` file available under an alias in the current
file. The path is resolved relative to the importing file. Built-in macros
live at the virtual path `<builtin>/<name>.circ` and are auto-imported as soon
as the file participates in the project pipeline (i.e. has at least one
explicit `import`); to use a built-in in a single-file program with no other
imports, write the import explicitly:

```
import xor "<builtin>/xor.circ"
```

---

## 4. Signals and Wiring

A *signal* is whatever you place on the right-hand side of a port binding. It
identifies the source of the bit that drives the port. Signals come in three
forms.

**Reference to an input pin:**

```
and g(a = pin1, b = pin2)        // pin1 and pin2 are 'input' declarations
```

**Reference to a named component's output:**

```
not n1 (in = pin1.out)
and g  (a  = n1.out, b = pin2)
```

The `.out` suffix is the implicit output port of any single-output primitive.
For sub-circuit instances, use the explicit output port name from the imported
file: `ha.sum`, `ha.carry`, etc.

**Anonymous nested components.** A component may be instantiated inline as the
value of a port. The nested instance has no name; its `.out` is wired
immediately into the enclosing port:

```
and g(
    a = pin1,
    b = not(in = pin2).out
)
```

Anonymous nesting may nest arbitrarily deep. It is purely a syntactic sugar:
the resolver lowers it to an unnamed component instance with the same wiring
rules as a named one.

### 4.1 Validation Rules

The compiler enforces a small set of rules on the resulting graph; violations
produce diagnostics with stable codes (`E001`–`E013`, `W001`–`W003`, see
`circuit-format.md` for the full catalogue):

* Every signal reference must resolve to a declared name (`E001`).
* Every named port on a component must exist on that component's type
  (`E002`, `E012`).
* Every input port that the component requires must be bound exactly once;
  binding a port twice is `E003` (multi-driver), and leaving a required port
  unbound is `E004`/`E013`.
* Identifiers must be unique within their file (`E005`); user instances may
  not shadow primitive type names (`E006`).
* The induced signal graph must be acyclic (`E008`). See §5 for the role
  `wire` plays in cycle detection.

---

## 5. Wires

A `wire` is a one-port pass-through component. Its single input port is `in`
and its single output port is `out`; the value on `out` is, after evaluation,
identical to the value on `in`. Wires are the closest thing the language has
to a "let" binding for signals.

### 5.1 What wires are for

Wires exist for two reasons.

**(a) Naming an intermediate signal.** A bare `pin1.out` carries no
documentation. Threading it through a `wire` lets you give the bit a meaningful
name without changing the circuit's logical behaviour:

```
input clk
wire clock_buf(in = clk)
and  g(a = clock_buf.out, b = data.out)
```

This is purely a readability device. The compiler does not optimise wires
away in the topology section, so the named signal survives into runtime
introspection.

**(b) Anchoring a signal that is referenced more than once.** Inline anonymous
components have no name and therefore cannot be re-used; if the same derived
signal feeds two ports, you need a named anchor for it. A `wire` is the
lightest anchor available:

```
input a
wire na(in = not(in = a).out)     // 'na' = NOT a, named once
and  g1(a = na.out, b = b1)
and  g2(a = na.out, b = b2)
```

### 5.2 Wires and cycles

Wires participate in cycle detection like any other component. A pair of wires
that drive each other's `in` is a hard error (`E008`):

```
// E008_wire_loop.circ — rejected at compile time
wire w1(in = w2.out)
wire w2(in = w1.out)
```

This is *not* a special-case for `wire`; it is the same rule that forbids
combinational feedback through any chain of components. The fixture
`clean_gated_feedback.circ` illustrates the legal counterpart, where wires
break two NOT gates into a sequence rather than a loop:

```
not  n1(in = w2.out)   // n1 is fed from w2
wire w1(in = n1.out)
not  n2(in = w1.out)
wire w2(in = n2.out)   // closes the chain — but the chain has length 4 and
                       // — crucially — has no cycle in the *signal* graph
```

(In this snippet `w2.out` is forward-referenced; the validator resolves names
globally, so order in source is irrelevant for binding.)

### 5.3 What wires are *not*

A `wire` is not a multi-bit bus, not a tri-state line, and not a clocked
register. It is a value-preserving pass-through over a single bit. If you find
yourself wanting any of those things, the language does not yet model them.

---

## 6. A Worked Example

The program below builds a half-adder out of primitives and exposes its sum
and carry as outputs. It exercises every construct in the language: imports,
input pins, primitive components, a built-in macro (`xor`), a `wire` used both
to name a signal and to fan it out, anonymous nested components, and output
pins.

```
// half_adder_demo.circ
//
// Computes:   sum   = a XOR b
//             carry = a AND b
// and exposes a third output 'busy' = NOT(sum) AND carry, which is always 0
// — purely to demonstrate fan-out via a 'wire'.

import xor "<builtin>/xor.circ"

input a, b

// xor primitive (auto-imports the macro expansion under the hood).
xor s_gate(a = a, b = b)

// 'sum_w' names the XOR output so we can use it twice without re-instantiating
// the gate. Without the wire, anonymous nesting would force us to duplicate
// the xor gate.
wire sum_w(in = s_gate.out)

// First fan-out: feed the sum into a NOT gate inline.
// Second fan-out: drive the 'sum' output pin directly from the same wire.
and busy_gate(
    a = not(in = sum_w.out).out,
    b = and(a = a, b = b).out          // anonymous AND for the carry bit
)

output sum  (in = sum_w.out)
output carry(in = and(a = a, b = b).out)
output busy (in = busy_gate.out)
```

Compile and inspect:

```sh
circ-compile half_adder_demo.circ -o half_adder_demo.wasm
circ-compile half_adder_demo.circ --preview
```

The `--preview` flag prints an ASCII schematic of the resolved circuit; see
[`preview.md`](preview.md) for the rendering conventions.

---

## 7. Where to Go Next

* [`getting-started.md`](getting-started.md) — install the compiler, write your
  first circuit, drive it from Node.
* [`circuit-format.md`](circuit-format.md) — the original tutorial-flavored
  walkthrough of the format, with the full diagnostic-code catalogue.
* [`wasm-api.md`](wasm-api.md) — the runtime API exposed by every compiled
  `.wasm` artifact.
* [`preview.md`](preview.md) — `--preview`, `--expand-macros`, and the
  conventions used when rendering circuits as ASCII.
