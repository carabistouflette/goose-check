# Command checker contract

`goose-check [options] -- /absolute/program [arguments...]` checks one trusted
command. It feeds a finite binary stdin fixture, compares bounded captured
stdout byte-for-byte with an expected fixture and checks a normal exit status.
Stderr remains inherited and live. Commands are not parsed by a shell; PATH is
not searched. Environment/cwd are inherited and trusted. This is not a sandbox.

Options, each accepted at most once:

- `--stdin ABSOLUTE_FILE`: default empty input; at most 1 MiB.
- `--stdout ABSOLUTE_FILE`: default empty expected output; at most output-limit.
- `--expect-exit INTEGER`: default 0, range 0..255.
- `--timeout-ms INTEGER`: default 30000, range 1..86400000.
- `--output-limit INTEGER`: default 65536, range 0..1048576.
- `--config ABSOLUTE_FILE`: opt-in `.json`/`.toml` numeric defaults, at most
  65,536 bytes. Supplied numeric flags override these defaults regardless
  of option order; see [configuration](CONFIGURATION.md).

A literal `--` is required before the executable; subsequent argument bytes and
empty arguments retain their boundaries. Numeric options accept decimal digits
only. Duplicate/unknown options, missing values, invalid bounds and nonabsolute
executables fail before launch. Normal library argv bounds also apply.

Fixture loading finishes before launch. goose-fs requires strict absolute paths:
no repeated/trailing separators, dot/dot-dot components or symlink traversal.
Only regular files are accepted, with no newline or encoding normalization.
Filesystem reads have no deadline and opening a special path can have OS effects
before its file type is rejected. Treat fixture paths as trusted local inputs.

Exit codes: 0 match; 1 stdout/exit/signal mismatch; 2 usage; 125 fixture/process/
checker failure; 126 failed executable launch; 127 missing executable/cwd.
Child exits 126/127 are ordinary outcomes that can match --expect-exit.
A latched parent SIGINT/SIGTERM wins as 128+signal after child cleanup. Diagnostics
contain mismatch offsets/lengths and error classifications, never raw fixture,
argument or environment contents. Child stderr is intentionally inherited.
Checker diagnostics are best effort: a broken stderr pipe cannot abort owned
cleanup. The standalone application temporarily ignores SIGPIPE around its own
diagnostic writes, then restores its prior disposition; no spawn occurs during
those writes. The spawned command retains its own normal signal policy.

A scoped application signal guard is established before start. Handlers only
latch flags. A normal Child step loop forwards signals by pidfd and always
finishes/closes its owner. Already-reaped identities are never signaled.
SIGCHLD is normalized until cleanup ends. A failed start or operation can transfer
an unreaped child; a separate local recovery owner retains the guard until
terminal wait/ECHILD, with diagnostics/backoff on persistent denial. Such recovery
may wait indefinitely rather than abandon ownership.

Only the direct child is supervised. Descendants retaining stdout may cause a
capture timeout after it exits. The process timeout starts after fixture/argument
preparation and is a cancellation budget, not a total wall-clock promise.
Filesystem work, kernel calls and exceptional recovery may overrun it.
Inherited stderr may block the child, which remains subject to process deadline.
Terminal Ctrl-C duplicate suppression is best effort: an event in the launch
window or a concurrent group change cannot be classified perfectly. No job
control, process-group cleanup, signal-storm guarantee or watchdog is provided.
