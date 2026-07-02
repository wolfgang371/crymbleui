# Windows SFML GL synchronization bug — IMPORTANT, READ THIS

> **TL;DR:** On Windows, SFML 3.0.0 + the system OpenGL driver does **not** make
> glyph atlas uploads visible to subsequent reads in time. The result is
> stochastic glyph garbling: random characters in rendered text show the
> *wrong glyph* (e.g. `b` rendered as `Z`, `[` as `]`). The fix is a two-part patch: `Texture::resize` in `Texture.cpp` is changed
> to zero-fill the new texture instead of passing `nullptr`; and
> `Font::loadGlyph` in `Font.cpp` calls `glFinish()` after the glyph atlas
> upload. Only `Font::loadGlyph` calls `glFinish()` — adding it to
> `Texture::resize` too caused ~240 ms of stall per keystroke (~20 ms ×
> ~12 layer textures per full rebuild). Without this patch, **rendering is
> non-deterministic across process launches on Windows**.

## Symptoms

- Random characters in text labels render with the wrong glyph (a totally
  different character from the same font, not just the wrong color or
  position)
- Different characters get garbled on every program launch
- Within a single process, the corruption is stable; across launches it
  varies wildly
- Only reproduces on **Windows** (Linux Mesa zero-inits VRAM, masking the
  bug)
- Triggers reliably with strings of ~10+ characters; short strings (≤8) and
  pure shape rendering are unaffected
- The font file/bytes are unchanged (verified by hashing)
- The glyph metadata (`tex_rect`, `bounds`) is identical across runs
- The differing data is in the **atlas texture pixels** themselves

## Root cause

`sf::Texture::resize` calls `glTexImage2D(..., nullptr)` to allocate the new
texture. On Windows GL drivers the new texture's content is undefined.

`sf::Texture::update` then uses `glTexSubImage2D` to upload glyph bitmaps.
**The upload is asynchronous** in the GL command stream — the GPU may not
have finished writing the bytes before the next operation reads them. On
Windows IHV drivers (NVIDIA / AMD / Intel) this often manifests as the next
read seeing stale or partially-written data, which means a glyph
rasterized at position (X, Y) may end up with another glyph's bitmap.

The Linux Mesa driver happens to zero-initialize VRAM and synchronize
operations more aggressively, so the bug is invisible there.

## Fix

Two patches, both narrowly scoped so the slow `glFinish()` only fires
when actually needed (a globally-applied `glFinish()` in `Texture::update`
caused massive input lag and dropped events because every glyph upload
stalled the CPU until the GPU was idle).

### 1. `SFML/src/SFML/Graphics/Texture.cpp` — `Texture::resize`

Replace `glTexImage2D(..., nullptr)` with a `glTexImage2D` call passing a
zero-filled `std::vector<std::uint8_t>` of the right size. The Windows GL
drivers leave the new texture content undefined when given `nullptr`;
pre-zeroing means a later sampler read sees zeros instead of garbage.
`Texture::resize` does **not** call `glFinish()` — measurement showed a
~20 ms stall per texture creation, and crymble-ui creates ~12 layer textures
per full rebuild, making the cumulative cost ~240 ms per keystroke. The
`Font::loadGlyph` `glFinish()` (Fix 2) is sufficient for correctness. The
original analysis assumed `Texture::resize` was rare enough that a
`glFinish()` there would be negligible; that assumption did not survive
measurement.

### 2. `SFML/src/SFML/Graphics/Font.cpp` — `Font::loadGlyph`

Add `glCheck(glFinish());` immediately after the
`page.texture.update(...)` call that uploads the rasterised glyph bitmap
into the atlas. This is the only Texture::update site whose result is
sampled in the same frame (SF::Text builds its vertex buffer using the
glyph's atlas coordinates immediately after the upload). All other
Texture::update sites (image widgets, render textures, etc.) write
once and sample on a later frame, so a sync there isn't needed and
would just cost performance.

The full patch is stored alongside the patched lib at
`crymble-ui/locallib/sfml3/lib/win32/sfml-graphics-windows-glsync.patch`
and is also annotated inline in the (out-of-tree) SFML source tree
under the `PATCH` comments in `Texture.cpp` and `Font.cpp`. See
`crymble-ui/locallib/sfml3/lib/win32/README.md` for instructions on
rebuilding `sfml-graphics.lib` with the patch applied.

## Reproduction

A standalone reproducer was used during the investigation:

- A Crystal `font_autotest` target in embrace's `shard.yml` (loaded
  `Cousine-Regular.ttf` from embedded bytes, rendered the same SAMPLE
  string to an offscreen `RenderTexture`, copied pixels, printed a
  SHA-1 hash). The target and source file are no longer carried
  in-tree — the bug is fixed and we don't want a permanent test
  fixture for it. Recreate from git history if you need to re-prove
  it: `src/gui/font_autotest.cr`.
- A pure C++ reproducer at `C:\myenv\sfml_test\` (loads the font from
  disk, renders the same SAMPLE, hashes the pixels). This confirmed
  the bug was in SFML itself, not in Crystal/CSFML bindings.

Test protocol used:

- **Without** the SFML patches: ~50–85% of runs produce a random hash
- **With** the SFML patches: 30/30 runs produce the canonical hash
  `e1dcf8036bea22777c15506b4b5b37eb175051d1`

## What this means for crymble-ui code

- **DO NOT** assume a `glTexSubImage2D` or texture upload is visible to the
  next operation without a sync. If you write GPU upload code, follow it
  with `glFinish()` (or a fence) on Windows.
- **DO NOT** create multiple `SF::Font` instances expecting they will
  produce identical atlases — each one re-runs the broken upload path. The
  upstream fix is in SFML; until that lands you depend on the patched
  `sfml-graphics.lib`.
- The single shared font in `SfmlRenderer` (load once at construction,
  never reload on zoom) was already the right call for a different reason
  (avoiding the reload path's churn) — and it also reduces exposure to
  this bug since fewer atlases are created.

## History

- 2026-04-08: bug discovered while bringing up Windows builds for embrace.
  Diagnosed as a stochastic SFML/Windows GL driver issue via the
  `font_autotest` autotest. The cross-process variation in pixel hashes
  proved the non-determinism, the C++ test ruled out Crystal/CSFML, and a
  CPU busy-loop in `Font::getGlyph` (which made the bug disappear) led
  to the timing/sync hypothesis. The fix is `glFinish()` after every
  texture allocation/upload in SFML's `Texture.cpp`.
