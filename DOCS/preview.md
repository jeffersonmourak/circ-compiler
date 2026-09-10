# Preview: ASCII circuit schematics

`circ-compile <foo.circ> --preview` renders a digital circuit as a styled ASCII schematic to stdout. The output is deterministic — the same `.circ` source produces byte-identical output on every invocation — and includes the wires, gate glyphs, fan-out taps, and `┼` crossings that make the diagram readable in a terminal.

## Quick start

```sh
zig-out/bin/circ-compile tests/fixtures/circuits/single_gate.circ --preview
```

Expected output:

```
╭───╮     ╭───╮     ╭─────╮
│ a ├○───▶┤NOT├○───▶┤ out │
╰───╯     ╰───╯     ╰─────╯
```

Every node is a labeled box — input pin `a`, the `NOT` gate, output pin `out`. The `○` glyph immediately outside each port is a bubble showing where a wire enters or leaves the cell; the `▶` arrowhead marks the destination end of each wire.

For a circuit using a builtin macro (xor in this case):

```sh
zig-out/bin/circ-compile tests/fixtures/circuits/builtin_xor.circ --preview
```

```
╭───╮     ╭───────╮            
│ a ├○───▶┤       │     ╭─────╮
╰───╯     │[xor:g]├○───▶┤ out │
      ╭──▶┤       │     ╰─────╯
╭───╮ │   ╰───────╯            
│ b ├○╯                        
╰───╯                          
```

The `[xor:g]` box represents the entire `xor g(...)` instance as a single labeled subcircuit — the label sits on the row between the two left-side input ports, with the output port on the right. To render the macro's primitive expansion instead, add `--expand-macros`.

## Flags

| Flag | Purpose |
|------|---------|
| `--preview` | Selects preview mode. Mutually exclusive with `--emit-zig`, `--inspect`, `--truth-table` and `--sim`. `-o` is rejected at parse time. |
| `--expand-macros` | Renders subcircuits as their full primitive expansion instead of as a single labeled box. Only valid with `--preview`. |
| `--expand-display` | Renders a multi-bit `led[N]` (widths 2..7) as a row of `·` indicator glyphs inside its box, LSB on the left, instead of the `0x?` hex display; a width of 8 or more falls back to the hex display and warns on stderr. Only valid with `--preview`. |
| `--color=auto\|always\|never` | Enables ANSI color (per-kind: input pins green, gates cyan, LEDs yellow, macros magenta, wires dim). Defaults to `auto` (color when stdout is a TTY *and* `NO_COLOR` is unset). `always` overrides `NO_COLOR` per the convention used by `git`/`ls`/`grep`. |

The render path is fully in-memory: parse → resolve → translate → topology build → layout → render → stdout. No `.wasm` is written, no temp directory, no subprocess.

## Rendering conventions

**Per-kind glyphs.** Every node renders as a bordered box. The box body always uses `╭───╮` / `╰───╯` for the corners, with the kind-specific label and ports on the rows in between:

| Kind | Cell shape | Cell size |
|------|------------|-----------|
| `input_pin` | `╭───╮` / `│ <n> ├○` / `╰───╯` — name centered, output bubble on right edge | 5×3 (wider for long names) |
| `output_pin` | `╭───╮` / `┤ <n> │` / `╰───╯` — input port `┤` on left edge | 5×3 (wider for long names) |
| `not_gate` | `╭───╮` / `┤NOT├○` / `╰───╯` — input `┤` left, output `├○` right | 5×3 |
| `and_gate` | `╭───╮` / `┤   │` / `│AND├○` / `┤   │` / `╰───╯` — two stacked input ports flanking the label row | 5×5 |
| `led` | `╭───╮` / `┤LED│` / `╰───╯` — input port `┤` on the left edge like every sink; a multi-bit LED shows `0x?` (one `?` per nibble) or, with `--expand-display`, one `·` per bit | 5×3 (wider for the multi-bit labels) |
| `subcircuit` (opaque) | `╭─...─╮` / `┤     │` / `│[<sub>:<alias>]├○` / `┤     │` / `╰─...─╯` — width grows to fit the label, one input port per odd border row | max(8, label width + 2) × (2·inputs + 1, at least 3) |
| `rom` | `╭─...─╮` / `┤ rom <name>[W,A] ├○` / `╰─...─╯` — one input port `addr` | (label width + 4) × 3 |
| `ram` | same label as `rom`; input ports `addr`, `din`, `we`, `clk` on rows 1, 3, 5, 7 | (label width + 4) × 9 |

Names longer than the cell width are truncated; shorter names pad with spaces. The `○` port-side bubbles aren't part of the box itself — they sit one column outside the `╭╮╰╯` border, so a 5-column box with bubbles looks 6 columns wide on the wire side.

**Wire line art.** Wires are routed as orthogonal segments and drawn with these glyphs:

- `─` horizontal rail, `│` vertical rail.
- `╭` `╮` `╰` `╯` corners between perpendicular segments. The glyph is picked from the two segment directions: `{W,S} → ╮`, `{E,S} → ╭`, `{W,N} → ╯`, `{E,N} → ╰`.
- `┬` `┴` `├` `┤` 3-way junctions. Picked by the same neighbour-inspection pass that handles corners. Under the channel router every fan-out branches at a `●` tap, so no current golden contains one; the glyphs remain for a wire that branches into a T off another.
- `┼` 4-way crossings — drawn on any cell where two wires cross and neither *diverges* there: two wires that share a source or a destination but merely pass over each other still get `┼`. The renderer prefers ┼ over the older "jump-arc" trick.
- `●` fan-out / fan-in branch point — drawn where two wires of one net diverge (one corners at the cell while the other passes straight through), and on any source cell from which three or more wires leave.
- `○` port-side bubble — drawn only on the cell immediately outside a component's *output* port (the cell where the wire begins); the destination end always carries an arrowhead.
- `▶` `◀` `▲` `▼` arrowhead — drawn on the destination end of every wire, just before it enters the target port. Direction matches the segment's last step.
- `+` fallback — appears only on cells that have no connecting neighbours in any direction. It's a *visible warning glyph* meaning the router placed a wire that nothing connects to; if you see one, something is off.

**Layout determinism.** Rendering uses a five-stage layout pipeline (collapse → layering → ordering → coords → channels, described below), followed by a junction-picker pass that resolves crossings into the right corner/T-glyph. Every decision uses ascending node id as the universal tie-breaker; hash-map iteration is forbidden as an ordering source. The same `.circ` source produces byte-identical output across runs and platforms.

## Multi-bit pins

A pin declared with a width annotation (`input[4] a`, `wire[8] bus`) renders with the width appended to its label as `[N]`; a multi-bit LED shows a hex placeholder instead (`led_4bit_default.circ`):

```
╭──────╮     ╭─────╮
│ a[4] ├○───▶┤ 0x? │
╰──────╯     ╰─────╯
```

A scalar pin omits the suffix, so the label width-marker is the visual cue that distinguishes a 1-bit and an N-bit wire. The wire glyph itself is the same — there is no "bus" glyph.

### LED labels

The preview is static, so it never knows a signal's value; an LED's label depends only on its width and the flags:

| Label | When |
|-------|------|
| `LED` | width 1 |
| `0x?…?` (one `?` per nibble) | width > 1 (default) |
| `····` (one `·` per bit, LSB left) | width 2..7 with `--expand-display`; width 8 or more keeps the hex form and warns once on stderr |

## Macro modes

Built-in macros (`or`, `nand`, `nor`, `xor`, `xnor`) and user-imported subcircuits expand into primitive gates during compilation. The renderer can display them two ways:

- **Opaque (default).** All primitives that came from one subcircuit instance collapse into a single labeled box `[<sub>:<alias>]`. Connections to/from the subcircuit's published ports flow into the box's edges.
- **Expanded (`--expand-macros`).** Every primitive appears individually, with its origin chain visible in the topology metadata. Useful for understanding what a macro actually does or for debugging unexpected behaviour from a builtin.

## Where the data comes from

The renderer reads from a versioned topology payload embedded in compiled `.wasm` artifacts as WASM custom sections:

| Section | Contains |
|---------|----------|
| `circ.topology.v0.min` | Flat primitive components (id, kind, `width: u8`, plus kind-dispatched aux bytes: `slice` carries `lo`/`hi`, `rom`/`ram` the address width) + connections. Magic `CIRC`, version `0x03`. The "lightweight" payload — what the runtime needs. |
| `circ.topology.v0.full` | Adds per-component instance names + subcircuit-origin chains. Magic `CIRF`, version `0x03`. The "rich" payload — what the renderer (and any future inspection tooling) needs. |

`--preview` builds the `full` payload in memory (skipping the `.wasm` write) and feeds it directly into the layout. Tools that consume a `.wasm` artifact from disk can parse the same payload via `lib/topology/full_decoder.zig:decode`.

The `min` and `full` sections are independent variants on a single version axis — they coexist in every produced artifact. Pre-1.0, the schemas are freely revvable: bump `vN.{min,full}` rather than carrying compatibility shims. See `lib/topology/full_format.zig` for the wire format.

## How the layout is computed

`lib/preview/layout/` turns the `full` topology into a `LayoutGrid` (boxes with port cells, wires as axis-aligned segments) that `lib/preview/render.zig` paints. It is a layered-graph layout in the Sugiyama tradition, with channel routing:

1. **Collapse** (`collapse.zig`). Wires, slices and concats fold away; in opaque mode every primitive that came from one subcircuit instance becomes one box with a synthetic id.
2. **Layering** (`layering.zig`). Longest-path layers: input pins in layer 0, every other node one past its furthest upstream, `led`/`output` pins forced to the last layer. Edges that close a cycle (a DFS back edge) and edges that sink-forcing turns leftward are flagged as *back edges*. A forward edge spanning several layers is split through one dummy node per intermediate layer, so every later stage sees only layer-adjacent segments.
3. **Ordering** (`ordering.zig`). Inside each layer, barycenter sweeps down and up over the neighbours' *port* positions (an `and`'s `a` sits above its `b`), kept while they lower the crossing count, then adjacent swaps to a fixed point. Integer arithmetic throughout; ties fall back to ascending id.
4. **Coordinates** (`coords.zig`). Every node gets its own row: the top that makes the wire into its highest input port a straight horizontal, packed in the ordering with one free row between boxes; dummies are wire rows on their source's port row. A node with one outgoing wire may move down to straighten it. Columns are each layer's widest box plus the gap the router asks for.
5. **Channels** (`channels.zig`). Each inter-layer gap is routed as a channel: a *net* is one source port and its sinks in the next layer; a net whose terminals share a row is a straight horizontal; every other net gets a vertical *track* in the gap, assigned by the left-edge rule under a constraint graph (a source rail and a sink rail on one row order their tracks so no rail reaches another net's corner). Constraint cycles are broken with a dogleg on a free row, or a spacer row when none is free; back edges leave down a track to a *return row* below the diagram, run along it, and rise to their sink; a gap is `tracks + 2` cells wide (never under five). A net no track can hold falls back to a bounded cell search — counted, never silent.

Every stage is deterministic: the same topology produces byte-identical output, and `tests/preview/layout_conformance_test.zig` pins the grid of every previewable fixture as JSON under `tests/fixtures/preview/layouts-json/` plus one table of invariants (`tests/fixtures/preview/layout-invariants.golden`): no wire cell inside a box, no cell shared by two nets running the same way, no junction between nets that is not a clean `┼` crossing, every net a tree — asserted over the whole corpus, with the crossings, bends and size of each fixture on record. The renderer at `circ-renderer/src/layout/` ports the same stages so the canvas and the ASCII preview agree.

## Known limitations

- The `--color` flag has no effect outside `--preview` mode (no other mode renders to a terminal). It's accepted in any mode but harmlessly stored.
- **A macro input port the topology cannot name is drawn as one port.** The collapse stage maps every subcircuit input whose name is not `a`, `in` or `b` onto `in`, so a parametric macro with inputs such as `data` and `select` receives two wires on one port cell; the two rails necessarily share that cell (a `●` merge in the picture). The six such fixtures are the only rows of `layout-invariants.golden` with a non-zero I1/I2, exempted by name of the cause, not of the fixture.
- Dense circuits get taller and wider than they did under the fixed-gutter layout: every wire now owns its cells, a gap is as wide as its track count, and a return lane adds a row per back edge (`stress_grid_10x10` is 47×599 cells). There is no wrapping or height cap.
- A `+` glyph in the rendered output indicates a routed cell with no connecting neighbours — a router bug rather than a stylistic fallback. If one appears, the relevant fixture is worth checking against the goldens under `tests/fixtures/preview/renders/`.
