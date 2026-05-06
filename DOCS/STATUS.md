# Implementation Status

## 2026-05-06 — Phase 0 — Slice 1: `min` placeholder rename

**What shipped:** Renamed the static `topology_blob` marker emitted by `circ-compile` from `"debug-paths-v1"` to `"circ.topology.v0.min"`. The export `getTopology()` mechanism is unchanged; only the marker string content moved. This establishes the `circ.topology.v0.{min,full}` naming axis in the codebase ahead of slice 2's IR work and slice 3+4's `full` payload.

**Files touched:** `lib/emit/main.zig`, `lib/emit/project.zig`, `tests/emit/full_emit_test.zig`, plus 9 golden fixtures under `tests/fixtures/expected-zig/` (`anonymous_nested.zig`, `empty_ish.zig`, `and_two_inputs.zig`, `projects/passthrough_chain/main.zig`, `projects/same_name_half_adder/main.zig`, `projects/diamond/main.zig`, `projects/deep_chain/main.zig`, `projects/nested_invert/main.zig`, `projects/and_pair/main.zig`).

**Tests:** added `emit topology_blob marker is circ.topology.v0.min` (focused marker assertion in `tests/emit/full_emit_test.zig`); ran `zig build test`, result pass.

**Next slice:** Phase 0 Slice 2 — extend the IR with `macro_origin: []const MacroFrame` chains in `lib/ir/types.zig` and thread provenance through `lib/syntax/translate.zig` and `lib/ir/resolver.zig`.

**Notes:** The TODO(phase0) for slice 1 ("confirm `getTopology()` is the only consumer") is resolved: the placeholder string lives in two emit-side sites (`lib/emit/main.zig:59`, `lib/emit/project.zig:736`) and is golden-locked in 9 fixture files — no parsers consume the literal value, only golden tests assert it. Bulk perl rewrite handled all 11 sites in lockstep; the existing `full emitter fixture files` test would have failed loudly if any site drifted, which makes the rename self-checking.

**Reframing (2026-05-06, post slice-2):** Slice 1's commit `04422b4` renamed an *unrelated* runtime-export placeholder (`topology_blob` returned via `getTopology()` — a static string baked into the runtime WASM, separate from the offline `circ.topology` custom section). The original Phase 0 spec had conflated these two things; the spec was rewritten in commit `f0efe23` to disentangle them. Slice 2 (commit below) is the actual section-name rename the original "min" intent referred to. Slice 1's cleanup remains useful and stands as-committed; this note is here so a future reader mapping slice numbers to commits doesn't get confused.

## 2026-05-06 — Phase 0 — Slice 2: rename custom section to `circ.topology.v0.min`

**What shipped:** Renamed the WASM custom section emitted by `lib/topology/section_writer.zig` from `"circ.topology"` to `"circ.topology.v0.min"`. The section's payload bytes are unchanged — only its identifier on the `circ.topology.v0.*` versioned axis is being established. This is what the original Phase 0 "rename existing min" intent referred to (now correctly disentangled from the slice 1 placeholder rename).

**Files touched:** `lib/topology/section_writer.zig` (constant `SECTION_NAME`, comments, hardcoded byte counts in the `custom section bytes are correct` test); `tests/e2e/section_writer_fixtures_test.zig`, `tests/e2e/serializer_fixtures_test.zig`, `tests/e2e/cli_e2e_test.zig`, `tests/e2e/topology_protocol_test.zig` (Zig literals + JS section-name strings in WebAssembly.Module.customSections calls).

**Tests:** existing `section_writer: custom section bytes are correct` updated for new byte counts (1 + 20 + 9 = 30 body, name_len = 20, payload offset = section_start + 23); ran `zig build test`, result pass.

**Next slice:** Phase 0 Slice 3 — `circ.topology.v0.full` schema (new `lib/topology/full_format.zig`) + encoder/decoder over hand-built structs (no IR walk yet).

**Notes:** Blast radius was 14 sites across 5 files: 1 constant + 3 comments + 4 test-byte-counts + 6 e2e test references (mix of Zig literals and JS section-name strings inside Zig multiline string blocks). Used `perl -pi -e` with a negative-lookahead regex `(?!\.v0)` for the e2e files to avoid double-replacing on a hypothetical re-run; the lib changes were targeted Edits because byte-count constants needed individual updating. The TODO(phase0) about external consumers reading the section name literally is left open — the user's pre-1.0 stance applies, but if a downstream tool turns out to grep `"circ.topology"`, the rename will surface in a follow-up rather than a compat shim.

## 2026-05-06 — Phase 0 — Slice 3: `circ.topology.v0.full` schema + encoder + decoder

**What shipped:** New `lib/topology/full_format.zig` defining `FULL_MAGIC = "CIRF"`, `FULL_VERSION = 0x01`, in-memory types `OriginFrame`, `FullComponentRecord`, `FullTopology` (with `deinit`), and reusing `format.ComponentKind` / `format.PortName` / `format.ConnectionRecord`. New `lib/topology/full_serializer.zig` exposing `pub fn encode(allocator, topology) ![]u8` operating over a hand-built `FullTopology` (no IR walk yet — that's slice 4). New `lib/topology/full_decoder.zig` exposing `pub fn decode(allocator, bytes) !FullTopology` with a small `Cursor` helper for bounded byte reads. New `tests/topology/full_roundtrip_test.zig` exercising encoder + decoder together. Four new module registrations in `build.zig`.

**Files touched:** `lib/topology/full_format.zig` (new), `lib/topology/full_serializer.zig` (new), `lib/topology/full_decoder.zig` (new), `tests/topology/full_roundtrip_test.zig` (new), `build.zig` (4 new module registrations between `section_writer_tests` and `section_writer_fixtures_tests_mod`).

**Tests:** added `full_format: magic and version are stable`, `full_format: kind values mirror min payload`, `full_encode_empty: locks the wire format` (golden 13 bytes), `full_encode: single component with no origin emits expected layout` (golden 28 bytes with offset assertions), `full_decode_rejects_bad_magic`, `full_decode_rejects_unknown_version`, `full_decode: empty payload round-trips`, `full_decode_rejects_truncated_input`, `full_encode_decode_roundtrip_simple` (3 components, 2 connections), `full_encode_decode_roundtrip_with_origin` (single-frame and nested-frame origin chains, including empty-alias inner frame). Ran `zig build test`, result pass.

**Next slice:** Phase 0 Slice 4 — IR-walking serializer. Mirror `serializer.serializeProjectFull`'s recursion in `lib/topology/full_serializer.zig` with an added `pub fn serializeProjectFull(allocator, project) ![]u8` that threads an `OriginFrame` stack and records names while walking.

**Notes:** Hit one Zig style error during first build — `var components/origin/connections` for slices that aren't mutated through their headers should be `const`. Fixed by changing the three slice-binding declarations. The decoder's errdefer chain handles partial-allocation cleanup correctly (built counters for components and origin frames let errdefer free only what was successfully constructed). The roundtrip-with-origin test deliberately includes an empty-alias inner frame to lock that anonymous-nested-macro round-trips byte-identically — that case is what the Phase 2 expanded-mode renderer will need to display correctly.
