#!/usr/bin/env bash
# ============================================================================
# Linux release build for the CrymbleUI showcase demo — single, self-contained
# script. Produces a portable AppImage with all NON-system dependencies (the
# vendored SFML 3 / CSFML 3 .so) bundled. The Linux counterpart of win-build.bat.
#
#   Output: temp/crymbleui-showcase-linux-x86_64.AppImage
#
# No branded icon: AppImage tooling (linuxdeploy / appimagetool) REQUIRES some
# icon, so we generate a plain placeholder square at build time. Nothing icon-
# related is checked into the repo. Drop in a real icon later by replacing the
# `convert` line with a committed PNG.
#
# Prerequisites:
#   1. crystal + `shards install` already run.
#   2. ImageMagick (`convert`), patchelf, file — for the placeholder + the
#      dependency-bundling that linuxdeploy performs.
#   3. Network access: linuxdeploy + appimagetool are downloaded on first run
#      (they are themselves AppImages).
#
# Everything this script produces lives under temp/ (gitignored), so a build
# leaves NOTHING behind in the working tree. This is the exact build the Release
# workflow (.github/workflows/release.yml) runs on a v* tag.
# ============================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

TEMP="temp"
APPDIR="$TEMP/AppDir"

rm -rf "$APPDIR"
mkdir -p "$TEMP"

# linuxdeploy + appimagetool are AppImages; GitHub runners (ubuntu-24.04) ship no
# FUSE, so run them via their built-in extract-and-run path instead.
export APPIMAGE_EXTRACT_AND_RUN=1

# 1) Wire the vendored SFML 3 / CSFML 3 paths (LD_LIBRARY_PATH) so both the
#    linker and `ldd` (which linuxdeploy walks) resolve them.
# shellcheck source=/dev/null
source setup.sh

# 2) Build the release binary. NOT --static: the C/SFML deps are bundled into the
#    AppImage instead, and a fully static GUI binary is fragile on Linux anyway.
#    (The font + themes are compiled in via read_file, so no runtime resources.)
shards build showcase_demo --release --no-debug

# 3) Fetch linuxdeploy (assembles the AppDir) + appimagetool (packs it). Cached
#    across local re-runs. linuxdeploy walks ldd, copies the dependency closure
#    into the AppDir, patches RPATHs, and honours the AppImage excludelist — so
#    host libraries (libGL, libX11, libxcb, the GL driver stack) are deliberately
#    NOT bundled (the user supplies those, same as CI's apt list).
fetch() { [ -f "$TEMP/$1" ] || wget -qO "$TEMP/$1" "$2"; chmod +x "$TEMP/$1"; }
fetch linuxdeploy  https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage

# 4) Plain placeholder icon. linuxdeploy matches the icon file's basename against
#    the .desktop Icon= entry, so it MUST be named showcase_demo.png.
convert -size 256x256 xc:'#2d3237' "$TEMP/showcase_demo.png"

# 5) Minimal desktop entry (generated, not committed).
cat > "$TEMP/showcase_demo.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=CrymbleUI Showcase
Exec=showcase_demo
Icon=showcase_demo
Categories=Development;
Terminal=false
DESKTOP

# 6) Assemble the AppDir (deps + RPATHs + AppRun + desktop/icon at the root).
"$TEMP/linuxdeploy" \
    --appdir "$APPDIR" \
    --executable bin/showcase_demo \
    --desktop-file "$TEMP/showcase_demo.desktop" \
    --icon-file "$TEMP/showcase_demo.png"

# 7) Pack the AppImage under the stable, version-less name the website can link
#    (/releases/latest/download/crymbleui-showcase-linux-x86_64.AppImage); the
#    version stays visible in the GitHub Release title.
"$TEMP/appimagetool" "$APPDIR" "$TEMP/crymbleui-showcase-linux-x86_64.AppImage"

echo "OK: temp/crymbleui-showcase-linux-x86_64.AppImage built ($(du -h "$TEMP/crymbleui-showcase-linux-x86_64.AppImage" | cut -f1))."
