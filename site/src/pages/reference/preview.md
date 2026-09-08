---
layout: ../../layouts/DocsLayout.astro
title: "ASCII Preview"
description: "Render circuits as deterministic ASCII schematics with --preview."
---

`circ-compile <foo.circ> --preview` renders a digital circuit as a styled ASCII schematic to stdout. The output is deterministic — the same `.circ` source produces byte-identical output on every invocation — and includes the wires, gate glyphs, fan-out taps, and jump-arc crossings that make the diagram readable in a terminal.

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
╭───╮     ╭───────╮     ╭─────╮
│ a ├○───▶┤       │ ╭──▶┤ out │
╰───╯     │[xor:g]├○╯   ╰─────╯
       ╭─▶┤       │            
       │  ╰───────╯            
       │                       
╭───╮  │                       
│ b ├○─╯                       
╰───╯                          
```

The `[xor:g]` box represents the entire `xor g(...)` instance as a single labeled subcircuit — the label sits on the row between the two left-side input ports, with the output port on the right. To render the macro's primitive expansion instead, add `--expand-macros`.

## Flags

| Flag | Purpose |
|------|---------|
| `--preview` | Selects preview mode. Mutually exclusive with `--emit-zig` and `--inspect`. `-o` is rejected at parse time. |
| `--expand-macros` | Renders subcircuits as their full primitive expansion instead of as a single labeled box. Only valid with `--preview`. |
| `--expand-display` | Renders an `led[N]` (width > 1) as a row of `N` single-bit LED cells with explicit `b0..bN-1` slice connections, instead of the default opaque multi-bit numeric display box. Only valid with `--preview`. |
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
| `led` | `╭───╮` / `│LED│` / `╰───╯` — input rides on the centre row, no separate port glyph | 5×3 |
| `subcircuit` (opaque) | `╭─...─╮` / `┤     │` / `│[<sub>:<alias>]├○` / `┤     │` / `╰─...─╯` — width grows to fit the label | (label width + 2) × 5 |

Names longer than the cell width are truncated; shorter names pad with spaces. The `○` port-side bubbles aren't part of the box itself — they sit one column outside the `╭╮╰╯` border, so a 5-column box with bubbles looks 6 columns wide on the wire side.

**Wire line art.** Wires are routed as orthogonal segments and drawn with these glyphs:

- `─` horizontal rail, `│` vertical rail.
- `╭` `╮` `╰` `╯` corners between perpendicular segments. The glyph is picked from the two segment directions: `{W,S} → ╮`, `{E,S} → ╭`, `{W,N} → ╯`, `{E,N} → ╰`.
- `┬` `┴` `├` `┤` 3-way junctions. Picked by the same neighbour-inspection pass that handles corners; you'll see these wherever a wire branches into a T off another wire.
- `┼` 4-way crossings — only drawn where two unrelated wires pass over each other (no shared endpoint). The renderer prefers ┼ over the older "jump-arc" trick.
- `●` fan-out / fan-in branch point — drawn where one wire splits into two destinations, or two wires merge into one port.
- `○` port-side bubble — drawn on the cell immediately outside a gate's input or output port (the cell where the wire begins or ends).
- `▶` `◀` `▲` `▼` arrowhead — drawn on the destination end of every wire, just before it enters the target port. Direction matches the segment's last step.
- `+` fallback — appears only on cells that have no connecting neighbours in any direction. It's a *visible warning glyph* meaning the router placed a wire that nothing connects to; if you see one, something is off.

**Layout determinism.** Rendering uses a five-stage pipeline (collapse → columns → rows → place → route), followed by a junction-picker pass that resolves crossings into the right corner/T-glyph. Every decision uses ascending node id as the universal tie-breaker; hash-map iteration is forbidden as an ordering source. The same `.circ` source produces byte-identical output across runs and platforms.

## Multi-bit pins

A component declared with a width annotation (`input[4] a`, `led[4] disp`, `wire[8] bus`) renders with the width appended to its label as `[N]`:

```
╭──────╮     ╭────────────╮
│ a[4] ├○───▶┤ [led:disp] │
╰──────╯     ╰────────────╯
```

A scalar pin omits the suffix, so the label width-marker is the visual cue that distinguishes a 1-bit and an N-bit wire. The wire glyph itself is the same — there is no "bus" glyph.

### LED rendering modes

A multi-bit `led[N]` (width > 1) has three rendering modes:

| Mode | Trigger | Cell content |
|------|---------|--------------|
| **Numeric** | width > 1, all bits `defined` | The unsigned integer value (`0`–`2^N-1`) inside the box. |
| **Numeric + warning** | width > 1, some bits `defined`, others `undefined` | The integer value formed from the defined bits, with a warning marker (`?`) showing partial state. |
| **Indicator** | width = 1 | The single-bit LED glyph: lit on `high`, dim on `low`, `?` on `undefined`. |

With `--expand-display`, the multi-bit form decomposes into `N` scalar LEDs wired to explicit bit-index slices of the input signal, which is the right view when you need to debug per-bit drive state.

## Macro modes

Built-in macros (`or`, `nand`, `nor`, `xor`, `xnor`) and user-imported subcircuits expand into primitive gates during compilation. The renderer can display them two ways:

- **Opaque (default).** All primitives that came from one subcircuit instance collapse into a single labeled box `[<sub>:<alias>]`. Connections to/from the subcircuit's published ports flow into the box's edges.
- **Expanded (`--expand-macros`).** Every primitive appears individually, with its origin chain visible in the topology metadata. Useful for understanding what a macro actually does or for debugging unexpected behaviour from a builtin.

## Where the data comes from

The renderer reads from a versioned topology payload embedded in compiled `.wasm` artifacts as WASM custom sections:

| Section | Contains |
|---------|----------|
| `circ.topology.v0.min` | Flat primitive components (id, kind, `width: u8`) + connections. Magic `CIRC`, version `0x03`. The "lightweight" payload — what the runtime needs. |
| `circ.topology.v0.full` | Adds per-component instance names + subcircuit-origin chains. Magic `CIRF`, version `0x03`. The "rich" payload — what the renderer (and any future inspection tooling) needs. |

`--preview` builds the `full` payload in memory (skipping the `.wasm` write) and feeds it directly into the renderer. Tools that consume a `.wasm` artifact from disk can parse the same payload via `lib/topology/full_decoder.zig:decode`.

The `min` and `full` sections are independent variants on a single version axis — they coexist in every produced artifact. Pre-1.0, the schemas are freely revvable: bump `vN.{min,full}` rather than carrying compatibility shims. See `lib/topology/full_format.zig` for the wire format.

## Known limitations

- The `--color` flag has no effect outside `--preview` mode (no other mode renders to a terminal). It's accepted in any mode but harmlessly stored.
- The compile/emit-zig modes use a `has_imports` gate that can miss builtin-macro single-file fixtures (only preview was widened to handle them — see `cmd/circ-compile/main.zig`'s `needs_project_resolution` logic).
- A `+` glyph in the rendered output indicates a routed cell with no connecting neighbours — a router bug rather than a stylistic fallback. If one appears, the relevant fixture is worth checking against the goldens under `tests/fixtures/preview/renders/`.
