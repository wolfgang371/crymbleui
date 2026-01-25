require "../csfml3/wrapper"
require "../core/types"
require "./render_backend"
require "./opengl_bindings"

module CrymbleUI
  # SFML render backend wrapper
  # Wraps SF::RenderTexture to implement RenderBackend interface
  # Allows LayerRenderer to work with SFML without knowing SFML specifics
  #
  # ## Texture Pooling
  # RenderTextures are expensive GPU resources. SFML best practice is to pool and reuse them
  # rather than creating/destroying frequently. This class implements texture pooling:
  # - Textures are bucketed by size (64px increments) for reuse
  # - dispose() returns textures to pool instead of destroying
  # - acquire() gets from pool or creates new
  # See: https://en.sfml-dev.org/forums/index.php?topic=18428.0
  class CrSFMLBackend
    include RenderBackend

    # Texture pool for reusing GPU resources
    # Key: (bucketed_width, bucketed_height), Value: available textures with their fonts
    @@texture_pool = Hash(Tuple(Int32, Int32), Array(Tuple(SF::RenderTexture, SF::Font))).new
    @@pool_memory_usage : Int64 = 0_i64

    # Pool limits to prevent unbounded growth
    MAX_POOL_MEMORY  = 100 * 1024 * 1024 # 100MB total GPU memory in pool
    MAX_PER_BUCKET   =                50 # Max textures per size bucket
    BUCKET_INCREMENT =                64 # Round sizes up to this increment

    @texture : SF::RenderTexture
    @font : SF::Font
    @clip_stack : Array(SF::IntRect) # Stack of scissor clip rectangles

    # Round dimension up to next bucket increment (64px)
    # This allows textures of similar sizes to be reused
    private def self.bucket_size(dimension : Int32) : Int32
      ((dimension + BUCKET_INCREMENT - 1) // BUCKET_INCREMENT) * BUCKET_INCREMENT
    end

    # Acquire a backend from the pool or create a new one
    # This is the primary way to get a CrSFMLBackend - prefer over new()
    def self.acquire(width : Int32, height : Int32, font : SF::Font) : CrSFMLBackend
      # POOLING DISABLED: Causes rendering artifacts (garbled text, ghost backgrounds)
      # All attempted fixes failed. See docs/TEXTURE_POOLING_INVESTIGATION.md for details.
      # When pooling works, remove this early return to re-enable.
      return new(width, height, font)

      # --- POOLING CODE (disabled) ---
      bucket_w = bucket_size(width)
      bucket_h = bucket_size(height)
      key = {bucket_w, bucket_h}

      if (textures = @@texture_pool[key]?) && (entry = textures.pop?)
        texture, pooled_font = entry
        texture_memory = bucket_w.to_i64 * bucket_h.to_i64 * 4
        @@pool_memory_usage -= texture_memory

        # Texture was already cleared on release - ready to use immediately
        # (Clearing on release gives GPU time to finish before next acquire)

        {% if flag?(:DEBUG_POOL) %}
          puts "[POOL] Reused #{bucket_w}x#{bucket_h} texture (pool: #{@@pool_memory_usage / 1024 / 1024}MB)"
        {% end %}

        # Create backend wrapping the pooled texture
        new(texture, font, true)
      else
        {% if flag?(:DEBUG_POOL) %}
          puts "[POOL] Created new #{width}x#{height} texture (no #{bucket_w}x#{bucket_h} in pool)"
        {% end %}

        # Create new texture at exact requested size
        new(width, height, font)
      end
    end

    # Return a backend's texture to the pool for reuse
    # Called by dispose() - do not call directly
    def self.release(backend : CrSFMLBackend)
      texture = backend.@texture
      font = backend.@font
      bucket_w = bucket_size(texture.size.x.to_i)
      bucket_h = bucket_size(texture.size.y.to_i)
      texture_memory = bucket_w.to_i64 * bucket_h.to_i64 * 4

      # Check if pool is full (memory limit)
      if @@pool_memory_usage + texture_memory > MAX_POOL_MEMORY
        {% if flag?(:DEBUG_POOL) %}
          puts "[POOL] Memory limit reached, not pooling #{bucket_w}x#{bucket_h}"
        {% end %}
        return # Let GC handle it
      end

      key = {bucket_w, bucket_h}
      textures = @@texture_pool[key]? || (@@texture_pool[key] = [] of Tuple(SF::RenderTexture, SF::Font))

      # Check if bucket is full
      if textures.size >= MAX_PER_BUCKET
        {% if flag?(:DEBUG_POOL) %}
          puts "[POOL] Bucket #{key} full (#{MAX_PER_BUCKET}), not pooling"
        {% end %}
        return # Let GC handle it
      end

      # Clear texture BEFORE adding to pool
      # This gives the GPU time to finish clearing before next acquire()
      # (Key insight: display() only initiates GPU commands, doesn't wait)
      texture.clear(SF::Color::Transparent)
      texture.display

      # Add to pool (now clean)
      textures << {texture, font}
      @@pool_memory_usage += texture_memory

      {% if flag?(:DEBUG_POOL) %}
        puts "[POOL] Released #{bucket_w}x#{bucket_h} to pool (pool: #{@@pool_memory_usage / 1024 / 1024}MB, bucket: #{textures.size})"
      {% end %}
    end

    # Get pool statistics for debugging/monitoring
    def self.pool_stats : NamedTuple(buckets: Int32, textures: Int32, memory_mb: Float64)
      total_textures = 0
      @@texture_pool.each_value { |arr| total_textures += arr.size }
      {
        buckets:   @@texture_pool.size,
        textures:  total_textures,
        memory_mb: @@pool_memory_usage / (1024.0 * 1024.0),
      }
    end

    # Clear all pooled textures (useful for tests or memory pressure)
    def self.clear_pool
      @@texture_pool.clear
      @@pool_memory_usage = 0_i64
    end

    # Internal constructor for wrapping a pooled texture
    # Uses a struct tag to distinguish from width/height constructor
    protected def initialize(@texture : SF::RenderTexture, @font : SF::Font, _pooled : Bool)
      @clip_stack = [] of SF::IntRect
      # CRITICAL: Reset view to default - pooled textures retain view from previous widget
      # Without this, rendering uses stale scale/offset/viewport from previous use
      @texture.view = @texture.default_view
      # Match the new constructor - clear the texture to ensure identical state
      @texture.clear(SF::Color::Transparent)
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
      sf_text.position = SF.vector2f(position.x, position.y)
      sf_text.fill_color = to_sf_color(color)
      @texture.draw(sf_text)
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

    # Return this backend's texture to the pool for reuse
    # Called when backend is being replaced due to widget size change
    #
    # NOTE: We do NOT call @texture.finalize here!
    # Calling finalize while other code may still reference the backend causes crashes.
    # Instead, we return the texture to the pool for reuse by future widgets.
    # If the pool is full, the texture is simply abandoned for GC to clean up.
    def dispose
      CrSFMLBackend.release(self)
    end

    # Convert CrymbleUI Color to SF::Color
    private def to_sf_color(color : Color) : SF::Color
      SF::Color.new(color.r, color.g, color.b, color.a)
    end
  end
end
