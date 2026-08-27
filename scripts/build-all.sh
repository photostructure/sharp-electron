#!/usr/bin/env bash
# The single documented entry point: fetch -> patch -> Phase A -> Phase B ->
# both gates -> emit. Stops on first failure. Requires only Docker and git on
# the host (see README.md's "Building from source" section).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "### 1/5 Fetch pinned upstream sources ###"
./scripts/fetch-sources.sh

echo ""
echo "### 2/5 Phase A: libvips ###"
./scripts/build-libvips.sh

echo ""
echo "### 3/5 Phase B: sharp ###"
./scripts/build-sharp.sh

echo ""
echo "### 4/5 Test gates ###"
./scripts/run-gates.sh

echo ""
echo "### 5/5 Emit ###"
./scripts/emit-dist.sh

echo ""
echo "All done. Copy out/linux-x64/* into the consumer — for PhotoStructure that is"
echo "tools/sharp-patched/linux-x64/, installed by bin/patch-sharp.mjs."
