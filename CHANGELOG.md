# Changelog

## v0.35.4-ps.1 — 2026-09-04

- Bumped the pinned upstreams to sharp v0.35.4 and sharp-libvips v1.3.3
  (libvips 8.18.6, glib 2.89.4). Both patches applied unchanged.
- Hardened the workflows: every Action pinned to a full commit SHA,
  `contents: read` by default with the release job elevating itself,
  `persist-credentials: false` on each checkout, non-cancelling concurrency for
  releases, and a validated `workflow_dispatch` ref so a dispatch cannot tag an
  arbitrary branch.
- Disabled setup-node's package-manager cache explicitly. It caches npm by
  default whenever `package.json` names npm via `packageManager` or
  `devEngines.packageManager` — neither is set today, but adding one would
  silently switch caching on in the workflow that publishes digest-pinned,
  attested binaries.
- Added `.npmrc` with `ignore-scripts=true` and `min-release-age=14`, and
  `check-workflows.yml`, which runs zizmor over this repo's own workflows.

## v0.35.3-ps.2 — 2026-08-27

Initial PhotoStructure build, derived from
[janhapke/sharp-electron](https://github.com/janhapke/sharp-electron) — see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

- Builds a patched `sharp` addon and `libvips` for `linux-x64` from the upstream
  commits pinned in [versions.env](versions.env): sharp v0.35.3, sharp-libvips
  v1.3.2 (libvips 8.18.3, glib 2.89.1).
- Emits two binaries into `out/linux-x64/` rather than publishing an npm package.
  Consumers swap them into a stock `sharp` install; no `overrides` entry and no
  `package.json` change is needed. See README.md's "Use it".
- Replaced git submodules with `scripts/fetch-sources.sh`, which clones the pinned
  commits into `.work/`.
- Pinned the `electron` devDependency to 43.4.1, the version PhotoStructure ships. The
  Electron crash-regression gate had been running against `^33.0.0` (33.4.11), so it was
  not validating the runtime we actually release on.
- Releases are built and published by GitHub Actions with a signed
  build-provenance attestation, rather than uploaded from a workstation. Tags use
  `-ps.N` so they cannot collide with the `-electron.N` tags this fork inherits.
- Passes `--user` to every `docker run` this repo controls, so builds stop leaving
  root-owned files in the work tree. sharp-libvips's own `build.sh` does not, so
  `scripts/clean.sh` deletes from inside a container instead of requiring `sudo`.
