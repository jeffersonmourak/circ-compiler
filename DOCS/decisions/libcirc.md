# libcirc

The entries below record the library half of the libcirc initiative (`lib/libcirc.zig`, `libcirc.a`, `libcirc.wasm`, the site's `/playground`). The numbered decisions they cite are the ten locked in `DOCS/PLANS_PROMPT.md`; the parser half is in [tooling.md](tooling.md). The host-facing reference is `DOCS/libcirc-api.md`; the JSON the status-1 result shares with `--analyze` is `DOCS/analyze-api.md`.

### One wasm module, ten exports, JSON in / bytes-or-JSON out

**Decision.** The compiler front end is one C ABI with ten exports, in this order: `circ_alloc(len)`, `circ_free(ptr, len)`, `circ_version()`, `circ_analyze(req, len)`, `circ_compile(req, len)`, `circ_preview(req, len)`, `circ_truth_table(req, len)`, `circ_result_ptr()`, `circ_result_len()`, `circ_reset()`. A request is one JSON object, `{"root": "/playground/main.circ", "files": {...}, "options": {...}}`; every call returns a status — `0` ok, `1` front-end diagnostics in the analyze-api shape, `2` bad request, `3` mode refusal (`{"error": "..."}`: the input-bit cap, a stateful RAM truth table, a layout failure), `4` out of memory, `5` internal — and leaves its result in a library-owned buffer valid until the next `circ_*` call. Request buffers come from `circ_alloc` and are freed by the caller. The surface is identical for `libcirc.a` (`export fn`, `callconv(.c)`, pointer-sized `ptr`/`len`) and `libcirc.wasm` (decision 3).

**Rationale.** One request shape and one result buffer keep the ABI small enough to implement by hand in any host (the site's worker is forty lines), and a status per call lets a host branch without parsing first. Byte identity with the CLI is the acceptance: the driver tests compare every mode with the in-process CLI.

**Alternatives.** One export per mode with out-pointers (more surface, same information). A WASI shim (files and stdio the library does not need). Per-call instantiation (throws away the warm module).

### Overlay-first virtual file loading

**Decision.** `file_loader.resolveImportPath` resolves imports lexically with `std.fs.path.resolvePosix`, returns the overlay key when the overlay holds it, otherwise `realpath` on native, otherwise `FileNotFound` (which the import scan reports as `E009`). The loader consults the overlay by the normalised key before touching disk; disk branches are compiled out on `.freestanding`. Keys are absolute-looking, `/playground/<name>.circ`, and match byte for byte (decision 4).

**Rationale.** A root plus overlay-only siblings must resolve with no filesystem, which is the whole browser case. The change also fixed a latent native bug: an overlay-only sibling import failed with `E009` because the loader realpathed unconditionally, and an edited file under a symlinked directory could miss its own overlay entry. The inline analyze test `overlay-only sibling import resolves without E009` is the tripwire.

**Alternatives.** A virtual-filesystem trait object (an abstraction for two implementations). Rewriting imports client-side (the compiler would report positions in text the user never wrote).

### Library memory model

**Decision.** Every compiler allocation for one call comes from a per-call `ArenaAllocator` that is rewound at the start of the next call; the result is copied into one library-owned buffer; `memory.reset()` (`arena.reset(.free_all)`) is the single addition to the engine's global allocator (CLAUDE.md invariant 6) and is called only after a truth table has torn down its `Session`, and by `circ_reset`. The module is never re-instantiated per call (decision 5).

**Rationale.** A long-lived host must not grow without bound. The wasm e2e test is the tripwire: fifty repeated compiles, previews and truth tables leave linear memory exactly where the fifth call left it. On wasm the arenas sit over `std.heap.wasm_allocator` (`page_allocator` is that allocator on wasm32), so freed buffers return to its free lists.

**Alternatives.** An allocator parameter on the engine (rejected by invariant 6). A fresh `WebAssembly.instantiate` per request (simple, but every call pays instantiation and the runtime is warm for nothing).

### `-Dwasm-optimize` governs both wasm builds

**Decision.** `circ-runtime.wasm` and `libcirc.wasm` follow `-Dwasm-optimize` (default `ReleaseSmall`, stripped), decoupled from the CLI's `-Doptimize` (decision 6). `wasm-opt` is not a build dependency.

**Rationale.** The runtime used to follow the global optimize mode, which is why every committed site artifact was a ~921 KB Debug build (almost all DWARF and name sections); a Debug CLI must still embed a small runtime. `expected-wasm` fixtures are behaviour vectors, so runtime bytes may change freely. Measured: `circ-runtime.wasm` 19,628 B (8,715 B gzip) ReleaseSmall vs 933,116 B Debug; `libcirc.wasm` 383,450 B raw / 146,581 B gzip against a 600 KB / 200 KB budget with a 3 MiB hard cap in the test suite.

**Alternatives.** `-Doptimize=ReleaseSmall` for everything (slows every native test). Post-processing with `wasm-opt`/`wasm-strip` (another toolchain dependency for a few kilobytes).

### The renderer follows the compiler, once, per topology version

**Decision.** The site's `circ-renderer` pin and every committed example artifact move together: one commit bumps the pin (`bun add circ-renderer@github:jeffersonmourak/circ-renderer#<ref>`), regenerates `site/public/wasm/*.wasm`, and the committed `libcirc.wasm` comes from the same compiler revision. The playground handshakes `circ_version().full_version` against the versions the renderer decodes and shows a banner instead of a decode throw (decision 7). The v03 (memories) sync of the renderer — kinds `rom`/`ram`, ports `addr/din/we/clk`, the memory aux byte — is the next such step, after the native-memories work merges.

**Rationale.** Pre-1.0 the topology version byte is freely revvable (`compiler-pipeline.md`), so the renderer must follow rather than the compiler carry compatibility shims; doing it in one commit keeps the examples page and the playground from ever disagreeing about which bytes they can draw.

**Alternatives.** A compatibility shim in the compiler (rejected by the pipeline decision). Letting the pin and the artifacts drift independently (the exact failure the handshake exists to make visible).

### Playground artifacts are committed; the module runs in a Web Worker

**Decision.** `site/public/wasm/libcirc.wasm` and `libcirc.manifest.json` (version, revision, topology versions, parser identity, grammar sha256, sizes, budget) are committed, written by `site/scripts/build-libcirc.ts`, which sources the identity from the binary's own `circ_version()` and fails over budget; they are refreshed by hand (`bun run libcirc`) on releases, and the deploy workflow stays bun-only. In the page, a dedicated Web Worker owns the instance so a `2^N` truth-table enumeration never blocks the main thread; the page caps the enumeration at 12 input bits (decision 8).

**Rationale.** Building the wasm in CI would put Zig into the site deploy for an artifact that changes only when the compiler does; committing it keeps the site buildable from `bun` alone and makes the exact module a page serves reviewable in the diff. The `bun test` suite runs against the committed module, so a stale one fails before it ships.

**Alternatives.** Building in CI (Zig in `deploy-site.yml`). Running the module on the main thread (a 4,096-row table freezes the editor).

### Not exported through libcirc

**Decision.** `--sim` (stdio-shaped; reads memory image files), `--emit-zig` (needs a Zig toolchain on the consumer's machine), and `--inspect` (single-module debug output) stay CLI-only. Browser interactivity is `circ_compile`'s bytes fed to `circ-renderer`'s `renderCircuit({ bytes })` (decision 10).

**Rationale.** Each of the three either needs a host facility the library deliberately lacks or duplicates what the renderer already does over the artifact. `circ_inspect` is a cheap later addition if a consumer appears.

**Alternatives.** A `circ_sim` line-protocol export (would re-implement stdio over JSON for no consumer).
