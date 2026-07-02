require "../rendering/draw_primitive"
require "../core/types"

module CrymbleUI
  # DSL for building primitive lists declaratively
  #
  # Usage:
  #   class MyWidget < Widget
  #     include PrimitiveBuilder
  #
  #     def to_primitives(bounds : Rect) : Array(DrawPrimitive)
  #       primitives do
  #         fill_rect(bounds, color)
  #         draw_text("Hello", pos, color)
  #       end
  #     end
  #   end
  module PrimitiveBuilder
    @primitives : Array(DrawPrimitive)?

    # DSL entry point - execute block and return collected primitives
    def primitives(&block) : Array(DrawPrimitive)
      @primitives = [] of DrawPrimitive
      yield
      @primitives.not_nil!
    end

    # Fill a rectangle with a solid color
    def fill_rect(bounds : Rect, color : Color)
      @primitives.not_nil! << FillRect.new(bounds, color)
    end

    # Fill a widget's ENTIRE background. Use this — not fill_rect(Rect.new(0,0,bounds.width,
    # bounds.height)) — for a full-area background. The widget_backend is pixel-snapped to
    # floor(abs_right)-floor(abs_left), which is up to 1px WIDER than the logical bounds.width when
    # the widget sits on a fractional position (e.g. a half-pixel from an Expanded 50/50 split). A
    # fill of the logical width then leaves that last column transparent — a 1px white "strip" at the
    # widget's right/bottom edge that blinks in at the window widths where the split lands on x.5.
    # ceil covers the snapped backend in every case (ceil(bounds.width) >= widget_width); the fill is
    # clamped to the backend, so it never bleeds onto a sibling.
    def fill_background(bounds : Rect, color : Color)
      @primitives.not_nil! << FillRect.new(Rect.new(0.0, 0.0, bounds.width.ceil, bounds.height.ceil), color)
    end

    # Draw text at a position with automatic SFML offset compensation
    #
    # SFML's sf::Text has internal offsets (local_bounds.left/top) that shift where
    # glyphs actually render. Without compensation, text appears to have unequal padding
    # and can render outside widget bounds.
    #
    # This function compensates by subtracting the offsets, ensuring:
    # 1. Visual glyphs appear exactly at the requested position
    # 2. Text stays within bounds measured by measure_text()
    # 3. Equal visual padding on all sides when centered
    #
    # Research: Based on SFML Game Development Book's centerOrigin() implementation
    # which adds offsets when centering: origin = (left + width/2, top + height/2)
    # We do the inverse: position = requested_pos - (left, top)
    # NOTE: Uses font_scale (Int32) to enforce zoom-aware font sizing
    def draw_text(text : String, position : Vec2, color : Color, font_scale : Int32 = 0)
      size = FontSizing.calculate_size(font_scale)
      # Get the font to measure offsets
      if font = Widget.font
        # Text may have left/top offsets in rendering (SFML-specific)
        # The visual glyphs start at (position.x + left, position.y + top)
        # We compensate by subtracting these offsets so visual glyphs appear at the requested position
        left_offset, top_offset = font.get_text_offsets(text, size)
        adjusted_position = Vec2.new(position.x - left_offset, position.y - top_offset)
        @primitives.not_nil! << DrawText.new(text, adjusted_position, color, size)
      else
        # Fallback if no font loaded (shouldn't happen in practice)
        @primitives.not_nil! << DrawText.new(text, position, color, size)
      end
    end

    # Local y at which to draw a single line of text so it is vertically centered in the
    # band [band_top, band_top + band_height]. draw_text anchors the cap-top, so we centre
    # the font's real visual extent (reference_height) -- NOT the em font_size, which
    # over-reserves the descender slot and makes text sit high. Headless fonts report
    # reference_height == font_size, so this reduces to the previous `(h - font_size)/2`.
    def vcentered_text_y(band_height : Float64, font_scale : Int32 = 0, band_top : Float64 = 0.0) : Float64
      size = FontSizing.calculate_size(font_scale)
      ref_h = (font = Widget.font) ? font.reference_height(size) : size
      band_top + (band_height - ref_h) / 2.0
    end

    # Draw a line between two points
    def draw_line(from : Vec2, to : Vec2, color : Color, width : Float64 = 1.0)
      @primitives.not_nil! << DrawLine.new(from, to, color, width)
    end

    # Draw a circle (filled or outline)
    def draw_circle(center : Vec2, radius : Float64, color : Color, fill : Bool = true)
      @primitives.not_nil! << DrawCircle.new(center, radius, color, fill)
    end

    # Fill a triangle with 3 vertices
    def fill_triangle(p1 : Vec2, p2 : Vec2, p3 : Vec2, color : Color)
      @primitives.not_nil! << FillTriangle.new(p1, p2, p3, color)
    end

    # Draw a rectangle outline
    def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)
      @primitives.not_nil! << DrawRect.new(bounds, color, width)
    end

    # Draw the REAL checkbox glyph (box outline + state mark) into the current
    # primitives block — the shared visual used by Checkbox, the MultiComboBox
    # gutter, and checkable menu items. Geometry only: the caller resolves colors
    # (including any focus highlight) and sizes. `rect` is the square box area;
    # `rect.width` is taken as the box size. Box = 4 edge fill_rects (always);
    # Checked = 2 lines + a junction circle; Indeterminate = 1 dash; Unchecked = box only.
    def draw_check_glyph(state : CheckState, rect : Rect, box_color : Color, check_color : Color,
                         line_thickness : Float64 = 2.0, junction_radius : Float64 = 1.0)
      box_x = rect.x
      box_y = rect.y
      box = rect.width

      # Box border as 4 filled rectangles (pixel-perfect, drawn inside bounds —
      # avoids SFML outline_thickness clipping).
      fill_rect(Rect.new(box_x, box_y, box, 1.0), box_color)             # Top
      fill_rect(Rect.new(box_x, box_y + box - 1.0, box, 1.0), box_color) # Bottom
      fill_rect(Rect.new(box_x, box_y, 1.0, box), box_color)             # Left
      fill_rect(Rect.new(box_x + box - 1.0, box_y, 1.0, box), box_color) # Right

      case state
      when CheckState::Checked
        cx = box_x + box / 2.0
        cy = box_y + box / 2.0
        cs = box * 0.7
        # Short down-left stroke into the junction, then long up-right stroke.
        p1 = Vec2.new(cx - cs * 0.35, cy - cs * 0.1)
        junction = Vec2.new(cx - cs * 0.1, cy + cs * 0.25)
        p4 = Vec2.new(cx + cs * 0.4, cy - cs * 0.4)
        draw_line(p1, junction, check_color, line_thickness)
        draw_line(junction, p4, check_color, line_thickness)
        draw_circle(junction, junction_radius, check_color, fill: true)
      when CheckState::Indeterminate
        pad = box * 0.2
        draw_line(Vec2.new(box_x + pad, box_y + box / 2.0),
          Vec2.new(box_x + box - pad, box_y + box / 2.0), check_color, line_thickness)
      when CheckState::Unchecked
        # Box only.
      end
    end

    # Push a clipping rectangle
    def push_clip(rect : Rect)
      @primitives.not_nil! << PushClip.new(rect)
    end

    # Pop the most recent clipping rectangle
    def pop_clip
      @primitives.not_nil! << PopClip.new
    end
  end
end
