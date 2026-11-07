# Explicit sparse consumer qualification

The source adds an explicit selector; LCS remains the default. The immutable
library revision and file hashes are in vendor/pins.json. The library now supplies
its own sparse::Limits instead of borrowing LCS max_cells semantics.

Seven independently authored CLI methods plus the existing diff methods check
explicit/default LCS identity, sparse tie ordering, four far-edit recoveries with
independent no-fuzz patch application, and a dense no-fallback guard. They also
cover strict prelaunch option validation, byte/work/trace/output limits, binary
escaping/truncation, config/child scope and process/stderr error precedence.
All 19 targeted diff methods pass. Full release qualification runs normal/debug
GCC/Clang, ownership/fault tests, both ASan/UBSan configurations and static analysis.

Independent design, source/security and test reviews found no code blocker.
Review feedback marks alpha.2 context evidence historical instead of implying
that the current selector leaves all consumer source bytes unchanged. Separate
library tests retain exhaustive/exponential/LCS correctness oracles, hard bounds
and 9,585 LCS/sparse no-fuzz patch round trips.

Local validation encountered /tmp quota errors in Clang temporary objects and
GNU patch scratch output. Those failure logs are retained; affected checks use
a workspace TMPDIR on rerun, without source or compiler-wrapper changes. This is
an environment qualification detail, not a relaxed product limit.

[Strategy measurement methodology](../bench/README.md) records default, explicit
lcs and explicit sparse on one unsanitized binary. Every omission and slower run
stays labeled. No end-to-end speedup or memory guarantee is claimed. Historical
experimental timings remain on their isolated branch; automatic strategy choice
and fallback are not introduced.

Hosted exact-source CI, clean public clone and final publication/catalog pins
remain separate gates recorded in the PR and parent receipt.
