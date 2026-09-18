require "../csfml3/wrapper"
require "../core/types"
require "./render_backend"
require "./pixel_snap"
require "./clip_math"
require "./fbo_math"

module CrymbleUI
  # SFML render backend wrapper
  # Wraps SF::RenderTexture to implement RenderBackend interface
  # Allows LayerRenderer to work with SFML without knowing SFML specifics
  class CrSFMLBackend
    include RenderBackend

    @texture : SF::RenderTexture
    @width : Int32
    @height : Int32
    @font : SF::Font
    # Clip rects as pushed, in FLOAT pixels. Kept unrounded so the whole stack is
    # intersected in float and converted to device pixels ONCE, at the end — rounding
    # each rect first and intersecting afterwards gives a different answer at fractional
    # boundaries. That puts the conversion ORDER in step with TestRenderBackend, which
    # also intersects in float. The rounding RULE still differs (the instrument truncates
    # both edges; this ceils the extent) — tracked in the backlog, still open.
    @clip_stack : Array(Rect)
    # ONE long-lived view per backend, the clip's carrier. Copied from the texture's
    # DEFAULT view (sfView_create would yield centre (500,500)/size (1000,1000) and
    # silently relocate every draw). Copied ONCE: RenderTexture#view hands back an
    # interior pointer into the render texture, and a per-clip copy would both allocate
    # on the render hot path and hand View#finalize a handle destroyed manually.
    @clip_view : SF::View

    # Factory method - creates a new backend
    def self.acquire(width : Int32, height : Int32, font : SF::Font) : CrSFMLBackend
      new(width, height, font)
    end

    # Standard constructor - creates new RenderTexture
    def initialize(width : Int32, height : Int32, font : SF::Font)
      @texture = SF::RenderTexture.new(width.to_u32, height.to_u32)
      @font = font
      @clip_stack = [] of Rect
      @clip_view = @texture.default_view.dup
      # Cached because they must remain answerable AFTER dispose (blit-plan bookkeeping and the
      # size-compare in render_single_widget both read them). Querying the destroyed texture would
      # be sfRenderTexture_getSize(NULL) — a hard SEGFAULT that no raise-on-use contract can catch.
      # Equivalent by construction: sfRenderTexture_create takes exactly this size.
      @width = width
      @height = height

      # CRITICAL: Clear GPU texture immediately to prevent garbage from previous allocations
      # Without this, newly created backends inherit GPU memory from freed backends → contamination!
      # Note: For NEW textures, just clear() is sufficient. display() is only needed for REUSED textures.
      @texture.clear(SF::Color::Transparent)
    end

    # Get underlying SFML texture (for sprite creation).
    # Guarded: after dispose the underlying pointer is freed memory, and handing it to a sprite or
    # copy_to_image would be a silent use-after-free rather than a clean failure.
    def texture : SF::Texture
      assert_live("texture")
      @texture.texture
    end

    def width : Int32
      @width
    end

    def height : Int32
      @height
    end

    def clear(color : Color)
      assert_live("clear")
      @texture.clear(to_sf_color(color))
    end

    def fill_rect(bounds : Rect, color : Color)
      assert_live("fill_rect")
      rect = SF::RectangleShape.new(SF.vector2f(bounds.width, bounds.height))
      rect.position = SF.vector2f(bounds.x, bounds.y)
      rect.fill_color = to_sf_color(color)
      @texture.draw(rect)
    end

    def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)
      assert_live("draw_rect")
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
      assert_live("draw_line")
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
      assert_live("draw_circle")
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
      assert_live("fill_triangle")
      # SFML ConvexShape for triangle (3 points)
      shape = SF::ConvexShape.new(3)
      shape.set_point(0, SF.vector2f(p1.x.to_f32, p1.y.to_f32))
      shape.set_point(1, SF.vector2f(p2.x.to_f32, p2.y.to_f32))
      shape.set_point(2, SF.vector2f(p3.x.to_f32, p3.y.to_f32))
      shape.fill_color = to_sf_color(color)
      @texture.draw(shape)
    end

    def draw_text(text : String, position : Vec2, color : Color, size : Float64)
      assert_live("draw_text")
      # Ensure this RenderTexture is the active OpenGL target before drawing
      # Without this, text may render to wrong texture when multiple RenderTextures exist
      @texture.active = true
      sf_text = SF::Text.new(text, @font, size.round.to_u32)
      # Snap to whole pixels to avoid GPU bilinear blur on the glyph atlas (20a683b).
      # PixelSnap (not Float#round): its translation invariance keeps the widget-local
      # (texture) and layer-local (direct) render paths on the same device pixel.
      sf_text.position = SF.vector2f(PixelSnap.snap(position.x).to_f32, PixelSnap.snap(position.y).to_f32)
      sf_text.fill_color = to_sf_color(color)
      @texture.draw(sf_text)
    end

    # Class-level texture cache shared across all backends, keyed by ImageSource#key
    @@image_cache = Hash(String, SF::Texture).new

    def draw_image(source : ImageSource, bounds : Rect, color : Color)
      assert_live("draw_image")
      @texture.active = true
      texture = @@image_cache[source.key]? || begin
        # Cache miss. Embedded bytes (compile-time, CWD-independent) take priority;
        # otherwise read the key as a disk path. Texture creation is lazy here, where
        # an OpenGL context is guaranteed to exist.
        t = if data = source.bytes
              SF::Texture.from_memory(data)
            else
              SF::Texture.from_file(source.key)
            end
        t.smooth = true
        @@image_cache[source.key] = t
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
      assert_live("display")
      @texture.display
      # Release this RenderTexture's GL context back to SFML's shared context after each layer.
      # draw_text/draw_image do `@texture.active = true` (glXMakeCurrent) but never deactivate, so a
      # TRANSIENT RT (e.g. a ComboBox popup) can be SFML's tracked-active target when the Boehm GC
      # later runs its ~RenderTexture finalizer — whose own glXMakeCurrent then fires from a dangling
      # transient-context baseline → X_GLXMakeCurrent BadAccess (crash on first dropdown open→close).
      # Deactivating here keeps that baseline clean; each RT#draw re-activates its own context anyway.
      @texture.active = false
    end

    # Sample a pixel from the texture (for debugging)
    def debug_sample_pixel(x : Int32, y : Int32) : String
      assert_live("debug_sample_pixel")
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
      assert_live("blit")
      assert_live_other(source, "blit", "source")
      # Cast to CrSFMLBackend to access texture
      if source.is_a?(CrSFMLBackend)
        sprite = SF::Sprite.new(source.texture)
        sprite.position = SF.vector2f(dest_x.to_f32, dest_y.to_f32)
        # CRITICAL: Use BlendNone to REPLACE destination pixels instead of blending!
        # With default alpha blending, transparent source pixels don't overwrite destination
        # → old widget content remains visible when restoring transparent background → double rendering!
        @texture.draw(sprite, SF::RenderStates.new(SF::BlendNone))
      else
        # No-Fallbacks: a mismatched backend type is a broken invariant, not a
        # degradable condition. One renderer pass is backend-homogeneous (single
        # per-renderer backend factory), so this branch is unreachable in a correct
        # build — make it loud, mirroring TestRenderBackend's raise.
        raise "blit between mismatched backend types (#{source.class}) — one renderer pass is backend-homogeneous"
      end
    end

    # Blit rectangular region from source backend to this backend
    # Uses SFML texture rect to sample region (GPU→GPU copy, very fast)
    # IMPORTANT: RenderTexture.texture is Y-flipped, so texture_rect Y must be inverted
    def blit_region(source : RenderBackend, src_x : Int32, src_y : Int32, width : Int32, height : Int32, dest_x : Int32, dest_y : Int32)
      assert_live("blit_region")
      assert_live_other(source, "blit_region", "source")
      if source.is_a?(CrSFMLBackend)
        {% if flag?(:DEBUG_RENDER) %}
          puts "      [BLIT_REGION] backend#{source.object_id}[(#{src_x},#{src_y}) #{width}x#{height}] → backend#{self.object_id} at (#{dest_x}, #{dest_y})"
        {% end %}
        # Create sprite with texture rectangle to sample just the region
        sprite = SF::Sprite.new(source.texture)
        # RenderTexture.texture is Y-flipped (FBO): FboMath computes the texture_rect
        # Y invert, the scale sign that re-flips the sampled band back to top-down,
        # and the draw Y. See the convention table in fbo_math.cr.
        flip = FboMath.blit_region_flip(source.texture.size.y.to_i, src_y, height, dest_y)
        sprite.texture_rect = SF.int_rect(src_x, flip.texture_rect_y, width, height)
        sprite.scale = SF.vector2f(1.0_f32, flip.scale_y)
        sprite.position = SF.vector2f(dest_x.to_f32, flip.draw_y.to_f32)
        # CRITICAL: Use BlendNone to REPLACE pixels (same reason as regular blit)
        @texture.draw(sprite, SF::RenderStates.new(SF::BlendNone))
      else
        # No-Fallbacks: a mismatched backend type is a broken invariant, not a
        # degradable condition (see #blit). Make it loud.
        raise "blit between mismatched backend types (#{source.class}) — one renderer pass is backend-homogeneous"
      end
    end

    # Get pixels from rectangular region (for background memorization)
    # GPU→CPU transfer - slow but only happens once per widget on first render
    def get_pixels(x : Int32, y : Int32, width : Int32, height : Int32) : Array(Color)
      assert_live("get_pixels")
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

    {% if flag?(:probe) %}
      # DIAGNOSTIC ONLY (-Dprobe). Read a SCATTERED set of points with ONE GPU->CPU copy.
      # #get_pixels above takes a rectangle, and its per-pixel FFI over a whole layer is what turned
      # an instrumented build into a black window (embrace src/gui/probe.cr says the arithmetic).
      # An oracle that compares a layer against its own widgets needs a few thousand scattered
      # points, not a rectangle, so it would otherwise pay one copy_to_image per point.
      # Points outside the texture come back fully transparent rather than raising: the caller is an
      # instrument, and a clamped sample is a better failure than a crashed diagnostic build.
      def get_pixels_at(points : Array(Tuple(Int32, Int32))) : Array(Color)
        assert_live("get_pixels_at")
        image = @texture.texture.copy_to_image
        w = width
        h = height
        points.map do |(px, py)|
          if px < 0 || py < 0 || px >= w || py >= h
            Color.new(0_u8, 0_u8, 0_u8, 0_u8)
          else
            c = image.get_pixel(px, py)
            Color.new(c.r, c.g, c.b, c.a)
          end
        end
      end
    {% end %}

    # Set pixels in rectangular region (for background restoration)
    # Creates Image from pixel array, then draws to RenderTexture via sprite
    # Can't use texture.update() on RenderTexture - causes upside-down rendering
    def set_pixels(x : Int32, y : Int32, width : Int32, height : Int32, pixels : Array(Color))
      assert_live("set_pixels")
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

    # Push clipping region onto stack. Stored unrounded — see @clip_stack.
    def push_clip(rect : Rect)
      assert_live("push_clip")
      @clip_stack << rect
      apply_clip
    end

    # Pop clipping region from stack
    def pop_clip
      assert_live("pop_clip")
      @clip_stack.pop
      apply_clip
    end

    # Deliberately NOT assert_live: this is a pure read of the stack, and the renderer
    # calls it while unwinding, where raising would replace the exception being unwound.
    def clip_depth : Int32
      @clip_stack.size
    end

    # Temporarily lift this backend's clip, for the stretch where the renderer draws to
    # OTHER backends mid-clip (background capture/restore).
    #
    # NOT because "the scissor is global" — it is not. Measured: with a clip live on one
    # backend, a draw on another comes back completely unclipped, because each render
    # texture carries its own view. So this pair no longer protects the OTHER backends'
    # draws; they were never at risk once the clip became per-target.
    #
    # It is retained as a contract guard for THIS backend: SFML applies the view's scissor
    # to `clear` as well as to draws, so a clear issued on this backend while its own clip
    # is live would be confined to it. Audited: no current call site does that, so the pair
    # is a no-op today. Deleting it belongs to the task that resolves the remaining
    # raw-GL clip path, not to this change.
    def suspend_clip
      assert_live("suspend_clip")
      install_scissor(FULL_TARGET_SCISSOR)
    end

    # Restore the clip suspended above. This IS apply_clip — re-deriving "the current
    # clip" anywhere else is how the stack-top/intersection split got in last time.
    def resume_clip
      assert_live("resume_clip")
      apply_clip
    end

    # SFML documents the full-target scissor as equivalent to disabling the test.
    FULL_TARGET_SCISSOR = SF.float_rect(0.0, 0.0, 1.0, 1.0)

    # Hand the clip to SFML as the view's scissor rather than issuing glScissor ourselves.
    #
    # WHY, and it is the whole bug: SFML applies its own GL state inside RenderTarget#draw
    # and RenderTarget#clear, and that reset disables GL_SCISSOR_TEST while leaving the
    # box. Any scissor WE enable is therefore live only until the next render-target
    # re-activation — so the first draw after one escaped its clip, which in a grid is the
    # first cell of the layer, whose text then ran across its neighbours. Expressed as the
    # view's scissor, SFML re-applies it itself on every re-activation instead.
    private def apply_clip
      # The stack collapse AND the float->device rounding both live in ClipMath, shared
      # with TestRenderBackend. They used to be derived separately and drifted: the
      # instrument clipped one column narrower at a fractional edge, so a real right-edge
      # defect could pass headless. One function means that is unrepresentable, not merely
      # spec-detected.
      if box = ClipMath.device_box(@clip_stack)
        x0, y0, x1, y1 = box
        install_scissor(SF.float_rect(
          x0.to_f32 / @width, y0.to_f32 / @height,
          (x1 - x0).to_f32 / @width, (y1 - y0).to_f32 / @height))
      else
        install_scissor(FULL_TARGET_SCISSOR)
      end
    end

    # The ONLY place this backend's view is touched. The view IS the clip's carrier, so
    # setting it anywhere else would silently replace the active clip; a tripwire pins
    # that (spec/rendering/instrument_tripwires_spec.cr, guard (f)).
    private def install_scissor(scissor : SF::FloatRect)
      @clip_view.scissor = scissor
      @texture.view = @clip_view
    end

    # Capture rectangular region of pixels as packed UInt32 (RGBA: R in high byte)
    # GPU→CPU transfer via copy_to_image — use sparingly (cache validation only)
    def capture_region_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Array(UInt32)
      assert_live("capture_region_pixels")
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

    # Release the native RenderTexture. NOT pooling — nothing here is ever reused; the earlier
    # pooling attempt corrupted FBO state (garbled text, ghost backgrounds) because it REUSED
    # textures, which is a different thing from freeing them. Freeing is what was missing: the GC
    # cannot feel driver memory, so an empty dispose meant no texture allocated since startup was
    # ever released (measured: 370 textures per create/drop cycle, RSS never returning).
    #
    # DEFERRED by design. Most dispose sites fire mid-render — while ANOTHER layer's RenderTexture
    # is the active target — and destroying an FBO there disturbs the GL state SFML tracks, which
    # is the corruption signature the pooling attempt produced. So dispose only ENQUEUES; the
    # renderer drains the queue once per frame at a point where nothing is mid-render.
    protected def release_payload : Nil
      @@reaper << @texture
    end

    # Textures handed over by dispose, destroyed together at the frame boundary.
    @@reaper = [] of SF::RenderTexture

    def self.pending_reaper : Int32
      @@reaper.size
    end

    # Destroy everything released during the frame. MUST be called with no RenderTexture active —
    # SFMLRenderer calls it after window.display, i.e. outside any layer's render.
    def self.drain_reaper : Int32
      n = @@reaper.size
      @@reaper.each(&.destroy!)
      @@reaper.clear
      n
    end

    # Convert CrymbleUI Color to SF::Color
    private def to_sf_color(color : Color) : SF::Color
      SF::Color.new(color.r, color.g, color.b, color.a)
    end
  end
end
