# The `--analyze` API

`circ-compile --analyze` is a structured analysis surface intended for
tooling (editors, language servers). It runs the normal pipeline (scan
imports, cycle check, resolve bodies, validate) and emits the result as
JSON. It is the stable contract the external [`circ-lsp`](https://github.com/jeffersonmourak/circ-lsp)
language server is built on; the compiler never depends on that repo, only
the reverse.

Unlike the six file-path modes (`--inspect`, `--preview`, `--truth-table`,
`--sim`, `--emit-zig`, default compile), `--analyze` takes its input as a JSON
request on **stdin** rather than a file path, so a caller can hand it
unsaved editor buffers. Implemented in `lib/analyze/analyze.zig`; mode
dispatch is in `cmd/circ-compile/main.zig`.

## Invocation

```sh
echo '<request>' | circ-compile --analyze    # JSON response on stdout
```

Exit code `0` with JSON on stdout on success; non-zero with a human
message on stderr for a malformed request or an internal failure.

## Request (stdin)

```json
{
  "root_path": "/abs/path/to/entry.circ",
  "overlays": {
    "/abs/path/to/entry.circ": "input a\n...",
    "/abs/path/to/dep.circ":   "..."
  }
}
```

- `root_path` (required): absolute path of the file to analyze as the project root.
- `overlays` (optional): map of absolute path to unsaved buffer text. Keys must already be normalised the way the loader looks them up (POSIX-style, `.`/`..` folded): the library's `files` map normalises its keys, but `circ-compile --analyze` inserts request keys verbatim, so an un-normalised key silently misses. The loader consults the overlay *before* disk: it reads a path in the overlay from memory, and an import whose joined path is an overlay key resolves to that key without touching the filesystem. A root plus overlay-only siblings therefore analyzes with no disk access. Anything missing from the overlay, including imported files the request omits, comes from disk. `files[].path` for an overlay-keyed file is the key as given, not its realpath; a never-saved root resolves against its overlay entry even though it does not exist on disk.

## Response (stdout)

```json
{
  "files":       [ { "file_id": 0, "path": "/abs/entry.circ" } ],
  "diagnostics": [ { "file_id": 0, "severity": "error", "code": "E004",
                     "range": {"start_line":3,"start_col":1,"end_line":3,"end_col":6},
                     "message": "required input 'a' is unconnected",
                     "related": [ { "file_id": 0, "range": {…}, "message": "…" } ] } ],
  "symbols":     [ { "file_id": 0, "name": "a", "kind": "input", "width": 1, "range": {…} },
                   { "file_id": 0, "name": "code", "kind": "rom", "width": 8, "addr_width": 4, "range": {…} } ],
  "references":  [ { "file_id": 0, "range": {…}, "target_file": 0, "target_range": {…}, "hover": "input a" } ]
}
```

- **`files`**: `file_id` to absolute path. Paths beginning `<builtin>/` are embedded macro sources with no on-disk file; consumers should skip them when mapping to editor URIs.
- **`diagnostics`**: `severity` is `"error"` or `"warning"`. `code` is a validator code (`E001`-`E018`, `W001`-`W003`, a stable surface) or `"syntax"` for the synthetic truncation diagnostic (see below). `related` carries secondary spans (e.g. the first declaration in a collision).
- **`symbols`**: `kind` is `input`, `output`, `and`, `not`, `led`, `rom`, `ram`, or `instance`. One entry per declaration. `addr_width` is present only on `rom`/`ram` symbols, where `width` is the data width `W` and `addr_width` the address width `A` of the `[W, A]` declaration; consumers must tolerate its absence on every other kind.
- **`references`**: a navigable link from a use site (`range`) to a definition (`target_file` + `target_range`), with a `hover` string. Covers signal references (to the source component's declaration) and import aliases (to the imported file).

### Range

```json
{ "start_line": 3, "start_col": 1, "end_line": 3, "end_col": 6 }
```

All positions are **1-based** line and **byte** column, the compiler's
native span format. Consumers convert as needed (the LSP server maps to
0-based, UTF-16 LSP positions). `--analyze` reports spans against
`Module.effectiveSourceFileId()`, so a definition never points at a
synthetic parametric-specialization path.

## Behavior on invalid input

The grammar recovers at the declaration level: the parser skips a
malformed declaration and resynchronises at the next line, and every valid
declaration around it still resolves. `--analyze` emits one `"syntax"`
diagnostic per recovered error mark: the message names what was expected
(`expected ')' to close the connection list`, `unexpected input; expected a
declaration`, …). The range is the mark's span, widened to one column
when the parser stalled without consuming anything (so a bus truncated
after `a=` at the end of a line reports the start of the *next* line). The
`tests/fixtures/circuits/recovery_*.circ` goldens and
`tests/fixtures/expected-analyze/*.json` pin the exact marks for a set of
malformed inputs.

Only a source the parser cannot start on at all (an empty or
whitespace-only buffer, or a hard parse failure) yields no symbols: a blank
source returns an empty analysis with no diagnostics, and a hard failure
returns one located `"syntax"` diagnostic and no builtin files.
