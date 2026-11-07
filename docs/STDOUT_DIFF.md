# Opt-in stdout differences

Pass `--diff` once before `--` to add escaped line differences when stdout bytes
mismatch. Exact byte comparison, existing mismatch metadata and exit code 1 remain
authoritative. With no flag diagnostics omit fixture contents. There is no config
key or implicit environment setting for this option.

The default retains up to three unchanged context lines around each change.
`--diff-context N` selects 0..4096 context lines and requires `--diff`; either
option order is accepted, duplicates/invalid values fail before fixture loading
or launch. There is no config key for context. Touching/overlapping hunk windows
merge; separated changes produce separate headers. Zero omits all equal context.
`--diff-algorithm lcs|sparse` explicitly selects the strategy and requires --diff.
Default lcs retains prior limits and exact edit ordering. Explicit lcs is equivalent
to omission. Values are exact lowercase; missing/invalid/duplicate selection fails
before fixture reads or launch. There is no algorithm config key or environment
selection. Sparse never automatically falls back to LCS (nor the reverse).
Input, line, compared-byte and output caps remain unchanged.

This explicitly discloses expected and actual changed stdout plus selected context.
Treat logs accordingly. Diffing is byte-based: LF terminates lines; final-newline
presence matters, CRLF is preserved and there is no Unicode normalization.
Control bytes, DEL, non-ASCII bytes and backslash are escaped as uppercase
`\xHH`; LF remains a line break. The block is labeled escaped diagnostics, not
an applicable patch. Labels are fixed; fixture paths are never included.

The additional block is capped at 16,384 bytes including its header and any
truncation marker, excluding the existing mismatch metadata line. Tokens are
complete; truncation is explicit. All raw context hunks together are separately
capped at 16,384 bytes. Library budgets: 65,536 bytes and 4,096 lines per input,
1,048,576 compared byte pairs, and either 262,144 LCS matrix cells (including
sentinels) or a separately named 262,144-slot sparse trace bound. Sparse admits
whole retained frontier rows including unreachable/unvisited positions, so state
exhaustion still bounds work when length mismatches compare no bytes.
Matrix work and input scanning have separate bounds; byte comparisons are not an
instruction or wall-clock budget. Oversized inputs, work, matrix or raw output
produce one fixed omission note. Normal byte comparison checks the entire capture,
up to the existing process cap. Logical LCS matrix or sparse trace storage is at most 2 MiB;
allocator overhead, capacity and runtime OOM are outside these limits. Context planning additionally uses bounded
per-line rows and hunk descriptors (at most 327,704 logical bytes at the consumer
line limits); allocator capacity is separate.

Diffing runs only after direct-child cleanup and guard restoration. Process,
launch, signal or expected-exit failures take priority and do not render a diff.
Neither matching stdout nor stderr-only mismatches emit one. Stderr capture and
its inherited/checked modes retain their contracts. Diagnostic writes can block;
the child-process deadline does not cover filesystem or diagnostic I/O.

The portable goose-diff sources and notices are pinned by complete upstream
revision and SHA-256 hashes in vendor/pins.json. No build-time dependency fetch
is required. See THIRD_PARTY.md and the vendored LICENSE/NOTICE.

Sparse minimizes the same inserted/deleted line cost but its deterministic
frontier tie rule can select different valid hunks, including insertion before
deletion in a replacement. Dense rewrites can be slower or hit sparse states
where LCS succeeds. For example, 400 entirely changed short lines fit the LCS
matrix but exceed the sparse trace cap. This yields the same fixed omission note
and mismatch exit 1; selection does not grant fallback or unlimited search.
Choose lcs when its exact diagnostic ordering is required. Earlier experimental
speed results are not a guarantee for complete command invocations.
