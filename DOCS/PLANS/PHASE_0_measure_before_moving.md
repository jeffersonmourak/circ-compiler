# Phase 0 — Measure before moving

> **Dependencies:** None. This is the first phase of the layout-rewrite initiative (`DOCS/PLANS_PROMPT.md`). Every later phase is judged by the numbers this phase puts on record.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` decisions 10, 12 and 13, the *Build and goldens* traps, and `CLAUDE.md` in full. **The layout algorithm does not change in this phase** — `lib/preview/layout/{columns,rows,place,route}.zig` are not edited, and every existing golden under `tests/fixtures/preview/` stays byte-identical. The attempt's harness is read with `git show layout-v1-attempt:<path>` (this repository, tip `14b43f1`; the renderer's branch of the same name is at `3f16380`), never by checking that branch out. Apply `build.zig` hunks without reformatting (the attempt's diff also stripped 17 lines of trailing whitespace — do not carry that). Slice 5 lives in `/Users/jeffersonmourak/circus/circ-renderer` and **cannot start until the human has reset `host-pin-api` to `62d0def`** (decision 13; the backup branch `layout-v1-attempt` already exists there). `zig build test` after every slice; `zig build test-all` before every commit that touches `build.zig` or `lib/`.

## Goal

After this phase a maintainer can run `zig build test` and get, for every fixture the CLI can preview, a checked-in JSON `LayoutGrid` (`tests/fixtures/preview/layouts-json/<name>.<mode>.layout.json`) produced through the exact path `circ-compile --preview` and the site's `circ_preview` take, plus one table (`tests/fixtures/preview/layout-invariants.golden`) that says per fixture-mode how many wire cells sit inside a box (I0), how many cells two different nets share colinearly (I1), how many cells unrelated nets meet at other than a clean perpendicular crossing (I2), how many nets are not a tree from their source (I3), and how many crossings, bends and straight wires the layout has — with today's algorithm's numbers pinned, `and_of_not opaque` showing a non-zero I1, and `UPDATE_GOLDENS=1 zig build test` provably regenerating both (the run steps are `has_side_effects`). In `circ-renderer`, on a branch reset to the sha the site pins, `bun test` reads a vendored subset of the same JSON and reports which fixture-modes the TypeScript port already matches and which it does not, and computes the same invariant counts over its own `buildLayout`. Nothing a reader sees changes.

## Scope

**In scope:**
- `lib/preview/dump_json.zig` revived verbatim from the attempt (the contract of decision 12), with its two inline tests.
- `lib/preview/layout/invariants.zig`: a pure, render-free checker over `LayoutGrid` producing the report of decision 10, with unit tests on hand-built grids for every counter.
- `tests/preview/corpus.zig`: the corpus walk — every `tests/fixtures/circuits/*.circ` and every `tests/fixtures/projects/*/root.circ`, sorted by path, that the library front end previews on the `.project` route with no hard error; opaque mode always, expanded mode only when the opaque grid contains a subcircuit box.
- `tests/preview/layout_conformance_test.zig`: one JSON golden per corpus fixture-mode, and the invariants table golden with every fixture-mode listed (zero rows included) plus totals and the corpus count.
- `build.zig`: the two module blocks from the attempt, both run steps `has_side_effects = true`.
- `circ-renderer` on the reset branch: `test/layout-parity.test.ts` and `test/layout-invariants.test.ts` over a vendored subset (`test/fixtures/layouts/*.layout.json` + the matching `.wasm`), a `test/fixtures/layouts/MANIFEST.md` naming the compiler commit both halves came from.
- `DOCS/decisions/preview-layout.md` created with the entries this phase exercises and registered in `DOCS/decisions/index.md`; `DOCS/STATUS.md` created by slice 1.

**Explicitly deferred:**
- Any change to placement or routing (Phases 1–3); any change to render.
- A divergence *ledger* in the playground-plan sense: the renderer test pins which fixtures match today and that the rest differ, and that list is deleted in Phase 4 rather than maintained.
- Vendoring the whole corpus into the renderer (175 `.wasm` files); the subset is the fixtures that have a render golden today plus the attempt's twelve, and the manifest says so.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| `preview_dump_json` | `lib/preview/dump_json.zig` | `dumpLayoutJson(writer, grid)`: the camelCase common-subset JSON of a `LayoutGrid` (decision 12). Revived from `git show layout-v1-attempt:lib/preview/dump_json.zig` unchanged. |
| `preview_layout_invariants` | `lib/preview/layout/invariants.zig` | `check(arena, grid) !Report`: the render-free invariant counter and the extra measurements. |
| test helper | `tests/preview/corpus.zig` | `walk(arena) ![]const Entry`: the sorted, previewable fixture-mode list built through `libcirc.frontend.run(.project)`. |
| test | `tests/preview/layout_conformance_test.zig` | The JSON goldens over the corpus and the invariants table golden. |
| goldens | `tests/fixtures/preview/layouts-json/*.layout.json`, `tests/fixtures/preview/layout-invariants.golden` | Generated by `UPDATE_GOLDENS=1 zig build test`. |
| docs | `DOCS/decisions/preview-layout.md`, `DOCS/STATUS.md` | The decisions ledger for this initiative; the status log. |
| renderer test | `circ-renderer/test/layout-parity.test.ts`, `test/layout-invariants.test.ts`, `test/fixtures/layouts/*.layout.json`, `test/fixtures/layouts/MANIFEST.md`, `test/fixtures/*.wasm` (new ones only) | The TypeScript side of the contract. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| build | `build.zig` | Add `preview_dump_json_mod` + its test step after `preview_dump_mod`; add `preview_layout_conformance_mod` after `run_preview_layout_integration_tests` with imports `libcirc` (`fe.libcirc`), `layout`, `render` (`fe.preview_render`), `preview_dump_json`, `invariants`, `corpus`, `golden`; both run steps `has_side_effects = true`. |
| build | `build/frontend_modules.zig` | Register `lib/preview/layout/invariants.zig` as `preview_layout_invariants` importing `layout`, and expose it on the struct so `build.zig` and the tests can import it. |
| docs | `DOCS/decisions/index.md` | Register `preview-layout.md` under Topics. |
| renderer | `circ-renderer/README.md` | One paragraph pointing at `test/fixtures/layouts/MANIFEST.md`. |

**New dependencies:** None.

## Data & State

```zig
// lib/preview/layout/invariants.zig
pub const Report = struct {
    body: u32,      // I0: wire cells strictly inside a component body (port cells are outside boxes)
    shared: u32,    // I1: cells where ≥2 nets cover it with the same orientation
    junction: u32,  // I2: cells where ≥2 nets meet and it is not a clean perpendicular crossing
    tree: u32,      // I3: nets whose cells are not one connected set containing the source cell,
                    //     or whose wires have a segment chain that is not contiguous/axis-aligned
    crossings: u32, // clean perpendicular crossings between two different nets
    bends: u32,     // corners summed over all wires (segments.len - 1 per wire)
    straight: u32,  // wires with exactly one segment
    wires: u32,
};

/// A net is identified by (src_id, src_port). A cell claim records the net,
/// the wire index and the orientation of the segment covering it, and whether
/// the wire corners or terminates at that cell (segment endpoint that is not
/// shared with the next segment's start, or the first/last cell).
pub fn check(arena: std.mem.Allocator, grid: layout.LayoutGrid) !Report;
```

Cell classification, applied to every cell covered by at least two different nets: if every claim has the same orientation → `shared` (I1). Otherwise, if exactly two nets are present, each with one claim, both claims pass straight through (neither corners nor terminates there) and their orientations differ → `crossings`. Anything else → `junction` (I2). A cell claimed by one net only, whatever its shape, is never counted (fan-out taps are a net's own business).

```zig
// tests/preview/corpus.zig
pub const Mode = enum { opaque, expanded };
pub const Entry = struct { name: []const u8, path: []const u8, mode: Mode };
/// Sorted by (path, mode). `name` is the file stem for circuits and
/// `<dir>` for projects. Failures on the .project route are skipped and counted.
pub const Walk = struct { entries: []const Entry, skipped: u32 };
pub fn walk(arena: std.mem.Allocator) !Walk;
pub fn buildGrid(arena, path, expand_macros: bool) !layout.LayoutGrid; // frontend.run(.project) → buildTopology → buildLayout
```

The invariants golden format, one line per fixture-mode, all of them, sorted as the walk sorts:

```
# corpus layout invariants — every previewable fixture-mode; regenerate with UPDATE_GOLDENS=1 zig build test
# I0 body cells, I1 shared cells, I2 junctions, I3 non-tree nets, X crossings, B bends, S straight wires of W wires, size WxH
and_of_not opaque I0=0 I1=… I2=… I3=0 X=… B=… S=…/… size=…x…
…
# totals: fixture-modes=… skipped=… I0=… I1=… I2=… I3=… X=… B=… S=…/…
```

JSON golden path: `tests/fixtures/preview/layouts-json/<name>.<mode>.layout.json` where `<name>` is the entry's `name` (projects use their directory name; a circuit and a project with the same stem would collide — the walk asserts uniqueness).

`RoutedWire`, `LayoutGrid` and the JSON shape are inherited unchanged (decision 12; `lib/preview/layout.zig`).

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. The corpus walk runs inside one test with one arena per fixture-mode so memory is released between fixtures (the attempt's pattern).

## Persistence & I/O

Test-time only: reading `tests/fixtures/circuits/` and `tests/fixtures/projects/` via `std.fs.cwd()` (sorted after iteration — directory order is not stable), reading and, under `UPDATE_GOLDENS=1`, writing the goldens through `tests/helpers/golden.zig` (`makePath` on the parent). The renderer reads its vendored files with `node:fs`. No network, no other I/O.

## Slices

The execution agent implements this phase one slice at a time, committing after each under the plan prompt's waiver.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Revive the JSON dump and start the log | `lib/preview/dump_json.zig` verbatim from the attempt, its `build.zig` module + test step, `DOCS/STATUS.md` created, `DOCS/decisions/preview-layout.md` created with "The parity contract is a JSON projection" and registered. | `zig build test` runs `dump_json: emits the contract shape and parses back as JSON` and `dump_json: empty grid and escaped names`; `git diff --stat tests/fixtures` empty. |
| 2 | The invariant checker | `lib/preview/layout/invariants.zig` with `Report` and `check`, registered in `build/frontend_modules.zig`, unit tests on hand-built grids. | Nine unit tests (table below) green; a hand-built copy of `and_of_not`'s shared cell reports `shared == 1`. |
| 3 | The corpus walk and the conformance goldens | `tests/preview/corpus.zig`, `tests/preview/layout_conformance_test.zig` (JSON goldens only), `build.zig` wiring with `has_side_effects`, every `layouts-json/*.layout.json` generated and committed. | `UPDATE_GOLDENS=1 zig build test` writes N files, a second clean `zig build test` passes, deleting one golden fails with `GoldenFixtureMissing`, and touching the test binary's inputs is not needed for a regeneration (negative proof: with `has_side_effects` removed, a deleted golden is not recreated on the second run). |
| 4 | The invariants table | `corpus_layout_invariants` test and `tests/fixtures/preview/layout-invariants.golden`; the decision entry "The corpus invariants are the measurement of record". | The golden lists every fixture-mode with `and_of_not opaque` at `I1 > 0`; totals line present; the count of fixture-modes equals the number of JSON goldens. |
| 5 | The renderer harness on the reset branch | On `host-pin-api` at `62d0def`: `test/layout-parity.test.ts`, `test/layout-invariants.test.ts`, vendored subset + `MANIFEST.md`, README paragraph. **Hard stop before this slice** until the human confirms the reset. | `bun test` and `bun run typecheck` green in the renderer; `MATCHES_TODAY` non-empty and every other vendored fixture-mode asserted to differ; TS invariant counts pinned per vendored fixture-mode. |

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `dump_json: emits the contract shape and parses back as JSON` | `lib/preview/dump_json.zig` | Exact text for a two-component, one-wire grid; `std.json` parses it back. |
| `dump_json: empty grid and escaped names` | `lib/preview/dump_json.zig` | Empty arrays render `[]`; quotes, backslashes and tabs are escaped. |
| `invariants: empty grid reports zeros` | `invariants.zig` | All counters zero, `wires == 0`. |
| `invariants: a single straight wire is straight and clean` | `invariants.zig` | `straight == 1`, `bends == 0`, everything else zero. |
| `invariants: a wire through a box body counts body cells` | `invariants.zig` | `body` equals the number of cells inside the box, port cells excluded. |
| `invariants: two nets on one row share cells` | `invariants.zig` | `shared` equals the overlap length; `junction == 0`, `crossings == 0`. |
| `invariants: a perpendicular pass-through is a crossing, not a junction` | `invariants.zig` | `crossings == 1`, `junction == 0`, `shared == 0`. |
| `invariants: a corner on another net's cell is a junction` | `invariants.zig` | `junction == 1`, `crossings == 0`. |
| `invariants: three nets meeting is a junction` | `invariants.zig` | `junction == 1`. |
| `invariants: fan-out sharing its own trunk is not shared` | `invariants.zig` | Two wires of one net over the same cells: `shared == 0`, `junction == 0`, `tree == 0`. |
| `invariants: a disconnected net and a broken chain count as non-tree` | `invariants.zig` | A wire whose second segment does not start where the first ends → `tree == 1`; a wire whose cells do not include its source cell → `tree == 1`. |
| `corpus: the walk is sorted, unique and non-empty` | `tests/preview/corpus.zig` | Entries sorted by `(path, mode)`, names unique, `and_of_not` present in opaque only, `builtin_xor` present in both modes, `E001_undeclared` absent. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `layout_conformance_corpus` | `tests/preview/layout_conformance_test.zig` | For every walk entry the JSON dump equals its golden; on mismatch prints the fixture-mode name before returning the error. |
| `corpus_layout_invariants` | same file | The invariants table equals `tests/fixtures/preview/layout-invariants.golden`; on mismatch prints the current table. |
| `layout parity` (TS) | `circ-renderer/test/layout-parity.test.ts` | Every vendored fixture-mode in `MATCHES_TODAY` equals its golden after projection; every other vendored fixture-mode differs (so a convergence is loud). |
| `layout invariants` (TS) | `circ-renderer/test/layout-invariants.test.ts` | The TS port's I0–I3 over every vendored fixture-mode equal a pinned table in the test file. |

Run command: `zig build test` (and `UPDATE_GOLDENS=1 zig build test` to regenerate); renderer: `cd /Users/jeffersonmourak/circus/circ-renderer && bun test && bun run typecheck`.

## Open Questions / Spikes

- `TODO(phase0)`: the renderer reset (decision 13) is the human's; slice 5 waits on it.
- `TODO(phase0)`: the corpus exclusion rule is "no hard error on the `.project` route"; slice 3 records the resulting fixture-mode count and the skipped count in STATUS so a corpus change is visible later. Project roots that need an import outside their directory are expected to be skipped; the spike lists them.
- `TODO(phase0)`: whether `alu_4bit` and the N-bit adders (the largest layouts) make the JSON goldens unwieldy — slice 3 reports the largest golden's size; if any exceeds 200 KB the spike proposes an exclusion by size rather than by name, argued in STATUS.
