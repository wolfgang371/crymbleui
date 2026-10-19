#!/bin/bash
# The web flavour's whole check, before a push that touches it (CREDO): run from crymble-ui's root after
# `source setup.sh`, with DISPLAY set (conformance draws the native half through SFML).
#   1. spec.sh       the wasm patch's suite, the web flavour's own spec, the GC soak (Node WASI)
#   2. builds        tutorial-22, tutorial-07, tutorial-24, showcase_demo - unchanged - with bin/crymble-web
#   3. conformance   one program in both flavours, compared pixel for pixel (tools/wasm/conformance.sh)
#   4. smoke         the four builds driven in headless Chromium (tools/wasm/smoke.mjs)
#                    2-4 run twice: at -O0 (bin/crymble-web build) and as releases (--release, what is published)
#   5. README        the README's web commands in a scratch app, as an app author runs them (readme_check.sh;
#                    the README builds without --release, so -O0)
# Exit 0 only if every step passed; the first failing step stops the run and is named.
# Needs: bin/crymble-web setup (once); `npm ci` in tools/wasm (done here); a Chromium for playwright-core:
# `npx playwright-core install chromium-headless-shell` in tools/wasm, or CRYMBLE_CHROMIUM=<a chrome binary>.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
step() { echo; echo "=== check.sh: $1"; }
trap 'echo "check.sh: FAIL in step: ${current:-setup}" >&2' ERR

current="npm ci"
(cd "$HERE" && npm ci --silent --no-audit --no-fund)

current="spec.sh"; step "$current"
"$HERE/spec.sh"

for level in O0 release; do
  flags=()
  [ $level = release ] && flags=(--release)
  current="builds ($level)"; step "$current"
  bin/crymble-web build tutorial-22 tutorial-07 tutorial-24 showcase_demo ${flags[@]+"${flags[@]}"}

  current="conformance ($level)"; step "$current"
  "$HERE/conformance.sh" ${flags[@]+"${flags[@]}"} | tail -3

  current="smoke ($level)"; step "$current"
  node "$HERE/smoke.mjs" bin/web | grep -v '^ok'
done

current="README"; step "$current"
"$HERE/readme_check.sh" | tail -1

trap - ERR
echo
echo "check.sh: PASS"
