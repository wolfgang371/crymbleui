# The web flavour

A crymble-ui app builds in two flavours from the same source: the **desktop** one (`shards build`, SFML) and the
**web** one (`bin/crymble-web build`): a static web page whose WebAssembly module is the same Crystal, drawing on
an HTML canvas. The app does not change, and nothing in it is compiled conditionally: the flavour is a property
of the build, decided inside crymble-ui. The README's "In a browser" section is the quick start; this page is the
model.

## How it fits together

```
 the app (unchanged)          CrymbleUI.run(app)
        |                           |
 crymble-ui                 desktop: SFMLRenderer#run  - a blocking loop, as always
   WindowRenderer           web:     WebRenderer#start - returns; the page ticks it
   (loop decisions,                   |
    dispatch, frame,        src/web/entry.cr   crymble_init / crymble_tick / crymble_gc ... (wasm exports)
    composite)              src/web/*.cr       WebRenderer, WebBackend (a canvas), WebFont, WebClipboard
        |                           |  imports, module "crymble" (src/web/js.cr)
        |                   web/crymble.js     the canvases, SFML's raster and blend rules, input -> CSFML events
        |                   web/crymble-web.js the loader: download, WASI, font, the frame loop, unsupported()
        |                   web/index.html     the generic page (an app may bring its own web/index.html)
```

- **One loop, two drivers.** `WindowRenderer` holds everything a frame needs that is not platform: event dispatch,
  the loop's decisions (timers, rebuilds, the redraw verdict), the frame and the compositor. `SFMLRenderer` drives
  it with a blocking loop; `WebRenderer` with `start` once and `tick` per animation frame. (docs/ARCHITECTURE.md,
  "Renderers, and driving the loop".)
- **Which flavour** is chosen in `src/crymble-ui.cr` by the target (`flag?(:wasm32)`): the web flavour requires
  `src/web/entry.cr` instead of SFML. An app's own code never asks.
- **The page drives.** `crymble_init` runs the app's top level (which reaches `CrymbleUI.run`, which starts the
  renderer and returns); then the page calls `crymble_tick` each animation frame (2 rendered, 1 idle, 0 closed,
  -1 failed) and `crymble_gc` after it.
- **Garbage collection only between ticks.** WebAssembly keeps a function's locals outside linear memory, where
  Boehm cannot see them; between two ticks no wasm function runs, so a collection there sees every live object.
  The collector is disabled otherwise (src/web/entry.cr).
- **Input** arrives as CSFML events built from the page's DOM events (`next_event`), so the dispatch is the
  desktop's own. Keys follow the keyboard layout as SFML's do (Ctrl+Z on a German layout is the Z key).
- **Files** live in an in-memory file system in the tab (`/home/user`, `/tmp`); they are gone when it closes.
- **The font** is the one crymble-ui embeds; the page loads it from the module's memory before the app starts.

## Building

```bash
bin/crymble-web setup                       # once (Linux x86_64)
bin/crymble-web build [TARGET...|FILE.cr]   # bin/web/<target>/ - all shard.yml targets when none is named
bin/crymble-web build ... --release         # with flag?(:release) set, as a release build of the app is
bin/crymble-web build ... --local           # marks the page "local build - not for publication"
bin/crymble-web serve [TARGET] [PORT]       # http://127.0.0.1:8765/
```

`bin/web/<target>/` is the whole site: `index.html`, `<target>.wasm`, `crymble-web.js`, `crymble.js`, `vendor/`
(browser_wasi_shim), `NOTICES`. Serve it from any static web server (the module is `application/wasm`).

**The toolchain** (`tools/wasm/setup.sh`, into `~/.cache/crymble-wasm`, about 1 GB; a few minutes - measured
3 minutes from an empty cache): wasi-sdk 25 (clang, wasm-ld, wasi-libc), Binaryen 123 (wasm-opt), Crystal 1.22.0
with `tools/wasm/crystal-1.22.0-wasm.patch` built against the host's LLVM 18, and the C libraries Crystal links,
built for wasm32: Boehm GC 8.2.8, zlib 1.3.1, libxml2 2.13.8, PCRE2 10.42. Every download is pinned by SHA-256;
each step is skipped while what it was built from is unchanged. The host needs LLVM 18 development files
(`llvm-config-18`), a C++ compiler, cmake, git, curl, pkg-config, python3 (the build fills the page, `serve` serves it), the development files of libpcre2-8, libffi and
zlib, and a Crystal >= 1.20 to build the compiler with.

**The patch** (its header lists each change and why): wasm exceptions (stock 1.22 exits on `raise`), struct
returns from C, Boehm as wasm32's collector (stock: no collection at all) with its static data registered as roots,
finalizer callbacks that return void, and three WASI file-system fixes. Boehm is built with `ALL_INTERIOR_POINTERS`
(an `Array#shift`ed buffer is reachable only through an interior pointer) and `ALWAYS_SMALL_CLEAR_STACK`.

**Linking**: the compile runs `-O0` (LLVM 18 emits invalid wasm exception handling when it optimizes); wasm-opt
`-O2` optimizes the linked module. So `--release` is the release FLAG only (`-Drelease`: what an app shows or skips
in a release build, `flag?(:release)`), not Crystal's `--release`, which would also turn LLVM's optimizer on. The compiler asks pkg-config for library versions at compile time - a shim
(`tools/wasm/shims/pkg-config`) answers with the toolchain's, so nothing of the host's `-dev` packages leaks in.
An app whose `@[Link]` names a library the toolchain has no wasm build of fails to build, by name.

**Size**: a crymble-ui app is about 3.5 MB of wasm, 1.4 MB gzipped.

## The page

The generic page shows the target's name, what it is, "files you save live in this tab", the app's and
crymble-ui's versions and commits, a source link (`repository:` in the app's `shard.yml`), the `NOTICES` link and
the shortcuts the browser keeps for itself (below). An app brings its own page as `web/index.html`; the build fills
the placeholders `{{target}} {{wasm}} {{name}} {{version}} {{repository}} {{commit}} {{crymble_ui_version}}
{{crymble_ui_commit}} {{versions}} {{built}} {{banner}}` (HTML-escaped) and copies the rest unchanged. A page
boots the app with:

```js
import { boot } from './crymble-web.js';
boot({ canvas, wasmUrl: '{{wasm}}', confirmLeave: true, onStatus(kind, text) { ... } });
```

`onStatus` kinds: `progress`, `starting`, `running`, `unsupported`, `closed`, `error`, `stderr`, `shortcuts`.
`unsupported()` says why a browser cannot run it (no WebAssembly exception handling; no fine pointer - a
touch-only device) before anything is downloaded. `confirmLeave` asks before the tab closes once the visitor has
given input. The canvas fills whatever box the page gives it and follows its size.

**Licences.** `NOTICES` lists everything the folder ships or the module links (the build fails on a linked library
or an installed shard without a licence entry). What an app's About shows comes from `CrymbleUI.backend_notices`,
which answers per flavour. An app under a copyleft licence decides its own source offer: the page's source link and
`--local` are the tool's part, not a policy.

## What differs from the desktop

- **Pixels.** Filled geometry, outlines, lines, circles, clips, images (tint included) and layer compositing in
  every blend mode paint the desktop's pixels: `tools/wasm/conformance` holds them to within one level per channel
  (two where blending rounds). The canvas reproduces SFML's rules - the pixel-centre rule with the top-left tie
  rule (on the window as the GPU applies it, on every other canvas as a y-flipped RenderTexture does -
  `PixelSnap.fill_edge` / `fill_edge_y_flipped`), SFML's 30-point circle, and SFML's
  blend arithmetic on a layer texel that already carries its alpha (src/web docs, `composite` in crymble.js).
- **Text.** Glyphs are the browser's antialiasing of the same font; layout metrics come from the browser's
  measurement, grid-fitted as FreeType's are, and agree with the desktop within 1 px at the sizes checked (8 to 30
  px). Measured exception: at 12 px FreeType's hinting draws the font 2 px taller ("Ag" 12 px high on the desktop,
  10 px in the browser), so text at that size sits 1 px differently; the conformance pins exactly this gap.
- **Tabs** advance four spaces' widths, as in sf::Text (the canvas's own tab is one space); at 16 px the four
  add up 2 px short of the desktop's (pinned by the conformance).
- **Keys the browser keeps.** A tab never sees Ctrl+W, Ctrl+N, Ctrl+T, Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+PageUp/Down,
  Ctrl+Shift+N/T/W (documented browser behaviour, not measured: synthetic keys never reach the browser's own
  accelerators). The page lists which of the app's shortcuts - its registered ones and crymble-ui's built-ins -
  are among them; giving them other keys is the app's business. F5, F11 and F12 are left to the browser.
- **macOS.** Cmd shortcuts are not mapped to Ctrl ones; Cmd+key types nothing.
- **Clipboard.** Ctrl+C / Ctrl+X write the system clipboard; Ctrl+V / Shift+Insert paste from it (the browser's
  paste event). A paste the app starts without a key (a menu item reading the clipboard) gets the text last
  pasted or copied in the tab - a browser does not let a page read the clipboard unasked.
- **Dead keys and IME** are not measurable headlessly (synthetic keys bypass the OS layout); untested.
- **Speed.** An idle tick costs about 0.2 ms. Headless Chromium rasterizes in software: there a VirtualMatrix
  scroll step takes 100 to 250 ms and a small redraw that composites every layer (the showcase's CPU monitor)
  about 125 ms. A browser with GPU canvases is much faster; not measured here.

## Checks

`tools/wasm/check.sh` (from crymble-ui's root, after `source setup.sh`, with `DISPLAY` set), before a push that
touches the web flavour (CREDO):

1. `spec.sh` - the patch's suite, the web flavour's own spec and a garbage-collection soak, under Node's WASI:
   exceptions, struct returns, the file-system fixes, the toolchain's library versions, a planted failure and
   error the runner must report, the event round trip (crymble.js's event and key tables against crymble-ui's
   enums, every field of every event kind), the web `backend_notices`, and 2000 ticks with collections between
   them (heap flat, finalizers run, data intact).
2. builds tutorial-22, tutorial-07, tutorial-24 and showcase_demo, unchanged.
3. `conformance.sh` - one program (`tools/wasm/conformance/conformance.cr`) in both flavours, each case read back
   and compared by `diff.mjs`; every RenderBackend drawing method has a case, enumerated by a macro. Its first
   file-system calls are a file dialog's (list a folder, stat each entry) - in the page those once made wasi-libc
   exit, because the shim answered ENOTSUP where WASI hosts answer EBADF (crymble-web.js translates it). Cases whose
   desktop result contradicts RenderBackend's contract are held to the contract instead (the desktop's
   `blit_region` samples a flipped band - tracked in the backlog; its one caller is the cache validator).
4. `smoke.mjs` - the four builds in headless Chromium: clicks, the wheel, blit-shift scrolling, 20 scroll cycles
   with collections (heap and live canvases flat, canvases made and freed), typing, AltGr, Ctrl+C to the system
   clipboard, an external paste, keys claimed or left to the browser, the leave guard, a viewport resize, a late
   image, the shortcut note, the source link, and the unsupported-browser messages.
5. `readme_check.sh` - the README's commands in a scratch app made of the README's own stanza and Quick Start.

Each check was shown failing with its piece broken. The stock compiler type-checks the web flavour
(`crystal build --no-codegen --cross-compile --target wasm32-unknown-wasi -Dwithout_mt -Dwithout_main`), so CI
can do that without the toolchain.

Node 18 or newer; playwright-core (pinned in `tools/wasm/package.json`, `npm ci`) with its Chromium
(`npx playwright-core install chromium-headless-shell`) or any Chrome binary as `CRYMBLE_CHROMIUM`.

## Browsers

Tested: Chromium (headless, by the checks above). Not yet tested by hand: Firefox, Safari, a GPU-backed Chrome.
The showcase is live at https://wolfgang371.github.io/crymbleui/ (since v1.9.0) and the README links it, naming the
browsers it is tested in (`LIVE_DEMO_TESTED` in scripts/generate-readme.cr) - widen that once a manual Firefox and
Safari pass is recorded here.

## Publishing the showcase

`tools/wasm/pages.sh` builds the showcase and writes the site to `bin/pages/`. A release publishes it: after the
release push, `scripts/publish.sh` runs `.publish.after-push.sh`, which asks, builds the site from the release
commit (its page names the release tag) and force-pushes it as a single orphan commit to the public remote's
`gh-pages` branch - the page always shows the latest release. Once, by hand: GitHub > Settings > Pages > serve the
`gh-pages` branch. A machine that publishes needs the toolchain (`bin/crymble-web setup`); without it the hook
says so and leaves `gh-pages` as it was - run `.publish.after-push.sh <tag>` by hand after the setup.
