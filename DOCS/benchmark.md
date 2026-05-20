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

Wall-clock is sampled with `std.time.nanoTimestamp` around `runFixture` (parse, resolve, validate, build topology, drive all vectors). The bench prints per-fixture wall-clock to stderr but does not write it to the golden:

```
bench: alu_4bit                  16384 vecs   1752.696 ms    106976.1 ns/vec   422.7 ns/event
```

Pass `--human` (after a `--` separator, since Zig's build driver consumes its own args first) to switch the output to a humanized form: counts get k/M suffixes plus the raw value in parens, throughput flips to `items/<time>` (so the engine's pace reads as "vectors per unit of wall-clock" instead of "wall-clock per vector"), and every column uses **one fixed time unit** so values line up vertically and are easy to scan.

You pick the unit:

| Invocation             | Time / throughput unit             | When to use                                                          |
| ---------------------- | ---------------------------------- | -------------------------------------------------------------------- |
| `--human` (no arg)     | `ns` (default)                     | Mirrors the existing `ns/vec` / `ns/event` precision but inverted    |
| `--human ms`           | `ms`                               | Best general-purpose; most fixtures land in 1–100 vec/ms range       |
| `--human s`            | `s`                                | High-level summary; throughput shows in k/s or M/s                   |

```sh
zig build bench -- --human ms
```

```
[bench] alu_4bit                 16.38k vecs (16384)             2297.377 ms          7.31 vec/ms          1.81k events/ms
[bench] chain                    2 vecs                             1.376 ms          1.45 vec/ms            7.27 events/ms
[bench] four_bit_adder           256 vecs                          13.684 ms         18.71 vec/ms          1.07k events/ms
[bench] xor_4bit                 256 vecs                           5.433 ms         47.12 vec/ms          1.31k events/ms
[bench] ---  46 fixtures   19.55k vectors (19552)   4.22M events (4216701)   2378.035 ms total
```

Same data with `--human s`:

```
[bench] alu_4bit                 16.38k vecs (16384)             2.297 s         7.13k vec/s          1.81M events/s
[bench] chain                    2 vecs                          0.0014 s         1.45k vec/s           7.27k events/s
[bench] ---  46 fixtures   19.55k vectors (19552)   4.22M events (4216701)   2.367 s total
```

And `--human` (default, ns) keeps full precision at the cost of wide numbers and scientific notation for the throughput:

```
[bench] alu_4bit                 16.38k vecs (16384)             2297377000 ns       7.13e-6 vec/ns       1.81e-3 events/ns
[bench] ---  46 fixtures   19.55k vectors (19552)   4.22M events (4216701)   2392374000 ns total
```

Throughput k/M scaling kicks in inside the chosen unit — `1.81M events/s` and `1.31k events/ms` are the same engine; only the denomination is different. The flag only affects the stderr report; the golden comparison and the golden file itself are untouched.

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

Example output (`--human ms --sort time`, top 5):

```
[bench] alu_4bit                 16.38k vecs (16384)           2317.862 ms          7.07 vec/ms          1.79k events/ms
[bench] four_bit_adder           256 vecs                        13.775 ms         18.58 vec/ms          1.07k events/ms
[bench] mux_4bit_2to1            512 vecs                         7.748 ms         66.08 vec/ms          1.06k events/ms
[bench] xnor_4bit                256 vecs                         6.312 ms         40.56 vec/ms          1.37k events/ms
[bench] three_bit_adder          64 vecs                          5.894 ms         10.86 vec/ms         531.90 events/ms
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

### What it does *not* measure

By design, the bench skips several signals:

- **Allocation count / bytes**. Adding this would require wrapping `memory.allocator`. Easy follow-up, omitted in v1.
- **Setup vs. steady-state split**. The truth-table builder constructs the circuit once and reuses it across all `2^N` vectors, so construction is amortized. Splitting it would only be interesting if `createComponent` or `connect` cost ever dominated.
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
3. Run `zig build bench` to confirm no algorithmic regression. If it fails, the diff in stderr shows expected vs. actual columns side by side.
4. If the regression is intentional (e.g. you rewrote the event scheduler), run `UPDATE_GOLDENS=1 zig build bench` and review the resulting fixture diff in your PR.

## Files

| Path                                            | Role                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------- |
| `lib/circuit.zig`                               | Engine + `Metrics` struct + counter bumps                                  |
| `lib/truth_table/builder.zig`                   | Drives the engine over `2^N` vectors; surfaces `circuit.metrics` on `Table`|
| `tools/bench/main.zig`                          | Bench runner: walks the corpus, prints wall-clock, writes/compares golden  |
| `tests/fixtures/bench/engine.bench.golden`      | The committed golden: 46 rows, one per fixture                             |
| `build.zig`                                     | Parallel modules + `zig build bench` step                                  |
