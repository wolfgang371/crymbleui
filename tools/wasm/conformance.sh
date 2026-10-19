#!/bin/bash
# The web flavour's conformance check: tools/wasm/conformance/conformance.cr built in both flavours, run (native
# under DISPLAY, web in headless Chromium) and compared by diff.mjs. Run from crymble-ui's root, after
# `source setup.sh` (the native build) and with the toolchain set up (bin/crymble-web setup). `conformance.sh
# --release` checks the web half built as a release (LLVM-optimized) instead of at -O0.
# Exit 0 only if diff.mjs passes.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
: "${DISPLAY:?the native half draws through SFML: set DISPLAY}"

crystal build "$HERE/conformance/conformance.cr" -o "$WORK/conformance"
timeout 60 "$WORK/conformance" > "$WORK/native.out"
bin/crymble-web build "$HERE/conformance/conformance.cr" --local "$@" > /dev/null
node "$HERE/conformance/web.mjs" bin/web/conformance > "$WORK/web.out"
node "$HERE/conformance/diff.mjs" "$WORK/native.out" "$WORK/web.out"
