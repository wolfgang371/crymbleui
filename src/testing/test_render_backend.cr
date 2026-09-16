require "../core/types"
require "../rendering/draw_primitive"
require "../rendering/render_backend"
require "../rendering/pixel_snap"
require "../rendering/clip_math"
require "./test_font"

module CrymbleUI
  module Testing
    # Headless render backend for testing layer rendering
    # Maintains a simple pixel buffer and implements basic drawing primitives
    # Tracks render operations for performance testing
    # Implements RenderBackend interface for use with LayerRenderer
    class TestRenderBackend
      include RenderBackend

      getter width : Int32
      getter height : Int32

      # Pixel buffer: row-major order (y * width + x)
      @pixels : Array(Color)

      # Performance tracking
      getter primitive_count : Int32 = 0
      getter fill_rect_count : Int32 = 0
      getter draw_rect_count : Int32 = 0
      getter draw_line_count : Int32 = 0
      getter draw_text_count : Int32 = 0
      getter clear_count : Int32 = 0

      # Clipping bug detection: tracks blit attempts at negative coordinates.
      # Both render the partial sprite, scissored by the target's clip — this counter is a
      # smell detector for layer-level clipping bugs in ScrollView, not a divergence.
      getter negative_blit_count : Int32 = 0
      getter blit_count : Int32 = 0             # full-texture blits (harness)
      getter blit_region_count : Int32 = 0      # partial-region blits — "1 slot re-blit" oracle

      # Clip stack for scissor-test simulation (matches SFML behavior).
      # NOT exposed: a getter would hand out the live array, and the cached projections
      # below are only sound while push_clip/pop_clip are the sole mutators. `clip_depth`
      # covers the one thing a caller legitimately observes.
      @clip_stack : Array(Rect) = [] of Rect

      # The clip as a device-pixel box {x0,y0,x1,y1}, x1/y1 exclusive; nil = no clip.
      # Recomputed at push/pop — exactly when CrSFMLBackend#apply_clip recomputes its
      # scissor. Deriving it per pixel instead walked the stack and allocated on every write.
      @clip_box : Tuple(Int32, Int32, Int32, Int32)? = nil

      # Scissor suspension flag (matches SFML's GL_SCISSOR_TEST disable)
      @scissor_suspended : Bool = false

      def initialize(@width : Int32, @height : Int32, background : Color = Color.new(255, 255, 255, 255))
        # Strict: a render backend dimension is non-negative by definition. SFML's
        # RenderTexture.new(.to_u32) turns a negative Int into a huge UInt ("Arithmetic
        # overflow"); the lenient pixel buffer used to silently mask that. Fail loudly so
        # a layout bug that produces a negative size is caught headlessly, not in prod.
        if @width < 0 || @height < 0
          raise ArgumentError.new("TestRenderBackend: negative dimensions #{@width}x#{@height} — a layout bug produced a negative size")
        end
        @pixels = Array(Color).new(@width * @height, background)
        @@census.try(&.<< self)
      end

      # CENSUS — an OPT-IN registry of every backend created while it is armed. Exists so a spec
      # can ask the general question ("is any UNREACHABLE backend still unreleased?") instead of
      # the fixture-specific one ("was this particular widget's backend released?"). The general
      # form is what catches a NEW stranding site: it does not care whether a widget was held in
      # @children, in layer.widgets, in an overlay list, or in some container invented later.
      #
      # Off by default and nil-checked on a cold path: an always-on registry would pin every
      # backend the whole suite ever makes, and the suite makes a great many.
      @@census : Array(TestRenderBackend)? = nil

      def self.census_start : Nil
        @@census = [] of TestRenderBackend
      end

      # Everything created since census_start. Stops recording.
      def self.census_take : Array(TestRenderBackend)
        taken = @@census || [] of TestRenderBackend
        @@census = nil
        taken
      end

      # Both projections from one derivation. ClipMath is shared with CrSFMLBackend, so
      # the collapse rule, the empty case and the float->device rounding cannot drift
      # between instrument and production.
      private def recompute_clip : Nil
        @clip_box = ClipMath.device_box(@clip_stack)
        # A push or a pop CANCELS a suspension, because production's push_clip/pop_clip
        # call apply_clip unconditionally and that re-installs the stack's box over the
        # full-target scissor suspend_clip put there. Modelling suspension as a sticky
        # flag instead let the instrument stay unclipped for a backend's whole life after
        # an unbalanced suspend — render_single_widget suspends and resumes with no
        # `ensure`, so any raise between them leaves it stuck.
        @scissor_suspended = false
      end

      # The region writes may land in: the clip box (or the whole buffer when there is no
      # clip, or while suspended) intersected with the buffer. Bulk primitives clamp their
      # destination to this ONCE rather than testing every pixel — which is both what the
      # GPU does (a scissor is a rect intersection, not a per-pixel predicate) and cheaper
      # than the per-pixel path it makes them consistent with.
      #
      # NORMALISED so it can never invert. ClipMath legitimately returns boxes that miss
      # the buffer entirely — a disjoint stack collapses to a degenerate box at, say,
      # {1000,1000,1000,1000} — and a naive intersection then yields x0 > x1. That is not
      # cosmetic: Array#fill raises on a negative count and, worse, SILENTLY fills the
      # buffer's tail on a negative start.
      protected def writable_box : Tuple(Int32, Int32, Int32, Int32)
        box = @clip_box
        return {0, 0, @width, @height} if box.nil? || @scissor_suspended
        x0 = box[0].clamp(0, @width)
        y0 = box[1].clamp(0, @height)
        {x0, y0, box[2].clamp(x0, @width), box[3].clamp(y0, @height)}
      end

      # Fill a half-open device box {x0, y0, x1, y1} — x1/y1 EXCLUSIVE, the same convention
      # ClipMath uses. The ONE place a bulk write happens, so the empty-box guard exists
      # once instead of in each caller.
      private def fill_span(x0 : Int32, y0 : Int32, x1 : Int32, y1 : Int32, color : Color) : Nil
        return if x0 >= x1 || y0 >= y1
        cols = x1 - x0
        (y0...y1).each { |y| @pixels.fill(color, y * @width + x0, cols) }
      end

      # Is this device pixel inside the clip? Four integer comparisons against the box
      # CrSFMLBackend hands to the GPU — the same box, from the same function.
      private def point_in_clip?(x : Int32, y : Int32) : Bool
        box = @clip_box
        return true if box.nil? # No clip = everything visible
        x >= box[0] && y >= box[1] && x < box[2] && y < box[3]
      end

      # Reset performance counters
      def reset_counters
        @primitive_count = 0
        @fill_rect_count = 0
        @draw_rect_count = 0
        @draw_line_count = 0
        @draw_text_count = 0
        @clear_count = 0
        @negative_blit_count = 0
        @blit_count = 0
        @blit_region_count = 0
      end

      # Headless mirror of the SFML release path. The pixel buffer is ordinary Crystal memory the
      # collector could reclaim on its own, so this is not about freeing bytes — it is about making
      # release OBSERVABLE and use-after-release LOUD. Headless can then witness the release defect
      # class deterministically (`disposed?`), where SFML can only show it as drifting RSS.
      protected def release_payload : Nil
        @pixels = Array(Color).new(0)
      end

      # Get pixel color at (x, y)
      def get_pixel(x : Int32, y : Int32) : Color?
        assert_live("get_pixel")
        return nil if x < 0 || x >= @width || y < 0 || y >= @height
        @pixels[y * @width + x]
      end

      # Set pixel color at (x, y) - respects current clip region unless suspended
      def set_pixel(x : Int32, y : Int32, color : Color)
        assert_live("set_pixel")
        return if x < 0 || x >= @width || y < 0 || y >= @height
        return unless @scissor_suspended || point_in_clip?(x, y)  # Clip check (bypassed when suspended)
        @pixels[y * @width + x] = color
      end

      # Get pixels from rectangular region (for background memorization)
      # Returns array in row-major order (top-to-bottom, left-to-right)
      def get_pixels(x : Int32, y : Int32, width : Int32, height : Int32) : Array(Color)
        assert_live("get_pixels")
        pixels = [] of Color
        height.times do |dy|
          width.times do |dx|
            color = get_pixel(x + dx, y + dy)
            pixels << (color || Color.new(0, 0, 0, 0))  # Transparent if out of bounds
          end
        end
        pixels
      end

      # Capture rectangular region of pixels as packed UInt32 (RGBA: R in high byte)
      # Used by cache validation framework for pixel comparison
      def capture_region_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Array(UInt32)
        assert_live("capture_region_pixels")
        result = Array(UInt32).new(w * h, 0_u32)
        h.times do |dy|
          w.times do |dx|
            px = x + dx
            py = y + dy
            if color = get_pixel(px, py)
              result[dy * w + dx] = (color.r.to_u32 << 24) | (color.g.to_u32 << 16) | (color.b.to_u32 << 8) | color.a.to_u32
            end
          end
        end
        result
      end

      # Save buffer to PPM image file (no dependencies required)
      def save_ppm(path : String)
        assert_live("save_ppm")
        File.open(path, "w") do |f|
          f.puts "P3"
          f.puts "#{@width} #{@height}"
          f.puts "255"
          @height.times do |y|
            @width.times do |x|
              px = @pixels[y * @width + x]
              f.print "#{px.r} #{px.g} #{px.b} "
            end
            f.puts
          end
        end
      end

      # Set pixels in rectangular region (for background restoration)
      # Expects array in row-major order (top-to-bottom, left-to-right)
      def set_pixels(x : Int32, y : Int32, width : Int32, height : Int32, pixels : Array(Color))
        assert_live("set_pixels")
        height.times do |dy|
          width.times do |dx|
            idx = dy * width + dx
            next if idx >= pixels.size  # Safety check
            set_pixel(x + dx, y + dy, pixels[idx])
          end
        end
      end

      # Clear entire buffer to color
      def clear(color : Color = Color.new(255, 255, 255, 255))
        assert_live("clear")
        @clear_count += 1
        # SFML applies the view's scissor to `clear` as well as to draws. No production
        # site clears a backend that holds its own live clip (audited — which is the whole
        # reason suspend_clip/resume_clip still exist), so this is a contract guard for the
        # next caller rather than a fix for a live defect.
        x1, y1, x2, y2 = writable_box
        fill_span(x1, y1, x2, y2, color)
      end

      # Fill rectangle with color.
      # Pixel-coverage MUST match the SFML GPU rasterizer: a pixel is filled iff its CENTER
      # (i + 0.5) lies inside the rect — NOT floor(edge). The old floor(x+w) under-filled the right/
      # bottom edge by 1px whenever the edge fell on a fractional coordinate, so the headless backend
      # DIVERGED from SFML at sub-pixel boundaries — inventing 1px edge strips that don't exist live
      # and making headless pixel tests untrustworthy. Center-coverage: first covered pixel i has
      # i+0.5 >= left  → i = ceil(left - 0.5); past-the-end has i+0.5 >= right → i = ceil(right - 0.5).
      def fill_rect(bounds : Rect, color : Color)
        assert_live("fill_rect")
        @primitive_count += 1  # Count all primitives
        @fill_rect_count += 1
        # Clamped to the CLIP, not merely the buffer: production scissors a fill like any
        # other draw. The centre-coverage rounding (the SFML rasterizer model) is
        # unchanged — only what it is clamped against.
        bx1, by1, bx2, by2 = writable_box
        fill_span(
          (bounds.x - 0.5).ceil.to_i.clamp(bx1, bx2),
          (bounds.y - 0.5).ceil.to_i.clamp(by1, by2),
          (bounds.x + bounds.width - 0.5).ceil.to_i.clamp(bx1, bx2),
          (bounds.y + bounds.height - 0.5).ceil.to_i.clamp(by1, by2),
          color)
      end

      # Four edges INSIDE bounds — the shape CrSFMLBackend#draw_rect produces (four filled
      # rects), not SFML's centred outline_thickness.
      #
      # DIVERGENCE a caller here can hit: `width` is ignored, always 1px, where production
      # honours thickness (drag_manager asks for 2.0). Two further ones are cross-file and
      # tracked in the backlog: the raw truncations below vs fill_rect's centre coverage,
      # and SFMLRenderer#execute_primitive's DrawRect arm, which is still a centred outline.
      def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)
        assert_live("draw_rect")
        @primitive_count += 1  # Count all primitives
        @draw_rect_count += 1
        x1 = bounds.x.to_i
        y1 = bounds.y.to_i
        x2 = (bounds.x + bounds.width - 1).to_i
        y2 = (bounds.y + bounds.height - 1).to_i

        # All four edges, INSIDE bounds. Production draws a border as four FILLED rects
        # positioned inside the rect (crsfml_backend.cr#draw_rect), so an edge sitting on
        # the clip boundary is inside the scissor and IS drawn; where an edge genuinely
        # falls outside, set_pixel's own clip check removes it.
        (x1..x2).each do |x|
          set_pixel(x, y1, color)
          set_pixel(x, y2, color)
        end
        (y1..y2).each do |y|
          set_pixel(x1, y, color)
          set_pixel(x2, y, color)
        end
      end

      # Draw line from (x1, y1) to (x2, y2) with width - simple Bresenham's algorithm
      # Note: width parameter accepted but simplified rendering (just draws center line)
      # For proper thick lines, would need to draw perpendicular pixels at each point
      def draw_line(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, color : Color, width : Float64 = 1.0)
        assert_live("draw_line")
        @primitive_count += 1  # Count all primitives
        @draw_line_count += 1
        ix1 = x1.to_i
        iy1 = y1.to_i
        ix2 = x2.to_i
        iy2 = y2.to_i

        dx = (ix2 - ix1).abs
        dy = (iy2 - iy1).abs
        sx = ix1 < ix2 ? 1 : -1
        sy = iy1 < iy2 ? 1 : -1
        err = dx - dy

        x = ix1
        y = iy1

        loop do
          set_pixel(x, y, color)
          break if x == ix2 && y == iy2

          e2 = 2 * err
          if e2 > -dy
            err -= dy
            x += sx
          end
          if e2 < dx
            err += dx
            y += sy
          end
        end
      end

      # Draw circle at center with radius (simplified rendering for tests)
      def draw_circle(center_x : Float64, center_y : Float64, radius : Float64, color : Color, fill : Bool = true)
        assert_live("draw_circle")
        @primitive_count += 1
        # Simple filled circle using midpoint circle algorithm
        cx = center_x.to_i
        cy = center_y.to_i
        r = radius.to_i

        x = r
        y = 0
        err = 0

        while x >= y
          # Draw 8 symmetric points
          if fill
            # Fill horizontal spans for filled circle
            (-x..x).each do |dx|
              set_pixel(cx + dx, cy + y, color)
              set_pixel(cx + dx, cy - y, color) if y != 0
            end
            (-y..y).each do |dx|
              set_pixel(cx + dx, cy + x, color) if x != y
              set_pixel(cx + dx, cy - x, color) if x != y && x != 0
            end
          else
            # Just outline points
            set_pixel(cx + x, cy + y, color)
            set_pixel(cx + y, cy + x, color)
            set_pixel(cx - y, cy + x, color)
            set_pixel(cx - x, cy + y, color)
            set_pixel(cx - x, cy - y, color)
            set_pixel(cx - y, cy - x, color)
            set_pixel(cx + y, cy - x, color)
            set_pixel(cx + x, cy - y, color)
          end

          y += 1
          err += 1 + 2*y
          if 2*(err-x) + 1 > 0
            x -= 1
            err += 1 - 2*x
          end
        end
      end

      # Fill triangle using scanline algorithm
      def fill_triangle(p1 : Vec2, p2 : Vec2, p3 : Vec2, color : Color)
        assert_live("fill_triangle")
        @primitive_count += 1
        # Sort vertices by Y coordinate
        vertices = [p1, p2, p3].sort_by(&.y)
        v0, v1, v2 = vertices[0], vertices[1], vertices[2]

        # Simple scanline fill
        y0, y1, y2 = v0.y.to_i, v1.y.to_i, v2.y.to_i

        (y0..y2).each do |y|
          next if y < 0 || y >= @height

          # Calculate x intersections at this scanline
          if y < y1
            # Upper part of triangle (v0 to v1, v0 to v2)
            t1 = (y1 == y0) ? 0.0 : (y - y0).to_f / (y1 - y0)
            t2 = (y2 == y0) ? 0.0 : (y - y0).to_f / (y2 - y0)
            x1 = v0.x + t1 * (v1.x - v0.x)
            x2 = v0.x + t2 * (v2.x - v0.x)
          else
            # Lower part of triangle (v1 to v2, v0 to v2)
            t1 = (y2 == y1) ? 0.0 : (y - y1).to_f / (y2 - y1)
            t2 = (y2 == y0) ? 0.0 : (y - y0).to_f / (y2 - y0)
            x1 = v1.x + t1 * (v2.x - v1.x)
            x2 = v0.x + t2 * (v2.x - v0.x)
          end

          # Draw horizontal span
          x_min, x_max = [x1.to_i, x2.to_i].minmax
          (x_min..x_max).each do |x|
            set_pixel(x, y, color)
          end
        end
      end

      # Draw text at position using "barcode" rendering
      # Each character draws 2 vertical lines based on 2 LSBs of char code
      # This makes text visible and testable without real font support
      def draw_text(text : String, position : Vec2, color : Color, size : Float64)
        assert_live("draw_text")
        @draw_text_count += 1

        # Pitch comes from the FONT, not from a second copy of the ratio here: the two must
        # agree or every horizontal pixel claim in the suite is measured against a width the
        # font never reported.
        char_width = (size * TestFont::CHAR_WIDTH_RATIO).to_i.clamp(4, 20)
        # The line SLOT comes from the headless font, not from a second local formula: the
        # two must agree about where line k sits or a multi-line claim is unreadable. The
        # glyph's INK is then capped to the slot, because the existing clamp floors at 6px
        # and would otherwise make ink TALLER than the step below size 6 — an instrument
        # contradicting itself, which is the failure this whole pass exists to prevent.
        line_step = TestFont.line_step(size)
        char_height = size.to_i.clamp(6, 30)
        char_height = line_step.to_i if line_step < char_height
        # Same snap as the SFML text path — headless ink lands on production's pixel.
        origin_x = PixelSnap.snap(position.x).to_i
        x = origin_x
        y = PixelSnap.snap(position.y).to_i
        line = 0

        text.each_char do |char|
          if char == '\n'
            # SFML renders `\n` natively, so the headless backend must too: back to the
            # origin column, down one slot. Snapped from the ORIGIN each time rather than
            # accumulated, so line k lands on the same device row the font's k * step
            # predicts and rounding cannot drift across a long block.
            line += 1
            x = origin_x
            y = PixelSnap.snap(position.y + line * line_step).to_i
            next
          end
          code = char.ord
          # Draw 2 vertical stripes based on 2 LSBs
          # LSB 0 -> left stripe, LSB 1 -> right stripe
          stripe_width = (char_width // 3).clamp(1, 4)

          if (code & 0x01) != 0  # LSB 0 set -> left stripe
            draw_vertical_stripe(x, y, stripe_width, char_height, color)
          end
          if (code & 0x02) != 0  # LSB 1 set -> right stripe
            draw_vertical_stripe(x + char_width - stripe_width, y, stripe_width, char_height, color)
          end

          x += char_width
        end
      end

      # Helper: draw a filled vertical stripe
      private def draw_vertical_stripe(x : Int32, y : Int32, width : Int32, height : Int32, color : Color)
        height.times do |dy|
          width.times do |dx|
            set_pixel(x + dx, y + dy, color)
          end
        end
      end

      # Finalize rendering (no-op for test backend)
      def display
        assert_live("display")
        # No-op for test backend (SFML needs this to finalize texture)
      end

      # Execute a DrawPrimitive on this backend
      def execute_primitive(primitive : DrawPrimitive)
        assert_live("execute_primitive")
        @primitive_count += 1
        case primitive
        when FillRect
          fill_rect(primitive.bounds, primitive.color)
        when DrawRect
          draw_rect(primitive.bounds, primitive.color)
        when DrawLine
          draw_line(primitive.from.x, primitive.from.y, primitive.to.x, primitive.to.y, primitive.color)
        when DrawText
          @draw_text_count += 1
          # Skip actual text rendering in tests (no font support)
        when FillTriangle
          fill_triangle(primitive.p1, primitive.p2, primitive.p3, primitive.color)
        when PushClip
          # The clip stack DOES exist here, and since it governs every write it must
          # govern these too — production's dispatcher pushes and pops the same way
          # (layer_renderer's execute_primitive_with_offset). Dropping them silently
          # rendered a widget that clips its own primitive stream unclipped.
          push_clip(primitive.rect)
        when PopClip
          pop_clip
        end
      end

      # Execute multiple primitives
      def execute_primitives(primitives : Array(DrawPrimitive))
        assert_live("execute_primitives")
        primitives.each { |p| execute_primitive(p) }
      end

      # Debug: print ASCII representation of buffer (for small buffers)
      def to_ascii(palette : Hash(Color, Char) = {} of Color => Char) : String
        assert_live("to_ascii")
        lines = [] of String
        @height.times do |y|
          line = String.build do |str|
            @width.times do |x|
              color = get_pixel(x, y).not_nil!
              str << (palette[color]? || '.')
            end
          end
          lines << line
        end
        lines.join('\n')
      end

      # Check for transparent pixels in a region (for debugging Inspector panel issue)
      # Returns count of transparent pixels found
      def check_transparent_pixels(x_start : Int32, y_start : Int32, width : Int32, height : Int32, context : String = "") : Int32
        assert_live("check_transparent_pixels")
        transparent_count = 0
        height.times do |y|
          width.times do |x|
            color = get_pixel(x_start + x, y_start + y)
            if color && color.a < 255
              transparent_count += 1
              {% if flag?(:DEBUG_TEXT) %}
                if transparent_count <= 5  # Only show first 5 to avoid spam
                  puts "    ⚠️  TRANSPARENT PIXEL #{context} at (#{x_start + x}, #{y_start + y}): rgba(#{color.r}, #{color.g}, #{color.b}, #{color.a})"
                end
              {% end %}
            end
          end
        end
        {% if flag?(:DEBUG_TEXT) %}
          if transparent_count > 0
            puts "    ⚠️  TOTAL: #{transparent_count} transparent pixels in #{width}x#{height} region #{context}"
          end
        {% end %}
        transparent_count
      end

      # Blit/composite this buffer onto target buffer at specified position
      # Supports two blend modes:
      # - BLEND mode (use_alpha_blend=true): Alpha blending, transparent pixels show target through (compositor)
      # - COPY mode (use_alpha_blend=false): Replace pixels even if transparent (widget restoration)
      # clip_width/clip_height specify the visible portion to blit (defaults to full buffer)
      # opacity: Layer opacity multiplier (0.0-1.0), applied to source alpha during blending
      def blit_to(target : TestRenderBackend, offset_x : Int32, offset_y : Int32, clip_width : Int32 = @width, clip_height : Int32 = @height, use_alpha_blend : Bool = true, opacity : Float64 = 1.0, blend_mode : BlendMode = BlendMode::Normal)
        assert_live("blit_to")
        assert_live_other(target, "blit_to", "target")
        # FAST PATH: Row-level copy for opaque blits (most common case).
        # Skips per-pixel get/set/clip overhead — direct array slice copy.
        if !use_alpha_blend || (opacity >= 1.0 && blend_mode == BlendMode::Normal)
          # Clip the DESTINATION span to the target's writable box — its clip intersected
          # with its buffer. Production draws a blit as a sprite, so the TARGET's view
          # scissor governs it exactly like any other draw; the source's clip is correctly
          # irrelevant. Clamping to the target's buffer alone let a blit paint straight
          # through a live clip, which is the architecture's main path
          # (layer_renderer.cr blits each widget texture into the layer INSIDE the layer
          # clip, in COPY mode) and the reason the slow path and the fast path disagreed.
          #
          # Derive the source start FROM the clipped destination. Computing it from the
          # sign of the offset first and clipping afterwards is the wrong variant: it drops
          # the case where the clip's near edge lies inside the buffer but beyond `offset`.
          tx1, ty1, tx2, ty2 = target.writable_box
          dx0 = Math.max(offset_x, tx1)
          dy0 = Math.max(offset_y, ty1)
          # The source rect is bounded too. clip_width/clip_height are a SOURCE-side crop
          # supplied by the caller and NOT derived from this backend — the compositor
          # passes cover()-rounded layer bounds against a span()-sized buffer — so without
          # this a row could read into the next one.
          dx1 = Math.min(offset_x + Math.min(clip_width, @width), tx2)
          dy1 = Math.min(offset_y + Math.min(clip_height, @height), ty2)
          return if dx0 >= dx1 || dy0 >= dy1

          cols = dx1 - dx0
          # Row POINTERS, not indices. Both rows are already known to be inside both buffers —
          # that is what the clipping above establishes — so re-deriving and bounds-checking the
          # index for every pixel is pure overhead, and this is the hottest loop in the headless
          # renderer by a wide margin: one idle frame of a real app composites ~3.6M pixels here
          # (measured 2026-09-12: 183ms of a 290ms frame, 63%, while painting nothing at all).
          # Arithmetic below is byte-for-byte what it was, floats included, so no pixel moves.
          src_base = @pixels.to_unsafe
          dst_base = target.@pixels.to_unsafe
          ty = dy0
          while ty < dy1
            src_row = src_base + ((ty - offset_y) * @width + (dx0 - offset_x))
            dst_row = dst_base + (ty * target.width + dx0)

            if use_alpha_blend
              # Normal blend with opacity=1.0: copy opaque pixels, blend semi-transparent.
              # `while`, not `cols.times do |j|`: the specs build in DEBUG mode, where the block
              # is a real closure call per pixel rather than an inlined loop body — and this runs
              # millions of times a frame. Same arithmetic, same order.
              j = 0
              while j < cols
                src_color = src_row[j]
                if src_color.a == 255
                  dst_row[j] = src_color
                elsif src_color.a > 0
                  bg = dst_row[j]
                  a = src_color.a / 255.0
                  dst_row[j] = Color.new(
                    ((src_color.r * a + bg.r * (1 - a)).to_i).clamp(0, 255).to_u8,
                    ((src_color.g * a + bg.g * (1 - a)).to_i).clamp(0, 255).to_u8,
                    ((src_color.b * a + bg.b * (1 - a)).to_i).clamp(0, 255).to_u8,
                    255_u8
                  )
                end
                j += 1
              end
            else
              # COPY mode: one memcpy per row. Color is a 4-byte struct, the rows cannot overlap
              # (distinct backends), and every pixel is written unconditionally — so the loop was
              # only ever a slow way of spelling this. The previous comment rejected
              # `@pixels[src_offset, cols]` because a slice allocates an Array per row; copy_from
              # allocates nothing.
              dst_row.copy_from(src_row, cols)
            end
            ty += 1
          end
          return
        end

        # SLOW PATH: Per-pixel blending for special blend modes (additive, subtractive)
        clip_height.times do |src_y|
          clip_width.times do |src_x|
            src_color = get_pixel(src_x, src_y)
            next unless src_color  # Skip if out of bounds

            target_x = src_x + offset_x
            target_y = src_y + offset_y

            # Apply layer opacity multiplier to source alpha
            effective_alpha = (src_color.a / 255.0) * opacity
            next if effective_alpha == 0.0  # Skip fully transparent

            if blend_mode == BlendMode::Additive
              if bg = target.get_pixel(target_x, target_y)
                blended = Color.new(
                  (bg.r + src_color.r * effective_alpha).clamp(0, 255).to_i.to_u8,
                  (bg.g + src_color.g * effective_alpha).clamp(0, 255).to_i.to_u8,
                  (bg.b + src_color.b * effective_alpha).clamp(0, 255).to_i.to_u8,
                  255_u8
                )
                target.set_pixel(target_x, target_y, blended)
              end
            elsif blend_mode == BlendMode::Subtractive
              if bg = target.get_pixel(target_x, target_y)
                blended = Color.new(
                  (bg.r - src_color.r * effective_alpha).clamp(0, 255).to_i.to_u8,
                  (bg.g - src_color.g * effective_alpha).clamp(0, 255).to_i.to_u8,
                  (bg.b - src_color.b * effective_alpha).clamp(0, 255).to_i.to_u8,
                  255_u8
                )
                target.set_pixel(target_x, target_y, blended)
              end
            elsif effective_alpha >= 1.0
              target.set_pixel(target_x, target_y, src_color)
            else
              if bg = target.get_pixel(target_x, target_y)
                blended = Color.new(
                  ((src_color.r * effective_alpha + bg.r * (1 - effective_alpha)).to_i).clamp(0, 255).to_u8,
                  ((src_color.g * effective_alpha + bg.g * (1 - effective_alpha)).to_i).clamp(0, 255).to_u8,
                  ((src_color.b * effective_alpha + bg.b * (1 - effective_alpha)).to_i).clamp(0, 255).to_u8,
                  255_u8
                )
                target.set_pixel(target_x, target_y, blended)
              end
            end
          end
        end
      end

      # Implement RenderBackend#blit interface
      # Blit entire source backend to this backend at specified position
      # Uses COPY mode (matches SFML's BlendNone) for widget backend restoration
      def blit(source : RenderBackend, dest_x : Int32, dest_y : Int32)
        assert_live("blit")
        assert_live_other(source, "blit", "source")
        @blit_count += 1
        # Track negative blit destinations (indicates missing layer-level clipping).
        # SFML renders the partial sprite, scissored by the target's view; blit_to matches
        # that by clipping the destination span to the target's writable box.
        if dest_x < 0 || dest_y < 0
          @negative_blit_count += 1
        end

        # Cast to TestRenderBackend to access blit_to method
        if source.is_a?(TestRenderBackend)
          source.blit_to(self, dest_x, dest_y, use_alpha_blend: false)  # COPY mode
        else
          raise "TestRenderBackend can only blit from another TestRenderBackend"
        end
      end

      # Blit rectangular region from this backend to target with alpha blending
      # Copies pixels from (src_x, src_y, width, height) to target at (dest_x, dest_y)
      # Supports alpha blending and opacity (for viewport_cache layer compositing)
      def blit_region_to(target : TestRenderBackend, src_x : Int32, src_y : Int32, width : Int32, height : Int32, dest_x : Int32, dest_y : Int32, use_alpha_blend : Bool = true, opacity : Float64 = 1.0, blend_mode : BlendMode = BlendMode::Normal)
        assert_live("blit_region_to")
        assert_live_other(target, "blit_region_to", "target")
        height.times do |dy|
          width.times do |dx|
            src_color = get_pixel(src_x + dx, src_y + dy)
            next unless src_color  # Skip if out of bounds

            target_x = dest_x + dx
            target_y = dest_y + dy

            if use_alpha_blend
              effective_alpha = (src_color.a / 255.0) * opacity
              next if effective_alpha == 0.0  # Skip fully transparent

              if blend_mode == BlendMode::Additive
                # ADDITIVE: result = src * alpha + dst (non-damping)
                if bg = target.get_pixel(target_x, target_y)
                  blended = Color.new(
                    (bg.r + src_color.r * effective_alpha).clamp(0, 255).to_i.to_u8,
                    (bg.g + src_color.g * effective_alpha).clamp(0, 255).to_i.to_u8,
                    (bg.b + src_color.b * effective_alpha).clamp(0, 255).to_i.to_u8,
                    255_u8
                  )
                  target.set_pixel(target_x, target_y, blended)
                end
              elsif blend_mode == BlendMode::Subtractive
                # SUBTRACTIVE: result = dst - src * alpha (for darkening highlight on light bg)
                if bg = target.get_pixel(target_x, target_y)
                  blended = Color.new(
                    (bg.r - src_color.r * effective_alpha).clamp(0, 255).to_i.to_u8,
                    (bg.g - src_color.g * effective_alpha).clamp(0, 255).to_i.to_u8,
                    (bg.b - src_color.b * effective_alpha).clamp(0, 255).to_i.to_u8,
                    255_u8
                  )
                  target.set_pixel(target_x, target_y, blended)
                end
              elsif effective_alpha >= 1.0
                target.set_pixel(target_x, target_y, src_color)
              else
                # ALPHA BLEND: result = src * alpha + dst * (1 - alpha)
                if bg = target.get_pixel(target_x, target_y)
                  blended = Color.new(
                    ((src_color.r * effective_alpha + bg.r * (1 - effective_alpha)).to_i).clamp(0, 255).to_u8,
                    ((src_color.g * effective_alpha + bg.g * (1 - effective_alpha)).to_i).clamp(0, 255).to_u8,
                    ((src_color.b * effective_alpha + bg.b * (1 - effective_alpha)).to_i).clamp(0, 255).to_u8,
                    255_u8
                  )
                  target.set_pixel(target_x, target_y, blended)
                end
              end
            else
              target.set_pixel(target_x, target_y, src_color)
            end
          end
        end
      end

      # Blit rectangular region from source backend to this backend
      # Copies pixels from (src_x, src_y, width, height) to (dest_x, dest_y)
      def blit_region(source : RenderBackend, src_x : Int32, src_y : Int32, width : Int32, height : Int32, dest_x : Int32, dest_y : Int32)
        assert_live("blit_region")
        assert_live_other(source, "blit_region", "source")
        @blit_region_count += 1
        if source.is_a?(TestRenderBackend)
          # Copy pixel region
          height.times do |dy|
            width.times do |dx|
              if src_color = source.get_pixel(src_x + dx, src_y + dy)
                # Simple copy (no alpha blending for background capture)
                set_pixel(dest_x + dx, dest_y + dy, src_color)
              end
            end
          end
        else
          raise "TestRenderBackend can only blit from another TestRenderBackend"
        end
      end

      # Push clipping region onto stack (matches SFML scissor test behavior)
      def push_clip(rect : Rect)
        assert_live("push_clip")
        @clip_stack << rect
        recompute_clip
      end

      # Pop clipping region from stack
      def pop_clip
        assert_live("pop_clip")
        # The `if any?` SWALLOWS an underflow that CrSFMLBackend#pop_clip raises on —
        # a recorded divergence, tracked in the backlog, not a contract.
        @clip_stack.pop if @clip_stack.any?
        recompute_clip
      end

      def clip_depth : Int32
        @clip_stack.size
      end

      # Suspend scissor clipping (matches SFML's glDisable(GL_SCISSOR_TEST))
      # Used during background capture when drawing to OTHER backends
      def suspend_clip
        assert_live("suspend_clip")
        @scissor_suspended = true
      end

      # Resume scissor clipping (matches SFML's glEnable(GL_SCISSOR_TEST))
      def resume_clip
        assert_live("resume_clip")
        @scissor_suspended = false
      end

      # Concise inspect for readable spec output (prevents dumping pixel arrays)
      def inspect(io : IO)
        io << "TestRenderBackend(#{@width}x#{@height}, prims=#{@primitive_count}, clears=#{@clear_count})"
      end
    end
  end
end
