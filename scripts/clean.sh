#!/usr/bin/env bash
# Removes .work/ and dist/.
#
# WHY THIS IS NOT JUST `rm -rf`: sharp-libvips's own build.sh runs its build
# container without --user, so libvips build output under .work/sharp-libvips
# is owned by root. Those files cannot be deleted, moved, or even renamed by
# the invoking user — renaming a directory needs write permission on the
# directory itself, not just its parent — so a plain rm -rf fails partway and
# leaves a work tree that the next build cannot re-checkout.
#
# Rather than requiring `sudo` (which a CI runner may not have, and which is a
# blunt instrument to hand a build script), delete them from inside a
# throwaway container, where we are already root.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

if [ -n "$(find .work dist -not -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
  echo "removing root-owned build output via container"
  docker run --rm -v "$ROOT:/repo" -w /repo alpine:3 rm -rf /repo/.work /repo/dist
fi

rm -rf "$ROOT/.work" "$ROOT/dist"
echo "clean: .work/ and dist/ removed"
