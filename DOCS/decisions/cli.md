# CLI Design

### Six invocation modes

**Decision.** The CLI supports six modes, selected by mutually-exclusive flags, plus `--analyze`, which runs before the mode parser and reads a JSON request on stdin instead of a file path:

```
circ-compile <input.circ> -o <output.wasm>           # produce WASM (default)
circ-compile <input.circ> --emit-zig -o <output.zig> # standalone Zig source (experimental)
circ-compile <input.circ> --inspect                  # dump parse tree / IR to stdout
circ-compile <input.circ> --preview                  # render ASCII schematic to stdout
circ-compile <input.circ> --truth-table              # enumerate input combinations to stdout
circ-compile <input.circ> --sim                      # drive the circuit over a stdio line protocol
echo '<json>' | circ-compile --analyze               # JSON analysis for editor tooling (stdin)
```

**Rationale.** The default produces the only artifact most users care about. `--emit-zig` exposes the experimental emit pipeline for users who want a richer (but unstable) export surface in standalone Zig source. `--inspect` is the debugging mode for the compiler itself: it prints the parse tree and resolved IR without invoking the build, useful when a `.circ` file produces unexpected emission. `--preview` is the visualisation mode: it lays out the resolved circuit on a character grid and emits a styled ASCII schematic with line-art glyphs, useful for code review, documentation, and teaching. `--truth-table` enumerates every input combination against the simulated circuit and prints a table, used both as a debugging aid for small circuits and as the bench fixture driver. See [`preview.md`](../preview.md) and [`circuit-format.md`](../circuit-format.md) for the per-mode rendering / format references. The compile, preview, truth-table, and analyze modes are also the library's four entry points (`DOCS/libcirc-api.md`); `--sim`, `--emit-zig`, and `--inspect` stay CLI-only per [libcirc.md](libcirc.md) "Not exported through libcirc".

**Alternatives.** A single mode with everything controlled by output extension. Concise but magical; users have to know that `.zig` extensions trigger different behaviour. Explicit flags are clearer.

### Mode-specific flags are gated at parse time

**Decision.** Flags that make sense only for a single mode are accepted there and rejected (or silently stored) elsewhere. The flags carved out today:

- `--expand-macros` — `--preview` only. Expand subcircuits into their constituent primitives instead of rendering them as labeled opaque boxes.
- `--expand-display` — `--preview` only. Label a multi-bit `led[N]` (widths 2..7) with one `·` indicator per bit instead of the `0x?` hex placeholder; width 8 or more keeps the hex form and warns on stderr.
- `--color=auto|always|never` — `--preview` only in effect, accepted in all modes. Defaults to `auto` (color when stdout is a TTY *and* `NO_COLOR` is unset). `always` overrides `NO_COLOR` per the convention used by `git`/`ls`/`grep`.
- `--format=markdown|csv|json` — `--truth-table` only. Defaults to `markdown`. CSV uses `0`/`1`/`?` cells; JSON encodes undefined cells as `null`.
- `--truth-table-format=binary|hex|decimal` — `--truth-table` only. Selects the per-cell rendering of multi-bit pin values. Defaults to `binary`.
- `--truth-table-cap=<N>` — `--truth-table` only. Raises the default 16-input-bit cap up to a hard ceiling of 24 (`2^24 ≈ 16M` rows). Beyond that, the `.wasm` runtime is the appropriate driver.
- `--strict` — `--truth-table` only. Promotes any `?` (undefined) output cell into a hard exit-1 with one diagnostic line per offending row on stderr. The table itself still renders.
- `--verbose` — `--truth-table` only. Per-vector engine traces on stderr.

**Rationale.** Each flag is a *display* or *format* choice attached to its mode, not a compilation one — the same `.circ` artifact can be rendered every way. Surfacing them as flags avoids forking topology formats or running the same input through the CLI multiple times. `--color` follows the standard tri-state convention so users don't need to learn a project-specific colour discipline. The `--truth-table-cap` ceiling is a UX call: a glance-readable truth table tops out around 16 input bits, but some power users may legitimately want 18 – 24; beyond that, almost certainly user error.

**Alternatives.** Always render macros expanded (loses the schematic-style abstraction by default) or always render them opaque (hides what the macro does). The flag-controlled split serves both audiences without picking one as canonical.

### TypeScript declaration emission deferred

**Decision.** Emitting a `.d.ts` file describing the compiled circuit's pin API is not part of v0. A host can read the `circ.topology.v0.full` section for names and kinds (the `getFileInfo()` export exists only on the experimental `--emit-zig` runtime); static `.d.ts` generation can be added later without breaking changes.

**Rationale.** `.d.ts` emission requires a second emission backend in the compiler and a stable contract between the runtime SDK and the generated types. None of that work blocks the v0 goal of producing a runnable artifact. Deferring keeps the v0 surface small.

**Alternatives.** Including `.d.ts` from the start. Worthwhile polish but expands scope before the core pipeline is proven.

### No build directory, no intermediate Zig subprocess

**Decision.** Default compile does not spawn `zig` and does not write to any intermediate directory. The pipeline runs entirely in-process: parser → resolver → validator → topology serializers → `section_writer.combineTwo` splices both topology blobs into the prebuilt runtime WASM that `cmd/circ-compile/main.zig` `@embedFile`s. The single output is the path passed to `-o`.

**Rationale.** Earlier drafts of this decision document carried a `--build-dir <path>` override for the now-removed temp-directory dance. The Zig-free pipeline collapsed that path away entirely: it has nothing to override because it keeps no intermediate state. `--emit-zig` covers the "I want to inspect the Zig" use case directly.

**Alternatives.** Re-introducing an intermediate directory would matter only if a future build mode produced multiple artifacts that needed coordination — not in scope today.

### `--mem` is scoped to sim and truth-table

**Decision.** `--mem=<name>=<path>` preloads a `rom`/`ram` from a raw image and is accepted only by `--sim` and `--truth-table`; every other mode rejects it at parse time with a usage error, exactly as `--strict`/`--format` are gated above. The flag is repeatable up to a fixed 16 (`ParseError.TooManyMemPreloads` → `usage error: too many --mem flags (max 16)`), stored in a fixed `[16]` array on `Args` so `Args.parse` stays allocator-free, and split at the *first* `=` after the prefix so a path may itself contain `=`. Name resolution, file reading, and image validation happen later, in `main.zig`, after the topology is built.

**Rationale.** The flag half of decision 7 of the memories plan prompt (archived at `DOCS/archive/plan-memories.md`; full text at `git show 2e15e97b973d822373d2b078dd0261fc3974b989:DOCS/PLANS_PROMPT.md`). Preloads mean something only to a mode that *runs* the circuit; the default compile deliberately never embeds contents (see [language.md](language.md) "Memory contents are runtime configuration"), so accepting `--mem` there would suggest an artifact can carry an image. Sixteen is far above any teaching circuit's memory count and lets `Args` stay a plain value type. Splitting at the first `=` mirrors how a human reads `name=path`.

**Alternatives.** A growable list on `Args` — needs an allocator in `parse`, which every existing test calls without one. Accepting `--mem` in default compile as "bake this image into the `.wasm`" — a second contents mechanism, rejected with the in-source image. The verbs that do the same job interactively are recorded in [runtime-api.md](runtime-api.md) "`--sim` preloads by declared name; verbs are additive at proto=1".
