# Phase 0 — Builtins resolve; the bundle gets a budget

> **Dependencies:** None. Phase 0 is the first phase of the playground-v2 initiative and the only one that touches Zig. Every later phase (`DOCS/PLANS/PHASE_1_editor.md` … `DOCS/PLANS/PHASE_7_live_editors.md`) builds on the artifacts and the `bun test` baseline this phase leaves behind.
> **Warnings:** Read `DOCS/PLANS_PROMPT.md` (decisions 8, 14, 15; the Phase 0 row of the Phase Index; the Recurring Traps) and `CLAUDE.md` in full first. `CLAUDE.md`'s three git rules bind, with the per-slice commit waiver of `DOCS/PLANS_PROMPT.md`'s Working Loop. Diagnostic codes are append-only and this phase adds none. **No `tests/fixtures/expected-*` golden may change** — see *Goldens that must stay byte-identical* below. `zig build test-all` must be green after **every** slice, not only at the end; `bun test` and `bun --bun run build` likewise (plain `bun run build` fails on this machine — local `node` is x64 under Rosetta and rollup's native loader aborts). `site/node_modules` **is** installed in this worktree (astro `5.18.1`, vite `6.4.2`), contrary to the trap written into the plan prompt; `site/dist` is not. `SKIP_LIBCIRC_TEST=1` and `SKIP_WASM_E2E=1` are never the way to make a slice pass. `build.zig` is not `zig fmt`-clean (17 pre-existing trailing-whitespace lines); apply hunks without reformatting.

## Goal

After this phase, a single `.circ` file that instantiates a built-in macro without importing it — `xor s(a=a, b=b)` with no `import xor "<builtin>/xor.circ"` line — compiles to a real `.wasm` artifact through `circ-compile`, through `libcirc`, and through the committed `site/public/wasm/libcirc.wasm` that the browser playground drives, instead of returning `E001: undeclared name 'xor'` from a circuit that previews and tabulates perfectly (`DOCS/archive/plan-libcirc.md:191`; the page says "Compile reported diagnostics." at `site/src/components/Playground.astro:208` and the Simulate tab goes empty). The fix is one usage-aware predicate on the compile/emit fast path in `lib/libcirc/frontend.zig:171-175`, and every committed artifact is regenerated from that one compiler revision. In the same phase the site gains a per-page JavaScript budget: `bun run bundle` walks `dist/**/*.html`, sums each page's eager module graph raw and gzipped, and exits 1 over a committed ceiling in `site/bundle-budget.json`; a companion `bun test` case that needs no build asserts that nothing reachable from `Base.astro`, `Nav.astro` or `Footer.astro` imports `@codemirror/*`. Phase 1 therefore cannot leak an editor into the base bundle of `/`, `/reference/*` or `/download` without a red gate, and today's numbers are on record as the baseline it is measured against. `DOCS/STATUS.md` exists from the first slice, so every later session has the log the Working Loop reads on cold start.

## Scope

**In scope:**

- `lib/libcirc/frontend.zig`: a private `usesBuiltinMacro(ir.Module) bool` helper and the `.project_if_imports` arm of the route switch at `:171-175`. Nothing else in the route table moves.
- `build/frontend_modules.zig`: `libcirc.addImport("builtins", builtins);` — the module exists at `:178` but the `libcirc` module does not import it (`:295-323`).
- `lib/libcirc.zig:274-276`: `_ = frontend;` alongside `_ = json;` so the new inline tests are actually analysed and run under `libcirc_tests` (`build.zig:700-705`, wired into `test_step` at `:788`).
- One new fixture, `tests/fixtures/circuits/builtin_xor_anonymous.circ`, whose only `xor` sits in anonymous position (`ast.SignalSource.anonymous`, `lib/syntax/ast.zig:57`), pinning the predicate and the known specializer gap; it is **not** a compile fixture — see *The new fixture*.
- Test coverage for the new behaviour and for the invariants around it: inline route tests in `frontend.zig`; `full_adder_from_builtins.circ` joining `compile_fixtures` (`tests/libcirc/driver_test.zig:196-206`, retiring the comment at `:199-201`); `four_bit_adder` joining `drive_cases` (`tests/e2e/libcirc_wasm_test.zig:251-259`, retiring the comment at `:254-256`); a CLI test that pins the `--inspect` (`.single_module`) route against the currently-orphaned golden `tests/fixtures/expected-inspect/canonical_full_adder_root.txt`.
- Regeneration and commit of `site/public/wasm/libcirc.wasm` + `libcirc.manifest.json` (`bun run libcirc`) and a regeneration pass over the 11 committed example artifacts (`bun run scripts/compile-content.ts` after `zig build circ-compile`), whose bytes are expected to be **unchanged**.
- One new `bun test` case in `site/test/libcirc.test.ts` proving the regenerated module compiles a builtin-using single file with no import. No anonymous-position twin — see *The new fixture* for why that case cannot compile yet.
- `site/scripts/check-bundle.ts`, `site/bundle-budget.json`, a `"bundle"` script in `site/package.json`, and `site/test/bundle-graph.test.ts` (decision 14(a) and 14(b), decision 15's Phase 0 module list).
- Docs: `DOCS/STATUS.md` (created); `DOCS/decisions/playground.md` (created, registered in `DOCS/decisions/index.md` under *Topics*, carrying this phase's two decisions); `DOCS/decisions/libcirc.md:3` repointed from `DOCS/PLANS_PROMPT.md` to `DOCS/archive/plan-libcirc.md`; `DOCS/language.md:217-226`, whose text the change makes false, and `DOCS/getting-started.md:170` plus the `:187` *v0 papercut* blockquote, which names this exact fix as pending — both reach the site as `/reference/getting-started` via `bun run sync` (`site/scripts/lib/site-config.ts:22-27`); `DOCS/PLANS_PROMPT.md`'s resolved `TODO(phase0)` Open item and its stale `site/node_modules` trap.

**Explicitly deferred:**

- Any UI change to `site/src/components/Playground.astro`. The page is untouched in Phase 0; the visible effect (Simulate finally rendering for an import-free `xor`) comes from the regenerated wasm alone.
- `site/src/content/tour.ts:98`'s prose ("In a single-file program you import macros explicitly"). The step's `source` keeps its explicit `import xor` line at `:101`, which stays valid and stays the clearer teaching form; the sentence becomes optional rather than false. Editing tour content also moves the `/tour` page bytes, and the baseline is measured in this phase. Content work belongs to the phase that revisits the tour.
- Adding `tour-*.wasm` to `site/.gitignore`. The trap deliberately says "expect them in `git status`" (`DOCS/PLANS_PROMPT.md`, Pillar 4(a)); their visibility *is* the reminder not to stage them. Adding an ignore is the maintainer's call, not a slice's.
- A new `libcirc` export, a new `options` key, or any change to the `.single_module` / `.project` arms. Decision 8 rejected all four alternatives; none is reopened here.
- Raising `site/scripts/build-libcirc.ts:26-27`'s wasm budget (`614400 / 204800`). The module grows by one small helper; if it ever crossed that line the raise would be argued in STATUS with the measured number, not applied silently.
- Gating inline `<script is:inline>` bytes (e.g. `site/src/layouts/Base.astro:63-73`) in the bundle budget. Decision 14(a) defines the metric as the *eager module graph*; inline bytes are reported as an informational line only.
- Any CodeMirror install. Phase 1's first slice owns that; Phase 0 only builds the tripwire that will catch it.

## File & Module Topology

**New files:**

| Module/Package | File | Responsibility |
|---------------|------|---------------|
| fixtures | `tests/fixtures/circuits/builtin_xor_anonymous.circ` | Import-free root whose only `xor` is an anonymous nested instance; the case an AST-level scan would miss. Proves the IR scan sees it and pins the pre-existing anonymous-specialization gap (E012, not E001) — it does **not** compile, so it never joins `compile_fixtures`. |
| site scripts | `site/scripts/check-bundle.ts` | `bun run bundle`: walks `dist/**/*.html`, resolves each page's eager module graph, prints the per-page raw/gzip table, compares against `site/bundle-budget.json`, exits 1 over budget. |
| site config | `site/bundle-budget.json` | Committed ceilings (`default`, per-route overrides) plus the baseline rows measured in this phase. |
| site tests | `site/test/bundle-graph.test.ts` | Build-free companion: no module reachable from `Base.astro` / `Nav.astro` / `Footer.astro` may import `@codemirror/*`, `@lezer/*` or `codemirror`. |
| docs | `DOCS/STATUS.md` | Append-only slice log the Working Loop reads on cold start. Also heals the dangling reference at `.github/workflows/pr-tests.yml:62`. |
| docs | `DOCS/decisions/playground.md` | Playground-v2 decision entries, `###` headings per `DOCS/decisions/index.md:65-70`. Phase 0 writes two. |

**Modified files:**

| Module/Package | File | Change |
|---------------|------|--------|
| libcirc | `lib/libcirc/frontend.zig` | Add `const builtins = @import("builtins");`; add `fn usesBuiltinMacro(module: ir.Module) bool`; change the `.project_if_imports` arm at `:173`; add the inline route tests. Also update the `Route` doc comment at `:24-27` — `.project_if_imports` now takes the project route when the root declares an import **or** instantiates a built-in macro; only a macro-free, import-free root skips the import scan, so the contrast the second sentence draws against preview/truth-table/sim is gone. |
| libcirc | `lib/libcirc.zig` | `test { _ = frontend; _ = json; }` at `:274-276`. |
| build | `build/frontend_modules.zig` | `libcirc.addImport("builtins", builtins);` in the `:295-323` block (the `builtins` module already exists at `:178`). |
| cli | `cmd/circ-compile/main.zig` | `:255-258`: the comment explaining the compile/emit route is false in both halves after this change — the gate is no longer `has_imports`, and the asymmetry it explains is gone. Replace with: "Compile/emit_zig take the project route only when the root declares an import or instantiates a built-in macro (`frontend.usesBuiltinMacro`), so a macro-free, import-free root still skips the import scan and the perf budget holds; preview, truth_table and sim always take it." Comment only — the switch arms at `:259-260` are unchanged. |
| tests | `tests/libcirc/driver_test.zig` | Add `full_adder_from_builtins.circ` to `compile_fixtures` (`:196-206`); replace the comment at `:199-201`. `builtin_xor_anonymous.circ` does **not** join the list — see *The new fixture*. |
| tests | `tests/e2e/libcirc_wasm_test.zig` | Add the `four_bit_adder` `DriveCase` to `drive_cases` (`:251-259`); replace the comment at `:254-256`. |
| tests | `tests/cli/integration_test.zig` | Add `cli inspect full_adder project root still reports E001 for 'or'`, pinning `tests/fixtures/expected-inspect/canonical_full_adder_root.txt`. |
| site | `site/package.json` | Add `"bundle": "bun run scripts/check-bundle.ts"` to `scripts` (`:6-14`). |
| site tests | `site/test/libcirc.test.ts` | One case: `compiles a builtin-using single file with no import`. No anonymous-position twin — see *The new fixture*. |
| site artifacts | `site/public/wasm/libcirc.wasm`, `site/public/wasm/libcirc.manifest.json` | Regenerated by `bun run libcirc` from this phase's compiler revision. |
| docs | `DOCS/decisions/libcirc.md` | `:3`: `DOCS/PLANS_PROMPT.md` → `DOCS/archive/plan-libcirc.md`, so `(decision 7)` at `:39` and `(decision 8)` at `:47` keep resolving to the libcirc plan's ten and not to this initiative's fifteen. |
| docs | `DOCS/decisions/index.md` | Register `### [playground.md](playground.md)` under *Topics*, after the `libcirc.md` block at `:56-63` and before `## Conventions` at `:65`. |
| docs | `DOCS/language.md` | `:217-226`: the paragraph that says built-ins are auto-imported only when a file "has at least one explicit `import`" and that a single-file program must write the import. Reaches the site as `/reference` via `bun run sync` (`site/scripts/sync-reference.ts`, `site/scripts/lib/site-config.ts:16-21`). |
| docs | `DOCS/getting-started.md` | `:170`: §5's auto-import rule ("auto-imported when a file is part of a project — i.e. when the parser sees at least one `import` declaration") and `:187`'s *v0 papercut* blockquote, which names this exact fix as pending ("until the CLI is updated to run the project pipeline unconditionally"). Both are false for `-o` / `--emit-zig` after this change. **Narrow, do not delete, the papercut:** `--inspect` is `.single_module` and is untouched, so `:184`'s `--inspect` invocation still reports `E001`, and `tests/fixtures/expected-inspect/canonical_full_adder_root.txt:62` is the golden that pins it. Reaches the site as `/reference/getting-started` via `bun run sync` (`site/scripts/lib/site-config.ts:22-27`); it ships today at `site/src/pages/reference/getting-started.md:191`. |
| docs | `DOCS/PLANS_PROMPT.md` | Open items: delete the resolved `TODO(phase0)` modulepreload entry at `:188` (per the rule at `:186`, "Resolve it in the phase named … and delete the entry from this list") — slice 5. Recurring Traps → *Environment and tooling*, `:132`: correct the first bullet — `site/node_modules` **is** installed in this worktree (astro `5.18.1`, vite `6.4.2`); `site/dist` is not, and the CodeMirror half of that bullet stands until Phase 1's spike — slice 1. Trap upkeep is required by `:128`, so both edits are named in their slice's STATUS `Notes:` line. |

**New dependencies:** None. `check-bundle.ts` and `bundle-graph.test.ts` use only bun built-ins (`Bun.gzipSync`, `Bun.Glob`, `node:fs`, `node:path`) — the same shape as `site/scripts/build-libcirc.ts:63,78-86`. No CodeMirror package is installed in this phase.

## Data & State

### The usage-aware predicate (Zig)

`frontend.run` already resolves the root into `ir_module` at `lib/libcirc/frontend.zig:165`, above the route switch, so the scan costs one pass over an array that has already been built — no allocation, no extra I/O, and nothing new on the fast path for macro-free roots.

```zig
// lib/libcirc/frontend.zig — new import beside the existing ones (`:6-16`)
const builtins = @import("builtins");

/// True when the root instantiates a built-in macro (`or`, `nand`, `nor`,
/// `xor`, `xnor`) it never imported. The single-module resolve has no
/// builtin aliases in scope, so such an instance lands as
/// `.unresolved_name` (`lib/ir/resolver.zig:137`, kind at
/// `lib/ir/types.zig:63`); only the project pipeline auto-imports
/// `<builtin>/<name>.circ` for it (`lib/resolver/scan_imports.zig:234-265`).
///
/// Scans the IR, not `ast_file.components[]`: an anonymous nested instance
/// (`wire w(in = xor(a=a, b=b).out)` — `ast.SignalSource.anonymous`,
/// `lib/syntax/ast.zig:57`) never appears in `ast_file.components[]`, which
/// covers top-level instances only (`ast.ComponentInstance`,
/// `lib/syntax/ast.zig:41-47`), while `lib/ir/resolver.zig:246-252`
/// flattens it into `ir_module.components`.
fn usesBuiltinMacro(module: ir.Module) bool {
    for (module.components) |component| {
        switch (component.kind) {
            .unresolved_name => |name| {
                if (builtins.isMacroImportAlias(name)) return true;
            },
            else => {},
        }
    }
    return false;
}
```

The route switch (`lib/libcirc/frontend.zig:171-175`) changes on exactly one line:

```zig
    const project_route = switch (route) {
        .single_module => false,
        .project_if_imports => ast_file.imports.len > 0 or usesBuiltinMacro(ir_module),
        .project => true,
    };
```

Types this leans on, unchanged and not repeated here: `ir.Module.components: []const Component` (`lib/ir/types.zig:138-155`), `ir.Component.kind: ComponentKind` (`:84-90`), the `unresolved_name: []const u8` variant (`:63`), and `builtins.isMacroImportAlias(alias: []const u8) bool` over the five-entry `table` (`lib/resolver/builtins.zig:40-46,55-60`).

Why the predicate cannot over-trigger, and why the perf guard survives: a genuinely undeclared non-macro name (`mystery u1(in=a)`, `tests/fixtures/circuits/E001_undeclared.circ`) is still `.unresolved_name` but fails `isMacroImportAlias`, so the root keeps the fast path and still reports `E001`. `tests/fixtures/circuits/stress_grid_10x10.circ` contains only `input`, `and` and `output` declarations (verified: `awk '{print $1}' … | sort -u`), so it stays on the fast path and the 30-second smoke at `tests/cli/integration_test.zig:360-383` and the route pin at `cmd/circ-compile/main.zig:2085-2098` are untouched. A file that already declares any `import` was on the project route before this change. No new diagnostic is possible: `W003` skips implicit builtins at `lib/validator/passes/unused_import.zig:33`.

### The new fixture

```
// tests/fixtures/circuits/builtin_xor_anonymous.circ
// The only macro usage sits in anonymous position, so it never appears in
// ast_file.components[]; only the IR scan (lib/ir/resolver.zig:246-252)
// sees it. Import-free on purpose: this is the fast-path case.
input a, b
wire w(in = xor(a = a, b = b).out)
output out(in = w.out)
```

The shape mirrors `tests/fixtures/circuits/edge_deep_anonymous.circ:2` (`wire w(in=not(...).out)`), which already proves anonymous instances nest inside a `wire`'s `in` port.

**This fixture does not compile, and Phase 0 must not assert that it does.** It proves the *predicate*, not the pipeline. `usesBuiltinMacro` correctly routes it to the project pipeline (an `ast_file.components[]` scan would not), and `lib/resolver/resolve_bodies.zig:454-467` rewrites the anonymous `.unresolved_name` into a `.sub_circuit_ref` (the rewrite loop walks all of `module.components`, anonymous ones included). But `specializeCallSites` pairs AST instances to IR components **positionally** over `item.ast_file.components` (`resolve_bodies.zig:245-248`, `ir_comp_idx = input_pin_count + ast_idx`), while `lib/ir/resolver.zig:340-344` appends anonymous components during `resolvePendingPorts`, i.e. after the top-level range — so the anonymous instance is never visited and `specialized_target_file` stays `null`. All five builtin macros are parametric (`input<W>[W] a, b`, e.g. `lib/resolver/builtin_circ/xor.circ:3`), so `resolve_bodies.zig:441-447` leaves `stubModule` (empty `inputs`/`outputs`, `:111-120`) in their `project.files` slot, and `sub_circuit_validation.targetForRef` (`lib/validator/passes/sub_circuit_validation.zig:27-30`) falls back to it through `findTargetModule` (`:16-25`, which does find the implicit-builtin `import_table` entry, `lib/resolver/scan_imports.zig:234-265`). Result: **three `E012`s** — `sub-circuit 'xor' has no input port 'a'`, the same for `'b'`, and `no output port 'out'` (`sub_circuit_validation.zig:114-153`). Not `E013`: that pass iterates `target.inputs` (`:162`), which on a stub is empty, so no arity diagnostic is emitted.

That gap is **pre-existing and out of scope here** — closing it means teaching `specializeCallSites` to walk `module.components`, which renumbers specialization ids and moves goldens this phase promises to keep byte-identical. Nothing in the tree covers it today: no fixture uses a builtin macro in anonymous position (verified by grep over `tests/fixtures/circuits/` and `tests/fixtures/projects/`), and `edge_deep_anonymous.circ` plus `DOCS/language.md:390,682` prove only anonymous *primitives* (`not`, `and`). Phase 0 records the gap and asserts the honest behaviour:

- the inline route test asserts `front.project != null` (the predicate fired) and that no diagnostic carries `E001` — the code this phase removes — rather than `front.errors == 0`;
- the fixture does **not** join `compile_fixtures`;
- `site/test/libcirc.test.ts` gets no anonymous-position twin.

No `expected-*` golden is added for it either; its whole proof is the inline route test.

### The bundle budget (TypeScript)

```ts
// site/scripts/check-bundle.ts — the reader's view of site/bundle-budget.json.
// These are TypeScript declarations in the script, not content of the JSON file.
export interface BundleBudget {
  /** Envelope version; bump only alongside a reader change in check-bundle.ts. */
  version: 1;
  /** Applies to any route without a `routes` entry. `raw` optional: decision 14 gates gzip only. */
  default: Ceiling;
  /** Per-route overrides, keyed by the route the walker derives from the dist path. */
  routes: Record<string, Ceiling>;
  /** Measured in Phase 0 and committed. Informational: never gates, never auto-updated. */
  baseline: Record<string, Measurement>;
}

export interface Ceiling {
  /** Sum of raw bytes across the page's eager module graph. Omit to gate gzip only. */
  raw?: number;
  /** Sum of per-file `Bun.gzipSync(bytes, { level: 9 }).length`. Always present. */
  gzip: number;
}

export interface Measurement {
  files: number;
  raw: number;
  gzip: number;
}
```

`site/bundle-budget.json` itself is plain JSON — no TypeScript, no comments — and this is its literal skeleton:

```json
{
  "version": 1,
  "$comment": "gzip is summed per file, not over a concatenation: each chunk is a separate HTTP response.",
  "default": { "gzip": 10240 },
  "routes": { "/playground": { "raw": 368640, "gzip": 122880 } },
  "baseline": { "/": { "files": 0, "raw": 0, "gzip": 0 } }
}
```

The ten `baseline` rows (one per route, listed below) are filled in from slice 5's own measured run; the `0`s above are placeholders in this plan, never in the committed file.

Ceilings from decision 14, in bytes: `default` `{ gzip: 10240 }` (10 KB); `routes["/playground"]` `{ raw: 368640, gzip: 122880 }` (360 KB / 120 KB). The 20 KB gzip ceiling for pages embedding a `<LiveEditor>` is **not** written in Phase 0 — no page embeds one until `DOCS/PLANS/PHASE_7_live_editors.md`, and that phase adds the `/tour` and `/examples` entries. `baseline` carries one row per route measured by this phase's own run: `/`, `/tour`, `/examples`, `/download`, `/playground`, `/reference`, `/reference/getting-started`, `/reference/circuit-format`, `/reference/wasm-api`, `/reference/preview` (the four `src/pages/reference/*.md` files are generated by `bun run sync` from `site/scripts/lib/site-config.ts:15-46`).

**If a route measures over its ceiling on the first run, the slice does not silently raise it.** No `site/dist` exists in this tree, so no measurement is on record and this is a live possibility — `/` and `/examples` both render `LiveCanvas.astro` (`site/src/pages/index.astro:41`, `site/src/pages/examples.astro:30`) and would fall under the 10 KB `default`. Record the measured raw/gzip in the STATUS entry, then either (a) argue the raise there with the number and the reason, per decision 14's "**A ceiling is never raised silently**" (`DOCS/PLANS_PROMPT.md:55`), and commit the higher ceiling as a `routes` override — never by moving `default`; or (b) if the overrun is a lazy chunk the walker wrongly followed, fix the walker and re-measure. Only `/playground` may carry a raise in this phase; a base-layout page over 10 KB gzip is a finding to report, not a ceiling to move.

Gzip is summed **per file, not over a concatenation**: each chunk is a separate HTTP response, so per-file gzip is what the network actually transfers. `check-bundle.ts` says so in its header comment and in the JSON's `$comment` field.

### The eager module graph (TypeScript)

```ts
/** One page as the walker sees it. */
interface PageGraph {
  /** Route derived from the dist-relative path: `index.html` → `/`, `tour/index.html` → `/tour`. */
  route: string;
  /** dist-relative paths of every eagerly-loaded module, in discovery order. */
  files: string[];
  raw: number;
  gzip: number;
  /** Chunks reachable only through `import()`. Reported with their own raw and
   *  gzip bytes so a later phase can measure a lazy chunk without a second
   *  walk (`PHASE_1_editor.md:569` reads the CodeMirror chunk off this line);
   *  never gated. */
  lazy: { file: string; raw: number; gzip: number }[];
  /** Bytes of `<script>` blocks with no `src`. Reported, never gated. */
  inlineBytes: number;
}
```

Seeds per page: the union of every `<script type="module" src="…">` and every `<link rel="modulepreload" href="…">`. From each seed the walker follows **static** import specifiers found in the emitted chunk text, transitively; `import("…")` specifiers are collected into `lazy` and never followed. Two scanners, applied to each chunk's text:

```ts
// A static, namespace or side-effect import, minified or not. Astro's client
// build is esbuild-minified (Vite's default `build.minify` is
// `consumer === "server" ? false : "esbuild"`,
// site/node_modules/vite/dist/node/chunks/dep-Dq2t6Dq0.js:45977; only Astro's
// SSR pass sets `minify: false`, astro/dist/core/build/static-build.js:169,
// while the client config at :199-219 sets none and site/astro.config.mjs
// overrides nothing), so `import{a as b}from"./x.js"` and
// `import*as n from"./x.js"` have no space after `import` and must still
// match. `import(` and `import.meta` cannot match: neither `(` nor `.` starts
// a binding, and neither is a quote.
const STATIC_IMPORT =
  /(?:^|[;}\n])\s*import\s*(?:(?:[\w$]+\s*,\s*)?(?:\*\s*as\s+[\w$]+|\{[^}]*\}|[\w$]+)\s*from\s*)?["']([^"']+)["']/g;
const REEXPORT      = /(?:^|[;}\n])\s*export\s*(?:\*|\{[^}]*\})\s*from\s*["']([^"']+)["']/g;
const DYNAMIC       = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;
```

`STATIC_IMPORT` was checked against these fifteen samples before it was written into this plan: `import{a as b}from"./chunk.js"`, `import{a,b}from"./c.js"`, `import*as n from"./x.js"`, `import d,{a}from"./m.js"`, `import d,*as n from"./m2.js"`, `import"./side.js"`, `import a from"./d.js"`, `import a from "./e.js"`, a multi-line `import {\n a,\n b\n} from "./multi.js"`, and the three-on-one-line `import"./a.js";import{b}from"./b.js";import*as c from"./c.js"` all resolve; `const p=import("./lazy.js")`, `x=await import ("./y.js")`, `import.meta.url`, `;importantThing="x"` and `export*from"./r.js"` do not (the last is `REEXPORT`'s, the two `import()` forms are `DYNAMIC`'s). The `\s`-after-`import` form the earlier draft used matched none of the first four — every minified clause shape — and that is the failure this replaces: it produces no warning line, so the walker would silently follow nothing past the entry script.

Specifiers are resolved relative to the containing chunk and clamped to `dist/`; anything that escapes `dist/` or does not exist is skipped with a warning line. `process.env.BASE_PATH` (normalised to end in `/`, as `site/scripts/lib/site-config.ts:60` and `site/src/layouts/Base.astro:27` do — `site/astro.config.mjs:5` is `const base = process.env.BASE_PATH ?? '/';`, which passes the value through unnormalised and lets Astro normalise it, so it is not the model to copy) is stripped from `src`/`href` before joining onto `dist/`, so the walker works for both a bare local build and a `BASE_PATH`-prefixed one.

### The build-free graph walk (TypeScript)

```ts
/** Roots per decision 14(b). Absolute paths under site/src. */
const ROOTS = ['src/layouts/Base.astro', 'src/components/Nav.astro', 'src/components/Footer.astro'];

interface SourceGraph {
  /** Repo-relative paths of every source file reached. */
  visited: Set<string>;
  /** Bare (non-relative) specifiers seen anywhere in the graph, e.g. 'astro:content'. */
  bare: Set<string>;
}

const FORBIDDEN = /^(?:@codemirror\/|@lezer\/|codemirror$)/;
```

For an `.astro` file the walker scans the frontmatter fence *and* every `<script>` block (`site/src/components/PostHog.astro:22` imports `../utils/sillyname` from inside one, and `site/src/components/Nav.astro:43` and `site/src/components/ThemeToggle.astro:4` are import-free `<script>` blocks that must not break the parse). Relative specifiers resolve by trying, in order, the literal path, `+ '.ts'`, `+ '.mjs'`, `+ '.js'`, `+ '.astro'`, `+ '/index.ts'`; `.css` and unresolvable relative specifiers are recorded and skipped (`site/src/layouts/Base.astro:5` imports `../styles/global.css`). Bare specifiers are never resolved — they are collected into `bare` and asserted against `FORBIDDEN`.

## Execution & Concurrency Model

This phase is fully synchronous. No background threads, goroutines, workers, or async state machines are introduced. The Zig change adds one bounded loop over an already-built slice inside `frontend.run`, on the same call stack the CLI and the C ABI already use (`cmd/circ-compile/main.zig:263`, `lib/libcirc.zig:101`). `site/scripts/check-bundle.ts` and `site/test/bundle-graph.test.ts` are one-shot scripts that read files and exit; neither spawns a process except through the existing `bun run libcirc` → `zig build libcirc-wasm` chain (`site/scripts/build-libcirc.ts:30`) and `bun run scripts/compile-content.ts` → `zig-out/bin/circ-compile` (`compile-content.ts:40,67,74`), both of which are `spawnSync`. The browser Web Worker (`site/src/workers/libcirc.worker.ts`) is not touched; its ownership of the wasm instance is unchanged.

## Persistence & I/O

Filesystem only; no network at any point (`bun install` is already done in this worktree). Reads: `tests/fixtures/**` from the build root under `zig build test` (run steps inherit the build root as cwd — no `setCwd` in `build.zig`, and `tests/libcirc/driver_test.zig:33` already reads relative paths this way); `site/public/wasm/libcirc.wasm` and `libcirc.manifest.json` under `bun test`; `site/dist/**` under `bun run bundle`; `site/src/**` under `bundle-graph.test.ts`.

Writes, all of them committed build products or new sources:

- `site/public/wasm/libcirc.wasm` + `site/public/wasm/libcirc.manifest.json`, by `bun run libcirc`. The manifest's identity fields come from the binary's own `circ_version()` (`site/scripts/build-libcirc.ts:44-61`) and its `bytes`/`gzip_bytes` from the file, so it cannot disagree with the module. **The `revision` it records names the commit *before* the one that commits it** — inherent to committing a build product, and the example artifacts already behave that way (`DOCS/archive/plan-libcirc.md:199`).
- `site/public/wasm/<slug>.wasm` × 11 (10 example slugs plus `hero-half-adder.wasm`, the exact set at `git ls-files site/public/wasm`), by `bun run scripts/compile-content.ts`. **These are expected to come back byte-identical.** `build_info.revision` is threaded only into `circ_version()` (`lib/libcirc.zig:248-249`, options built at `build.zig:180-219`); it is not embedded in an emitted artifact, and the artifact is the vendored runtime plus two topology sections (`lib/topology/section_writer.zig`, `lib/libcirc/modes.zig:47-65`). Every one of the 11 sources either declares an import or uses no macro, so none of them changes route. If any of the 11 does show a diff, **stop and explain before committing** — that is a signal the change reached further than specified.
- 7 untracked `site/public/wasm/tour-<N>.wasm` files, written by the same run (`compile-content.ts:93-99`). They have never been committed, `site/.gitignore` does not cover them, and they **must not be staged**. Stage by path only.
- `site/scripts/.compiled.json` — already ignored (`site/.gitignore`).
- `site/dist/**` — already ignored; never committed, and the bundle gate is the only consumer.

No crash-recovery contract applies: every write above is idempotent and regenerable from the tree.

CI reality worth knowing while planning proof: `.github/workflows/pr-tests.yml` runs `zig build test-all` with `SKIP_WASM_E2E: "1"` (`:64`), so the new `four_bit_adder` drive case is exercised **locally only**; and no workflow runs `bun test` at all (`deploy-site.yml` only builds, at `:65`). The site suite and `bun run bundle` are local gates.

## Slices

The execution agent implements this phase one slice at a time, stopping for review after each. Each slice ends with `zig build test-all`, `bun test` and `bun --bun run build` green — plus `bun run bundle` from slice 5 on, once that script exists — a STATUS entry appended, files staged by path, and one commit.

| # | Slice Title | Deliverable | Test Proof |
|---|-------------|-------------|-----------|
| 1 | Start the status log and repoint the libcirc decisions preamble | New `DOCS/STATUS.md` (header + this slice's entry, per the STATUS template in `DOCS/PLANS_PROMPT.md`). `DOCS/decisions/libcirc.md:3`: replace "the ten locked in `DOCS/PLANS_PROMPT.md`" with a pointer that carries the retrieval hop, so `(decision 7)` at `:39` and `(decision 8)` at `:47` stop resolving to this initiative's fifteen. The archive is a *highlight view* and contains no numbered list (`DOCS/archive/plan-libcirc.md:7`, verified by grep), so pointing at it alone would dangle one hop further out; write instead: "The numbered decisions they cite are the ten locked in the libcirc plan prompt, archived at `DOCS/archive/plan-libcirc.md` and readable in full at `git show 3a81c361ad3b2f240c602e06f0e968faa56efe26:DOCS/PLANS_PROMPT.md`." (that sha is the canonical commit named at `DOCS/archive/plan-libcirc.md:3`). In the same commit, correct the stale `site/node_modules` trap in `DOCS/PLANS_PROMPT.md`'s Recurring Traps (`:132`) per the Modified-files row, and name it in this slice's STATUS `Notes:` line as `:128` requires. No executable change. | `zig build test-all`, `bun test`, `bun --bun run build` all green and unchanged (no code touched). Manual, run: `grep -n "plan-libcirc" DOCS/decisions/libcirc.md` and `grep -n "3a81c36" DOCS/decisions/libcirc.md` each show `:3`, and `grep -n "PLANS_PROMPT" DOCS/decisions/libcirc.md` shows **only** the `git show 3a81c36…:DOCS/PLANS_PROMPT.md` retrieval command — never a bare pointer to the live file (today `PLANS_PROMPT` occurs in that file only at `:3`, as the bare pointer). `test -f DOCS/STATUS.md`. |
| 2 | Make the compile fast path usage-aware | `build/frontend_modules.zig`: `libcirc.addImport("builtins", builtins);`. `lib/libcirc/frontend.zig`: the `builtins` import, `usesBuiltinMacro`, the one-line change to the `.project_if_imports` arm, and four inline route tests. `lib/libcirc.zig:274-276`: `_ = frontend;`. New fixture `tests/fixtures/circuits/builtin_xor_anonymous.circ`. New CLI test pinning `--inspect` on the full-adder project root against `tests/fixtures/expected-inspect/canonical_full_adder_root.txt`. Comment-only rewrites at `lib/libcirc/frontend.zig:24-27` (the `Route` doc comment) and `cmd/circ-compile/main.zig:255-258` (the route comment), both per the Modified-files rows — each states the old behaviour as a rule and would otherwise contradict the code two lines below it. `DOCS/language.md:217-226`, `DOCS/getting-started.md:170` and the `:187` papercut blockquote (narrowed to `--inspect`, not deleted) rewritten. `DOCS/decisions/playground.md` created with `### The compile fast path resolves implicit builtins`, whose closing paragraph names the anonymous-instance specializer gap as the known remainder, registered in `DOCS/decisions/index.md` between `:63` and `:65`. Then, **in the same slice and the same commit** (the *One revision for the compiler and every site artifact* constraint, `DOCS/PLANS_PROMPT.md:28`, and the trap at `:142`): `zig build circ-compile`, `bun run libcirc` (rewrites `site/public/wasm/libcirc.wasm` + `libcirc.manifest.json`), `bun run scripts/compile-content.ts` (the 11 committed example artifacts, expected byte-identical — if any moves, stop and explain before committing; the 7 untracked `tour-<N>.wasm` are never staged). Stage by path: exactly two modified tracked artifacts. | `zig build test-all` (the four new inline cases in `lib/libcirc/frontend.zig` and the new case in `tests/cli/integration_test.zig`; the existing route pin at `cmd/circ-compile/main.zig:2085-2098` and the perf smoke at `tests/cli/integration_test.zig:360-383` still green; every `tests/fixtures/expected-*` golden still byte-identical). `bun test` green against the regenerated module — including `circ_version matches the committed manifest` (`site/test/libcirc.test.ts:30-39`) and `renderer pin` (`site/test/renderer-pin.test.ts:17-19,21-33`). `bun --bun run build` green. `git status` shows exactly two modified tracked artifacts beyond the sources this slice edits. |
| 3 | Prove it byte for byte, and through the wasm module | `tests/libcirc/driver_test.zig`: add `tests/fixtures/circuits/full_adder_from_builtins.circ` to `compile_fixtures` (`:196-206`) — and **only** that one; `builtin_xor_anonymous.circ` does not compile, see *The new fixture* — and replace the now-false comment at `:199-201`. `tests/e2e/libcirc_wasm_test.zig`: add the `four_bit_adder` `DriveCase` (root `/playground/main.circ`, source `tests/fixtures/circuits/four_bit_adder.circ`, vectors `tests/fixtures/expected-wasm/four_bit_adder.txt`) and replace the comment at `:254-256`. | `zig build test-all`: `driver: compile equals the CLI artifact byte for byte` (`:208-229`) now covers both builtin-using roots, and `libcirc.wasm: compile inverter, slice_basic, chain, full_adder project and drive expected-wasm vectors` (`:261-334`) drives the 4-bit adder's committed vectors. Note in STATUS that the drive case runs locally only — CI sets `SKIP_WASM_E2E=1` (`pr-tests.yml:64`). |
| 4 | Prove the browser module | One new case in `site/test/libcirc.test.ts`: `compiles a builtin-using single file with no import` — `callOp(w, 'compile', single(tour[4].source.replace(/^import xor .*\n/m, '')))`, expecting `status === 0` and both custom sections. No anonymous-position twin: that source does not compile (*The new fixture*). The artifacts this case runs against were regenerated and committed back in slice 2, where the Zig change landed; this slice touches no `.wasm`. | `bun test`: the new case green, and the existing `circ_version matches the committed manifest` (`site/test/libcirc.test.ts:30-39`, which also asserts `manifest.bytes === readFileSync(wasmPath).length`) plus `renderer pin` (`site/test/renderer-pin.test.ts:17-19,21-33`) still green. `bun --bun run build`. `git status` shows no modified `.wasm` — a diff here means slice 2's regeneration did not land. |
| 5 | `bun run bundle`: the dist walker and the committed budget | `site/scripts/check-bundle.ts` per *Data & State*; `site/bundle-budget.json` with `default`, `routes["/playground"]` and the ten measured `baseline` rows; `"bundle"` added to `site/package.json` scripts. `DOCS/decisions/playground.md` gains `### The JavaScript budget is per page and gzip is the gate`. Delete the resolved `TODO(phase0)` modulepreload entry from `DOCS/PLANS_PROMPT.md`'s Open items (`:188`), as the rule at `:186` requires, and record the answer verbatim in the STATUS entry along with the measured table. | `bun --bun run build && bun run bundle` exits 0 and prints one row per route, then an ungated informational table of every lazy chunk with its raw and gzip bytes, then the inline-script byte line. **Non-vacuity, as an exit-1 condition inside `check-bundle.ts`, not a printed number:** the walker must reach at least one chunk beyond the seeds for `/playground` — `Playground.astro:69-72` imports `libcirc-client.ts`, `split-files.ts` and `columns.ts` statically. A zero there means the chunk scanner is not matching the emitted module syntax; it is a bug in the walker, not a fact about the site, and must never be recorded as the answer to the modulepreload spike. Negative proof, run once and recorded in STATUS: temporarily lower `default.gzip` to `1` and confirm `bun run bundle` exits 1 naming the offending routes, then restore. **If any route is over its ceiling on the first real measurement, stop and report before committing `bundle-budget.json`** — see *The bundle budget*. `bun test` and `zig build test-all` still green. |
| 6 | The build-free CodeMirror tripwire | `site/test/bundle-graph.test.ts` per *Data & State*: walk the three roots, assert no bare specifier matches `/^(?:@codemirror\/\|@lezer\/\|codemirror$)/`, assert the walk is non-vacuous (`visited.size >= 6`) and that it reached `src/utils/sillyname.ts` (proving `<script>` blocks inside `.astro` are parsed) and `src/utils/url.ts` (proving frontmatter is parsed). | `bun test`: the new file's cases green. Negative proof, run once and recorded in STATUS: temporarily add `import { EditorView } from '@codemirror/view';` to `site/src/components/Footer.astro`'s frontmatter, confirm the test fails naming `@codemirror/view`, then revert. `bun --bun run build` and `zig build test-all` still green. |

Slices are ordered by dependency: 2 must precede 3 (the tests need the behaviour); **slice 2 carries its own artifact regeneration, because a Zig change and its committed artifacts are one commit** (`DOCS/PLANS_PROMPT.md:28`, `:142`) — deferring it would ship slices 2 and 3 with a browser module that predates the compiler in the same tree, and nothing would catch it, since `site/test/libcirc.test.ts:30-39` compares the committed manifest against the committed module's own `circ_version()` and a stale pair stays green together. 4 proves the regenerated module from the site side; 5 and 6 are independent of the Zig work and of each other. Each slice is fully reviewable on its own.

## Goldens that must stay byte-identical

No `tests/fixtures/expected-*` file is added, removed or regenerated in this phase. `UPDATE_GOLDENS=1` is not run. In particular:

- `tests/fixtures/expected-inspect/canonical_full_adder_root.txt:62` — pins `E001: undeclared name 'or'` on the `.single_module` (`--inspect`) route, the arm this change does not touch (`cmd/circ-compile/main.zig:254`). **It is currently referenced by no test** (verified by repo-wide grep; only `DOCS/PLANS_PROMPT.md:49` mentions it), which is why slice 2 adds the CLI test that makes it a real gate. If that first run shows it stale, the drift is pre-existing rather than caused by this change: regenerate it by hand from the CLI's own stdout in the same slice and record the diff in STATUS. `expectStdoutMatchesFixture` (`tests/cli/integration_test.zig:65-69`) does not honour `UPDATE_GOLDENS`.
- `tests/fixtures/expected-inspect/{error_undeclared,clean_inverter,canonical_half_adder_root,rom_basic}.txt` — already gated at `tests/cli/integration_test.zig:236,246,338,348`.
- Every `tests/fixtures/expected-diagnostics/*.txt`. These come from validator tests that run the validator directly on a resolved module (`tests/validator/{run,structural_passes,diagnostics}_test.zig`) and never enter `frontend.run`, so no route change can reach them.
- Every `tests/fixtures/expected-{ast,ir,zig,wasm,analyze}/**` and `tests/fixtures/{preview/renders,truth_table}/**`. The emit and serializer suites call `scan_imports.scanProjectImports` directly (`tests/e2e/serializer_fixtures_test.zig:131`, `tests/e2e/section_writer_fixtures_test.zig:166,228`, `tests/emit/project_emit_test.zig:69`, `tests/emit/project_behavior_test.zig:147`) or resolve a single module in-process (`tests/emit/behavior_test.zig:143-167`), so no route change can reach them. Two tests **do** cross the route table, both through `--emit-zig`'s shared `.project_if_imports` arm: `tests/cli/integration_test.zig:176-194` (`cli emit-zig mode writes expected zig file`) against `tests/fixtures/expected-zig/and_two_inputs.zig`, and `:196-210` (`cli emit-zig hard error exits 1 and no output`) against `E001_undeclared.circ`. Both stay put because their fixtures use no built-in macro — `and_two_inputs.circ` declares only `input`/`and`/`output`, and `mystery` is not in `builtins.table` — so the predicate does not fire and the route is unchanged. Any future macro-using emit-zig CLI fixture *would* move its golden.
- `tests/fixtures/expected-sim/**`, `tests/fixtures/sim/**` and `tests/fixtures/mem/**` — driven by `--sim`, which the route table already sends down `.project` unconditionally (`cmd/circ-compile/main.zig:260`), so no `.project_if_imports` change can reach them.
- `tests/fixtures/bench/engine.bench.golden` — the bench harness maps fixtures to circuits by hand (`tools/bench/main.zig:54,86`) and does not use `frontend.run`.
- The 11 committed `site/public/wasm/*.wasm` example artifacts — see *Persistence & I/O* for why they must not move, and what to do if one does.

The one deliberately changing binary pair is `site/public/wasm/libcirc.wasm` and `libcirc.manifest.json`, regenerated and committed in **slice 2**, in the same commit as the Zig change (`DOCS/PLANS_PROMPT.md:28`, `:142`). Slice 4 only tests them and must show **no** modified `.wasm` in `git status`.

## Tests

**Unit tests:**

| Test Name | Module | What It Asserts |
|-----------|--------|----------------|
| `frontend: an import-free root that uses a builtin takes the project route` | `lib/libcirc/frontend.zig` (inline) | `frontend.run(a, "tests/fixtures/circuits/full_adder_from_builtins.circ", &.{}, .project_if_imports, &failure)` returns `front.project != null`, `front.errors == 0`, `front.warnings == 0`, `front.early_stop == null`, and `front.file_paths` contains `"<builtin>/xor.circ"` (expected length 6: the root plus all five macro files, per `lib/resolver/scan_imports.zig:234-265`; record the observed number in STATUS rather than hard-coding it if it differs). |
| `frontend: an anonymous-position builtin still takes the project route` | `lib/libcirc/frontend.zig` (inline) | Same call over `tests/fixtures/circuits/builtin_xor_anonymous.circ`: `front.project != null` (the predicate fired — this is the case an `ast_file.components[]` scan would miss) and **no diagnostic carries code `E001`**, the code this phase removes. **Not** `front.errors == 0`: the anonymous instance is never specialized, so validation emits three `E012`s — see *The new fixture* for the mechanism and why closing that gap is out of scope. |
| `frontend: a non-macro undeclared name keeps the fast path` | `lib/libcirc/frontend.zig` (inline) | Over `tests/fixtures/circuits/E001_undeclared.circ`: `front.project == null`, `front.file_paths.len == 1`, `front.errors == 1`, `front.warnings == 0`. Proves the predicate does not fire on every `.unresolved_name`. |
| `frontend: a macro-free root keeps the fast path` | `lib/libcirc/frontend.zig` (inline) | Over `tests/fixtures/circuits/stress_grid_10x10.circ`: `front.project == null`, `front.file_paths.len == 1`. The library-level mirror of `cmd/circ-compile/main.zig:2085-2098`, which stays as it is. |
| `cli inspect full_adder project root still reports E001 for 'or'` | `tests/cli/integration_test.zig` | `circ-compile tests/fixtures/projects/full_adder/root.circ --inspect` exits 1, writes nothing to stderr, and its stdout equals `tests/fixtures/expected-inspect/canonical_full_adder_root.txt` byte for byte. Pins that `.single_module` is untouched. |
| `bundle graph: nothing in the base layout imports CodeMirror` | `site/test/bundle-graph.test.ts` | No bare specifier reachable from `Base.astro` / `Nav.astro` / `Footer.astro` matches `/^(?:@codemirror\/\|@lezer\/\|codemirror$)/`. |
| `bundle graph: the walk is non-vacuous` | `site/test/bundle-graph.test.ts` | `visited.size >= 6`, and `visited` contains `src/utils/url.ts` (frontmatter parsed) and `src/utils/sillyname.ts` (an `.astro` `<script>` block parsed, `site/src/components/PostHog.astro:22`). Without this a broken resolver would pass the assertion above by reaching nothing. |

**Integration tests:**

| Test Name | Scope | What It Asserts |
|-----------|-------|----------------|
| `driver: compile equals the CLI artifact byte for byte` (extended) | `tests/libcirc/driver_test.zig:208-229` over `compile_fixtures` | With `full_adder_from_builtins.circ` added: the in-process CLI exits 0 for it, and `libcirc.compile` returns the identical bytes starting `\x00asm`. Before this phase the CLI exited 1 on it, which is why the fixture list carried the comment at `:199-201`. `builtin_xor_anonymous.circ` is deliberately **not** in this list — see *The new fixture*. |
| `libcirc.wasm: compile … and drive expected-wasm vectors` (extended) | `tests/e2e/libcirc_wasm_test.zig:261-334` | With the `four_bit_adder` case added: the wasm build's artifact is byte-equal to the native library's for an import-free root that uses `xor` and `or`, and driving it in Node reproduces `tests/fixtures/expected-wasm/four_bit_adder.txt` line for line. Local only — `SKIP_WASM_E2E=1` in CI (`pr-tests.yml:64`). |
| `libcirc.wasm: compiles a builtin-using single file with no import` | `site/test/libcirc.test.ts` | Against the **committed** `site/public/wasm/libcirc.wasm`: `callOp(w, 'compile', single(tour[4].source.replace(/^import xor .*\n/m, '')))` returns `status === 0`, and `WebAssembly.Module.customSections` finds exactly one `circ.topology.v0.min` and one `circ.topology.v0.full`. This is the browser-facing statement of the whole phase. |
| `circ_version matches the committed manifest` (unchanged, re-run) | `site/test/libcirc.test.ts:30-39` | After regeneration the manifest's seven identity fields still equal `circ_version()`'s, and `manifest.bytes` equals the file length — the tripwire for a half-done regeneration. |
| `renderer pin` (unchanged, re-run) | `site/test/renderer-pin.test.ts:17-19,21-33` | `SUPPORTED_TOPOLOGY_VERSIONS` still contains `manifest.full_version` and the pinned `circ-renderer` still decodes what the regenerated module emits. |
| `bun run bundle` | `site/scripts/check-bundle.ts` over `site/dist` | Every route's eager module graph is at or under its ceiling; exit 1 otherwise. Not a `bun test` case — it is the fourth gate, run after `bun --bun run build`. |

Run commands, in the order a slice runs them (`bun run bundle` exists only from slice 5 on, since slice 5 is what adds the `"bundle"` script to `site/package.json:6-14`; slices 1-4 stop after the build):

```
zig build test-all                                    # from the repo root
cd site && bun test && bun --bun run build && bun run bundle   # bundle: slices 5-6 only
```

`zig build test-all` is `test` + `test-emit`; `test-emit` is in this phase's gate because `--emit-zig` shares the `.project_if_imports` arm (`cmd/circ-compile/main.zig:259`) even though its own fixtures bypass `frontend.run`. Never substitute `bun run build` for `bun --bun run build` on this machine, and never set `SKIP_LIBCIRC_TEST=1` or `SKIP_WASM_E2E=1` to make a slice pass.

**Manual checklist (browser), recorded in slice 4's STATUS entry as _unrun_ unless someone actually runs it** — no browser has been available in any session on this branch (`DOCS/archive/plan-libcirc.md:189`): open `/playground`, pick tour step 5 (*A half-adder*), delete the `import xor "<builtin>/xor.circ"` line (`site/src/content/tour.ts:101`), and confirm the status line no longer reads "Compile reported diagnostics." (`site/src/components/Playground.astro:208`) and the Simulate tab renders a canvas.

## Open Questions / Spikes

**Resolved here — `TODO(phase0)` from `DOCS/PLANS_PROMPT.md`'s Open items: "does Vite emit a `modulepreload` link for every statically imported chunk, and none for an `import()`-only chunk?"**

Answered from the installed toolchain, without a build. Vite's HTML plugin does emit one `<link rel="modulepreload">` per statically imported chunk — `getImportedChunks` walks `chunk.imports` (rollup's static-import list, distinct from `dynamicImports`) and feeds `toPreloadTag` (`site/node_modules/vite/dist/node/chunks/dep-Dq2t6Dq0.js:36520-36557`) — **but Astro never runs that plugin's HTML transform for a static build.** Astro renders pages itself and injects only `<script type="module" src>` and `<link rel="stylesheet">` (`site/node_modules/astro/dist/core/render/ssr-element.js:39-58`); a grep for `modulepreload` across the whole of `site/node_modules` hits vite's chunk and nothing else, and Astro enables no vite build manifest (`build.manifest` appears nowhere; only `@astro/plugin-build-manifest`, an unrelated SSR manifest, exists). So decision 14(a)'s assumption does **not** hold for this site, and the fallback it named is the shipping design: the walker seeds from the script tags (keeping the modulepreload seed, harmlessly empty today, so the script stays correct if Astro ever changes) and then follows the built chunks' own static import graph. Confirmation step, inside slice 5 and recorded in STATUS: after the first `bun --bun run build`, grep `site/dist/**/*.html` for `modulepreload` and report the count (expected `0`), and **assert** — as an exit-1 condition inside `check-bundle.ts`, not merely a printed number — that the walker reached at least one chunk beyond the seeds for `/playground`, since `Playground.astro:69-72`'s island imports `libcirc-client.ts`, `split-files.ts` and `columns.ts` statically. With the modulepreload seeds empty, the chunk scanner is the walker's *only* way past the entry script, so a zero here means `STATIC_IMPORT` is not matching the emitted (esbuild-minified) module syntax and every route's measurement has silently collapsed to its seeds — a budget measured over seeds alone is not a budget, and that zero must not be recorded in STATUS as the answer to this spike. Decision 14(b)'s build-free test does not depend on any of this and ships either way, in slice 6.

**Still open:**

- Resolved at plan time: `DOCS/PLANS_PROMPT.md` decision 8 and the Phase 0 index row were corrected to call `builtin_xor_anonymous.circ` a predicate fixture, not a compile fixture. Slice 2's STATUS entry still records the gap, and `DOCS/decisions/playground.md`'s `### The compile fast path resolves implicit builtins` carries a closing paragraph naming the anonymous-instance specializer gap (`resolve_bodies.specializeCallSites` pairs positionally over `ast_file.components`) as the known remainder, so the next initiative can pick it up deliberately rather than rediscover it.
- `TODO(phase0)`: is `tests/fixtures/expected-inspect/canonical_full_adder_root.txt` still current? It is referenced by no test in the tree (verified by repo-wide grep), so nothing has regenerated or checked it since it was written, and `expectStdoutMatchesFixture` has no `UPDATE_GOLDENS` path. Its shape matches the gated `canonical_half_adder_root.txt` (same `=== Parse Tree ===` / `=== Resolved IR ===` / `=== Diagnostics ===` / `=== Summary ===` sections, same span syntax, neither carrying the `Errors (n)` line that only `tests/helpers/ast_dump.zig:159` emits), so it is very likely current — but "likely" is not a gate. **Spike:** slice 2 adds the CLI test that pins it and runs `zig build test-all`. Green resolves this. Red means pre-existing drift, not a regression from the route change: regenerate the golden by hand from the CLI's stdout in that same slice, and record the diff in the STATUS entry so the next reader knows the golden moved and why.
- `TODO(phase0)`: does `front.file_paths.len` equal exactly 6 for an import-free macro-using root? `lib/resolver/scan_imports.zig:234-265` injects all five `<builtin>/*.circ` files into the scan and dedupes through `path_to_id`, and the five macro sources reference only each other and the primitives (`lib/resolver/builtin_circ/*.circ`), so 6 is the expected count — but parametric specialization creates synthetic modules in `resolve_bodies` and this plan has not proved those never reach `scan_result.file_paths`. **Spike:** slice 2's first inline test asserts the robust form (`front.file_paths.len >= 2` and the list contains `"<builtin>/xor.circ"`) and prints the observed length; STATUS records the number, and the assertion is tightened to `== <observed>` in the same slice once it is known.
