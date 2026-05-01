# Phase 9 — Integration Test Suite Hardening

## Goal

Lock down v0 by filling in coverage that earlier phases didn't have time for: stress fixtures, edge cases, regression fixtures from bugs found during phases 1–8, diagnostic snapshot tests for every code, canonical end-to-end fixtures, and a smoke perf test. Ship a top-level `README.md` and a getting-started document so a first-time user can install and use the compiler without reading source.

After this phase, v0 is *done*. Anything left is post-v0 polish or feature expansion.

## Scope

In scope:

- Stress fixtures: large circuits (~100+ components) covering allocator, propagation queue, and emission paths.
- Edge cases: empty circuits, single-component circuits, circuits with only built-ins, deeply nested anonymous components, deeply nested sub-circuit hierarchies.
- Regression fixtures: every bug found and fixed during phases 1–8 lands here as a fixture so it can't recur. (Build the list from STATUS log notes.)
- Diagnostic snapshot tests: every diagnostic code from Phases 3, 7 has at least one fixture asserting on the formatted message — locks message stability.
- Canonical full-pipeline fixtures: half-adder, full-adder, 4-bit ripple counter (combinational, no clock — the "counter" is a 4-bit AND/OR network, since v0 has no sequential elements; rename the fixture if "counter" misleads).
- Smoke performance test: a single fixture asserting compile time stays under a generous budget for a 100-component circuit (Q12b, decision (ii)).
- A top-level `README.md` covering install, basic usage, and a worked example (Q12c, decision (ii)).
- A `DOCS/getting-started.md` walking through writing and compiling a first circuit.
- Updates to existing `DOCS/` files where v0's actual behaviour diverged from the original architecture docs (likely small touch-ups).

Out of scope:

- A full perf budget per phase (parse, validate, emit, build). Smoke only — no per-phase budgets in v0.
- A docs site or tutorial series. The README + getting-started is the v0 documentation surface.
- Cookbook of common circuit patterns. Post-v0.
- Sequential elements (clocked components) or any v1 feature work.
- CI configuration. The user is setting up GitHub Actions separately.

## Architectural anchors recap

- Hard errors block emission (anchor 5). Every error fixture asserts no output is produced.
- Diagnostic codes are stable (engineering rule 4). Snapshot tests on formatted messages catch wording drift.
- Tests live under `tests/fixtures/` organised by artifact kind (engineering rule 2). Phase 9 adds many fixtures but doesn't reorganise.

## Deliverables overview

This phase has two distinct workstreams that can interleave at slice level:

- **Test hardening** (slices 9.1 – 9.5).
- **Documentation** (slices 9.6 – 9.7).

Each workstream is independently reviewable.

## Slices

### Slice 9.1 — Edge-case fixtures

**What ships.** A set of fixtures exercising boundary conditions:

- `empty_circuit.circ` — no components beyond declared inputs/outputs (or fully empty if the grammar allows). Verify the compiler handles it gracefully (success or a clear error — pin the expected behaviour during the slice).
- `single_component.circ` — one input pin, one LED, no logic. Trivial pipeline.
- `single_builtin.circ` — uses exactly one built-in gate, nothing else.
- `deep_anonymous.circ` — five levels of nested anonymous component expressions in a single port connection.
- `deep_subcircuit_chain.circ` — root imports A imports B imports C imports D, each wrapping the previous in a single passthrough.
- `wide_fanout.circ` — one input pin drives 20 components.
- `wide_fanin.circ` — one component reads from many sources via a chain of 2-input gates.

Each fixture either has a behavioural test (truth-table assertion) or, if it's expected to fail validation, a diagnostic-output golden file.

**Tests.** One test loop per fixture group. Reuses the Phase 4 harness.

**Files touched.** `tests/fixtures/circuits/edge_*.circ`, corresponding expected files.

### Slice 9.2 — Stress fixtures

**What ships.** Larger fixtures that exercise scaling:

- `stress_chain_100.circ` — 100 NOT gates in a chain. Verifies propagation queue handles long delay sequences and emission scales linearly.
- `stress_grid_10x10.circ` — a 10×10 grid of AND gates fed by 20 input pins. Verifies emission of many simultaneous connections.
- `stress_deep_subcircuit.circ` — a 4-level sub-circuit hierarchy where each level instantiates 4 children (256 leaf components). Verifies the resolver and emitter handle hierarchy fan-out.

Each fixture has a behavioural test asserting at least one input/output pair behaves correctly. Full truth-table coverage is impractical at this scale; one sanity check per fixture is enough.

**Tests.** Behavioural tests via the Phase 4 harness. May be marked as slow (long compile + run times) but still part of `zig build test`.

**Files touched.** Stress fixtures and behavioural specs.

### Slice 9.3 — Diagnostic snapshot tests

**What ships.** A fixture per diagnostic code (`E001`–`E013`, `W001`–`W003`) paired with an expected-diagnostics golden file. Each fixture is the smallest input that triggers exactly that code. Most of these were created during Phases 3 and 7 — slice 9.3's job is to *audit* the set, fill gaps, and migrate any inline-test diagnostics to fixture-driven assertions.

The audit produces a checklist in this slice's STATUS entry: "code X has a fixture / does not have a fixture / fixture exists but doesn't cover variant Y." Gaps get fixtures.

**Tests.** A single test loop iterates the fixtures, runs them through Phase 2 → 3 → (7 if multi-file), compares the diagnostic dump to the golden file.

**Files touched.** `tests/fixtures/circuits/<code>_*.circ`, `tests/fixtures/expected-diagnostics/<code>_*.txt`.

### Slice 9.4 — Canonical end-to-end fixtures

**What ships.** Three canonical circuits demonstrating realistic usage, each with a project-fixture layout:

- `tests/fixtures/projects/half_adder/` — single sub-circuit, two inputs, two outputs (sum, carry). Truth table for all four inputs.
- `tests/fixtures/projects/full_adder/` — composes two half-adders + an OR. Truth table for all eight inputs.
- `tests/fixtures/projects/and_or_network/` — a 4-bit-wide AND/OR network (replaces the originally-planned "ripple counter" since v0 has no sequential elements). Documents how to express wide combinational logic by composition.

Behavioural tests via the Phase 4/7 harness.

These fixtures double as worked examples for the getting-started doc.

**Files touched.** Three project fixtures with `.circ` files and behavioural specs.

### Slice 9.5 — Regression fixtures and smoke perf test

**What ships.** Two parts:

**Part A: Regression fixtures.** Walk the STATUS log from Phases 0–8, identify every entry that mentions a bug found and fixed mid-phase. For each, extract a minimal `.circ` reproduction and add it to `tests/fixtures/circuits/regression_<short_description>.circ`. A test loop runs all regression fixtures and asserts they produce the expected behaviour (success or a specific diagnostic, depending on the bug).

If the STATUS log is empty of bug entries (e.g. earlier phases shipped clean), this part is a no-op — note that in the STATUS entry.

**Part B: Smoke perf test.** A single test that runs `circ-compile` on `stress_grid_10x10.circ` (from slice 9.2) and asserts compile time is under a generous budget — recommend 30 seconds on a typical developer machine. The budget is intentionally loose; the goal is to catch accidental quadratic blowups in future changes, not to commit to a perf SLA. The test is marked as not-CI-blocking unless this changes.

**Files touched.** Regression fixtures, perf test harness.

### Slice 9.6 — README

**What ships.** A top-level `README.md` (currently absent or minimal — verify and overwrite). Sections:

- One-paragraph project description.
- "What it does" with one or two example `.circ` snippets and what they compile to.
- Install instructions: how to build the CLI from source (`zig build`), where the binary ends up, optional `langlang` install for grammar regeneration only.
- Quick usage: `circ-compile input.circ -o output.wasm`, the three modes summarised.
- A pointer to `DOCS/getting-started.md` for new users.
- A pointer to `DOCS/architecture.md` and `DOCS/decisions/` for contributors.
- License (or a pointer to `LICENSE`).

Aim for under 200 lines. Detailed reference lives under `DOCS/`; the README is a landing pad.

**Tests.** None — documentation isn't tested. Verify the README's example commands actually work by running them manually.

**Files touched.** `README.md`.

### Slice 9.7 — Getting-started doc

**What ships.** `DOCS/getting-started.md` walking through:

1. Install + verify (`circ-compile --help` or equivalent should print usage).
2. Writing a first `.circ` file: pin → not → led, with the source shown.
3. Compiling it: invocation and what gets produced.
4. Loading the resulting `.wasm` from JavaScript: a small Node example calling `init`, `setPin`, `run`, `getOutputState`.
5. A second `.circ` example using a built-in gate (`xor`).
6. A third example introducing a sub-circuit import.
7. Pointers to `circuit-format.md` for the full language reference and `wasm-api.md` for the runtime API.

Each code snippet is small enough to be copyable. Each step has expected output so users can verify they're on track.

**Tests.** None — documentation isn't tested. Run through the doc end-to-end manually with a fresh checkout to confirm every command works.

**Files touched.** `DOCS/getting-started.md`. May also touch `DOCS/index.md` to add a pointer to the new doc.

## Definition of done for Phase 9

- All seven slices committed.
- `zig build test` passes (including stress fixtures).
- Every diagnostic code has at least one snapshot fixture.
- Every regression noted in STATUS during phases 0–8 has a fixture.
- The smoke perf test runs and stays well under its budget on a typical developer machine.
- `README.md` exists and a first-time user can follow it to a working compilation.
- `DOCS/getting-started.md` walks through three increasingly complex examples that all succeed.
- v0 is done. The next phase, if any, is a v1 plan in a new prompt.

## Open questions to resolve at slice time

- Which scaling parameter for stress fixtures: 100 components is recommended, but the actual budget depends on what the host machine can handle in CI. If the perf budget needs to drop under 100 to keep CI fast, do that — the goal is "catch quadratic blowups," not "claim v0 handles 1000 components."
- Whether `--inspect` output for the canonical fixtures (slice 9.4) gets golden coverage too. Recommendation: yes — adds confidence the introspection mode works on real circuits, not just toy ones.
- Whether the regression-fixture audit (slice 9.5 part A) is exhaustive or best-effort. Recommendation: best-effort — read the STATUS log, file what you find, don't archaeologise the git history. Bugs not captured here will be caught by future bug reports and added when fixed.
- Whether the perf budget should be enforced in CI or local-only. Recommendation: local-only for v0. CI machines are unpredictable and a flaky perf test is worse than no perf test. Mark it `test "perf: ..." { try std.testing.skip(); }` if running in CI environments where it's unreliable, or use `std.testing.allocator`'s slowness as the gate.
- Whether the example WASM produced in slice 9.4 should be checked in alongside the fixtures. Recommendation: no — `.wasm` files are build outputs, regenerable on demand, and pollute version control. The fixtures regenerate them via the harness.

## Notes for v0 sign-off

After Phase 9, the v0 product can:

- Compile single-file `.circ` source to a self-contained `.wasm` artifact.
- Compose sub-circuits across multiple files.
- Use the standard logic-gate vocabulary (`and`, `or`, `not`, `nand`, `nor`, `xor`, `xnor`, `wire`, `led`, `input`, `output`).
- Produce informative diagnostics with stable codes.
- Expose a fixed runtime API (`init`, `run`, `reset`, pin I/O, introspection, file info).
- Be embedded in any host that supports WebAssembly.

What v0 cannot do:

- Sequential elements (clocks, latches, flip-flops).
- N-ary built-in gates (workaround: compose).
- TypeScript declaration emission (`.d.ts`).
- Source-snippet diagnostic rendering (caret indicators).
- Incremental compilation.

These are post-v0 work. None block declaring v0 done.
