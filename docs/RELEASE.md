# v0.1 release policy

v0.1.0 is the first tagged source release. Implementation and vendored dependencies
are unchanged from 91de39cd68fc532ec47d6f5cd8590d33488b9032.

CONTRACT.md and its linked CONFIGURATION.md, STREAMED_STDERR.md and STDOUT_DIFF.md
define the supported CLI. Within v0.1.x patches preserve existing invocations,
flags/grammar/defaults/ranges, configuration schema/precedence, fixture byte/path
rules, exit and error precedence, disclosure/escaping and diff ordering rules,
direct-child ownership and documented resource units. LCS stays default; sparse
stays explicit without fallback. A standalone --help remains supported.
Exact usage/diagnostic prose, internal helpers, build paths, compiler ABI and
generated code are not stable interfaces. Scripts should use status codes and
documented behavior rather than parse human-readable diagnostics.

Patch releases may correct violations of the documented contract; test and record
corrections in the changelog. Additions must preserve existing supported calls.
Breaking contracts require a new minor version and migration notes. This is a
project commitment for v0.1.x, not a claim that pre-1.0 Semantic Versioning requires
stability. No support SLA is provided. Vendored upstream interfaces can remain
experimental without changing this CLI commitment.

## Platform and resource scope

Qualification covers Linux x86-64/glibc with the pinned GOOSE_REVISION compiler,
GCC and Clang. Runtime requires glibc 2.34+ and working pidfd support (kernel
5.3+); build headers must provide openat2 definitions. The filesystem adapter
has a checked fallback when openat2 is unavailable. Minimum versions are
requirements, not a claim every such system was tested. OS policy can deny
required syscalls. Other platforms/compiler revisions remain unqualified.
README.md lists source-build prerequisites. No portable/reproducible-binary
or exact RSS guarantee is made.

Commands, paths and inherited environment/cwd are trusted inputs. Only the direct
child is supervised; this is not a sandbox. The process deadline is a cancellation
budget, not a total wall-clock limit. Filesystem work and exceptional cleanup can
overrun it; denied cleanup may wait indefinitely rather than abandon ownership.
Payload/diff-work caps do not bound allocator capacity or runtime OOM. Explicit
--diff reveals escaped expected/actual stdout and context; escaping does not
protect confidentiality. Read CONTRACT.md and SECURITY.md for remaining limits.

## Publication gates

1. Clean standalone clone: make setup at the exact compiler pin, then README
   build/stdin/stdout smoke and a copied executable invoked outside the checkout.
2. Run make check test test-faults with CC=gcc and CC=clang; make sanitize with
   SANITIZER_CC=gcc and SANITIZER_CC=clang; make example with each compiler;
   make analyze; git diff --check. One Make invocation at a time per checkout.
   A writable TMPDIR with adequate space may be selected.
3. Check vendored identities/licenses/notices and private vulnerability reporting.
   Obtain independent CLI/security and release-readiness review and green hosted
   GCC/Clang CI for the exact reviewed candidate before tagging.
4. Publish immutable v0.1.0 and a non-prerelease GitHub source release. Never move
   published tags. Clone the public tag and repeat inventory/build/README smoke,
   verify its resolved commit, and retain identities/results in the catalog receipt.
   Correctness tests establish no comparative performance ranking.
