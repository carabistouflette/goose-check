# Third-party notices

All project sources are Apache-2.0. `vendor/pins.json` records complete upstream
revisions and hashes for each bundled source, manifest, license and notice.

- goose-process: `470c23f8244d17ff2597bca3da35f3a98cc3ca50` (experimental v0.1.0).
- goose-fs: `910576e745e9ef4afc7807c4843ddc948836189a`.

Each dependency's Apache-2.0 license is retained in its vendor directory.
The project-specific notices there apply to the bundled sources. Their upstream
third-party descriptions describe those upstream distributions, not this repo.
Vendored files are byte-identical to the pinned Git objects. Local changes in
sibling checkouts are not imported.

Application cancellation and exceptional reaping code in `native/caller.c` is
adapted from Honk `453aa53dc7b20622782423c64cc180097f653650`,
`native/platform.c`, under Apache-2.0; see NOTICE and the root LICENSE.
Setup/fingerprint tooling adapts Apache-2.0 scripts from goose-process, goose-log
and goose-json, with attribution in NOTICE.

`make setup` downloads the Goose compiler at GOOSE_REVISION. Its source/build
lives under ignored `.toolchain/` and is not distributed here. This project uses
host Linux/glibc/pthreads; tests use Python, GCC and Clang. Those tools retain
their respective licenses and are not bundled as binaries.
