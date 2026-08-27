---
description: Re-run this project's patch/build/test pipeline against a new sharp/sharp-libvips release, with judgment at each step rather than blind reapplication.
argument-hint: <sharp-version> <sharp-libvips-version>
---

# Rebuild for a new `sharp`/`sharp-libvips` version

Arguments: `$ARGUMENTS` — expected as `<sharp-version> <sharp-libvips-version>`, e.g. `0.36.0 1.4.0`. If either is missing, ask for it before doing anything else.

This is **not** a script to run to completion unattended — it's a guided process with real judgment calls at several points. Read all of this before starting, and stop to report back (rather than guessing and continuing) at any point marked **STOP**.

## Step 0: Orient

- Read `patches/wrapper-symbols.json` — the current source of truth for which symbols are wrapped and why.
- Read `README.md`'s "Engineering notes" section (especially "How the fix works" and "The wrapper symbol set").
- Confirm the new target versions are real releases: check `https://github.com/lovell/sharp/releases` and `https://github.com/lovell/sharp-libvips/releases` for the tags given in `$ARGUMENTS`, and resolve each tag to a commit SHA — `versions.env` pins SHAs, not tags.

## Step 1: Check whether the bug still reproduces at all — before assuming any patches are needed

Do not skip this by assuming "same bug, same fix." Upstream could have partially or fully fixed this independently since the current target version.

1. `npm run clean`, then update `versions.env` to the new SHAs and run `npm run fetch`.
2. Build **unpatched** — do *not* run `scripts/apply-patches.sh` yet. Run `sharp-libvips`'s own `build.sh linux-x64` and `sharp`'s own default build (against the npm `@img/sharp-libvips-linux-x64` package, *not* `SHARP_FORCE_GLOBAL_LIBVIPS`) to get a genuinely stock addon.
3. Run `test/electron-crash-repro.js` with `SHARP_MODULE_PATH` pointed at that stock build, via `ELECTRON_RUN_AS_NODE=1 electron ...`.
4. **STOP and report** if it does *not* crash. Investigate why before proceeding — check `sharp-libvips`'s `build/posix.sh` for whether they broadened their own `vips.map` fix, check the [Electron tracking issue](https://github.com/electron/electron/issues/46323) for whether it's been closed, check whether `libvips`'s `VImage8.h` still has the same inline-header pattern. The patches might need to shrink, change shape, or (best case) not be needed at all. The right next step depends entirely on *why* it's fixed.

If it still crashes (expected, most likely outcome): continue to Step 2.

## Step 2: Attempt to apply the existing patches

1. Run `scripts/apply-patches.sh`.
2. **Clean apply**: proceed to Step 3.
3. **Apply failure**: diagnose *why*, don't just retry blindly.
   - Note that `apply-patches.sh` self-heals one specific case — a half-patched tree, where the files the patch *creates* exist but its edits to tracked files don't. If it reports that, nothing is wrong with the patch.
   - Otherwise, pull up the failing hunk. Diff the relevant upstream file between the old and new pinned commits, focused on just the lines the patch touches.
   - Judge: trivial context drift (safe to regenerate mechanically — `git apply --recount`, or a small manual edit, then re-verify with `git apply --check`), or a structural change (`VImage8.h`'s `VObject` class reshaped, `build/posix.sh`'s libvips-build block reorganized, `cplusplus/meson.build`'s `library('vips-cpp', ...)` sources list restructured)?
   - For structural changes: **STOP and report** what changed and what you think the patch needs to become, before rewriting it.

## Step 3: Re-check the wrapper symbol scope

Do not assume the symbol set in `patches/wrapper-symbols.json` is still complete or still necessary. A new upstream version can introduce new bare glib call sites, and a missed one is not a build error — it is a segfault in production.

1. Re-run the exhaustive grep for bare `glib`/`gobject` calls across *every* file in the new `.work/sharp/src/` (not just the files that had them last time):
   ```bash
   for f in $(git -C .work/sharp ls-tree -r --name-only HEAD -- src/ | grep -E '\.(cc|h)$'); do
     git -C .work/sharp show HEAD:"$f" | grep -noE '\bg_[a-z0-9_]+\s*\(' | while read -r m; do echo "$f: $m"; done
   done | sort -u
   ```
2. Also re-check whether `libvips`'s other public C++ headers (`VError8.h`, `VInterpolate8.h`, `VRegion8.h`, `VConnection8.h` — see `wrapper-symbols.json`'s `headersChecked` for what was clean last time) have picked up the same inline-header pattern `VImage8.h` has.
3. Diff both results against `patches/wrapper-symbols.json`. Report any symbols now called that aren't wrapped (add them to `extra/glib_wrapper.c`/`.h` in `.work/sharp-libvips`, following the existing pattern, remembering the `__attribute__((visibility("default")))` requirement), and any wrapped symbols no longer called anywhere (safe to leave; removing them is low priority).
4. Update `patches/wrapper-symbols.json` and the patch files to match — including `targetVersions`, which must always name the exact versions the manifest was verified against — then re-verify `git apply --check` on both.

## Step 4: Rebuild both phases

```bash
npm run build:libvips
npm run build:sharp
```

## Step 5: Run both gates

```bash
npm run test:gates
```

**If either gate fails**, follow the loop this project's own development actually used — expect this to happen at least once; it is not a sign something is broken:

1. Identify the specific symbol from the failure. `undefined symbol: <name>` names it directly. A genuine *segfault* in gate 2 means a wrapped symbol isn't taking effect somewhere — re-check `objdump -T` on the rebuilt `libvips-cpp.so` for that symbol in both directions before assuming it's a *new* symbol.
2. Add it to the wrapper set (`extra/glib_wrapper.c`/`.h`, `wrapper-symbols.json`, and the relevant call-site patch), regenerate both patch files, rebuild, re-run gates.
3. **Bound this to 3 automatic iterations.** If gates still aren't green after 3 rounds, **STOP and report** what's still failing rather than continuing to loop.

## Step 6: Re-verify the binaries directly

1. `objdump -T` on the rebuilt `libvips-cpp.so`, checking **every** symbol in `wrapper-symbols.json` in both directions (bare name absent, `vips_<name>` present as defined + global).
2. `npm run emit`, then `readelf -d out/linux-x64/sharp-linux-x64-*.node` — confirm `DT_RPATH` (**not** `DT_RUNPATH`; see README's "Packaging details that matter").
3. Confirm the addon imports no bare glib symbols at all:
   ```bash
   readelf --dyn-syms -W out/linux-x64/sharp-linux-x64-*.node | grep ' UND ' | grep -E '\bg_[a-z]'
   ```
   Expect no output.

## Step 7: Hand off to the consumer — do not publish anything

This repo publishes nothing. There is no npm package and no release script.

1. Copy `out/linux-x64/*` into PhotoStructure's `tools/sharp-patched/linux-x64/` (git-LFS).
2. **Update PhotoStructure's `src/desktop/package.json`** to the new `sharp` version in the same commit. The two are coupled: `bin/patch-sharp.mjs` derives the addon filename from the installed `@img/sharp-linux-x64` version and **fails the install** if `tools/sharp-patched/` doesn't provide a matching file. That guard is deliberate — a mismatch would otherwise leave sharp loading the stock addon and crash-looping — but it means bumping one without the other breaks `npm install`.
3. Write a `CHANGELOG.md` entry: the new upstream versions, any patch adjustments and why (Step 2), any wrapper-symbol changes (Step 3), and confirmation that both gates pass.
4. **STOP and report** a summary: what changed, what needed judgment, and that it's ready for review. Committing, tagging, and pushing are always explicit, separately-confirmed human actions.
