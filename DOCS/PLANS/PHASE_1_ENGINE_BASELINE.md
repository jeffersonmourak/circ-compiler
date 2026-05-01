# Phase 1 — Engine Baseline

## Goal

Bring `lib/circuit.zig` up to the contract the compiler will emit against by adding the missing `output_pin` primitive. After this phase, the engine implements the full primitive set the compiler depends on: `input_pin`, `output_pin`, `not`, `and`, `led`, `wire`.

This phase is intentionally narrow. Existing primitives (`input_pin`, `not`, `and`, `led`, `wire`) are not retroactively backfilled with new tests — they are assumed correct based on existing behaviour. Audit work on them is out of scope for v0.

## Scope

In scope:

- Add `output_pin` to the `Kind` union in `lib/circuit.zig`.
- Implement its propagation behaviour as a pass-through (input drives output, after wire-equivalent delay).
- Add named port constants (`in`, `out`).
- Wire `output_pin` into the integer-`Kind` mapping in `lib/wasm.zig` so the existing dynamic API can construct one (kind id picked next in sequence after the current set).
- Extend `lib/transport.zig`'s state encoding to recognise `output_pin` so the dynamic snapshot path stays correct.
- Unit tests covering pass-through behaviour, propagation timing, and snapshot encoding for the new primitive.

Out of scope:

- New tests for existing primitives. The engine is trusted to be correct on what it already supports.
- TypeScript SDK updates (`src/index.ts`). The SDK doesn't need `output_pin` until the compiled-artifact runtime ships; deferred to whichever later phase consumes it.
- Any compiler-side work. The compiler does not exist yet beyond the WIP parser scaffolding.
- Changes to the introspection/snapshot format used by *compiled* artifacts. The compiled-artifact snapshot path is built fresh in Phase 4 and does not reuse `lib/transport.zig`.

## Architectural anchors recap

- The engine knows nothing about source files, hierarchy, or compilation. `output_pin` is a runtime primitive; its role as a sub-circuit interface marker is a Phase 4+ concern, not visible here.
- `output_pin` is a pass-through with both `in` and `out` ports — it is *not* a sink like `led`. (See the recurring-traps section of `DOCS/PLANS_PROMPT.md`.)
- All allocations go through the project's arena allocator.

## Delay choice

`output_pin` uses the **wire delay** (`WIRE_DELAY = 1`), not the gate delay. Rationale: it is structurally a pass-through, semantically equivalent to a named wire. Treating it as a gate (delay 5) would surprise users who expect their declared outputs to settle as fast as a wire.

This decision is local to Phase 1 and may be revisited if the compiler ever needs different timing for output pins in compiled artifacts.

## Slices

Each slice is the smallest reviewable unit. Land one slice per session. Do not start the next slice until the previous is committed.

### Slice 1.1 — Type and constants only (no behaviour)

**What ships.** The `Kind` union in `lib/circuit.zig` gains an `output_pin: struct { inputs: PortMap }` variant. New port-name constants for the variant. The `lib/wasm.zig` `Kind`-mapping table gains an entry assigning the next sequential numeric kind id to `output_pin`.

The build compiles. No new behaviour — `recalculateAndReschedule` does not yet handle the new variant (a `switch` arm returns without doing anything, or panics in debug — pick whichever the existing engine code style favours; if other unhandled variants panic, this one panics too).

**Tests.** A single compile-time test asserting the variant exists and constructs cleanly. No behavioural assertions yet.

**Files touched.** `lib/circuit.zig`, `lib/wasm.zig`.

**Why this slice exists alone.** Adding a tagged-union variant in Zig has compile-time consequences on every `switch` over the union. Landing the variant first surfaces every `switch` that needs an `output_pin` arm before behaviour is added.

### Slice 1.2 — Pass-through behaviour and propagation

**What ships.** `recalculateAndReschedule` in `lib/circuit.zig` learns to evaluate `output_pin`: read the `in` port, set the output state, schedule the change at `current_time + WIRE_DELAY` if the output differs from the current state. Connection wiring (`connect`) needs no special case — `output_pin`'s `inputs` map participates in the same `PortMap` machinery as every other gate.

**Tests.** Add `test "output_pin: passes input through"` covering:

- `low` input → `low` output after one wire delay.
- `high` input → `high` output after one wire delay.
- `undefined` input → `undefined` output (nothing scheduled).
- Transition: input changes from `low` to `high`, output settles after delay.
- Chained: two `output_pin`s in series propagate correctly with cumulative delay.

Tests live as `test "..."` blocks at the bottom of `lib/circuit.zig`, matching the existing engine test convention. If the engine has no existing test convention, create one — `test "<primitive>: <behaviour>"`.

**Files touched.** `lib/circuit.zig`.

### Slice 1.3 — Snapshot encoding

**What ships.** `lib/transport.zig`'s `EncodedState` writer recognises `output_pin` and emits the correct kind byte. The `Kind` enum mapping in `transport.zig` (or wherever the kind-to-byte mapping lives) gains the new variant.

**Tests.** Add `test "transport: encodes output_pin state"` constructing a one-component circuit (single `output_pin`, no inputs), reading `encodeState` output, asserting the produced bytes match the expected layout (state byte, kind byte, id bytes per the existing 9-byte format).

**Files touched.** `lib/transport.zig`.

## Definition of done for Phase 1

- All three slices committed.
- `zig build test` passes.
- `lib/wasm.zig` exports the new kind id (the dynamic API can construct an `output_pin` from JS — though no JS caller does so yet).
- The engine's primitive set matches what the compiler will emit against in Phase 4: `input_pin`, `output_pin`, `not`, `and`, `led`, `wire`.

## Open questions to resolve at slice time

- The exact numeric `Kind` id assigned to `output_pin` in `lib/wasm.zig`. Pick the next sequential id; the existing TypeScript SDK enum is *not* updated in this phase, so id stability across a future SDK update is not a concern yet.
- Existing engine code style for tests (file location, naming). If the engine has no tests today, this phase establishes the convention used by later phases.

## Notes for the next phase

Phase 2 (parser & AST/IR) does not depend on this phase's runtime behaviour — it depends only on the *existence* of the `output_pin` primitive in the engine's vocabulary, so its semantic validator (Phase 3) can recognise `output` declarations as valid. The behavioural correctness of `output_pin` is exercised end-to-end in Phase 4 when the first compiled artifact runs.
