# libcirc — the compiler front end as a library

`libcirc` is `circ-compile` without the process: hand it an in-memory
project and get back exactly what the CLI prints or writes — the
self-contained `.wasm` (`circ_compile`), the `--preview` text
(`circ_preview`), the `--truth-table` output (`circ_truth_table`), or the
`--analyze` JSON (`circ_analyze`). The CLI is itself a client of the same
Zig API (`lib/libcirc.zig`), so the two cannot drift: the driver tests
prove the library equals the in-process CLI byte for byte across the
render, table and compile fixtures.

There are two surfaces:

- **Zig** — `lib/libcirc.zig`: `analyze`, `compile`, `preview`, `truthTable`
  take an allocator and a `Request` and return an `Outcome{ status, body }`.
  `frontend.run` and the `modes.*` steps underneath are public for callers
  that want the pieces (the CLI uses them to keep its own stderr/exit-code
  contract).
- **C** — `include/libcirc.h`, built by `zig build libcirc` into
  `zig-out/lib/libcirc.a`. Ten exports, one JSON request in, one result
  buffer out. Phase 3 builds the same root for `wasm32-freestanding`.

## Request

One JSON object. Only `root` is required.

```json
{"root": "/playground/main.circ",
 "files": {"/playground/main.circ": "input a\nnot n(in=a)\noutput o(in=n.out)\n"},
 "options": {"color": "never"}}
```

- `root` — the file to compile. A key of `files`, or (native builds only) a
  path on disk.
- `files` — the in-memory project: absolute path → source text. Keys are
  normalised (`.`/`..` folded) and consulted **before** disk, so imports
  between `files` entries resolve without any filesystem access. An import
  that is not in `files` falls back to disk on native and is `E009` in the
  wasm build. A relative key is rejected (status 2).
- `options` — all optional; an unknown or mistyped key is status 2, never a
  silent default:

| Key | Type | Default | Used by |
| --- | --- | --- | --- |
| `expand_macros` | bool | `false` | preview |
| `expand_display` | bool | `false` | preview |
| `color` | `"never"` \| `"always"` | `"never"` | preview (there is no `"auto"`: the library has no TTY) |
| `format` | `"markdown"` \| `"csv"` \| `"json"` | `"markdown"` | truth table |
| `value_format` | `"binary"` \| `"hex"` \| `"decimal"` | `"binary"` | truth table |
| `truth_table_cap` | integer 1..24 | `16` | truth table: hard cap on the sum of input widths |
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
| 3 | refused | — | — | `{"error":"layout build failed: …"}` | `{"error":"truth table requires N input bits, exceeds cap of C (raise with options.truth_table_cap, max 24)"}` |
| 4 | out of memory | empty | empty | empty | empty |
| 5 | internal | `{"error":"analyze: <ErrName>"}` | `{"error":"<stage>: <ErrName>"}` | same | same |

Status 1 bodies use the analyze-api shape, so one decoder serves both
`circ_analyze` and a failed compile. A root that does not parse at all is
status 1 with a single `"syntax"` diagnostic at `1:1-1:2` whose message is
`parse failed: <ErrName>`. A root that is neither a `files` key nor a
readable path is status 2, `{"error":"failed reading input file: FileNotFound"}`.
Warnings are not returned on status 0 — call `circ_analyze` for them.

`circ_version` is always status 0 with:

```json
{"version":"0.0.2","revision":"<git short sha>","topology_version":2,"full_version":2,
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
per-call arena that is rewound at the start of the next call, and the
result is copied into one library-owned buffer that `circ_result_ptr`/
`circ_result_len` expose until the next `circ_*` call replaces it. The
simulation engine (used by the truth table) allocates from its own global
arena, which `circ_truth_table` releases after rendering. `circ_reset`
drops the result buffer, the call arena and the engine arena. Nothing is
thread-safe: all of that state is process-global, so serialise calls.

**Logging.** The library root installs a `std_options.logFn` that discards
everything; a host never sees engine or resolver logs on its stderr.

## Building and linking

```sh
zig build libcirc            # zig-out/lib/libcirc.a + zig-out/include/libcirc.h
zig build libcirc-smoke      # compiles and runs examples/c/analyze.c against it
```

`examples/c/analyze.c` is the smallest complete client: it prints the
version JSON, then the analysis JSON and the preview for the inverter
request shown above, and exits non-zero on any status other than 0. Its
request literal is the one in this document; `tests/libcirc/c_api_test.zig`
parses the same bytes so the two cannot drift.
