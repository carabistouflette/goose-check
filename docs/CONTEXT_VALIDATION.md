# Context consumer qualification

The consumer uses bounded goose-diff context rendering at the full revision in
vendor/pins.json. --diff defaults to three context lines; `--diff-context N`
(0..4096) requires --diff and never changes comparison budgets. Original byte
matching, error precedence, stderr policy and the diagnostic cap remain covered.

Independent design/security review and independent test authorship check context
coordinates, split/merged hunks, omission of unrelated private/control content,
large fixtures fitting compact output, max-context omission and option scope.
The five new context test methods plus six existing diff methods pass against
the release binary. Full release qualification uses the existing normal/debug,
GCC/Clang, fault-injection, both ASan/UBSan configurations and static-analysis gates.

[All 180 raw real-command samples](../bench/results/context-alpha2/) retain exact
source/binary/toolchain identities, inputs and every slower result. Measured
source d096687 is clean; subsequent dependency-provenance updates preserve source
bytes. Workloads add actual pinned-compiler diagnostic transcripts, generated text
with one middle edit and scattered changes. Default and opt-in invocations
alternate on the same binary. Historical alpha.1 samples remain historical;
no old/new executable speed claim is made.

The comparison algorithm is unchanged. Library evidence keeps core budget
rejections visible. Timing/RSS on a shared host does not establish a general
speedup, isolated phase attribution or memory guarantee. Hosted CI and final
publication/catalog identity are separate gates recorded in the PR and receipt.
