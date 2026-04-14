# Typed Coordinates Plan

## Problem

Three coordinate systems (content, viewport, buffer) are all represented as `Float64`/`Vec2`. Mixing them silently produces wrong results. 19 overlap/bounds bugs and 66 scroll/viewport bugs partly stem from coordinate confusion.

## Proposed Types

```crystal
struct ContentPos    # Absolute position in the grid (row/col → pixel)
  property x : Float64
  property y : Float64
end

struct ViewportPos   # Position relative to visible viewport (screen coords within layer)
  property x : Float64
  property y : Float64
end

struct BufferPos     # Position within viewport_cache buffer (buffer_origin-relative)
  property x : Float64
  property y : Float64
end
```

## Conversion Methods

```crystal
module CoordConvert
  def self.content_to_viewport(pos : ContentPos, scroll : Vec2) : ViewportPos
    ViewportPos.new(pos.x - scroll.x, pos.y - scroll.y)
  end

  def self.content_to_buffer(pos : ContentPos, buffer_origin : Vec2) : BufferPos
    BufferPos.new(pos.x - buffer_origin.x, pos.y - buffer_origin.y)
  end

  def self.viewport_to_content(pos : ViewportPos, scroll : Vec2) : ContentPos
    ContentPos.new(pos.x + scroll.x, pos.y + scroll.y)
  end
end
```

## Migration Strategy

1. Define types + conversions
2. Annotate VirtualMatrix public API with typed parameters
3. Internal code: migrate one method at a time, compiler catches mismatches
4. StickyMath: key beneficiary — sticky vs content coords are currently ad-hoc

## Status

DESIGN ONLY — no code changes yet.
