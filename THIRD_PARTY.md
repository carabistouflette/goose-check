# Third-party notices

All project sources are Apache-2.0. `vendor/pins.json` records complete upstream
revisions and hashes for each bundled source, manifest, license and notice.

- goose-process: `35b74eff63118abdd5b00603e1de4bf8ded110a2` (reviewed streaming implementation; experimental, no new tag).
- goose-fs: `910576e745e9ef4afc7807c4843ddc948836189a`.
- goose-config: `f7bef7dcfeab2ca95c94d92d0fbb2320ab3dcb05` (experimental, untagged).
  Its nested goose-toml parser license, modification notice and upstream
  attribution are retained in `vendor/goose-config/vendor/` and
  `vendor/goose-config/THIRD_PARTY_NOTICES.md`.

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

- goose-terminal at `51e09f5010ece452ae42f184220b027ee67d777e` (Apache-2.0),
  https://github.com/carabistouflette/goose-terminal; see vendor/goose-terminal/LICENSE
  and NOTICE. Optional result summaries use the rendering core and POSIX adapter.
