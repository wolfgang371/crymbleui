#!/bin/bash
# The wasm32 patch's regression suite, run under Node's WASI with the toolchain bin/crymble-web setup built - every
# part built twice, at -O0 and as a release (-O3), each linked and optimized with wasm-opt as builds ship:
#   patch_spec    exceptions, the struct-return ABI, layout numbers, the WASI file-system fixes, the toolchain's
#                 library versions; its constants are static (no lazy initializer in the IR)
#   layout_guard  a layout number fixed inside a type argument before its type is complete is a compile error
#                 naming it, never a wrong number
#   planted_spec  the runner can fail: exactly one failure and one error, or this suite fails
#   web_spec      the web flavour: the event round trip against crymble.js's tables, its notices
#   soak          garbage collection between ticks: rows intact, finalizers run, heap flat
# First: setup.sh --check accepts this toolchain, and refuses a stale stamp (on a copy).
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

# The patched compiler, host-independent (the same environment bin/crymble-web builds in). LEVEL is the
# optimization this build gets, independent of what bin/crymble-web's --release means: O0, or release (Crystal's
# --release: -O3, one module). The compiler reports the calls its stub step retargeted (compiler.cr).
build() { # SOURCE OUT LEVEL [crystal flags...] - the compiler's status
  local src=$1 out=$2 level=$3
  shift 3
  [ "$level" = release ] && set -- --release "$@"
  env -u CRYSTAL_LIBRARY_PATH -u LIBXML_VERSION PATH="$HERE/shims:$PATH" CRYSTAL_PATH="lib:$HOME_DIR/crystal/src" \
    CRYMBLE_WASM_STUB_REPORT=1 \
    "$HOME_DIR/crystal/.build/crystal" build --cross-compile --target wasm32-unknown-wasi -Dwithout_mt "$@" "$src" -o "$out" \
    > "$out.link-line" 2> "$out.stderr"
}
compile() { # SOURCE OUT LEVEL [crystal flags...]
  build "$@" || { cat "$2.stderr" >&2; fail "$(basename "$1") ($3) did not compile"; }
}
# Link, then optimize with wasm-opt as bin/crymble-web ships every build; an invalid module fails with V8's reason.
link() { # OBJECT OUT [wasm-ld args...]
  local obj=$1 out=$2
  shift 2
  local libs
  libs=$(tr ' ' '\n' < "${obj%.wasm}.link-line" | grep -x -- '-l.*' | grep -vx -- '-lc' | sort -u | tr '\n' ' ')
  # shellcheck disable=SC2086
  "$SDK/bin/wasm-ld" "$obj" "$HOME_DIR/lib/cpp_tag.o" "$@" -o "$out.linked" -L"$HOME_DIR/lib" \
    -L"$SDK/share/wasi-sysroot/lib/wasm32-wasi" $libs -lc -lwasi-emulated-process-clocks -lwasi-emulated-mman \
    -lwasi-emulated-signal -z stack-size=8388608 --stack-first --fatal-warnings
  node -e "try { new WebAssembly.Module(require('fs').readFileSync('$out.linked')) } catch (e) { console.error(e.message); process.exit(1) }" ||
    fail "$(basename "$out"): the linked module is not valid wasm"
  "$HOME_DIR/binaryen/bin/wasm-opt" -O2 --strip-debug --all-features "$out.linked" -o "$out" ||
    fail "$(basename "$out"): wasm-opt failed"
}
# The stub step's report for a build: "CALLS INVOKES"
stubs() { sed -n 's/^wasm32 stubs: \([0-9]*\) calls, \([0-9]*\) invokes$/\1 \2/p' "$1.stderr"; }

# The toolchain is what this crymble-ui builds with - and the check that says so refuses a stale one.
"$HERE/setup.sh" --check
STALE=$WORK/stale-home
mkdir -p "$STALE" && cp -r "$HOME_DIR/.stamps" "$STALE/"
CRYMBLE_WASM_HOME=$STALE "$HERE/setup.sh" --check || fail "setup.sh --check refused a copy of current stamps"
echo old > "$STALE/.stamps/crystal"
CRYMBLE_WASM_HOME=$STALE "$HERE/setup.sh" --check 2> "$WORK/stale.txt" && fail "setup.sh --check accepted a stale stamp"
grep -q "(crystal) - run bin/crymble-web setup" "$WORK/stale.txt" || fail "setup.sh --check did not name the stale step"

"$SDK/bin/clang" --target=wasm32-wasi --sysroot="$SDK/share/wasi-sysroot" -O2 -c "$HERE/spec/struct_return.c" -o "$WORK/struct_return.o"

cp "$HERE/../../web/crymble.js" "$WORK/crymble.mjs" # an ES module outside any package.json
node --input-type=module -e "import { EV, KEYS } from '$WORK/crymble.mjs'; console.log(JSON.stringify({ EV, KEYS }))" \
  > "$WORK/js_tables.json"

examples=$(grep -c '^ *it "' "$HERE/spec/patch_spec.cr") # every example in the file must run
for level in O0 release; do
  echo "spec.sh: -- $level"
  W=$WORK/$level
  mkdir -p "$W"

  compile "$HERE/spec/patch_spec.cr" "$W/patch_spec" $level --emit llvm-ir
  # Folded by cleanup, a constant's layout number is a literal: no lazy initializer (`NAME:const_init`) for it
  for const in LAYOUT_SPEC_CONSTANT String::HEADER_SIZE; do
    ! grep -qF "\"$const:const_init\"" "$W/patch_spec.ll" || fail "patch_spec ($level): $const is initialized lazily"
  done
  link "$W/patch_spec.wasm" "$W/patch_spec.out.wasm" "$WORK/struct_return.o"
  out=$(node --no-warnings "$HERE/spec/run.mjs" command "$W/patch_spec.out.wasm" 2>&1) || true
  summary "$out"
  echo "$out" | grep -qx "$examples examples, 0 failures, 0 errors, 0 pending" ||
    fail "patch_spec ($level): expected $examples examples, 0 failures"
  if [ $level = release ]; then
    # The optimized build must contain the mismatched call AND invoke its specs exist for - else they test nothing
    read -r calls invokes <<< "$(stubs "$W/patch_spec")"
    echo "patch_spec (release): the stub step retargeted $calls calls, $invokes invokes"
    [ "${calls:-0}" -ge 1 ] && [ "${invokes:-0}" -ge 1 ] ||
      fail "patch_spec (release): no mismatched call or invoke - the optimizer no longer creates the mismatch (LLVM changed?)"
  fi

  if [ $level = O0 ]; then # (the check runs before codegen: one level shows it)
    build "$HERE/spec/layout_guard.cr" "$W/layout_guard" $level && fail "layout_guard compiled"
    grep -q 'instance_sizeof(GuardCell) was folded to [0-9]* before the layout of GuardCell was complete: its final layout gives [0-9]*' \
      "$W/layout_guard.stderr" || { cat "$W/layout_guard.stderr" >&2; fail "layout_guard: not the check's error"; }
    echo "layout_guard: $(grep -o 'instance_sizeof(GuardCell) was folded.*' "$W/layout_guard.stderr")"
  fi

  compile "$HERE/spec/planted_spec.cr" "$W/planted_spec" $level
  link "$W/planted_spec.wasm" "$W/planted_spec.out.wasm"
  out=$(node --no-warnings "$HERE/spec/run.mjs" command "$W/planted_spec.out.wasm" 2>&1) && fail "planted_spec ($level) exited 0"
  summary "$out"
  echo "$out" | grep -qx '3 examples, 1 failures, 1 errors, 0 pending' || fail "planted_spec ($level): the runner did not report the planted failure and error"

  # The web flavour itself: the event round trip against crymble.js's own tables, and its notices
  CRYMBLE_JS_TABLES="$WORK/js_tables.json" compile "$HERE/spec/web_spec.cr" "$W/web_spec" $level
  link "$W/web_spec.wasm" "$W/web_spec.out.wasm"
  out=$(node --no-warnings "$HERE/spec/run.mjs" command "$W/web_spec.out.wasm" 2>&1) || true
  summary "$out"
  echo "$out" | grep -qx '4 examples, 0 failures, 0 errors, 0 pending' || fail "web_spec ($level): expected 4 examples, 0 failures"

  compile "$HERE/spec/soak.cr" "$W/soak" $level -Dwithout_main
  link "$W/soak.wasm" "$W/soak.out.wasm" "$SDK/share/wasi-sysroot/lib/wasm32-wasi/crt1-reactor.o" --no-entry \
    --export=_initialize --export=soak_init --export=soak_tick --export=soak_gc --export=soak_check \
    --export=soak_finalized --export=soak_heap_kb
  node --no-warnings "$HERE/spec/run.mjs" soak "$W/soak.out.wasm" || fail "soak ($level)"
done

echo "spec.sh: PASS"
