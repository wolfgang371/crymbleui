# The web flavour

A crymble-ui app builds in two flavours from the same source: the **desktop** one (`shards build`, SFML) and the
**web** one (`bin/crymble-web build`): a static web page whose WebAssembly module is the same Crystal, drawing on
an HTML canvas. The app does not change, and nothing in it is compiled conditionally: the flavour is a property
of the build, decided inside crymble-ui. The README's "Building for the browser" section is the quick start; this page is the
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
bin/crymble-web build ... --release         # a release build: LLVM-optimized, flag?(:release) set
bin/crymble-web build ... --local           # marks the page "local build - not for publication"
bin/crymble-web serve [TARGET] [PORT]       # http://127.0.0.1:8765/
bin/crymble-web publishable TARGET|DIR...   # fails unless each site is a release build without --local
```

Only a release build is for publication. Any other - the quick -O0 default, or `--local` - says so in its page's
bar ("-O0 build - not for publication") and in a line of `NOTICES`; `publishable` reads that line, and every script
that publishes a page calls it first: the showcase's (`.publish.after-push.sh`), Minesweeper's, Embrace's
`web/build.sh`.

`bin/web/<target>/` is the whole site: `index.html`, `<target>.wasm`, `crymble-web.js`, `crymble.js`, `vendor/`
(browser_wasi_shim), `NOTICES`. Serve it from any static web server (the module is `application/wasm`).

**The toolchain** (`tools/wasm/setup.sh`, into `~/.cache/crymble-wasm`, about 1 GB; a few minutes - measured
3 minutes from an empty cache): wasi-sdk 25 (clang, wasm-ld, wasi-libc), Binaryen 123 (wasm-opt), Crystal 1.22.0
with `tools/wasm/crystal-1.22.0-wasm.patch` built against the host's LLVM 18, and the C libraries Crystal links,
built for wasm32: Boehm GC 8.2.8, zlib 1.3.1, libxml2 2.13.8, PCRE2 10.42. Every download is pinned by SHA-256;
each step is skipped while what it was built from is unchanged; `setup.sh --check` (which `build`, `spec.sh` and
an app's own checks call first) refuses a toolchain built from anything else, naming the stale steps. Apps whose
crymble-ui versions carry different patches rebuild a shared toolchain in turn - give each its own
`CRYMBLE_WASM_HOME` to avoid it. The host needs LLVM 18 development files
(`llvm-config-18`), a C++ compiler, cmake, git, curl, pkg-config, python3 (the build fills the page, `serve` serves it), the development files of libpcre2-8, libffi and
zlib, and a Crystal >= 1.20 to build the compiler with.

**The patch** (its header lists each change and why): wasm exceptions (stock 1.22 exits on `raise`), struct
returns from C, Boehm as wasm32's collector (stock: no collection at all) with its static data registered as roots,
finalizer callbacks that return void, three WASI file-system fixes, what an LLVM-optimized build needs (below),
and layout numbers computed from complete types. Stock Crystal fixes `sizeof`, `alignof`, `instance_sizeof`,
`instance_alignof` and `offsetof` while it types the program, through a typer that caches each layout: a field typed
by a generic module whose including struct does not exist yet is laid out as a pointer, so `dup` copies too few bytes
(Embrace's reference cells lost their link to their table - the tab crashed on Enter). The patch folds them after
typing, and inside a type argument (which needs the number while typing) through a fresh typer; every folded number
is checked against the final layout before and after codegen, a difference a compile error naming the expression.
Native builds use the stock compiler and stay exposed until upstream Crystal fixes it (an issue is to be filed).
Boehm is built with `ALL_INTERIOR_POINTERS`
(an `Array#shift`ed buffer is reachable only through an interior pointer) and `ALWAYS_SMALL_CLEAR_STACK`.

**Optimizing**: `--release` compiles with Crystal's `--release` (LLVM `-O3`, one module) and `-Drelease` (what an app
shows or skips in a release build, `flag?(:release)`); a build without it is `-O0`, quick to compile. wasm-opt `-O2`
optimizes every linked module. Two things in the patch make the optimized build valid wasm. `__crystal_raise` is
never inlined: inlined into a rescue body, its `llvm.wasm.throw` would become an invoke, which LLVM forbids. And
after the optimizer, a direct call whose type differs from its callee's with a struct or array parameter or return
calls a stub whose body is `unreachable`: the optimizer makes such calls out of the branch of a proc call that never
runs for the proc at hand (the closure-data branch on a plain function, or the other one on a closure's), and LLVM's
WebAssembly backend - which adapts such calls without aggregates, and gives the ones it cannot adapt this very stub -
emits invalid wasm with one. A call with fewer arguments would read a missing one natively too; one with more is
harmless natively and traps here; neither runs for a proc Crystal builds. Never run wasm-opt with
`--traps-never-happen` or `--ignore-implicit-traps`: the stubs are traps.

**Linking**: the compiler asks pkg-config for library versions at compile time - a shim
(`tools/wasm/shims/pkg-config`) answers with the toolchain's, so nothing of the host's `-dev` packages leaks in.
An app whose `@[Link]` names a library the toolchain has no wasm build of fails to build, by name.

**Size and speed**: a crymble-ui app is about 2.1 MB of wasm, 0.8 MB gzipped, as a release (3.6 MB, 1.4 MB at
`-O0`). Measured 2026-10-18 (headless, median of 5), release against `-O0`: crymble-ui's own frame work 2.6 to 5.9
times faster (tutorial-22's scrolling, the soak's ticks), Embrace's domain specs 2.5 times; a release compile of
Embrace takes 165 s against 92 s.

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

1. `spec.sh` - first `setup.sh --check` (and that it refuses a stale stamp), then the patch's suite, the web
   flavour's own spec and a garbage-collection soak under Node's WASI, every part built twice - at `-O0` and as a
   release - and each module validated and optimized by wasm-opt as builds ship: exceptions (re-raise, ensure on
   return/break/next, raises in closures, `rescue A | B` and `else`, nested frames with union locals), struct
   returns, a closure called with a union argument directly and in a rescue body (the release build must stub at
   least one call and one invoke - else the optimizer no longer makes the mismatch these test), layout numbers
   typed before a generic module's struct exists (`dup`, `sizeof` of a struct, `alignof`, `offsetof` of a struct,
   a class and a tuple, abstract-struct and tuple fields, type arguments and a constant - which must stay a static
   literal in the IR), a layout number fixed inside a type argument too early that must stop the build with the
   check's error, the file-system fixes, the toolchain's library versions, a planted failure and error the runner
   must report, the event round trip (crymble.js's event and key tables against crymble-ui's
   enums, every field of every event kind), the web `backend_notices`, and 2000 ticks with collections between
   them (heap flat, finalizers run, data intact).
2. builds tutorial-22, tutorial-07, tutorial-24 and showcase_demo, unchanged - steps 2 to 4 run at `-O0` and then
   with `--release`, what is published.
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
5. `readme_check.sh` - the README's commands in a scratch app made of the README's own stanza and Quick Start
   (the README builds without `--release`: `-O0`).

Each check was shown failing with its piece broken. The stock compiler type-checks the web flavour
(`crystal build --no-codegen --cross-compile --target wasm32-unknown-wasi -Dwithout_mt -Dwithout_main`), so CI
can do that without the toolchain.

Node 18 or newer; playwright-core (pinned in `tools/wasm/package.json`, `npm ci`) with its Chromium
(`npx playwright-core install chromium-headless-shell`) or any Chrome binary as `CRYMBLE_CHROMIUM`.

## Apps built with it

- the showcase (`examples/showcase_demo.cr`), published with each release - see "Publishing the showcase";
- [Minesweeper](https://github.com/wolfgang371/minesweeper), live at https://wolfgang371.github.io/minesweeper/ - a
  small app in a repository of its own, with crymble-ui as a shard dependency. Start a web build of your own app
  from it: its `shard.yml` (a target, and the `repository:` the page links as its source), its README section
  and its Pages publishing are all a third-party app needs;
- [Embrace](https://github.com/holistic3fficientsolutions/embrace), live at https://h3o.de/demo - a large app
  (AGPL), framed by a page of its own site; its `web/build.sh` builds a page to publish only from a public release.

## Browsers

Tested: Chromium (headless, by the checks above); Firefox by hand (2026-10). Not yet tested: Safari, a GPU-backed
Chrome.
The showcase is live at https://wolfgang371.github.io/crymbleui/ (since v1.9.0) and the README links it, naming the
browsers it is tested in (`LIVE_DEMO_TESTED` in scripts/generate-readme.cr) - widen that as each manual pass is
recorded here.

## Publishing the showcase

`tools/wasm/pages.sh` builds the showcase and writes the site to `bin/pages/`. A release publishes it: after the
release push, `scripts/publish.sh` runs `.publish.after-push.sh`, which asks, builds the site from the release
commit (its page names the release tag) and force-pushes it as a single orphan commit to the public remote's
`gh-pages` branch - the page always shows the latest release. Once, by hand: GitHub > Settings > Pages > serve the
`gh-pages` branch. A machine that publishes needs the toolchain (`bin/crymble-web setup`); without it the hook
says so and leaves `gh-pages` as it was - run `.publish.after-push.sh <tag>` by hand after the setup.
