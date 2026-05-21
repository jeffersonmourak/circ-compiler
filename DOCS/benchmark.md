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

Total: 98,400 input vectors driven through the engine in a single bench run; ~8.3M events popped, ~8.2k allocator calls totaling ~985 KB. Pop efficiency sits at ~100% corpus-wide after the `propagateEvent` no-op short-circuit (the harness's drive-all-inputs-per-vector pattern used to push it as low as 28% on the AND family). The wider adders (`five_bit_adder`, `six_bit_adder`, `eight_bit_adder`) characterize cascading-carry depth, and the 8-bit adder pushing 65k vectors and 3.9M events overtakes `alu_4bit` as the heaviest fixture by both vector count and event volume. The corpus totals above reflect the current engine state; the per-milestone evolution lives in `tests/fixtures/bench/engine.bench.golden.hist.md` (see [Historical evolution](#historical-evolution) below).

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
bench: alu_4bit                  16384 vecs    984.129 ms (drv  952.929)    58162.2 ns/vec   241.2 ns/event  100.0% pop   306.1 t/vec
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
[bench] alu_4bit          16.38k vecs    1026.451 ms (drv    995.085 ms)     16.46 vec/ms     3.97k events/ms    1.20k allocs   148.33k bytes  100.0% pop  306.1 t/vec
[bench] and_4bit             256 vecs       2.595 ms (drv      0.671 ms)    381.52 vec/ms     1.48k events/ms       43 allocs     4.93k bytes  100.0% pop   45.6 t/vec
[bench] chain                  2 vecs       1.394 ms (drv      0.003 ms)    666.67 vec/ms     3.33k events/ms       16 allocs     1.91k bytes  100.0% pop   21.0 t/vec
[bench] four_bit_adder       256 vecs       9.417 ms (drv      3.331 ms)     76.85 vec/ms     3.95k events/ms      460 allocs    55.97k bytes  100.0% pop  141.6 t/vec
[bench] nand_4bit            256 vecs       2.698 ms (drv      0.840 ms)    304.76 vec/ms     2.36k events/ms       88 allocs    10.24k bytes  100.0% pop   60.3 t/vec
[bench] ---  53 fixtures   98.40k vectors (98400)   8.26M events (8259072)   8.20k allocs (8198)   985.30k bytes (985296)   2364.414 ms total (2194.047 ms drv, 92.8% engine)
```

The per-fixture rows drop the `(raw)` parenthetical that the totals line carries — on aggregate counts the exact value is useful, on individual rows it just bloats every column. The totals keep it.

Same data with `--human s`:

```
[bench] alu_4bit          16.38k vecs        1.010 s (drv      0.9781 s)     16.75k vec/s      4.04M events/s    1.20k allocs   148.33k bytes  100.0% pop  306.1 t/vec
[bench] chain                  2 vecs       0.0014 s (drv      0.0000 s)    500.00k vec/s      2.50M events/s       16 allocs     1.91k bytes  100.0% pop   21.0 t/vec
[bench] ---  53 fixtures   98.40k vectors (98400)   8.26M events (8259072)   8.20k allocs (8198)   985.30k bytes (985296)   2.385 s total (2.216 s drv, 92.9% engine)
```

And `--human` (default, ns) keeps full precision at the cost of wide numbers and scientific notation for the throughput:

```
[bench] alu_4bit          16.38k vecs   990179000 ns (drv  958651000 ns)   1.71e-5 vec/ns   4.12e-3 events/ns    1.20k allocs   148.33k bytes  100.0% pop  306.1 t/vec
[bench] ---  53 fixtures   98.40k vectors (98400)   8.26M events (8259072)   8.20k allocs (8198)   985.30k bytes (985296)   2372651000 ns total (2201553000 ns drv, 92.8% engine)
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
[bench] eight_bit_adder   65.54k vecs    1136.861 ms (drv   1119.442 ms)     58.54 vec/ms     3.49k events/ms      985 allocs   118.66k bytes  100.0% pop  195.2 t/vec
[bench] alu_4bit          16.38k vecs     994.179 ms (drv    962.800 ms)     17.02 vec/ms     4.10k events/ms    1.20k allocs   148.33k bytes  100.0% pop  306.1 t/vec
[bench] six_bit_adder      4.10k vecs      73.269 ms (drv     62.971 ms)     65.05 vec/ms     3.74k events/ms      723 allocs    88.64k bytes  100.0% pop  171.6 t/vec
[bench] mux_5bit_2to1      2.05k vecs      26.437 ms (drv     13.350 ms)    153.41 vec/ms     1.38k events/ms      185 allocs    21.94k bytes  100.0% pop   81.0 t/vec
[bench] five_bit_adder     1.02k vecs      22.756 ms (drv     14.582 ms)     70.22 vec/ms     3.88k events/ms      591 allocs    70.98k bytes  100.0% pop  157.8 t/vec
[bench] and_6bit           4.10k vecs      16.951 ms (drv     14.356 ms)    285.32 vec/ms     1.13k events/ms       64 allocs     7.49k bytes  100.0% pop   65.9 t/vec
```

The `allocs` and `bytes` columns are the same delta values that get written to the golden's two rightmost columns; only the formatting differs (k/M scaling, optional raw value in parens). `and_5bit`'s 54 allocs and `and_6bit`'s 64 allocs grow linearly with fan-out width (about 10 allocs per additional input bit, since each new connection appends to a single `ArrayList` that doubles its capacity at growth boundaries). The wider adders show events and time scaling steeply (`eight_bit_adder` hits 3.9M events), but `peak_queue` caps at 7 across every adder from 4-bit to 8-bit. That's not a sampling artifact; it's the truth-table builder calling `propagateEvent` once per input pin, so peak depth is bounded by per-input fanout rather than total bit width.

### Family rollup

Pass `--rollup` to collapse the 53 per-fixture rows into ~14 per-family lines. Useful for a smell-check: scan whether one family's pop_eff or allocator pressure has shifted, instead of eyeballing every row. The family is inferred from the fixture name — suffix-match on `_adder` groups half/full/N-bit adders together, otherwise the prefix before the first underscore (so `and_4bit` → `and`, `primitive_led` → `primitive`).

```sh
zig build bench -- --rollup
zig build bench -- --rollup --human ms       # rollup is independent of --human; same format either way
```

```
bench rollup: adder         8 fix   71.00k vecs     4.21M events    7 peak    3.49k allocs   421.16k bytes  100.0% pop    1255.54 ms drv
bench rollup: alu           1 fix   16.38k vecs     3.95M events   21 peak    1.20k allocs   148.33k bytes  100.0% pop     969.54 ms drv
bench rollup: and           6 fix    5.46k vecs    21.58k events    1 peak      230 allocs    26.85k bytes  100.0% pop      18.50 ms drv
bench rollup: builtin       5 fix       20 vecs       244 events    2 peak      222 allocs    26.16k bytes  100.0% pop       0.08 ms drv
bench rollup: chain         1 fix        2 vecs        10 events    1 peak       16 allocs     1.91k bytes  100.0% pop       0.00 ms drv
bench rollup: demux         4 fix       60 vecs       348 events    2 peak      174 allocs    20.59k bytes  100.0% pop       0.19 ms drv
bench rollup: mux           5 fix    2.73k vecs    24.53k events    2 peak      571 allocs    67.54k bytes  100.0% pop      10.83 ms drv
bench rollup: nand          3 fix      336 vecs     2.56k events    2 peak      200 allocs    23.30k bytes  100.0% pop       1.12 ms drv
bench rollup: nor           3 fix      336 vecs     4.81k events    2 peak      356 allocs    42.26k bytes  100.0% pop       1.55 ms drv
bench rollup: not           3 fix       28 vecs       150 events    1 peak       72 allocs     8.33k bytes  100.0% pop       0.07 ms drv
bench rollup: or            3 fix      336 vecs     3.43k events    2 peak      255 allocs    29.81k bytes  100.0% pop       1.27 ms drv
bench rollup: primitive     4 fix       10 vecs        28 events    1 peak       43 allocs     5.24k bytes  100.0% pop       0.02 ms drv
bench rollup: xnor          3 fix      336 vecs     9.28k events    2 peak      601 allocs    71.77k bytes  100.0% pop       2.41 ms drv
bench rollup: xor           4 fix    1.36k vecs    29.79k events    2 peak      776 allocs    92.06k bytes  100.0% pop       9.12 ms drv
```

Rollup columns are always sums except `peak` which is the family max (depth is per-iteration, not additive) and `pop` which is computed from total committed / total popped. Pop efficiency reads 100% across every family today because `propagateEvent` short-circuits no-op enqueues (events the caller asks for that already match the component's current state, the dominant waste pattern under the bench harness). The family rows still make some patterns obvious that get lost across 53 fixtures: `alu` reaches the only peak_queue above 7, and `adder` accounts for ~half the corpus's events and allocator pressure thanks to `eight_bit_adder`.

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
| xor_4bit                 |     256 |         76 |          5598 |             5598 |    5602 |          2 |      24830 |     221 |     25984 | 6cc538e8 |
```

That means: an XOR over 4-bit operands exhaustively driven across all 256 input combinations against a 76-component graph (XOR macro expansion: 4 XOR cells × ~19 primitives each, minus shared inputs). The engine popped 5,598 events from its heap, every one of which changed state (`events_popped == events_committed`, the post-short-circuit norm); it ran 5,602 downstream gate evaluations; the heap never held more than 2 events at once; the final propagation settled at logical time 24,830; the run made 221 allocator calls totaling 25,984 bytes (≈118 bytes per alloc, mostly `Component` structs plus a handful of `ArrayList` growth slabs); and the topology hash `6cc538e8` identifies this exact shape of components and wires.

The split between `events_popped` and `events_committed` is the diagnostic-grade column. It's not exposed in any other test path, and it catches algorithmic regressions where the scheduler enqueues redundant events that are correctly dedup'd downstream — the circuit gives the right answer, function tests pass, but the heap work has silently doubled.

### Derived stderr columns

These three columns appear in the stderr report only; they are deliberately *not* written to the golden because they are derivable from the seven columns above (or from `drive_ns`, which is itself wall-clock and host-dependent). The point of surfacing them is at-a-glance readability during a bench run — the underlying values are still the regression gate.

| Column   | Formula                                | What it tells you                                                                    |
| -------- | -------------------------------------- | ------------------------------------------------------------------------------------ |
| `drv`    | `Table.drive_ns` from the inner loop   | Drive-only wall-clock. Excludes parse, validate, topology build, engine construction. |
| `% pop`  | `events_committed / events_popped`     | Pop efficiency. 100% = every event changed state; lower = scheduler is wasting heap work. |
| `t/vec`  | `final_time / vectors`                 | Logical settling time per input vector. Drift = engine timing model changed.         |

The `% pop` column reads ~100% across every fixture today: `propagateEvent` short-circuits when the requested state already matches the component's current state, so the only events that enter the queue from the outside are the ones that actually commit. Pre-short-circuit, the `and_*bit` family was the corpus's worst offender (61% → 48% → 39% → 33% → 28% from `and_2bit` through `and_6bit`, with 71.6% of pops being dedup'd no-ops by the 6-bit point); that signal turned out to track the bench harness's drive-all-inputs-per-vector pattern rather than anything structural about the AND topology. A future drop below 100% would mean a new event flow inside the engine is enqueueing redundant proposals, which is a worth-investigating signal.

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

# Record this run as a milestone in the historical log (see "Historical
# evolution" below for the file format). Independent of UPDATE_GOLDENS;
# can be combined with it or run after a clean compare.
RECORD_MILESTONE="<label>" zig build bench
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

## Historical evolution

The bench can optionally append a corpus-level milestone to `tests/fixtures/bench/engine.bench.golden.hist.md`. Setting `RECORD_MILESTONE="<label>"` switches the feature on; the label becomes the human-readable description for the milestone row. The file is an append-only audit trail and complements (rather than replaces) the engine golden: the golden is the regression gate, the `.hist` is the story of how the corpus got to where it is.

```sh
RECORD_MILESTONE="scheduler dedup" zig build bench
```

On first invocation against a working tree without a `.hist` file, the bench bootstraps the BASE section by retrieving the golden at git HEAD (via `git show HEAD:tests/fixtures/bench/engine.bench.golden`). The BASE snapshot therefore reflects an honest pre-change state regardless of which run actually creates the file. After that, each run parses the existing `.hist`, derives "Δ vs base" and "Δ vs prev" for the current totals, and appends a new milestone summary row plus a per-fixture detail block.

The summary table holds these columns per milestone:

| Column            | Aggregation        | What a non-zero delta means                                                |
| ----------------- | ------------------ | -------------------------------------------------------------------------- |
| `events_popped`   | sum across fixtures| Heap throughput shifted (a scheduler change either drained more or fewer events). |
| `events_committed`| sum                | Pop-efficiency shifted, even if `events_popped` didn't.                    |
| `recalcs`         | sum                | Downstream-walk count moved (graph traversal cost).                        |
| `peak_queue`      | max                | Worst-case heap depth moved (not additive: depth is per-iteration).        |
| `final_time`      | sum                | Engine timing model drifted (settling time in delay-units).                |
| `allocs`          | sum                | Allocator pressure (`memory.allocator` calls) shifted.                     |
| `bytes`           | sum                | Total bytes requested shifted.                                             |
| `drv_ms`          | sum                | Wall-clock for the inner replay loop. Not asserted; `?` when the reference side never recorded drv. |

Each cell renders as `<value> (Δ% vs base / Δ% vs prev)`. The first recorded milestone has no "prev", so the right half of every cell shows `?`. The BASE row's `drv_ms` is also `?` because the engine golden has never stored wall-clock, so the bootstrap can't recover it; once a milestone with drv is recorded, subsequent "Δ vs prev" comparisons compute against that.

Below the summary, each milestone gets a `## Milestone N: <label>` block with per-fixture deltas vs BASE for the seven deterministic counters. Detail blocks are append-only decoration preserved verbatim on re-write; the summary table is the structured source of truth that the parser reads to compute the next "Δ vs prev".

The `.hist` file is checked in alongside the golden so the history travels with the codebase. A typical workflow when shipping an engine perf change:

1. Run `UPDATE_GOLDENS=1 zig build bench` to regenerate `engine.bench.golden` with the new asserted counters.
2. Run `RECORD_MILESTONE="<description>" zig build bench` to append the milestone to `.hist`.
3. Both files land in the same commit; reviewers read the golden diff for the algorithmic change and the `.hist` diff for the deltas.

## Files

| Path                                            | Role                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------- |
| `lib/circuit.zig`                               | Engine + `Metrics` struct + counter bumps                                  |
| `lib/truth_table/builder.zig`                   | Drives the engine over `2^N` vectors; surfaces `circuit.metrics` and `drive_ns` on `Table` |
| `lib/memory.zig`                                | Global allocator + counting wrapper (`Counter`) gated by `COLLECT_METRICS` |
| `tools/bench/main.zig`                          | Bench runner: walks the corpus, prints wall-clock and derived columns, writes/compares golden, renders structured diff on mismatch, records milestones to `.hist` |
| `tests/fixtures/bench/engine.bench.golden`      | The committed golden: 53 rows, one per fixture                             |
| `tests/fixtures/bench/engine.bench.golden.hist.md` | Append-only historical milestone log: BASE snapshot + per-milestone deltas |
| `build.zig`                                     | Parallel modules + `zig build bench` step                                  |
