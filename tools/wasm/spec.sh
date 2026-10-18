#!/bin/bash
# The wasm32 patch's regression suite, run under Node's WASI with the toolchain bin/crymble-web setup built:
#   patch_spec    exceptions, the struct-return ABI, the WASI file-system fixes, the toolchain's library versions
#   planted_spec  the runner can fail: exactly one failure and one error, or this suite fails
#   web_spec      the web flavour: the event round trip against crymble.js's tables, its notices
#   soak          garbage collection between ticks: rows intact, finalizers run, heap flat
# Exit 0 only if every part holds at its expected count. Run from crymble-ui's root.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOME_DIR=${CRYMBLE_WASM_HOME:-$HOME/.cache/crymble-wasm}
SDK=$HOME_DIR/wasi-sdk
WORK=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
fail() { echo "spec.sh: FAIL - $*" >&2; exit 1; }
# A spec run's summary and failures; the run's last lines when it printed no summary (it died).
summary() { echo "$1" | grep -E 'examples|^\s+[0-9]+\)' || echo "$1" | tail -5; }

# The patched compiler, host-independent (the same environment bin/crymble-web builds in).
compile() { # SOURCE OUT [crystal flags...]
  local src=$1 out=$2
  shift 2
  env -u CRYSTAL_LIBRARY_PATH -u LIBXML_VERSION PATH="$HERE/shims:$PATH" CRYSTAL_PATH="lib:$HOME_DIR/crystal/src" \
    "$HOME_DIR/crystal/.build/crystal" build --cross-compile --target wasm32-unknown-wasi -Dwithout_mt "$@" "$src" -o "$out" \
    > "$out.link-line"
}
link() { # OBJECT OUT [wasm-ld args...]
  local obj=$1 out=$2
  shift 2
  local libs
  libs=$(tr ' ' '\n' < "${obj%.wasm}.link-line" | grep -x -- '-l.*' | grep -vx -- '-lc' | sort -u | tr '\n' ' ')
  # shellcheck disable=SC2086
  "$SDK/bin/wasm-ld" "$obj" "$HOME_DIR/lib/cpp_tag.o" "$@" -o "$out" -L"$HOME_DIR/lib" \
    -L"$SDK/share/wasi-sysroot/lib/wasm32-wasi" $libs -lc -lwasi-emulated-process-clocks -lwasi-emulated-mman \
    -lwasi-emulated-signal -z stack-size=8388608 --stack-first --fatal-warnings
}

"$SDK/bin/clang" --target=wasm32-wasi --sysroot="$SDK/share/wasi-sysroot" -O2 -c "$HERE/spec/struct_return.c" -o "$WORK/struct_return.o"

compile "$HERE/spec/patch_spec.cr" "$WORK/patch_spec"
link "$WORK/patch_spec.wasm" "$WORK/patch_spec.out.wasm" "$WORK/struct_return.o"
out=$(node --no-warnings "$HERE/spec/run.mjs" command "$WORK/patch_spec.out.wasm" 2>&1) || true
summary "$out"
echo "$out" | grep -qx '10 examples, 0 failures, 0 errors, 0 pending' || fail "patch_spec: expected 10 examples, 0 failures"

compile "$HERE/spec/planted_spec.cr" "$WORK/planted_spec"
link "$WORK/planted_spec.wasm" "$WORK/planted_spec.out.wasm"
out=$(node --no-warnings "$HERE/spec/run.mjs" command "$WORK/planted_spec.out.wasm" 2>&1) && fail "planted_spec exited 0"
summary "$out"
echo "$out" | grep -qx '3 examples, 1 failures, 1 errors, 0 pending' || fail "planted_spec: the runner did not report the planted failure and error"

# The web flavour itself: the event round trip against crymble.js's own tables, and its notices
cp "$HERE/../../web/crymble.js" "$WORK/crymble.mjs" # an ES module outside any package.json
node --input-type=module -e "import { EV, KEYS } from '$WORK/crymble.mjs'; console.log(JSON.stringify({ EV, KEYS }))" \
  > "$WORK/js_tables.json"
CRYMBLE_JS_TABLES="$WORK/js_tables.json" compile "$HERE/spec/web_spec.cr" "$WORK/web_spec"
link "$WORK/web_spec.wasm" "$WORK/web_spec.out.wasm"
out=$(node --no-warnings "$HERE/spec/run.mjs" command "$WORK/web_spec.out.wasm" 2>&1) || true
summary "$out"
echo "$out" | grep -qx '4 examples, 0 failures, 0 errors, 0 pending' || fail "web_spec: expected 4 examples, 0 failures"

compile "$HERE/spec/soak.cr" "$WORK/soak" -Dwithout_main
link "$WORK/soak.wasm" "$WORK/soak.out.wasm" "$SDK/share/wasi-sysroot/lib/wasm32-wasi/crt1-reactor.o" --no-entry \
  --export=_initialize --export=soak_init --export=soak_tick --export=soak_gc --export=soak_check \
  --export=soak_finalized --export=soak_heap_kb
node --no-warnings "$HERE/spec/run.mjs" soak "$WORK/soak.out.wasm" || fail "soak"

echo "spec.sh: PASS"
