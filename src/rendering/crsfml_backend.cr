require "../csfml3/wrapper"
require "../core/types"
require "./render_backend"
require "./opengl_bindings"

module CrymbleUI
  # SFML render backend wrapper
  # Wraps SF::RenderTexture to implement RenderBackend interface
  # Allows LayerRenderer to work with SFML without knowing SFML specifics
  class CrSFMLBackend
    include RenderBackend

    @texture : SF::RenderTexture
    @font : SF::Font
    @clip_stack : Array(SF::IntRect) # Stack of scissor clip rectangles

    # Factory method - creates a new backend
    def self.acquire(width : Int32, height : Int32, font : SF::Font) : CrSFMLBackend
      new(width, height, font)
    end

    # Standard constructor - creates new RenderTexture
    def initialize(width : Int32, height : Int32, font : SF::Font)
      @texture = SF::RenderTexture.new(width.to_u32, height.to_u32)
      @font = font
      @clip_stack = [] of SF::IntRect

      # CRITICAL: Clear GPU texture immediately to prevent garbage from previous allocations
      # Without this, newly created backends inherit GPU memory from freed backends → contamination!
      # Note: For NEW textures, just clear() is sufficient. display() is only needed for REUSED textures.
      @texture.clear(SF::Color::Transparent)
    end

    # Get underlying SFML texture (for sprite creation)
    def texture : SF::Texture
      @texture.texture
    end

    def width : Int32
      @texture.size.x.to_i
    end

    def height : Int32
      @texture.size.y.to_i
    end

    def clear(color : Color)
      @texture.clear(to_sf_color(color))
    end

    def fill_rect(bounds : Rect, color : Color)
      rect = SF::RectangleShape.new(SF.vector2f(bounds.width, bounds.height))
      rect.position = SF.vector2f(bounds.x, bounds.y)
      rect.fill_color = to_sf_color(color)
      @texture.draw(rect)
    end

    def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)
      # Draw border as 4 filled rectangles instead of SFML outline_thickness
      # SFML's outline_thickness centers on edges, causing sub-pixel artifacts at fractional zoom levels
      sf_color = to_sf_color(color)
      x = bounds.x.to_f32
      y = bounds.y.to_f32
      w = bounds.width.to_f32
      h = bounds.height.to_f32
      t = width.to_f32 # thickness

      # Top edge
      top = SF::RectangleShape.new(SF.vector2f(w, t))
      top.position = SF.vector2f(x, y)
      top.fill_color = sf_color
      @texture.draw(top)

      # Bottom edge
      bottom = SF::RectangleShape.new(SF.vector2f(w, t))
      bottom.position = SF.vector2f(x, y + h - t)
      bottom.fill_color = sf_color
      @texture.draw(bottom)

      # Left edge
      left = SF::RectangleShape.new(SF.vector2f(t, h))
      left.position = SF.vector2f(x, y)
      left.fill_color = sf_color
      @texture.draw(left)

      # Right edge
      right = SF::RectangleShape.new(SF.vector2f(t, h))
      right.position = SF.vector2f(x + w - t, y)
      right.fill_color = sf_color
      @texture.draw(right)
    end

    def draw_line(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, color : Color, width : Float64 = 1.0)
      # Draw line as thin rotated rectangle (SFML doesn't have line primitive)
      dx = x2 - x1
      dy = y2 - y1
      length = Math.sqrt(dx * dx + dy * dy)
      angle = Math.atan2(dy, dx) * 180.0 / Math::PI

      # Use provided width instead of hardcoded 1.0
      shape = SF::RectangleShape.new(SF.vector2f(length.to_f32, width.to_f32))
      shape.position = SF.vector2f(x1.to_f32, (y1 - width / 2.0).to_f32)
      shape.rotation = angle.to_f32
      shape.fill_color = to_sf_color(color)
      @texture.draw(shape)
    end

    def draw_circle(center_x : Float64, center_y : Float64, radius : Float64, color : Color, fill : Bool = true)
      circle = SF::CircleShape.new(radius.to_f32)
      # SFML circles are positioned by top-left corner, so offset by radius
      circle.position = SF.vector2f((center_x - radius).to_f32, (center_y - radius).to_f32)
      if fill
        circle.fill_color = to_sf_color(color)
      else
        circle.fill_color = SF::Color::Transparent
        circle.outline_color = to_sf_color(color)
        circle.outline_thickness = 1.0
      end
      @texture.draw(circle)
    end

    def fill_triangle(p1 : Vec2, p2 : Vec2, p3 : Vec2, color : Color)
      # SFML ConvexShape for triangle (3 points)
      shape = SF::ConvexShape.new(3)
      shape.set_point(0, SF.vector2f(p1.x.to_f32, p1.y.to_f32))
      shape.set_point(1, SF.vector2f(p2.x.to_f32, p2.y.to_f32))
      shape.set_point(2, SF.vector2f(p3.x.to_f32, p3.y.to_f32))
      shape.fill_color = to_sf_color(color)
      @texture.draw(shape)
    end

    def draw_text(text : String, position : Vec2, color : Color, size : Float64)
      # Ensure this RenderTexture is the active OpenGL target before drawing
      # Without this, text may render to wrong texture when multiple RenderTextures exist
      @texture.active = true
      sf_text = SF::Text.new(text, @font, size.round.to_u32)
      # Round to integers to avoid GPU bilinear interpolation blur on glyph atlas
      # (fractional coords from zoom centering arithmetic cause washed-out text — commit 20a683b)
      sf_text.position = SF.vector2f(position.x.round.to_f32, position.y.round.to_f32)
      sf_text.fill_color = to_sf_color(color)
      @texture.draw(sf_text)
    end

    # Class-level texture cache shared across all backends
    @@image_cache = Hash(String, SF::Texture).new

    # Registry of compile-time-embedded image bytes, keyed by the same path
    # that draw_image will be called with. The texture is created LAZILY on
    # the first draw_image call (when an OpenGL context is guaranteed to
    # exist), so registration itself is GL-free and safe to do at app
    # construction time, well before the window is created.
    @@embedded_image_data = Hash(String, Slice(UInt8)).new

    # Register compile-time-embedded image bytes under a virtual path. The
    # bytes are kept in a class-level registry; the GPU texture is created
    # on first use by draw_image. Call this once at app construction time
    # for every image that should be served from the embedded data instead
    # of from disk (avoiding any CWD dependency).
    def self.register_embedded_image(path : String, data : Slice(UInt8)) : Nil
      @@embedded_image_data[path] = data
    end

    # Read-only accessor used by other rendering subsystems (e.g.
    # SfmlRenderer.load_cached_texture, which has its own per-renderer
    # texture cache but should still honour the shared embedded-bytes
    # registry).
    def self.embedded_image_bytes(path : String) : Slice(UInt8)?
      @@embedded_image_data[path]?
    end

    def draw_image(path : String, bounds : Rect, color : Color)
      @texture.active = true
      texture = @@image_cache[path]? || begin
        # Cache miss. Prefer registered embedded bytes over a disk read so
        # behaviour is independent of the current working directory and we
        # don't need any external files at runtime.
        if data = @@embedded_image_data[path]?
          t = SF::Texture.from_memory(data)
        else
          t = SF::Texture.from_file(path)
        end
        t.smooth = true
        @@image_cache[path] = t
        t
      rescue
        return
      end
      sprite = SF::Sprite.new(texture)
      sprite.position = SF.vector2f(bounds.x.to_f32, bounds.y.to_f32)
      tex_size = texture.size
      if tex_size.x > 0 && tex_size.y > 0
        sprite.scale = SF.vector2f(
          (bounds.width / tex_size.x).to_f32,
          (bounds.height / tex_size.y).to_f32
        )
      end
      sprite.color = to_sf_color(color)
      @texture.draw(sprite)
    end

    def display
      @texture.display
    end

    # Sample a pixel from the texture (for debugging)
    def debug_sample_pixel(x : Int32, y : Int32) : String
      img = @texture.texture.copy_to_image
      if x >= 0 && x < img.size.x.to_i && y >= 0 && y < img.size.y.to_i
        px = img.get_pixel(x, y)
        "RGBA(#{px.r},#{px.g},#{px.b},#{px.a})"
      else
        "OUT_OF_BOUNDS"
      end
    end

    # Blit entire source backend to this backend at specified position
    # Creates sprite from source texture and draws it (GPU→GPU copy, fast)
    # Uses BlendMode::None to REPLACE pixels (not blend) - critical for background restoration!
    #
    # WARNING: DO NOT ADD Y-FLIP HERE! Unlike blit_region(), full-texture blit does NOT need
    # Y-flip handling. SFML handles this automatically for full-texture sprites.
    # Adding Y-flip here breaks ALL rendering (everything appears upside-down).
    # See blit_region() for the case where Y-flip IS needed (partial texture sampling).
    def blit(source : RenderBackend, dest_x : Int32, dest_y : Int32)
      # Cast to CrSFMLBackend to access texture
      if source.is_a?(CrSFMLBackend)
        sprite = SF::Sprite.new(source.texture)
        sprite.position = SF.vector2f(dest_x.to_f32, dest_y.to_f32)
        # CRITICAL: Use BlendNone to REPLACE destination pixels instead of blending!
        # With default alpha blending, transparent source pixels don't overwrite destination
        # → old widget content remains visible when restoring transparent background → double rendering!
        @texture.draw(sprite, SF::RenderStates.new(SF::BlendNone))
      else
        # Graceful degradation: skip if incompatible backend type
        return
      end
    end

    # Blit rectangular region from source backend to this backend
    # Uses SFML texture rect to sample region (GPU→GPU copy, very fast)
    # IMPORTANT: RenderTexture.texture is Y-flipped, so texture_rect Y must be inverted
    def blit_region(source : RenderBackend, src_x : Int32, src_y : Int32, width : Int32, height : Int32, dest_x : Int32, dest_y : Int32)
      if source.is_a?(CrSFMLBackend)
        {% if flag?(:DEBUG_RENDER) %}
          puts "      [BLIT_REGION] backend#{source.object_id}[(#{src_x},#{src_y}) #{width}x#{height}] → backend#{self.object_id} at (#{dest_x}, #{dest_y})"
        {% end %}
        # Create sprite with texture rectangle to sample just the region
        sprite = SF::Sprite.new(source.texture)
        # RenderTexture.texture is Y-flipped (FBO), so invert Y coordinate for texture_rect
        # If source texture height is H and we want row Y, in flipped texture it's at H-Y-height
        source_height = source.texture.size.y.to_i
        flipped_src_y = source_height - src_y - height
        sprite.texture_rect = SF.int_rect(src_x, flipped_src_y, width, height)
        # Flip sprite vertically since we're sampling from flipped coords
        sprite.scale = SF.vector2f(1.0_f32, -1.0_f32)
        sprite.position = SF.vector2f(dest_x.to_f32, (dest_y + height).to_f32)
        # CRITICAL: Use BlendNone to REPLACE pixels (same reason as regular blit)
        @texture.draw(sprite, SF::RenderStates.new(SF::BlendNone))
      else
        # Graceful degradation: skip if incompatible backend type
        return
      end
    end

    # Get pixels from rectangular region (for background memorization)
    # GPU→CPU transfer - slow but only happens once per widget on first render
    def get_pixels(x : Int32, y : Int32, width : Int32, height : Int32) : Array(Color)
      # Copy texture to image (GPU→CPU)
      image = @texture.texture.copy_to_image
      pixels = [] of Color

      height.times do |dy|
        width.times do |dx|
          sf_color = image.get_pixel(x + dx, y + dy)
          pixels << Color.new(sf_color.r, sf_color.g, sf_color.b, sf_color.a)
        end
      end
      pixels
    end

    # Set pixels in rectangular region (for background restoration)
    # Creates Image from pixel array, then draws to RenderTexture via sprite
    # Can't use texture.update() on RenderTexture - causes upside-down rendering
    def set_pixels(x : Int32, y : Int32, width : Int32, height : Int32, pixels : Array(Color))
      return if pixels.empty?

      # Create SFML Image and populate with pixels
      image = SF::Image.new(width.to_u32, height.to_u32)
      pixels.each_with_index do |color, idx|
        px = idx % width
        py = idx // width
        image.set_pixel(px.to_u32, py.to_u32, to_sf_color(color))
      end

      # Create texture from image and draw to RenderTexture
      temp_texture = SF::Texture.from_image(image)
      sprite = SF::Sprite.new(temp_texture)
      sprite.position = SF.vector2f(x.to_f32, y.to_f32)
      @texture.draw(sprite)
    end

    # Push clipping region onto stack
    # Use ceil for width/height to avoid off-by-one when bounds are fractional
    # (matches compositor which uses .ceil.to_i for texture_rect)
    def push_clip(rect : Rect)
      @clip_stack << SF.int_rect(rect.x.to_i, rect.y.to_i, rect.width.ceil.to_i, rect.height.ceil.to_i)
      apply_clip
    end

    # Pop clipping region from stack
    def pop_clip
      @clip_stack.pop
      apply_clip
    end

    # Temporarily suspend scissor clipping (disables GL scissor test)
    # Used when drawing to OTHER backends while a clip is active on THIS backend
    # OpenGL scissor is global state, so we must disable it to avoid affecting other textures
    def suspend_clip
      display = ENV["DISPLAY"]?
      return if display.nil? || display.empty?

      begin
        LibGL.disable(LibGL::GL_SCISSOR_TEST)
      rescue
        # Silently ignore OpenGL errors
      end
    end

    # Resume scissor clipping after suspend_clip
    # Re-enables GL scissor test if there's an active clip on the stack
    def resume_clip
      display = ENV["DISPLAY"]?
      return if display.nil? || display.empty?

      begin
        if @clip_stack.last?
          LibGL.enable(LibGL::GL_SCISSOR_TEST)
        end
      rescue
        # Silently ignore OpenGL errors
      end
    end

    # Apply current clipping region using OpenGL scissor test
    private def apply_clip
      # Skip OpenGL calls if no display available (headless tests)
      # This allows tests to compile/link but skip actual GL calls
      display = ENV["DISPLAY"]?
      return if display.nil? || display.empty?

      begin
        if clip = @clip_stack.last?
          # Enable scissor test
          LibGL.enable(LibGL::GL_SCISSOR_TEST)

          # Convert clip rect to OpenGL coordinates
          # OpenGL Y axis is bottom-to-top, our system is top-to-bottom
          # For RenderTexture (FBO), Y is already flipped, so we need to flip again
          texture_height = @texture.size.y
          gl_x = clip.left
          gl_y = (texture_height - (clip.top + clip.height)).to_i32 # Flip Y axis
          gl_width = clip.width
          gl_height = clip.height

          LibGL.scissor(gl_x, gl_y, gl_width, gl_height)
        else
          # No clip region - disable scissor test
          LibGL.disable(LibGL::GL_SCISSOR_TEST)
        end
      rescue
        # Silently ignore OpenGL errors (e.g., no active context)
      end
    end

    # Capture rectangular region of pixels as packed UInt32 (RGBA: R in high byte)
    # GPU→CPU transfer via copy_to_image — use sparingly (cache validation only)
    def capture_region_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Array(UInt32)
      image = @texture.texture.copy_to_image
      result = Array(UInt32).new(w * h, 0_u32)
      h.times do |dy|
        w.times do |dx|
          px = x + dx
          py = y + dy
          if px >= 0 && px < image.size.x.to_i && py >= 0 && py < image.size.y.to_i
            sf_color = image.get_pixel(px, py)
            result[dy * w + dx] = (sf_color.r.to_u32 << 24) | (sf_color.g.to_u32 << 16) | (sf_color.b.to_u32 << 8) | sf_color.a.to_u32
          end
        end
      end
      result
    end

    # No-op: let GC handle RenderTexture cleanup.
    # Texture pooling was attempted but causes OpenGL FBO state corruption
    # (garbled text, ghost backgrounds) with both SFML 2.5 and 3.0.
    def dispose
    end

    # Convert CrymbleUI Color to SF::Color
    private def to_sf_color(color : Color) : SF::Color
      SF::Color.new(color.r, color.g, color.b, color.a)
    end
  end
end
