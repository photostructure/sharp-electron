# Changelog

## Unreleased

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
- Passes `--user` to every `docker run` this repo controls, so builds stop leaving
  root-owned files in the work tree. sharp-libvips's own `build.sh` does not, so
  `scripts/clean.sh` deletes from inside a container instead of requiring `sudo`.
