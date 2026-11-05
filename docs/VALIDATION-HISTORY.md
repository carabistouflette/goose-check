# Historical checker validation

These records describe the source revisions named in each section. Statements
about unchanged pins or pending hosted checks belong to those snapshots, not
today's code. See [current coverage](VALIDATION.md).

## Recorded prepublication checks (2026-11-04)

Implementation source `6589dc4380db2f008ecb71154b4728222431cf40` passed:

- Seven release and seven debug CLI integration methods, with compiler and binary
  fixture subcases, using both GCC and Clang instrumentation configurations.
- Three real-CLI fault scenarios: pending prelaunch cancellation, actual ownership
  transfer with two denied recovery waits, and broken-stderr transfer cleanup.
- Both complete ASan/UBSan/fortification matrices, including generated C and all
  three native packages. Debug uses `--debug --no-bce`; native sanitizer C uses
  -O1 so fortification remains active despite the debug compiler's -O0 default.
- The documented C compiler example and Clang static analysis of caller policy.
- Inventory, source-fingerprint, Python syntax and whitespace checks.

A clean separate local clone in a path containing spaces ran `make setup` to
fetch/build its own exact Goose compiler, then passed `make check test
test-faults example CC=gcc` with no compiler override or sibling library access.
The compiler source/tree remained clean. Vendored files were independently
compared against both pinned upstream Git revisions.

Host provenance: Linux x86-64/glibc 2.44, GCC 16.2.1, Clang 23.1.4,
Python 3.14.9, Goose `eadca409f68210893f366e60d0c2f0dc29a339be`.
These are functional checks on a shared host, not performance measurements.
Two independent design reviewers, independent security and contract reviewers,
and a final independent publication auditor examined the new project. The
security reviewer found/reproduced the diagnostic ownership bug before initial
publication; its fix and failure-cleanup regression are retained in history.

## Public source checkpoint

Initial public main `a032bbf2be047085f4ec7d7b8bcd811a8167297b` passed both
GCC/Clang hosted jobs in [CI 41907398317](https://github.com/carabistouflette/goose-check/actions/runs/41907398317).
A fresh HTTPS clone of that exact public source fetched/built its own pinned
compiler with `make setup`, then passed `make check test test-faults example
CC=gcc` and `make test test-faults example CC=clang`, without compiler overrides
or sibling sources. Both application and compiler trees remained clean.
Anonymous Git access, public visibility, default main, Apache-2.0 detection and
private vulnerability reporting were verified. The source archive contained 41
source/document/license files, no toolchain/build state, symlinks or executable
binaries. No release tag or stability promotion is implied by publication.

## Explicit configuration consumer

Feature `95dbfc5224f05527b54ce8d135df773144abd4bf` integrates the supported
goose-config API into this existing application. Follow-ups
`8f6df568a0f362108a950ee2b0a508dbc2c5b572` and
`a49857d996dc9978f06808d083efef07764ba8a1` add configured compiler workflows,
complete numeric-option order coverage, and atomic PID-readiness publication.
The latter prevents a controller from reading a newly created but empty marker.

The bundled goose-config pin is
`f7bef7dcfeab2ca95c94d92d0fbb2320ab3dcb05`. All ten vendored artifacts match
immutable upstream Git objects and the checked-in hash inventory, including
six unmodified runtime files, both complete licenses and nested parser notices.
Existing fs/process pins, native caller code, signal guards, compiler wrapper
and native source fingerprint are unchanged from `3dae698`.

The actual CLI suite now has ten test groups. Configuration checks include both
formats, both file/CLI orders for each numeric setting, tokens with more than 128
leading zeroes, exact 64KiB files and one-byte-over-limit failures, file/key
removal between invocations, strict types/ranges/duplicates, diagnostics without
raw values, configured output/expected-fixture limits and actual child timeout/
reaping. Rejected inputs use marker commands to prove no launch. Real C and
Goose compiler workflows use selected defaults. Existing binary-argument,
broken-stderr, cancellation and three ownership-fault scenarios remain active.

Reproduce with the compiler pinned in `GOOSE_REVISION`:

```sh
make check test test-faults example CC=gcc
make test test-faults example CC=clang
make sanitize SANITIZER_CC=gcc
make sanitize SANITIZER_CC=clang
make analyze
```

All commands above passed locally after the atomic readiness fix, including
release/debug and sanitizer runs of the ten CLI groups and three ownership
fault scenarios with each C compiler.

Independent design, contract and security/standards reviewers checked the
integration and frozen dependency provenance. Coverage feedback added timeout
and output-limit override cases; no checker/config runtime defect was found.
The repository contains 54 tracked source/document/license files and no generated
build/cache/binary assets. These are functional checks, not throughput or memory
measurements. The [configuration contract](CONFIGURATION.md) records I/O limits,
per-invocation rereads and the upstream incomplete sustained-fuzz release gate.

The follow-up anonymous checkout audit exposed a Makefile-only compiler override
bug: GNU Make's word-based `abspath` split an absolute `GOOSE` path containing
spaces before passing it to the CLI tests. The Makefile now passes the quoted
path unchanged to the test runner's existing `Path.resolve()` step, preserving
both relative and absolute compiler overrides. This does not change checker
execution or dependency sources.

## Streamed stderr integration, 2026-11-05

Starting from `32de6c4783bf8d3242e042993dadd160a98b2945`, the streamed-stderr
feature deliberately vendors reviewed public goose-process
`35b74eff63118abdd5b00603e1de4bf8ded110a2` from a clean credential-disabled
anonymous HTTPS clone. Every bundled file matches its immutable upstream Git
object and `vendor/pins.json`. This is a runtime/native dependency change;
goose-fs/config pins, app native caller, guard/recovery, compiler wrapper,
native fingerprint, numeric schema and pinned CI actions remain unchanged.
The previous config-only statements above describe their historical checkpoint.

The CLI now has 13 groups. New tests cover checked binary stderr across 8192-byte
chunk boundaries through 1 MiB; cap+1 including zero/max; both outputs exactly at
their independent caps; simultaneous finite input; mismatch offsets, prefix
directions, privacy and precedence; strict marker-backed prelaunch errors; both
config formats/CLI orders; and checked-mode timeout/SIGINT/SIGTERM with pidfd
proof of child disappearance. Independent ordinary C and pinned-Goose compiler
invocations supply exact diagnostic oracles for actual compiler workflows.

Ownership fault execution now has five scenarios: prestart cancellation and real
transferred-child recovery in inherited and checked modes, plus the existing
broken-diagnostic-stderr cleanup regression. Transfer traces require two denied
recovery waits, exclusive local termination/reaping, and guard preservation.

Normal release/debug tests and all faults passed with GCC and Clang. Both full
ASan/UBSan matrices also passed all 13 groups and five faults, including rebuilding
the app/process native sidecars under each instrumented compiler identity. The
existing real C example and Clang static analysis passed. Three independent
security/lifecycle, contract and final acceptance/provenance reviewers found no
actionable defect; review inspection is distinct from execution evidence.

A fresh local clone of `82f2b019bcae18c3338019374c5081d2e3abd722`, with spaces
in its checkout path and a fresh `GOOSE_HOME`, passed GCC and Clang release/debug,
fault and example execution. It reused the matching pinned existing compiler;
this is not a new compiler bootstrap or anonymous public-source execution claim.
The clone remained clean after its runs.

The [streamed-stderr contract](STREAMED_STDERR.md) specifies bounded chunks,
caller-enforced independent caps, output suppression and comparison precedence.
This consumer integration makes no throughput, allocation or RSS claim. It does
not complete any unrelated upstream fuzz/stability gate or create a release tag.
Hosted CI conclusions are reported separately by exact commit.
