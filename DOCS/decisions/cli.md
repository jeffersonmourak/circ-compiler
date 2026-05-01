# CLI Design

### Three invocation modes

**Decision.** The CLI supports three modes, all using `-o <path>` for the output destination:

```
circ-compile <input.circ> -o <output.wasm>           # produce WASM (default)
circ-compile <input.circ> --emit-zig -o <output.zig> # emit IR Zig source only
circ-compile <input.circ> --inspect                  # dump parse tree / IR to stdout
```

**Rationale.** The default produces the only artifact most users care about. `--emit-zig` exposes the IR step for users who want to inspect, hand-edit, or integrate the emitted source into a larger Zig project — and it falls out of the pipeline for free. `--inspect` is the debugging mode for the compiler itself: it prints the parse tree and resolved IR without invoking the build, useful when a `.circ` file produces unexpected emission.

**Alternatives.** A single mode with everything controlled by output extension. Concise but magical; users have to know that `.zig` extensions trigger different behaviour. Explicit flags are clearer.

### TypeScript declaration emission deferred

**Decision.** Emitting a `.d.ts` file describing the compiled circuit's pin API is not part of v0. The TypeScript SDK can read `getFileInfo()` at runtime for typed-ish access; static `.d.ts` generation can be added later without breaking changes.

**Rationale.** `.d.ts` emission requires a second emission backend in the compiler and a stable contract between the runtime SDK and the generated types. None of that work blocks the v0 goal of producing a runnable artifact. Deferring keeps the v0 surface small.

**Alternatives.** Including `.d.ts` from the start. Worthwhile polish but expands scope before the core pipeline is proven.

### Build-directory override

**Decision.** A `--build-dir <path>` flag overrides the default temp directory for the intermediate Zig build. When supplied, the directory is preserved on success; without the flag the default is `/tmp/circ-compile-<random>/` and is cleaned on success but preserved on failure.

**Rationale.** Reuses the same orchestration as the default path; the flag just changes the directory choice and the cleanup policy. Users who want to inspect successful builds, integrate with their own tooling, or commit emitted Zig get a first-class way to do so without resorting to `--emit-zig` and rebuilding by hand.

**Alternatives.** Always using a temp dir or always preserving. Either extreme inconveniences a real audience; the flag-controlled split serves both.
