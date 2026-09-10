# Archived plans

Each file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the canonical commit listed in that file's header.

| Archive | Contents |
| ------- | -------- |
| [plan-v0.md](plan-v0.md) | v0 implementation plan (highlights; full bundle in git history) |
| [plan-dead-code-removal.md](plan-dead-code-removal.md) | Dead-code removal plan (highlights; full bundle in git history) |
| [plan-test-speed.md](plan-test-speed.md) | Test-suite speed-up plan (highlights; full bundle in git history) |
| [plan-zig-free-cli.md](plan-zig-free-cli.md) | Self-contained `circ-compile`: no Zig at user runtime (highlights; full bundle in git history) |
| [plan-cli-preview.md](plan-cli-preview.md) | `circ-compile <file> --preview`: ASCII circuit schematic rendering with opaque/expanded macro modes and ANSI color (highlights; full bundle in git history) |
| [plan-multi-bit-language.md](plan-multi-bit-language.md) | Multi-bit wires language extension (literal widths, slice / bit-index / concat, parametric sub-circuits, topology format v02). Landed across stages S1–S12. |
| [plan-memories.md](plan-memories.md) | Native memories (`rom`/`ram`): engine memory kind with two `[]u64` planes, topology v03 (`rom=8`/`ram=9`, `addr/din/we/clk`), eight `mem*` runtime exports, `--mem` preloads, `--sim` memory verbs, `E017`/`E018` (highlights; full bundle in git history). |
| [plan-libcirc.md](plan-libcirc.md) | The compiler front end as a library: parser generated straight to Zig by the langlang fork (Go retired), `lib/libcirc.zig` + the ten `circ_*` C ABI, `zig build libcirc` / `libcirc-wasm`, and the site's `/playground` (highlights; full bundle in git history). |
| [plan-playground.md](plan-playground.md) | Playground v2, a workbench: the usage-aware builtin fast path and the per-page JS budget, a CodeMirror editor with compiler diagnostics, files as tabs then a workspace tree, the `circ.playground.v1` envelope, share links, source linking by name, settings and ROM images, the Memory tab, the gallery, and six `circ-renderer` pin bumps (highlights; full bundle in git history). |
