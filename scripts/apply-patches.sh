#!/usr/bin/env bash
# Applies this project's patches to the sources in .work/. Idempotent: safe to
# run whether they're pristine (fresh fetch) or already patched — skips
# anything already applied rather than erroring.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

apply_patch() {
  local target="$1"
  local patch="$ROOT/$2"

  if [ ! -d "$target/.git" ]; then
    echo "error: $target is not a checkout — run scripts/fetch-sources.sh first" >&2
    exit 1
  fi

  if ! git -C "$target" apply --check "$patch" 2>/dev/null; then
    if git -C "$target" apply --check --reverse "$patch" 2>/dev/null; then
      echo "already applied: $2 -> $target (skipping)"
      return 0
    fi

    # Neither direction applies. Before blaming upstream, check for the one
    # recoverable cause: a half-applied tree. `git reset --hard` reverts a
    # patch's edits to tracked files but leaves behind the files the patch
    # *creates*, since reset does not touch untracked files — so the forward
    # apply trips over "already exists" while the reverse apply finds the
    # tracked hunks missing. Those created files are wholly patch-owned, so
    # removing them and retrying is lossless.
    local created
    created=$(awk '/^diff --git/{f=$4} /^new file mode/{sub(/^b\//,"",f); print f}' "$patch")
    if [ -n "$created" ]; then
      local all_present=1
      while IFS= read -r f; do
        [ -e "$target/$f" ] || all_present=0
      done <<< "$created"

      if [ "$all_present" = 1 ]; then
        echo "note: $target looks half-patched (files this patch creates already exist," >&2
        echo "      but its edits to tracked files are absent). Removing them and retrying." >&2
        while IFS= read -r f; do rm -f "$target/$f"; done <<< "$created"
        if git -C "$target" apply --check "$patch" 2>/dev/null; then
          git -C "$target" apply "$patch"
          echo "applied: $2 -> $target (after repairing a half-patched tree)"
          return 0
        fi
      fi
    fi

    echo "error: $2 does not apply cleanly to $target, and isn't already applied either." >&2
    echo "       The pinned upstream in versions.env likely moved in the area this patch" >&2
    echo "       touches. See README.md's 'Bumping to a newer sharp' section — and check" >&2
    echo "       patches/wrapper-symbols.json against a fresh grep of the upstream source," >&2
    echo "       since a bump can introduce new glib call sites that need wrapping too." >&2
    exit 1
  fi

  git -C "$target" apply "$patch"
  echo "applied: $2 -> $target"
}

apply_patch .work/sharp-libvips patches/sharp-libvips-glib-wrapper.patch
apply_patch .work/sharp patches/sharp-glib-calls.patch
