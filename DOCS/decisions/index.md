# Compiler Architecture Decisions

This directory captures the architectural decisions guiding the development of the `.circ` compiler — a CLI that consumes a `.circ` source file and produces a self-contained `.wasm` artifact simulating that specific circuit.

Each decision follows the format: **decision**, **rationale**, **alternatives**.

## Topics

### [compiler-pipeline.md](compiler-pipeline.md)
- Output artifact shape (single self-contained `.wasm` per circuit)
- Compilation pipeline (`.circ → topology binary → custom-section splice → .wasm`)
- IR shape: paired `circ.topology.v0.{min,full}` binary payloads
- Prebuilt runtime WASM embedded in the CLI via `@embedFile`
- `-Dwasm-optimize` (ReleaseSmall, stripped) for both wasm builds
- Host protocol: `topology_alloc` + memcpy + `init()`

### [runtime-api.md](runtime-api.md)
- Settle-only `run()` semantics
- Initial state is implicitly `undefined`; `init()` does not pre-settle
- Pin identification by component ID (no separate pin-index space)
- Paired `getOutputValue` / `getOutputDefined` BigInt exports
- `setPin(id, value, defined)` symmetry with the output getters
- Pull-based, no `onStateChange` callback
- Topology section copied into linear memory at startup
- Deliberately omitted: `deinit`, `reset`, `stop`, `getStateSnapshot`, `getTopology`, `getPendingEvents`, `getFileInfo`, `freeBuffer`
- Native memories (engine kind + mode, cell planes, raw image format, replace-all load, the eight memory exports, topology v03 records, `--sim` preloads and verbs, tooling policy, `--inspect`)

### [language.md](language.md)
- Sub-circuits emit a flat topology binary at serialize time
- Source-path debug info lives in `circ.topology.v0.full`, not on `Component`
- Built-in primitives (`and`, `not`, `wire`, `led`, `output_pin`, `input_pin`) vs auto-imported macro family (`or`, `nand`, `nor`, `xor`, `xnor`)
- Import statement syntax (`import name "path"`)
- LEDs vs `output` declarations
- Multi-bit wires (17 decisions: width syntax, bit numbering, slice/concat, parametric sub-circuits, topology v02)
- Native memories (`rom`/`ram` declarations via `CallWidths`, contents are runtime configuration, edge rule, `E008` policy, `E017`/`E018`)

### [validation.md](validation.md)
- Hard errors vs warnings vs accepted
- Combinational loops are hard errors
- `--warnings-as-errors` flag for CI strictness
- Diagnostic format (location + message; snippets deferred)

### [cli.md](cli.md)
- Five invocation modes (`-o`, `--emit-zig`, `--inspect`, `--preview`, `--truth-table`)
- Mode-specific flag gating (`--expand-macros`, `--format`, `--strict`, …)
- No intermediate `zig build` subprocess; no build-directory override
- `--mem=<name>=<path>` is scoped to `--sim` and `--truth-table`

### [tooling.md](tooling.md)
- Parser generated straight to Zig by the maintainer's langlang fork (supersedes the Go c-archive bridge)
- Pin = the fork's tag `go/v0.0.13-zig.2`; skew signal = the generated header's runtime sha256
- Generated parser vendored in the repo
- Contract pinned before the switch (`Errors (n)` dump, recovery goldens, `expected-analyze`)
- Go retired in one cut-over

### [libcirc.md](libcirc.md)
- One wasm module, ten `circ_*` exports, JSON in / bytes-or-JSON out, status codes 0–5
- Overlay-first virtual file loading (no disk on freestanding)
- Library memory model (per-call arena, library-owned result, `memory.reset()`)
- `-Dwasm-optimize` governs both wasm builds
- The renderer follows the compiler, once, per topology version
- Playground artifacts are committed; the module runs in a Web Worker
- Not exported through libcirc (`--sim`, `--emit-zig`, `--inspect`)

### [playground.md](playground.md)
- The compile fast path resolves implicit builtins (usage-aware `.project_if_imports`; `--inspect` unchanged)
- The JavaScript budget is per page and gzip is the gate (`bun run bundle`, `bundle-budget.json`, the build-free CodeMirror tripwire)
- The editor is CodeMirror 6 with a hand-written StreamLanguage (six exact-pinned packages, no meta-package, no autocomplete/search)
- The editor chunk loads on idle, not on interaction (dynamic `import()` after paint, textarea fallback, ungated lazy chunk)
- One token table, two consumers (`circ-tokens.mjs` feeds the TextMate grammar and the CodeMirror tokenizer; `rom`/`ram` were the bug)
- The editor palette is derived from the shiki themes (one `TAG_SCOPES` table, last-scope-wins, the TextMate `fontStyle` split into real CSS properties)
- Analyze offsets are mapped in a pure module (byte columns + `SplitFile.startLine` → absolute UTF-16 offsets; both producers; the snapshot guard)
- The marker format does not fork; `joinFiles` is its inverse (`isFileName`, `joinConflicts`, `NamedFile`, the three normalisations)
- The last file is the root; reorder is how you change it (no root field, `rootOf` is position)
- One editor state per file is what makes undo per-file (state-per-file, the pure index registry, the theme fan-out)
- Diagnostics are mapped once per tab, and listed once overall (file-local offsets, the total mapper, the per-tab staleness guard)
- The playground is an `app` layout variant of `Base.astro` (one `data-layout` attribute, scoped rules, `min-height: 0`)
- The splitter is one custom property and a WAI-ARIA separator (intent versus rendered ratio, pointer capture, nullable key handling)
- One localStorage key, one schema-versioned envelope (`normalize` drops unknown keys, LRU eviction, retry once, session disable)
- The status bar is a pure function of one input record (fixed precedence, the label written only on a kind change)
- Two debounces, a sequence counter per stage (claimed at fire time, guarded at every await, last good output dimmed)
- A share link carries the source in the fragment, under two keys (`#src=` deflate, `#src0=` plain, an 8 KB cap, failures as values)
- The fragment is scrubbed at parse time, before anything can read it (a classic inline script beats every deferred module; one-rule-at-a-time precedence)
- Scratch projects are flat, capped three ways, and never hold shipped text (ids for content, LRU eviction that spares the active project)
- The first edit forks a shipped example into your own project (fork on change, not on diff; a shared link arrives as your own project)
- The renderer exposes three host hooks, and the highlight reuses `hovered` (`onHover`, `setHighlight`, `getLayout`; two ids kept apart)
- Source and picture are joined by declared name, never by span (root file only, top-level boxes only, no snapshotted ranges)
- Settings are the envelope's sixth field, and the option names are the wire's (per-op projection, no second normaliser)
- One field is the truth-table cap, read by the pre-flight and by the request (decision 13's two enforcement points, merged)
- ROM images are session state, and the page refuses what the library would (same checks, same order; a ram gets no box)
- A live editor ships inert and shares one worker (touch-activated, one client per page, the editor chunk stays lazy)
- An expand link carries a reference when it can, and a source when it must (id while unedited; a told-about degrade over the cap)

### [preview-layout.md](preview-layout.md)
- The parity contract is a JSON projection, not either side's native type (`dump_json.zig`, camelCase common subset, one golden per fixture-mode)

## Conventions

- Decisions use `###` headings inside topic files.
- Each decision is small (decision / rationale / alternatives, ~15 lines).
- No numbering — decisions are referenced by heading slug. The multi-bit fold inside `language.md` is numbered §1–§17 only because it lifted the stage numbering from `DOCS/archive/plan-multi-bit-language.md` verbatim.
- The runtime principle of "few dependencies, Zig-only" applies across every decision unless explicitly noted.
