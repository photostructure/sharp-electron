#!/usr/bin/env bash
# Clones the pinned upstream sources into .work/.
#
# This project deliberately does NOT use git submodules: its only consumer is
# PhotoStructure's private monorepo, which has no submodules and would have to
# add --recurse-submodules to every clone and CI checkout to gain nothing. The
# desktop build never compiles libvips — it consumes the two prebuilt files
# this repo emits — so the upstream source only needs to exist at build time,
# on a build machine, which is exactly what this script arranges.
#
# Idempotent, and deliberately NON-destructive once a checkout is at the pinned
# ref: it returns immediately rather than resetting.
#
# It used to `git reset --hard` unconditionally, which broke every multi-stage
# build. Phase A applies the patches; Phase B calls this again; the reset
# reverted the patches' *tracked* edits but left the file the libvips patch
# *creates* (extra/glib_wrapper.c) behind, since reset does not remove
# untracked files. apply-patches.sh then saw a tree where the patch neither
# applied nor reverse-applied, and failed. Resetting would also have discarded
# Phase A's expensive (and root-owned) libvips build output.
#
# To genuinely start over, use scripts/clean.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# shellcheck source=../versions.env
. ./versions.env

fetch() {
  local name="$1" repo="$2" ref="$3"
  local dir="$ROOT/.work/$name"

  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$ref" ]; then
    echo "  $name already at ${ref:0:12} (leaving as-is, patches included)"
    return 0
  fi

  if [ -d "$dir/.git" ]; then
    # Already checked out, but at a different commit — i.e. versions.env moved.
    # Don't try to switch in place: this tree is patched, and the libvips one
    # also holds root-owned build output, so a checkout here half-succeeds at
    # best. A version bump means a full rebuild regardless.
    echo "error: .work/$name is at $(git -C "$dir" rev-parse --short HEAD), but versions.env pins ${ref:0:12}." >&2
    echo "       Run 'npm run clean' first, then rebuild." >&2
    exit 1
  fi

  echo "cloning $name @ ${ref:0:12}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$repo"

  # Fetch just the pinned commit. --depth 1 keeps sharp-libvips (a large
  # history) cheap; not all servers allow fetching a bare SHA, but GitHub does.
  git -C "$dir" fetch -q --depth 1 origin "$ref"
  git -C "$dir" checkout -q --detach FETCH_HEAD

  echo "  $name -> $(git -C "$dir" rev-parse HEAD)"
}

fetch sharp "$SHARP_REPO" "$SHARP_REF"
fetch sharp-libvips "$SHARP_LIBVIPS_REPO" "$SHARP_LIBVIPS_REF"
