# Security

Report suspected vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/carabistouflette/goose-check/security/advisories/new).
Do not include credentials or confidential fixtures in public issues. There is
no production stability/security-support promise for this experimental project.

The executable, arguments, environment/cwd and fixture paths are trusted local
inputs. This tool is not an execution sandbox or environment sanitizer. It keeps
stdin/stdout payloads bounded, avoids an implicit shell/PATH policy, and owns its
direct child until cleanup or explicit local recovery. Stderr is inherited and
may contain any data written by the chosen child. File operations have no total
budget and special-path opens may have OS side effects before type rejection.

Only the direct child is supervised. External SIGKILL or other unhandled fatal signals, fatal runtime
failures, descendant processes, terminal launch-window ambiguity, hostile
external reapers, concurrent changes to signal dispositions and thread
cancellation are outside the normal ownership guarantee. Permission denial may
prevent cleanup indefinitely; the recovery owner retains scope and diagnoses it
instead of silently abandoning a child. See docs/CONTRACT.md.
