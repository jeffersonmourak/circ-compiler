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

### Import statement: `import name from "./file.circ"`

**Decision.** Sub-circuit imports use the form `import <alias> from "./<path>.circ"`. The alias becomes the gate-kind identifier in the importing file. Paths are resolved relative to the importing file. Built-in gates (`and`, `or`, `nand`, ...) require no import and live in a global namespace.

**Rationale.** The explicit-alias form mirrors JavaScript and Python and gives users a way to rename on import to resolve collisions. Relative paths make `.circ` files portable as a directory tree. A built-in global namespace means simple circuits don't pay an import-statement tax for `and` and `not`.

**Alternatives.** Implicit naming (`import "./half_adder.circ"` exposes `half_adder`) is shorter but offers no rename escape hatch. Multi-export brace form (`import { a, b } from "./file.circ"`) is more flexible but premature — the v0 model is one sub-circuit per file.

### No circular imports

**Decision.** Circular import chains are a hard error detected at compile time. The compiler reports the cycle and refuses to emit any artifact.

**Rationale.** A cycle in module imports has no defined semantics in this language — sub-circuits expand into their parents at instantiation, which can't terminate if the chain loops. Detecting it at compile time is cheap (a topological sort during resolution) and avoids any runtime mystery.

**Alternatives.** Allowing cycles with some tie-breaking rule. No use case justifies the complexity, and any meaningful "feedback" between modules belongs inside a single sub-circuit using actual feedback connections, not import cycles.

### LEDs and `output` declarations are different concepts

**Decision.** LEDs are visualisation primitives — they sink a signal and expose it for rendering, but they are not part of a sub-circuit's external interface. `output` declarations define the named ports a sub-circuit exposes to its parent. The compiler's `getFileInfo()` lists them in separate categories: `outputs` for declared output ports, `leds` for LED instances.

**Rationale.** Conflating the two would mean every sub-circuit author has to choose between "this is for display" and "this is for the parent", or worse, every LED becomes implicitly part of the public interface. Keeping them separate lets a sub-circuit have internal LEDs (debug indicators) without polluting its external contract, and lets the top-level circuit have outputs without forcing a visual element.

**Alternatives.** A single "sink" concept covering both. Simpler vocabulary, but loses the distinction between rendering and interface that consumers actually care about.
