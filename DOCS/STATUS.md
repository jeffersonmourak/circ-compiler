# Implementation Status

## 2026-05-06 — Phase 0 — Slice 1: `min` placeholder rename

**What shipped:** Renamed the static `topology_blob` marker emitted by `circ-compile` from `"debug-paths-v1"` to `"circ.topology.v0.min"`. The export `getTopology()` mechanism is unchanged; only the marker string content moved. This establishes the `circ.topology.v0.{min,full}` naming axis in the codebase ahead of slice 2's IR work and slice 3+4's `full` payload.

**Files touched:** `lib/emit/main.zig`, `lib/emit/project.zig`, `tests/emit/full_emit_test.zig`, plus 9 golden fixtures under `tests/fixtures/expected-zig/` (`anonymous_nested.zig`, `empty_ish.zig`, `and_two_inputs.zig`, `projects/passthrough_chain/main.zig`, `projects/same_name_half_adder/main.zig`, `projects/diamond/main.zig`, `projects/deep_chain/main.zig`, `projects/nested_invert/main.zig`, `projects/and_pair/main.zig`).

**Tests:** added `emit topology_blob marker is circ.topology.v0.min` (focused marker assertion in `tests/emit/full_emit_test.zig`); ran `zig build test`, result pass.

**Next slice:** Phase 0 Slice 2 — extend the IR with `macro_origin: []const MacroFrame` chains in `lib/ir/types.zig` and thread provenance through `lib/syntax/translate.zig` and `lib/ir/resolver.zig`.

**Notes:** The TODO(phase0) for slice 1 ("confirm `getTopology()` is the only consumer") is resolved: the placeholder string lives in two emit-side sites (`lib/emit/main.zig:59`, `lib/emit/project.zig:736`) and is golden-locked in 9 fixture files — no parsers consume the literal value, only golden tests assert it. Bulk perl rewrite handled all 11 sites in lockstep; the existing `full emitter fixture files` test would have failed loudly if any site drifted, which makes the rename self-checking.
