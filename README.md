# sharp-electron

> **PhotoStructure's fork of
> [janhapke/sharp-electron](https://github.com/janhapke/sharp-electron)** (Apache-2.0) — the patches
> and the glib-wrapper technique are Jan Hapke's work, carried here essentially unmodified; see
> [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). PhotoStructure maintains it so the binaries
> shipped in PhotoStructure for Desktop are built and released from infrastructure PhotoStructure
> controls, and so the `sharp` version can be bumped on PhotoStructure's own schedule. Fixes that
> are not PhotoStructure-specific should go upstream — to
> [lovell/sharp](https://github.com/lovell/sharp) where possible, otherwise to janhapke's repo.

A patched rebuild of [`sharp`](https://github.com/lovell/sharp) and its bundled `libvips` that doesn't segfault under Electron on Linux.

`sharp` crashes with a native segfault — not a catchable JS error — when decoding an image (JPEG, PNG, etc.) inside any process built on Electron's Linux binary. The cause is two copies of `glib` colliding in one process; no configuration flag fixes it. This repo rebuilds both with the collision fixed at the linker level, and emits the two binaries that result. Consumers swap them into an ordinary `sharp` install ([Use it](#use-it)) — macOS and Windows are unaffected and keep stock `sharp`. See [Build it](#build-it), [Bump to a newer sharp](#bump-to-a-newer-sharp), and [Engineering notes](#engineering-notes).

## The problem

Electron's Linux binary dynamically links the system's `glib` (for GTK integration). `sharp`/`libvips` bundle their own private `glib` inside `libvips-cpp.so`, but don't fully hide its symbols. Two copies of `glib` exporting the same symbols into one process corrupt `glib`'s internal state, and the process dies with `SIGSEGV` the first time an image is actually decoded — no JS exception, no stack trace. This affects any process built on Electron's binary, including a `utilityProcess`, and is a known, currently-unresolved upstream bug: [electron/electron#46323](https://github.com/electron/electron/issues/46323).

Characteristically, *encoding* raw pixels works fine — only *decoding* a real compressed image crashes. If that matches what you're seeing, this is your bug.

## Build it

Requires Docker and git; everything else runs in containers.

```bash
git clone https://github.com/photostructure/sharp-electron.git
cd sharp-electron
npm install
npm run build
```

That fetches the upstream commits pinned in [versions.env](versions.env), applies the patches, rebuilds libvips and sharp's addon, runs both test gates, and writes two files to `out/linux-x64/`:

```
sharp-linux-x64-<version>.node   patched addon — imports vips_g_*, never bare g_*
libvips-cpp.so.<version>         patched libvips — exports no glib symbols
```

`npm run clean` starts over. Individual stages, if you need them: `npm run fetch`, `build:libvips`, `build:sharp`, `test:gates`, `emit`.

## Use it

Copy both files into the consuming project's `node_modules/@img/sharp-linux-x64/lib/`, then delete its `node_modules/@img/sharp-libvips-linux-x64/` directory.

That is the whole integration. Stock `sharp` from npm picks the patched pair up with no source changes, no `package.json` edit, and no npm `overrides` — the addon's `$ORIGIN` RPATH finds the libvips sitting next to it.

**Delete the stock libvips rather than leaving it in place.** Both `.so` files declare the same SONAME, and the ELF loader deduplicates by SONAME per process: leave both on disk and whichever loads first wins for every module in that process. When the unpatched one wins you don't get the original segfault, you get a confusing `undefined symbol: vips_g_...` from the correctly-patched module.

Only `linux-x64` needs this. macOS and Windows don't have the bug — leave stock `sharp` alone there.

PhotoStructure does this from `bin/patch-sharp.mjs`, wired as `src/desktop`'s `postinstall`, with these two files committed under `tools/sharp-patched/linux-x64/`.

## Bump to a newer sharp

Update the refs in [versions.env](versions.env), then `npm run clean && npm run build`. If a patch stops applying, `scripts/apply-patches.sh` says so instead of guessing.

Prefer the guided process for a real bump: [`/rebuild-for-version <sharp-version> <sharp-libvips-version>`](.claude/commands/rebuild-for-version.md). A bump involves judgment a script gets silently wrong — whether the bug still reproduces upstream at all, whether a patch conflict is context drift or a structural change, and whether the wrapper symbol set is still complete. That last one is the dangerous one: a newly-added bare glib call site is not a build error, it is a segfault in production.

Note that the emitted filenames carry the sharp and libvips versions, so a consumer that hardcodes them (PhotoStructure's `bin/patch-sharp.mjs` does, deliberately, so a mismatch fails the install) needs updating in the same change.

## Releases

Releases are cut by [`.github/workflows/release.yml`](.github/workflows/release.yml), never from a workstation — push a `v*-ps.*` tag, or dispatch the workflow with a tag. It runs the full pipeline including both gates, asserts the emitted addon imports no bare glib symbols, attaches both binaries with their sha256 digests, and emits a signed build-provenance attestation:

```bash
gh attestation verify sharp-linux-x64-0.35.3.node --repo photostructure/sharp-electron
```

That subcommand needs **gh >= 2.49**; Ubuntu's `gh` package is older (26.04 ships 2.46) and will report `unknown command "attestation"`. Either install gh from [cli.github.com](https://cli.github.com), or check the attestation through the API, which any gh can do:

```bash
gh api repos/photostructure/sharp-electron/attestations/sha256:<digest> \
  --jq '.attestations[0].bundle.dsseEnvelope.payload' | base64 -d | jq .subject
```

The tag scheme is `-ps.N`, deliberately *not* upstream's `-electron.N`. This fork keeps inheriting upstream's tags on every fetch, and `gh release create` silently reuses an existing tag — which once attached our assets to upstream's commit rather than ours.

## Troubleshooting

- **`undefined symbol: vips_g_...` at load time** (an exception, not a crash) — the SONAME collision above: something in the process resolved to a stock, unpatched `libvips-cpp.so`. Confirm `@img/sharp-libvips-linux-x64` is gone and the patched pair really is in `@img/sharp-linux-x64/lib/`.
- **Segfault decoding an image under Electron on Linux, with the swap in place** — an unpatched `libvips-cpp.so` from elsewhere is winning the SONAME race. Check what else in the process loads libvips.
- **`ERR_DLOPEN_FAILED: libvips-cpp.so...: cannot open shared object file`, but only in a *packaged* app** — your packager is dropping the `.so` that sits beside the addon. Two causes, both seen in a real Electron Forge project: a native-module whitelist that walks only `dependencies` (prebuilt `@img/*` packages are `optionalDependencies`), or asar tooling that unpacks `.node` but not `.so` sidecars — `@electron-forge/plugin-auto-unpack-natives` matches only `**/*.node`, leaving the library inside the archive where `dlopen()` cannot reach it. Diagnose against the packaged output: `find <app>/resources/app.asar.unpacked -iname 'libvips-cpp.so*'`.

## Engineering notes

Everything a contributor (or future maintainer bumping versions) needs to know about how and why this works.

### How the fix works

The fix has two halves, applied as patches (in [patches/](patches/)) to two upstream repos vendored as git submodules pinned at release tags. The submodules stay pristine in git; [scripts/apply-patches.sh](scripts/apply-patches.sh) applies the patches to their working trees at build time (idempotently — it detects an already-patched tree and skips).

**Phase A — `sharp-libvips` (the `libvips` binary).** `sharp-libvips` doesn't vendor `libvips`'s source; its `build/posix.sh` downloads the upstream release tarball at build time and patches it inline. Our patch extends that same mechanism:

- Adds `extra/glib_wrapper.c`/`.h`: thin wrapper functions re-exporting each needed `glib` symbol under a renamed `vips_g_*` identity (e.g. `vips_g_malloc` calls the bundled `glib`'s `g_malloc`).
- Broadens the `vips.map` linker version script from hiding a single symbol (`g_param_spec_types` — upstream's own partial fix for this class of bug) to hiding *everything* except `libvips`'s own API: `{ global: vips_*; _Z*; local: *; }`. This is what actually removes the colliding `g_*` exports from `libvips-cpp.so`.
- Patches `libvips`'s C++ header `VImage8.h`, whose inline `VObject` smart-pointer class calls `g_object_ref`/`g_object_unref` directly — those calls get compiled straight into `sharp`'s addon wherever `vips::VImage` is used, so they must be redirected at the header level, not in `sharp`'s source.

One non-obvious gotcha, recorded because it *will* bite again: `libvips-cpp.so`'s meson target sets `gnu_symbol_visibility: 'hidden'`, which strips any new symbol from the dynamic table at compile time — before the version script even applies — unless it's explicitly marked `__attribute__((visibility("default")))`. The build succeeds cleanly either way; only `objdump -T` reveals the difference. A clean build is not sufficient evidence here.

**Phase B — `sharp` (the Node addon).** Redirects `sharp`'s own direct `glib` calls (`common.cc`, `metadata.cc`, `sharp.cc`) to the `vips_g_*` wrappers, then rebuilds the addon against the Phase A `libvips` using `sharp`'s own supported mechanism for custom libvips builds: `SHARP_FORCE_GLOBAL_LIBVIPS=1` plus `PKG_CONFIG_PATH` pointed at generated `.pc` files. The build runs in a Docker image ([scripts/sharp-build.Dockerfile](scripts/sharp-build.Dockerfile)) replicating `sharp`'s official CI environment (Rocky Linux 8, gcc-toolset-14, Node 20), so nothing touches the host toolchain and the binary matches upstream's baseline glibc compatibility.

### The wrapper symbol set

Seven symbols are wrapped. The machine-readable source of truth — including each symbol's origin, risk classification, and how it was found — is [patches/wrapper-symbols.json](patches/wrapper-symbols.json); version bumps should diff a fresh grep against that file, not against this prose. The short version:

- `g_object_ref`, `g_object_unref` — from `libvips`'s `VImage8.h` inline header (see Phase A above); the original crash culprits.
- `g_malloc`, `g_free` — from `sharp`'s own source. Wrapped **as a pair** deliberately: an allocator and its matching free must come from the same `glib` copy, or the result is silent heap corruption, not just a symbol-hygiene issue.
- `g_signal_connect_data`, `g_log_set_handler` — from `sharp`'s own source.
- `g_utf8_validate` — from `sharp`'s `metadata.cc`. Notably, this one was **missed by grepping** and only surfaced when running `sharp`'s full test suite against the rebuilt addon (`undefined symbol` at runtime). Lesson: the test-gate loop below is load-bearing, not a formality — expect a version bump to surface a symbol the grep missed.

### Packaging details that matter

Two hard-won, non-obvious decisions live in [scripts/emit-dist.sh](scripts/emit-dist.sh):

- **`libvips-cpp.so` sits next to the `.node` addon, found via RPATH — and it must be old-style `DT_RPATH`, not `DT_RUNPATH`.** `patchelf --set-rpath` produces `DT_RUNPATH` by default, which the loader consults *after* `LD_LIBRARY_PATH` — so anything else in a real consumer's environment or `node_modules` that provides the same SONAME can win over the co-located patched copy. `patchelf --force-rpath` produces `DT_RPATH`, consulted *before* `LD_LIBRARY_PATH`, so the co-located copy always wins for the addon's own direct dependency. (Setting `process.env.LD_LIBRARY_PATH` from JavaScript doesn't work at all: glibc reads it once at process start, not per `dlopen()`.)
- **The SONAME is kept identical to upstream's** — that is what lets the patched pair drop into a stock `sharp` install unchanged. It is also why the consumer must delete `@img/sharp-libvips-linux-x64`: see [Use it](#use-it).

### Test gates

Every build must pass both, enforced by [scripts/run-gates.sh](scripts/run-gates.sh) (non-zero exit on failure, usable in CI):

1. **`sharp`'s own upstream test suite** against the rebuilt addon (1804/1811 at last run; the one known failure is `test/unit/esm.mjs`, a pre-existing Node CJS/ESM interop quirk unrelated to these patches — it fails identically against stock `sharp`).
2. **The Electron crash regression test** ([test/electron-crash-repro.js](test/electron-crash-repro.js)): encode raw pixels to JPEG, then decode a real JPEG via `.metadata()` and `.resize().toBuffer()`, under `ELECTRON_RUN_AS_NODE`. On an unpatched build the decode step reliably segfaults; on a correct build both steps pass. The same script serves both directions via `SHARP_MODULE_PATH`.

**Keep the `electron` devDependency pinned to the version the consumer ships.** This gate's only job is to answer "does sharp survive under *our* Electron", and it is exactly-pinned rather than a caret range so it cannot drift away from that silently. It had been left on `^33.0.0` — ten majors behind PhotoStructure's 43.4.1 — while claiming to validate the shipped runtime. Gate 2 prints the electron version it ran on, so a mismatch is visible in the log.

**The `sharp` devDependency lags `versions.env` on purpose, for up to 14 days.** It is only the default module for `npm run repro` — the "confirm the bug still reproduces on stock sharp" path — so it is the one place this repo resolves `sharp` through npm. The build does not: `scripts/fetch-sources.sh` clones the pinned commit by SHA, which is why `versions.env` can name a release that `.npmrc`'s `min-release-age=14` still refuses to install. Bumping the devDependency to a release younger than that fails with `npm error notarget ... with a date before <date>`. Move it once the version ages past the gate; until then the repro validates against the previous release, which reproduces the same crash.

**If a gate fails with `undefined symbol: g_<something>`**: that's a missing wrapper symbol. Add it to `extra/glib_wrapper.c`/`.h` in `.work/sharp-libvips` (remember the `visibility("default")` attribute), patch the call site, update `patches/wrapper-symbols.json`, regenerate the patch files, rebuild, re-run the gates. This loop is normal — it's how `g_utf8_validate` was found.

### Alternatives that didn't work

Tried before concluding a from-source rebuild was the only real fix:

| Approach | Result |
|---|---|
| `LD_PRELOAD` sharp's `libvips-cpp.so` before Electron starts | Made Electron crash even earlier |
| `objcopy --localize-symbols` (hide symbols post-hoc, no recompile) | Still segfaults — `sharp.node`'s undefined references then bind to Electron's `glib` instead |
| `RTLD_DEEPBIND` | Crashes differently, during load |
| Do `sharp` work in a real separate Node process (not Electron's binary) | Works, but requires bundling a Node binary and adds an IPC boundary |

### Repository layout

```
versions.env                 pinned upstream commits — the one place a version bump starts
patches/                     the actual fix: two .patch files + wrapper-symbols.json (symbol manifest)
scripts/                     fetch-sources → apply-patches → build-libvips → build-sharp → run-gates → emit-dist
test/electron-crash-repro.js the regression test (and original bug repro)
.github/workflows/ci.yml     the full Linux pipeline on every push
.work/                       gitignored; pinned upstream checkouts, partly root-owned (see clean.sh)
dist/                        gitignored; Phase A libvips output + generated .pc files
out/linux-x64/               gitignored; the two emitted binaries — this repo's whole product
```

## Status

The `linux-x64` build passes both test gates and has been verified end-to-end
against PhotoStructure for Desktop: stock `sharp` with these two binaries swapped in
survives the decode path under both a `LD_PRELOAD`ed system `libgobject` and the real
packaged Electron binary, each of which reliably segfaults stock `sharp`.

No other architecture has a patched build. PhotoStructure ships linux-x64 only.

## License

Apache-2.0, matching `sharp`. See [LICENSE](LICENSE) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) (this project patches `libvips`, LGPL-2.1-or-later; the `glib_wrapper.c`/`.h` shim is original code).
