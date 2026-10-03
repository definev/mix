# Mix performance benchmarks

Run from `packages/mix`:

```sh
flutter test benchmark/style_resolution_benchmark.dart --reporter expanded
```

The suite warms each workload, measures seven batches, and reports the median
elapsed time per operation in microseconds. Inputs are reused for resolution;
the merge workloads construct a new chain and resolve it in each iteration.
The widget workload updates 100 static `StyleAnimationBuilder`s with freshly
resolved, equal specs and changing children. Token and hover/pressed workloads
resolve against real inherited providers.

There are no timing assertions. Run comparisons sequentially, with other tests
and analysis stopped. These are Flutter test/JIT timings, useful for comparing
the same workload on the same machine. They do not measure production frame
times, raster work, or heap allocation. Profile an application on its target
device to evaluate those costs.

## Example before/after comparison

Measured on macOS arm64 with Flutter 3.44.4 / Dart 3.12.2. The baseline uses
commit `295178a`; both versions use the same benchmark and dependencies. The
optimized version adds single-source resolution, shared source snapshots for
long merge chains, and controller-free static style updates.

| Workload | Baseline (µs/op) | Optimized (µs/op) | Speedup |
| --- | ---: | ---: | ---: |
| Single value resolve | 0.02144 | 0.00847 | 2.53× |
| Single Mix resolve | 0.13465 | 0.04195 | 3.21× |
| Static Box style build | 0.1934 | 0.0832 | 2.32× |
| Merge 8 sources and resolve | 0.319 | 0.328 | 0.97× |
| Merge 32 sources and resolve | 1.6885 | 1.568 | 1.08× |
| Merge 128 sources and resolve | 16.0735 | 7.938 | 2.02× |
| Merge 512 sources and resolve | 185.3235 | 32.6775 | 5.67× |
| Token Box style build | 0.7749 | 0.6255 | 1.24× |
| Hover/pressed Box style build | 4.3066 | 4.2264 | 1.02× |
| Update 100 static style widgets | 1283.73 | 647.9 | 1.98× |

Small-chain and hover/pressed differences are modest and should be treated as
roughly unchanged. Source lists of up to 32 entries retain the ordinary list
implementation; longer chains share snapshots and flatten on first read.
Snapshot detachment preserves source ordering and the existing mutable List
surface. Tokens still resolve on every build and nested styles still build
their context variants.
