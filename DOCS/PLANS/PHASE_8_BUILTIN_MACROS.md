# Phase 8 — Built-in Macro Library

## Goal

Ship `or`, `nand`, `nor`, `xor`, and `xnor` as compiler-provided sub-circuits, expanded at compile time using the `and` and `not` primitives the engine already supports. After this phase, users can write circuits with the full conventional logic-gate vocabulary without writing or importing any `.circ` files for these gates.

## Scope

In scope:

- Built-in `.circ` source files for `or`, `nand`, `nor`, `xor`, `xnor` under `templates/builtins/` (or equivalent), embedded into the CLI binary via `@embedFile`.
- A virtual `<builtin>/` filesystem mount in the file loader, so import paths starting with `<builtin>/` resolve to embedded content rather than disk reads.
- Implicit auto-import: every parsed file behaves as if it had `import or from "<builtin>/or.circ"`, etc., at the top — without users writing those statements.
- Truth-table tests per macro covering all 2-input combinations.
- Composition tests proving built-ins compose with each other and with user-defined sub-circuits (Q11d, decision (ii)).
- Documentation update to `circuit-format.md` listing the available built-in gates.

Out of scope:

- N-ary gates (`and3`, `or4`, etc.). Built-ins are 2-input only in v0; users compose for wider gates.
- Buffer/identity gate beyond what `wire` already provides.
- Tri-state gates, latches, flip-flops, or any sequential element. The engine has no concept of clocked elements; sequential primitives are out of scope for v0.
- Promotion of any built-in to an engine primitive for performance. Profiling-driven promotions are post-v0.
- Special CLI handling for built-ins. They go through the normal pipeline.

## Architectural anchors recap

- Built-ins go through the same parse/validate/emit pipeline as user code (engineering rule 7 in `PLANS_PROMPT.md`). No special-case branches in the resolver, validator, or emitter.
- Built-ins live at `<builtin>/` in a virtual filesystem (recurring trap in `PLANS_PROMPT.md`).
- Implicit auto-import (Q11b, decision (ii)).
- Macros may compose using each other (Q11c, decision (i) — minimal expansions).

## Built-in expansions

The minimal expansion for each macro, using only `and` and `not` (and other built-ins where it shrinks the result):

```
# templates/builtins/or.circ
input a, b
output out

# OR(a, b) = NOT(AND(NOT(a), NOT(b)))
not na (in = a.out)
not nb (in = b.out)
and inner (a = na.out, b = nb.out)
out = not (in = inner.out).out
```

```
# templates/builtins/nand.circ
input a, b
output out

# NAND(a, b) = NOT(AND(a, b))
and inner (a = a.out, b = b.out)
out = not (in = inner.out).out
```

```
# templates/builtins/nor.circ
input a, b
output out

# NOR(a, b) = NOT(OR(a, b))
or inner (a = a.out, b = b.out)
out = not (in = inner.out).out
```

```
# templates/builtins/xor.circ
input a, b
output out

# XOR(a, b) = AND(OR(a, b), NAND(a, b))
or  o (a = a.out, b = b.out)
nand n (a = a.out, b = b.out)
out = and (a = o.out, b = n.out).out
```

```
# templates/builtins/xnor.circ
input a, b
output out

# XNOR(a, b) = NOT(XOR(a, b))
xor inner (a = a.out, b = b.out)
out = not (in = inner.out).out
```

These exact source forms can be tweaked at slice time as long as they parse cleanly under the existing grammar and produce the correct truth tables.

The expansions deliberately compose: `nor` reuses `or`, `xor` reuses `or` and `nand`, `xnor` reuses `xor`. This proves the built-ins are first-class sub-circuits and exercises Phase 7's multi-file resolution.

## Virtual filesystem mount

The file loader from slice 7.1 grows a small dispatch:

```zig
pub fn loadFile(path: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, path, "<builtin>/")) {
        return loadBuiltin(path["<builtin>/".len..]);
    }
    return loadFromDisk(path);
}
```

`loadBuiltin(name)` looks the name up in an embedded table populated by `@embedFile` (analogous to the runtime template's embed manifest from Phase 5).

The path is treated as opaque by the rest of the resolver — the import-cycle check, the topological sort, the diagnostics, all work identically whether the source came from disk or from the virtual filesystem.

## Implicit auto-import

After parsing a file's AST in Phase 2, the resolver injects synthetic `ast.Import` nodes for every built-in name *before* running the body resolver. The injected nodes have a synthetic `Span` that points back at a file location like `<builtin>/auto-imported.zig` (or simply marks the span as "synthetic" — pick at slice time).

Synthetic imports do *not* trigger `W003 unused_import` if the user doesn't reference the alias. The `unused_import` warning only fires for user-written imports.

Aliases are reserved names: a user-written `import or from "./my-or.circ"` is an `E011 import_alias_collision` against the implicit `or` import.

## Slices

### Slice 8.1 — Built-in source files and embed table

**What ships.** The five `.circ` files under `templates/builtins/` plus an embed table in `lib/resolver/builtins.zig` (or co-located with the file loader) exposing each as a named blob.

**Tests.** A test that lists every expected built-in name (`or`, `nand`, `nor`, `xor`, `xnor`) and asserts the embed table contains a non-empty blob for each. A second test parses each built-in's source through Phase 2's parser and asserts the AST has at least one `input`, one `output`, and one `component` declaration — proves the built-in source files are syntactically valid.

**Files touched.** `templates/builtins/*.circ`, `lib/resolver/builtins.zig`.

### Slice 8.2 — Virtual filesystem mount in the file loader

**What ships.** Update `lib/resolver/file_loader.zig` to dispatch on path prefix `<builtin>/` to the embed table from slice 8.1, falling back to disk reads.

**Tests.**

- `loadFile("<builtin>/or.circ")` returns the same content as the embed table's `or` entry.
- `loadFile("<builtin>/missing.circ")` returns an error indicating the built-in doesn't exist (distinct error from "file not found on disk").
- `loadFile("./real_file.circ")` still hits disk.

**Files touched.** `lib/resolver/file_loader.zig`.

### Slice 8.3 — Implicit auto-import

**What ships.** The resolver gains a step (between parsing and body resolution) that injects synthetic `ast.Import` nodes for every built-in into every parsed file. The scanner (slice 7.1) treats synthetic imports identically to user imports for graph purposes, so the import scan + topo sort already cover the built-ins.

The dead-code pass (Phase 7's slice 7.4) is updated: synthetic imports are flagged so they don't trigger `W003`.

**Tests.**

- A clean fixture using `or` directly without an explicit import: the resolver produces a `sub_circuit_ref` to the built-in, no diagnostics.
- A fixture writing `import or from "./my-or.circ"`: emits `E011 import_alias_collision` against the implicit built-in.
- A fixture with no built-in references: still parses cleanly, no `W003` for the unused implicit imports.

**Files touched.** `lib/resolver/resolve_bodies.zig` (or wherever auto-import injection lives), Phase 7's dead-code pass.

### Slice 8.4 — Truth-table tests per built-in

**What ships.** A behavioural fixture per built-in: a `.circ` file using only that built-in (driven by two input pins, with one LED reading the output), plus a `tests/fixtures/expected-wasm/<builtin>.txt` truth-table specification. The Phase 4 harness runs each fixture through the full pipeline (now including Phase 7's multi-file emission).

```
# Example: tests/fixtures/expected-wasm/xor.txt
a=0 b=0 => out=0
a=0 b=1 => out=1
a=1 b=0 => out=1
a=1 b=1 => out=0
```

One test loop iterates the five built-ins, runs each fixture, asserts the truth table holds.

**Files touched.** `tests/fixtures/circuits/builtin_<name>.circ`, `tests/fixtures/expected-wasm/builtin_<name>.txt`.

### Slice 8.5 — Composition tests

**What ships.** A canonical composition fixture and behavioural test: a 1-bit full adder built from `xor`, `and`, and `or`:

```
# tests/fixtures/circuits/full_adder_from_builtins.circ
input a, b, cin
output sum, cout

xor s1 (a = a.out, b = b.out)
xor s2 (a = s1.out, b = cin.out)

and c1 (a = a.out, b = b.out)
and c2 (a = s1.out, b = cin.out)
or  c3 (a = c1.out, b = c2.out)

sum  = s2.out
cout = c3.out
```

Truth-table fixture covers all 8 input combinations.

A second composition fixture combines a user-written sub-circuit with built-ins (e.g. a user-written `half_adder` together with `or` for the full adder's carry) — proves built-ins and user sub-circuits compose freely.

**Files touched.** Two `.circ` fixtures, two truth-table specs.

## Definition of done for Phase 8

- All five slices committed.
- `zig build test` passes.
- A user can write `or`, `nand`, `nor`, `xor`, `xnor` without any explicit `import` statement and the compiler resolves them through the implicit `<builtin>/` import path.
- All truth tables pass for every built-in.
- The full-adder composition test passes.
- The user-defined-sub-circuit + built-in composition test passes.
- `circuit-format.md` lists the available built-in gates.

## Open questions to resolve at slice time

- Whether `wire` is documented as a built-in alongside the new ones, or stays an engine primitive. Recommendation: stay an engine primitive — `wire` doesn't need an expansion. Document it separately.
- Whether `not` and `and` appear in the built-in list. They don't — they're primitives, not macros. Document accordingly.
- Synthetic `Span` representation. Recommendation: a magic `FileId(-1)` or a flag on `Span` that marks it as synthetic; the diagnostic formatter prints `<builtin>` instead of a real path.
- Whether built-ins can themselves declare `import` statements (e.g. could `or` import some helper). Recommendation: no — built-ins are leaf-level expansions in `and` + `not` only (or other built-ins, but no external imports). Enforce by making the resolver reject non-built-in imports from a built-in source.
- Whether to vendor the truth-table fixture format as a reusable test helper. Phase 4 already established the format; Phase 8 just adds more fixtures of the same shape. No new helper needed.

## Notes for the next phase

Phase 9 (integration test hardening) adds stress fixtures, edge cases, regression fixtures for any bugs found during phases 1–8, and the README + getting-started doc. Phase 9 may want to add additional built-in-related coverage (e.g. nested compositions, large built-in trees) — those are hardening work, not core built-in functionality, so they belong in Phase 9 not here.
