# Stdout diff qualification

Production behavior was introduced at `2266217`; documentation/harness checkpoint
`93ae35f` preserves that code. Local normal/debug GCC and Clang, fault injection,
GCC/Clang ASan/UBSan, and static analysis pass with compiler
`eadca409f68210893f366e60d0c2f0dc29a339be` (clean source).

Independent reviews checked design, escaping, bounded work/output, disclosure,
cleanup ordering, default compatibility and error precedence. Real CLI tests
exercise exact default diagnostics, opt-in goldens, binary escaping, truncation,
each omission budget, malformed flags and unchanged process/stderr precedence.
Review feedback corrected the main contract and historical performance wording.

Raw real-command measurements and fixtures are retained under bench/results.
The initial sample provenance honestly records concurrent uncommitted test/doc
edits in a shared checkout; production files were verified byte-identical to the
committed candidate. A separate clean candidate is used for publication. All
samples, including slower runs, remain retained. They establish no speedup or
peak-memory guarantee. Read the harness scope before interpreting timings/RSS.

Hosted CI and the exact final publication pin are independent gates recorded
in the consumer PR and catalog registration receipt. The dependency is immutable
upstream goose-diff `ba87b7d84dedfb7e90b42a95a473baaa3f95b7ee`.
