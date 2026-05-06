# CLI Design

### Four invocation modes

**Decision.** The CLI supports four modes, selected by mutually-exclusive flags:

```
circ-compile <input.circ> -o <output.wasm>           # produce WASM (default)
circ-compile <input.circ> --emit-zig -o <output.zig> # emit IR Zig source only
circ-compile <input.circ> --inspect                  # dump parse tree / IR to stdout
circ-compile <input.circ> --preview                  # render ASCII schematic to stdout
```

**Rationale.** The default produces the only artifact most users care about. `--emit-zig` exposes the IR step for users who want to inspect, hand-edit, or integrate the emitted source into a larger Zig project — and it falls out of the pipeline for free. `--inspect` is the debugging mode for the compiler itself: it prints the parse tree and resolved IR without invoking the build, useful when a `.circ` file produces unexpected emission. `--preview` is the visualisation mode: it lays out the resolved circuit on a character grid and emits a styled ASCII schematic with line-art glyphs, useful for code review, documentation, and teaching. See [`preview.md`](../preview.md) for the rendering reference.

**Alternatives.** A single mode with everything controlled by output extension. Concise but magical; users have to know that `.zig` extensions trigger different behaviour. Explicit flags are clearer.

### Preview mode flags

**Decision.** `--preview` accepts two extra flags that are meaningless in other modes:

- `--expand-macros` — expand subcircuits into their constituent primitives instead of rendering them as labeled opaque boxes. Rejected at parse time outside `--preview`.
- `--color=auto|always|never` — control ANSI color output. Defaults to `auto` (color when stdout is a TTY *and* `NO_COLOR` is unset). `always` overrides `NO_COLOR` per the convention used by `git`/`ls`/`grep`. Stored but harmlessly ignored in non-preview modes — those don't render anything.

**Rationale.** Macro expansion is a *display* choice, not a compilation one — the same artifact can be rendered both ways. Surfacing it as a flag avoids forking the topology format. `--color` follows the standard tri-state convention so users don't need to learn a project-specific colour discipline.

**Alternatives.** Always render macros expanded (loses the schematic-style abstraction by default) or always render them opaque (hides what the macro actually does). The flag-controlled split serves both audiences without picking one as canonical.

### TypeScript declaration emission deferred

**Decision.** Emitting a `.d.ts` file describing the compiled circuit's pin API is not part of v0. The TypeScript SDK can read `getFileInfo()` at runtime for typed-ish access; static `.d.ts` generation can be added later without breaking changes.

**Rationale.** `.d.ts` emission requires a second emission backend in the compiler and a stable contract between the runtime SDK and the generated types. None of that work blocks the v0 goal of producing a runnable artifact. Deferring keeps the v0 surface small.

**Alternatives.** Including `.d.ts` from the start. Worthwhile polish but expands scope before the core pipeline is proven.

### Build-directory override

**Decision.** A `--build-dir <path>` flag overrides the default temp directory for the intermediate Zig build. When supplied, the directory is preserved on success; without the flag the default is `/tmp/circ-compile-<random>/` and is cleaned on success but preserved on failure.

**Rationale.** Reuses the same orchestration as the default path; the flag just changes the directory choice and the cleanup policy. Users who want to inspect successful builds, integrate with their own tooling, or commit emitted Zig get a first-class way to do so without resorting to `--emit-zig` and rebuilding by hand.

**Alternatives.** Always using a temp dir or always preserving. Either extreme inconveniences a real audience; the flag-controlled split serves both.
