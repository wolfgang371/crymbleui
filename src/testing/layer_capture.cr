# Full lib: LayerCapture references Layer, Widget and CrSFMLBackend, whose transitive
# graph forward-references App; the consumers (autotests/twins/sweep) already load the
# whole lib, so require it here too rather than replay a fragile partial ordering.
require "../crymble-ui"

module CrymbleUI
  module Testing
    # Pixel-capture toolkit for SFML-backed instruments (parity sweep, bug hunts).
    # Unifies the six divergent copies that were duplicated across spec/autotest/ —
    # layer-region + visible-region capture, the software whole-window compositor
    # (the ONLY sticky-inclusive view any instrument has), PNG save, RGBA formatting,
    # the black-pixel predicate/count, and the tolerance compare.
    #
    # SFML-CONDITIONAL TREATMENT: this file is compiled UNCONDITIONALLY, exactly like
    # crsfml_backend.cr — CrSFML is a hard build dependency (there is no compile flag
    # gating SFML in this codebase; `require "../csfml3/wrapper"` is unconditional), so
    # the CrSFMLBackend / SF references below compile fine in a headless build. The
    # GPU-sampling functions (copy_to_image / get_pixel / save_to_file) merely need a
    # live DISPLAY at RUNTIME — the same runtime convention CrSFMLBackend#apply_clip
    # uses (headless has no GPU context). They no-op gracefully off a non-SFML backend.
    #
    # The backend-generic signatures (is_black_pixel?, count_black_pixels,
    # pixels_different?, rgba_string) touch no SFML and are unit-tested directly in
    # spec/testing/layer_capture_spec.cr. The SFML capture paths are exercised on real
    # hardware by the SFML parity sweep (a headless spec cannot sample a real FBO).
    #
    # RGBA packing convention (shared with every retired autotest): R in the high byte,
    #   rgba = (r << 24) | (g << 16) | (b << 8) | a.
    module LayerCapture
      # Capture a rectangular region of a layer's backend as {x, y, RGBA} tuples.
      def self.capture_layer_region(layer : CrymbleUI::Layer?, x1 : Int32, y1 : Int32, x2 : Int32, y2 : Int32, step : Int32 = 2) : Array(Tuple(Int32, Int32, UInt32))
        result = [] of Tuple(Int32, Int32, UInt32)
        return result unless layer
        backend = layer.backend
        return result unless backend.is_a?(CrymbleUI::CrSFMLBackend)
        image = backend.texture.copy_to_image
        y = y1
        while y <= y2
          x = x1
          while x <= x2
            if x >= 0 && y >= 0 && x < image.size.x.to_i && y < image.size.y.to_i
              px = image.get_pixel(x, y)
              rgba = (px.r.to_u32 << 24) | (px.g.to_u32 << 16) | (px.b.to_u32 << 8) | px.a.to_u32
              result << {x, y, rgba}
            end
            x += step
          end
          y += step
        end
        result
      end

      # Capture the VISIBLE region of a layer, accounting for a viewport_cache layer's
      # buffer origin (scroll_offset - buffer_origin maps viewport to buffer coords).
      def self.capture_layer_visible_region(layer : CrymbleUI::Layer, step : Int32 = 2) : Array(Tuple(Int32, Int32, UInt32))
        if layer.viewport_cache
          buf_x = (layer.scroll_offset.x - layer.buffer_origin.x).to_i
          buf_y = (layer.scroll_offset.y - layer.buffer_origin.y).to_i
          vp_w = layer.bounds.width.to_i
          vp_h = layer.bounds.height.to_i
          capture_layer_region(layer, buf_x, buf_y, buf_x + vp_w, buf_y + vp_h, step)
        else
          b = layer.bounds
          capture_layer_region(layer, 0, 0, b.width.to_i, b.height.to_i, step)
        end
      end
      # Software whole-window compositor — the only sticky-inclusive "what the user
      # sees" view any instrument has. Overlays layers bottom-to-top
      # (content -> sticky_col -> sticky_row -> sticky_corner) onto a background fill,
      # converting each viewport_cache layer's buffer coords to screen coords the same
      # way SFML's texture_rect offset does.
      def self.capture_window_composite(
        content_layer : CrymbleUI::Layer?,
        sticky_col_layer : CrymbleUI::Layer?,
        sticky_row_layer : CrymbleUI::Layer?,
        sticky_corner_layer : CrymbleUI::Layer?,
        window_width : Int32, window_height : Int32,
        bg_rgba : UInt32, step : Int32 = 2
      ) : Array(Tuple(Int32, Int32, UInt32))
        pixels = Hash(Tuple(Int32, Int32), UInt32).new

        # Initialize sampled grid with the window background.
        y = 0
        while y < window_height
          x = 0
          while x < window_width
            pixels[{x, y}] = bg_rgba
            x += step
          end
          y += step
        end

        # Overlay layers bottom-to-top.
        [content_layer, sticky_col_layer, sticky_row_layer, sticky_corner_layer].each do |layer|
          next unless layer
          visible = capture_layer_visible_region(layer, step)
          layer_x = layer.bounds.x.to_i
          layer_y = layer.bounds.y.to_i

          # viewport_cache layers: buffer coords -> viewport-relative before mapping to
          # screen (the SFML compositor does this via the texture_rect offset).
          vp_offset_x = 0
          vp_offset_y = 0
          if layer.viewport_cache
            vp_offset_x = (layer.scroll_offset.x - layer.buffer_origin.x).to_i
            vp_offset_y = (layer.scroll_offset.y - layer.buffer_origin.y).to_i
          end

          visible.each do |lx, ly, rgba|
            sx = (lx - vp_offset_x) + layer_x
            sy = (ly - vp_offset_y) + layer_y
            # Snap to the step grid for a consistent lookup key.
            sx = (sx // step) * step
            sy = (sy // step) * step
            next if sx < 0 || sy < 0 || sx >= window_width || sy >= window_height
            # Skip near-transparent pixels (don't overwrite lower layers).
            a = rgba & 0xFF
            pixels[{sx, sy}] = rgba if a > 128
          end
        end

        pixels.map { |(pos, rgba)| {pos[0], pos[1], rgba} }
      end

      # Save a layer's backend to a PNG file (GPU->CPU->disk; instrument diagnostics).
      def self.save_layer_image(layer : CrymbleUI::Layer?, path : String)
        return unless layer
        backend = layer.backend
        return unless backend.is_a?(CrymbleUI::CrSFMLBackend)
        image = backend.texture.copy_to_image
        image.save_to_file(path)
      end

      # Human-readable RGBA for diagnostics.
      def self.rgba_string(rgba : UInt32) : String
        r = (rgba >> 24) & 0xFF
        g = (rgba >> 16) & 0xFF
        b = (rgba >> 8) & 0xFF
        a = rgba & 0xFF
        "RGBA(#{r},#{g},#{b},#{a})"
      end

      # Black pixel = opaque window-background showing through where a cell should be
      # (the GAP class of sticky/scroll bugs). Window bg ~(40,40,40), cell bg ~(45,50,55).
      def self.is_black_pixel?(rgba : UInt32) : Bool
        r = ((rgba >> 24) & 0xFF).to_i
        g = ((rgba >> 16) & 0xFF).to_i
        b = ((rgba >> 8) & 0xFF).to_i
        a = (rgba & 0xFF).to_i
        avg = (r + g + b) / 3
        a > 200 && avg < 43
      end

      def self.count_black_pixels(pixels : Array(Tuple(Int32, Int32, UInt32))) : Int32
        pixels.count { |_, _, rgba| is_black_pixel?(rgba) }
      end

      # Per-channel tolerance compare (ignores alpha) — the GARBLE/color-drift class.
      def self.pixels_different?(a : UInt32, b : UInt32, tolerance : Int32 = 5) : Bool
        ar = ((a >> 24) & 0xFF).to_i
        ag = ((a >> 16) & 0xFF).to_i
        ab = ((a >> 8) & 0xFF).to_i
        br = ((b >> 24) & 0xFF).to_i
        bg = ((b >> 16) & 0xFF).to_i
        bb = ((b >> 8) & 0xFF).to_i
        (ar - br).abs > tolerance || (ag - bg).abs > tolerance || (ab - bb).abs > tolerance
      end
    end
  end
end
