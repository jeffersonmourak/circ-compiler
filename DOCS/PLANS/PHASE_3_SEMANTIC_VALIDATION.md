# Phase 3 — Semantic Validation

## Goal

Take the resolved IR produced by Phase 2 and run every semantic check committed to in `DOCS/decisions/validation.md`. After this phase, the compiler produces a list of diagnostics for any `.circ` source: hard errors that would block emission, warnings that surface but don't block, or an empty list when the source is clean.

This phase produces the diagnostic infrastructure the rest of the project depends on. Phase 4 (emission) refuses to run if there are hard errors. Phase 6 (CLI) prints diagnostics in the `<file>:<line>:<col>: <level>: <message>` format. Phase 7 (sub-circuits) extends the multi-driver and cycle checks to the multi-file IR.

## Scope

In scope:

- A multi-pass validator under `lib/validator/` (or equivalent). One pass per check; passes run in dependency order.
- Diagnostic types with stable codes (`E001`, `W001`, …). Each pass emits codes; the CLI/tests format them.
- Diagnostic accumulation: every pass collects all the diagnostics it can find rather than failing fast. Downstream passes are resilient to upstream failures (skip checks that depend on unresolved data).
- Hard-error categories per `DOCS/decisions/validation.md`.
- Warning categories per `DOCS/decisions/validation.md`.
- Combinational-loop detection on the *connection graph* (delay-quotient: only gates break loops, wires don't).
- Tests: one fixture per diagnostic code, plus composite fixtures exercising multiple checks at once.

Out of scope:

- Import-cycle detection. Imports are unresolved at this phase — the IR's `imports` field is populated but not followed. Phase 7 owns import-cycle detection and runs it on a different graph (the import graph, not the connection graph).
- Built-in-name handling. Phase 8 owns the built-in macro library. References to `or`, `nand`, etc. land in Phase 3 as `unresolved_name` markers and would be diagnosed as `E001` — that's correct behaviour for now; Phase 8 makes them resolve through the implicit `<builtin>/` import path.
- Sub-circuit-reference resolution. Sub-circuit references are `sub_circuit_ref` markers from Phase 2 and stay unresolved at this phase. Phase 3 *does not* diagnose them as errors — they're a legal IR shape that Phase 7 will resolve. The validator skips checks that depend on a sub-circuit's internal structure.
- Source-snippet rendering. Diagnostics produced here have spans (from Phase 2) and the format string `<file>:<line>:<col>: <level>: <code>: <message>`. Caret-indicated source snippets are deferred per the decisions doc.

## Architectural anchors recap

- Multi-pass validator (Q6a, decision (ii)). Each pass is independently testable.
- Accumulate-all diagnostics (Q6b, decision (ii)). One run produces every diagnostic the validator can find.
- Stable codes (Q6c, decision (i)). Tests assert on codes; messages are formatted by a separate layer.
- Combinational loops are hard errors detected on the delay-quotient graph (Q6d). Wires do not break loops.

## Diagnostic structure

```
Diagnostic {
    level:    .error | .warning,
    code:     DiagnosticCode,            # enum: E001, E002, ..., W001, W002, ...
    span:     Span,
    message:  []const u8,                # formatted at emission time, includes interpolated names
    notes:    []DiagnosticNote = &.{},   # optional supplementary spans (e.g. "first declared here")
}

DiagnosticNote {
    span:     Span,
    message:  []const u8,
}
```

`code` is the stable identifier. The mapping from code to default message lives in a single table (`lib/validator/codes.zig` or similar). Tests assert on the code; the CLI formats `<level>: <code>: <message>`.

`notes` exists so a diagnostic can point at a second location (e.g. for a name collision: the offending duplicate plus a note "first declared here"). Phase 3 uses notes where they help; the CLI prints them on additional lines.

## Diagnostic code allocation

This phase commits the following codes. Future phases append to the list — do not renumber.

**Errors:**

- `E001 undeclared_name` — reference to a name that doesn't resolve to a primitive, sub-circuit, or local declaration.
- `E002 unknown_port` — reference to a port that doesn't exist on the target component kind.
- `E003 multi_driver` — a single input port is driven by more than one source.
- `E004 unconnected_required_input` — a required input port has no driver.
- `E005 duplicate_instance_name` — two components share an instance name in the same scope.
- `E006 name_shadows_builtin` — an instance name collides with a built-in gate name.
- `E007 unassigned_output` — an `output` declaration has no driver.
- `E008 combinational_loop` — a feedback path with no delay-bearing component.

(`E009` and beyond are reserved for Phase 7's import-resolution errors and Phase 4+ surprises.)

**Warnings:**

- `W001 unused_input` — an input pin is declared but never connected to anything.
- `W002 dangling_output` — a sub-circuit's `output` is declared but the parent never reads it. Note: in single-file mode this is "an `output` declaration in a top-level circuit," which is rarely meaningful — but the warning still fires.

(`W003+` reserved for Phase 7.)

## Pass pipeline

The validator runs these passes in order. Each pass takes the IR + the diagnostics-so-far list. Downstream passes check for upstream failures and skip on a per-component basis where appropriate.

1. **Name resolution** — finalise the resolution of `unresolved_name` markers. In single-file mode there's no resolution to do beyond what Phase 2 already did, so this pass walks the IR and emits `E001` for every `unresolved_name`. (`sub_circuit_ref` is not an error here — it's deferred.)
2. **Name-collision check** — duplicate instance names (`E005`), collision with a built-in name (`E006`).
3. **Port validation** — every `Connection`'s endpoint references a port that exists on the target component kind. Skips connections involving sub-circuit refs (Phase 7's job). Emits `E002`.
4. **Multi-driver check** — group connections by `(target_component, target_port)`. Any group with more than one driver emits `E003` with notes pointing at each driver.
5. **Required-input check** — for each component, check that every required input port has at least one driver. `and` requires `a` and `b`; `not` requires `in`; `wire` requires `in`; `led` requires `in`; `output_pin` requires `in`. Emits `E004`. Skips sub-circuit refs.
6. **Output-assignment check** — every `ir.OutputPin` has a driver. Emits `E007` for those that don't.
7. **Combinational-loop check** — build the delay-quotient graph, run DFS cycle detection. Emits `E008` for each cycle, with notes listing every node in the cycle.
8. **Dead-code warnings** — input pins with no outgoing connection (`W001`), output declarations with no readers (`W002`).

Each pass is its own Zig file (`lib/validator/passes/<name>.zig`) with a single entry point `pub fn run(ir: *const Ir, diags: *DiagnosticList) void`.

## Slices

### Slice 3.1 — Diagnostic types and code table

**What ships.** `Diagnostic`, `DiagnosticNote`, `DiagnosticList`, `DiagnosticCode` enum, and the `codes.zig` table mapping codes to default message templates. A simple format function that produces `<file>:<line>:<col>: <level>: <code>: <message>` — used by the CLI later but exercised here in tests.

**Tests.** Construct a diagnostic by hand, format it, assert the output matches the expected string. One test per diagnostic-code message format (a parameterised loop over the code table is fine).

**Files touched.** `lib/validator/diagnostics.zig`, `lib/validator/codes.zig`, `tests/fixtures/expected-diagnostics/.gitkeep` (directory exists from Phase 0).

**Why this slice exists alone.** The diagnostic shape is the contract every pass uses. Locking it before any pass is implemented prevents per-pass churn.

### Slice 3.2 — Name resolution and collision passes

**What ships.** Passes 1 and 2 from the pipeline above (`name_resolution.zig`, `name_collision.zig`). Each is a pure function over the IR producing diagnostics.

**Tests.** Per-code fixture pairs:

- `tests/fixtures/circuits/E001_undeclared.circ` + `tests/fixtures/expected-diagnostics/E001_undeclared.txt`
- `tests/fixtures/circuits/E005_duplicate_name.circ` + `tests/fixtures/expected-diagnostics/E005_duplicate_name.txt`
- `tests/fixtures/circuits/E006_shadows_builtin.circ` + `tests/fixtures/expected-diagnostics/E006_shadows_builtin.txt`
- A clean fixture asserting *no* diagnostics for valid input.

The expected-diagnostics file is a deterministic dump of the diagnostic list (one diagnostic per line, sorted by span position).

**Files touched.** `lib/validator/passes/name_resolution.zig`, `lib/validator/passes/name_collision.zig`, fixtures.

### Slice 3.3 — Port validation, multi-driver, required-input, output-assignment

**What ships.** Passes 3, 4, 5, 6 from the pipeline. Each pass is its own file under `lib/validator/passes/`.

**Tests.** Per-code fixtures for `E002`, `E003`, `E004`, `E007`. Each fixture is the smallest input that triggers exactly that diagnostic; if other diagnostics are unavoidable side effects, they appear in the expected output too — that's fine, it's how accumulate-all works in practice.

A composite fixture (`tests/fixtures/circuits/multi_diagnostic.circ`) deliberately triggers `E001` and `E002` together to verify accumulation across passes.

**Files touched.** Four new files under `lib/validator/passes/`, fixtures.

### Slice 3.4 — Combinational-loop detection

**What ships.** Pass 7 (`combinational_loop.zig`). Builds the delay-quotient graph by walking `ir.Connection`s and treating gate components (`and`, `not`) as cycle-breaking — wires (`wire`, `output_pin` since pass-through) and sinks (`led`) do *not* break cycles. Runs DFS cycle detection on the resulting graph; emits `E008` for each cycle with notes naming every node in the cycle.

**Tests.**

- `tests/fixtures/circuits/E008_simple_loop.circ` — a single NOT gate feeding back into itself (`not a (in = a.out)`). Hard error.
- `tests/fixtures/circuits/E008_wire_loop.circ` — a chain of wires looping back without a gate. Hard error (wires don't break loops).
- `tests/fixtures/circuits/clean_gated_feedback.circ` — feedback through at least one gate. Clean (no diagnostics) — this verifies the cycle detector correctly *doesn't* flag legitimate gated feedback.
- A two-cycle fixture verifying multiple cycles are reported, not just the first.

**Files touched.** `lib/validator/passes/combinational_loop.zig`, fixtures.

### Slice 3.5 — Warning passes and validator driver

**What ships.** Pass 8 (`dead_code.zig`) covering `W001` and `W002`. The validator's top-level driver (`lib/validator/run.zig`) that orchestrates all passes in order, returning the accumulated `DiagnosticList`.

A `--warnings-as-errors` mode is **not** implemented at this layer — the validator always reports level=`.warning` for warnings. The promotion-to-error logic lives in the CLI layer (Phase 6). The validator's only job is to label things correctly.

**Tests.**

- `W001_unused_input.circ` — input declared, never connected.
- `W002_dangling_output.circ` — output declared, never read (in single-file mode this means: an `output` declaration whose driver is set but no other component reads from it; arguably a top-level concept, see "Open questions").
- A clean fixture with no warnings.
- A fixture combining errors and warnings, verifying both appear in the accumulated list.

**Files touched.** `lib/validator/passes/dead_code.zig`, `lib/validator/run.zig`, fixtures.

## Definition of done for Phase 3

- All five slices committed.
- `zig build test` passes.
- Given a resolved IR, the validator produces a `DiagnosticList` with every applicable diagnostic.
- Every code in the allocated range (`E001`–`E008`, `W001`–`W002`) has at least one fixture.
- The validator does not emit diagnostics for `sub_circuit_ref` markers or for `imports` — those are deferred to Phase 7.
- The diagnostic format `<file>:<line>:<col>: <level>: <code>: <message>` is produced for every diagnostic in test output.

## Open questions to resolve at slice time

- `W002 dangling_output` semantics in single-file mode. A top-level circuit's `output` declarations are read by the *runtime host*, not by another sub-circuit, so "no readers" is the default state at compile time. Two interpretations:
  - (i) `W002` is only meaningful for *imported* sub-circuits whose outputs the parent ignores. It never fires in single-file mode. Defer the warning's actual implementation to Phase 7.
  - (ii) `W002` fires in single-file mode if an `output` declaration has no driver (but that's already `E007 unassigned_output` — duplicate). Drop (ii).
  - Recommendation: take (i). Slice 3.5 reserves the code but leaves the pass as a no-op in single-file mode. Phase 7 implements the actual check when it has a multi-file context.
- The exact format of expected-diagnostics fixture files. Recommendation: one diagnostic per line, format `<file>:<line>:<col>: <level>: <code>: <message>`. Notes appear on the next line indented two spaces, prefixed `note:`. Stable, line-diffable.
- Whether to validate the IR's structural invariants (e.g. "every connection's endpoint references a real component") as a separate pre-validation pass or trust Phase 2 to produce well-formed IR. Recommendation: trust Phase 2. If a Phase 2 bug produces malformed IR, Phase 3 will hit a panic — that's the right failure mode for an internal-invariant violation.

## Notes for the next phase

Phase 4 (emission) refuses to emit if `DiagnosticList` contains any `.error`-level diagnostic. The check is one line in the CLI driver. Phase 4 is otherwise unaware of validation — it consumes a clean IR and assumes correctness.

Phase 7 (sub-circuit support) revisits passes 1, 4, 5, 6, 7 to extend them across imported sub-circuits. The multi-pass structure makes this straightforward — each pass already takes the IR as input; Phase 7 changes what "the IR" is (single module → linked multi-module).
