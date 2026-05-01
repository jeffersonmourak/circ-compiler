# Compiler Architecture Decisions

This directory captures the architectural decisions guiding the development of the `.circ` compiler — a CLI that consumes a `.circ` source file and produces a self-contained `.wasm` artifact simulating that specific circuit.

Each decision follows the format: **decision**, **rationale**, **alternatives**.

## Topics

### [compiler-pipeline.md](compiler-pipeline.md)
- Output artifact shape (single self-contained `.wasm` per circuit)
- Compilation pipeline (`.circ → IR Zig file → zig build → .wasm`)
- IR shape (code-emitting Zig file, one function per `.circ`)
- `zig build` orchestration (subprocess + vendored runtime)
- Build directory layout and `--build-dir` override

### [runtime-api.md](runtime-api.md)
- Settle-only `run()` semantics
- Cold-start `reset()` semantics
- Introspection surface (snapshot + topology + pending events)
- File info exposure (Zig constants in static data section)
- Full WASM export list for compiled artifacts

### [language.md](language.md)
- Sub-circuits compile as Zig functions, one per `.circ` file
- Source-path debug info stored outside the engine
- Built-in primitives vs compiler-provided macro library (`nand`, `or`, `xor`)
- Import statement syntax (`import name from "./file.circ"`)
- LEDs vs `output` declarations

### [validation.md](validation.md)
- Hard errors vs warnings vs accepted
- Combinational loops are hard errors
- `--warnings-as-errors` flag for CI strictness
- Diagnostic format (location + message for v0, snippets deferred)

### [cli.md](cli.md)
- Invocation forms and flags
- TypeScript declaration emission deferred to post-v0

### [tooling.md](tooling.md)
- langlang version pinning (`go/v0.0.12`)
- Generated parser sources vendored in the repo

## Conventions

- Decisions use `###` headings inside topic files.
- Each decision is small (decision / rationale / alternatives, ~15 lines).
- No numbering — decisions are referenced by heading slug.
- The runtime principle of "few dependencies, Zig-only" applies across every decision unless explicitly noted.
