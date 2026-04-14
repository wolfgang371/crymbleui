require "../core/types"

module CrymbleUI
  # Abstract render backend interface
  # Provides SFML-like drawing operations that can be implemented by:
  # - CrSFMLBackend (wraps SF::RenderTexture)
  # - TestRenderBackend (headless pixel buffer)
  module RenderBackend
    # Get width of render target
    abstract def width : Int32

    # Get height of render target
    abstract def height : Int32

    # Clear entire buffer to color
    abstract def clear(color : Color)

    # Fill rectangle with color
    abstract def fill_rect(bounds : Rect, color : Color)

    # Draw rectangle outline with color and width
    abstract def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)

    # Draw line from (x1, y1) to (x2, y2) with width
    abstract def draw_line(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, color : Color, width : Float64 = 1.0)

    # Draw circle at center with radius (filled or outline)
    abstract def draw_circle(center_x : Float64, center_y : Float64, radius : Float64, color : Color, fill : Bool = true)

    # Fill triangle with 3 vertices
    abstract def fill_triangle(p1 : Vec2, p2 : Vec2, p3 : Vec2, color : Color)

    # Draw text at position (tracking only, actual rendering backend-specific)
    abstract def draw_text(text : String, position : Vec2, color : Color, size : Float64)

    # Draw an image from file path at the given bounds with tint/alpha
    # Default noop — only SFML backend renders images (test backend skips)
    def draw_image(path : String, bounds : Rect, color : Color)
    end

    # Finalize rendering (for SFML display(), no-op for test)
    abstract def display

    # Blit (copy) entire source backend to this backend at specified position
    # Used for per-widget texture compositing: widget backend → layer backend
    # Performs GPU→GPU copy for SFML (fast), pixel copy for test backend
    abstract def blit(source : RenderBackend, dest_x : Int32, dest_y : Int32)

    # Blit (copy) rectangular region from source backend to this backend
    # Used for background capture: layer region → background backend
    # src_x, src_y: position in source to copy from
    # width, height: size of region to copy
    # dest_x, dest_y: position in destination to copy to
    # Performs GPU→GPU copy for SFML (fast), pixel copy for test backend
    abstract def blit_region(source : RenderBackend, src_x : Int32, src_y : Int32, width : Int32, height : Int32, dest_x : Int32, dest_y : Int32)

    # Push clipping region onto stack (all drawing will be clipped to this rect)
    # Used to prevent widget content from overflowing its bounds
    abstract def push_clip(rect : Rect)

    # Pop clipping region from stack
    abstract def pop_clip

    # Temporarily suspend scissor clipping (disables GL scissor test)
    # Used when drawing to OTHER backends while a clip is active on THIS backend
    # OpenGL scissor is global state, so we must disable it to avoid affecting other textures
    def suspend_clip
      # Default: no-op (test backend doesn't use GL scissor)
    end

    # Resume scissor clipping after suspend_clip
    # Re-enables GL scissor test if there's an active clip on the stack
    def resume_clip
      # Default: no-op (test backend doesn't use GL scissor)
    end

    # Capture rectangular region of pixels as packed UInt32 (RGBA: R in high byte)
    # Used by cache validation framework to compare cached vs uncached renders
    # Returns row-major array of width*height packed pixel values
    abstract def capture_region_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Array(UInt32)

    # Explicitly release GPU resources (textures, framebuffers)
    # Called when backend is being replaced due to size change
    # Without explicit disposal, old backends are orphaned and rely on GC
    # which can cause GPU memory accumulation under rapid size changes
    def dispose
      # Default: no-op (subclasses implement actual resource cleanup)
    end
  end
end
