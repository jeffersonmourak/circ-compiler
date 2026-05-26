# The `--analyze` API

`circ-compile --analyze` is a structured analysis surface intended for
tooling (editors, language servers). It runs the normal pipeline (scan
imports, cycle check, resolve bodies, validate) and emits the result as
JSON. It is the stable contract the external [`circ-lsp`](https://github.com/jeffersonmourak/circ-lsp)
language server is built on; the compiler never depends on that repo, only
the reverse.

Unlike the five output modes (`--inspect`, `--preview`, `--truth-table`,
`--emit-zig`, default compile), `--analyze` takes its input as a JSON
request on **stdin** rather than a file path, so it can be handed unsaved
editor buffers. Implemented in `lib/analyze/analyze.zig`; mode dispatch is
in `cmd/circ-compile/main.zig`.

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
- `overlays` (optional): map of absolute path to unsaved buffer text. Any path in the overlay is read from memory instead of disk; everything else (including imported files not listed) is read from disk. A never-saved root resolves against its overlay entry even though it does not exist on disk.

## Response (stdout)

```json
{
  "files":       [ { "file_id": 0, "path": "/abs/entry.circ" } ],
  "diagnostics": [ { "file_id": 0, "severity": "error", "code": "E004",
                     "range": {"start_line":3,"start_col":1,"end_line":3,"end_col":6},
                     "message": "required input 'a' is unconnected",
                     "related": [ { "file_id": 0, "range": {…}, "message": "…" } ] } ],
  "symbols":     [ { "file_id": 0, "name": "a", "kind": "input", "width": 1, "range": {…} } ],
  "references":  [ { "file_id": 0, "range": {…}, "target_file": 0, "target_range": {…}, "hover": "input a" } ]
}
```

- **`files`**: `file_id` to absolute path. Paths beginning `<builtin>/` are embedded macro sources with no on-disk file; consumers should skip them when mapping to editor URIs.
- **`diagnostics`**: `severity` is `"error"` or `"warning"`. `code` is a validator code (`E001`-`E016`, `W001`-`W003`, a stable surface) or `"syntax"` for the synthetic truncation diagnostic (see below). `related` carries secondary spans (e.g. the first declaration in a collision).
- **`symbols`**: `kind` is `input`, `output`, `and`, `not`, `led`, or `instance`. One entry per declaration.
- **`references`**: a navigable link from a use site (`range`) to a definition (`target_file` + `target_range`), with a `hover` string. Covers signal references (to the source component's declaration) and import aliases (to the imported file).

### Range

```json
{ "start_line": 3, "start_col": 1, "end_line": 3, "end_col": 6 }
```

All positions are **1-based** line and **byte** column, the compiler's
native span format. Consumers convert as needed (the LSP server maps to
0-based, UTF-16 LSP positions). Spans are reported against
`Module.effectiveSourceFileId()`, so a definition never points at a
synthetic parametric-specialization path.

## Behavior on invalid input

The parser succeeds-with-truncation on malformed source (it stops at the
first unparseable construct rather than failing). `--analyze` detects this
by comparing the parse extent against the file's content length and emits
one `"syntax"` diagnostic at the stall point. Semantic diagnostics derived
from the truncated prefix are still returned but may be misleading;
consumers should prefer their last clean analysis for navigation while a
document is mid-edit. Robust grammar-level recovery is future work (see
the LSP repo's `docs/plan.md`, Stage 7).
