# Performance scope

No throughput, startup speedup or peak-memory guarantee is claimed. Trusted command
execution, filesystem work and diagnostic I/O are part of the measured invocation.
Payload/work limits are not measured allocation or resident-memory guarantees.

The [diff consumer harness](../bench/README.md) records real checker invocations
with and without --diff, including matching controls and omission/truncation paths.
It retains fixtures, raw wall-time/RSS samples and exact identities. Shared-host
samples are descriptive and do not establish a general speed ranking.

Source and toolchain identities live in Git, GOOSE_REVISION and vendor/pins.json.
The new portable goose-diff dependency is immutable; process/fs/config pins remain
unchanged. See [diff contracts](STDOUT_DIFF.md) and THIRD_PARTY.md.

The older [invocation-cost study](https://github.com/carabistouflette/goose-process/blob/4cf1f13302ad5b42f3ca94f3c7a829c44b7ee60e/docs/CHECKER-CONSUMER.md#invocation-cost-experiment)
used checker32de6c4 before streamed stderr and this integration. It is historical,
not evidence for the current checker; all slower samples and qualifications stay
with that report. Current evidence does not waive upstream release/fuzz gates.
