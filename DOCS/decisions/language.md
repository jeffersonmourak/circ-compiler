# Language Semantics

The surface syntax of `.circ` is documented in [../circuit-format.md](../circuit-format.md). This file captures the semantic decisions that shape how the compiler interprets and lowers that syntax.

### Sub-circuits compile to Zig functions

**Decision.** Each `.circ` file emits one Zig function (`buildXxx(circuit, inputs...) → outputs`) that constructs its internal components and connections by calling the engine API. Each instantiation of a sub-circuit in a parent file becomes a call site of that function, with parent components passed as arguments.

**Rationale.** A function-per-file IR is the smallest unit that maps cleanly onto the source — one source file, one emitted symbol. Calls flatten at runtime so the engine only ever sees primitives, which keeps the engine simple and lets the Zig compiler decide whether to inline. Component IDs are fresh per call, so multiple instances of the same sub-circuit don't collide.

**Alternatives.** One function per *instance* (specialised emission). Bigger artifact, no semantic gain — Zig's inliner achieves the same end result from the function-per-file form when it pays off.

### Source-path debug info lives outside the engine

**Decision.** The hierarchical source path of each component (e.g. `["full_adder", "h1", "s"]`) is stored in a parallel debug-info table emitted by the compiler, exposed via `getTopology()`. The engine's `Component` struct carries no source-path field.

**Rationale.** Hierarchy is a property of the source language, not the simulation. Putting source paths on every `Component` would force the dynamic API in `lib/wasm.zig` (and any future engine consumer) to carry a field they have no information for. Keeping it parallel means the engine stays clean and only compiled artifacts pay for hierarchy debug info.

**Alternatives.** Embedding source paths in `Component`. Slightly faster lookup during introspection at the cost of polluting the engine's data model and burdening every engine user with a field most don't populate.

### Built-in primitives kept minimal

**Decision.** The engine implements only the primitives it needs: `input_pin`, `output_pin`, `not`, `and`, `led`, `wire`. Standard logic gates beyond this set (`or`, `nand`, `nor`, `xor`, `xnor`) are provided by the compiler as built-in macro sub-circuits, expanded at compile time using the existing primitives (e.g. `nand = not(and(a, b))`).

**Rationale.** The smaller the primitive set, the less the engine has to maintain and verify. Any gate expressible in terms of `and`/`not` doesn't need to live in the engine. Users still get the full standard library on day one because the compiler ships these expansions as built-ins. If profiling shows a particular composite is hot enough to deserve a primitive, it can be promoted later without changing user-facing semantics.

**Alternatives.** Implementing the full standard set as engine primitives. Higher engine surface, more test obligations, and circuit-equivalent results. Or restricting the surface language to engine primitives only — leaks the implementation detail into user code.

### Import statement: `import name "path"`

**Decision.** Sub-circuit imports use the form `import <alias> "<path>"`. The alias becomes the gate-kind identifier in the importing file. Paths are resolved relative to the importing file. Built-in gates (`and`, `not`, `wire`, `led`, `output`, `input`) require no import and live in a global namespace; the auto-imported macro family (`or`, `nand`, `nor`, `xor`, `xnor`) is materialised under the virtual `<builtin>/<name>.circ` path and is treated as if `import <name> "<builtin>/<name>.circ"` were written when the file participates in a project.

**Rationale.** The explicit-alias form gives users a way to rename on import to resolve collisions. Relative paths make `.circ` files portable as a directory tree. A built-in global namespace means simple circuits don't pay an import-statement tax for `and` and `not`. The earlier draft of this decision included a `from` keyword (`import name from "path"`); the keyword was dropped from the grammar because the trailing string already unambiguously identifies the import path, and shaving a keyword keeps the surface lean.

**Alternatives.** Implicit naming (`import "./half_adder.circ"` exposes `half_adder`) is shorter but offers no rename escape hatch. Multi-export brace form (`import { a, b } from "./file.circ"`) is more flexible but premature — the model is one sub-circuit per file.

### No circular imports

**Decision.** Circular import chains are a hard error detected at compile time. The compiler reports the cycle and refuses to emit any artifact.

**Rationale.** A cycle in module imports has no defined semantics in this language — sub-circuits expand into their parents at instantiation, which can't terminate if the chain loops. Detecting it at compile time is cheap (a topological sort during resolution) and avoids any runtime mystery.

**Alternatives.** Allowing cycles with some tie-breaking rule. No use case justifies the complexity, and any meaningful "feedback" between modules belongs inside a single sub-circuit using actual feedback connections, not import cycles.

### LEDs and `output` declarations are different concepts

**Decision.** LEDs are visualisation primitives — they sink a signal and expose it for rendering, but they are not part of a sub-circuit's external interface. `output` declarations define the named ports a sub-circuit exposes to its parent. The compiler's `getFileInfo()` lists them in separate categories: `outputs` for declared output ports, `leds` for LED instances.

**Rationale.** Conflating the two would mean every sub-circuit author has to choose between "this is for display" and "this is for the parent", or worse, every LED becomes implicitly part of the public interface. Keeping them separate lets a sub-circuit have internal LEDs (debug indicators) without polluting its external contract, and lets the top-level circuit have outputs without forcing a visual element.

**Alternatives.** A single "sink" concept covering both. Simpler vocabulary, but loses the distinction between rendering and interface that consumers actually care about.

---

## Multi-bit wires

The 17 decisions below were locked during the multi-bit wires initiative (stages S1–S12). The full historical plan with rationale and stage ordering moved to `DOCS/archive/plan-multi-bit-language.md` after S12 closed; that file is the place to read for *why* each decision shaped the way it did.

### 1. Width annotation syntax

**Decision.** A width is declared with `[N]` after the type keyword: `input[4] a, b`, `and[4] g(...)`, `output[4] r(in=...)`. A missing `[N]` means width 1.

**Rationale.** Postfix annotation keeps existing scalar `.circ` files legal as-is, which is the load-bearing property — the validator's job becomes a single equality check per connection and no caller has to be touched when a sub-circuit goes multi-bit.

### 2. Bit numbering

**Decision.** `a[0]` is the LSB; bit `i` carries weight `2^i`.

**Rationale.** Matches `BitVecState.value`'s bit layout exactly, so the topology format, the engine, and the language all agree byte-for-byte.

### 3. Slice notation

**Decision.** `a[lo..hi]` is half-open. `a[0..4]` covers bits 0, 1, 2, 3 — four bits.

**Alternatives.** Closed-range (`a[0..3]` covers four bits) is mathematically equivalent but every empty/identity case ends in an off-by-one trap. Half-open keeps `hi - lo == width`.

### 4. Concatenation

**Decision.** `{low, high}` with braces, low-on-left ordering. `{a, b}` produces a width `a.width + b.width` value where bits `[0, a.width)` come from `a` and bits `[a.width, ...)` come from `b`.

**Rationale.** Low-on-left lines up with how `BitVecState.value` is stored (LSB at bit 0) and how slice notation places the lower bound on the left. A Verilog-flavoured high-on-left ordering was rejected because it forces every shape transformation to mentally reverse the operand list.

### 5. Sub-circuit parametricity

**Decision.** A sub-circuit becomes parametric by introducing parameters with `<Identifier>` on its `input` declarations. Use sites inside the file write `[Identifier]`. Callers bind via `name[N, M, ...]` positionally at the instance name.

### 6. `<W>` versus `[W]`

**Decision.** Angle brackets are the *introduction* form (declares a parameter). Square brackets are the *reference* form (an integer literal or a previously-introduced parameter name).

**Rationale.** Visually different brackets make it immediately obvious whether you're looking at a declaration or a use. The compiler can also produce better diagnostics: `[W]` without a corresponding `<W>` triggers `E015`, and the suggestion can point at the exact spelling change.

### 7. Where parameters can appear

**Decision.** Width annotations only. Parameters never appear inside slice bounds, indices, arithmetic, or anywhere else.

**Rationale.** Keeping parameters to declaration positions only means the resolver can do all specialization with a tree rewrite at one fixed place (`Identifier.width` and `ComponentInstance.width_args`). Allowing parameters inside `a[W..W+4]` would require an arithmetic-evaluation pass and pull resolver complexity sideways for marginal gain.

### 8. `[N]` on a scalar sub-circuit

**Decision.** Compile error `E015`. The diagnostic suggests adding `<W>` to the sub-circuit.

### 9. Multiple parameters

**Decision.** Allowed. Positional at call sites; ordered by the position of first introduction in the source file.

**Rationale.** Positional binding matches every other language's convention for parameterised types and avoids the readability cost of keyword arguments at every call site. Source-order-of-introduction is the only ordering that's both well-defined and visible to the reader; declaration order in `<W, X>` may differ from reference order in the body, and the introducer wins.

### 10. Missing `[N]` at call site

**Decision.** Defaults all parameters to 1.

**Rationale.** This is the entire reason every existing scalar caller of the built-in macros kept working after S8 rewrote them as parametric. Without this rule, S8 would have been a breaking change for every `.circ` file in the world.

### 11. `<W>` discipline

**Decision.** A parametric sub-circuit always declares its parameter in angle brackets on the introducing `input` line, never elided or implicit.

**Rationale.** Two reasons to read a `.circ` file: understand its logic and understand its interface. Hiding parametricity would force the reader to infer it from internal usages. The `<W>` mark is small, visible, and unambiguous.

### 12. LED at width > 1

**Decision.** Default `--preview` rendering is a single hex numeric display (`0x?` for fully undefined). With `--expand-display` and `N < 8`, render `N` indicator glyphs (LSB on the left). At `N >= 8` with `--expand-display`, fall back to numeric and emit one stderr warning per offending LED.

**Rationale.** Indicator rows wider than 7 don't fit comfortably in a typical terminal; the cap is a UX call, not a technical one. The warning is non-fatal so the user still gets a render and can re-run without the flag.

### 13. Truth table

**Decision.** One column per pin; multi-bit values rendered per format flag. `--truth-table-format binary|hex|decimal` (default binary). Hard cap at 16 total input bits across all inputs; `--truth-table-cap` overrides up to 24.

**Rationale.** `2^16 = 65,536` rows is the practical ceiling for a glance-readable truth table; pushing past 24 (16 M rows) is almost never what the user wanted, so the override is opt-in.

### 14. WASM host API

**Decision.** Three exports per pin:

- `setPin(id: i32, value: i64, defined: i64) -> void`
- `getOutputValue(id: i32) -> i64`
- `getOutputDefined(id: i32) -> i64`

The two i64 fields are read by JS as `BigInt`. The full rationale (paired exports vs. a single out-pointer call) lives in `DOCS/wasm-api.md`.

### 15. Macro migration

**Decision.** The five built-in macros (`or`, `xor`, `nand`, `nor`, `xnor`) are written with `<W>` annotations. `nor` and `xnor` propagate width through their internal `or` / `xor` calls (`or inner[W]`, `xor inner[W]`).

**Rationale.** Decision #10 is what makes this safe: scalar callers default `W` to 1 and get byte-identical IR and topology. Bench's `golden matches` invariant tracks this empirically.

### 16. Signal-expression composition

**Decision.** A signal source on the right-hand side of a port binding is one of:

- a bare name (`a`)
- `name.port`
- `name[i]` or `name[lo..hi]`
- `name.port[i]` or `name.port[lo..hi]`
- an anonymous component instance (`not(in = a).out`)
- a brace concat (`{ ... }`) containing any of the above

### 17. Topology format version

**Decision.** Bumped from `0x01` (pre-multibit) to `0x02`. Both `ComponentRecord` (min) and `FullComponentRecord` (full) carry a `width: u8` byte per component. Slice records carry auxiliary `(lo, hi)` bytes in the min section. Concat records carry their operand list in the full section's auxiliary slot.

See `DOCS/circuit-format.md` for the exact byte layout.

---

## Native memories

The entries below record the language-facing half of the native-memory initiative (`rom`/`ram`, topology v03). The numbered decisions they cite are the eleven locked in the memories plan prompt, archived at `DOCS/archive/plan-memories.md` and readable in full at `git show 2e15e97b973d822373d2b078dd0261fc3974b989:DOCS/PLANS_PROMPT.md`; the runtime and tooling half lives in [runtime-api.md](runtime-api.md) `## Native memories`, and the `--mem` flag gating in [cli.md](cli.md). Reference semantics for users are in `DOCS/language.md` §6.5.

### Memory declarations reuse `CallWidths` and reserve two type names

**Decision.** A memory is declared with the existing instance syntax and exactly two width arguments in instance position: `rom code[8, 4](addr = pc)`, `ram data[8, 4](addr = a, din = d, we = w, clk = clk)`. `[W, A]` is the same `CallWidths` list a parametric sub-circuit call takes, read as data width and address width, so `rom m[W, A]` inside a `<W, A>` sub-circuit binds through `widthFromSpec` for free. `rom` and `ram` are reserved type names: they resolve before import aliases, a sub-circuit file may not shadow them (`E006`), and an import may not alias them (`E011`). The grammar (`lib/grammar/proto-circ.peg`) is unchanged.

**Rationale.** Decision 1's premise was that the front door should cost nothing at the parser: `CallWidths` already parses a comma-separated width list, and the resolver already turns `width_args` into bound widths for parametric calls. Reusing both means memories inherit parametric binding, the `--inspect`/`--analyze` plumbing, and every existing width diagnostic instead of introducing a second declaration form. Reserving the names keeps `rom`/`ram` unambiguous in every file — a user sub-circuit named `rom` would otherwise silently win or lose depending on import order.

**Alternatives.** A dedicated `memory` keyword with named parameters (`rom code(width = 8, depth = 16)`) — clearer to read but a grammar change, a new AST node, and a second width-binding path. Treating memories as built-in macro sub-circuits — a 256×8 RAM would flatten to tens of thousands of primitives in the topology, which is the reason "native" was chosen at all.

### Memory contents are runtime configuration, never source

**Decision.** A declaration carries only the memory's shape. Contents are supplied at run time: by the host through the WASM memory exports, by `--sim`/`--truth-table` through `--mem=<name>=<path>`, or interactively through `--sim`'s `load`/`poke`. Unloaded and unwritten cells read undefined. No `.circ` syntax embeds an initial image, and the topology sections never carry cell contents.

**Rationale.** This is the principle behind decisions 2, 3, 4 and 7. A compiled artifact is then a *machine*, not a machine plus one program: the same `cpu.wasm` runs every program a host loads into it, a teaching deck can swap the ROM between slides without recompiling, and a `.circ` file stays a readable description of wiring rather than a hex dump. It also keeps the wire format small and the `.wasm` reproducible from source alone.

**Alternatives.** An in-source image (`rom code[8, 4] = "prog.hex"` or an inline hex literal) was the first draft and was superseded: it couples a circuit to one program, needs a file-resolution rule in the resolver, and would have to travel in the topology. An optional in-source default image on top of runtime loading was rejected as two mechanisms for one job.

### ROM is combinational; RAM writes on a defined rising edge

**Decision.** Both kinds read asynchronously: `out` is the word at the presented `addr` and follows every address change without a clock. A `ram` writes `din` into the addressed cell when `clk` transitions from *defined low* to *defined high* while `we` is defined high and every `addr` bit is defined; `prev_clk` is stored before the write is evaluated, so the same edge is never counted twice and a `din` change on the same step is captured. `din` is stored masked to `W` with its definedness preserved (a partially undefined `din` writes a partially undefined cell). Any undefined `addr` bit makes `out` fully undefined. `clk` and `we` are ordinary width-1 inputs read with a width-agnostic bit test.

**Rationale.** Decision 5. Async read plus clocked write is the Logisim default model and the one students meet first; a synchronous read port would have doubled the state and made "peek at an address" a two-step dance. Requiring the low side of the edge to be *defined* means the first `set clk 1` after power-on is not an edge — the circuit cannot write on the way out of the all-undefined initial state — which keeps `init()`'s "nothing has happened yet" promise (see runtime-api.md). Storing `prev_clk` before acting makes the write idempotent under re-evaluation, which the engine's event loop relies on.

**Alternatives.** Level-triggered writes (write whenever `we` is high) — simpler, but any glitch on `din` corrupts the cell and the timing model becomes "whatever settles last". Treating `X → 1` as a rising edge — matches some simulators, but it makes power-on behaviour depend on evaluation order. A synchronous-read RAM was deferred; it can be built from this one plus a register once the language has one.

### `ram` breaks combinational loops, `rom` does not

**Decision.** In the `E008` combinational-loop pass, `ram` belongs to the same cycle-breaking class as `and`/`not` (a path through a `ram` does not form a loop); `rom` stays transparent, so a `rom` whose `out` feeds back into its own `addr` is `E008`.

**Rationale.** Decision 6. The pass is component-granular (it does not distinguish ports), so each kind must be classified whole. A `ram` holds state and its write side is clocked, so feedback through it is the normal shape of a register file or a counter's memory — the way an `and`-based latch already passes today. A `rom` is a pure lookup table: `addr → out → addr` with no clock is a genuine combinational loop and would spin the engine exactly as a wire loop does.

**Alternatives.** Making the pass port-aware (a `ram` read path `addr → out` is combinational, the write path is not) would be more precise but is a rewrite of the pass for a distinction no current fixture needs. Marking `rom` cycle-breaking too was rejected: it hides a real oscillation.

### `E017`/`E018` plus reused codes through one port-width helper

**Decision.** Two new codes: `E017` "memory parameter list malformed" for any memory declaration without exactly two width arguments in instance position (`rom m(…)`, `rom m[8](…)`, `rom m[8, 4, 2](…)`, the identifier-list form `rom a, b`, a type-position width `rom[8] m[8, 4]`), with a message that shows the correct shape; `E018` "memory width out of range" for `W ∉ 1..64` or `A ∉ 1..16`. Everything else reuses existing codes through one helper, `memoryPortWidth(mem, port)` (`addr → A`, `din`/`out` → `W`, `we`/`clk` → 1): `E002` for an unknown port, `E004` for a missing required input, `E014` for a width mismatch on any memory port. The helper returns nothing when the argument count is wrong so `E017` never cascades into spurious width errors.

**Rationale.** Decision 11. Diagnostic codes are append-only, so the new ones had to be genuinely new *kinds* of mistake; a wrong port name or a mismatched width on a memory is the same mistake as on a gate and should read the same to a user and to `circ-lsp`. Centralising the per-port width in one function is what let `E002`/`E004`/`E014` gain memory arms without each pass learning the port table separately.

**Alternatives.** One umbrella "invalid memory declaration" code — fewer codes but loses the shape/range distinction that decides the fix. Per-port codes (`E019` bad `we` width, …) — more precise, but the validator already expresses all of them, and each new code is a permanent surface.
