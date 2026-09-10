# Archived plan: multi-bit-language

**Canonical commit:** `bdaf0ee6cb2c808c417af4c26758ef109afc9dd4` (`bdaf0ee docs: bring DOCS into line with multi-bit wires and topology v02 (#70)`)
**Archived on:** 2026-05-25
**Plan duration:** 2026-05-21 → 2026-05-25

> This file is the plan document as it was written before implementation, kept verbatim. The work shipped across stages S1–S12; its seventeen decisions are recorded in `DOCS/decisions/language.md` ("Multi-bit wires", §1–§17) and the format in `DOCS/circuit-format.md`. It predates `DOCS/prompts/ARCHIVE.md`, so it has no phase-by-phase highlights section.

# Multi-bit Wires in the circ Language

**Status:** Shipped (see the header above).
**Last updated:** 2026-05-21 (plan text); archived 2026-05-25.
**Scope:** Extend the `circ` language surface to express multi-bit wires, leveraging the engine's existing width-agnostic `BitVecState` and width-tiered pool design.

---

## Summary

The simulation engine already accepts wire widths up to 64 bits via `BitVecState{value, defined, width}` and a width-tiered Structure-of-Arrays pool. Only width=1 is wired today because the language has no syntax for declaring or referring to wider wires, and the gate evaluator hardcodes width-1 predicates.

This plan extends the language surface to express multi-bit wires end to end, with parametric sub-circuits as the mechanism for reusable multi-bit logic. Built-in macros (`or`, `xor`, `nand`, `nor`, `xnor`) move from scalar-only `.circ` files to parametric ones, providing the first users of the new feature.

The engine grows two new primitive kinds (`slice` and `concat`) to support compositional signal expressions, but stays otherwise unchanged. All bitwise semantics live in widened `BitVecState` operations, not new gate kinds.

---

## Goals

* Allow declaring multi-bit pins, gates, and wires: `input[4] a, b`, `and[4] g(a=a, b=b)`, `output[4] r(in=g.out)`.
* Allow referring to bits or ranges of multi-bit signals: `a[2]`, `a[0..4]`.
* Allow composing multi-bit signals from narrower ones: `{a, b, c, d}`.
* Allow user-defined sub-circuits to be width-parametric: `input<W> a` / `not[W] g(in=a)`.
* Keep existing scalar `.circ` files working byte-identically (default missing width is 1).
* Bump the topology format version (v01 → v02) to carry width per component.
* Update the WASM host API to carry `(value, defined)` `u64` pairs (BigInt on the JS side).
* Migrate the five built-in macros to parametric form.

## Out of scope (v1)

* Integer or bit literals in source code (e.g. `1'b0`, `4'hF`). The language has no literals today; constants are a separate design.
* Arithmetic on parameters (`W-1`, `W/2`). Parameters appear only as `[W]` width annotations, never inside slice/index/arithmetic expressions.
* Iteration / generative loops over parameters. Structural parametric sub-circuits (ripple-carry adders, shifters, comparators) stay fixed-width in v1.
* Width inference. Every declaration spells its width; missing `[N]` means width 1.
* Slicing or indexing applied to anonymous component outputs (`not(in=x).out[0..2]`) or to concat expressions (`{a,b}[0..2]`). These compose only on named references.
* Default parameter values at the sub-circuit declaration site. A future `<W=8>` syntax can land additively.
* Multi-output-port sub-circuits with mixed widths participating in width-parametric calls. Sub-circuits with `<W>` may have multiple output ports, but all parametric ports share the same parameter family in v1.

---

## Locked Design Decisions

| # | Topic | Decision |
| - | - | - |
| 1 | Width on declarations | `[N]` after the type keyword. `input[4] a, b`, `and[4] g(...)`, `output[4] r(in=...)`. Missing `[N]` means width 1. |
| 2 | Bit numbering | `a[0]` is the LSB; bit `i` carries weight 2^i. Matches `BitVecState.value` bit layout exactly. |
| 3 | Slice notation | `a[lo..hi]` half-open. `a[0..4]` is a 4-bit slice covering bits 0, 1, 2, 3. |
| 4 | Concatenation | `{low, high}` with braces, low-on-left ordering. `{a, b}` produces a width `a.width + b.width` value where bits `[0, a.width)` come from `a` and bits `[a.width, ...)` come from `b`. |
| 5 | Sub-circuit parametricity | A sub-circuit becomes parametric by introducing parameters via `<Identifier>` on `input` declarations. Use sites inside the file write `[Identifier]`. Caller binds via `name[N, M, ...]` positionally. |
| 6 | `<W>` vs `[W]` | Angle brackets are the *introduction* form (declares a parameter). Square brackets are the *reference* form (carries either an integer literal or a previously-introduced parameter name). |
| 7 | Where parameters can appear | Width annotations only. Parameters do not appear inside slice bounds, indices, arithmetic, or anywhere else. |
| 8 | `[N]` on a scalar sub-circuit | Compile error (E015). The diagnostic suggests adding `<W>` to the sub-circuit. |
| 9 | Multiple parameters | Allowed. Positional at call sites; ordered by the position of first introduction in the source file. |
| 10 | Missing `[N]` at call site | Defaults all parameters to 1. Preserves the behavior of every existing scalar caller. |
| 11 | `<W>` discipline | Mandatory and visible. A parametric sub-circuit declares its parameter in angle brackets on the introducing `input` line; never elided or implicit. |
| 12 | LED at width > 1 | Default `--preview` rendering is a single numeric display (hex). New `--expand-display` flag switches to a row of indicator LED glyphs (LSB on the left). Flag honored only when `N < 8`; at `N >= 8` the renderer falls back to numeric and emits a post-render warning. |
| 13 | Truth table | One column per pin; multi-bit values rendered per format flag. New `--truth-table-format binary\|hex\|decimal` (default binary). Hard cap at 16 total input bits across all inputs. New `--truth-table-cap` override available up to 24. |
| 14 | WASM host API | Two BigInt `u64`s per pin call: `setPin(id, value, defined)` writes the state; `getOutputState(id)` returns `{value, defined}`. Direct mirror of `BitVecState`. |
| 15 | Macro migration | Rewrite the five built-in macros (`or`, `xor`, `nand`, `nor`, `xnor`) in place with `<W>` annotations. The default-missing-`[N]` rule keeps every existing scalar caller working unchanged. |
| 16 | Signal-expression composition | Allowed signal sources: bare name, `name.port`, `name[i]`, `name[lo..hi]`, `name.port[i]`, `name.port[lo..hi]`, an anonymous component instance, or `{ ... }` containing any of the above. |
| 17 | Topology format | Bump version from `0x01` to `0x02`. `ComponentRecord` and `FullComponentRecord` grow a `width: u8`. Slice and concat carry auxiliary metadata in the full topology section. |

### Design notes

**Width is a static, declaration-bound property.** The engine's tier dispatch happens once at `createComponent`; making width a property of declarations (not signals) mirrors that reality and keeps the validator's job a single equality check per connection.

**Parametric specialization is a resolver-time transformation.** By the time the IR reaches the validator, the topology emitter, and the engine, all widths are concrete integers. Parameters appear nowhere downstream of the resolver. This is the same architectural choice the project already made for built-in macro expansion: do the work once at the language layer; keep downstream code seeing a flat IR.

**Slice and concat are engine kinds, not language primitives.** Users never write `slice(...)` or `concat(...)`. The language exposes the operations only through `[lo..hi]` and `{...}` syntactic forms. The resolver lowers each to an engine-level component. This isolates bit-range arithmetic in two small evaluators rather than threading it through every gate's evaluator.

**Component count vs. event count.** Parametric sub-circuits keep component count *independent of width* (e.g. `or[64]` is the same four components as `or[1]`, just with width-64 state slots). Slice and concat each add one component per use, but their evaluators are simple and the dedup check in `propagate()` keeps no-op events out of the queue. Net cost is dominated by the parametric design's wins, not the slice/concat overhead.

---

## Implementation Stages

Each stage is independently mergeable. The regression suite stays green at every stage. The intended order is back-to-front: engine first (riskiest, no user-visible change), then format, then the language surface. Stages 5, 6, 9, 10, and 11 are mutually independent once their prerequisites land; the rest form a linear chain.

```
       ┌──────────────────────┐
       │ S1  Engine bitwise   │
       └──────────┬───────────┘
                  │
       ┌──────────▼───────────┐
       │ S2  Topology v02     │
       └──────────┬───────────┘
                  │
       ┌──────────▼───────────┐
       │ S3  Grammar + AST    │
       └──────────┬───────────┘
                  │
       ┌──────────▼───────────┐
       │ S4  IR + resolver    │
       │     (literal widths) │
       └──┬────────────────┬──┘
          │                │
   ┌──────▼──────┐  ┌──────▼──────────────┐
   │ S5 Slice +  │  │ S6 Validator E014,  │
   │    concat   │  │     E015            │
   └──────┬──────┘  └──────┬──────────────┘
          │                │
       ┌──▼────────────────▼──┐
       │ S7 Parametric        │
       │    specialization    │
       └──────────┬───────────┘
                  │
       ┌──────────▼───────────┐
       │ S8 Macro migration   │
       └──────────┬───────────┘
                  │
   ┌──────────────┼──────────────┐
   │              │              │
┌──▼────┐    ┌────▼─────┐   ┌────▼──────┐
│S9 WASM│    │S10 Truth │   │S11 Preview│
│  API  │    │   table  │   │  + LED    │
└───────┘    └──────────┘   └───────────┘
                  │
       ┌──────────▼───────────┐
       │ S12 Documentation    │
       └──────────────────────┘
```

---

### Stage 1: Engine bitwise primitives

**Goal.** Make the engine accept width > 1 internally. No user-visible change.

**Files.**
* `lib/circuit.zig`:
  * `BitVecState`: add `bitAnd`, `bitOr`, `bitXor` (three-state bitwise ops; bits low if either operand bit is defined-low, high if both are defined-high, undefined otherwise). `flip` is already general.
  * `Pool`: drop the `width == 1` asserts on `init`, `read`, `write`. Add a non-1 storage path (one `u64` per `(value, defined)` slot for widths 2..=64).
  * `tierIndexForWidth`: stop panicking; return `width` as the tier index. Convert `tier1: Pool` into a lazily-initialized array (or `AutoHashMap(u8, Pool)`) indexed by tier.
  * `Circuit.createComponent(kind, width)`: thread width through; default to 1 in existing call sites.
  * `recalculateAndReschedule`: rewrite AND/NOT/wire/output_pin/led arms to use the new bitwise ops instead of `isHigh`/`isLow` predicates.

**Acceptance.**
* Every existing engine test passes byte-identical.
* New unit tests in `lib/circuit.zig` for AND/NOT/wire at width 2, 4, 8, 64.
* `zig build bench` shows no regression on width-1 corpora; record a new milestone for the lazy tier creation.

**Notes.** Lazy tier init matters because most circuits will only use a handful of widths (1, 4, 8, 16, 32, 64). Allocating 65 empty pools per `Circuit` would be wasteful; lazy init keeps single-bit circuits at one allocated pool.

---

### Stage 2: Topology format v02

**Goal.** Carry width in the topology binary. Format bump prepares for any subsequent IR change.

**Files.**
* `lib/topology/format.zig`: bump `VERSION` to `0x02`. `ComponentRecord` grows `width: u8`.
* `lib/topology/full_format.zig`: `FullComponentRecord` grows `width: u8`.
* `lib/topology/serializer.zig`, `full_serializer.zig`: emit the new byte.
* `lib/topology/full_decoder.zig`: read the new byte; reject `0x01` topologies with `error.UnsupportedVersion`.
* `lib/cli/inspect_dump.zig`: print width in the inspect output.

**Acceptance.**
* Round-trip tests at widths 1, 4, 8 pass.
* All existing `tests/fixtures/expected-inspect/` outputs regenerate with the new width column.
* Reading a `0x01` topology produces a clean error pointing at the version mismatch.

**Notes.** No backward-compat shim. The format is internal to a compiled artifact; bumping is the supported path.

---

### Stage 3: Grammar, AST, and translate for new syntax

**Goal.** Parser accepts every new syntactic form locked in the decision table. AST captures it. Nothing past the parser changes yet.

**Files.**
* `lib/grammar/proto-circ.peg`:
  * `Declaration`: allow `[Integer | Identifier]` after the type keyword.
  * `InputDecl`: allow `<Identifier>` before the pin name list (parameter introduction).
  * `PortRef`: extend with `[Integer]` index, `[Integer .. Integer]` slice, `{ PortRef (, PortRef)* }` concat.
  * Call site: allow `[Integer (, Integer)*]` for multi-parameter binding.
* `lib/parser/`: regenerate `parser.go` via langlang v0.0.12; recompile `parser.a` and `parser.h`.
* `lib/syntax/ast.zig`:
  * `Identifier` gets an optional `width: ?WidthSpec` where `WidthSpec` is `union { literal: u8, parameter: []const u8 }`.
  * `InputDecl.parameters: []const Identifier` for the `<W>` introductions.
  * `ComponentInstance.width_args: []const WidthSpec` for the `[N, M]` at the call site.
  * New `SignalSource` variants: `indexed`, `sliced`, `concat`.
* `lib/syntax/translate.zig`: produce the new shapes.

**Acceptance.**
* Parser unit tests for each new syntactic form (literal width, parametric introduction, index, slice, concat, multi-parameter call).
* Every existing fixture parses unchanged.
* AST snapshot tests under `tests/fixtures/expected-ast/` for the new forms.

**Notes.** Regenerating the Go parser is the only place this stage touches a non-Zig toolchain. Vendoring keeps regular contributors from needing langlang.

---

### Stage 4: IR + resolver for literal widths

**Goal.** Literal widths flow from AST to topology end to end. Primitive-only multi-bit circuits work (`input[4] a, b` → `and[4] g(...)` → `output[4] r(...)` → simulate). Parametric and slice/concat still placeholder-error.

**Files.**
* `lib/ir/types.zig`: add `width: u8` to `Component`, `InputPin`, `OutputPin`.
* `lib/ir/resolver.zig`: read width from the AST, default to 1 if omitted, error if a `[parameter]` reference is encountered (parametric specialization lands at stage 7).
* `lib/emit/`: thread width into the topology section emission.
* `lib/resolver/scan_imports.zig`, `resolve_bodies.zig`: pick up widths from imported sub-circuits.

**Acceptance.**
* New fixtures (`and_4bit_native.circ`, `not_8bit.circ`, etc.) compile, emit, simulate, and produce correct outputs.
* Every existing scalar fixture continues to work byte-identical in IR, topology, and simulation.
* IR snapshot tests pass.

**Notes.** This is the first stage with user-visible behavior. The existing `and_4bit.circ` fixture (which writes out four scalar `and` gates) stays as is; a sibling `and_4bit_native.circ` exercises the `and[4]` path and verifies identical truth-table output.

---

### Stage 5: Slice and concat at IR and engine

**Goal.** `a[lo..hi]` and `{a, b, ...}` work end to end. Engine grows two new component kinds.

**Files.**
* `lib/circuit.zig`:
  * Add `Component.Kind.slice` (with `from_lo: u8`, `from_hi: u8` metadata) and `.concat` (with operand-width list).
  * `recalculateAndReschedule` evaluates each: slice reads source bits and masks-and-shifts; concat reads each operand and assembles by shifting each into its position.
* `lib/topology/format.zig`: add `slice` and `concat` to `ComponentKind` enum (values 6 and 7).
* `lib/topology/full_format.zig`, `full_serializer.zig`, `full_decoder.zig`: serialize slice ranges and concat operand lists.
* `lib/ir/types.zig`: extend `Component.kind` for these.
* `lib/ir/resolver.zig`: when a `SignalSource` is `indexed`, `sliced`, or `concat`, synthesize the corresponding IR component and rewrite the connection to feed from it.
* `lib/validator/passes/port_validation.zig`: validate slice ranges in bounds; validate concat operand widths sum to the destination's expected width.

**Acceptance.**
* Slice fixtures: pulling bits 0..2 from a 4-bit bus into a width-2 gate.
* Concat fixtures: assembling four 1-bit inputs into a 4-bit bus.
* Composed fixtures: slice-then-concat round-trip returns the original value.
* Single-bit index `a[2]` is `a[2..3]` (width-1 slice); same engine kind.

**Notes.** Slice and concat are confined to lowered-only forms. Users never write `slice(...)` or `concat(...)` directly. The grammar exposes the operations only through `[lo..hi]` and `{...}`.

---

### Stage 6: Validator for E014 and E015

**Goal.** Width mismatches and "scalar sub-circuit invoked with `[N]`" produce clean diagnostics.

**Files.**
* `lib/validator/passes/width_match.zig` (new): walk every `Connection`, look up the source's output width and the destination's port-expected width; emit `E014` on mismatch with span info.
* `lib/validator/passes/sub_circuit_validation.zig`: detect `[N]` on a sub-circuit lacking `<W>` introductions; emit `E015` with a suggestion to add `<W>`.
* `lib/validator/codes.zig`: register `E014` ("width mismatch: source width X, destination expects Y") and `E015` ("sub-circuit `name` is not parametric; add `<W>` to make it so").
* `lib/validator/run.zig`, `run_project.zig`: register the new pass.

**Acceptance.**
* `tests/fixtures/circuits/E014_width_mismatch.circ` rejected with span pointing at the offending connection.
* `tests/fixtures/circuits/E015_scalar_subcircuit_widened.circ` rejected with the suggestion in the diagnostic body.
* Every existing fixture remains valid.

---

### Stage 7: Parametric specialization

**Goal.** `<W>` on a sub-circuit works. The resolver specializes a parametric body per call site, sharing specializations across identical bindings.

**Files.**
* `lib/ir/resolver.zig`: when an imported sub-circuit has parameters and the call site supplies `[N, M, ...]`, walk the sub-circuit body and substitute each parameter reference with its concrete value. Bindings positional, in introduction order. Missing `[N]` defaults all parameters to 1.
* `lib/resolver/resolve_bodies.zig`: cache specializations keyed by `(file, parameter-binding tuple)`; multiple call sites at the same widths share one specialization.
* `lib/syntax/ast.zig`: ensure parameter ordering is preserved through translation.
* `lib/validator/codes.zig`: register `E016` ("parameter count mismatch: sub-circuit declares N parameters, call site supplies M").

**Acceptance.**
* Single-parameter sub-circuit `or<W>` specializes correctly at width 1, 4, 8.
* Multi-parameter sub-circuit `mux<W,S>` accepts `mux[4, 2]` and specializes.
* Missing call-site `[N]` defaults all parameters to 1; existing scalar fixtures unchanged.
* Two call sites at identical widths share one cached specialization (verified by IR snapshot diff).
* Parameter-count mismatch emits E016.

**Notes.** Specialization is purely a resolver-time transform. The validator, topology emitter, and engine all see flat IR with concrete widths.

---

### Stage 8: Macro migration

**Goal.** Rewrite the five built-in macros with `<W>`. Every existing scalar caller produces byte-identical output.

**Files.**
* `lib/resolver/builtin_circ/or.circ`: rewrite with `input<W>` and `[W]` annotations.
* Same for `xor.circ`, `nand.circ`, `nor.circ`, `xnor.circ`.

**Acceptance.**
* Every existing scalar caller of these macros produces byte-identical IR and topology to before (verified by the regression suite).
* New multi-bit caller fixtures `or_4bit_macro.circ`, `xor_8bit_macro.circ` work end to end.
* The discipline rule (`<W>` always explicit, never elided) is upheld in the rewritten files.

**Notes.** Each rewritten macro should carry a top comment noting "parametric in width W (default 1)" so future readers see the convention even before seeing the syntax.

---

### Stage 9: WASM host API for multi-bit pins

**Goal.** `setPin` and `getOutputState` carry `(value, defined)` BigInt `u64` pairs.

**Files.**
* `lib/transport.zig`: encode `BitVecState` as two `i64`s in WASM exports (i64 maps to BigInt in JS).
* `lib/emit/runtime.zig`: update the WASM export signatures.
* `lib/emit/build_fn.zig`: update the generated host-side bindings.
* JS host examples in `example/` and `templates/` updated for the new signature.

**Acceptance.**
* WASM integration tests pass with BigInt args.
* Width-1 callers can pass `0n`/`1n` and read back BigInts (transparent migration).
* Documented call sequence: `setPin(id, 0b0101n, 0b1111n)`, settle via `run()`, `getOutputState(driver_id)` returns `{ value, defined }`.

---

### Stage 10: Truth table multi-bit support

**Goal.** Truth-table generator handles multi-bit pins and supports the `--truth-table-format` flag.

**Files.**
* `lib/truth_table/builder.zig`: iterate over `2^(sum of input widths)` combinations; render multi-bit columns. Cap at 16 total input bits with a clean error.
* `lib/truth_table/csv.zig`, `json.zig`, `markdown.zig`: render multi-bit values per the selected format.
* `lib/cli/args.zig`: add `--truth-table-format binary|hex|decimal` (default binary). Add `--truth-table-cap` override (max 24).

**Acceptance.**
* Truth tables for `and[4]` produce 256 rows with correct binary, hex, and decimal renderings.
* Cap exceeded yields a clean diagnostic; override flag works up to its max.
* Existing scalar truth-table fixtures unchanged.

---

### Stage 11: Preview and LED rendering

**Goal.** `--preview` handles multi-bit signals. LED renders as a numeric display by default with `--expand-display` for narrow buses.

**Files.**
* `lib/preview/`: render multi-bit signal labels (e.g. `a[4]` on pin labels, wire glyphs annotated with width).
* New display glyph type for `led[N]` numeric rendering.
* `lib/cli/args.zig`: add `--expand-display` flag.
* Renderer rule: if `--expand-display` and `N < 8`, draw N indicator LEDs in a row (LSB on the left); if `--expand-display` and `N >= 8`, fall back to numeric and emit a post-render warning.

**Acceptance.**
* Preview fixtures for multi-bit signals.
* `--expand-display` honored for N=4 (4 indicator glyphs), ignored for N=8 (numeric + warning).
* Existing scalar preview fixtures unchanged.

---

### Stage 12: Documentation pass

**Goal.** All docs reflect the new language. The decisions file is authoritative.

**Files.**
* `DOCS/decisions/language.md`: append a new section capturing every decision from the table.
* `DOCS/language.md`: rewrite §3 (declarations) and §4 (signals); add a new section on multi-bit wires (literal widths, parametric sub-circuits, slice/index/concat). Update §5 to note `wire[N]`.
* `DOCS/simulation-engine.md`: remove the "width=1 only" caveats; document slice and concat as engine kinds.
* `DOCS/circuit-format.md`: bump format version reference; document the width byte.
* `DOCS/wasm-api.md`: document the BigInt API.
* `DOCS/preview.md`: document `--expand-display` and multi-bit rendering conventions.
* `DOCS/getting-started.md`: add at least one multi-bit example.

**Acceptance.**
* Existing doc checks pass.
* `getting-started.md` walks a new user through a multi-bit example.

---

## Risks and Mitigations

**Engine perf at width=1.** Bitwise ops must reduce to identical fast paths at width 1. The `propagate()` dedup check on `BitVecState.equals` is the load-bearing optimization for the truth-table corpus. Mitigation: the bench suite runs at every stage; any regression on the and/xor/adder corpora blocks the stage from landing.

**Parser regression on existing fixtures.** Grammar changes touch the most-tested file in the project. Mitigation: every existing `.circ` fixture must parse byte-identically (no AST-shape changes for files that don't use new syntax). The langlang vendored parser provides a hard checkpoint.

**Specialization combinatorial explosion.** A user who calls `or[4]`, `or[5]`, `or[6]`, ... at many widths produces many specializations. Mitigation: cache by `(file, binding tuple)` so duplicate widths share. Warn at 32 unique specializations per import to flag accidental over-instantiation.

**Topology format breakage.** Bumping to v02 means any cached `.wasm` artifact compiled with v01 cannot be read by tooling that expects v02 introspection. Mitigation: the format is internal to the compiler-runtime contract; the only consumer is `circ-compile` itself, so the bump is a clean break with no migration story needed.

**Slice/concat as engine kinds.** Two new component kinds grow the engine surface. Mitigation: confine them to lowered-only forms (no direct user syntax for `slice(...)`), so the surface area is hidden from users and tests target them through `[lo..hi]` / `{...}`.

**Multi-bit pin host API.** BigInt is required across the WASM boundary. JS environments that predate Node 10.4 or that block BigInt (rare today) cannot drive the new API. Mitigation: this is acceptable for v1; if a legacy environment becomes a real concern, a lo+hi i32-pair adapter can be added as a separate shim.

---

## Verification Approach

Every stage must keep `zig build test` green. Every stage that touches the topology format must regenerate `tests/fixtures/expected-*` and commit the result. Every stage that changes parser output must run the existing parser snapshot tests.

Three smoke tests run end to end at every stage:

1. **Scalar regression.** `and_two_inputs.circ`, `chain.circ`, `clean_gated_feedback.circ` produce byte-identical IR and simulation outputs from stage 0 to stage 12.
2. **Multi-bit primitive.** A new fixture `and_4bit_native.circ` (using `and[4]`, `input[4]`) is added in stage 4 and must keep passing through every subsequent stage.
3. **Parametric macro.** A new fixture `or_4bit_macro.circ` (using `or[4]`) is added in stage 8 and must keep passing through stages 9 to 12.

---

## Effort Summary

| Stage | Estimated effort | Why |
| - | - | - |
| 1 Engine bitwise | Heavy | Touches the hot path; needs careful perf verification |
| 2 Topology v02 | Light | Mechanical format bump |
| 3 Grammar + AST | Heavy | Largest surface-area diff; parser regeneration |
| 4 IR + resolver (literal widths) | Medium | New fields throughout; clear shape |
| 5 Slice + concat | Medium | Two new engine kinds plus resolver lowering |
| 6 Validator E014/E015 | Light | New pass, well-isolated |
| 7 Parametric specialization | Heavy | Substitution and caching logic |
| 8 Macro migration | Light | Five small files |
| 9 WASM host API | Medium | Cross-boundary API change |
| 10 Truth table | Light | Builder extension and one CLI flag |
| 11 Preview + LED | Medium | New glyph type and flag handling |
| 12 Documentation | Medium | Five docs to update consistently |

Total: 12 mergeable PRs. Heaviest at stages 1, 3, 7. Lightest at 2, 6, 8, 10. The project's existing benchmark and snapshot infrastructure provides the verification spine throughout.
