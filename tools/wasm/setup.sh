#!/bin/bash
# The toolchain the web flavour builds with (bin/crymble-web setup runs this). Idempotent: each step leaves a stamp
# keyed by what it was built from, and is skipped while that key is unchanged.
#
# Into ${CRYMBLE_WASM_HOME:-$HOME/.cache/crymble-wasm}:
#   wasi-sdk/      clang, wasm-ld and the wasm32-wasi sysroot (libc, crt1-reactor.o, pthread/dl stubs)
#   binaryen/      wasm-opt (optimizes every linked module)
#   crystal/       Crystal 1.22.0 + crystal-1.22.0-wasm.patch, built against the system's LLVM 18
#   lib/           the C libraries Crystal's standard library links, built for wasm32: libgc (Boehm), libz,
#                  libxml2 (with the accessor shim inside), libpcre2-8; cpp_tag.o
#
# Build host: Linux x86_64 with LLVM 18 development files (llvm-config-18), a C++ compiler, cmake, git, curl,
# the development files of libpcre2-8, libffi and zlib, and a Crystal >= 1.20 to build the compiler with.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOME_DIR=${CRYMBLE_WASM_HOME:-$HOME/.cache/crymble-wasm}
STAMPS=$HOME_DIR/.stamps
DOWNLOADS=$HOME_DIR/downloads

WASI_SDK_URL=https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-25/wasi-sdk-25.0-x86_64-linux.tar.gz
WASI_SDK_SHA=52640dde13599bf127a95499e61d6d640256119456d1af8897ab6725bcf3d89c
BINARYEN_URL=https://github.com/WebAssembly/binaryen/releases/download/version_123/binaryen-version_123-x86_64-linux.tar.gz
BINARYEN_SHA=e959f2170af4c20c552e9de3a0253704d6a9d2766e8fdb88e4d6ac4bae9388fe
WASM_LIBS_URL=https://github.com/lbguilherme/wasm-libs/releases/download/0.0.3/wasm32-wasi-libs.tar.gz
WASM_LIBS_SHA=cd36f319f8f9f9cd08f723d10e6ec2b92f2e44d3ce3b20344b8041386d85c261
ZLIB_URL=https://zlib.net/fossils/zlib-1.3.1.tar.gz
ZLIB_SHA=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
LIBXML2_URL=https://download.gnome.org/sources/libxml2/2.13/libxml2-2.13.8.tar.xz
LIBXML2_SHA=277294cb33119ab71b2bc81f2f445e9bc9435b893ad15bb2cd2b0e859a0ee84a
BDWGC_URL=https://github.com/ivmai/bdwgc/releases/download/v8.2.8/gc-8.2.8.tar.gz
BDWGC_SHA=7649020621cb26325e1fb5c8742590d92fb48ce5c259b502faf7d9fb5dabb160
CRYSTAL_TAG=1.22.0
CRYSTAL_COMMIT=39f3f4d08f70c3678b579f85dc6f8b7be69c7956
PATCH=$HERE/crystal-1.22.0-wasm.patch

die() { echo "crymble-web setup: $*" >&2; exit 1; }
say() { echo "crymble-web setup: $*"; }

# --- prerequisites -------------------------------------------------------------------------------------------
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || die "builds on Linux x86_64 only (this is $(uname -s) $(uname -m))"
LLVM_CONFIG=$(command -v llvm-config-18 || true)
[ -n "$LLVM_CONFIG" ] || [ ! -x /usr/lib/llvm-18/bin/llvm-config ] || LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config
[ -n "$LLVM_CONFIG" ] || die "needs LLVM 18 development files (llvm-config-18; e.g. the llvm-18-dev package)"
case "$("$LLVM_CONFIG" --version)" in 18.*) ;; *) die "$LLVM_CONFIG is not LLVM 18";; esac

# --- what each step is built from: its stamp's key -----------------------------------------------------------
XML_KEY="$LIBXML2_SHA $(sha256sum "$HERE/shims/xmlshim.c" "$HERE/shims/dupstub.h" | cut -c1-16 | tr -d '\n')"
GC_KEY="$BDWGC_SHA $(sha256sum "$HERE"/shims/gcroots.c "$HERE"/shims/setjmp.h "$HERE"/shims/emscripten/stack.h | cut -c1-16 | tr -d '\n')"
TAG_KEY=$(sha256sum "$HERE/shims/cpp_tag.s" | cut -c1-16)
CRYSTAL_KEY="$CRYSTAL_COMMIT $(sha256sum "$PATCH" | cut -c1-16) $("$LLVM_CONFIG" --version)"

# done_with KEY NAME: true if step NAME was completed from KEY
done_with() { [ -f "$STAMPS/$2" ] && [ "$(cat "$STAMPS/$2")" = "$1" ]; }

# setup.sh --check: exit 0 if every step is built from what this crymble-ui needs, else name the stale ones (every
# step below is listed here)
if [ "${1:-}" = --check ]; then
  stale=()
  for step in "wasi-sdk $WASI_SDK_SHA" "binaryen $BINARYEN_SHA" "pcre2 $WASM_LIBS_SHA" "zlib $ZLIB_SHA" \
    "libxml2 $XML_KEY" "bdwgc $GC_KEY" "cpp_tag $TAG_KEY" "crystal $CRYSTAL_KEY"; do
    done_with "${step#* }" "${step%% *}" || stale+=("${step%% *}")
  done
  [ ${#stale[@]} = 0 ] && exit 0
  die "the toolchain in $HOME_DIR is not what this crymble-ui builds with (${stale[*]}) - run bin/crymble-web setup"
fi
for tool in g++ cmake git curl crystal pkg-config; do
  command -v "$tool" > /dev/null || die "needs $tool"
done
for pc in libpcre2-8 libffi zlib; do
  pkg-config --exists "$pc" || die "needs the development files of $pc (e.g. libpcre2-dev, libffi-dev, zlib1g-dev)"
done

mkdir -p "$STAMPS" "$DOWNLOADS" "$HOME_DIR/lib"

# --- helpers -------------------------------------------------------------------------------------------------
stamp() { echo "$1" > "$STAMPS/$2"; }

# fetch URL SHA256 -> prints the verified local path
fetch() {
  local file=$DOWNLOADS/$(basename "$1")
  if [ ! -f "$file" ] || ! echo "$2  $file" | sha256sum -c --status; then
    curl -fsSL -o "$file.part" "$1"
    echo "$2  $file.part" | sha256sum -c --status || die "checksum mismatch for $1"
    mv "$file.part" "$file"
  fi
  echo "$file"
}

SDK=$HOME_DIR/wasi-sdk
CC="$SDK/bin/clang --target=wasm32-wasi --sysroot=$SDK/share/wasi-sysroot -O2"

# --- wasi-sdk, binaryen --------------------------------------------------------------------------------------
if ! done_with "$WASI_SDK_SHA" wasi-sdk; then
  say "wasi-sdk 25"
  rm -rf "$SDK" && mkdir -p "$SDK"
  tar xzf "$(fetch $WASI_SDK_URL $WASI_SDK_SHA)" -C "$SDK" --strip-components=1
  stamp "$WASI_SDK_SHA" wasi-sdk
fi
if ! done_with "$BINARYEN_SHA" binaryen; then
  say "binaryen 123"
  rm -rf "$HOME_DIR/binaryen" && mkdir -p "$HOME_DIR/binaryen"
  tar xzf "$(fetch $BINARYEN_URL $BINARYEN_SHA)" -C "$HOME_DIR/binaryen" --strip-components=1
  stamp "$BINARYEN_SHA" binaryen
fi

# --- the C libraries Crystal's standard library links, for wasm32 ---------------------------------------------
BUILD=$HOME_DIR/build
mkdir -p "$BUILD"
if ! done_with "$WASM_LIBS_SHA" pcre2; then
  say "pcre2 10.42 (prebuilt, Crystal's wasm32-wasi-libs 0.0.3)"
  rm -rf "$BUILD/wasm-libs" && mkdir -p "$BUILD/wasm-libs"
  tar xzf "$(fetch $WASM_LIBS_URL $WASM_LIBS_SHA)" -C "$BUILD/wasm-libs"
  cp "$BUILD/wasm-libs/libpcre2-8.a" "$HOME_DIR/lib/" # ONLY pcre2: libc and libgc come from wasi-sdk and below
  stamp "$WASM_LIBS_SHA" pcre2
fi
if ! done_with "$ZLIB_SHA" zlib; then
  say "zlib 1.3.1"
  rm -rf "$BUILD/zlib" && mkdir -p "$BUILD/zlib"
  tar xzf "$(fetch $ZLIB_URL $ZLIB_SHA)" -C "$BUILD/zlib" --strip-components=1
  (cd "$BUILD/zlib" && for f in adler32 crc32 deflate inflate inftrees inffast trees zutil; do $CC -c $f.c -o $f.o; done &&
    rm -f "$HOME_DIR/lib/libz.a" && "$SDK/bin/llvm-ar" rcs "$HOME_DIR/lib/libz.a" *.o)
  stamp "$ZLIB_SHA" zlib
fi
if ! done_with "$XML_KEY" libxml2; then
  say "libxml2 2.13.8"
  rm -rf "$BUILD/libxml2" && mkdir -p "$BUILD/libxml2"
  tar xJf "$(fetch $LIBXML2_URL $LIBXML2_SHA)" -C "$BUILD/libxml2" --strip-components=1
  cmake -S "$BUILD/libxml2" -B "$BUILD/libxml2/build" -DCMAKE_TOOLCHAIN_FILE="$SDK/share/cmake/wasi-sdk.cmake" \
    -DWASI_SDK_PREFIX="$SDK" -DCMAKE_BUILD_TYPE=Release "-DCMAKE_C_FLAGS=-include $HERE/shims/dupstub.h" \
    -DBUILD_SHARED_LIBS=OFF -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_ZLIB=OFF -DLIBXML2_WITH_LZMA=OFF \
    -DLIBXML2_WITH_ICONV=OFF -DLIBXML2_WITH_THREADS=OFF -DLIBXML2_WITH_HTTP=OFF -DLIBXML2_WITH_FTP=OFF \
    -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_MODULES=OFF > "$BUILD/libxml2.cmake.log"
  cmake --build "$BUILD/libxml2/build" -j"$(nproc)" > "$BUILD/libxml2.build.log"
  cp "$BUILD/libxml2/build/libxml2.a" "$HOME_DIR/lib/libxml2.a"
  # The accessor shim goes INTO the archive: only a program that uses XML pulls it in.
  $CC -c "$HERE/shims/xmlshim.c" -o "$BUILD/xmlshim.o"
  "$SDK/bin/llvm-ar" rs "$HOME_DIR/lib/libxml2.a" "$BUILD/xmlshim.o"
  stamp "$XML_KEY" libxml2
fi
if ! done_with "$GC_KEY" bdwgc; then
  say "Boehm GC 8.2.8"
  rm -rf "$BUILD/bdwgc" && mkdir -p "$BUILD/bdwgc"
  tar xzf "$(fetch $BDWGC_URL $BDWGC_SHA)" -C "$BUILD/bdwgc" --strip-components=1
  # EMSCRIPTEN: the configuration for WebAssembly (sbrk, no mmap, no signals); ALL_INTERIOR_POINTERS: Crystal's
  # Array#shift keeps a pointer into its buffer (without it the buffer is freed while live - measured);
  # ALWAYS_SMALL_CLEAR_STACK: the recursive stack clearing never ends on wasm; sbrk -> gc_wasm_sbrk: wasi-libc's
  # sbrk takes whole 64 KiB pages only.
  $CC -I "$BUILD/bdwgc/include" -I "$HERE/shims" -DEMSCRIPTEN -DALL_INTERIOR_POINTERS -DALWAYS_SMALL_CLEAR_STACK \
    -DNO_GETCONTEXT -DNO_EXECUTE_PERMISSION -DGC_DISABLE_INCREMENTAL -D_WASI_EMULATED_PROCESS_CLOCKS \
    -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_MMAN -Dsbrk=gc_wasm_sbrk -c "$BUILD/bdwgc/extra/gc.c" -o "$BUILD/gc.o"
  $CC -c "$HERE/shims/gcroots.c" -o "$BUILD/gcroots.o"
  rm -f "$HOME_DIR/lib/libgc.a" && "$SDK/bin/llvm-ar" rcs "$HOME_DIR/lib/libgc.a" "$BUILD/gc.o" "$BUILD/gcroots.o"
  stamp "$GC_KEY" bdwgc
fi
if ! done_with "$TAG_KEY" cpp_tag; then
  "$SDK/bin/clang" --target=wasm32-wasi -mexception-handling -c "$HERE/shims/cpp_tag.s" -o "$HOME_DIR/lib/cpp_tag.o"
  stamp "$TAG_KEY" cpp_tag
fi

# --- Crystal 1.22.0 + the patch ------------------------------------------------------------------------------
if ! done_with "$CRYSTAL_KEY" crystal; then
  say "Crystal $CRYSTAL_TAG + the wasm patch (a few minutes)"
  rm -rf "$HOME_DIR/crystal"
  git clone -q --depth 1 -b "$CRYSTAL_TAG" https://github.com/crystal-lang/crystal.git "$HOME_DIR/crystal" 2> /dev/null
  [ "$(git -C "$HOME_DIR/crystal" rev-parse HEAD)" = "$CRYSTAL_COMMIT" ] || die "tag $CRYSTAL_TAG is not commit $CRYSTAL_COMMIT"
  git -C "$HOME_DIR/crystal" apply "$PATCH"
  make -C "$HOME_DIR/crystal" crystal LLVM_CONFIG="$LLVM_CONFIG" FLAGS=-Dwithout_interpreter > "$BUILD/crystal.build.log" 2>&1 ||
    die "building Crystal failed; see $BUILD/crystal.build.log"
  stamp "$CRYSTAL_KEY" crystal
fi

say "ready in $HOME_DIR"
