# Tooling Dependencies

The project's runtime guideline is "no dependencies in runtime, Zig-only with as few build-time dependencies as possible." This file captures the few external tools that remain, and how they are integrated.

### langlang version pinning

**Decision.** The project's PEG grammar is processed by [langlang](https://github.com/clarete/langlang) at the version `go/v0.0.12` specifically. The required version is documented in the build instructions and checked at build time when grammar regeneration is requested.

**Rationale.** langlang is the only non-Zig tool in the build pipeline. Pinning to a specific version protects against silent behaviour changes between releases — a regenerated parser must be byte-identical to the vendored one for a given grammar. The `go/v0.0.12` tag is the version the project's grammar has been validated against.

**Alternatives.** Tracking the latest langlang release. Lower maintenance but exposes the project to upstream changes that could silently alter parser output. Pinning is the standard tradeoff.

### Generated parser is vendored in the repo

**Decision.** The langlang-generated `lib/parser.c` and `lib/parser.h` files are checked into the repository. langlang is only required when the grammar (`lib/grammar/proto-circ.peg`) changes and the parser needs regeneration. Day-to-day contributors who don't touch the grammar do not need langlang installed.

**Rationale.** Most users of the repo — including most contributors and all downstream consumers of the CLI — never modify the grammar. Requiring them to install a Go toolchain plus a specific langlang version just to build is friction without benefit. Vendoring the generated sources means the standard build path needs only Zig.

**Alternatives.** Generating the parser at every build. Always-current and avoids the "did someone forget to regenerate?" failure mode, but every build pulls in langlang as a hard prerequisite. The vendored approach trades that for a discipline of regenerating-and-committing whenever the grammar changes — a smaller and more localised burden.

### Build-time check when regenerating

**Decision.** When the build is asked to regenerate the parser (an explicit build option, not the default path), it checks that the available `langlang` binary reports the expected version. A mismatch is a hard build error.

**Rationale.** Silent regeneration with the wrong version would produce a parser that compiles but behaves subtly differently, and the diff would land in version control as a "harmless" parser update. An upfront version check makes the failure loud.

**Alternatives.** Trusting whatever version is installed. Convenient until it breaks; the failure mode is hard to diagnose because parser bugs surface as `.circ` parse failures, not as build errors.
