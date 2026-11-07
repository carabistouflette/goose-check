# Contributing

Keep the CLI small and explicit. Preserve byte boundaries, prelaunch fixture
validation, capture/input limits, finite process budgets and exclusive child
ownership. No implicit shells, PATH search, environment scrubbing, process-group
supervision or library-global signal policy. Application handlers only latch
flags. Never signal cached numeric library-owned PIDs. Transferred ownership is
a distinct owner; prove terminal reaping/ECHILD before returning or restoring
the guard. Document unavoidable caller/OS limitations honestly.

Use focused branches and Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`,
`chore:`). Commit coherent changes regularly. Tests must exercise actual CLI
behavior and meaningful error paths, not mirror implementation helpers.
Use clear names and small functions; avoid speculative configuration/abstraction.

Before publication, run normal release/debug tests and faults with GCC/Clang,
both sanitizer targets, static analysis and whitespace checks. Native/script
changes refresh the package fingerprint with `make format`. Changes to the
compiler wrapper must continue hashing the real compiler, wrapper contents,
instrumentation and fault sources into its identity. Do not change ignored
compiler wrappers in place as a substitute for a new content identity.

Dependencies are vendored immutable upstream Git objects with full revisions
and per-file hashes in vendor/pins.json. Update them deliberately with review,
licenses/notices and the complete validation matrix. Never copy dirty sibling
sources or modify them from this project. Do not commit builds, caches, secrets,
private coordination notes or unrelated workspace files.

Meaningful behavior/ownership changes require independent security and contract
review. Profiles must keep raw inputs/results and precise provenance; avoid
unverified speed claims. Preserve the supported [v0.1.x contract](docs/RELEASE.md) in patch releases;
review compatibility explicitly before changing user-visible behavior.
