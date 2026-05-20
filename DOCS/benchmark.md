# Engine Benchmark

A regression gate for `lib/circuit.zig` driven by the truth-table fixture corpus. Runs via `zig build bench`; the result is compared against a golden file at `tests/fixtures/bench/engine.bench.golden`.

The benchmark exists to answer one question: *does the simulation engine still do the same amount of work it used to, on the same circuits?* It is not a wall-clock benchmark — wall-clock is reported but never asserted, because it varies with the host. The asserted numbers are deterministic counters that depend only on the algorithm.

## What it runs

The bench walks 46 fixtures from the truth-table corpus: every circuit that has a matching `*.truth.golden` under `tests/fixtures/truth_table/`. Coverage spans the full size range:

| Tier                     | Fixtures (examples)                                                | Vectors per circuit |
| ------------------------ | ------------------------------------------------------------------ | ------------------- |
| Single primitive         | `primitive_not`, `primitive_wire`, `primitive_led`                 | 2                   |
| Single gate              | `primitive_and`, `and_two_inputs`                                  | 4                   |
| Builtin macros           | `builtin_xor`, `builtin_nand`, `builtin_xnor`                      | 4                   |
| 2/3/4-bit fan-outs       | `and_2bit`, `or_3bit`, `xor_4bit`                                  | 16 / 64 / 256       |
| Combinational structures | `mux_2to1` ... `mux_4bit_2to1`, `demux_1to2` ... `demux_4bit_1to2` | 4 – 512             |
| Adders                   | `half_adder`, `full_adder`, `two/three/four_bit_adder`             | 4 – 256             |
| Largest                  | `alu_4bit` (14 inputs)                                             | 16384               |

Total: 19,552 input vectors driven through the engine in a single bench run; ~4.2M events committed.

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
[bench] alu_4bit                 16.38k vecs (16384)           2364.292 ms (drv 2331.841 ms   )          7.03 vec/ms          1.78k events/ms      95.2% pop    306.1 t/vec
[bench] and_4bit                 256 vecs                         3.254 ms (drv 1.249 ms      )        204.96 vec/ms          2.02k events/ms      39.2% pop     45.6 t/vec
[bench] chain                    2 vecs                           1.387 ms (drv 0.006 ms      )        333.33 vec/ms          1.67k events/ms     100.0% pop     21.0 t/vec
[bench] four_bit_adder           256 vecs                        13.461 ms (drv 7.417 ms      )         34.52 vec/ms          1.98k events/ms      89.5% pop    141.6 t/vec
[bench] xor_4bit                 256 vecs                         5.828 ms (drv 3.327 ms      )         76.95 vec/ms          2.14k events/ms      78.4% pop     97.0 t/vec
[bench] ---  46 fixtures   19.55k vectors (19552)   4.22M events (4216701)   2493.171 ms total (2365.480 ms drv, 94.9% engine)
```

Same data with `--human s`:

```
[bench] alu_4bit                 16.38k vecs (16384)               2.320 s (drv 2.287 s       )          7.16k vec/s           1.81M events/s      95.2% pop    306.1 t/vec
[bench] chain                    2 vecs                           0.0017 s (drv 0.0000 s      )        250.00k vec/s           1.25M events/s     100.0% pop     21.0 t/vec
[bench] ---  46 fixtures   19.55k vectors (19552)   4.22M events (4216701)   2.497 s total (2.349 s drv, 94.1% engine)
```

And `--human` (default, ns) keeps full precision at the cost of wide numbers and scientific notation for the throughput:

```
[bench] alu_4bit                 16.38k vecs (16384)        2297377000 ns (drv 2264500000 ns )       7.13e-6 vec/ns       1.81e-3 events/ns      95.2% pop    306.1 t/vec
[bench] ---  46 fixtures   19.55k vectors (19552)   4.22M events (4216701)   2392374000 ns total (2264500000 ns drv, 94.7% engine)
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
[bench] alu_4bit                 16.38k vecs (16384)           2237.021 ms (drv 2205.216 ms   )          7.43 vec/ms          1.88k events/ms      95.2% pop    306.1 t/vec
[bench] four_bit_adder           256 vecs                        13.607 ms (drv 7.430 ms      )         34.45 vec/ms          1.98k events/ms      89.5% pop    141.6 t/vec
[bench] mux_4bit_2to1            512 vecs                         8.111 ms (drv 3.732 ms      )        137.19 vec/ms          2.20k events/ms      56.2% pop     71.0 t/vec
[bench] three_bit_adder          64 vecs                          6.407 ms (drv 1.609 ms      )         39.78 vec/ms          1.95k events/ms      91.8% pop    121.8 t/vec
[bench] xnor_4bit                256 vecs                         6.248 ms (drv 4.010 ms      )         63.84 vec/ms          2.16k events/ms      82.2% pop    116.8 t/vec
[bench] xor_4bit                 256 vecs                         5.484 ms (drv 3.374 ms      )         75.87 vec/ms          2.11k events/ms      78.4% pop     97.0 t/vec
```

## What it measures

Five deterministic counters live on `engine.Circuit.metrics`. Each catches a different class of regression. All are `u64`.

| Counter            | Bumped where                          | Catches                                                                                  |
| ------------------ | ------------------------------------- | ---------------------------------------------------------------------------------------- |
| `events_popped`    | `propagate()` drain, post-pop         | Raw heap throughput. Grows if the scheduler enqueues more events.                        |
| `events_committed` | After the no-op `state == event` skip | "Real" state changes. Diverges from `events_popped` when duplicate events stack up.      |
| `recalcs`          | Per call to `recalculateAndReschedule`| Downstream gate evaluations. Walks of the forward-edge graph.                            |
| `peak_queue`       | Sampled after each Phase-2 fanout     | Worst-case heap depth seen during simulation.                                            |
| `final_time`       | End of `propagate()`                  | Settling time in delay-units (`current_time` after the queue drained).                   |

Two columns in the golden are not metrics but corpus shape: `vectors` (= `2^N` inputs = `table.rows.len`) and `components` (= `topology.components.len`, total graph size including expanded sub-circuit primitives).

### How to read a row

Take a row from `tests/fixtures/bench/engine.bench.golden`:

```
| xor_4bit                 |     256 |         76 |          7136 |             5598 |    5602 |          2 |      24830 |
```

That means: an XOR over 4-bit operands exhaustively driven across all 256 input combinations against a 76-component graph (XOR macro expansion: 4 XOR cells × ~19 primitives each, minus shared inputs). The engine popped 7,136 events from its heap, of which 5,598 actually changed state (the other ~1,500 were dedup'd no-ops); it ran 5,602 downstream gate evaluations; the heap never held more than 2 events at once; and the final propagation settled at logical time 24,830.

The split between `events_popped` and `events_committed` is the diagnostic-grade column. It's not exposed in any other test path, and it catches algorithmic regressions where the scheduler enqueues redundant events that are correctly dedup'd downstream — the circuit gives the right answer, function tests pass, but the heap work has silently doubled.

### Derived stderr columns

These three columns appear in the stderr report only; they are deliberately *not* written to the golden because they are derivable from the seven columns above (or from `drive_ns`, which is itself wall-clock and host-dependent). The point of surfacing them is at-a-glance readability during a bench run — the underlying values are still the regression gate.

| Column   | Formula                                | What it tells you                                                                    |
| -------- | -------------------------------------- | ------------------------------------------------------------------------------------ |
| `drv`    | `Table.drive_ns` from the inner loop   | Drive-only wall-clock. Excludes parse, validate, topology build, engine construction. |
| `% pop`  | `events_committed / events_popped`     | Pop efficiency. 100% = every event changed state; lower = scheduler is wasting heap work. |
| `t/vec`  | `final_time / vectors`                 | Logical settling time per input vector. Drift = engine timing model changed.         |

The `% pop` column is where the buried lede surfaces. From the corpus right now, `and_4bit` runs at 39.2% pop efficiency — 60.8% of its heap pops are dedup'd no-ops. That number was always available in the golden (raw counters), but you had to do the subtraction in your head to see it.

The `drv` column reframes the small-fixture rates. `chain` (2 vectors) reports total wall-clock around 1.4 ms; its `drv` is ~6 μs. The 1.4 ms is dominated by the per-fixture parser+validator+topology pipeline that runs once and is the same regardless of how many vectors you replay. Reporting throughput against total wall-clock was systematically wrong by ~250× for fixtures like this; throughput against `drv` is honest.

### What it does *not* measure

By design, the bench skips several signals:

- **Allocation count / bytes**. Adding this would require wrapping `memory.allocator`. Easy follow-up, omitted in v1.
- **`createComponent` / `connect` cost in isolation**. `drive_ns` covers only the `2^N` replay loop, so the inner stderr throughput excludes engine construction. But construction itself isn't separately itemized — it's lumped into `(total - drive)` along with parse, validate, and topology build. Splitting further would only matter if construction ever dominated, which it currently doesn't (look at `alu_4bit`: drive_ns is ~98% of total).
- **WASM runtime cost**. Counters live on the native `Circuit`. The shipped `.wasm` runtime is built with `collect_metrics=false` and carries zero metrics overhead.
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

Walked in fixture-manifest (alphabetical) order regardless of `--sort`, so diffs are stable. If the parser itself fails on a malformed golden, the runner falls back to the original side-by-side dump (`--- expected --- / --- actual ---`) so a structurally broken golden is still debuggable.

## Files

| Path                                            | Role                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------- |
| `lib/circuit.zig`                               | Engine + `Metrics` struct + counter bumps                                  |
| `lib/truth_table/builder.zig`                   | Drives the engine over `2^N` vectors; surfaces `circuit.metrics` and `drive_ns` on `Table` |
| `tools/bench/main.zig`                          | Bench runner: walks the corpus, prints wall-clock and derived columns, writes/compares golden, renders structured diff on mismatch |
| `tests/fixtures/bench/engine.bench.golden`      | The committed golden: 46 rows, one per fixture                             |
| `build.zig`                                     | Parallel modules + `zig build bench` step                                  |
