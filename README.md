# goose-check

A small command-regression checker written in Goose. Feed a binary stdin fixture,
compare exact stdout and exit status, and keep stderr live by default. Optionally
check stderr incrementally against a fixture. Useful for compiler
and CLI tests in Makefiles or CI. Apache-2.0; experimental, with no release tag.

```sh
git clone https://github.com/carabistouflette/goose-check.git
cd goose-check
make setup
make build
printf 'hello\n' > .build/hello
.build/goose-check --stdin "$PWD/.build/hello" --stdout "$PWD/.build/hello" -- /bin/cat
```

Success is quiet and exits 0. A mismatch exits 1 and reports its first differing
byte offset, lengths or exit/signal status on stderr. Fixture/argument contents
are not echoed in checker diagnostics. The command's stderr is intentionally
inherited, so compiler diagnostics and progress remain live.
With `--stderr ABSFILE`, diagnostics are instead checked as bounded chunks arrive;
raw child stderr is suppressed in that explicit mode. See [streamed checking](docs/STREAMED_STDERR.md).

## Compile and check a real program

`make example` feeds [echo.c](examples/echo.c) to the host C compiler through
finite stdin, then checks the resulting executable with a binary fixture:

```sh
make example CC=gcc
```

The integration tests also check valid and invalid Goose programs using the
pinned Goose compiler. This is a standalone consumer of goose-process,
goose-fs and goose-config, with dependency sources bundled at exact commits. Builds do
not fetch library dependencies. The compiler is downloaded by `make setup`.

## Interface

```text
goose-check [options] -- /absolute/program [arguments...]

--stdin ABSFILE       finite stdin fixture (default: empty; maximum 1 MiB)
--stdout ABSFILE      expected stdout (default: empty; bounded by output-limit)
--stderr ABSFILE      opt-in expected stderr (default: inherited live)
--expect-exit N       expected normal exit, 0..255 (default: 0)
--timeout-ms N        finite process budget, 1..86400000 (default: 30000)
--output-limit N      independent limit for each checked stream, 0..1048576 (default: 65536)
--config ABSFILE      explicit .json/.toml numeric defaults (maximum 64 KiB)
```

Options may occur once each. `--` is required. Executable paths must be absolute;
there is no implicit shell or PATH lookup. Command arguments preserve their byte
boundaries, including empty arguments. Environment and cwd are inherited and
trusted. A child exit 126/127 is an ordinary test outcome, distinct from a launch
failure. Exit codes: 0 match, 1 mismatch, 2 usage, 125 checker/process/fixture
error, 126 failed launch, 127 missing executable. Parent SIGINT/SIGTERM status
wins as 128+signal after cleanup.

Fixtures must use strict absolute paths: no symlink traversal, `.`/`..`, repeated
separators or trailing separator. They are bounded regular-file reads without
text/newline conversion. Invalid or unreadable fixtures fail before launch.
Filesystem operations have no deadline; the process budget starts later. See
the complete [contract](docs/CONTRACT.md).

For shared numeric defaults, use `--config "$PWD/examples/checker.toml"`.
The file can set only `timeout_ms`, `output_limit` and `expect_exit`; CLI values
take priority regardless of order. There is no implicit file discovery or
environment binding. Invalid selected files fail before command launch.
See [configuration contracts and examples](docs/CONFIGURATION.md).

The app forwards parent cancellation through pidfds and keeps ownership through
cleanup. It supervises only the direct child. Descendants are not killed and may
hold stdout open until timeout. The budget is not a hard wall-clock guarantee;
kernel/filesystem work and exceptional reaping can overrun it. Terminal launch
window duplicate suppression is best effort. This tool executes trusted programs
and is not a sandbox. Exceptional OS permission denial may require indefinite
recovery rather than abandoning a child.

## Build and validation

Requires 64-bit Linux/glibc 2.34+, kernel pidfds (5.3+), Linux headers providing
openat2, Git, Make, CMake 3.27+, C/C++20 compilers and Python 3.11+. The pinned
compiler revision is in GOOSE_REVISION. Other revisions are not promised.

```sh
make check test test-faults CC=gcc
make test test-faults CC=clang
make sanitize SANITIZER_CC=gcc
make sanitize SANITIZER_CC=clang
make analyze
```

Tests exercise actual release/debug CLI binaries, binary/exact-limit fixtures,
no-launch errors, nonzero exits versus launch failures, live stderr, timeout and
parent signal cleanup, C/Goose compiler invocations and selected ownership-transfer
faults. Sanitizers instrument application, dependency sidecars and generated C.
Goose's mmap-backed data stacks mean sanitizers alone are not a complete check
of logical Goose array bounds; debug builds and independent expected bytes also
matter. [Validation evidence](docs/VALIDATION.md) records scope and limitations.
No universal performance or absence-of-bugs claim is made.

An existing matching compiler can be selected with `make GOOSE=/absolute/goose`.
Use one Make invocation per checkout: Goose's generated outputs are shared.
The generated CC wrapper path includes compiler bytes, instrumentation settings
and fault-fixture source so normal/sanitized/test caches have distinct identities.
Generated toolchains, build outputs and wrappers stay ignored.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
[dependency notices](THIRD_PARTY.md) and [LICENSE](LICENSE).
