# Tooling Dependencies

The project's runtime guideline is "no dependencies in runtime, Zig-only with as few build-time dependencies as possible." This file captures the few external tools that remain, and how they are integrated.

### langlang version pinning

**Decision.** The project's PEG grammar is processed by [langlang](https://github.com/clarete/langlang) at version `v0.0.12` specifically (the git tag is `go/v0.0.12`; Go's module resolver strips the `go/` prefix). Install with `go install github.com/clarete/langlang/go/cmd/langlang@v0.0.12`.

**Rationale.** Pinning to a specific version protects against silent behaviour changes between releases — a regenerated parser must be byte-identical to the vendored one for a given grammar. `v0.0.12` is also the earliest tagged release that ships a stable Go backend. The C output that the project previously consumed lived on an unmerged `c-output` branch and was never part of any tagged release; relying on it meant tracking a moving branch HEAD. Pinning a tagged release is more durable.

**Alternatives.** Tracking the latest langlang release. Lower maintenance but exposes the project to upstream changes that could silently alter parser output. Pinning is the standard tradeoff.

### Generated parser is vendored in the repo

**Decision.** The langlang-generated `lib/parser/parser.go` file is checked into the repository. langlang is only required when the grammar (`lib/grammar/proto-circ.peg`) changes and the parser needs regeneration. Contributors who don't touch the grammar do not need langlang installed.

**Rationale.** Most users of the repo — including most contributors and all downstream consumers of the CLI — never modify the grammar. Requiring them to install langlang just to build is friction without benefit. Vendoring the generated source means the standard build path needs only Zig and Go (Go is required at every build because the parser is bridged to Zig via CGo c-archive; see below).

**Alternatives.** Generating the parser at every build. Always-current and avoids the "did someone forget to regenerate?" failure mode, but every build pulls in langlang as a hard prerequisite. The vendored approach trades that for a discipline of regenerating-and-committing whenever the grammar changes — a smaller and more localised burden.

### CGo c-archive as the Zig↔Go bridge

**Decision.** The langlang-generated Go parser is wrapped by a small hand-written shim (`lib/parser/shim/shim.go`) and compiled via `go build -buildmode=c-archive` into `lib/parser/parser.a` + `lib/parser/parser.h`. Zig links the archive the same way it would link any static C library. The `build.zig` step that runs `go build` derives `GOARCH` and `GOOS` from the Zig target, so cross-compiling `circ-compile` also cross-compiles the parser archive.

**Rationale.** langlang's only tagged-release output language is Go (`v0.0.12` lists exactly `case "go":` in its language switch). CGo c-archive is the lowest-friction bridge: it presents a C-style API to Zig that mirrors the prior langlang C runtime layout, so `lib/syntax/translate.zig` retains the same tree-walk structure it had against the C parser. Contributors never have to touch Go code unless they change the shim itself.

**Alternatives.** Subprocess bridge (spawn a precompiled Go binary at compile time, exchange JSON or protobuf): adds per-file process spawn overhead and another embedded binary. Hand-port to Zig: cleanest result but a non-trivial maintenance burden for a parser the upstream tool already maintains.

**Trade-offs.** The c-archive embeds the Go runtime (~2 MB per binary, fixed cost regardless of code size) and means `circ-compile` always links Go's GC and scheduler even though only the parser uses them. Cross-compile to Windows is unsupported because `c-archive` does not target it. Go is now required at every build (not just at parser-regen time).

### Build-time check when regenerating

**Decision.** When the build is asked to regenerate the parser (an explicit build option, not the default path), it checks that the available `langlang` binary reports the expected version. A mismatch is a hard build error.

**Rationale.** Silent regeneration with the wrong version would produce a parser that compiles but behaves subtly differently, and the diff would land in version control as a "harmless" parser update. An upfront version check makes the failure loud.

**Alternatives.** Trusting whatever version is installed. Convenient until it breaks; the failure mode is hard to diagnose because parser bugs surface as `.circ` parse failures, not as build errors.
