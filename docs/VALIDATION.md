# Validation scope

The maintained tests run the compiled CLI, not a Python substitute for its
process behavior. Release and debug builds check exact binary fixtures, finite
stdin EOF, independent inherited stderr, stdout bounds, exit statuses, literal
argument boundaries, prelaunch errors, no shell fallback, timeouts, and direct
SIGINT/SIGTERM to the checker. Child pidfds are acquired during private-session
readiness before cancellation; gone identities are checked after the checker
returns. The controller bounds waits, owns unreaped session leaders for failure
cleanup, and checks its own descriptors and unwaited children.

The actual compiler cases feed C source through finite stdin into the host C
compiler, check its produced binary, and invoke the pinned Goose compiler for
positive and negative source fixtures. These are practical command/compiler
checks; no compile-time or cross-tool speedup claim follows.

A separate content-fingerprinted fault binary injects a prelaunch pending signal
and a post-start clock failure followed by denied library cancellation. The
latter really transfers ownership, denies two local recovery waits, checks the
SIGCHLD/parent guard is retained, then permits owned signaling/terminal reaping.
The trace enforces order and no signal after terminal ownership ends. Fault
hooks are absent from production builds. Denials are selected simulations,
not blanket syscall restrictions or real credential changes.

A security reviewer reproduced a live-child abandonment in an initial unpublished
bridge: a recovery diagnostic to broken stderr received SIGPIPE before reaping.
Application diagnostic writes now have scoped SIGPIPE protection. The regression
requires terminal reaping and recovery completion with a silent long-lived child
and no stderr reader. Its private test subreaper and reserved-session cleanup
also recover adopted children if this behavior regresses. Normal CLI failures
still return their defined status when diagnostic stderr is broken.

Compiler wrappers freeze the actual compiler path/bytes, wrapper source,
instrumentation and fault-fixture bytes into distinct filenames. This matters
because Goose identifies a toolchain using its path/style/version, rather than
all wrapper contents/environment. Build logs show all three native packages
being rebuilt for a new sanitizer/fixture identity.

The GCC and Clang sanitizer targets cover generated C and all native packages
with ASan/UBSan, -O1 and fortification. Debug Goose checks remain enabled in the
debug tool. This does not independently prove all logical bounds/lifetimes in
Goose's mmap-backed data stacks. Expected-byte oracles, debug checks and reviews
complement sanitizers. Current CI is Linux x86-64; no Windows/macOS guarantee.
Native static analysis targets application-owned caller policy.

All inputs/results for correctness are checked in or deterministically generated
by tests. See the Makefile for exact commands and GOOSE_REVISION/vendor/pins.json
for source identities. No throughput benchmark has been recorded, and resource
caps are payload bounds rather than exact RSS limits. File I/O, inherited stderr,
OS work, exceptional recovery and descendant-held captures retain the limits in
the contract. The recorded prepublication evidence below is separate from hosted CI.


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
