# Stdout diff consumer measurements

Build unsanitized `make build CC=gcc`, then run:

```sh
python3 bench/diff.py --tool .build/goose-check --out .build/diff-samples --rounds 10
```

Requires Linux `/usr/bin/time`, `/bin/cat`, Python and the usual toolchain. Retains
every input, binary/source/toolchain/dependency identities and all wall-time,
maximum-RSS and stderr-byte samples. Flag order alternates and runs are serial.
Timing includes checker startup, fixture reads, cat, diagnostics and time-wrapper
startup. RSS is GNU time's process measurement, not a library allocation limit.

Covers matching output, a small edit, escaped truncation and three resource-limit
omission paths. Both modes use one binary and the same fixtures. Shared-host
samples justify no speedup, absence-of-overhead, cross-machine ranking or peak-
memory guarantee. Retain slower samples and identities. No CI speed threshold.

Context qualification adds a compiler transcript captured by the pinned Goose
compiler (exact source fixtures from goose-diff context evidence), generated text
with a small middle edit, and scattered changes. Current --diff uses three
context lines. Previous alpha.1 samples remain historical, not a timing control
for the changed workload set. New runs compare default and opt-in invocations
of the same new binary; no old/new executable speed claim is made.

## Explicit strategy consumer

```sh
make build CC=gcc SANITIZE=0
python3 bench/strategies.py --tool .build/goose-check --out .build/strategy-samples
```

Nine frozen inputs cover distant generated/diagnostic/repeated edits, equal and
single changes, dense limits and a 400-line no-fallback guard. Default, explicit
lcs and explicit sparse rotate order on one unsanitized binary. Default/explicit
LCS diagnostics must match exactly in every round. Omission states are recorded;
never use rejected LCS work as a successful-throughput denominator. Earlier
microbenchmarks remain historical, not an end-to-end command speed guarantee.
All raw samples and fixture hashes are retained with provenance; no CI threshold.
