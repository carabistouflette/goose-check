# Explicit checker defaults

`--config ABSFILE` loads a JSON or TOML file for goose-check's numeric defaults.
The lowercase `.json` or `.toml` suffix selects the parser. There is no implicit
discovery, environment binding, recursive include or command declaration.

```toml
# examples/checker.toml
timeout_ms = 60000
output_limit = 65536
expect_exit = 0
```

Equivalent JSON: `{"timeout_ms":60000,"output_limit":65536,"expect_exit":0}`.
Run a trusted command with these defaults:

```sh
.build/goose-check --config "$PWD/examples/checker.toml" -- /bin/true
```

Numeric CLI options override the file regardless of option order:

```sh
.build/goose-check --expect-exit 1 --config "$PWD/examples/checker.toml" -- /bin/false
```

Executables, arguments and input/expected fixture paths remain explicit CLI
inputs; the file cannot supply them. `make example` uses these defaults to
compile and check a real C program. The CLI suite also uses selected defaults
with valid and invalid pinned-Goose compiler invocations.

`output_limit` applies independently to captured stdout and opt-in checked stderr.
`--stderr ABSFILE` is a CLI fixture option; the config schema has no new keys and
cannot enable stderr checking. Stderr remains inherited live when it is absent.

## Values and precedence

| Field | Built-in default | Accepted values |
| --- | ---: | --- |
| `timeout_ms` | 30000 | Integer 1–86400000 |
| `output_limit` | 65536 | Integer 0–1048576 |
| `expect_exit` | 0 | Integer 0–255 |

Layer order: built-in defaults, the selected file, then supplied numeric flags.
Missing fields use built-in defaults. The file is a flat object/table of these
three integers. Unknown fields/tables/objects, duplicates, lists, strings,
booleans, floats and out-of-range values are rejected even when CLI flags would
override them. JSON fractional/exponent tokens are Float, not Integer, even if
their mathematical value is integral. TOML retains its own integer syntax.

CLI numeric values retain the existing ASCII-digits-only grammar, including
leading zeroes. Validated numbers are converted to canonical decimal before
being passed to goose-config, so its scalar token limit does not shorten the
accepted CLI grammar. Each invocation rereads the file; removed keys expose
defaults, and a removed selected file causes an error. There is no retained
history, watcher or live reload loop in this single-command application.

## Failures and I/O boundaries

All three resulting settings are staged before assignment. Configuration
processing finishes before fixture reads, signal-guard setup and child launch.
Rejected files never launch a command. The configured output limit also bounds
expected-stdout fixture reads, as the equivalent CLI flag did previously.

- Exit `2`: malformed/repeated/missing options, invalid path syntax/suffix,
  document parsing, duplicate, unknown-field, type or range failures.
- Exit `125`: failed bounded regular-file reads, including missing files,
  symlinks, directories and files larger than 65,536 bytes.

The same strict absolute path/no-symlink policy as fixture reads applies.
Paths are trusted local inputs. File reads have no deadline or snapshot
guarantee against concurrent writers; replace files atomically. The process
budget starts after config/fixture preparation, not at checker startup.
Diagnostics use fixed classifications without paths, file contents or parser
details. The trusted command's stderr remains inherited. Existing cancellation,
child ownership and argument/fixture contracts remain in [CONTRACT.md](CONTRACT.md).

## Dependency and checks

The bundled goose-config sources are exact Git objects at
`f7bef7dcfeab2ca95c94d92d0fbb2320ab3dcb05`, with per-file hashes in
`vendor/pins.json`, complete licensing and nested parser notices. The six runtime
files are unmodified. Existing process/fs pins are unchanged; no library fetch
or sibling checkout is a build input. Only supported config APIs are used.

The actual CLI suite covers both formats and option orders, long leading-zero
tokens, exact/oversized files, file/key removal, malformed/duplicate/type/range
failures, configured output/fixture limits and timeout/reaping. Marker commands
prove rejected inputs never launch. Existing compiler, cancellation,
broken-stderr and ownership-transfer fault tests remain in the compiler matrix.

Without `--config`, no file is read or parsed. Linking parsers can still change
binary size/layout/startup; no unchanged-latency or throughput claim is made.
This deterministic consumer suite does not complete goose-config's outstanding
sustained-fuzz release gate.
