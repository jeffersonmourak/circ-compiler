# Compiler Pipeline

### Self-contained WASM artifact per circuit

**Decision.** The compiler produces a single `.wasm` file per `.circ` source. The artifact embeds both the simulation engine and the circuit-specific construction code — no companion runtime file, no external dependencies at load time.

**Rationale.** A two-file model (shared engine `.wasm` + per-circuit data blob) saves bytes when many circuits ship together, but it forces consumers to coordinate two artifacts, version-match them, and load them in order. For the v0 use case — embedding a single circuit in a page or a Node script — one file is the simplest deliverable. Browsers cache the artifact unchanged; a CDN entry is one URL.

**Alternatives.** A circuit-as-data-blob loaded by the existing `circ-renderer-lib.wasm`. Smaller per-circuit footprint and lets the engine evolve independently, but creates a coupling that v0 doesn't need. Revisit if many-circuit pages become a real workload.

### Pipeline shape: parse → topology bytes → custom section append → wasm

**Decision.** Compilation runs as `.circ source → langlang parse tree → resolved IR → `circ.topology.v0.{min,full}` binary payloads → custom sections appended to pre-built runtime blob → `.wasm``. No `zig` subprocess is spawned at circuit-compile time.

**Rationale.** The previous pipeline required Zig installed on every user machine at circuit-compile time. Serializing the resolved IR into a compact binary format and appending it as a WASM custom section to a pre-built runtime blob removes that dependency entirely. The runtime is compiled exactly once at CLI build time and embedded via `@embedFile`. The host protocol (`topology_alloc` + `init()`) is simple enough to implement in any JS environment without SDK support.

**Alternatives.** The previous `zig build` subprocess approach (rejected: requires Zig at user runtime). Direct WASM emission (rejected: requires hand-written WASM lowering). Embedding the Zig compiler as a library (rejected: API instability — the cost of tracking a moving target outweighs the convenience).

### IR shape: flat topology binary (`circ.topology.v0.min` + `circ.topology.v0.full`)

**Decision.** The resolved project IR is serialized into two coexisting binary payloads embedded as WASM custom sections. `circ.topology.v0.min` (magic `CIRC`, version `0x03`) describes an ordered sequence of `createComponent` records followed by `connect` records — what the runtime interpreter consumes. `circ.topology.v0.full` (magic `CIRF`, version `0x03`) carries the same structural data plus per-component instance names and subcircuit-origin chains — what offline tools (the `--preview` renderer; future inspection tooling) consume. The full sub-circuit hierarchy is flattened by the serializer into primitive operations with globally-unique IDs in both payloads, and the two serializers produce identical id sequences so a reader can correlate records by index. Each component record carries a `width: u8` byte (added when multi-bit support landed); `slice` records also carry `(lo, hi)` bytes in the min section, and `concat` records carry their operand list in the full section's auxiliary slot. Memory records (`rom = 8`, `ram = 9`, added in v03) carry one trailing `addr_width` byte in the min section and an `Aux.memory { addr_width }` entry in the full section; memory contents never travel in the topology.

**Rationale.** The runtime interpreter has no concept of sub-circuit boundaries — it only ever calls `createComponent` and `connect`. Flattening at serialize time keeps the interpreter minimal and makes the custom section self-contained. Splitting "what the runtime needs" (`min`) from "what tooling needs" (`full`) means the runtime path stays a fixed-size byte parser while the tooling path can carry arbitrary metadata without bloating the runtime hot path. Pre-1.0 the version axis is freely revvable: bump the internal version byte rather than carrying compatibility shims. The section name still starts with `v0` to keep host-side `customSections()` lookups stable across format-byte bumps.

**Alternatives.** A hierarchical format requiring the runtime to handle sub-circuit scoping. More flexible but much harder to implement correctly in a WASM-hosted interpreter with no dynamic dispatch.

### Pre-built runtime WASM

**Decision.** The runtime (simulation engine, WASM entry point with `topology_alloc`, `init`, `run`, `setPin`, `getOutputValue`, `getOutputDefined` exports) is compiled to `wasm32-freestanding` exactly once, at `zig build circ-compile` time, and embedded in the CLI binary via `@embedFile`.

**Rationale.** The CLI is a single self-contained binary — no install prefix, no runtime path lookup, no version drift. Reproducibility is built in: the same CLI binary always embeds the same runtime version. Concurrent `circ-compile` invocations are safe by construction — there is no shared mutable filesystem state.

**Alternatives.** Runtime located via env var or `--runtime-path` flag (rejected: moving part in packaging, runtime/CLI mismatch bugs). Recompiling the runtime at circuit-compile time (rejected: requires Zig at user runtime, the problem we are solving).

### Host protocol: `topology_alloc` + `init()`

**Decision.** WASM custom sections are opaque to the module itself. The host reads the `circ.topology.v0.min` section via `WebAssembly.Module.customSections()`, calls `topology_alloc(len)` to get a writable pointer, copies the bytes into WASM linear memory, then calls `init()`. Hosts that don't need rendering metadata can ignore the parallel `circ.topology.v0.full` section.

**Rationale.** The protocol is three calls and a `memcpy`. Any JS environment (browser, Node, Deno) can implement it without SDK support. The TypeScript SDK wraps this transparently; raw users follow the documented protocol.

**Alternatives.** Passing topology bytes through WASM imports at instantiation time (rejected: WebAssembly.instantiate takes imports, not arbitrary data; topology can be hundreds of KB). Encoding topology in the module's data section (rejected: requires modifying the WASM binary structure, not just appending).
