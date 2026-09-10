# Archived plan: memories

**Canonical commit:** `2e15e97b973d822373d2b078dd0261fc3974b989` (`2e15e97 perf(engine): box the memory payload and bench two ROM fixtures`)
**Archived on:** 2026-09-09
**Plan duration:** 2026-09-07 → 2026-09-08

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show 2e15e97b973d822373d2b078dd0261fc3974b989:DOCS/PLANS_PROMPT.md`, etc.) when you need the unabridged source.

## Goal & scope

The circ language gains two native memory primitives, `rom` and `ram`, declared with the shape the grammar already parsed — `rom code[8, 4] (addr = pc)` and `ram data[8, 4] (addr = a, din = d, we = w, clk = clk)`, where `[W, A]` is the existing `CallWidths` production read as `[data_width, address_width]` (zero changes to `lib/grammar/proto-circ.peg`). Memories are engine primitives, not gate macros; memory contents never appear in source — they are runtime configuration loaded and read back by a host through eight WASM exports, by `--sim`/`--truth-table` through `--mem=<name>=<path>`, and by `--sim` verbs addressed by declared name. The in-transit currency is a headerless raw image of little-endian words, `ceil(W/8)` bytes per word, so an assembler's `.bin` or a `printf`-built file loads with no converter; unloaded and unwritten cells read as undefined through the existing `BitVecState` story. ROM is purely combinational (`out = cells[addr]`, any undefined address bit yields a fully undefined output, gate delay). RAM is single-port with asynchronous read and a clocked edge write: the write commits inside the RAM's own recalc arm when `clk` goes defined-low → defined-high (X→1 is not an edge), `we` is defined-high, and `addr` is fully defined; `prev_clk` is stored before acting so the detector is idempotent across Phase-2 recalcs in one timestep. The clock is an ordinary width-1 input pin the host pulses with `setPin` — no clock construct, no `tick()` export. Constraints that shaped the work: wire kind encodings and diagnostic codes are append-only (`rom=8`/`ram=9`, `E017`/`E018`); `PortName` is a closed `u8` enum (`addr..clk` = 4..7); topology bumps `0x02 → 0x03` with v02 rejected by both readers; no allocator parameters on the engine (`memory.allocator` is an arena over `page_allocator`); one engine node per memory record so positional ids stay dense; one output port per component (memories expose only `out`); cells live as two `[]u64` planes on the payload, not in the state pool; `W ∈ [1, 64]`, `A ∈ [1, 16]`; `--sim`'s `ready` block stays byte-identical and `proto` stays `1`; existing scalar `.circ` files and goldens stay byte-stable.

## Phase-by-phase highlights

### Phase 0 — Language front door

The compiler *understands* `rom`/`ram` (IR, `--inspect`, `--analyze`, the validator contract), but every artifact-producing mode refuses them with `rom/ram are not yet supported in this mode`, exit 1, no partial output.

- `ir.ComponentKind.memory` (`Memory { mode, data_width, addr_width, arg_count, type_width_given }`); resolver recognises `rom`/`ram` before primitives and import aliases, both `width_args` via `widthFromSpec` so parametric `ram m[W, A]` binds.
- Every exhaustive `ComponentKind` switch gained an arm: `--inspect` `kind=rom[W=8,A=4]` + `width_args=[8, 4]`; `--analyze` symbol kinds `rom`/`ram` with hover `rom[8,4] code`; `expected-inspect/rom_basic.txt`.
- `E017` (memory parameter list malformed) and `E018` (memory width out of range) appended to `lib/validator/codes.zig`; new pass `lib/validator/passes/memory_validation.zig` wired into `validator/run.zig`; `E018` suppressed when `E017` fired.
- Fixtures `E017_memory_{no_widths,one_width,type_width,ident_list}.circ`, `E018_memory_width_range.circ`; the identifier-list form `rom a, b` reports one `E017` per name (the translator emits one component per name).
- Reused codes gained memory arms through `memoryPortWidth` (addr=A, din=W, we=1, clk=1, out=W): `E002_memory_unknown_port`, `E004_memory_missing_ports`, `E014_memory_port_width`; no contract while `[W, A]` is malformed, so `E017` never cascades into `E014`.
- Name reservation: `E006_shadows_memory.circ` (`name_collision.isBuiltinName`), project `E011_memory_alias/` (`scan_imports.isBuiltinAlias`); an existing `import rom` now collides instead of degrading to `W003`.
- `E008` policy: `ram` is cycle-breaking, `rom` is not — `E008_rom_loop.circ` vs `clean_ram_feedback.circ`, both looping through a `wire` because gates already break cycles.
- Project fixture `projects/memory_parametric/{root,mem_wrap}.circ` with an empty `memory_parametric_clean.txt` golden proves `ram m[W, A]` inside a `<W, A>` sub-circuit instantiated at `[8, 4]`.
- `reportBackendError` in `cmd/circ-compile/main.zig` replaced twelve raw `<context>: <ErrorName>` prints; `--emit-zig` rejection (`MemoryUnsupportedInEmitZig`) is permanent; the serializer rejection was temporary.
- Test `cli memory sources are rejected in every artifact mode` (five spawned invocations); the `E001-E016` range became `E001-E018` in README, CLAUDE.md, `DOCS/*.md`, and the site mirror.

**Deviation:** the `--analyze` zero-diagnostics proof lives in an inline `analyze` test, not a spawned-CLI case — the CLI test helper cannot feed stdin (`Child.run` uses `.Ignore`). `dead_code`/`name_resolution` needed no memory arms.

### Phase 1 — Engine memories + image codec

`lib/circuit.zig` gains a `memory` kind a library client can create, wire, drive, and mutate through host hooks, plus `lib/memimage.zig`; no user-visible change (Phase 0's rejection stayed).

- `lib/circuit.zig` became its own `addTest` root (`engine_tests` in `build.zig`): 52 never-executed inline tests now run, one latent slice assertion fixed (`Pool.write` canonicalises `value & defined`, so `0b01` not `0b11`).
- `lib/memimage.zig`: `bytesPerWord`, `maxImageSize`, `validate`, `decode` (replace-all, rejected image leaves planes untouched), `encode` (`value & defined`), `MemoryImageError { LengthNotWordMultiple, WordExceedsWidth, TooManyWords }`; re-exported as `pub const memimage` from `circuit.zig`.
- `ComponentType.memory` with `MemoryMode { rom, ram }`, `MemCells { addr_width, values, defined }` planes zero-allocated in `createComponent` (`error.InvalidAddrWidth` for `A ∉ 1..16`), `MAX_ADDR_WIDTH = 16`, `memoryReadOut`, `memoryCells`; `connect` accepts `addr` on both modes, `din`/`we`/`clk` only on ram.
- Dead `toKind` deleted (its numbering contradicted the wire format); `transport.kindByte` maps mode → 8/9; CLAUDE.md, `DOCS/simulation-engine.md`, `DOCS/architecture.md` describe nine kinds citing `format.zig` as the encoding truth.
- RAM rising-edge write in the recalc arm via a `|*m|` pointer capture: `prev_clk` stored before acting, width-agnostic `bit0High`/`bit0Low` tests for `we`/`clk` (`isHigh`/`isLow` assert `width == 1`), partial-X `din` stored canonically.
- Engine tests: `ram: writes only on defined-low to defined-high`, `ram: no double fire when clk and din change together`, `ram: level changes while clk high do not write`, `ram: width-agnostic we/clk bit test`, `memory: async read through undefined addr`.
- Host hooks `Circuit.memoryWriteWord`/`memoryClear`/`memoryLoadImage`/`memoryStoreImage` (`NotAMemory`, `AddressOutOfRange`, `BufferTooSmall`), each ending in private `memoryRefresh`: asserts an empty queue, recomputes `out`, `propagateEvent` only when `BitVecState.equals` says it changed.
- Tests `memory: host write to presented address resyncs out`, `memory: no-op refresh does not bump current_time`, `memory: failed load leaves cells untouched`; `memimage.zig` added to the emit-zig smoke's engine copy list in `tests/helpers/wasm_run.zig` (`test-all` had failed with `unable to load 'memimage.zig'`).

**Deviation:** hook error sets are inferred (`!`) rather than the spec's spelled-out unions; `TODO(phase1)` (mutator called mid-propagate) stays a Debug assert — no host callback runs during `propagate`.

### Phase 2 — Topology v03, runtime, WASM memory exports

`circ-compile rom.circ -o rom.wasm` produces a self-contained v03 artifact whose host can discover, stage, load, mutate, read back, export, and wipe a memory; `--preview`, `--truth-table`, `--sim` handle memories; `--emit-zig` rejects by design.

- `format.VERSION`/`full_format.FULL_VERSION` → `0x03`; `ComponentKind.rom = 8`, `.ram = 9`; `PortName.addr = 4`, `.din = 5`, `.we = 6`, `.clk = 7`; `.min` memory record is 7 bytes (`aux_lo` = `addr_width`); `.full` gains `Aux.memory { addr_width }`.
- Both serializers, `full_decoder`, `templates/interpreter.zig` (`InvalidMemoryRecord`, `TruncatedPayload`, `memKindByte`), `engine_session.Session.build`, all five port-byte mappers, and `preview/layout/route.portByteOf` learned memories; `serializer.ProjectTopology.memory_ids` lists root memories by name.
- Tests `full_decode_rejects_v02`, `interpreter: rejects v02 payload`, `serialize: rom/ram records carry addr_width suffix`, `session builds rom and ram nodes from memory records`; the 6-byte-stride walks became kind-aware.
- Phase 0's `MemoryNotYetSupported` arms removed and the CLI rejection test flipped in the same commit; `reportBackendError` keeps only `--emit-zig does not support rom/ram; compile to .wasm instead`.
- Preview: `VirtualNode.addr_width`, `sizing.memorySize`, labels `rom code[8,4]` / `ram data[8,4]`, rom = 1-input 3-row box, ram = 4-input 9-row box; goldens `preview/renders/{rom,ram}_basic.render.golden`.
- Truth table: `BuildError.StatefulComponent` + origin-agnostic `firstRamName` refuse any ram (root or nested) in `build()` and at the CLI pre-flight (`truth-table: ram '<name>' is stateful …; use --sim to drive it`); unloaded roms tabulate `?` (`rom_basic.truth.golden`); `truth_table_build_rejects_nested_ram`.
- `templates/main.zig` exports `getMemInfo`, `memBuffer`, `memLoad`, `memStore`, `memClear`, `setMemWord`, `getMemValue`, `getMemDefined` with status codes `0` / `-1..-7`; staging buffer of `maxImageSize(W, A)` bytes allocated once; `out` resyncs without `run()`.
- Test `topology host protocol: memory exports over a hand-built v03 payload` (`rom[8,4]`, `rom[12,2]` so `-2` is reachable, `rom[4,2]` so `-3` is reachable) in `tests/e2e/topology_protocol_test.zig`.
- `tests/e2e/section_writer_fixtures_test.zig` parses a `mem <name> [<hexbytes>]` preamble (`InvalidHexImage`, `PreloadAfterVector`, `UnknownMemory`) feeding `memBuffer`/`memLoad` after `init()`; fixtures `expected-wasm/{rom_lookup,ram_write_read}.txt`; `tests/README.md` documents the grammar.
- `DOCS/wasm-api.md` (+ site mirror) "Memory exports" section: id mapping via `.full`, edge rule, image format, staging protocol, status table with the `-4`-unreachable note; the stale "`setPin` only enqueues — call `run()`" sentence corrected (`setPin` settles).

**Deviation:** no `pin=0xNN/0xMM` notation was introduced — the harness's existing MSB-first `0/1/?` bit strings carry multi-bit values; `serializer_fixtures_test.zig` (scalar-only) untouched. `site/public/wasm/*.wasm` deliberately left at v01 (`circ-renderer` is pinned to full-format v01).

### Phase 3 — `--sim` and `--truth-table` memory ergonomics

`--sim --mem=code=prog.bin` has the ROM loaded before the byte-identical `ready` handshake; memories are discovered with `mems` and driven by name; `--truth-table --mem` tabulates a preloaded ROM.

- `lib/engine_session.zig`: `MemRef { name, component_id, kind, data_width, addr_width }`, `Preload { name, bytes }`, `collectMemories` (root-level only, `origin.len == 0`, `InvalidTopology` for a record without `Aux.memory`), `validateImage`, `Session.memories`, `findMemory`, `applyImage`.
- `--mem=<name>=<path>` in `lib/cli/args.zig`: repeatable, split at the first `=` after the prefix, fixed `[16]` array (`ParseError.TooManyMemPreloads` → `usage error: too many --mem flags (max 16)`), scoped to `--sim`/`--truth-table`.
- `main.zig` `resolvePreloads` runs after topology build and before any handshake byte; stderr line `--mem <name>=<path>: no memory named '<name>' (declared memories: rom code[8, 4], …)` / `file not found` / `failed reading file: <err>` / codec reason, exit 2; 16 MiB read cap (`IMAGE_READ_CAP`, `FileTooBig`).
- `serve(preloads)` applies preloads after `Session.build` and again after `reset`; `BuildOptions.preloads` + `BuildError.BadPreload` for the truth table; golden `truth_table/rom_lookup.truth.golden`.
- Tests `handshake unchanged with memories`, `preload is visible through the circuit and survives reset`, `truth_table_build_applies_rom_preload`, `sim_mem_unknown_name_exits_2_before_handshake`, `sim_mem_missing_file_and_bad_image_exit_2`.
- `protocol.Command` verbs `mems`, `load <mem> <path>`, `save <mem> <path>`, `peek <mem> <addr>`, `poke <mem> <addr> <value> [<mask>]`, `mem <mem> [<start> [<count>]]`, `clear <mem>`; `ErrorCode` appends `E_NOMEM`, `E_IO`, `E_MEMFMT`, `E_ADDR`.
- Reply shapes: `mems <N>` + `mem <name> <rom|ram> <W> <A>`; `load` → `ok words=<n>`; `save` → `ok words=<2^A>`; `peek` → `ok <value> <mask>`; `mem` → `cells <N>` block of `<0xaddr> <value> <mask>`; `set`/`get` on a memory stay `E_NOPIN`, memory verbs on a pin are `E_NOMEM`.
- Loop tests (tmpDir-backed): `load then read through addr, and load refreshes the presented address`, `save round-trips`, `ram write then peek`, `reset re-applies preloads and drops poke`, `memory error replies`.
- `DOCS/sim-protocol.md`: seven verb rows, nine error codes with `E_NOSETTLE` marked declared-but-never-emitted, a "Memories" section, a path-free transcript locked to the code by `serve: doc example session` (replays the doc's block against `serve`).

**Deviation:** `applyImage` uses an inferred error set (codec errors + `OutOfMemory`/`InvalidTopology`) rather than the spec's union; a successful `--sim --mem` run is observable only through a spawned CLI (landed in Phase 4).

### Phase 4 — Golden coverage, decision records, classroom docs

`--sim` behaviour is provable from source fixtures the way `expected-wasm` proves the artifact; decisions are recorded; a student can author, load, and step a ROM/RAM from the docs.

- `tests/sim/golden_test.zig` (`sim_golden_tests` root): `tests/fixtures/sim/<name>.script` served in-process by `sim_loop.serve` through the same project pipeline `--sim` uses, transcript compared against `tests/fixtures/expected-sim/<name>.txt`.
- Goldens `sim_and_gate` (handshake tripwire, `mems 0`), `sim_rom_pc_walk` (new `sim_rom_pc_walk.circ`, preloaded from `mem/rom_pc_walk.bin`: async read, mid-session `load` resync, replace-all, `reset`), `sim_ram_write_read` (new `sim_ram_write_read.circ`), `sim_mem_errors` (every memory error code).
- Raw images `tests/fixtures/mem/*.bin` with their `printf`/`head` recipes in `tests/README.md`; spawned-CLI cases `sim --mem preload prints the unchanged handshake`, `sim --mem unknown memory exits 2 before the handshake`, `sim --mem missing image exits 2 before the handshake`.
- `--analyze`: `Symbol.addr_width: ?u8` rendered as `"addr_width":A` between `width` and `range` only for memories (key order `file_id, name, kind, width, addr_width, range`); `DOCS/analyze-api.md` updated; `analyze: renderJson emits addr_width only for memories`.
- Decision records: `## Native memories` folds in `DOCS/decisions/language.md` (five entries) and `DOCS/decisions/runtime-api.md` (nine entries), "`--mem` is scoped to sim and truth-table" in `decisions/cli.md`, non-exhaustive export clause in `compiler-pipeline.md`, `decisions/index.md` bullets.
- `DOCS/language.md` `### 6.5 Memories (rom/ram)` (ports, bounds, read/write rules, three contents doors, `E008` policy, parametric example) + §4.1 `E017`/`E018` bullet; §3.5's Phase 0 "not yet supported" paragraph replaced by a cross-link.
- `DOCS/circuit-format.md` `rom`/`ram` component rows and a "memory codes added with v03" table; `DOCS/getting-started.md` `## 7. Loading a program into ROM and stepping a clocked circuit` (7.1–7.5, every output pasted from a real run against the built CLI and Node 24).
- `DOCS/logisim-import.md` (new): Logisim `ROM`/`RAM` → `rom`/`ram` port mapping, unmodelled pins, `v2.0 raw` converter out of scope; listed in `DOCS/index.md`. Site mirrors regenerated with `bun site/scripts/sync-reference.ts`.

**Deviation:** the Logisim note landed at `DOCS/logisim-import.md` rather than `example/` (gitignored) — the plan's open question, resolved by placement.

### Follow-up — bench regression, ROM bench fixtures (same STATUS log)

- The inline `memory` union member had grown every `Component` by 56 bytes (`bytes` counter +11–17% on all 56 bench fixtures); the payload is now boxed: `pub const MemoryState`, `Kind.memory` is `*MemoryState`, built by `memoryKind(mode, addr_width)`, freed by `Component.deinit`.
- Bench corpus gains a Memories tier: `rom_lookup` and `rom_lookup_8bit` (new `rom_lookup_8bit.circ`, 256 × 8-bit) preloaded via `Fixture.preload` → `truth_table_builder.build`'s `preloads`; `engine.bench.golden` +2 rows, 56 pre-existing rows byte-identical; `DOCS/benchmark.md` updated.

## Diagnostic / API surface frozen by this plan

### Diagnostic codes (`lib/validator/codes.zig`)

| Code | Meaning |
|------|---------|
| `E017` | memory parameter list malformed — `rom`/`ram` take exactly two instance-position width arguments `[W, A]`; fires for 0/1/3 args, the type-position form `rom[8] m[8, 4]`, and once per name for `rom a, b` |
| `E018` | memory width out of range — `W` in 1..64, `A` in 1..16; suppressed when `E017` fired |

Existing codes with memory arms: `E002` (unknown port), `E004` (required port unconnected: rom `addr`; ram `addr`, `din`, `we`, `clk`), `E006` (instance/input named `rom`/`ram`), `E008` (`ram` breaks cycles, `rom` does not), `E011` (`import rom`/`import ram` alias), `E014` (per-port width via `memoryPortWidth`). Snapshot guard: `tests/validator/codes_snapshot_test.zig`.

### Topology format v03 (`lib/topology/format.zig`, `full_format.zig`)

`VERSION = 0x03`, `FULL_VERSION = 0x03` (v02 rejected by `templates/interpreter.zig` and `lib/topology/full_decoder.zig`). `ComponentKind.rom = 8`, `ram = 9`. `PortName.addr = 4`, `din = 5`, `we = 6`, `clk = 7`. `.min` memory record `id u32 | kind u8 | width u8 (= W) | addr_width u8`; `.full` `Aux.memory { addr_width }`. Contents never travel in the topology.

### WASM runtime exports (compiled artifact, `templates/main.zig`)

| Export | Returns |
|--------|---------|
| `getMemInfo(id)` | `(kind << 16) \| (W << 8) \| A`, or `-1` |
| `memBuffer(id)` | pointer to a per-memory staging buffer of `ceil(W/8) << A` bytes, allocated once; re-view `memory.buffer` after the call |
| `memLoad(id, len)` | status; replace-all from the staging buffer |
| `memStore(id)` | bytes written (`value & defined`) into the staging buffer |
| `memClear(id)` | status |
| `setMemWord(id, addr, value, defined)` | status |
| `getMemValue(id, addr)` / `getMemDefined(id, addr)` | `i64` pair, `0` on any error |

Status codes: `0` ok; `-1` uninitialised / bad id / not a memory; `-2` length not a word multiple; `-3` word exceeds width; `-4` too many words (unreachable through `memLoad`); `-5` `len` exceeds staging size; `-6` `memBuffer` never called; `-7` address out of range. Ids are positional, the same as `setPin`; hosts find a memory's id from its `.full` record (kind 8/9, `name`, empty origin).

### Image format (`lib/memimage.zig`)

Headerless, little-endian, `bpw = ceil(W/8)` bytes per word, word `i` at `[i*bpw, (i+1)*bpw)`, bits `>= W` must be zero, `len % bpw == 0`, `len / bpw <= 2^A`; load is replace-all (short image leaves the tail undefined, empty image = clear); export writes `value & defined`; no magic sniffing.

### CLI (`circ-compile`)

- `--mem=<name>=<path>` — repeatable (max 16, `TooManyMemPreloads`), split at the first `=` after the prefix, accepted only with `--sim` and `--truth-table`; failures exit 2 on stderr before any handshake byte.
- `--sim` verbs (proto stays `1`, `ready` block unchanged): `mems`, `load <mem> <path>`, `save <mem> <path>`, `peek <mem> <addr>`, `poke <mem> <addr> <value> [<mask>]`, `mem <mem> [<start> [<count>]]`, `clear <mem>`; error codes `E_NOMEM`, `E_IO`, `E_MEMFMT`, `E_ADDR` (reusing `E_WIDTH`, `E_BADVAL`, `E_PROTO`, `E_NOPIN`); `reset` re-applies CLI preloads and drops mid-session `load`/`poke`.
- `--truth-table` tabulates ROMs (unloaded cells `?`, `--strict` fails them) and refuses any RAM with `error.StatefulComponent`; `--emit-zig` refuses memories (`--emit-zig does not support rom/ram; compile to .wasm instead`); `--inspect` prints `kind=rom[W=8,A=4]` / `width_args=[8, 4]`; `--analyze` adds `"addr_width"` on `rom`/`ram` symbols.

### Engine (`lib/circuit.zig`)

`ComponentType.memory` with `MemoryMode { rom, ram }`, `MemoryState` (boxed payload), `MemCells`, `MAX_ADDR_WIDTH = 16`, `MemoryError`; `memoryKind(mode, addr_width)`; hooks `memoryWriteWord`, `memoryClear`, `memoryLoadImage`, `memoryStoreImage`; `memoryReadOut`, `memoryCells`; `pub const memimage`. Ports `addr` (both), `din`/`we`/`clk` (ram only); single output `out`; gate delay.

## Known papercuts carried forward

- **Width literals `> 255` vanish silently.** `lib/syntax/translate.zig` parses widths as `u8` and `catch {}`es the failure, so `rom m[8, 300](...)` drops the whole declaration with no diagnostic and `E018` can never fire for it. Pre-existing hole, documented not fixed.
- **`--sim reset` leaks memory planes.** The arena never frees; every `reset` rebuilds the `Session` and leaks ~1 MiB per `A=16` memory. A `Circuit.reset()` reusing planes is the fix.
- **`-4` (`TooManyWords`) is unreachable through `memLoad`.** The staging buffer is exactly one full image, so an oversize `len` returns `-5` first; the code exists for parity with `MemoryImageError` and is reachable via `--sim load` (`E_MEMFMT`).
- **No name → global-id listing for hosts.** `--inspect` ids are resolver-local; hosts must decode the `.full` section to find a memory's (or pin's) positional id. A listing mode that runs the serializer is a separate follow-up.
- **Nested memories are not `--sim`-addressable.** Only root-level memories (`origin.len == 0`, mirroring pins) appear in `mems`/preloads; nested ones remain id-addressable from a WASM host only.
- **`--sim` paths are whitespace-free and cwd-relative.** The tokenizer splits on whitespace; a failed `save` may leave a partial file (no temp-and-rename); the image read cap is 16 MiB and is exercised only by a `writeImageError` unit test.
- **Preload failure hides warnings.** When `--mem` fails before the handshake, the `diag` lines that would have appeared in `ready` are printed nowhere.
- **`site/public/wasm/*.wasm` are still v01.** `site/node_modules/circ-renderer/src/wasm/topology.ts` is pinned to `FULL_VERSION = 0x01`; do not recompile the committed site artifacts until the renderer is updated.
- **`--truth-table --strict` on an unloaded ROM exits 1** with `undefined output` rows by design; only a `--mem` preload makes a ROM tabulate values.
- **RAM cannot be benched.** The bench harness drives `truth_table_builder.build`, which refuses `ram`; only ROM fixtures are in the corpus. The bench `topology` hash ignores widths and `addr_width`, so both ROM rows share hash `9491f678`.
- **`TODO(phase1)` remains a Debug assert.** `memoryRefresh` asserts an empty queue; a host hook invoked from inside a listener callback mid-propagate is unguarded because no such path exists in this runtime.
- **Zig collects tests only from a test root's own module.** A `test { _ = mod; }` hook in another root does not run a separate `createModule`'s tests; `memory_validation` and `circuit.zig` each needed their own `addTest` root, and any new pass module needs the same.
- **`getting-started.md` links `sim-protocol.md` as plain text** because the site sync script has no page for it; `DOCS/sim-protocol.md` has no site mirror.

## Decisions & specs that survived the plan

Authoritative docs remain outside this archive:

- `DOCS/architecture.md`, `DOCS/simulation-engine.md` (nine kinds; `format.zig` is the encoding truth)
- `DOCS/circuit-format.md` (v03 records, `rom`/`ram` rows, `E017`/`E018`)
- `DOCS/wasm-api.md` ("Memory exports": staging protocol, status codes, image format)
- `DOCS/sim-protocol.md` ("Memories": `--mem`, the seven verbs, the four error codes)
- `DOCS/language.md` §3.5 and §6.5, `DOCS/analyze-api.md` (`addr_width`), `DOCS/getting-started.md` §7, `DOCS/logisim-import.md`, `DOCS/benchmark.md`
- `DOCS/decisions/language.md` and `DOCS/decisions/runtime-api.md` (`## Native memories` folds), `DOCS/decisions/cli.md` (`--mem` scoping), `DOCS/decisions/compiler-pipeline.md`; index at `DOCS/decisions/index.md`
