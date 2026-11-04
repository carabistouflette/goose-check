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
the contract. Fresh-clone/publication evidence will be recorded once validated.
