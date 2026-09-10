# Phase 4 — Golden coverage, decision records, classroom docs

> **Dependencies:** Phases 0–3 complete and committed (`DOCS/PLANS_PROMPT.md` phase index). This phase adds no engine, format, or protocol surface — it consumes them.
> **Warnings:** The `--sim` golden transcripts capture Phase 3's reply shapes byte-for-byte; generate them only after Phase 3 is merged, then *read* every line against the assertions in the Slices table before committing (`UPDATE_GOLDENS=1` writes whatever the loop prints, `tests/helpers/golden.zig:11-16`). Goldens must never contain a `save` verb — the family runs from the repo root with no temp dir and must not write files. `example/logisim-import/` does not exist today (`grep -rli logisim` hits only `DOCS/PLANS_PROMPT.md`); see Open Questions. The `ready` block stays byte-identical for memory-free circuits (`lib/sim/loop.zig:90-93`): the `sim_and_gate` golden is the tripwire. The spawned-CLI tests in slice 1 rely on `std.process.Child.run` leaving stdin at `.Ignore` so `serve` sees EOF and returns after the handshake with no `ok bye` (`loop.zig:110`, `maybe_line orelse break`; `DOCS/sim-protocol.md:23,70` document EOF ≡ clean exit) — if a later Zig changes that default, the test's exact-stdout assertion is the tripwire.

## Goal

A contributor can prove `--sim` behaviour from source fixtures the way `expected-wasm` proves the compiled artifact: a `.script` of protocol lines goes in through `sim_loop.serve` with an in-memory reader/writer (`lib/sim/loop.zig:268-272` pattern) and the full transcript is compared against `tests/fixtures/expected-sim/<name>.txt`. Four goldens ship: a memory-free AND gate (handshake unchanged, `mems 0`), a host-driven program counter stepping through a preloaded ROM (including mid-session `load`, replace-all, and `reset` restoring the CLI preload), a RAM write/read scenario (X→1 is not an edge, defined-low→high commits, `we` low blocks, `poke`/`peek`/`clear`), and every memory error code from real source. Three spawned-binary tests prove `main.zig`'s `--mem` path end-to-end: a good preload prints the unchanged handshake and exits 0; an unknown name or a missing file exits 2 with the message on stderr and an **empty** stdout (the "before any handshake" constraint, `PLANS_PROMPT.md` Architectural Constraints). `--analyze` reports `"addr_width": A` on `rom`/`ram` symbols and `DOCS/analyze-api.md` says so. The eleven locked decisions are recorded as decision/rationale/alternatives entries in `DOCS/decisions/language.md`, `runtime-api.md`, and (for `--mem` flag gating) `cli.md`. A student reading `DOCS/language.md` §6.5 knows every port, width, X rule, and the edge rule; `circuit-format.md` (and its site mirror, the only public-site language reference) lists `rom`/`ram` in its component table and `E017`/`E018` in its code catalogue; reading `DOCS/getting-started.md` §7 can author a ROM image with `printf`, verify it with `xxd`, load it with `--mem`, step a clock with `set clk 0`/`set clk 1`, author an image interactively with `poke` then `save`, and do the same from Node with the Phase 2 exports.

## Scope

**In scope:**
- `tests/sim/golden_test.zig` + `build.zig` wiring (new `sim_golden_tests` artifact under the `test` step, same shape as `serializer_fixtures_tests`, `build.zig:1506-1527`).
- Three `--sim --mem=…` cases in `tests/cli/integration_test.zig` through the existing `run()` helper (`:14-27`): handshake-only success, unknown-name failure, missing-file failure.
- Fixtures: `circuits/sim_rom_pc_walk.circ`, `circuits/sim_ram_write_read.circ`; scripts under `tests/fixtures/sim/`; goldens under `tests/fixtures/expected-sim/`; three tiny raw images under `tests/fixtures/mem/`.
- `lib/analyze/analyze.zig`: optional `addr_width` on `Symbol`, emitted only for memories; inline tests; `DOCS/analyze-api.md` contract note.
- Decision records (eleven decisions + the "contents are runtime configuration" principle) in `DOCS/decisions/language.md` and `DOCS/decisions/runtime-api.md`, one flag-gating entry in `DOCS/decisions/cli.md`; bullets in `DOCS/decisions/index.md`.
- `DOCS/language.md` §6.5 "Memories (`rom`/`ram`)" full reference plus `E017`/`E018` bullets in §4.1; `DOCS/circuit-format.md` component-table rows and a "codes added with v03" table, mirrored to `site/src/pages/reference/circuit-format.md`; `DOCS/getting-started.md` §7 "Loading a program into ROM and stepping a clocked circuit" plus the stale "full export list" sentence at `:153`; the site mirror `site/src/pages/reference/getting-started.md` (same prose with front-matter and `/reference/...` links, `:157`).
- The remaining "fixed six-export API" enumerations Phase 2 did not touch: `DOCS/index.md:3`, `DOCS/decisions/compiler-pipeline.md:29` (see Modified files for the exact edit each gets; `DOCS/architecture.md:121` is Phase 2's).
- The Logisim-import note (location per Open Questions — `example/` is gitignored); `tests/README.md` entries for the three new fixture directories and the script/transcript format.

**Explicitly deferred:**
- A converter from Logisim's `v2.0 raw` hex image to the circ raw image (the note says it is possible and out of scope).
- *Interactive* (stdin-driven) CLI tests of `--sim`: every CLI test helper uses `std.process.Child.run`, which pipes stdout/stderr but sets stdin to `.Ignore` (`tests/cli/integration_test.zig:16`, `tests/e2e/cli_e2e_test.zig:7,34,71`), so a spawned `circ-compile --sim` can be observed only up to EOF — it cannot be fed a script. That is exactly enough for the handshake and the exit-2 preload failures (in scope above); verb semantics over stdin are the in-process golden family, which passes the same preload slice `main.zig` passes to `serve`. Adding a `.Pipe` stdin helper is a test-infrastructure change out of this initiative's scope.
- `expected-sim` goldens with `save` (filesystem writes); the `save` round-trip is Phase 3's `tmpDir` loop test.
- `DOCS/sim-protocol.md`, `wasm-api.md` (Phases 2–3 own them); `DOCS/STATUS.md` archive.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| tests | `tests/sim/golden_test.zig` | Fixture table + `runFixture`: project-pipeline resolve (`scan_imports` → `import_cycle` → `resolve_bodies` → `validator_run_project`, copied from `tests/e2e/serializer_fixtures_test.zig:130-153`), `full_serializer.buildFromProject` (the `--sim` path, `cmd/circ-compile/main.zig:283-287`; `--sim` always takes the project pipeline, `:210`), read `tests/fixtures/sim/<name>.script`, read each fixture preload image, call `sim_loop.serve` with a `fixedBufferStream` reader and an `ArrayList(u8)` writer, then `golden.expectGolden(out.items, "tests/fixtures/expected-sim/<name>.txt")`. No Node dependency. |
| fixtures | `tests/fixtures/circuits/sim_rom_pc_walk.circ` | `input[4] pc` · `rom code[8, 4](addr = pc)` · `output[8] instr(in = code.out)`. The program counter is a host-driven input pin: the language has no register primitive (`and/not/wire/led` + macros, `DOCS/language.md:179-197`), so "stepping" is `set pc N`. |
| fixtures | `tests/fixtures/circuits/sim_ram_write_read.circ` | `input[4] a` · `input[8] d` · `input w, clk` · `ram data[8, 4](addr = a, din = d, we = w, clk = clk)` · `output[8] q(in = data.out)`. |
| fixtures | `tests/fixtures/sim/{sim_and_gate,sim_rom_pc_walk,sim_ram_write_read,sim_mem_errors}.script` | Protocol input, one verb per line, `#` comments allowed (skipped without reply, `lib/sim/protocol.zig:82-83`). Exact contents in Data & State. |
| fixtures | `tests/fixtures/expected-sim/<same four>.txt` | Full stdout transcript from `ready` to `ok bye`. |
| fixtures | `tests/fixtures/mem/rom_pc_walk.bin` (4 B: `10 21 32 43`), `rom_pc_walk_alt.bin` (2 B: `aa bb`), `too_many_words.bin` (17 B of `00`) | Raw little-endian images, `bpw = 1` for `W = 8` (decision 2). Authored with the POSIX-octal `printf` form the getting-started recipe teaches (`printf '\020\041\062\103'`, `printf '\252\273'`) and `head -c 17 /dev/zero`; all three commands are recorded in `tests/README.md` so the binaries are reproducible from any `sh`. |
| docs | `DOCS/logisim-import.md` (location per Open Questions; `example/` is gitignored) | Logisim → circ mapping note: `ROM`/`RAM` components now map to `rom`/`ram` (ports `addr/din/we/clk` ↔ Logisim `A/D/WE/clk`, single-port only, no `sel`/`clr`/`ld`); contents come from Logisim's `v2.0 raw` hex image via a converter, out of scope. |
| plans | `DOCS/PLANS/PHASE_4_golden_coverage_decisions_and_docs.md` (this file) | Plan artifact. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| build | `build.zig` | After `run_sim_loop_tests` (`:1214-1218`): `sim_golden_tests_mod` rooted at `tests/sim/golden_test.zig` with imports `scan_imports` (`resolver_scan_imports_mod`, `:590`), `import_cycle` (`:614`), `resolve_bodies` (`:638`), `validator_run_project` (`:272`), `diagnostics` (`validator_diagnostics_mod`, `:169`), `full_serializer` (`topology_full_serializer_mod`, `:1105`), `sim_loop` (`sim_loop_mod`, `:1203`), `golden` (fresh `createModule` over `tests/helpers/golden.zig`, the `:104-108` pattern). `addIncludePath(".")`/`("./lib")`, `linkParserArchive`, `linkLibC` (the resolver pulls the Go parser archive, `:1521-1524`), `addRunArtifact`, `test_step.dependOn` (`test_step` declared `:967`). |
| tests | `tests/cli/integration_test.zig` | Three new `test` blocks after the existing cases, using `run()` (`:14-27`) and `exitCode()` (`:29-36`): `sim --mem preload prints the unchanged handshake`, `sim --mem unknown memory exits 2 before the handshake`, `sim --mem missing image exits 2 before the handshake` (exact argv and assertions in Tests). No helper changes. |
| analyze | `lib/analyze/analyze.zig` | `Symbol` (`:52-58`) gains `addr_width: ?u8 = null`. Component loop (`:317-327`) sets `.addr_width = switch (c.kind) { .memory => \|m\| m.addr_width, else => null }` (else-guarded on purpose: only `.memory` carries A). `renderJson` symbols (`:417-427`): after `"width":{d}` emit `,"addr_width":{d}` iff non-null, then `"range"`. Two inline tests after `:512`. |
| docs | `DOCS/analyze-api.md` | `:49` example gains a `rom` symbol with `"addr_width": 4`; `:56` bullet: kinds add `rom`, `ram`; new sentence: `addr_width` present only on `rom`/`ram` symbols, `width` is the data width `W`; consumers must tolerate its absence. |
| docs | `DOCS/decisions/language.md` | Append a `## Native memories` fold after §17 (`:160-164`), unnumbered `###` entries per `decisions/index.md:52-55` conventions (see Data & State for the entry list). |
| docs | `DOCS/decisions/runtime-api.md` | Append a `## Native memories` fold after `:70`; one sentence at the end of "Things deliberately *not* exported" (`:61-70`) pointing at the memory export family as the first additive extension of the six-export surface. |
| docs | `DOCS/decisions/cli.md` | Append `### --mem is scoped to sim and truth-table` after "No build directory…" (`:43-`): decision 7's flag gating (fixed `[16]`, `TooManyMemPreloads`, rejected in every other mode at parse time like `--strict`/`--format`, `:19-33` precedent) with a cross-reference to the runtime-api.md verbs entry. |
| docs | `DOCS/decisions/compiler-pipeline.md` | `:29` "Pre-built runtime WASM" decision: the six-name export list gains the clause "— extended additively in v03 with the memory export family, see [runtime-api.md](runtime-api.md) `## Native memories`". The entry stays a history of *why the runtime is embedded*; only the enumeration is made non-exhaustive. |
| docs | `DOCS/decisions/index.md` | `runtime-api.md` bullets (`:16-24`), `language.md` bullets (`:26-32`), and `cli.md` bullets (`:40-43`) each gain one line naming the new fold/entry. |
| docs | `DOCS/index.md` | `:3` "exposes a small fixed API — `init`, `run`, `setPin(…)`, and the paired … getters —" gains "(and, for circuits with `rom`/`ram`, the memory export family documented in [wasm-api.md](wasm-api.md))". No table row changes (`:19-32`) unless the Logisim note lands under `DOCS/` — see Open Questions. |
| docs | `DOCS/language.md` | Insert `### 6.5 Memories (\`rom\`/\`ram\`)` after §6.4 (`:504-516`, before the `---` at `:518`); §4.1 bullet list (`:306-321`) gains one bullet for `E017`/`E018` after the `E016` bullet; §3.5 (Phase 0, declaration shape) gets a "semantics: see §6.5" cross-link. |
| docs | `DOCS/circuit-format.md` | Component table (`:52-56`, `and/not/led/wire/output` rows) gains `rom` (`addr`; "`[W, A]` data/address widths, `out` is `W` wide; contents loaded at runtime, see `language.md` §6.5") and `ram` (`addr`, `din`, `we`, `clk`; same note plus "writes on the rising edge of `clk` when `we` is high") rows; the sentence after the table (`:58`) that says every primitive takes an optional `[N]` gets "— memories take exactly two, `[W, A]`". Diagnostic Codes section: after the v02 table (`:153-157`) add a sibling "The memory codes added with v03 are:" table with `E017` (memory parameter list malformed) and `E018` (memory width out of range), keeping the v02 table a versioned changelog. |
| site | `site/src/pages/reference/circuit-format.md` | Same two edits as the DOCS copy (component table `:56-62`, diagnostic table `:157-161`) with `/reference/...` links (`language.md` → `/reference`, as `:155` does today). Precedent: Phase 0 edited `:155`. |
| docs | `DOCS/getting-started.md` | Insert `## 7. Loading a program into ROM and stepping a clocked circuit` before `## Where to go next` (`:233`); rewrite the `:153` sentence "The full export list … is exactly `topology_alloc`, `init`, `run`, `setPin`, `getOutputValue`, `getOutputDefined`" to name the eight memory exports as the additive family (Phase 2 fixed `wasm-api.md`, `CLAUDE.md:7`, `README.md:3,15` and `architecture.md:121`); add `sim-protocol.md` to "Where to go next". |
| site | `site/src/pages/reference/getting-started.md` | Same edits as the DOCS copy (it is a mirror with front-matter and `/reference/...` links: `diff` differs only at `:1-5`, `:83`, `:157`, `:170`). |
| tests | `tests/README.md` | Directory list (`:10-15`) gains `sim/` (scripts), `expected-sim/` (transcripts), `mem/` (raw images); format section (`:23-25`) gains the sim family line format and the golden-review rule; the three shell lines that regenerate `mem/*.bin`. |

**New dependencies:** None. (The family runs the native engine in-process, `lib/sim/loop.zig:82-84`; no Node. The three CLI cases spawn `zig-out/bin/circ-compile` exactly as every other test in `integration_test.zig` does.)

**Switches:** no exhaustive switch gains an arm in this phase. One new `else`-guarded switch is introduced deliberately (`analyze.zig` symbol loop, `.memory` → `addr_width`, everything else → `null`); Phase 0 already gave `symbolKind` (`:247-258`) and `hoverForComponent` (`:267-282`) their `.memory` arms.

## Data & State

Interfaces this phase **consumes** (fixed cross-phase vocabulary): from Phase 0, `ir.Memory.addr_width`/`data_width`, `symbolKind` → `"rom"`/`"ram"`, `E017`/`E018`; from Phase 2, the WASM exports `getMemInfo/memBuffer/memLoad/memStore/memClear/setMemWord/getMemValue/getMemDefined` and their status codes (docs only), `format.ComponentKind.rom = 8`/`.ram = 9`; from Phase 3, `sim_loop.serve`'s preload slice (the `--mem` payload `main.zig` passes after building the topology), `Args.mem_preloads`/`mem_preload_count` and the stderr "no memory named X (declared memories: …)" / exit-2 path in `main.zig`, verbs `mems/load/save/peek/poke/mem/clear`, error codes `E_NOMEM/E_IO/E_MEMFMT/E_ADDR`, `reset` re-applying CLI preloads and dropping mid-session `load`/`poke`, `Session.memories`/`findMemory`/`applyImage`. This phase **exposes** nothing to later phases (it is the last); externally it exposes the `addr_width` JSON field to `circ-lsp` and the `expected-sim` family to future contributors.

```zig
// tests/sim/golden_test.zig
const Preload = struct { name: []const u8, path: []const u8 }; // mirrors --mem=<name>=<path>

const Fixture = struct {
    name: []const u8,                  // tests/fixtures/sim/<name>.script -> expected-sim/<name>.txt
    root_path: []const u8,             // resolved through the project pipeline, as --sim does (main.zig:210)
    preloads: []const Preload = &.{},  // read with std.fs.cwd().readFileAlloc, handed to serve()
};

const fixtures = [_]Fixture{
    .{ .name = "sim_and_gate",       .root_path = "tests/fixtures/circuits/and_gate.circ" },
    .{ .name = "sim_rom_pc_walk",    .root_path = "tests/fixtures/circuits/sim_rom_pc_walk.circ",
       .preloads = &.{ .{ .name = "code", .path = "tests/fixtures/mem/rom_pc_walk.bin" } } },
    .{ .name = "sim_ram_write_read", .root_path = "tests/fixtures/circuits/sim_ram_write_read.circ" },
    .{ .name = "sim_mem_errors",     .root_path = "tests/fixtures/circuits/sim_ram_write_read.circ" },
};

fn updateModeEnabled() bool { /* mirror golden.zig:3-6: UPDATE_GOLDENS == "1" */ }

fn runFixture(f: Fixture) !void {
    // arena; scan/cycle/resolve/validate exactly as serializer_fixtures_test.zig:130-153 (hard error => test failure);
    // var topology = try full_serializer.buildFromProject(alloc, &project);        // main.zig:284
    // preloads: for (f.preloads) |p| append sim_loop.Preload{ .name = p.name, .bytes = try std.fs.cwd().readFileAlloc(alloc, p.path, sim_loop.IMAGE_READ_CAP) }
    // var fbs = std.io.fixedBufferStream(script_text);                            // loop.zig:270
    // try sim_loop.serve(alloc, topology, f.root_path, diags.items, preloads, fbs.reader(), out.writer(alloc));  // Phase 3 signature
    // try golden.expectGolden(out.items, golden_path);                            // golden.zig:8
}
```

`file_path` passed to `serve` is the fixture path, so `diag` lines (none expected, `warnings=0`) would be deterministic. Tests run with cwd = repo root (every golden path is relative, `golden.zig:9-19`, `serializer_fixtures_test.zig:251`), which is also what makes the script's cwd-relative `load` paths resolve (decision 7).

Scripts and the transcript lines each one must contain (block shapes for `mems`/`load`/`mem` are Phase 3's; `get`/`peek` use the `ok <value> <mask>` hex encoding of `loop.zig:187-198`):

| Fixture | Script (stdin) | Load-bearing transcript lines |
|---------|----------------|-------------------------------|
| `sim_and_gate` | `mems` / `set a 1` / `set b 1` / `get out` / `quit` | First four lines byte-identical to today's handshake (`ready proto=1 pins=3 warnings=0`, `pin a in 1`, `pin b in 1`, `pin out out 1`); `mems 0`; `ok 0x1 0x1`; `ok bye`. |
| `sim_rom_pc_walk` | `mems` / `set pc 0` / `get instr` / `set pc 1` / `get instr` / `set pc 3` / `get instr` / `set pc 4` / `get instr` / `mem code 0 6` / `set pc 0 0` / `get instr` / `set pc 0` / `load code tests/fixtures/mem/rom_pc_walk_alt.bin` / `get instr` / `peek code 3` / `reset` / `set pc 0` / `get instr` / `quit` | `ready proto=1 pins=2 warnings=0`; `mems 1` + one line naming `code` as `rom` `8` `4`; reads `0x10 0xff`, `0x21 0xff`, `0x43 0xff`; address 4 (unloaded) reads `0x0 0x0`; the `mem` block lists cells 0–3 defined and 4–5 as `0x0 0x0`; undefined `pc` (`set pc 0 0`) reads `0x0 0x0` (any undefined address bit ⇒ fully undefined output); after `load` with `pc` still presented at 0, `get instr` is `0xaa 0xff` with **no** `set` in between (host-side load resyncs `out`); `peek code 3` is `0x0 0x0` (replace-all: a 2-word image leaves cells 2..15 undefined); after `reset` + `set pc 0`, `0x10 0xff` (CLI preload re-applied, mid-session `load` dropped). |
| `sim_ram_write_read` | `mems` / `set a 5` / `set d 0x2a` / `set w 1` / `set clk 1` / `get q` / `set clk 0` / `set clk 1` / `get q` / `set a 6` / `get q` / `set a 5` / `get q` / `set w 0` / `set d 0x11` / `set clk 0` / `set clk 1` / `get q` / `peek data 5` / `peek data 6` / `poke data 6 0x7f` / `set a 6` / `get q` / `clear data` / `get q` / `quit` | `ready proto=1 pins=5 warnings=0` with `pin a in 4`, `pin d in 8`, `pin w in 1`, `pin clk in 1`, `pin q out 8`; `mems 1` naming `data` as `ram` `8` `4`; first `get q` is `0x0 0x0` (undefined→1 is not an edge); after `clk 0` then `clk 1`, `0x2a 0xff`; `a=6` reads `0x0 0x0`, `a=5` reads `0x2a 0xff` again (asynchronous read); with `w=0` a full clock pulse leaves `0x2a 0xff` (`peek data 5` agrees, `peek data 6` is `0x0 0x0`); after `poke data 6 0x7f` and `set a 6`, `0x7f 0xff`; after `clear data`, `0x0 0x0`. |
| `sim_mem_errors` | `load nosuch tests/fixtures/mem/rom_pc_walk.bin` / `load data tests/fixtures/mem/does_not_exist.bin` / `load data tests/fixtures/mem/too_many_words.bin` / `peek data 16` / `poke data 0 0x1ff` / `set data 1` / `get data` / `load data` / `quit` | In order: `err E_NOMEM nosuch`; a line starting `err E_IO tests/fixtures/mem/does_not_exist.bin`; a line starting `err E_MEMFMT tests/fixtures/mem/too_many_words.bin` (17 words into 16 cells); `err E_ADDR data 0x10` (addresses are echoed through `writeHex`, Phase 3 reply grammar); a line starting `err E_WIDTH data` (decision 7 fixes the code, Phase 3 the tail); `err E_NOPIN data` twice (a memory name is not a pin, decision 7); `err E_PROTO malformed command` (arity, `protocol.zig:93-97` pattern); `ok bye`. |

Spawned-CLI cases (`tests/cli/integration_test.zig`, `run()` at `:14-27`; the binary is built once per test binary, `:38-`). Because stdin is `.Ignore`, `serve` returns at EOF right after the handshake and `main.zig:296-300` returns 0:

| Test | argv (after the binary path) | Assertions |
|------|-----------------------------|------------|
| `sim --mem preload prints the unchanged handshake` | `tests/fixtures/circuits/sim_rom_pc_walk.circ --sim --mem=code=tests/fixtures/mem/rom_pc_walk.bin` | `exitCode == 0`; `stdout` **equals** `"ready proto=1 pins=2 warnings=0\npin pc in 4\npin instr out 8\n"` (no `ok bye` — EOF, not `quit`); `stderr` empty. Proves `main.zig`'s read-file → `findMemory` → `applyImage` branch runs before `serve` without disturbing the `ready` block. |
| `sim --mem unknown memory exits 2 before the handshake` | `… --sim --mem=nosuch=tests/fixtures/mem/rom_pc_walk.bin` | `exitCode == 2`; `stdout.len == 0`; `stderr` contains `no memory named 'nosuch'` (Phase 3's message style, `PLANS_PROMPT.md` phase 3 row; the "declared memories" tail is not asserted). |
| `sim --mem missing image exits 2 before the handshake` | `… --sim --mem=code=tests/fixtures/mem/does_not_exist.bin` | `exitCode == 2`; `stdout.len == 0`; `stderr` contains `does_not_exist.bin`. |

`--analyze` contract delta (`Symbol` after the change):

```zig
pub const Symbol = struct {
    file_id: u32,
    name: []const u8,
    kind: []const u8,      // "rom" / "ram" for memories (Phase 0)
    width: u8,             // data width W for memories (Component.width = data_width, Phase 0)
    addr_width: ?u8 = null, // A; rendered as "addr_width":A only when non-null
    range: Range,
};
// JSON key order: file_id, name, kind, width, [addr_width,] range
```

Decision-record entries (house style `DOCS/decisions/validation.md:5-13`: `###` heading, **Decision.**/**Rationale.**/**Alternatives.**, ~15 lines each; each entry states the choice from `PLANS_PROMPT.md` and cites its evidence lines):

| File | Entry (`###` slug) | Locked decision |
|------|--------------------|-----------------|
| `decisions/language.md` | Memory declarations reuse `CallWidths` and reserve two type names | grammar unchanged; `[W, A]` in instance position; `rom`/`ram` reserved in `isPrimitive`-adjacent check, `isBuiltinName` (E006), `isBuiltinAlias` (E011) |
| `decisions/language.md` | Memory contents are runtime configuration, never source | the principle behind decisions 2–4 and 7 |
| `decisions/language.md` | ROM is combinational; RAM writes on a defined rising edge | decision 5 (edge rule, `prev_clk`-before-act, width-agnostic bit test, partial-X `din` stored as-is, any undefined `addr` bit ⇒ undefined `out`) |
| `decisions/language.md` | `ram` breaks combinational loops, `rom` does not | decision 6 |
| `decisions/language.md` | `E017`/`E018` plus reused codes through one port-width helper | decision 11 (`memoryPortWidth`, `E002`/`E004`/`E014` arms, `widthFromSpec` on `width_args[0..2]`) |
| `decisions/runtime-api.md` | One engine kind with a mode; two wire kinds; one IR variant | decision 1 |
| `decisions/runtime-api.md` | Cells are two `[]u64` planes on the payload | the width-bounds/planes constraint (a choice, not a necessity — the verifier showed the pool could host them) |
| `decisions/runtime-api.md` | Headerless raw image, `ceil(W/8)` bytes per word, strict padding | decision 2 (no magic sniffing, ever) |
| `decisions/runtime-api.md` | Load is replace-all | decision 3 |
| `decisions/runtime-api.md` | Eight memory exports with status codes | decision 4 (`memBuffer` allocate-once, `-1..-7`, `getMem*` return 0 on error) |
| `decisions/runtime-api.md` | Topology v03 memory records | decision 10 (7-byte `.min` record, `aux_lo = addr_width`, `Aux.memory`, `PortName` 4..7) |
| `decisions/runtime-api.md` | `--sim` preloads by declared name; verbs are additive at proto=1 | decision 7 (+ handshake byte-identical, root-level names only, `reset` semantics, preload failures to stderr/exit 2 before any handshake) |
| `decisions/runtime-api.md` | Tooling policy: truth-table ROM-only, preview boxes, emit-zig rejects | decision 8 |
| `decisions/runtime-api.md` | `--inspect` prints widths, not global ids | decision 9 |
| `decisions/cli.md` | `--mem` is scoped to sim and truth-table | decision 7's flag half: parse-time gating like `--strict`/`--format`, fixed `[16]` so `Args.parse` stays allocator-free, `TooManyMemPreloads`; cross-references the runtime-api.md verbs entry |

`DOCS/language.md` §6.5 contents (reference, not tutorial). Title: `### 6.5 Memories (\`rom\`/\`ram\`)`; it stays under `## 6. Multi-bit Wires` because the locked plan places it in §6 and because the section's story is *widths*: memories are the first primitives whose instance takes two width parameters, so the opening sentence ties it to §6.1/§6.3 ("`[W, A]` is the same `CallWidths` list a parametric sub-circuit takes, read as data and address widths") rather than renumbering §7/§8 (`:520`, `:572`) and every link to them. Body order: declaration shape recap → port table (`rom`: `addr`[A] in, `out`[W] out; `ram`: `addr`[A], `din`[W], `we`[1], `clk`[1] in, `out`[W] out) → width bounds `W ∈ 1..64`, `A ∈ 1..16` (`E018`) → X semantics (unloaded/unwritten cells undefined; any undefined `addr` bit ⇒ fully undefined `out`; write requires `we` defined-high and `addr` fully defined; partial-X `din` is stored as-is) → the edge rule (defined-low → defined-high only; the first `set clk 1` after init is not an edge; `clk` is an ordinary width-1 input) → host-loaded contents (image format one-liner, `--mem`, `load`/`poke`, WASM exports by name, cross-links to `sim-protocol.md`/`wasm-api.md`) → E008 policy → parametric `ram m[W, A]` inside `<W, A>` sub-circuits. The §4.1 bullet: "A memory declaration must carry exactly two width arguments `[W, A]` (`E017`) with `W` in 1..64 and `A` in 1..16 (`E018`); see §6.5."

`DOCS/getting-started.md` §7 outline. One file name throughout: the reader saves the fixture's text as `prog_rom.circ` ("this is `tests/fixtures/circuits/sim_rom_pc_walk.circ` verbatim"). 7.1 the circuit · 7.2 author an image: `printf '\020\041\062\103' > prog.bin` (octal escapes — POSIX `printf` guarantees them, `\xHH` is a bash/zsh extension; the doc says so in one parenthetical), `xxd prog.bin` expected output, the one-rule format sentence (`ceil(W/8)` bytes per word, little-endian, high padding bits must be zero) · 7.3 `circ-compile prog_rom.circ --sim --mem=code=prog.bin` with the expected transcript for `set pc 0` … `mem code 0 4` · 7.4 a RAM (`sim_ram_write_read.circ` saved as `scratch_ram.circ`), stepping with `set clk 0` / `set clk 1`, then the interactive recipe `poke data 0 0x2a` … `save data ram.bin` and `xxd ram.bin` · 7.5 Node host snippet using the Phase 2 exports (from `wasm-api.md`, kept in sync):

```js
const mem = /* id of the kind-8/9 record named "code" in circ.topology.v0.full */;
const info = w.getMemInfo(mem); if (info < 0) throw new Error("not a memory");
const W = (info >> 8) & 0xff, A = info & 0xff;
const img = fs.readFileSync("prog.bin");
const ptr = w.memBuffer(mem);                       // may grow memory: re-view after
new Uint8Array(w.memory.buffer).set(img, ptr);
const rc = w.memLoad(mem, img.length); if (rc !== 0) throw new Error(`memLoad ${rc}`);
w.setPin(pc_id, 3n, 0xfn);                          // setPin settles (circuit.zig:825); run() is optional parity
console.log(w.getOutputValue(mem), w.getOutputDefined(mem)); // 0x43n, 0xffn
const n = w.memStore(mem);                          // bytes written into the same buffer
fs.writeFileSync("rom-after.bin", new Uint8Array(w.memory.buffer, w.memBuffer(mem), n).slice());
```

## Execution & Concurrency Model

This phase is fully synchronous. No background threads or workers are introduced. The golden test runs each fixture sequentially inside one test (`serializer_fixtures_test.zig:273-278` pattern), each with its own arena; `serve` owns its `Circuit`/`Session` per call (`loop.zig:79-84`) so fixtures share no state. The three CLI cases each spawn one short-lived child that exits at stdin EOF; Zig runs the test binary serially so the once-built `circ-compile` (`integration_test.zig:38-`) needs no synchronisation.

## Persistence & I/O

Reads (test time): fixture `.circ` files via the resolver's file loader, `tests/fixtures/sim/*.script` and `tests/fixtures/mem/*.bin` via `std.fs.cwd().readFileAlloc`, and — inside `serve` — the script's `load` paths (Phase 3's cwd-relative read); the CLI cases read the same fixtures through the spawned binary. Writes: only under `UPDATE_GOLDENS=1`, to `tests/fixtures/expected-sim/*.txt` (`golden.zig:11-16`). The family never invokes `save`; the CLI cases never reach a verb; nothing else writes. Docs recipes describe user-side `printf`/`xxd`/`save` file I/O only. `DOCS/STATUS.md` gains one entry per slice.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | `expected-sim` golden family + spawned `--mem` cases | `tests/sim/golden_test.zig`; `build.zig` wiring; two sim circuits; four scripts; three `mem/*.bin`; four transcripts generated with `UPDATE_GOLDENS=1 zig build test` and reviewed line-by-line; three `tests/cli/integration_test.zig` cases; `tests/README.md` entries. Commit: `test(sim): add expected-sim golden family and spawned --mem CLI cases`. | `zig build test` green; `git status` shows only the new files plus the two modified test/README files; every "load-bearing transcript line" in Data & State is present in the committed golden; `sim_and_gate.txt` lines 1–4 equal today's empirical handshake for `and_gate.circ`; deleting any golden makes the test fail with `GoldenFixtureMissing`; the spawned-CLI success case's stdout equals the handshake block byte-for-byte and both failure cases have `stdout.len == 0`. |
| 2 | `--analyze` `addr_width` | `Symbol.addr_width`, symbol-loop extraction, `renderJson` conditional key, two inline tests; `DOCS/analyze-api.md` example + bullet. Commit: `feat(analyze): report addr_width on rom/ram symbols`. | Inline tests pass (below); `echo "{\"root_path\":\"$PWD/tests/fixtures/circuits/sim_rom_pc_walk.circ\"}" \| zig-out/bin/circ-compile --analyze` (absolute `root_path` per `analyze-api.md:37`; `overlays` omitted so the file is read from disk) output contains `"kind":"rom","width":8,"addr_width":4` and the `pc` symbol has no `addr_width` key; every pre-existing analyze test unchanged. |
| 3 | Decision records | Two `## Native memories` folds (14 entries per the table), one `cli.md` entry, the one-sentence pointer in "Things deliberately *not* exported", the `compiler-pipeline.md:29` clause, `decisions/index.md` bullets. Commit: `docs(decisions): record the native memory design decisions`. | Review only: each entry names its decision number from `PLANS_PROMPT.md` in the rationale, no entry contradicts the fixed vocabulary, `index.md` conventions (`:52-55`) hold (unnumbered `###`); `grep -n getOutputDefined DOCS/decisions/compiler-pipeline.md` shows the non-exhaustive clause. |
| 4 | Classroom docs | `language.md` §6.5 + §4.1 bullet + §3.5 cross-link; `circuit-format.md` rows + v03 code table and its site mirror; `getting-started.md` §7 + `:153` fix + "Where to go next" and its site mirror; `DOCS/index.md:3`; the Logisim note (location per Open Questions). Commit: `docs: document rom/ram semantics and the ROM-loading walkthrough`. | Every command in §7 is executed against the built CLI and its shown output pasted verbatim (the `xxd` dump, the `--sim` transcript, the Node output); the Node snippet's export names and status codes match `DOCS/wasm-api.md` (Phase 2) exactly; `diff DOCS/getting-started.md site/src/pages/reference/getting-started.md` and the same `diff` for `circuit-format.md` show only front-matter and link-rewrite hunks, as today; `grep -rn "getOutputDefined" README.md DOCS site CLAUDE.md` finds no sentence that still presents the six names as the complete export list. |

Slices are ordered by dependency. Each slice must be fully reviewable on its own. Slice 1 first because the transcripts it commits are the ground truth the §7 walkthrough in slice 4 quotes.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `analyze: memory symbols carry addr_width` | `lib/analyze/analyze.zig` (inline, after `:512`) | Overlay `input[4] pc\nrom code[8, 4](addr = pc)\noutput[8] instr(in = code.out)\n`: symbol `code` has kind `"rom"`, `width == 8`, `addr_width.? == 4`; symbol `pc` has `addr_width == null`; zero error diagnostics. |
| `analyze: renderJson emits addr_width only for memories` | same | Render the analysis above into an `ArrayList(u8)`: contains `"kind":"rom","width":8,"addr_width":4,"range"`; the substring `"name":"pc","kind":"input","width":4,"range"` is present (no `addr_width` between `width` and `range`). |
| `sim golden: fixture inputs exist` | `tests/sim/golden_test.zig` | For each fixture the hand-authored inputs exist: `tests/fixtures/sim/<name>.script`, `root_path`, and every preload `path` (catches a renamed fixture with a clear name). The transcript `.txt` is checked only when `!updateModeEnabled()` — on the first `UPDATE_GOLDENS=1` run the transcripts do not exist yet and `expectGolden` writes them, so the generation run must stay green; in compare mode a missing `.txt` is already `GoldenFixtureMissing` from `expectGolden`. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `sim golden: transcripts match` (`tests/sim/golden_test.zig`) | source → project pipeline → `FullTopology` → `serve` | Byte-exact transcript for all four fixtures; the load-bearing lines in Data & State (handshake byte-identity, ROM async read + undefined addr, `load` resync without `set`, replace-all, `reset` re-applying the preload, X→1 not an edge, defined-low→high commit, `we` low blocks, `poke`/`peek`/`clear`, every memory error code from real source). |
| `sim --mem preload prints the unchanged handshake` / `… unknown memory exits 2 before the handshake` / `… missing image exits 2 before the handshake` (`tests/cli/integration_test.zig`) | spawned `circ-compile`, stdin at EOF | The three rows in Data & State: exit 0 with stdout equal to the handshake block; exit 2 with empty stdout and the name / the path on stderr. This is the only coverage of `main.zig`'s preload branch (Phase 3 tests `args.zig` and `serve` in isolation). |
| Existing suites | whole tree | `zig build test` green; every pre-existing golden byte-identical (`git status` shows only files listed in this phase). |
| Docs executed | manual, slice 4 | Every shell/Node block in `getting-started.md` §7 reproduces its pasted output against `zig-out/bin/circ-compile`. |

Run command: `zig build test` (the family is aggregated under the `test` step; `zig test` cannot run `tests/sim/golden_test.zig` alone because it needs the module graph and the parser archive — same limitation as `serializer_fixtures_test.zig`). Regenerate with `UPDATE_GOLDENS=1 zig build test`, then `git diff --stat tests/fixtures` must list only `expected-sim/`.

## Open Questions / Spikes

- `TODO(phase4)`: the Logisim-import note — `example/` is **gitignored** (it exists only in the maintainer's local checkout, never on the branch), so `example/logisim-import/NOTES.md` can never land in a commit. Confirm with the human whether to place the note at `DOCS/logisim-import.md` (adding it to the `DOCS/index.md:19-32` table) or drop it from this phase.
- Reply shapes are Phase 3's locked grammar (`DOCS/sim-protocol.md` Commands table): `mems <N>` / `mem <name> <rom|ram> <W> <A>` (decimal W/A), `ok words=<n>`, `cells <N>` + `<addr> <value> <mask>` (hex), `err E_IO <path>: <errname>`, `err E_MEMFMT <path>: <reason>`, `err E_WIDTH <mem>`, `err E_ADDR <mem> <0xaddr>`; `serve` is `serve(alloc, topology, file_path, diags, preloads: []const sim_loop.Preload, reader, writer)`. Regenerate goldens only after Phase 3 is merged and read every line against these.
- None otherwise — the eleven decisions in `DOCS/PLANS_PROMPT.md` cover every choice this phase records.
