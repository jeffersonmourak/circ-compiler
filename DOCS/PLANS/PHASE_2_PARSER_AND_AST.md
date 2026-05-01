# Phase 2 — Parser & AST/IR

## Goal

Wire the langlang-generated C parser into a typed Zig AST, then run a separate resolution pass that lowers the AST into a resolved IR. After this phase, given a `.circ` source file the compiler can produce:

1. A typed AST (close to syntax — what was written).
2. A resolved IR (what it means — names resolved, references typed).

These two structures are the inputs to every later phase. The validator (Phase 3) and the emitter (Phase 4) consume the resolved IR; the AST is retained for diagnostic spans and `--inspect` output.

This phase does *not* validate semantics beyond what's needed to build the IR (e.g. resolving a name to find its definition is in scope; reporting "undeclared name" as a diagnostic is Phase 3's job — Phase 2 marks the reference as unresolved and moves on).

## Scope

In scope:

- AST types under `lib/syntax/ast/` (or equivalent): one Zig type per syntactic construct (`File`, `Import`, `InputDecl`, `OutputDecl`, `ComponentInstance`, `PortConnection`, `SignalRef`, `AnonymousComponent`, etc.). Tagged unions where multiple shapes share a position.
- Every AST node carries a `Span { file_id, start_line, start_col, end_line, end_col }` field. The parser populates spans from the langlang parse tree's position information.
- A parse-tree-to-AST translator that consumes the langlang C parser's output and produces the typed AST. Replaces the WIP code in `lib/syntax/translate.zig` and `lib/syntax/nodes/declaration.zig`.
- A resolved IR under `lib/ir/` (or equivalent): name-resolved, port-resolved, with references represented as typed pointers/IDs into the IR's own structure.
- A resolution pass that takes an AST and produces the IR. Resolution is *single-file* in this phase — multi-file/import support lands in Phase 7.
- Tests covering both layers: parser fixtures (`.circ` → AST golden dump), resolution fixtures (AST → IR golden dump).

Out of scope:

- Semantic validation. Phase 3 owns name-resolution diagnostics, port checks, multi-driver detection, cycle detection. Phase 2's resolver simply leaves unresolved references marked as such; it does not emit diagnostics for them.
- Imports / multi-file resolution. Phase 7 owns this. Any `import` statement encountered in this phase is parsed into the AST but the resolver does not attempt to follow it — it records the import and leaves it unresolved.
- Built-in macro library. Phase 8 owns it. References to `or`, `nand`, etc. are unresolved at this phase's resolver output.
- Source-snippet rendering for diagnostics. Phase 3 will use the spans Phase 2 produces; richer rendering (caret indicators) is deferred per `decisions/validation.md`.

## Architectural anchors recap

- One AST type per syntactic construct (Q5a, decision (i)).
- AST and IR are separate layers (Q5b, decision (ii)). Validator and emitter consume the IR.
- Every node carries a `Span` (Q5c, decision (i)). No node without position info.
- Parser reuses the existing langlang-generated C sources (`lib/parser.c`, `lib/parser.h`) imported via `lib/syntax/CParser.zig`. langlang itself is not invoked in this phase.

## AST shape

The AST mirrors the surface language documented in `DOCS/circuit-format.md`. Sketch:

```
ast.File
    imports:    []ast.Import
    inputs:     []ast.InputDecl
    outputs:    []ast.OutputDecl
    components: []ast.ComponentInstance
    span:       Span

ast.Import
    alias:  ast.Identifier
    path:   ast.StringLiteral
    span:   Span

ast.InputDecl
    names:  []ast.Identifier
    span:   Span

ast.OutputDecl
    name:   ast.Identifier
    value:  ast.SignalSource
    span:   Span

ast.ComponentInstance
    type_name:    ast.Identifier
    instance_name: ?ast.Identifier        # null for anonymous (inline) instances
    ports:        []ast.PortConnection
    span:         Span

ast.PortConnection
    port:   ast.Identifier
    value:  ast.SignalSource
    span:   Span

ast.SignalSource = union {
    named:        ast.NamedSignalRef,     # `name.port`
    anonymous:    ast.ComponentInstance,  # inline component expression
}

ast.NamedSignalRef
    target:  ast.Identifier
    port:    ast.Identifier
    span:    Span

ast.Identifier
    text:   []const u8
    span:   Span

ast.StringLiteral
    text:   []const u8                    # decoded (escape sequences resolved)
    span:   Span
```

Exact field names and module paths can be adjusted at slice time as long as the *shape* (one type per construct, spans on every node, tagged union for `SignalSource`) matches.

## IR shape

The resolved IR represents the same circuit as the AST but with references resolved to indices into the IR's own arrays. Sketch:

```
ir.Module
    file_id:       FileId
    inputs:        []ir.InputPin           # indexed by InputId
    outputs:       []ir.OutputPin          # indexed by OutputId
    components:    []ir.Component          # indexed by ComponentId
    connections:   []ir.Connection
    imports:       []ir.UnresolvedImport   # populated, not resolved (Phase 7)

ir.Component
    id:            ComponentId
    kind:          ir.ComponentKind        # primitive, sub-circuit ref, or unresolved
    instance_name: ?[]const u8
    span:          Span

ir.ComponentKind = union {
    primitive:           PrimitiveKind,    # and, not, led, wire, input_pin, output_pin
    sub_circuit_ref:     UnresolvedRef,    # always unresolved in Phase 2 (deferred to Phase 7)
    unresolved_name:     []const u8,       # name lookup failed; Phase 3 will diagnose
}

ir.Connection
    from:        SignalEndpoint
    to:          PortEndpoint
    span:        Span                      # span of the source-level connection

SignalEndpoint
    component:   ComponentId
    port:        []const u8

PortEndpoint
    component:   ComponentId
    port:        []const u8

ir.InputPin
    id:          InputId
    name:        []const u8
    component:   ComponentId               # the synthesised input_pin component
    span:        Span

ir.OutputPin
    id:          OutputId
    name:        []const u8
    driver:      SignalEndpoint            # what drives this output
    span:        Span

ir.UnresolvedImport
    alias:       []const u8
    path:        []const u8
    span:        Span
```

Anonymous (inline) component instances are flattened during resolution: each gets a fresh `ComponentId`, an auto-generated instance name (e.g. `__anon_0`, `__anon_1`), and is added to the components array. The `SignalSource.anonymous` arm in the AST becomes a `SignalEndpoint` pointing at the synthesised component's `out` port.

## Slices

Each slice is the smallest reviewable unit. Land one slice per session.

### Slice 2.1 — AST types and Span

**What ships.** AST types under `lib/syntax/ast/` (one file or a single module — pick whichever matches existing project style). The `Span` struct lives at `lib/syntax/span.zig` (or co-located with AST types). No translator yet.

**Tests.** A trivial test that constructs an AST node by hand and reads its span, asserting the types compile and the data round-trips. No parser involved.

**Files touched.** `lib/syntax/ast/*.zig`, `lib/syntax/span.zig`.

**Why this slice exists alone.** Locking the AST shape before the translator is built means slice 2.2 has a fixed target. Otherwise the AST and translator co-evolve and the diff is noisy.

### Slice 2.2 — Parse tree → AST translator

**What ships.** A translator that consumes the langlang C parser's output (via `lib/syntax/CParser.zig`) and produces an `ast.File`. Replaces the WIP code in `lib/syntax/translate.zig`. Handles every node kind in the current grammar: `Import`, `InputDecl`, `OutputDecl`, `ComponentInstance`, `PortConnection`, `NamedSignalRef`, anonymous component expressions, identifiers, string literals.

The translator populates `Span` on every node by reading position info from langlang's parse tree. If langlang's position tracking is incomplete for some node types, this is a hard issue to flag — the recurring-traps section commits to "every node has a span," and slice 2.2 is where that commitment is verified.

**Tests.** Golden-file tests using the helper from Phase 0:

- `tests/fixtures/circuits/<name>.circ` is a small input.
- `tests/fixtures/expected-ast/<name>.txt` is the pretty-printed AST dump.

Coverage at minimum:
- Single input pin, single LED, no component (`empty-ish`).
- One AND of two inputs into an LED (the existing `demo_input.circ` shape).
- Anonymous (inline) component nested inside another component's port.
- A file with an `import` statement (parsed, not resolved).
- A file with multiple `output` declarations.
- A pretty-printer for AST dumps (deterministic, stable across runs) lives in the test helpers, not in production code — its only consumer is golden-file tests.

**Files touched.** `lib/syntax/translate.zig` (rewritten), `lib/syntax/nodes/*.zig` (rewritten or replaced), `tests/helpers/ast_dump.zig` (new), `tests/fixtures/circuits/*.circ`, `tests/fixtures/expected-ast/*.txt`.

Note: `tests/fixtures/expected-ast/` is a new fixture directory. Add it to the layout established in Phase 0 (`tests/README.md` may need a one-line update to mention it).

### Slice 2.3 — IR types

**What ships.** IR types under `lib/ir/` per the shape sketched above. `ComponentId`, `InputId`, `OutputId`, `FileId` are simple typed integer wrappers. No resolver yet — just the data structures.

**Tests.** A trivial construction-and-readback test mirroring slice 2.1. The IR exists, you can build one by hand, fields round-trip.

**Files touched.** `lib/ir/*.zig`.

### Slice 2.4 — AST → IR resolver (single-file)

**What ships.** A resolver that walks an `ast.File` and produces an `ir.Module`. Behaviour:

- Each `InputDecl` becomes an `ir.InputPin` with a synthesised `input_pin` component.
- Each `OutputDecl` becomes an `ir.OutputPin` with a synthesised `output_pin` component, and the resolver records the connection from the declared driver into that component's `in` port.
- Each `ComponentInstance` (named or anonymous) becomes an `ir.Component`. Anonymous instances get auto-generated names (`__anon_<n>`).
- Each `PortConnection` becomes an `ir.Connection`.
- Name lookups: a flat scope per file. If a name resolves to a primitive (`and`, `not`, `wire`, `led`, `input_pin`, `output_pin`), the component's kind is `primitive`. If it resolves to an imported alias, the kind is `sub_circuit_ref` left unresolved (Phase 7). If it resolves to nothing, the kind is `unresolved_name` (Phase 3 will diagnose).
- Imports are recorded in `ir.Module.imports` but not followed (Phase 7).

The resolver does *not* report diagnostics. It produces an IR with unresolved markers where Phase 3 will look.

**Tests.** Golden-file tests:

- `tests/fixtures/circuits/<name>.circ` (reusing fixtures from slice 2.2 plus new ones).
- `tests/fixtures/expected-ir/<name>.txt` is the pretty-printed IR dump.

Coverage at minimum:
- Single primitive resolution (input → and → led).
- Anonymous components flatten into named entries with stable `__anon_<n>` names.
- Reference to unknown name produces an `unresolved_name` marker (no diagnostic, just the marker).
- Reference to an imported alias produces a `sub_circuit_ref` marker.
- Output declaration produces an `ir.OutputPin` with a connected synthesised component.

**Files touched.** `lib/ir/resolver.zig`, `tests/helpers/ir_dump.zig` (new), `tests/fixtures/expected-ir/*.txt`.

## Definition of done for Phase 2

- All four slices committed.
- `zig build test` passes.
- Given a single-file `.circ` source, the project can produce a typed AST and a resolved IR. Both have spans on every node.
- The `tests/fixtures/circuits/` directory has enough representative fixtures that Phase 3 can immediately start writing validator tests against them — at least: minimum viable circuit, AND-of-NOT-of-pin, anonymous-nested, multi-input declaration, multi-output declaration.
- The WIP code in `lib/syntax/translate.zig` and `lib/syntax/nodes/declaration.zig` is replaced — no `std.debug.print` debug paths remain in the parser path.

## Open questions to resolve at slice time

- Whether `tests/helpers/ast_dump.zig` and `tests/helpers/ir_dump.zig` produce identical-looking output (both being pretty-printed tree dumps) or differ in style. Recommendation: same format conventions for both, since the same reviewer reads both during PR review.
- The exact pretty-printer format. S-expression-ish (`(File (Import ...) ...)`) vs indented-tree-ish. Pick whichever is easier to diff — indented-tree tends to win because line-oriented diffs are more readable. Once chosen, lock it and don't churn.
- Whether `FileId` is meaningful in single-file mode. Yes — assign `FileId(0)` to the root file. Phase 7 will add more.
- How much of `lib/syntax/helpers.zig` and `lib/syntax/nodes/declaration.zig` survives. Likely none — the new translator is a rewrite. Delete dead code rather than leaving it as "reference."

## Notes for the next phase

Phase 3 (semantic validation) consumes the IR produced here. The presence of `unresolved_name` markers is the contract: Phase 3 walks them and emits `E001 undeclared_name` diagnostics. Similarly, multi-driver detection runs over the connections array; cycle detection runs over the component+connection graph.

Phase 7 (sub-circuit support) will revisit the resolver to handle imports. The single-file resolver written here should be structured so the multi-file pass can reuse name-resolution logic without rewriting it — but do not pre-emptively design for multi-file in this phase. Keep it single-file and clean; let Phase 7 refactor if the seam becomes uncomfortable.
