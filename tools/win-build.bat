@echo off
REM ============================================================================
REM Windows release build for the CrymbleUI showcase demo — single, self-contained
REM script. Produces bin\showcase_demo.exe (static, no DLLs, no icon). The Windows
REM counterpart of tools/build-appimage.sh.
REM
REM Prerequisites:
REM   1. An MSVC "x64 Native Tools" command prompt (provides cl.exe, link.exe).
REM   2. shards install
REM      (crymble-ui ships the SFML 3 / CSFML 3 win32 static libs, so there is no
REM       separate SFML build step.)
REM
REM No icon resource is compiled in — by design, this is the demo, not a branded
REM app. (Font + themes are compiled into the binary via read_file, so the .exe is
REM self-contained.) This is the exact build the Release workflow
REM (.github/workflows/release.yml) runs on a v* tag.
REM ============================================================================
setlocal
cd /d "%~dp0.."

REM 1) Wire the vendored SFML 3 / CSFML 3 linker paths (LIB / INCLUDE) via the
REM    canonical env shim.
call setup.bat || (echo env setup failed & exit /b 1)

REM 2) Build a STATIC, self-contained .exe (fat binary). --static makes Crystal
REM    link its C deps (iconv, pcre2, xml2, z, gc) statically too — without it they
REM    link dynamically and a clean Windows box errors with "iconv-2.dll not found".
REM    The vendored SFML/CSFML win32 libs are already static, so the result needs
REM    no runtime DLLs.
shards build showcase_demo --release --no-debug --static || (echo build failed & exit /b 1)

echo.
echo OK: bin\showcase_demo.exe built (static, self-contained).
endlocal
