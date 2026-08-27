# Third-party notices

This project produces a patched rebuild of two upstream projects, distributed under their own licenses:

| Project                                                    | Used under the terms of |
| ------------------------------------------------------------ | ------------------------ |
| [sharp](https://github.com/lovell/sharp)                     | Apache License 2.0      |
| [sharp-libvips](https://github.com/lovell/sharp-libvips) / [libvips](https://github.com/libvips/libvips) | LGPL-2.1-or-later |

`sharp-libvips`'s own build pulls in a further set of third-party libraries (glib, cairo, pango, libjpeg, etc.) — see [`sharp-libvips`'s own `THIRD-PARTY-NOTICES.md`](https://github.com/lovell/sharp-libvips/blob/main/THIRD-PARTY-NOTICES.md) for that full list; this project doesn't change any of those licensing terms, only how `libvips-cpp.so` exports (or hides) `glib`/`gobject` symbols from its own public API (see `README.md` for why).

## Upstream of this repository

The glib-wrapper technique this repository is built on — the two patches in `patches/`,
`wrapper-symbols.json`, the `extra/glib_wrapper.c`/`.h` sources they add, and the Docker build
scripts in `scripts/` — is the work of Jan Hapke, published as
[janhapke/sharp-electron](https://github.com/janhapke/sharp-electron) under the Apache License 2.0.
Those files are used here essentially unmodified.

PhotoStructure carries its own fork so the binaries shipped in PhotoStructure for Desktop are built
and released from infrastructure PhotoStructure controls, and so the `sharp` version can be bumped on
PhotoStructure's schedule. This is a GitHub fork of that repository, not a copy of its files: upstream's
commit history is preserved intact, so every original commit remains attributed to its author and
PhotoStructure's changes sit on top as their own commits. Changes that are not PhotoStructure-specific
should go upstream: to [lovell/sharp](https://github.com/lovell/sharp) where the fix belongs there,
otherwise to janhapke's repository.

## What this project adds on top

- `extra/glib_wrapper.c`/`.h` (added to sharp-libvips by `patches/sharp-libvips-glib-wrapper.patch`) — original code written for this project (not derived from upstream `sharp`/`libvips`/`glib` source), released under the same license as the rest of this repository (see `LICENSE`).
- `patches/*.patch` — diffs against the above upstream projects, distributed here as patches (not as a modified copy of their source) specifically so the unmodified upstream license terms continue to apply to the code being patched.
