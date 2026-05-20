# Engine Benchmark

A regression gate for `lib/circuit.zig` driven by the truth-table fixture corpus. Runs via `zig build bench`; the result is compared against a golden file at `tests/fixtures/bench/engine.bench.golden`.

The benchmark exists to answer one question: *does the simulation engine still do the same amount of work it used to, on the same circuits?* It is not a wall-clock benchmark — wall-clock is reported but never asserted, because it varies with the host. The asserted numbers are deterministic counters that depend only on the algorithm.

## What it runs

The bench walks 53 fixtures from the truth-table corpus. Coverage spans the full size range:

| Tier                     | Fixtures (examples)                                                | Vectors per circuit |
| ------------------------ | ------------------------------------------------------------------ | ------------------- |
| Single primitive         | `primitive_not`, `primitive_wire`, `primitive_led`                 | 2                   |
| Single gate              | `primitive_and`, `and_two_inputs`                                  | 4                   |
| Builtin macros           | `builtin_xor`, `builtin_nand`, `builtin_xnor`                      | 4                   |
| 2 – 6-bit fan-outs       | `and_2bit` … `and_6bit`, `or_3bit`, `xor_4bit`, `xor_5bit`         | 16 – 4096           |
| Combinational structures | `mux_2to1` … `mux_5bit_2to1`, `demux_1to2` … `demux_4bit_1to2`     | 4 – 2048            |
| Adders                   | `half_adder`, `full_adder`, `two/three/four/five/six/eight_bit_adder` | 4 – 65536        |
| ALU                      | `alu_4bit` (14 inputs)                                             | 16384               |

Total: 98,400 input vectors driven through the engine in a single bench run; ~9.5M events popped, ~210k allocator calls totaling ~28 MB. The 5/6-bit family extensions added earlier characterize pop-efficiency scaling; the wider adders (`five_bit_adder`, `six_bit_adder`, `eight_bit_adder`) characterize cascading-carry depth — with the 8-bit adder pushing 65k vectors and 4.8M events, it overtakes `alu_4bit` as the heaviest fixture by both vector count and event volume.

The fixture-to-circuit mapping is hand-maintained at `tools/bench/main.zig:36`. Most fixtures are 1:1 with their `.circ` source; a handful (`full_adder` → `full_adder_from_builtins.circ`, `primitive_and` → `and_gate.circ`, etc.) follow the same historical aliases used by the truth-table golden tests.

## How it runs

For each fixture, the bench replays exactly the same pipeline that `circ-compile --truth-table` uses, then drives the engine over every input vector:

```
.circ source
    │
    ▼
translate.parseSource        ─→ AST
    │
    ▼
scan_imports → import_cycle  ─→ topo-ordered file list
    │
    ▼
resolve_bodies                ─→ ir.Project (modules + builtins)
    │
    ▼
validator_run_project        ─→ diagnostics (fail bench on errors)
    │
    ▼
full_serializer.buildFromProject ─→ FullTopology (components + connections)
    │
    ▼
truth_table_builder.build    ─→ constructs engine.Circuit, drives all 2^N vectors,
                                snapshots circuit.metrics into Table.metrics
    │
    ▼
read table.metrics, table.rows.len, topology.components.len
```

The bench reads the *cumulative* `Circuit.metrics` once per fixture, after every input vector has been simulated. Metrics never reset between vectors — they accumulate over the circuit's whole lifetime — so a single read at the end gives the totals.

Wall-clock is sampled in two nested windows. The outer one wraps `runFixture` (parse → resolve → validate → topology build → drive all vectors) and gives the total. The inner one, plumbed through `Table.drive_ns` from `lib/truth_table/builder.zig`, brackets only the `2^N` input-vector replay — so engine throughput can be separated from the one-shot pipeline overhead that dominates tiny fixtures. Neither timing is written to the golden:

```
bench: alu_4bit                  16384 vecs   2235.547 ms (drv 2203.712)   134503.9 ns/vec   531.4 ns/event   95.2% pop   306.1 t/vec
```

Reading left to right: total wall-clock, drive-only wall-clock in parens (the `drv` value), then engine-only throughput. The `ns/vec` and `ns/event` numbers are computed from drive time, not total — so a tiny fixture's per-vector cost reflects its actual engine pace rather than ~1 ms of unavoidable parser overhead. The last two columns are derived counters; see [Derived stderr columns](#derived-stderr-columns) below.

Pass `--human` (after a `--` separator, since Zig's build driver consumes its own args first) to switch the output to a humanized form: counts get k/M suffixes plus the raw value in parens, throughput flips to `items/<time>` (so the engine's pace reads as "vectors per unit of wall-clock" instead of "wall-clock per vector"), and every column uses **one fixed time unit** so values line up vertically and are easy to scan.

You pick the unit:

| Invocation             | Time / throughput unit             | When to use                                                          |
| ---------------------- | ---------------------------------- | -------------------------------------------------------------------- |
| `--human` (no arg)     | `ns` (default)                     | Mirrors the existing `ns/vec` / `ns/event` precision but inverted    |
| `--human ms`           | `ms`                               | Best general-purpose; fixtures land in the 7 – 350 vec/ms range      |
| `--human s`            | `s`                                | High-level summary; throughput shows in k/s or M/s                   |

```sh
zig build bench -- --human ms
```

```
[bench] alu_4bit          16.38k vecs    1793.852 ms (drv   1769.494 ms)      9.26 vec/ms     2.34k events/ms   34.73k allocs     4.62M bytes   95.2% pop  306.1 t/vec
[bench] and_4bit             256 vecs       2.434 ms (drv      0.924 ms)    277.06 vec/ms     2.74k events/ms      576 allocs    78.78k bytes   39.2% pop   45.6 t/vec
[bench] chain                  2 vecs       1.046 ms (drv      0.005 ms)    400.00 vec/ms     2.00k events/ms       26 allocs     5.29k bytes  100.0% pop   21.0 t/vec
[bench] four_bit_adder       256 vecs      10.395 ms (drv      5.874 ms)     43.58 vec/ms     2.50k events/ms    1.27k allocs   228.46k bytes   89.5% pop  141.6 t/vec
[bench] nand_4bit            256 vecs       3.216 ms (drv      1.476 ms)    173.44 vec/ms     2.38k events/ms      653 allocs    95.62k bytes   56.3% pop   60.3 t/vec
[bench] ---  53 fixtures   98.40k vectors (98400)   9.52M events (9515490)   210.08k allocs (210078)   28.04M bytes (28043712)   3921.909 ms total (3787.580 ms drv, 96.6% engine)
```

The per-fixture rows drop the `(raw)` parenthetical that the totals line carries — on aggregate counts the exact value is useful, on individual rows it just bloats every column. The totals keep it.

Same data with `--human s`:

```
[bench] alu_4bit          16.38k vecs        1.741 s (drv       1.716 s)      9.55k vec/s      2.42M events/s   34.73k allocs     4.62M bytes   95.2% pop  306.1 t/vec
[bench] chain                  2 vecs       0.0011 s (drv      0.0000 s)    400.00k vec/s      2.00M events/s       26 allocs     5.29k bytes  100.0% pop   21.0 t/vec
[bench] ---  53 fixtures   98.40k vectors (98400)   9.52M events (9515490)   210.08k allocs (210078)   28.04M bytes (28043712)   3.949 s total (3.814 s drv, 96.6% engine)
```

And `--human` (default, ns) keeps full precision at the cost of wide numbers and scientific notation for the throughput:

```
[bench] alu_4bit          16.38k vecs  1736209000 ns (drv 1711517000 ns)   9.57e-6 vec/ns   2.42e-3 events/ns   34.73k allocs     4.62M bytes   95.2% pop  306.1 t/vec
[bench] ---  53 fixtures   98.40k vectors (98400)   9.52M events (9515490)   210.08k allocs (210078)   28.04M bytes (28043712)   3894131000 ns total (3759333000 ns drv, 96.5% engine)
```

Throughput k/M scaling kicks in inside the chosen unit — `1.81M events/s` and `1.31k events/ms` are the same engine; only the denomination is different. The flag only affects the stderr report; the golden comparison and the golden file itself are untouched.

Throughput in every mode is computed from `drive_ns` (the inner replay loop only), not from total wall-clock. This matters for small fixtures: `chain` reads as `333 vec/ms` because its 2 vectors take ~6 μs in the engine, even though the surrounding parser+validator+topology pipeline pushes total wall-clock to 1.4 ms. Reading total-based vec/ms would suggest the engine handles `1.4 vec/ms`, which is wrong; the engine is doing ~250× that and the rest is one-shot overhead.

### Sorting the report

Add `--sort <column>` to reorder the stderr rows. Sort is **descending** so the heaviest fixtures land at the top, which is usually what you want when scanning for regressions or hotspots. The golden file is always written in alphabetical order regardless — sort only affects the on-screen report so diffs stay stable.

| Column   | Sorts by                                                                |
| -------- | ----------------------------------------------------------------------- |
| `inputs` | Vector count per fixture (`2^N` for N input pins)                       |
| `comps`  | Component count in the topology (after macro expansion)                 |
| `events` | `events_popped` — total heap throughput                                 |
| `time`   | Wall-clock elapsed per fixture                                          |

`--sort` works with or without `--human`. Combine them freely:

```sh
zig build bench -- --human ms --sort time     # heaviest fixtures first, in ms
zig build bench -- --sort events              # default formatting, sorted by event count
```

Example output (`--human ms --sort time`, top 6):

```
[bench] eight_bit_adder   65.54k vecs    1870.383 ms (drv   1856.763 ms)     35.30 vec/ms     2.60k events/ms  132.70k allocs    17.13M bytes   81.0% pop  195.2 t/vec
[bench] alu_4bit          16.38k vecs    1736.092 ms (drv   1711.533 ms)      9.57 vec/ms     2.42k events/ms   34.73k allocs     4.62M bytes   95.2% pop  306.1 t/vec
[bench] six_bit_adder      4.10k vecs     114.448 ms (drv    106.504 ms)     38.46 vec/ms     2.60k events/ms    9.38k allocs     1.31M bytes   85.2% pop  171.6 t/vec
[bench] five_bit_adder     1.02k vecs      32.000 ms (drv     25.376 ms)     40.35 vec/ms     2.55k events/ms    3.02k allocs   471.06k bytes   87.3% pop  157.8 t/vec
[bench] and_6bit           4.10k vecs      22.026 ms (drv     19.602 ms)    208.96 vec/ms     2.92k events/ms    8.29k allocs     1.07M bytes   28.4% pop   65.9 t/vec
[bench] mux_5bit_2to1      2.05k vecs      16.947 ms (drv     12.598 ms)    162.57 vec/ms     2.93k events/ms    4.39k allocs   586.61k bytes   50.0% pop   81.0 t/vec
```

The new `allocs` and `bytes` columns are the same delta values that get written to the golden's two rightmost columns — only the formatting differs (k/M scaling, optional raw value in parens). For the stress fixtures introduced for the family-scaling story, watch the trend: `and_5bit`'s 2.13k allocs and `and_6bit`'s 8.29k allocs continue the steep climb that the corpus shows for the AND family (allocs scale with fanout-driven heap pressure, not just vector count). The wider adders tell a different story: events and time scale steeply (eight_bit_adder hits 4.8M events and 1.87s drive), but `peak_queue` caps at 7 across every adder from 4-bit to 8-bit. That's not a sampling artifact — it's the truth-table builder calling `propagateEvent` once per input pin, so peak depth is bounded by per-input fanout rather than total bit width.

### Family rollup

Pass `--rollup` to collapse the 53 per-fixture rows into ~14 per-family lines. Useful for a smell-check: scan whether one family's pop_eff or allocator pressure has shifted, instead of eyeballing every row. The family is inferred from the fixture name — suffix-match on `_adder` groups half/full/N-bit adders together, otherwise the prefix before the first underscore (so `and_4bit` → `and`, `primitive_led` → `primitive`).

```sh
zig build bench -- --rollup
zig build bench -- --rollup --human ms       # rollup is independent of --human; same format either way
```

```
bench rollup: adder         8 fix   71.00k vecs     5.18M events    7 peak  147.73k allocs    19.41M bytes   81.3% pop    1997.85 ms drv
bench rollup: alu           1 fix   16.38k vecs     4.15M events   21 peak   34.73k allocs     4.62M bytes   95.2% pop    1763.44 ms drv
bench rollup: and           6 fix    5.46k vecs    72.56k events    1 peak   11.26k allocs     1.47M bytes   29.7% pop      25.62 ms drv
bench rollup: builtin       5 fix       20 vecs       254 events    2 peak      385 allocs    79.12k bytes   96.1% pop       0.11 ms drv
bench rollup: chain         1 fix        2 vecs        10 events    1 peak       26 allocs     5.29k bytes  100.0% pop       0.01 ms drv
bench rollup: demux         4 fix       60 vecs       492 events    2 peak      384 allocs    71.25k bytes   70.7% pop       0.27 ms drv
bench rollup: mux           5 fix    2.73k vecs    47.30k events    2 peak    6.36k allocs   888.46k bytes   51.9% pop      16.06 ms drv
bench rollup: nand          3 fix      336 vecs     4.39k events    2 peak      989 allocs   153.66k bytes   58.4% pop       1.58 ms drv
bench rollup: nor           3 fix      336 vecs     6.64k events    2 peak    1.25k allocs   211.50k bytes   72.4% pop       2.31 ms drv
bench rollup: not           3 fix       28 vecs       196 events    1 peak      164 allocs    30.62k bytes   76.5% pop       0.08 ms drv
bench rollup: or            3 fix      336 vecs     5.26k events    2 peak    1.08k allocs   173.14k bytes   65.2% pop       1.84 ms drv
bench rollup: primitive     4 fix       10 vecs        30 events    1 peak       72 allocs    13.86k bytes   93.3% pop       0.02 ms drv
bench rollup: xnor          3 fix      336 vecs    11.11k events    2 peak    1.66k allocs   299.34k bytes   83.5% pop       3.93 ms drv
bench rollup: xor           4 fix    1.36k vecs    39.81k events    2 peak    3.99k allocs   620.35k bytes   74.8% pop      14.24 ms drv
```

Rollup columns are always sums except `peak` which is the family max (depth is per-iteration, not additive) and `pop` which is computed from total committed / total popped. The family rows make some patterns immediately obvious that get lost across 53 fixtures: the `and` family's 29.7% pop efficiency is the worst in the corpus (60.3% of pops wasted), `alu` reaches the only peak_queue above 7, and `adder` accounts for ~half the corpus's events and allocator pressure thanks to `eight_bit_adder`.

Rollup ignores `--sort` because the family-grouped output is always alphabetical for stable diffs.

## What it measures

Seven deterministic counters split across two structures. Five live on `engine.Circuit.metrics` and characterize the scheduler; two come from `lib/memory.zig`'s counting allocator and characterize heap pressure. All are `u64`.

| Counter            | Source                                            | Catches                                                                                  |
| ------------------ | ------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `events_popped`    | `Circuit.metrics`, `propagate()` drain, post-pop  | Raw heap throughput. Grows if the scheduler enqueues more events.                        |
| `events_committed` | `Circuit.metrics`, after the no-op `state == event` skip | "Real" state changes. Diverges from `events_popped` when duplicate events stack up. |
| `recalcs`          | `Circuit.metrics`, per call to `recalculateAndReschedule` | Downstream gate evaluations. Walks of the forward-edge graph.                    |
| `peak_queue`       | `Circuit.metrics`, sampled after each Phase-2 fanout | Worst-case heap depth seen during simulation.                                         |
| `final_time`       | `Circuit.metrics`, end of `propagate()`           | Settling time in delay-units (`current_time` after the queue drained).                   |
| `allocs`           | `memory.snapshotAllocMetrics()` delta around fixture | Number of `alloc()` calls hitting the engine's global allocator. Catches "events stayed flat but heap allocations exploded." |
| `bytes`            | `memory.snapshotAllocMetrics()` delta around fixture | Total bytes requested across those `alloc()` calls.                                   |

Three columns in the golden are not metrics but corpus shape: `vectors` (= `2^N` inputs = `table.rows.len`), `components` (= `topology.components.len`, total graph size including expanded sub-circuit primitives), and `topology` (a CRC32 hex digest over the topology's deterministic shape — component id/kind/name/origin and connection from/to/port).

The two allocator counters come from a wrapping `Counter` in `lib/memory.zig` that intercepts the same global allocator the engine uses (`memory.allocator`). The wrapper is selected only when `build_options.collect_metrics=true`; production builds get the raw arena, byte-identical to before. `resize`, `remap`, and `free` pass through without counting because the arena treats `free` as a no-op anyway, and `std.ArrayList` growth ultimately calls `alloc()` for fresh buffers — so `alloc()` alone is a faithful proxy for engine heap pressure.

The `topology` hash is the diff renderer's "what changed" signal. If the hash holds steady but counters move, the engine drifted. If the hash moves, the fixture or the topology builder drifted — and the diff block prefixes the fixture with `(topology changed)` so a reviewer doesn't have to puzzle out which class of change it is.

### How to read a row

Take a row from `tests/fixtures/bench/engine.bench.golden`:

```
| xor_4bit                 |     256 |         76 |          7136 |             5598 |    5602 |          2 |      24830 |     874 |    143040 | 91b4cc3d |
```

That means: an XOR over 4-bit operands exhaustively driven across all 256 input combinations against a 76-component graph (XOR macro expansion: 4 XOR cells × ~19 primitives each, minus shared inputs). The engine popped 7,136 events from its heap, of which 5,598 actually changed state (the other ~1,500 were dedup'd no-ops); it ran 5,602 downstream gate evaluations; the heap never held more than 2 events at once; the final propagation settled at logical time 24,830; the run made 874 allocator calls totaling 143,040 bytes (≈164 bytes per alloc — mostly small `Component` and `ArrayList` headers); and the topology hash `91b4cc3d` identifies this exact shape of components and wires.

The split between `events_popped` and `events_committed` is the diagnostic-grade column. It's not exposed in any other test path, and it catches algorithmic regressions where the scheduler enqueues redundant events that are correctly dedup'd downstream — the circuit gives the right answer, function tests pass, but the heap work has silently doubled.

### Derived stderr columns

These three columns appear in the stderr report only; they are deliberately *not* written to the golden because they are derivable from the seven columns above (or from `drive_ns`, which is itself wall-clock and host-dependent). The point of surfacing them is at-a-glance readability during a bench run — the underlying values are still the regression gate.

| Column   | Formula                                | What it tells you                                                                    |
| -------- | -------------------------------------- | ------------------------------------------------------------------------------------ |
| `drv`    | `Table.drive_ns` from the inner loop   | Drive-only wall-clock. Excludes parse, validate, topology build, engine construction. |
| `% pop`  | `events_committed / events_popped`     | Pop efficiency. 100% = every event changed state; lower = scheduler is wasting heap work. |
| `t/vec`  | `final_time / vectors`                 | Logical settling time per input vector. Drift = engine timing model changed.         |

The `% pop` column is where the buried lede surfaces. From the corpus right now, the `and_*bit` family heads downhill steadily: 61% → 48% → 39% → 33% → 28% from `and_2bit` through `and_6bit`. By the 6-bit point, 71.6% of heap pops are dedup'd no-ops. The slope is decelerating (smaller drops as width grows), which tells you the AND family is heading toward an asymptote rather than blowing up — useful framing that pure counter-watching wouldn't surface.

The `drv` column reframes the small-fixture rates. `chain` (2 vectors) reports total wall-clock around 1.4 ms; its `drv` is ~6 μs. The 1.4 ms is dominated by the per-fixture parser+validator+topology pipeline that runs once and is the same regardless of how many vectors you replay. Reporting throughput against total wall-clock was systematically wrong by ~250× for fixtures like this; throughput against `drv` is honest.

### What it does *not* measure

By design, the bench skips several signals:

- **`createComponent` / `connect` cost in isolation**. `drive_ns` covers only the `2^N` replay loop, so the inner stderr throughput excludes engine construction. But construction itself isn't separately itemized — it's lumped into `(total - drive)` along with parse, validate, and topology build. Splitting further would only matter if construction ever dominated, which it currently doesn't (look at `alu_4bit`: drive_ns is ~98% of total).
- **WASM runtime cost**. Counters live on the native `Circuit` and the native `memory` module. The shipped `.wasm` runtime is built with `collect_metrics=false` and carries zero metrics overhead — both the engine counter bumps and the allocator wrapper are dead code stripped.
- **Compile-time perf**. That has its own gate at `tests/cli/integration_test.zig:260` (the 30-second budget on `stress_grid_10x10` compile).

## Where the counters live

The engine's `Circuit` struct gains a `metrics` field only when compiled with `collect_metrics=true`:

```zig
// lib/circuit.zig
pub const COLLECT_METRICS: bool = @import("build_options").collect_metrics;

pub const Metrics = struct {
    events_popped:    u64 = 0,
    events_committed: u64 = 0,
    recalcs:          u64 = 0,
    peak_queue:       u64 = 0,
    final_time:       u64 = 0,
};

pub const Circuit = struct {
    // ...
    metrics: if (COLLECT_METRICS) Metrics else void = if (COLLECT_METRICS) Metrics{} else {},
};
```

Counter bumps inside `propagate()` are wrapped in `if (COLLECT_METRICS) ...`. When the constant is false, the field is `void` (zero bytes) and every bump compiles away. The shipped `.wasm` runtime, `zig build test`, and `circ-compile` itself all use `collect_metrics=false`; the bench step is the only consumer that sets it to true.

The same flag drives the counting allocator wrapper in `lib/memory.zig`. With `collect_metrics=true`, `memory.allocator` resolves to a `Counter` that intercepts `alloc()`, increments `allocs` and `bytes`, and forwards to the inner arena. With `collect_metrics=false`, `memory.allocator` is the raw arena directly — the wrapper sits unused (≈32 bytes of static storage, no per-allocation overhead). `memory.snapshotAllocMetrics()` returns the cumulative counters; the bench snapshots before and after each `runFixture` and stores the delta on the row.

`build.zig` creates *two* circuit modules pointing at the same source file:

```zig
const circuit_options_default = b.addOptions();
circuit_options_default.addOption(bool, "collect_metrics", false);

const circuit_mod = b.createModule(.{ .root_source_file = b.path("lib/circuit.zig"), ... });
circuit_mod.addOptions("build_options", circuit_options_default);

// ... and later, inside the bench section ...

const circuit_options_bench = b.addOptions();
circuit_options_bench.addOption(bool, "collect_metrics", true);

const bench_circuit_mod = b.createModule(.{ .root_source_file = b.path("lib/circuit.zig"), ... });
bench_circuit_mod.addOptions("build_options", circuit_options_bench);
```

Only the truth-table builder, which actually instantiates a `Circuit`, gets a parallel bench-mode module. Everything else (parser, resolver, validator, full topology serializer) is reused unchanged — those modules don't transitively import the engine, so they don't care which circuit module is wired into the consumer.

## Running and updating

```sh
# Run the bench and compare against the golden. Exits non-zero on any
# counter regression. Prints per-fixture wall-clock to stderr.
zig build bench

# Same, but with the human-friendly stderr report. Pass an explicit unit
# (s | ms | ns) for consistent column alignment; bare --human defaults to ns.
zig build bench -- --human ms

# Sort the report by a column (descending). Works with or without --human.
zig build bench -- --human ms --sort time
zig build bench -- --sort events

# Regenerate the golden after an intentional engine change. The diff
# in the resulting fixture file is the audit trail.
UPDATE_GOLDENS=1 zig build bench
```

The `bench` step is not wired into `zig build test`. It is opt-in and does not affect the default test suite. A typical workflow:

1. Make a change to `lib/circuit.zig` (or anything that affects simulation behaviour).
2. Run `zig build test` to confirm correctness.
3. Run `zig build bench` to confirm no algorithmic regression. If it fails, the runner prints a structured per-fixture, per-column delta (see below) instead of dumping the full table.
4. If the regression is intentional (e.g. you rewrote the event scheduler), run `UPDATE_GOLDENS=1 zig build bench` and review the resulting fixture diff in your PR.

### Mismatch output

When any counter shifts, the bench parses the on-disk golden back into rows, joins it against the in-memory run by fixture name, and emits one block per changed fixture listing only the columns that moved:

```
bench: golden mismatch
bench: 2 changed, 0 added, 0 removed
  alu_4bit
    final_time             5015100 →    5015134   +34 (+0.00%)
  xor_4bit
    events_popped             8000 →       7136   -864 (-10.80%)
```

When the topology hash itself moved, the fixture block is tagged `(topology changed)` and the hash diff leads:

```
bench: golden mismatch
bench: 1 changed, 0 added, 0 removed
  alu_4bit  (topology changed)
    topology_hash       deadbeef → 2028acf9
```

That annotation tells the reviewer to expect counter drift downstream — the fixture or the topology builder moved, not the engine. Counter changes without an accompanying hash change are the inverse: the engine drifted while the test input stayed put. Walked in fixture-manifest (alphabetical) order regardless of `--sort`, so diffs are stable. If the parser itself fails on a malformed golden, the runner falls back to the original side-by-side dump (`--- expected --- / --- actual ---`) so a structurally broken golden is still debuggable.

## Files

| Path                                            | Role                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------- |
| `lib/circuit.zig`                               | Engine + `Metrics` struct + counter bumps                                  |
| `lib/truth_table/builder.zig`                   | Drives the engine over `2^N` vectors; surfaces `circuit.metrics` and `drive_ns` on `Table` |
| `lib/memory.zig`                                | Global allocator + counting wrapper (`Counter`) gated by `COLLECT_METRICS` |
| `tools/bench/main.zig`                          | Bench runner: walks the corpus, prints wall-clock and derived columns, writes/compares golden, renders structured diff on mismatch |
| `tests/fixtures/bench/engine.bench.golden`      | The committed golden: 53 rows, one per fixture                             |
| `build.zig`                                     | Parallel modules + `zig build bench` step                                  |
