# Security

Report suspected vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/carabistouflette/goose-check/security/advisories/new).
Do not include credentials or confidential fixtures in public issues. There is
no production stability/security-support promise for this experimental project.

The executable, arguments, environment/cwd and fixture paths are trusted local
inputs. This tool is not an execution sandbox or environment sanitizer. It keeps
stdin/stdout payloads bounded, avoids an implicit shell/PATH policy, and owns its
direct child until cleanup or explicit local recovery. Stderr is inherited by default and
may contain any data written by the chosen child; `--stderr` selects checked,
suppressed output instead. File operations have no total
budget and special-path opens may have OS side effects before type rejection.

Explicit `--config` files are read as bounded regular files with a 65,536-byte
cap. Strict schemas accept only the three numeric checker defaults. Parsing and
validation finish before fixture reads or child launch; diagnostics omit file
contents and paths. Config paths remain trusted local inputs, reads have no
deadline or concurrent-writer snapshot guarantee, and the process budget starts
later. Config cannot declare commands, arguments or fixture paths. See
[configuration boundaries](docs/CONFIGURATION.md).

Only the direct child is supervised. External SIGKILL or other unhandled fatal signals, fatal runtime
failures, descendant processes, terminal launch-window ambiguity, hostile
external reapers, concurrent changes to signal dispositions and thread
cancellation are outside the normal ownership guarantee. Permission denial may
prevent cleanup indefinitely; the recovery owner retains scope and diagnoses it
instead of silently abandoning a child. See docs/CONTRACT.md.

Explicit `--diff` discloses expected/actual stdout, including equal context, as
escaped diagnostics capped at 16 KiB. Escaping controls terminal bytes, not data
confidentiality. Resource exhaustion omits the diff and preserves mismatch status.
See [stdout diff boundaries](docs/STDOUT_DIFF.md).

`--diff-algorithm sparse` is explicit and requires --diff. Its complete trace
rows are bounded independently from LCS matrix cells, including byte-free length
mismatches. There is no fallback or automatic strategy selection. Dense inputs
can exhaust sparse states even when LCS succeeds. Escaping and the 16 KiB cap
remain unchanged; selected stdout/context is still disclosed intentionally.
