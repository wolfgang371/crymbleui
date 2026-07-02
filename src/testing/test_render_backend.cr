require "../core/types"
require "../rendering/draw_primitive"
require "../rendering/render_backend"

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

      # Clipping bug detection: tracks blit attempts at negative coordinates
      # SFML allows this (renders partial sprite), TestRenderBackend clips it
      # Used to detect layer-level clipping bugs in ScrollView
      getter negative_blit_count : Int32 = 0
      getter blit_count : Int32 = 0             # full-texture blits (harness)
      getter blit_region_count : Int32 = 0      # partial-region blits — "1 slot re-blit" oracle

      # Clip stack for scissor-test simulation (matches SFML behavior)
      @clip_stack : Array(Rect) = [] of Rect
      getter clip_stack

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
      end

      # Get current clip rect (intersection of all rects on stack)
      private def current_clip : Rect?
        return nil if @clip_stack.empty?
        # Intersect all rects on stack
        result = @clip_stack.first
        @clip_stack.each_with_index do |rect, i|
          next if i == 0
          result = intersect_rects(result, rect)
        end
        result
      end

      # Intersect two rectangles
      private def intersect_rects(a : Rect, b : Rect) : Rect
        x1 = [a.x, b.x].max
        y1 = [a.y, b.y].max
        x2 = [a.x + a.width, b.x + b.width].min
        y2 = [a.y + a.height, b.y + b.height].min
        width = [x2 - x1, 0.0].max
        height = [y2 - y1, 0.0].max
        Rect.new(x1, y1, width, height)
      end

      # Check if point is within current clip region
      private def point_in_clip?(x : Int32, y : Int32) : Bool
        clip = current_clip
        return true if clip.nil?  # No clip = everything visible
        x >= clip.x.to_i && x < (clip.x + clip.width).to_i &&
        y >= clip.y.to_i && y < (clip.y + clip.height).to_i
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

      # Get pixel color at (x, y)
      def get_pixel(x : Int32, y : Int32) : Color?
        return nil if x < 0 || x >= @width || y < 0 || y >= @height
        @pixels[y * @width + x]
      end

      # Set pixel color at (x, y) - respects current clip region unless suspended
      def set_pixel(x : Int32, y : Int32, color : Color)
        return if x < 0 || x >= @width || y < 0 || y >= @height
        return unless @scissor_suspended || point_in_clip?(x, y)  # Clip check (bypassed when suspended)
        @pixels[y * @width + x] = color
      end

      # Get pixels from rectangular region (for background memorization)
      # Returns array in row-major order (top-to-bottom, left-to-right)
      def get_pixels(x : Int32, y : Int32, width : Int32, height : Int32) : Array(Color)
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
        @clear_count += 1
        @pixels.fill(color)
      end

      # Fill rectangle with color.
      # Pixel-coverage MUST match the SFML GPU rasterizer: a pixel is filled iff its CENTER
      # (i + 0.5) lies inside the rect — NOT floor(edge). The old floor(x+w) under-filled the right/
      # bottom edge by 1px whenever the edge fell on a fractional coordinate, so the headless backend
      # DIVERGED from SFML at sub-pixel boundaries — inventing 1px edge strips that don't exist live
      # and making headless pixel tests untrustworthy. Center-coverage: first covered pixel i has
      # i+0.5 >= left  → i = ceil(left - 0.5); past-the-end has i+0.5 >= right → i = ceil(right - 0.5).
      def fill_rect(bounds : Rect, color : Color)
        @primitive_count += 1  # Count all primitives
        @fill_rect_count += 1
        x1 = (bounds.x - 0.5).ceil.to_i.clamp(0, @width)
        y1 = (bounds.y - 0.5).ceil.to_i.clamp(0, @height)
        x2 = (bounds.x + bounds.width - 0.5).ceil.to_i.clamp(0, @width)
        y2 = (bounds.y + bounds.height - 0.5).ceil.to_i.clamp(0, @height)
        return if x1 >= x2 || y1 >= y2

        cols = x2 - x1
        (y1...y2).each do |y|
          offset = y * @width + x1
          cols.times { |i| @pixels[offset + i] = color }
        end
      end

      # Draw rectangle outline with color
      # Simulates SFML's outline_thickness behavior: border is drawn CENTERED on edges
      # When shape starts at x=0, border extends from x=-0.5 to x=0.5, so left half is clipped
      # This reproduces the clipping bug visible in checkbox_demo
      # Note: width parameter currently ignored in test backend (always draws 1px)
      def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)
        @primitive_count += 1  # Count all primitives
        @draw_rect_count += 1
        x1 = bounds.x.to_i
        y1 = bounds.y.to_i
        x2 = (bounds.x + bounds.width - 1).to_i
        y2 = (bounds.y + bounds.height - 1).to_i

        # SFML outline_thickness draws centered on edges (±0.5px from edge)
        # When rect starts at x=0, left edge at -0.5 gets clipped by widget bounds
        # Simulate this by skipping leftmost column and topmost row when bounds start at 0
        skip_left = (bounds.x == 0.0)
        skip_top = (bounds.y == 0.0)

        # Top and bottom edges (skip left/right corners if those edges are clipped)
        start_x = skip_left ? x1 + 1 : x1
        (start_x..x2).each do |x|
          set_pixel(x, y1, color) unless skip_top
          set_pixel(x, y2, color)
        end

        # Left and right edges
        start_y = skip_top ? y1 + 1 : y1
        (start_y..y2).each do |y|
          set_pixel(x1, y, color) unless skip_left
          set_pixel(x2, y, color)
        end
      end

      # Draw line from (x1, y1) to (x2, y2) with width - simple Bresenham's algorithm
      # Note: width parameter accepted but simplified rendering (just draws center line)
      # For proper thick lines, would need to draw perpendicular pixels at each point
      def draw_line(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, color : Color, width : Float64 = 1.0)
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
        @draw_text_count += 1

        char_width = (size * 0.6).to_i.clamp(4, 20)  # ~60% of height
        char_height = size.to_i.clamp(6, 30)
        x = position.x.to_i
        y = position.y.to_i

        text.each_char do |char|
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
        # No-op for test backend (SFML needs this to finalize texture)
      end

      # Execute a DrawPrimitive on this backend
      def execute_primitive(primitive : DrawPrimitive)
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
        when PushClip, PopClip
          # Skip clipping in tests (would need clip stack implementation)
        end
      end

      # Execute multiple primitives
      def execute_primitives(primitives : Array(DrawPrimitive))
        primitives.each { |p| execute_primitive(p) }
      end

      # Debug: print ASCII representation of buffer (for small buffers)
      def to_ascii(palette : Hash(Color, Char) = {} of Color => Char) : String
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
        # FAST PATH: Row-level copy for opaque blits (most common case).
        # Skips per-pixel get/set/clip overhead — direct array slice copy.
        if !use_alpha_blend || (opacity >= 1.0 && blend_mode == BlendMode::Normal)
          # Clamp to valid target region
          src_y_start = offset_y < 0 ? -offset_y : 0
          src_x_start = offset_x < 0 ? -offset_x : 0
          rows = Math.min(clip_height - src_y_start, target.height - (offset_y + src_y_start))
          cols = Math.min(clip_width - src_x_start, target.width - (offset_x + src_x_start))
          return if rows <= 0 || cols <= 0

          rows.times do |i|
            sy = src_y_start + i
            ty = offset_y + sy
            src_offset = sy * @width + src_x_start
            dst_offset = ty * target.width + (offset_x + src_x_start)

            if use_alpha_blend
              # Normal blend with opacity=1.0: copy opaque pixels, blend semi-transparent
              cols.times do |j|
                src_color = @pixels[src_offset + j]
                if src_color.a == 255
                  target.@pixels[dst_offset + j] = src_color
                elsif src_color.a > 0
                  bg = target.@pixels[dst_offset + j]
                  a = src_color.a / 255.0
                  target.@pixels[dst_offset + j] = Color.new(
                    ((src_color.r * a + bg.r * (1 - a)).to_i).clamp(0, 255).to_u8,
                    ((src_color.g * a + bg.g * (1 - a)).to_i).clamp(0, 255).to_u8,
                    ((src_color.b * a + bg.b * (1 - a)).to_i).clamp(0, 255).to_u8,
                    255_u8
                  )
                end
              end
            else
              # COPY mode: direct array copy (no alpha check)
              @pixels[src_offset, cols].each_with_index do |c, j|
                target.@pixels[dst_offset + j] = c
              end
            end
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
        @blit_count += 1
        # Track negative blit destinations (indicates missing layer-level clipping)
        # SFML would render partial sprite; TestRenderBackend clips via set_pixel bounds check
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
        @clip_stack << rect
      end

      # Pop clipping region from stack
      def pop_clip
        @clip_stack.pop if @clip_stack.any?
      end

      # Suspend scissor clipping (matches SFML's glDisable(GL_SCISSOR_TEST))
      # Used during background capture when drawing to OTHER backends
      def suspend_clip
        @scissor_suspended = true
      end

      # Resume scissor clipping (matches SFML's glEnable(GL_SCISSOR_TEST))
      def resume_clip
        @scissor_suspended = false
      end

      # Concise inspect for readable spec output (prevents dumping pixel arrays)
      def inspect(io : IO)
        io << "TestRenderBackend(#{@width}x#{@height}, prims=#{@primitive_count}, clears=#{@clear_count})"
      end
    end
  end
end
