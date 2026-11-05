# Performance scope

**Current benchmark: N/A.** goose-check makes no throughput, startup-latency,
speedup or RSS claim. It checks trusted commands, whose execution and fixture I/O
usually determine the workload. No performance comparison is needed to explain
or validate this interface, so this documentation audit did not add a benchmark.

Capture/input caps and chunk sizes are API payload/work bounds, not measured
allocation or peak-memory limits. The [contract](CONTRACT.md) states them;
[validation](VALIDATION.md) covers correctness. Neither proves performance or an
absence of bugs.

An older invocation-cost study lives in goose-process at
[its historical report](https://github.com/carabistouflette/goose-process/blob/4cf1f13302ad5b42f3ca94f3c7a829c44b7ee60e/docs/CHECKER-CONSUMER.md#invocation-cost-experiment).
It used checker `32de6c4783bf8d3242e042993dadd160a98b2945`, before this application's
streamed-stderr change and process dependency update. It is not evidence for
current checker `713e2749ded459b915f59012aaa6e19351a17b18`. Its source versions,
raw samples, slower results and policy differences remain available there.

Current source identities are in `GOOSE_REVISION` and `vendor/pins.json`:
Goose `eadca409f68210893f366e60d0c2f0dc29a339be`,
process `35b74eff63118abdd5b00603e1de4bf8ded110a2`,
fs `910576e745e9ef4afc7807c4843ddc948836189a`,
config `f7bef7dcfeab2ca95c94d92d0fbb2320ab3dcb05`.
The docs audit preserves these objects and all dependency notices. It does not
waive an upstream fuzz/release gate or create a stable release of this untagged tool.
