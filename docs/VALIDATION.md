# Validation scope

The maintained tests run the compiled CLI, not a Python substitute for its
process behavior. Release and debug builds check exact binary fixtures, finite
stdin EOF, independent inherited stderr, stdout bounds, exit statuses, literal
argument boundaries, prelaunch errors, no shell fallback, timeouts, and direct
SIGINT/SIGTERM to the checker. Opt-in stdout diff cases check byte escaping,
disclosure defaults, truncation, resource-limit omission, option placement and
error precedence. Child pidfds are acquired during private-session
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
the contract. Earlier execution records are kept separately below.


## Historical published implementation

This earlier validation snapshot records
`713e2749ded459b915f59012aaa6e19351a17b18`. Its separate
[feature push workflow](https://github.com/carabistouflette/goose-check/actions/runs/41988650239)
and [PR workflow](https://github.com/carabistouflette/goose-check/actions/runs/41988708204)
completed successfully with GCC and Clang. Documentation edits do not change
application, native or bundled dependency sources.

[Historical checks](VALIDATION-HISTORY.md) retain the earlier compiler/configuration/
streaming records and exact revisions. See [performance scope](PERFORMANCE.md)
for the distinction between functional checks and measurements.

Current release gates include the full matrix, both compiler examples and a
clean-checkout setup/build/README smoke. Exact source/compiler identities, CI and
post-tag checks are recorded in the release PR and catalog receipt. See
[publication policy](RELEASE.md). Historical evidence retains its original source.
