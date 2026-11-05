# Incremental stderr fixtures

Default stderr remains inherited and live. Select `--stderr ABSFILE` explicitly
to compare binary diagnostics as they arrive, suppressing raw child stderr:

```sh
printf 'diagnostic\n' > .build/expected.stderr
.build/goose-check --stderr "$PWD/.build/expected.stderr" -- \
  /usr/bin/python3 -c 'import sys; sys.stderr.write("diagnostic\n")'
```

The stderr fixture is a strict absolute bounded regular-file read, completed
before the signal guard and command launch. Missing, invalid, symlink, directory
or oversized fixtures cannot launch the command. Numeric CLI options override configuration defaults. Expected stdout still defaults to empty, and selected
stderr fixtures may contain NUL and invalid UTF-8 without conversion.

The checker uses immutable public goose-process
`35b74eff63118abdd5b00603e1de4bf8ded110a2`, with per-file hashes/licenses in
`vendor/pins.json`. Its Child uses Capture for stdout and Stream for selected
stderr, consuming 8192-byte chunks without retaining actual stderr in full.
The expected fixture is still retained, and captured stdout/finite stdin remain
bounded allocations. No RSS/allocation or speedup claim is made.

`output_limit` applies independently to stdout and selected stderr (64 KiB
default, 0..1 MiB). Two streams each exactly at the limit succeed. One extra
observed byte yields OutputLimit/125 and normal owned-child cleanup. Caller-side
stderr detection can read at most one 8192-byte chunk beyond the cap before
closing; that prefix is never emitted as a diagnostic. Per-call counts and
configured bounds prevent unbounded accumulation/counter growth.

Comparison remembers the first differing offset, including an extra actual byte
or a missing expected suffix. A mismatch alone does not stop the child: status
and both stream lengths remain meaningful under the deadline/cap. After cleanup,
parent cancellation takes precedence, then guard/process/launch errors, then
exit/signal mismatch, stdout mismatch and finally stderr mismatch. Mismatch
diagnostics contain only offsets and lengths. Timeout, simultaneous stdout
overflow or other process failure may discard unread diagnostics; their error
classification takes precedence over a pending stderr mismatch.

The 20ms normal-context loop latches/forwards cancellation by pidfd and consumes
any returned bytes before handling errors, and performs explicit transferred-PID
recovery while retaining the guard. Ordinary cleanup finishes before diagnostics
or exit. Direct-child-only supervision, filesystem/kernel timing limits,
best-effort terminal launch handoff and exceptional recovery limits still apply.

Tests cover binary/chunk boundaries, exact/overflow caps, independent streams,
copied input, mismatch offsets/privacy, precedence, strict no-launch fixture
failures, both config formats/CLI orders, timeout/cancellation and ownership faults.
Inherited-stderr tests check default live behavior.
