# Phase 7 — Sub-Circuit Support

## Goal

Lift the compiler from "single-file circuits" to "multi-file circuits with imports." After this phase, a `.circ` file can `import` other `.circ` files as sub-circuits, instantiate them as if they were primitive components, and the compiler resolves the import graph, validates it, and emits one `buildXxx` Zig function per source file.

## Scope

In scope:

- A two-phase resolver under `lib/resolver/` (or extending `lib/ir/resolver.zig`): scan all imports first, then parse bodies in topological order.
- Per-file IR + a separate resolution table mapping `(importing_file, alias) → target_file` (Q10b, decision (ii)).
- Import-cycle detection in the resolver (separate graph from the combinational-loop check).
- File-system import resolution: paths relative to the importing file, hard error on missing files.
- Extension of the validator passes from Phase 3 to handle multi-file IR (sub-circuit refs are now *resolved*, so port checks, required-input checks, multi-driver checks all run across them).
- Extension of the emitter from Phase 4 to emit one `buildXxx` function per imported file, with sub-circuit instances becoming call sites.
- Emission of the `source_path` debug-info table now actually carries hierarchy (e.g. `["full_adder", "h1", "s"]`).
- New diagnostic codes for import-related errors.
- Comprehensive sub-circuit fixtures (Q10d, decision (ii)): two-file, diamond, deep-chain, name-overlap.

Out of scope:

- Built-in macro library. Phase 8. The implicit `<builtin>/` import is added there; Phase 7 only handles user-supplied imports.
- Incremental compilation. The whole-project IR is rebuilt on every compile.
- Versioning or external package management for `.circ` files. Imports are local filesystem paths only.
- Renaming the existing diagnostic codes from Phase 3. New import-related codes start at `E009`.

## Architectural anchors recap

- Each `.circ` file emits exactly one `buildXxx` function (architectural anchor 6 in `PLANS_PROMPT.md`). Sub-circuit instances are call sites.
- Two-phase resolution: scan-then-parse (Q10a, decision (ii)).
- Per-file IR + resolution table (Q10b, decision (ii)).
- Import-cycle detection lives in Phase 7's resolver; combinational-loop detection stays in Phase 3 (Q10c confirmed).
- Imports are resolved relative to the importing file. No search paths.
- Source-path debug info still lives outside the engine, in the parallel debug-info table (architectural anchor 2).

## New diagnostic codes

- `E009 import_not_found` — imported `.circ` file does not exist at the resolved path.
- `E010 import_cycle` — circular import chain (A → B → A, possibly through more files). Notes list every file in the cycle.
- `E011 import_alias_collision` — two imports in the same file use the same alias, or an alias collides with a built-in name.
- `E012 sub_circuit_port_unknown` — reference to a port name on a sub-circuit instance that the imported file's `output`/`input` declarations don't expose.
- `E013 sub_circuit_arity_mismatch` — sub-circuit instance is missing a required input port (specialisation of `E004` for sub-circuit refs).

`W003 unused_import` — an `import` statement whose alias is never instantiated. Replaces the placeholder behaviour from Phase 3 (where `W002 dangling_output` was a no-op in single-file mode).

## Resolver redesign

The single-file resolver from Phase 2 produces an `ir.Module`. The multi-file resolver produces an `ir.Project`:

```
ir.Project
    files:               []ir.Module               # indexed by FileId
    root_file_id:        FileId
    import_table:        []ir.ResolvedImport
    file_paths:          [][]const u8              # FileId → absolute path
```

```
ir.ResolvedImport
    importing_file:      FileId
    alias:               []const u8
    target_file:         FileId
    span:                Span
```

Each `ir.Module` retains the structure from Phase 2, but `ir.ComponentKind.sub_circuit_ref` is now *resolved* — it points at a `(target_file_id, target_module)` pair via the import table.

### Two-phase resolution

**Phase A — scan imports.** Walk the AST of every reachable file (starting from the root, transitively following `import` statements via filesystem reads + parsing) without resolving anything else. Build:

- The set of `FileId`s and their absolute paths.
- The import graph (`(file, alias) → target_file`).
- Diagnostics for `E009` (file not found) and `E010` (cycle).

If `E009` or `E010` fires, abort before Phase B — there's no point resolving bodies if the dependency graph is broken.

**Phase B — resolve bodies.** For each file in topological order (leaves first), run the single-file resolver from Phase 2 to produce an `ir.Module`. Then walk the module's components: for each `unresolved_name` that matches an imported alias, swap it for a resolved `sub_circuit_ref` pointing at the target module's `(input_id, output_id)` interface.

After Phase B, every `sub_circuit_ref` is resolved or is correctly an `unresolved_name` (which Phase 3 will diagnose as `E001`).

## Validator extensions

The validator passes from Phase 3 mostly Just Work on `ir.Project` — they iterate `project.files[*].components` instead of a single module's components. Additions:

- **Port validation** (Phase 3 pass 3): when checking a port reference on a `sub_circuit_ref`, look up the target module's `inputs` and `outputs` arrays; if the port name doesn't appear, emit `E012`.
- **Required-input check** (Phase 3 pass 5): for `sub_circuit_ref`s, treat every input pin of the target module as a required input. Emit `E013` for missing connections.
- **Combinational-loop check** (Phase 3 pass 7): walk *into* sub-circuits during cycle detection. A sub-circuit instance contributes its internal connection graph to the parent's cycle-detection graph (with appropriate gate/wire delay information from each internal component).
- **Dead-code warnings** (Phase 3 pass 8): `W003 unused_import` fires for imports never instantiated. `W002 dangling_output` now actually fires meaningfully — for any sub-circuit instance whose `output` ports the parent never reads.

## Emitter extensions

The emitter from Phase 4 changes shape: instead of one Zig file per circuit, it emits one Zig file *per source `.circ` file* in the project (or one file with multiple `buildXxx` functions — pick at slice time, see Open questions). The runtime entry point in the root file calls `buildRoot` which calls `buildSubcircuit1`, etc.

Each `buildXxx` function takes:

- `circuit: *engine.Circuit` (the shared circuit).
- One `*engine.Component` per declared input pin of the source file.

Returns:

- A struct with one `*engine.Component` per declared output pin.

Sub-circuit instances become call sites: `const ha1 = try buildHalfAdder(circuit, .{ .a = pin_a, .b = pin_b });`.

The `source_path` debug table is now meaningful: each emitted component's path is `[<root_buildXxx_name>, <instance_name_at_each_level>...]`.

## Slices

### Slice 7.1 — File loader and import scanner

**What ships.** `lib/resolver/file_loader.zig` for reading `.circ` files from disk. `lib/resolver/scan_imports.zig` walks the AST of every reachable file (loading and parsing as it goes) and produces:

- A `FileId`-indexed map of paths.
- The `import_table` (with `target_file` populated).
- Diagnostics for `E009` (file not found) and `E011` (alias collision within a single file).

No body resolution yet; this slice only builds the file graph.

**Tests.** Unit tests using fixture filesystems under `tests/fixtures/projects/<name>/` (a new fixture-tree convention — each subdir is a self-contained mini-project with its own `root.circ` and imported files). Coverage:

- Two-file project: scanner discovers both files, populates table.
- Diamond: A imports B and C, both import D — D is loaded once, table has both `(A→B)` and `(A→C)` and `(B→D)` and `(C→D)`.
- Missing import: `E009` emitted, scan continues for other imports.
- Alias collision: `E011` emitted.

**Files touched.** `lib/resolver/file_loader.zig`, `lib/resolver/scan_imports.zig`, `tests/fixtures/projects/<name>/`.

### Slice 7.2 — Import-cycle detection and topological sort

**What ships.** `lib/resolver/import_cycle.zig`: given the import graph from slice 7.1, detect cycles. On clean graph, return a topological order (leaves first). On any cycle, emit `E010` for each cycle with notes naming every file in it.

**Tests.**

- Linear chain (A → B → C): topo order is `[C, B, A]`, no diagnostics.
- Diamond (A → B/C → D): topo order has D first, A last; B and C order is unspecified.
- Self-cycle (A → A): `E010`.
- Indirect cycle (A → B → A): `E010` listing both files.
- Three-node cycle (A → B → C → A): `E010` listing all three.
- Multiple cycles in one project: each reported separately.

**Files touched.** `lib/resolver/import_cycle.zig`.

### Slice 7.3 — Body resolution and sub-circuit linking

**What ships.** `lib/resolver/resolve_bodies.zig`: takes the import table + topological order from slices 7.1/7.2, calls Phase 2's single-file resolver on each file in order, then walks each resolved module's components to link `unresolved_name`s that match imported aliases into `sub_circuit_ref`s.

The output is an `ir.Project` ready for validation.

**Tests.**

- Two-file project resolves cleanly: parent's component instance becomes a `sub_circuit_ref` pointing at the child file's module.
- Reference to a non-imported, non-primitive name stays `unresolved_name` (Phase 3 will diagnose).
- Built-in primitive references stay primitive (no accidental import-alias shadowing).

**Files touched.** `lib/resolver/resolve_bodies.zig`.

### Slice 7.4 — Validator extensions for multi-file IR

**What ships.** Updates to Phase 3's passes to handle `ir.Project`:

- Port validation: emit `E012` for unknown ports on sub-circuit refs.
- Required-input check: emit `E013` for missing inputs on sub-circuit refs.
- Combinational-loop check: extend the delay-quotient graph builder to walk into sub-circuits.
- Dead-code: implement `W003 unused_import`; activate `W002 dangling_output` for sub-circuit instances.

The pass interfaces change from `*const ir.Module` to `*const ir.Project`. Phase 3's existing fixtures are migrated to the new shape (most still work as single-file projects).

**Tests.** Per-code fixtures using the new project-fixture layout:

- `tests/fixtures/projects/E012_unknown_port/` — root imports a sub-circuit, references a port the sub-circuit doesn't expose.
- `tests/fixtures/projects/E013_missing_input/` — root instantiates a sub-circuit but doesn't connect a required input.
- `tests/fixtures/projects/E008_loop_through_subcircuit/` — combinational loop that crosses a sub-circuit boundary.
- `tests/fixtures/projects/W003_unused_import/` — import never instantiated.
- `tests/fixtures/projects/clean_two_file/` — clean two-file project, no diagnostics.

**Files touched.** Phase 3's pass files (modified), new fixtures.

### Slice 7.5 — Multi-file emission

**What ships.** Updates to Phase 4's emitter:

- `lib/emit/build_fn.zig` emits one `buildXxx` function per source file, taking the file's input pins as arguments and returning a struct of output pins.
- Sub-circuit instance emission: a `sub_circuit_ref` becomes a call to the corresponding `buildXxx` function with the parent's components as arguments.
- The runtime entry point (in `lib/emit/runtime.zig`) calls `buildRoot` (the root file's function) — its inputs and outputs are the project's externally visible pins.
- `lib/emit/debug_paths.zig` produces hierarchical paths now.
- `lib/emit/file_info.zig` lists root-file pins, plus a separate section listing sub-circuit instance names with their hierarchical paths (`getFileInfo()`'s `sub_circuits` field).

**Tests.**

- Golden-file tests: project fixtures pair with `tests/fixtures/expected-zig/<project>/main.zig` (the emitted source for the root) plus per-sub-file emitted source.
- Behavioural tests: the harness from Phase 4 is extended to handle multi-file projects (it now compiles a project, not a single file). Truth-table tests for canonical sub-circuit fixtures: half-adder, full-adder built from two half-adders.

**Files touched.** `lib/emit/build_fn.zig`, `lib/emit/runtime.zig`, `lib/emit/debug_paths.zig`, `lib/emit/file_info.zig`, harness updates, fixtures.

### Slice 7.6 — Hardening fixtures

**What ships.** The comprehensive fixtures committed in Q10d's option (ii):

- Diamond: A imports B and C, both import D — D is parsed and emitted once, instantiated thrice.
- Deep chain (4+ levels): A → B → C → D → E, each adding one wrapper.
- Same-name sub-circuits in unrelated files: two unrelated `.circ` files both define a `half_adder` (in this case via their filename). Aliasing on import keeps them separate.

Each fixture has a behavioural test driving its inputs and asserting outputs.

**Files touched.** Fixtures only, plus harness invocations.

## Definition of done for Phase 7

- All six slices committed.
- `zig build test` passes.
- A `.circ` file can `import` another `.circ` file and instantiate it as a sub-circuit. The result compiles to a working `.wasm`.
- Import cycles are detected and reported.
- Sub-circuit boundaries do not break combinational-loop detection.
- The `getTopology()` and `getFileInfo()` exports surface hierarchical information.
- Diagnostic codes `E009`–`E013` and `W003` have at least one fixture each.
- Diamond, deep-chain, and same-name fixtures all compile and run correctly.

## Open questions to resolve at slice time

- One Zig file per source `.circ` file vs one Zig file with multiple `buildXxx` functions. Recommendation: one Zig file with multiple `buildXxx` functions — keeps the temp dir layout simple, avoids any import-path mapping complexity in the production `build.zig` template, and Zig handles multi-function files trivially. The "one function per source file" architectural anchor is about the function structure, not the file structure.
- How to compute `FileId` order. Recommendation: assign in scan order during slice 7.1; topological sort returns indices, doesn't reorder. Stable IDs make debugging easier.
- Whether the resolver's per-file body resolution can be cached when the same file is imported by multiple parents. In a topological pass that visits each file once, caching is automatic — each file is resolved exactly once, regardless of how many parents import it. No explicit cache needed.
- How to handle a file with no `output` declarations imported as a sub-circuit. Probably a hard error (the sub-circuit has nothing to expose, so instantiating it is meaningless). Pick a code (could be `E014`) at slice time, or fold it into `E007 unassigned_output` semantics.
- Project-fixture directory layout: are project fixtures co-located with the existing `tests/fixtures/circuits/` (each project as a subdir) or separate at `tests/fixtures/projects/`? Recommendation: separate directory `tests/fixtures/projects/<name>/`. The flat circuits directory stays for single-file fixtures from Phases 2-6; projects get their own tree.

## Notes for the next phase

Phase 8 (built-in macro library) plugs into Phase 7's import machinery: built-ins are mounted at a virtual `<builtin>/` filesystem path. The implicit auto-import (Q11b) means every file behaves as if it had `import or from "<builtin>/or.circ"`, etc., at the top. The resolver from Phase 7 doesn't need a special case — it just needs the file loader from slice 7.1 to know how to resolve `<builtin>/` paths to embedded `@embedFile` content.

Phase 9 (integration test hardening) adds stress and edge-case fixtures across the full pipeline, many of which involve sub-circuits.
