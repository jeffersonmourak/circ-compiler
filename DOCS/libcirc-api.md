# libcirc — the compiler front end as a library

`libcirc` is `circ-compile` without the process: hand it an in-memory
project and get back exactly what the CLI prints or writes — the
self-contained `.wasm` (`circ_compile`), the `--preview` text
(`circ_preview`), the `--truth-table` output (`circ_truth_table`), or the
`--analyze` JSON (`circ_analyze`). The CLI is itself a client of the same
Zig API (`lib/libcirc.zig`), so the two cannot drift: the driver tests
prove the library equals the in-process CLI byte for byte across the
render, table, and compile fixtures.

The library has three surfaces:

- **Zig** — `lib/libcirc.zig`: `analyze`, `compile`, `preview`, `truthTable`
  take an allocator and a `Request` and return an `Outcome{ status, body }`.
  `frontend.run` and the `modes.*` steps underneath are public for callers
  that want the pieces (the CLI uses them to keep its own stderr/exit-code
  contract).
- **C** — `include/libcirc.h`, built by `zig build libcirc` into
  `zig-out/lib/libcirc.a`. Ten exports, one JSON request in, one result
  buffer out.
- **WebAssembly** — the same ten exports as `zig-out/lib/libcirc.wasm`
  (`zig build libcirc-wasm`, `wasm32-freestanding`), for browsers and Node.
  See *The wasm module* below.

## Request

One JSON object. Only `root` is required.

```json
{"root": "/playground/main.circ",
 "files": {"/playground/main.circ": "input a\nnot n(in=a)\noutput o(in=n.out)\n"},
 "options": {"color": "never"}}
```

- `root` — the file to compile. A key of `files`, or (native builds only) a
  path on disk.
- `files` — the in-memory project: absolute path → source text. The
  library normalises the keys (`.`/`..` folded) and consults them
  **before** disk, so imports between `files` entries resolve without any
  filesystem access. An import missing from `files` falls back to disk on
  native and is `E009` in the wasm build. The library rejects a relative
  key (status 2).
- `options` — all optional; an unknown or mistyped key is status 2, never a
  silent default:

| Key | Type | Default | Used by |
| --- | --- | --- | --- |
| `expand_macros` | bool | `false` | preview |
| `expand_display` | bool | `false` | preview |
| `color` | `"never"` \| `"always"` | `"never"` | preview (no `"auto"`: the library has no TTY) |
| `format` | `"markdown"` \| `"csv"` \| `"json"` | `"markdown"` | truth table |
| `value_format` | `"binary"` \| `"hex"` \| `"decimal"` | `"binary"` | truth table |
| `truth_table_cap` | integer 1..24 | `16` | truth table: hard cap on the sum of input widths |
| `preloads` | object: memory name → hex string | `{}` | truth table: raw images loaded into root `rom`s by declared name before any vector is driven (`ceil(W/8)` bytes per word, little-endian; the same bytes `--mem` reads from a file) |
| `warnings_as_errors` | bool | `false` | compile, preview, truth table: `W*` becomes status 1 |

The `--analyze` stdin contract of the CLI (`{"root_path","overlays"}`,
`DOCS/analyze-api.md`) is a different, older shape; `circ-compile --analyze`
keeps parsing it itself and calls the same Zig API.

## Status codes and result bodies

| Status | Name | `circ_analyze` | `circ_compile` | `circ_preview` | `circ_truth_table` |
| --- | --- | --- | --- | --- | --- |
| 0 | ok | analysis JSON (trailing `\n`) | the `.wasm` bytes | the schematic text | the table |
| 1 | diagnostics | — | `{"files":[…],"diagnostics":[…],"symbols":[],"references":[]}` | same | same |
| 2 | bad request | `{"error":"…"}` | same | same | same |
| 3 | refused | — | — | `{"error":"layout build failed: …"}` | `{"error":"…"}`: a bad preload (`truth-table: preload '<name>': <reason>`), a stateful `ram` (`truth-table: ram '<name>' is stateful (…); use --sim to drive it`), or the cap (`truth table requires N input bits, exceeds cap of C (raise with options.truth_table_cap, max 24)`) — checked in that order |
| 4 | out of memory | empty | empty | empty | empty |
| 5 | internal | `{"error":"analyze: <ErrName>"}` | `{"error":"<stage>: <ErrName>"}` | same | same |

Status 1 bodies use the analyze-api shape, so one decoder serves both
`circ_analyze` and a failed compile. A root that fails to parse at all is
status 1 with a single `"syntax"` diagnostic at `1:1-1:2` whose message is
`parse failed: <ErrName>`. A root that is neither a `files` key nor a
readable path is status 2, `{"error":"failed reading input file: FileNotFound"}`.
Status 0 omits warnings; call `circ_analyze` for them.

`circ_version` is always status 0 with:

```json
{"version":"0.0.2","revision":"<git short sha>","topology_version":3,"full_version":3,
 "parser":"langlang go/v0.0.12 abi=1",
 "parser_runtime_sha256":"<sha256 of the runtime pasted into lib/parser/parser.zig>",
 "grammar_sha256":"<sha256 of lib/grammar/proto-circ.peg at build time>"}
```

`topology_version`/`full_version` are the `circ.topology.v0.min`/`.full`
format versions the artifact carries; the two sha256 fields are the skew
signals for a host that caches compiled parsers or grammars.

## The C ABI

```c
uint8_t *circ_alloc(size_t len);                  /* request buffers */
void     circ_free(uint8_t *ptr, size_t len);
uint32_t circ_version(void);
uint32_t circ_analyze(const uint8_t *req, size_t len);
uint32_t circ_compile(const uint8_t *req, size_t len);
uint32_t circ_preview(const uint8_t *req, size_t len);
uint32_t circ_truth_table(const uint8_t *req, size_t len);
const uint8_t *circ_result_ptr(void);             /* library-owned */
size_t   circ_result_len(void);
uint32_t circ_reset(void);                        /* returns 0 */
```

Pointers and lengths are pointer-sized (`uint8_t*`/`size_t`), which is
`i32` in the wasm32 export signatures.

**Memory model.** The request bytes belong to the caller: fill a buffer from
`circ_alloc`, pass it, free it with `circ_free` afterwards (the library
never keeps a pointer to it). Every allocation a call makes comes from a
per-call arena that the next call rewinds at its start. The library
copies the result into a single buffer of its own that `circ_result_ptr`/
`circ_result_len` expose until the next `circ_*` call replaces it. The
simulation engine (used by the truth table) allocates from its own global
arena, which `circ_truth_table` releases after rendering. `circ_reset`
drops the result buffer, the call arena, and the engine arena. Nothing is
thread-safe: all of that state is process-global, so serialise calls.

**Logging.** The library root installs a `std_options.logFn` that discards
everything; a host never sees engine or resolver logs on its stderr.

## Building and linking

```sh
zig build libcirc            # zig-out/lib/libcirc.a + zig-out/include/libcirc.h
zig build libcirc-smoke      # compiles and runs examples/c/analyze.c against it
zig build libcirc-wasm       # zig-out/lib/libcirc.wasm (wasm32-freestanding)
```

Both wasm artifacts (the embedded runtime and `libcirc.wasm`) follow
`-Dwasm-optimize=<mode>` (default `ReleaseSmall`, stripped), independently
of the CLI's `-Doptimize`; `-Dwasm-optimize=Debug` keeps names and DWARF for
bisecting.

`examples/c/analyze.c` is the smallest complete client: it prints the
version JSON, then the analysis JSON, and the preview for the inverter
request shown above, and exits non-zero on any status other than 0. Its
request literal is the one in this document; `tests/libcirc/c_api_test.zig`
parses the same bytes, so the two cannot drift.

## The wasm module

`zig-out/lib/libcirc.wasm` is one self-contained module: the whole front
end, the simulation engine (for truth tables), and the embedded runtime
bytes the compiled artifacts carry. It reads no files and has no clock; a
request must supply every file it needs (`files` is the only source), and
an import missing from `files` is `E009`.

**Exports** — exactly `memory` plus the ten `circ_*` functions of the C
ABI. On wasm32 every pointer and length is an `i32`:

| Export | Signature | Notes |
| --- | --- | --- |
| `circ_alloc` | `(len: i32) -> i32` | Request buffers. Never 0 for a zero-length request. |
| `circ_free` | `(ptr: i32, len: i32)` | |
| `circ_version` | `() -> i32` | Status 0; result = the version JSON. |
| `circ_analyze` / `circ_compile` / `circ_preview` / `circ_truth_table` | `(req: i32, len: i32) -> i32` | Status code; result in the buffer. |
| `circ_result_ptr` | `() -> i32` | Library-owned; valid until the next `circ_*` call. |
| `circ_result_len` | `() -> i32` | |
| `circ_reset` | `() -> i32` | Drops the result buffer, the call arena, and the engine arena. Returns 0. |

**Host imports** — only the two engine log hooks, both in the `env`
namespace: `debugEnabled(): i32` (return 0 to keep engine logging off,
which also means nothing is ever formatted) and `onDebugLog(ptr: i32,
len: i32, level: i32)`. A minimal import object is
`{ env: { debugEnabled: () => 0, onDebugLog: () => {} } }`.

**Memory contract.** The same rules as the C ABI: request bytes are yours
(`circ_alloc` → copy in → call → `circ_free`), the result is the library's
until the next call, every call's own allocations die when it returns, and
`circ_truth_table` releases the engine arena after rendering. Linear memory
grows on demand and never shrinks; after a warm-up it is flat: fifty
repeated compiles, previews, or truth tables leave `memory.buffer.byteLength`
exactly where the fifth call left it (`tests/e2e/libcirc_wasm_test.zig`).
`WebAssembly.Memory.buffer` **detaches on every grow**, so never keep a
`Uint8Array` view across a `circ_*` call: re-read `exports.memory.buffer`
for every copy in and out. The instance is single-threaded by construction;
a page that must not block instantiates it inside a Web Worker.

**Loading from Node.** The helper below is the protocol; the test harness
(`tests/harness/libcirc_loader.js`) and the site's worker implement it
verbatim. `tests/e2e/libcirc_wasm_test.zig` runs the example
(`doc example loads and compiles the inverter`), so the example cannot
drift from the module.

```js
// libcirc-api.md: Node example
const api = {
  result() {
    const ptr = wasm.circ_result_ptr(), len = wasm.circ_result_len();
    return Buffer.from(new Uint8Array(wasm.memory.buffer, ptr, len)); // re-read memory.buffer: it detaches on grow
  },
  call(op, request) {                          // op ∈ analyze | compile | preview | truth_table
    const req = Buffer.from(JSON.stringify(request), "utf8");
    const ptr = wasm.circ_alloc(req.length);
    if (ptr === 0) throw new Error("circ_alloc failed");
    new Uint8Array(wasm.memory.buffer).set(req, ptr);
    const status = wasm["circ_" + op](ptr, req.length);
    wasm.circ_free(ptr, req.length);
    return { status, bytes: this.result() };
  },
};
const out = api.call("compile", {
  root: "/playground/main.circ",
  files: { "/playground/main.circ": "input a\nnot n(in=a)\noutput o(in=n.out)\n" },
});
if (out.status !== 0) throw new Error("status " + out.status + ": " + out.bytes);
if (out.bytes.subarray(0, 4).toString("latin1") !== "\0asm") throw new Error("not a wasm artifact");
process.stdout.write("PASS\n");
```

where `wasm` is `(await WebAssembly.instantiate(bytes, { env: { debugEnabled:
() => 0, onDebugLog: () => {} } })).instance.exports`. The returned artifact
is instantiated with the topology host protocol of `DOCS/wasm-api.md`
(`topology_alloc` → copy the `circ.topology.v0.min` custom section → `init`
→ `setPin`/`run`/`getOutputValue`/`getOutputDefined`).

**Loading in a browser.** `WebAssembly.instantiateStreaming(fetch(url),
imports)` with the same import object; run it in a Worker and post the
result copy back (`postMessage(bytes, [bytes.buffer])`) so a `2^N` truth
table never blocks the page.

**Version handshake.** Call `circ_version` first: `topology_version` /
`full_version` are the section format versions the artifacts carry (the
renderer must accept them), `parser` names the generator and bytecode ABI
of the vendored parser, and `parser_runtime_sha256` / `grammar_sha256`
identify the exact parser and grammar the module was built from.

**Size.** Measure with `stat -f%z zig-out/lib/libcirc.wasm` and
`gzip -9 -c zig-out/lib/libcirc.wasm | wc -c`. Budget 600 KB raw / 200 KB
gzip; the test suite fails above 3 MiB. On 2026-09-10 (the layout
rewrite): 437,566 B raw, 167,036 B gzip.

**Not exported.** `--inspect`, `--sim`, and `--emit-zig` stay CLI-only.
