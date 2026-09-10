# Importing memories from Logisim

Circuits drawn in Logisim (or Logisim-evolution) that use the `ROM` and `RAM`
components can now be expressed in `.circ` with the native `rom`/`ram`
memories; until topology v03, no primitive existed to map them to. This note
records the mapping so a hand translation is mechanical. No automatic importer
exists; you write the `.circ` file by hand, and the memory *contents* come
through the runtime-loading doors described in [`language.md`](language.md)
§6.5.

## Component mapping

| Logisim                       | circ                                   | Notes |
| ----------------------------- | -------------------------------------- | ----- |
| `ROM` (Data Bits `W`, Address Bits `A`) | `rom name[W, A](addr = …)`   | `A` is 1..16 in circ; Logisim allows up to 24. |
| `RAM` (Data Bits `W`, Address Bits `A`) | `ram name[W, A](addr = …, din = …, we = …, clk = …)` | Single-port, separate data in/out (Logisim's *Data Interface: Separate load and store ports*). |

## Port mapping

| Logisim pin | circ port | Width | Notes |
| ----------- | --------- | ----- | ----- |
| `A` (address)         | `addr` | `A` | any undefined address bit makes `out` undefined |
| `D` (data out)        | `out`  | `W` | asynchronous read in both tools |
| `D` / `Din` (data in) | `din`  | `W` | RAM only |
| `str` / `WE`          | `we`   | 1   | RAM only; write happens only while high |
| `clk`                 | `clk`  | 1   | RAM only; rising-edge write (Logisim's default *Trigger: Rising Edge*) |
| `sel`, `clr`, `ld`, `M`, output enable | — | — | not modelled: circ memories are always selected, never cleared by a pin, and `out` is never tri-stated |

A `ram` in circ is therefore the Logisim RAM with *Trigger = Rising Edge* and
*Data Interface = Separate load and store ports*; the bidirectional-bus and
falling-edge variants need glue logic (or a rewrite) before they map.
Logisim's asynchronous-read behaviour matches circ's exactly; a Logisim RAM
configured for synchronous read has no counterpart.

## Contents

Logisim stores ROM/RAM contents in its `v2.0 raw` hex image format (a text
header line followed by whitespace-separated hex words with optional
`N*value` run-length groups). circ memories take a headerless raw
little-endian binary image — `ceil(W/8)` bytes per word, at most `2^A` words,
padding bits zero ([`wasm-api.md`](wasm-api.md) "Image format"). A converter
from `v2.0 raw` to that format is a small stand-alone script (parse the words,
expand the runs, emit each as `ceil(W/8)` little-endian bytes), and this
repository deliberately omits it. After conversion, you load the image with
`--mem=<name>=<path>`, `--sim`'s `load`, or the artifact's `memLoad` export,
exactly as you would any other image.

Logisim images carry no definedness either, so a converted image marks every
loaded word fully defined; words past the end of the image read undefined,
as they do in circ for any short image.
