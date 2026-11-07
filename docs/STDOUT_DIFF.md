# Opt-in stdout differences

Pass `--diff` once before `--` to add escaped line differences when stdout bytes
mismatch. Exact byte comparison, existing mismatch metadata and exit code 1 remain
authoritative. With no flag diagnostics omit fixture contents. There is no config
key or implicit environment setting for this option.

This explicitly discloses expected and actual stdout, including unchanged context.
Treat logs accordingly. Diffing is byte-based: LF terminates lines; final-newline
presence matters, CRLF is preserved and there is no Unicode normalization.
Control bytes, DEL, non-ASCII bytes and backslash are escaped as uppercase
`\xHH`; LF remains a line break. The block is labeled escaped diagnostics, not
an applicable patch. Labels are fixed; fixture paths are never included.

The additional block is capped at 16,384 bytes including its header and any
truncation marker, excluding the existing mismatch metadata line. Tokens are
complete; truncation is explicit. The raw full-file unified hunk is separately
capped at 16,384 bytes. Library budgets: 65,536 bytes and 4,096 lines per input,
262,144 matrix cells including sentinels, and 1,048,576 compared byte pairs.
Matrix work and input scanning have separate bounds; byte comparisons are not an
instruction or wall-clock budget. Oversized inputs, work, matrix or raw output
produce one fixed omission note. Normal byte comparison checks the entire capture,
up to the existing process cap. Logical scratch matrix storage is at most 2 MiB;
allocator overhead, capacity and runtime OOM are outside these limits.

Diffing runs only after direct-child cleanup and guard restoration. Process,
launch, signal or expected-exit failures take priority and do not render a diff.
Neither matching stdout nor stderr-only mismatches emit one. Stderr capture and
its inherited/checked modes retain their contracts. Diagnostic writes can block;
the child-process deadline does not cover filesystem or diagnostic I/O.

The portable goose-diff sources and notices are pinned by complete upstream
revision and SHA-256 hashes in vendor/pins.json. No build-time dependency fetch
is required. See THIRD_PARTY.md and the vendored LICENSE/NOTICE.
