#!/usr/bin/env bash
# Emits the two files this repo exists to produce, into out/linux-x64/:
#
#   sharp-linux-x64-<version>.node   patched addon (imports vips_g_*, not g_*)
#   libvips-cpp.so.<version>         patched libvips (exports no glib symbols)
#
# Copy both into a consumer's node_modules/@img/sharp-linux-x64/lib/ and delete
# its @img/sharp-libvips-linux-x64 package. Stock sharp's own JS then loads the
# patched pair with no source changes — see README.md. PhotoStructure keeps
# these under tools/sharp-patched/linux-x64/ and installs them from
# bin/patch-sharp.mjs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

SHARP_SRC=".work/sharp"
SHARP_VERSION=$(node -p "require('./$SHARP_SRC/package.json').version")
VERSION_VIPS=$(grep '^VERSION_VIPS=' .work/sharp-libvips/versions.properties | cut -d= -f2)
ADDON="$SHARP_SRC/src/build/Release/sharp-linux-x64-${SHARP_VERSION}.node"
LIBVIPS_SO="dist/linux-x64/lib/libvips-cpp.so.${VERSION_VIPS}"
OUT="out/linux-x64"

[ -f "$ADDON" ] || { echo "error: $ADDON not found — run scripts/build-sharp.sh first" >&2; exit 1; }
[ -f "$LIBVIPS_SO" ] || { echo "error: $LIBVIPS_SO not found — run scripts/build-libvips.sh first" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$ADDON" "$OUT/"
cp "$LIBVIPS_SO" "$OUT/"

# The addon needs to find the patched libvips sitting next to it, and must not
# be diverted to some other libvips-cpp.so with the same SONAME elsewhere in a
# consumer's tree.
#
# --force-rpath gets old-style DT_RPATH rather than patchelf's default
# DT_RUNPATH. The distinction is load-bearing: RUNPATH is consulted *after*
# LD_LIBRARY_PATH, RPATH *before* it. With RUNPATH, a stray LD_LIBRARY_PATH
# entry — or a leftover unpatched libvips-cpp.so elsewhere in the consuming
# project — silently wins over this co-located patched copy. RPATH always wins
# for our own NEEDED entry, whatever the consumer's environment looks like.
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$ROOT:$ROOT" -w "$ROOT" \
  sharp-electron-build \
  patchelf --force-rpath --set-rpath '$ORIGIN' "$OUT/sharp-linux-x64-${SHARP_VERSION}.node"

echo "Emitted into $OUT/:"
ls -la "$OUT"
