# The circ Language

`circ` is a small declarative language for describing digital logic circuits. A
program is a flat list of declarations: each declaration either names an
external pin or instantiates a component and wires its input ports to signals
produced by other components. The compiler (`circ-compile`) parses the source,
resolves names, validates the resulting graph, and lowers it to a self-contained
WebAssembly module.

This document is the language reference. For an end-to-end tutorial, see
[`getting-started.md`](getting-started.md); for the runtime API exposed by the
compiled artifact, see [`wasm-api.md`](wasm-api.md).

> **Status.** This reference covers the surface as of the native-memories
> release: imports, input/output pins, primitive components (`and`, `not`,
> `led`, `wire`), the memories `rom` and `ram` (§3.5, §6.5), the auto-imported
> macro family (`or`, `nand`, `nor`, `xor`, `xnor`), anonymous nested
> components, sub-circuit instantiation, and width annotations on every
> signal-carrying declaration (`[N]` for literal widths, `<W>` for parametric
> ones). Slice (`a[lo..hi]`), bit-index (`a[i]`), and concatenation (`{a, b}`)
> signal expressions are also part of the language. Anything not mentioned
> here is not part of the language yet.

---

## 1. Abstract Grammar

The grammar below uses the conventions of EBNF: *italics* mark non-terminals,
**bold** marks literal terminals, `[ x ]` is optional, `{ x }` is zero or more,
and `|` separates alternatives. The authoritative PEG source lives at
`lib/grammar/proto-circ.peg`; this presentation is a slightly normalised
reading of it.

```
program      = { item } .
item         = comment
             | import
             | input-decl
             | component-decl
             | connection .

comment      = "//" { any-char-except-newline } newline .

import       = "import" alias string-literal .
alias        = identifier .

input-decl   = "input" [ param-intro ] [ width-annot ] ident-list .
param-intro  = "<" identifier { "," identifier } ">" .    (* declares width parameters *)
width-annot  = "[" width-arg "]" .
width-arg    = integer | identifier .                     (* a literal or a parameter *)
ident-list   = identifier { "," identifier } .

component-decl
             = type [ width-annot ] identifier [ call-widths ] bindings
             | type [ width-annot ] ident-list .          (* port-less form, see below *)
type         = "output" | "bus" | "led" | "and" | "or" | "not" | "xor" | "nand"
             | identifier .          (* wire, nor, xnor, rom, ram and every
                                        sub-circuit alias arrive through this branch *)
call-widths  = "[" width-arg { "," width-arg } "]" .      (* also a memory's [W, A] *)
bindings     = "(" port-binding { "," port-binding } ")" .
port-binding = identifier "=" signal .

signal       = concat | indexed-ref .
concat       = "{" signal { "," signal } "}" .
indexed-ref  = base-ref [ subscript ] .
subscript    = "[" integer ".." integer "]" | "[" integer "]" .
base-ref     = anonymous-component "." identifier
             | identifier [ "." identifier ] .            (* "name" or "name.port" *)
anonymous-component
             = type bindings .

connection   = signal "<>" signal .                       (* parsed, then discarded *)

identifier   = ( letter | "_" ) { letter | digit | "_" } .
integer      = digit { digit } .
string-literal
             = '"' { any-char-except-double-quote } '"' .
```

A few intentional shapes, and a few accidents, to note in the grammar:

* The order of items in a program is irrelevant for *semantics* (the validator
  resolves names globally), but parsing is strictly left-to-right
  line-oriented.
* `circ` has no statement terminator. Whitespace separates items; a single
  declaration may span multiple lines as long as its parentheses balance.
* `output` is an ordinary component-shaped declaration with one port. The
  translator **ignores the binding name**: `output r(zzz = g.out)` compiles,
  and it drops any binding after the first. Write `in` anyway.
* The `type` keywords carry no word boundary, so the parser splits an
  identifier in type position that merely *begins* with one: `andx g(a=a, b=a)` parses
  as `and x(...)` plus a syntax error (`recovery_keyword_prefix.circ`). A
  sub-circuit alias must therefore not start with `and`, `or`, `not`, `xor`,
  `nand`, `led`, `bus`, or `output`.
* `bus` is a keyword nothing implements: `bus x(in = y)` resolves to an
  undeclared name (`E001`).
* The port-less form `type ident-list` (`led x`, `and g1, g2`) parses but has
  no use today: a gate or LED declared that way reports `E004` (unconnected
  input), and `output q` makes the pin its own driver (`E008`).
* The parser accepts a `<>` connection line, and the translator discards it
  without a diagnostic (`recovery_connection_line.circ`).

---

## 2. Lexical Structure

### 2.1 Whitespace

Spaces, tabs, carriage returns, and newlines are insignificant outside string
literals and identifiers. They may appear between any two tokens.

### 2.2 Comments

`circ` has one comment form, the C++-style line comment:

```
// this is a comment, ignored to end of line
```

`#` is **not** a comment introducer. `circ` does not support block comments
(`/* … */`).

### 2.3 Identifiers

Identifiers match `[A-Za-z_][A-Za-z0-9_]*` and are case-sensitive. They name
component instances, ports, input/output pins, and import aliases. The
language draws no distinction between "user" and "system" identifiers, but
type keywords (`input`, `output`, `and`, `not`, `wire`, etc.) are reserved in
declaration position.

### 2.4 String Literals

String literals appear only in `import` declarations and are double-quoted with
no escape processing. They name a path on disk (or a virtual path beginning
with `<builtin>/`).

```
import xor "<builtin>/xor.circ"
import half_adder "half_adder.circ"
```

The compiler resolves paths relative to the directory of the file containing
the import.

---

## 3. Declarations

A `circ` program is a sequence of declarations. This section describes the
four kinds. Every declaration that carries a signal may name its width in
bits with a `[N]` annotation; a missing `[N]` means width 1, which keeps
pre-multi-bit `.circ` files legal as-is.

### 3.1 Input Pins

```
input a
input clk, reset
input[4] addr, data            // 4-bit buses
```

`input` declares one or more externally driven pins. An input pin has no input
ports of its own; elsewhere in the program you reference its single output as
**`<name>`** or, equivalently, **`<name>.out`**. The host drives input pins
via `setPin(component_id, value, defined)` after compilation (see
[`wasm-api.md`](wasm-api.md) for the BigInt-pair convention).

The `[N]` annotation between the keyword and the names sets the width for
every name in that `input` line. To declare pins at different widths, write
separate `input` lines.

A sub-circuit becomes parametric by introducing a parameter with `<W>` on its
`input` lines (covered fully in §6):

```
input<W>[W] a, b               // a, b inherit the parameter W as their width
```

### 3.2 Output Pins

```
output sum(in = adder.out)
output[4] result(in = alu.out)
```

`output` declares a named externally observable pin and binds its single port
`in` to a signal. Multi-bit outputs use the same `[N]` annotation. The host
reads output pins through two paired exports: `getOutputValue(driver_id)`
returns the `BitVecState.value` field as a BigInt;
`getOutputDefined(driver_id)` returns `BitVecState.defined`. Both take the
**driver** component id, not the output pin's own id; see
[`wasm-api.md`](wasm-api.md).

### 3.3 Component Instances

You instantiate a component by writing its **type**, an optional `[N]` width,
an instance **name**, and a parenthesised list of **port bindings**:

```
and gate1(a = pin1, b = pin2)
not inv  (in = clk.out)
and[4] adder(a = x, b = y)     // 4-bit AND
```

The available primitive types are:

| Type   | Input ports | Output | Notes                                                                  |
| ------ | ----------- | ------ | ---------------------------------------------------------------------- |
| `and`  | `a`, `b`    | `out`  | Bitwise AND. Width controlled by `[N]`; defaults to 1.                 |
| `not`  | `in`        | `out`  | Bitwise inverter. Width controlled by `[N]`; defaults to 1.            |
| `led`  | `in`        | `out`  | Visualisation sink; `out` re-drives `in` so an LED can feed a gate. Multi-bit form renders per `--preview` flags. |
| `wire` | `in`        | `out`  | Pass-through. See §5.                                                  |

The auto-imported macro family is parametric in width; the default-missing-`[N]`
rule keeps every existing scalar caller working unchanged.

| Type   | Input ports | Output | Expansion (per width slot)         |
| ------ | ----------- | ------ | ---------------------------------- |
| `or`   | `a`, `b`    | `out`  | `not(and(not a, not b))`           |
| `nand` | `a`, `b`    | `out`  | `not(and a b)`                     |
| `nor`  | `a`, `b`    | `out`  | `not(or[W] a b)` — `or` propagates width |
| `xor`  | `a`, `b`    | `out`  | `and(or a b, nand a b)`            |
| `xnor` | `a`, `b`    | `out`  | `not(xor[W] a b)` — `xor` propagates width |

You reference a user-defined sub-circuit by the alias bound in its `import`
declaration. Its ports are exactly the names declared as `input`/`output` in
the imported file. If the imported sub-circuit is parametric (declares one or
more `<W>` parameters), the caller binds widths positionally with the
`name[N, M, ...]` form at the instance name:

```
mux inst[4, 2](data = x, select = sel)   // mux<W, S> instantiated at W=4, S=2
```

Omitting the `[N, ...]` defaults all parameters to 1.

### 3.4 Imports

```
import half_adder "half_adder.circ"
```

`import` makes a sibling `.circ` file available under an alias in the current
file. The compiler resolves the path relative to the importing file. Built-in
macros live at the virtual path `<builtin>/<name>.circ`, and the compiler
auto-imports one whenever a file uses it. A single-file program may write
`xor s(a=a, b=b)` with no `import` at all, and every mode (compile, preview,
truth table, sim, analyze) resolves it through the project pipeline. Writing
the import explicitly is still valid, and is the clearer form when a file
mixes built-ins with its own siblings:

```
import xor "<builtin>/xor.circ"
```

The one exception is `--inspect`, which stays a single-module debugging view
and reports an unimported built-in as `E001`.

### 3.5 Memories (declaration shape)

`rom` and `ram` are built-in memory types. You declare a memory like a
parametric sub-circuit instance: the type keyword, an instance name, exactly
two instance-position width arguments `[W, A]` (data width and address
width), and a port list:

```
input[4] pc
rom code[8, 4](addr = pc.out)          // 16 words of 8 bits, read-only
output[8] out(in = code.out)

input[4] a
input[8] d
input we, clk
ram data[8, 4](addr = a.out, din = d.out, we = we.out, clk = clk.out)
output[8] q(in = data.out)
```

| Type  | Input ports                 | Output | Port widths                                  |
| ----- | --------------------------- | ------ | -------------------------------------------- |
| `rom` | `addr`                      | `out`  | `addr` is `A` wide; `out` is `W` wide        |
| `ram` | `addr`, `din`, `we`, `clk`  | `out`  | `addr` is `A`, `din`/`out` are `W`, `we`/`clk` are 1 |

`W` must be in `1..64` and `A` in `1..16` (`E018`); a declaration with any
other number of width arguments, or with a width written after the keyword
(`rom[8] m[8, 4]`), is `E017`. Inside a parametric sub-circuit, the arguments
may name introduced parameters (`ram m[W, A](...)`). Every listed input port is
required (`E004`), and ports are checked at their own widths (`E014`). A
`ram` breaks combinational loops; a `rom` does not (`E008`). `rom` and
`ram` are reserved: an instance or input named `rom` is `E006`, and
`import rom "..."` is `E011`.

Memory contents never appear in source; the host loads them at runtime (or
`--sim` does). This section is only the declaration shape; the read and
write semantics, the X rules, the edge rule, and how contents get in are in
§6.5.

---

## 4. Signals and Wiring

A *signal* is whatever you place on the right-hand side of a port binding. It
identifies the source of the bit(s) that drive the port. Signals come in six
forms:

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

**Bit index (`name[i]` or `name.port[i]`).** Picks a single bit out of a
multi-bit signal:

```
input[4] bus
and g(a = bus[0], b = bus[3])    // bit 0 AND bit 3
```

Bit 0 is the LSB. The result is a width-1 signal.

**Slice (`name[lo..hi]` or `name.port[lo..hi]`).** Picks a contiguous range of
bits, half-open:

```
input[8] bus
and[4] low_half(a = bus[0..4], b = some_other_4bit_signal)
```

`bus[0..4]` covers bits 0, 1, 2, 3 — a 4-bit signal. The width of a slice is
`hi - lo`. An out-of-range or inverted slice is `E002`.

**Concatenation (`{low, high, ...}`).** Joins one or more signals into a wider
one, low-on-left:

```
input a, b, c, d
input[4] mask
and[4] combine(a = {a, b, c, d}, b = mask)
// bits: [0]=a, [1]=b, [2]=c, [3]=d
```

The output width is the sum of operand widths.

**Anonymous nested components.** You may instantiate a component inline as the
value of a port. The nested instance has no name; its `.out` is wired
immediately into the enclosing port:

```
and g(
    a = pin1,
    b = not(in = pin2).out
)
```

Anonymous nesting may nest arbitrarily deep. It is pure syntactic sugar:
the resolver lowers it to an unnamed component instance with the same wiring
rules as a named one. Any component's port binding (`and`, `not`, `wire`,
`led`, a macro, a sub-circuit) accepts it; an `output` declaration does
**not**: `output o(in = and(a = a, b = b).out)` loses the nested gate's
bindings and fails with `E004`. When an output needs one, name the gate or
route it through a `wire`.

### 4.1 Validation Rules

The compiler enforces a small set of rules on the resulting graph; violations
produce diagnostics with stable codes (`E001`–`E018`, `W001`–`W003`; the
catalogue with each code's message is in `circuit-format.md` "Diagnostic
Codes", the registry in `lib/validator/codes.zig`):

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
* Connection widths must agree on both ends. A connection from a width-4
  source to a width-8 destination is `E014` (width mismatch).
* Passing `[N]` widths to a scalar (non-parametric) sub-circuit is `E015`; the
  diagnostic suggests adding `<W>` to the callee.
* Parametric arity mismatch (caller writes `[N, M]` but the callee declares
  one parameter, or vice versa) is `E016`.
* A memory declaration must carry exactly two width arguments `[W, A]`
  (`E017`) with `W` in `1..64` and `A` in `1..16` (`E018`); see §6.5.

---

## 5. Wires

A `wire` is a one-port pass-through component. Its single input port is `in`,
and its single output port is `out`; the value on `out` is, after evaluation,
identical to the value on `in`. Wires are the closest thing the language has
to a "let" binding for signals.

### 5.1 What wires are for

Wires exist for two reasons.

**(a) Naming an intermediate signal.** A bare `pin1.out` carries no
documentation. Threading it through a `wire` lets you give the bit a
descriptive name without changing the circuit's logical behaviour:

```
input clk
wire clock_buf(in = clk)
and  g(a = clock_buf.out, b = data.out)
```

This is purely a readability device. The compiler does not optimise wires
away in the topology section, so the named signal survives into runtime
introspection.

**(b) Anchoring a signal used more than once.** Inline anonymous components
have no name, so you cannot re-use them; if the same derived signal feeds two
ports, you need a named anchor for it. A `wire` is the lightest anchor
available:

```
input a
wire na(in = not(in = a).out)     // 'na' = NOT a, named once
and  g1(a = na.out, b = b1)
and  g2(a = na.out, b = b2)
```

### 5.2 Wires and cycles

Wires are *transparent* to cycle detection: a cycle that runs only through
`wire`, `led`, `output`, `slice`, `concat`, `rom`, and sub-circuit boundaries
has no delay element and is a hard error (`E008`), as is any component
driving itself. A pair of wires that drive each other's `in` is the simplest
case:

```
// E008_wire_loop.circ — rejected at compile time
wire w1(in = w2.out)
wire w2(in = w1.out)
```

`and`, `not`, and `ram` are *cycle-breaking*: a loop that passes through one
of them is sequential logic (a latch), not a combinational loop, and the
validator accepts it. The fixture `clean_gated_feedback.circ` is a ring of two NOT gates
and two wires — a genuine cycle in the signal graph — and compiles cleanly
because the NOT gates break it:

```
not  n1(in = w2.out)   // n1 is fed from w2
wire w1(in = n1.out)
not  n2(in = w1.out)
wire w2(in = n2.out)   // closes the ring; legal because it passes through gates
```

The check says nothing about whether such a ring settles: a ring with an odd
number of inverters compiles and oscillates at run time.

(This snippet forward-references `w2.out`; the validator resolves names
globally, so order in source is irrelevant for binding.)

### 5.3 Multi-bit wires

A `wire` also takes the `[N]` annotation when it carries a multi-bit signal:

```
input[4] bus
wire[4] buffered_bus(in = bus)
and[4] g(a = buffered_bus.out, b = some_4bit_signal)
```

The wire's input width must match the source's output width, and its output
width is the same `N`. Mismatches surface as `E014`.

### 5.4 What wires are *not*

A `wire` is not a tri-state line and not a clocked register. It is a
value-preserving pass-through over a fixed-width signal. If you need either
one, the language does not yet model it.

---

## 6. Multi-bit Wires

`circ` programs may carry signals wider than one bit. Every signal-carrying
declaration accepts an optional `[N]` annotation; a missing `[N]` means width
1. Sub-circuits may take their widths as parameters with the `<W>` form. The
authoritative decision record lives in
[`decisions/language.md`](decisions/language.md); this section is the
user-facing reference.

### 6.1 Literal widths

The simplest form annotates a fixed width on a declaration:

```
input[4] a, b
and[4] g(a = a, b = b)
output[4] r(in = g.out)
```

`a`, `b`, the `and` gate `g`, and the output `r` are all width-4. The
validator checks that every connection's source width matches its destination
width.

`a[0]` is the LSB. Bit `i` has weight `2^i`. This matches the
`BitVecState.value` bit layout the engine uses internally; the user-visible
numbering and the runtime numbering need no conversion.

### 6.2 Slice, bit-index, and concatenation

See §4 for the signal-expression syntax. A slice or bit-index produces a
narrower signal; a brace concat produces a wider one. The resolver lowers
each to an engine-level component, so users never write `slice(...)` or
`concat(...)` directly; the syntactic forms are the only way to invoke
them.

```
input[8] bus
and[4] g(a = bus[0..4], b = bus[4..8])   // AND the two halves
and    bit_eq(a = bus[0], b = bus[7])    // compare LSB to MSB

input a, b
input[2] tail
output[4] out(in = {a, b, tail})         // out = a | (b << 1) | (tail << 2)
```

### 6.3 Parametric sub-circuits

A sub-circuit becomes parametric by introducing parameters with `<W>` on its
`input` declarations. Use sites inside the file reference the parameter as
`[W]`:

```
// wide_not.circ
input<W>[W] a
not[W] inv(in = a)
output[W] o(in = inv.out)
```

Callers bind widths positionally with `name[N, ...]` at the instance name:

```
import wide_not "wide_not.circ"

input[4] x
wide_not inst[4](a = x)
output[4] r(in = inst.o)
```

A file may introduce several parameters, ordered by the source position of
first introduction:

```
// mux_lib.circ
input<W>[W] data
input<S>[S] select
// ... body uses [W] and [S] independently
```

The caller binds positionally: `mux inst[4, 2](data = ..., select = ...)`
maps `[W]` to 4 and `[S]` to 2.

Two rules to remember:

* **Missing `[N]` at the call site defaults all parameters to 1.** This keeps
  every existing scalar caller of the built-in macros working unchanged.
* **Angle brackets only on the introducing line.** A parametric sub-circuit
  marks its parameter once, on `input<W>`. Internal references use `[W]`,
  not `<W>`.

Width-mismatch on connections involving a sub-circuit boundary, missing
`<W>` introductions, and arity mismatches at call sites surface as `E014`,
`E015`, and `E016` respectively.

### 6.4 The built-in macros are parametric

`or`, `xor`, `nand`, `nor`, and `xnor` ship with `<W>` declarations. Scalar
callers (no `[N]`) default `W` to 1, which produces byte-identical IR and
topology to the pre-multibit form. Wider callers get the natural multi-bit
gate. `nor` and `xnor` propagate width through their internal `or` / `xor`
calls.

```
input[8] x, y
nor n[8](a = x, b = y)         // bitwise NOR across all 8 bits
output[8] z(in = n.out)
```

Pass the width of a macro or sub-circuit instance in *instance* position, as
call-widths (`n[8]`), exactly as for a user sub-circuit (§6.3). A `[N]` in
*type* position (`nor[8] n(...)`) sizes only primitives; on a macro it leaves
the callee at width 1, and the call fails with `E014`.

### 6.5 Memories (`rom`/`ram`)

Memories are the first primitives whose instance takes *two* width
parameters: `[W, A]` is the same `CallWidths` list a parametric sub-circuit
call takes (§6.3), read as the data width `W` and the address width `A`. A
memory therefore holds `2^A` words of `W` bits. The declaration shape is in
§3.5; this section is the reference for what a memory *does*.

```
input[4] pc
rom code[8, 4](addr = pc)                       // 16 words × 8 bits
output[8] instr(in = code.out)

input[4] a
input[8] d
input w, clk
ram data[8, 4](addr = a, din = d, we = w, clk = clk)
output[8] q(in = data.out)
```

**Ports.**

| Type  | Port   | Direction | Width | Meaning                                              |
| ----- | ------ | --------- | ----- | ---------------------------------------------------- |
| both  | `addr` | input     | `A`   | the address whose word appears on `out`              |
| both  | `out`  | output    | `W`   | the word at `addr` (asynchronous read)               |
| `ram` | `din`  | input     | `W`   | the word to write                                    |
| `ram` | `we`   | input     | 1     | write enable                                         |
| `ram` | `clk`  | input     | 1     | the clock; a write happens on its rising edge        |

Every input port is required (`E004`) and is checked at the width in the
table (`E014`); a port name outside the table is `E002`. `W` must be in
`1..64` and `A` in `1..16` (`E018`).

**Reading.** Both kinds read asynchronously: `out` is always the word stored
at the presented `addr`, and it follows every address change without a clock,
exactly like any other combinational output. A cell that has never been
loaded or written reads fully undefined. If *any* bit of `addr` is undefined,
`out` is fully undefined; the memory never does a partial lookup.

**Writing (`ram` only).** A `ram` writes `din` into the cell at `addr` on a
*defined low → defined high* transition of `clk`, and only if `we` is
defined-high and every bit of `addr` is defined at that moment. The clock's
previous level must have been a defined `0`: the very first `set clk 1` (or
`setPin(clk, 1n, 1n)`) after power-on is *not* an edge, because the previous
level was undefined. A circuit can therefore never write on its way out of
the all-undefined initial state. The `ram` stores `din` as presented, bit for
bit, including its definedness; a partially undefined `din` writes a
partially undefined cell. `clk` and `we` are ordinary width-1 inputs; the
language has no clock primitive. From a host you pulse the clock by driving
it low and then high; from `--sim` that is `set clk 0` then `set clk 1`.

**Contents come from the host.** Source never carries an image. A memory is
filled at run time through one of three doors, all taking the same headerless
raw image — `ceil(W/8)` little-endian bytes per word, at most `2^A` words,
padding bits clear (see `wasm-api.md` "Image format"):

* a compiled artifact's `getMemInfo` / `memBuffer` / `memLoad` / `memStore` /
  `memClear` / `setMemWord` / `getMemValue` / `getMemDefined` exports
  (`wasm-api.md`);
* `--sim` and `--truth-table` with `--mem=<name>=<path>` on the command line;
* `--sim`'s `load`, `save`, `peek`, `poke`, `mem`, and `clear` verbs
  (`sim-protocol.md`).

Loading is *replace-all*: a shorter image leaves the remaining cells
undefined; an empty image clears the memory.

**Loops.** For `E008`, a `ram` behaves like a gate: a path through it does
not form a combinational loop, so feeding `q` back into `d` or `a` is legal.
A `rom`, by contrast, is transparent, so `rom` `out → addr` with nothing in
between is an `E008` cycle (§5.2).

**Parametric memories.** Inside a `<W, A>` sub-circuit, the width arguments
may name the introduced parameters, and callers bind them positionally like
any other parametric call:

```
input<A>[A] addr
input<W>[W] din
input we, clk
ram m[W, A](addr = addr, din = din, we = we, clk = clk)
output[W] q(in = m.out)
```

**Tooling.** `--truth-table` tabulates a circuit whose memories are all `rom`
(preload them with `--mem`; unloaded cells print `?`) and refuses one that
contains a `ram`, whose clock it would otherwise enumerate as an input.
Drive those with `--sim`. `--preview` draws a `rom` as a one-input box and a
`ram` as a four-input box. `--emit-zig` does not support memories.

---

## 7. A Worked Example

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

// The carry bit, named so both an output and the gate below can read it.
and carry_gate(a = a, b = b)

// First fan-out: feed the sum into a NOT gate inline (an anonymous nested
// component). Second fan-out: drive the 'sum' output pin from the same wire.
and busy_gate(
    a = not(in = sum_w.out).out,
    b = carry_gate.out
)

output sum  (in = sum_w.out)
output carry(in = carry_gate.out)
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

## 8. Where to Go Next

* [`getting-started.md`](getting-started.md) — install the compiler, write your
  first circuit, drive it from Node.
* [`circuit-format.md`](circuit-format.md) — the original tutorial-flavored
  walkthrough of the format, with the full diagnostic-code catalogue.
* [`wasm-api.md`](wasm-api.md) — the runtime API exposed by every compiled
  `.wasm` artifact.
* [`preview.md`](preview.md) — `--preview`, `--expand-macros`, and the
  conventions used when rendering circuits as ASCII.
