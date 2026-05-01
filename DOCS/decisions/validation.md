# Semantic Validation

The compiler validates `.circ` source semantically before emission. Any hard error prevents the artifact from being generated; warnings allow emission but surface to the user.

### Hard errors block emission

**Decision.** When the compiler detects a hard error, it reports the error to stderr and exits non-zero without producing any output `.wasm`. Partial or "best-effort" artifacts are never emitted.

**Rationale.** A circuit that fails semantic checks cannot be trusted to behave as the source describes. Emitting an artifact anyway would let broken circuits ship and fail at runtime in obscure ways. Refusing to emit forces the failure into the build step where it's loudest and easiest to fix.

**Alternatives.** Emit-with-errors-flagged. Common in some toolchains for IDE feedback, but the CLI is not an IDE — its job is to produce correct artifacts or refuse.

### Hard error categories

**Decision.** The following are hard errors:

- Reference to undeclared name
- Reference to a non-existent port on a known component
- Port driven by multiple sources (no implicit bus semantics in v0)
- Required input port left unconnected
- Two components with the same instance name in the same scope
- Instance name colliding with an imported sub-circuit type or a built-in gate
- Output port declared but never assigned
- Imported file not found
- Import alias colliding with another import or a built-in
- Circular import chain
- Combinational loop (a feedback path with no delay element)

**Rationale.** Each of these makes the circuit either ill-defined (undeclared references, missing connections), ambiguous (name collisions, multi-driven ports), or non-terminating (combinational loops, import cycles). None of them have a defensible default interpretation.

**Alternatives.** Treating multi-driver as wired-OR by default. Plausible but surprising; deferred until a syntax for explicit bus semantics exists.

### Combinational loops are hard errors

**Decision.** A feedback path with no delay element (e.g. `not a (in = a.out)`) is rejected at compile time via a graph cycle check on the connection topology, ignoring delay-bearing components.

**Rationale.** The runtime engine processes such loops by oscillating events forever — `propagate()` never terminates. A compile-time check is the only place this can be caught without leaving a settle-only runtime hanging on a malformed circuit. Detection is cheap (DFS over the connection graph).

**Alternatives.** Runtime detection with a max-iterations cap. Catches the bug later, leaks into runtime API, and arbitrary cap values mean some legitimate-but-slow circuits get aborted.

### Warning categories (default: emit + warn)

**Decision.** The following emit warnings but allow the artifact to be produced:

- An `input` pin declared but never connected to anything
- An imported sub-circuit never instantiated
- A sub-circuit's `output` declared but the parent never reads it (dangling output)

**Rationale.** None of these break the circuit — they're indicators of dead code or work-in-progress, common during iterative development. Blocking emission on them would make exploratory editing painful. Surfacing them as warnings keeps them visible without halting work.

**Alternatives.** Treating any of these as hard errors. Too aggressive for v0; users routinely have unconnected pins while sketching. The `--warnings-as-errors` flag below covers users who want strict mode.

### `--warnings-as-errors` flag

**Decision.** The CLI accepts a `--warnings-as-errors` (also `-Werror`) flag. When set, any warning is promoted to a hard error and blocks emission. Default behaviour is warn-and-emit with exit code 0.

**Rationale.** Standard compiler convention (gcc, rustc, tsc). Lets CI pipelines opt into strict builds without forcing the same friction on local development. The default exits 0 on warnings so simple `circ-compile` invocations succeed during iterative work.

**Alternatives.** Always exiting non-zero on warnings (forces CI strictness on everyone) or never offering a strict mode (makes warnings invisible to CI). The flag covers both audiences.

### Diagnostic format: location + message for v0

**Decision.** Diagnostics are formatted as `<file>:<line>:<col>: <level>: <message>` — for example `demo.circ:14:8: error: undeclared name 'foo'`. Source-snippet rendering with caret indicators (rustc-style) is deferred to a follow-up.

**Rationale.** Location-tagged messages give editors enough information to jump to the offending line; this covers the bulk of the developer-experience benefit. Snippet rendering requires the langlang parser to accurately track byte offsets through the parse tree and a snippet-extraction pass over the original source — useful but not blocking for v0.

**Alternatives.** Plain message without location (insufficient for editor integration) or full snippet rendering immediately (more polish than needed for the first cut). The chosen format is the minimum viable for usability with a clear upgrade path.
