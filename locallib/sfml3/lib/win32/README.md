# Windows static SFML 3 libraries (patched)

These are static-CRT (`/MT`) Windows builds of SFML 3.0.0 + dependencies.

## ⚠️ The patched lib

`sfml-graphics.lib` in this directory is **NOT** stock SFML 3.0.0. It has an
out-of-tree patch applied to `src/SFML/Graphics/Texture.cpp` that fixes
stochastic font glyph garbling on Windows. Without the patch, rendered text
shows random wrong glyphs (e.g. `b` rendered as `Z`) on every program launch.

The patch source is stored alongside the lib:

  `sfml-graphics-windows-glsync.patch`

It applies cleanly on top of:

  - upstream: https://github.com/SFML/SFML.git
  - tag: `3.0.0`
  - commit: `7f1162dfea4969bc17417563ac55d93b72e84c1e`

For the full root-cause analysis and reproducer details, see:

  `crymble-ui/docs/WINDOWS_SFML_GL_SYNC_BUG.md`

## Rebuilding sfml-graphics.lib from source

```bat
git clone https://github.com/SFML/SFML.git
cd SFML
git checkout 3.0.0
git apply ..\path\to\sfml-graphics-windows-glsync.patch
mkdir build
cd build
cmake .. -DBUILD_SHARED_LIBS=OFF -DSFML_USE_STATIC_STD_LIBS=ON ^
         -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build . --config Release --target sfml-graphics
cmake --install . --config Release --prefix ..\..\sfml-install
```

Then copy `sfml-install\lib\sfml-graphics-s.lib` to this directory as
`sfml-graphics.lib`.

## What the patch does

Two changes, in `Texture.cpp` and `Font.cpp`:

1. **`Texture::resize`** (`Texture.cpp`): replaces `glTexImage2D(..., nullptr)`
   with a zero-filled buffer. The `nullptr` form leaves the GPU texture content
   undefined; on Windows GL drivers this leaks into rendered glyphs.
   `Texture::resize` does **not** call `glFinish()` — that caused a ~20 ms
   stall per texture creation (~240 ms per keystroke at ~12 layer textures per
   rebuild).

2. **`Font::loadGlyph`** (`Font.cpp`): adds `glFinish()` after the
   `page.texture.update(...)` call that uploads the rasterised glyph bitmap
   into the atlas. Without this, the upload is queued asynchronously and
   `SF::Text` may sample the atlas before the upload has applied, producing
   random wrong glyphs.

Both fixes are required: zero-fill alone produces ~50% correct renders;
`glFinish` alone reduces to ~30% correct; both together produce 100% correct
renders across 30+ test launches.

## Other libs in this directory

- `sfml-system.lib`, `sfml-window.lib`, `sfml-audio.lib`, `sfml-network.lib`,
  `sfml-main.lib`: stock SFML 3.0.0
- `freetype.lib`: stock, built as SFML extlib
