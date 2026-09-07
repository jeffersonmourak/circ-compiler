# Phase 0 — Language Front Door

> **Dependencies:** None (first phase of the Native Memories initiative; see `DOCS/PLANS_PROMPT.md`).
> **Warnings:** Zero changes to `lib/grammar/proto-circ.peg` — the declaration shape already parses (verified empirically: `rom mem[8, 4](addr = pc)` yields `Component type=rom instance=mem` with `width_args=[8, 4]`, then `E001`). Do **not** add `rom`/`ram` as literals to `ComponentType`: the grammar has no word-boundary guard after literals, so a literal `rom` would split `romx r(...)` into `rom` + `x` exactly as `nots n1(...)` splits into `not` + `s` today. Adding the IR variant is an all-subsystems compile break (Zig exhaustive switches); every arm listed under *File & Module Topology* must land in the same slice or the tree does not build.

## Goal

A user can write `rom code[8, 4] (addr = pc)` or `ram data[8, 4] (addr = a, din = d, we = w, clk = clk)` and the compiler *understands* it: `--inspect` prints the component as `kind=rom[W=8,A=4]` with its `width_args`, `--analyze` reports a `rom`/`ram` symbol with hover `rom[8,4] code` (the `E001` squiggle disappears), and the validator enforces the memory contract — exactly two width arguments (`E017`), widths in range (`E018`), the right port set (`E002`/`E004`), per-port widths (`E014`), and reservation of the two names (`E006` for instances and inputs, `E011` for import aliases). Every artifact-producing mode (`-o`, `--emit-zig`, `--preview`, `--truth-table`, `--sim`) refuses a memory-bearing source with `rom/ram are not yet supported in this mode` and exit 1, producing no partial artifact. Parametric widths (`ram m[W, A]` inside a `<W>`/`<A>` sub-circuit, instantiated as `wrap inst[8, 4](...)`) resolve cleanly through the project pipeline.

## Scope

**In scope:**
- `ir.ComponentKind.memory` variant with `mode`, `data_width`, `addr_width`, plus the two facts the validator needs from the AST (`arg_count`, `type_width_given`).
- Resolver recognition of `rom`/`ram` *before* the import-alias lookup, resolving both `width_args` via `widthFromSpec` (so `.parameter` args bind through `ctx.width_bindings`).
- New validator pass `memory_validation.zig` emitting `E017`/`E018`; arms in `port_validation` (port validity + per-port `E014`), `required_input` (`E004`), `sub_circuit_validation.endpointWidth` (cross-boundary `E014`), `combinational_loop` (`ram` cycle-breaking, `rom` not), `name_collision` (`E006`), `scan_imports.isBuiltinAlias` (`E011`).
- `codes.zig`: `E017`, `E018` enum members + `templates` rows + snapshot fixtures.
- Explicit rejection arms: `error.MemoryNotYetSupported` in both topology serializers (temporary, removed in Phase 2) and `error.MemoryUnsupportedInEmitZig` in the emit-zig backend (permanent policy); one CLI helper that maps both to the friendly stderr line.
- `--inspect` (`kind=rom[W=8,A=4]`, `width_args=[8, 4]` on the AST line), `--analyze` (`symbolKind`, hover), and the `tests/helpers/ir_dump.zig` mirror.
- Fixtures and goldens: `expected-ast`, `expected-ir`, `expected-diagnostics`, `expected-inspect`, a parametric project fixture, CLI rejection tests.
- Docs: `DOCS/language.md` §3.5 "Memories (declaration shape)"; every `E001-E016` range string becomes `E001-E018` (README.md:80, CLAUDE.md:84 and :144 table, DOCS/analyze-api.md:55, DOCS/language.md:303, DOCS/sim-protocol.md:46, DOCS/circuit-format.md:151, DOCS/index.md:91, site/src/pages/reference/circuit-format.md:155).

**Explicitly deferred:**
- Engine kind, cell storage, edge-write (Phase 1). Topology v03, runtime, WASM exports, preview glyphs, truth-table RAM policy (Phase 2). `--sim`/`--truth-table` preload and verbs (Phase 3). `expected-sim` goldens, `addr_width` analyze field, classroom docs (Phase 4).
- The pre-existing silent drop of width literals `> 255` (`lib/syntax/translate.zig:161` u8 parse, `:696 catch {}`): `rom m[8, 300](...)` vanishes with no diagnostic today and will keep doing so. Documented in the Recurring Traps of the plan prompt, not fixed here.
- A name→global-id listing in `--inspect` for hosts (separate follow-up; inspect ids are resolver-local).

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| validator | `lib/validator/passes/memory_validation.zig` | Emits `E017` (arity/shape) and `E018` (range) for every `.memory` component; exposes `pub fn memoryPortWidth(mem: ir.Memory, port: []const u8, side: enum { from, to }) ?u8` used by `port_validation` and `sub_circuit_validation`. |
| fixtures | `tests/fixtures/circuits/rom_basic.circ`, `ram_basic.circ` | Clean single-file declarations (AST/IR/inspect goldens, CLI rejection tests). |
| fixtures | `tests/fixtures/circuits/E017_memory_no_widths.circ`, `E017_memory_one_width.circ`, `E017_memory_type_width.circ`, `E017_memory_ident_list.circ`, `E018_memory_width_range.circ`, `E002_memory_unknown_port.circ`, `E004_memory_missing_ports.circ`, `E014_memory_port_width.circ`, `E006_shadows_memory.circ` | One fixture per new diagnostic path, paired with `tests/fixtures/expected-diagnostics/<same>.txt`. |
| fixtures | `tests/fixtures/projects/E011_memory_alias/{root,rom}.circ` + `expected-diagnostics/E011_memory_alias.txt` | `import rom "rom.circ"` must be `E011`, not silently shadowed. |
| fixtures | `tests/fixtures/projects/memory_parametric/{root,mem_wrap}.circ` + `expected-diagnostics/memory_parametric_clean.txt` | `ram m[W, A]` inside `input<W>[W] din` / `input<A>[A] addr` wrapper, instantiated `mem_wrap inst[8, 4](...)`; expected diagnostics: none. |
| fixtures | `tests/fixtures/expected-ast/{rom_basic,ram_basic}.txt`, `expected-ir/{rom_basic,ram_basic}.txt`, `expected-inspect/rom_basic.txt` | Goldens (regenerate with `UPDATE_GOLDENS=1 zig build test`, diff before committing). |
| plans | `DOCS/PLANS/PHASE_0_language_front_door.md` (this file), `DOCS/STATUS.md` (first entry) | Plan artifacts. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| ir | `lib/ir/types.zig` | Add `pub const MemoryMode = enum { rom, ram }`, `pub const Memory = struct {...}` (see Data & State), and `memory: Memory` to `ComponentKind` (after `concat`). |
| ir | `lib/ir/resolver.zig` | New `fn memoryModeFor(name) ?ir.MemoryMode`; in `addComponent` (:93-103) check it **first**, build `.memory` from `component_ast.width_args` via `widthFromSpec` (:45-56) — `widthFromSpec` is wired only to `type_name.width` today (:105), so this is an explicit two-call addition; set `Component.width = data_width`. Missing/extra args: record `arg_count`, default unresolved widths to 1 (the slice placeholder precedent at :140). `type_width_given = component_ast.type_name.width != null`. |
| validator | `lib/validator/run.zig` | Insert `memory_validation.run` after `name_collision.run` (:18). |
| validator | `lib/validator/passes/port_validation.zig` | `isValidInputPort` (:22-37): `.memory => \|m\| switch (m.mode) { .rom => addr, .ram => addr/din/we/clk }`; `isValidOutputPort` (:39-49): `.memory => out`. Replace the `E014` guard at :99-110 with a `connectionWidths` helper: primitives keep `component.width`; `.memory` uses `memoryPortWidth`; slice/concat/sub_circuit_ref/unresolved return null (preserves today's behavior: slice/concat mismatches still surface as `E002` text). Emit `E014` when both sides are non-null and differ. |
| validator | `lib/validator/passes/required_input.zig` | Switch at :30-33 currently `else => continue`; add `.memory => \|m\|` yielding `&.{"addr"}` for rom, `&.{ "addr", "din", "we", "clk" }` for ram (reuses `E004`). |
| validator | `lib/validator/passes/sub_circuit_validation.zig` | `endpointWidth` (:59-87, exhaustive): `.memory => \|m\| memoryPortWidth(m, port, side)`. |
| validator | `lib/validator/passes/combinational_loop.zig` | `isCycleBreaking` (:15-23): `.memory => \|m\| m.mode == .ram`. Policy: `ram` holds state (same class as `and`/`not`); `rom`'s `addr→out` is a genuine combinational path. |
| validator | `lib/validator/passes/name_collision.zig` | `isBuiltinName` (:19-26) gains `rom`, `ram`. Inputs are components with `instance_name` (resolver.zig:289-296), so `input rom` also trips `E006` — intended. |
| validator | `lib/validator/codes.zig` | Append `E017`, `E018` to the enum (after `E016`, before `W001`) **and** rows to `templates` in the same commit — `defaultMessage` (:50-55) hits `unreachable` at runtime otherwise. |
| resolver | `lib/resolver/scan_imports.zig` | `isBuiltinAlias` (:31-39) gains `rom`, `ram` → `E011` at :148-158. |
| topology | `lib/topology/serializer.zig` | First kind switch in Pass 1a (:168-173) and the project-path twin: `.memory => return error.MemoryNotYetSupported`. Temporary — Phase 2 replaces it with the real record. |
| topology | `lib/topology/full_serializer.zig` | Same arm at :179-184 (and its project-path twin at ~:331). |
| emit | `lib/emit/build_fn.zig`, `lib/emit/project.zig` | Exhaustive kind switches (`build_fn.zig:75-91`, `project.zig:360+`): `.memory => return error.MemoryUnsupportedInEmitZig` (permanent; precedent `error.UnsupportedSubCircuitInPhase4` at `build_fn.zig:88`). Review the `else`-guarded walks at `project.zig:152-156, :236-241, :295, :320` so a memory cannot slip through before the exhaustive switch rejects it. |
| cli | `cmd/circ-compile/main.zig` | New `fn reportBackendError(stderr, context: []const u8, err) !void`: prints `rom/ram are not yet supported in this mode` for `error.MemoryNotYetSupported` / `error.MemoryUnsupportedInEmitZig`, else the existing `"<context>: {s}"` text. Use it at every `catch` that prints `topology build failed` (:285, :290, preview and truth-table arms), `topology serialization failed` (:341, :346, :354…), and `emission failed` (:318, :327). Exit code stays 1. |
| cli | `lib/cli/inspect_dump.zig` | `dumpComponentKind` (:118-126): `.memory => rom[W=8,A=4]` / `ram[W=8,A=4]`. `dumpComponent` (:59-72): after the instance name print `width_args=[8, 4]` when `comp.width_args.len > 0` (same spelling as `tests/helpers/ast_dump.zig:86-92`). |
| tests | `tests/helpers/ir_dump.zig` | Mirror of `dumpComponentKind` (:11-18) gains the same `.memory` arm (exhaustive; compile-forced). |
| analyze | `lib/analyze/analyze.zig` | `symbolKind` (:247-258): `.memory => \|m\| if (m.mode == .rom) "rom" else "ram"`. `hoverForComponent` (:267-282): `.memory` renders `rom[8,4] code` (both widths, comma-separated, no space). |
| tests | `tests/syntax/translate_test.zig`, `tests/ir/resolver_test.zig`, `tests/validator/run_test.zig`, `tests/validator/codes_snapshot_test.zig` (`single_fixtures` :209-222, `project_fixtures` :226-236), `tests/cli/integration_test.zig` | Fixture-table entries for every new fixture; CLI rejection tests. |
| docs | `DOCS/language.md`, `README.md`, `CLAUDE.md`, `DOCS/analyze-api.md`, `DOCS/sim-protocol.md`, `DOCS/circuit-format.md`, `DOCS/index.md`, `site/src/pages/reference/circuit-format.md` | §3.5 declaration shape; `E001-E016` → `E001-E018`; two new rows in CLAUDE.md's code table. |

**New dependencies:** None.

## Data & State

```zig
// lib/ir/types.zig
pub const MemoryMode = enum { rom, ram };

/// A `rom`/`ram` declaration. `data_width` (W) and `addr_width` (A) come
/// from the instance-position `[W, A]` call widths, resolved through
/// `widthFromSpec` so parametric names bind. `Component.width` mirrors
/// `data_width` so single-width consumers (analyze hover, inspect) see the
/// port width of `out`. `arg_count` and `type_width_given` exist only so
/// `memory_validation` can report E017 without re-reading the AST; when
/// `arg_count != 2` the unresolved widths default to 1 to keep the IR
/// structurally valid until the diagnostic surfaces.
pub const Memory = struct {
    mode: MemoryMode,
    data_width: u8,
    addr_width: u8,
    arg_count: u8,
    type_width_given: bool,
};

pub const ComponentKind = union(enum) {
    primitive: PrimitiveKind,
    sub_circuit_ref: UnresolvedRef,
    unresolved_name: []const u8,
    slice: Slice,
    concat,
    memory: Memory,
};
```

```zig
// lib/validator/passes/memory_validation.zig
pub const MAX_DATA_WIDTH: u8 = 64;   // BitVecState cap
pub const MAX_ADDR_WIDTH: u8 = 16;   // 65,536 words, v1 cap (PLANS_PROMPT.md)

/// Single source of truth for memory port widths. `side == .to` answers
/// "what width does this input port expect"; `side == .from` answers
/// "what width does this output port drive". Unknown ports → null (E002
/// already fires for them).
pub fn memoryPortWidth(mem: ir.Memory, port: []const u8, side: enum { from, to }) ?u8 {
    return switch (side) {
        .from => if (std.mem.eql(u8, port, "out")) mem.data_width else null,
        .to => if (std.mem.eql(u8, port, "addr")) mem.addr_width
            else if (mem.mode == .ram and std.mem.eql(u8, port, "din")) mem.data_width
            else if (mem.mode == .ram and (std.mem.eql(u8, port, "we") or std.mem.eql(u8, port, "clk"))) 1
            else null,
    };
}
```

Diagnostic contract (messages are the `diagnostic.message` overrides; `templates` rows carry the short default):

| Code | `templates` default | Trigger | Message shape |
|------|---------------------|---------|---------------|
| `E017` | `memory parameter list malformed` | `arg_count != 2`, or `type_width_given` | `memory 'm' requires exactly two width arguments [W, A]; got 1` · for 0 args / IdentList form append ` (write 'rom m[W, A](...)' on its own line)` · for a type-position width: `memory 'm': width goes in the instance position, write 'rom m[8, 4](...)' not 'rom[8] m[8, 4](...)'` |
| `E018` | `memory width out of range` | `data_width` ∉ 1..64 or `addr_width` ∉ 1..16 (only when `arg_count == 2`) | `memory 'm': data width 0 must be 1..64` / `memory 'm': address width 20 exceeds 16 (65536 words)` |

`E017` and `E018` span the component (`component.span`), matching `E004`/`E006`. `E018` is suppressed when `E017` fired for the same component (the defaulted widths are placeholders).

Reserved-name behavior (all three lists updated together):

| Site | Names | Effect |
|------|-------|--------|
| `resolver.addComponent` | `rom`, `ram` as **type** | `.memory` kind, checked before `isPrimitive` and `import_aliases` |
| `name_collision.isBuiltinName` | `rom`, `ram` as instance/input **name** | `E006 instance name 'rom' shadows built-in` |
| `scan_imports.isBuiltinAlias` | `rom`, `ram` as import **alias** | `E011 import alias collision` (without this, an existing `import rom` degrades to `W003` and the primitive silently replaces the user's sub-circuit) |

The AST is unchanged: `ast.ComponentInstance.width_args` (`lib/syntax/ast.zig:41-47`) already carries `[W, A]` on the named-declaration path (`translate.zig:591-597`). The IdentList form (`rom a, b`, `translate.zig:622-631`) and anonymous inline form (`AnonDecl` has no `CallWidths`, `proto-circ.peg:12`) arrive with zero `width_args` and are reported by `E017`, never accepted.

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. The resolver, validator passes, dumps, and analyze walk run in the existing single-threaded pipeline order (`validator/run.zig`), and the new pass has no shared state beyond the `DiagnosticList` it appends to.

## Persistence & I/O

This phase has no persistence or external I/O beyond what prior phases established. No new filesystem access: fixtures are read through the existing test loaders; the CLI rejection is a stderr line. `DOCS/STATUS.md` gains its first entry (plain append by the execution agent).

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | IR variant + resolver + all compile-forced arms | `ir.Memory`/`ComponentKind.memory`; resolver builds it from `width_args` via `widthFromSpec` (parametric binding included); minimal arms so the tree builds: `inspect_dump`/`ir_dump` kind text, `analyze` symbolKind + hover, `port_validation` validity switches (`E014` helper deferred to slice 3), `sub_circuit_validation.endpointWidth` (calls a stub `memoryPortWidth` living in the new pass file, which ships here with the helper only), both serializers' `MemoryNotYetSupported`, emit's `MemoryUnsupportedInEmitZig`; `rom_basic`/`ram_basic` fixtures. Commit: `feat(ir): resolve rom/ram declarations into a memory component kind`. | `zig build test` green; `expected-ast/rom_basic.txt` shows `width_args=[8, 4]`; `expected-ir/{rom,ram}_basic.txt` show `kind=rom[W=8,A=4] width=8` / `kind=ram[W=8,A=4] width=8`; `memory_parametric_clean` project golden is empty (widths bound to 8/4, no `E001`/`E016`); analyze inline test asserts symbol kind `"rom"` and hover `rom[8,4] code`. |
| 2 | `E017`/`E018` + code registry | `codes.zig` enum + `templates`; `memory_validation.zig` `run` wired into `run.zig`; four `E017_*` and one `E018_*` fixtures + goldens; `codes_snapshot_test` entries; `E001-E016` → `E001-E018` in all nine docs; CLAUDE.md table rows. Commit: `feat(validator): add E017/E018 memory declaration diagnostics`. | Snapshot test passes with the new rows; `run_test` fixtures produce exactly one `E017` (or `E018`) each with the message shapes above; `E018` fixture with `[8, 20]` and `[0, 4]` lines yields two `E018`s and no `E017`; `E017_memory_type_width` (`rom[8] m[8, 4](...)`) yields one `E017`. |
| 3 | Reused-code arms: `E002`/`E004`/`E014`/`E006`/`E011`/`E008` policy | `required_input` arm; `port_validation` `connectionWidths` helper + `E014`; `combinational_loop` policy; `name_collision` + `scan_imports` reservations; fixtures `E002_memory_unknown_port`, `E004_memory_missing_ports`, `E014_memory_port_width`, `E006_shadows_memory`, project `E011_memory_alias`. Commit: `feat(validator): enforce memory port contract and reserve rom/ram`. | Each fixture golden matches: `din` on a rom → `E002 unknown input port 'din'`; ram missing `we`,`clk` → two `E004`; `addr` driven by `[3]` into `[8, 4]` → `E014 width mismatch: source width 3, destination expects 4`; `we` driven by `[2]` → `E014 ... expects 1`; `not rom(in=a)` → `E006`; `import rom "rom.circ"` → `E011`; a `ram.out → not → ram.din` loop fixture yields **no** `E008` while `rom.out → not → rom.addr` yields `E008` (two new circuits: `clean_ram_feedback.circ`, `E008_rom_loop.circ`). Existing `E014_width_mismatch`, `slice_*`, `concat_*` goldens unchanged byte-for-byte. |
| 4 | CLI rejection surface + inspect/analyze polish + docs | `reportBackendError` helper wired into every backend `catch`; `expected-inspect/rom_basic.txt`; `DOCS/language.md` §3.5. Commit: `feat(cli): reject rom/ram in artifact-producing modes until the engine lands`. | `tests/cli/integration_test.zig`: for each of `-o out.wasm`, `--emit-zig -o out.zig`, `--preview`, `--truth-table`, `--sim` on `rom_basic.circ`, exit code 1, stderr contains `rom/ram are not yet supported in this mode`, and no output file exists afterwards (`-o` cases); `--inspect` on `rom_basic.circ` exits 0 with the golden; `--analyze` request over `rom_basic.circ` returns zero diagnostics. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 1 is large because Zig's exhaustive switches force every arm at once; keep its non-IR arms minimal (dump text, rejection errors) so the review stays focused on the resolver.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `memory_validation: rejects wrong arity` | `lib/validator/passes/memory_validation.zig` (inline) | Hand-built module with `arg_count` 0/1/3 emits one `E017` each with the arity in the message; `arg_count == 2` emits none. |
| `memory_validation: rejects type-position width` | same | `type_width_given == true` emits `E017` with the "instance position" message even when `arg_count == 2`. |
| `memory_validation: width bounds` | same | `(65, 4)`, `(0, 4)`, `(8, 17)`, `(8, 0)` each emit `E018`; `(1, 1)`, `(64, 16)` emit none; `E018` suppressed when `E017` fired. |
| `memoryPortWidth contract` | same | rom: `addr→A`, `out→W`, `din/we/clk→null`; ram: `din→W`, `we→1`, `clk→1`; unknown → null. |
| `resolver: rom/ram precede import aliases` | `lib/ir/resolver.zig` (inline) | A file with `import rom "x.circ"` and `rom r[8,4](addr=a)` resolves `r` as `.memory`, not `.sub_circuit_ref`. |
| `resolver: parametric width args bind` | same | `resolveWithBindings` with `{W=8, A=4}` on `ram m[W, A](...)` yields `data_width=8, addr_width=4`; unbound `A` returns `error.UnboundParameter`. |
| `analyze: memory symbol and hover` | `lib/analyze/analyze.zig` (inline, next to :446-594) | Symbol kind `"rom"`/`"ram"`, hover `rom[8,4] code`. |
| `inspect_dump: memory kind text` | `lib/cli/inspect_dump.zig` (inline) | `kind=ram[W=8,A=4]` and `width_args=[8, 4]` rendering. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `translate_test` entries `rom_basic`, `ram_basic` | AST golden | `Component type=rom instance=code width_args=[8, 4]` with `Port addr` (and `din/we/clk` for ram). |
| `resolver_test` entries `rom_basic`, `ram_basic` | IR golden | `kind=rom[W=8,A=4] width=8`; connections `pc.out -> code.addr`, `code.out -> …`. |
| `run_test` / `codes_snapshot_test` single entries for `E017_*`, `E018_*`, `E002_memory_unknown_port`, `E004_memory_missing_ports`, `E014_memory_port_width`, `E006_shadows_memory`, `E008_rom_loop`, `clean_ram_feedback` | diagnostics golden | Exact `path:L:C: error: E0xx: message` lines; `clean_ram_feedback` golden is empty. |
| `codes_snapshot_test` project entries `E011_memory_alias`, `memory_parametric_clean` | project pipeline | `E011` for the alias; empty golden for the parametric wrapper instantiated at `[8, 4]`. |
| `integration_test: rejection in every artifact mode` | CLI | Five invocations → exit 1 + friendly stderr line + no output file; `--inspect` golden `expected-inspect/rom_basic.txt` exits 0. |
| Existing suites | whole tree | `zig build test` green; every pre-existing golden byte-identical (`git status` shows only the new/updated fixtures listed above). |

Run command: `zig build test` (full fast suite; single modules via `zig test tests/validator/run_test.zig`, `zig test tests/ir/resolver_test.zig`, `zig test tests/cli/integration_test.zig`). `zig build test-all` before the final slice to prove the emit-zig smoke still passes with the new rejection arm.

## Open Questions / Spikes

- `TODO(phase0)`: confirm whether `lib/validator/passes/dead_code.zig` (W001/W002) and `name_resolution.zig:21-28` need explicit `.memory` arms or behave correctly through their `else` paths — check during slice 1 by running `rom_basic` through `--inspect` and asserting zero warnings beyond the expected set.
- `TODO(phase0)`: `E017` for the IdentList form (`rom a, b`) reports on the declaration span, which covers both names; decide whether to emit once per declaration (proposed) or once per name.
- None otherwise — the eleven design decisions in `DOCS/PLANS_PROMPT.md` cover every choice this phase makes.
