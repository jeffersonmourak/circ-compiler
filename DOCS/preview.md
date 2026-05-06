# Preview: ASCII circuit schematics

`circ-compile <foo.circ> --preview` renders a digital circuit as a styled ASCII schematic to stdout. The output is deterministic — the same `.circ` source produces byte-identical output on every invocation — and includes the wires, gate glyphs, fan-out taps, and jump-arc crossings that make the diagram readable in a terminal.

## Quick start

```sh
zig-out/bin/circ-compile tests/fixtures/circuits/single_gate.circ --preview
```

Expected output:

```
a─────╮        ╭──────out
      ╰────▷○──╯         

```

For a circuit using a builtin macro (xor in this case):

```sh
zig-out/bin/circ-compile tests/fixtures/circuits/builtin_xor.circ --preview
```

```
a─────╮   ╭───────╮╭──────out
      ╯│╰──[xor:g]─╯         
       │  ╰───────╯          
       │                     
b──────╯
```

The `[xor:g]` box represents the entire `xor g(...)` instance as a single labeled subcircuit. The two ‘╯/╰’ glyphs flanking the vertical wire below are jump-arcs — the horizontal rail "jumps over" the vertical one at a crossing.

## Flags

| Flag | Purpose |
|------|---------|
| `--preview` | Selects preview mode. Mutually exclusive with `--emit-zig` and `--inspect`. `-o` is rejected at parse time. |
| `--expand-macros` | Renders subcircuits as their full primitive expansion instead of as a single labeled box. Only valid with `--preview`. |
| `--color=auto\|always\|never` | Enables ANSI color (per-kind: input pins green, gates cyan, LEDs yellow, macros magenta, wires dim). Defaults to `auto` (color when stdout is a TTY *and* `NO_COLOR` is unset). `always` overrides `NO_COLOR` per the convention used by `git`/`ls`/`grep`. |

The render path is fully in-memory: parse → resolve → translate → topology build → layout → render → stdout. No `.wasm` is written, no temp directory, no subprocess.

## Rendering conventions

**Per-kind glyphs.** Each gate kind gets a fixed cell shape:

| Kind | Glyph | Cell size |
|------|-------|-----------|
| `input_pin` | `name──` (left-aligned name + rail) | 6×1 |
| `output_pin` | `──name` (rail + right-aligned name) | 6×1 |
| `not_gate` | `─▷○──` (triangle + bubble) | 5×3 |
| `and_gate` | `─╮ │─── ─╯` (D-shape silhouette) | 5×3 |
| `led` | `─◉` (rail + fisheye) | 3×3 |
| `subcircuit` (opaque mode) | `╭─...─╮ │ [<sub>:<alias>] │ ╰─...─╯` | (label + 2) × 3, min width 8 |

Names longer than the cell width are truncated; shorter names pad with `─` rails.

**Wire line art.** Wires use:

- `─` for horizontal rails, `│` for vertical rails.
- `╭` `╮` `╰` `╯` for corners between perpendicular segments. The corner glyph is selected from the two segment directions: `{W,S} → ╮`, `{E,S} → ╭`, `{W,N} → ╯`, `{E,N} → ╰`.
- `●` at fan-out points where ≥3 wires share a source cell.
- Jump-arcs at every crossing: where a horizontal wire meets a vertical wire's column, the horizontal "jumps" — the cell *before* the crossing becomes `╯`, the crossing cell renders the vertical wire's `│` continuously, and the cell *after* becomes `╰`. Reads visually as `─╯│╰─` left-to-right.

**Layout determinism.** Rendering uses a five-stage pipeline (collapse → columns → rows → place → route). Every decision uses ascending node id as the universal tie-breaker; hash-map iteration is forbidden as an ordering source. The same `.circ` source produces byte-identical output across runs and platforms.

## Macro modes

Built-in macros (`or`, `nand`, `nor`, `xor`, `xnor`) and user-imported subcircuits expand into primitive gates during compilation. The renderer can display them two ways:

- **Opaque (default).** All primitives that came from one subcircuit instance collapse into a single labeled box `[<sub>:<alias>]`. Connections to/from the subcircuit's published ports flow into the box's edges.
- **Expanded (`--expand-macros`).** Every primitive appears individually, with its origin chain visible in the topology metadata. Useful for understanding what a macro actually does or for debugging unexpected behaviour from a builtin.

## Where the data comes from

The renderer reads from a versioned topology payload embedded in compiled `.wasm` artifacts as WASM custom sections:

| Section | Contains |
|---------|----------|
| `circ.topology.v0.min` | Flat primitive components (id, kind) + connections. Magic `CIRC`, version `0x01`. The "lightweight" payload — what the runtime needs. |
| `circ.topology.v0.full` | Adds per-component instance names + subcircuit-origin chains. Magic `CIRF`, version `0x01`. The "rich" payload — what the renderer (and any future inspection tooling) needs. |

`--preview` builds the `full` payload in memory (skipping the `.wasm` write) and feeds it directly into the renderer. Tools that consume a `.wasm` artifact from disk can parse the same payload via `lib/topology/full_decoder.zig:decode`.

The `min` and `full` sections are independent variants on a single version axis — they coexist in every produced artifact. Pre-1.0, the schemas are freely revvable: bump `vN.{min,full}` rather than carrying compatibility shims. See `lib/topology/full_format.zig` for the wire format.

## Known limitations

- At a 3-way junction where the corner glyph picker's 2-direction connection model can't pick between `┤`/`┬`/`┴`/`├`, the renderer falls back to a `+` glyph. Visible in `tests/fixtures/circuits/fan_in.render.golden`. A future improvement will detect the per-cell direction set across all wires and pick the right T-glyph.
- The `--color` flag has no effect outside `--preview` mode (no other mode renders to a terminal). It's accepted in any mode but harmlessly stored.
- The compile/emit-zig modes use a `has_imports` gate that can miss builtin-macro single-file fixtures (only preview was widened to handle them — see `cmd/circ-compile/main.zig`'s `needs_project_resolution` logic).
