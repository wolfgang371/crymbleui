# SFML RenderTexture Pooling Investigation

**Status**: BLOCKED - All approaches failed, pooling disabled
**Date**: 2026-01-02

## Problem Statement

When RenderTexture pooling is enabled, visual artifacts appear:
- Tan/orange colored boxes instead of proper widget backgrounds
- Ghost text bleeding through from previous widgets
- Garbled/corrupted glyph rendering (characters like "RHLXX" instead of "Note A")

When pooling is DISABLED, everything renders correctly.

## Why Pooling Matters

SFML best practice recommends pooling RenderTextures rather than creating/destroying them frequently:
- GPU texture allocation is expensive
- Rapid widget size changes (e.g., CPUMonitor) can leak GPU memory waiting for GC
- Reference: https://en.sfml-dev.org/forums/index.php?topic=18428.0

## Failed Approaches

### 1. clear() + display() on acquire
```crystal
# In pooled constructor after getting texture from pool
@texture.clear(SF::Color::Transparent)
@texture.display
```
**Result**: Still showed artifacts

### 2. Double-clear (Black then Transparent)
```crystal
@texture.clear(SF::Color::Black)
@texture.clear(SF::Color::Transparent)
```
**Result**: Still showed artifacts

### 3. BlendNone rect draw on acquire
```crystal
# Draw opaque rect with BlendNone to force pixel overwrite
rect = SF::RectangleShape.new(...)
@texture.draw(rect, SF::RenderStates.new(SF::BlendNone))
```
**Result**: Still showed artifacts

### 4. Clear on release (give GPU time)
```crystal
# In release() before adding to pool
texture.clear(SF::Color::Transparent)
texture.display  # Flush GPU commands
```
**Rationale**: Give GPU time to finish clearing before next acquire
**Result**: Still showed artifacts

### 5. reset_gl_states() at frame start
```crystal
# In SFMLRenderer.render_frame()
window.reset_gl_states
```
**Rationale**: imgui-sfml uses this pattern
**Result**: Still showed artifacts

### 6. view = default_view for pooled textures
```crystal
# In pooled constructor
@texture.view = @texture.default_view
```
**Rationale**: SFML View state might persist across reuse
**Result**: Still showed artifacts

### 7. clear() in pooled constructor
```crystal
protected def initialize(@texture, @font, _pooled)
  @clip_stack = [] of SF::IntRect
  @texture.view = @texture.default_view
  @texture.clear(SF::Color::Transparent)  # Match new constructor
end
```
**Result**: Still showed artifacts

### 8. Create textures at bucket size
```crystal
# In acquire() when creating new texture
new(bucket_w, bucket_h, font)  # Instead of exact size
```
**Rationale**: Ensure all textures in same bucket have same dimensions
**Result**: Made it WORSE - text completely garbled on startup

## Research Findings

### SFML Forum
- "draw with null texture between uses" mentioned - suggests OpenGL state binding issues
- oprypin (CrSFML maintainer): "create texture once, clear it in a loop if needed"

### imgui-sfml
Uses explicit GL state management:
- `resetGLStates()`
- `pushGLStates()` / `popGLStates()`

CrymbleUI doesn't use pushGLStates/popGLStates.

## Hypotheses Not Yet Tested

1. **Font texture atlas corruption**: The glyph corruption suggests font atlas might be affected by RenderTexture reuse. SFML fonts use internal textures that could interact badly with pooled RenderTextures.

2. **OpenGL context state**: Multiple RenderTextures share OpenGL context. State from one might leak to another in ways clear() doesn't fix.

3. **Texture binding order**: The order of texture.active = true calls might matter. When multiple backends exist, active state could get confused.

4. **FBO attachment state**: RenderTexture uses Frame Buffer Objects. FBO attachment state might not reset with clear().

## Current State

Pooling infrastructure exists but is **disabled** via early return in `acquire()`.
See `src/rendering/crsfml_backend.cr`.

## Next Steps (if revisiting)

1. Add extensive debug logging to track exact sequence of operations
2. Compare GL state between new texture and pooled texture using OpenGL queries
3. Try pushGLStates/popGLStates around all RenderTexture operations
4. Investigate if font.getTexture() is being corrupted
5. Check if issue is specific to text or affects all primitives
