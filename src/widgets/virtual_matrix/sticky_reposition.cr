module CrymbleUI
  class VirtualMatrix < Widget
    # Reposition sticky cells to account for scroll offset.
    # Sticky layers (row/col/corner) are non-viewport_cache, so they don't apply
    # scroll_offset during compositing. Cells must be positioned at screen-space
    # coordinates for correct alignment with the viewport_cache content layer.
    #
    # Uses TRUE content-space positions (linear sum of sizes) rather than StickyMath
    # offset+positions, because StickyMath output includes a scroll-dependent offset
    # that only works correctly with viewport_cache layers.
    #
    # - sticky_row cells: x = true_x - painted_scroll.x, y = true_y (fixed vertically)
    # - sticky_col cells: x = true_x (fixed horizontally), y = true_y - painted_scroll.y
    # - sticky_corner cells: x = true_x, y = true_y (fixed both ways)
    # - content cells: not touched (viewport_cache handles scroll)
    #
    # So a sticky cell is painted AT its bounds: VirtualMatrix#paint_shift_for shifts it by nothing, and
    # painted_rect reads its bounds as they are. Where a sticky cell belongs is ONE method, sticky_cell_rect,
    # which this pass and the blit plan's mirror both apply.
    private def reposition_sticky_cells(cells_destroyed : Bool = false)
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return if sticky_rows == 0 && sticky_cols == 0
      return if @active_cells.empty?

      return unless @cached_col_sizes && @cached_row_sizes
      col_view, row_view = sticky_axis_views

      any_changed = false

      @active_cells.each do |key, widget|
        row, col = key
        next unless row < sticky_rows || col < sticky_cols

        # The layout pass's half of CRYMBLE_CARET_LOG. Without it, "no [caret] line this frame" is
        # ambiguous between "no frame ran" and "the OTHER pass ran" — and the two have opposite
        # fixes. The blit-path half lives in blit_plan.cr; the passes run either/or per frame.
        log_caret_frame(key, "LAYOUT", widget)
        target = sticky_cell_rect(key, widget, col_view, row_view)
        new_x, new_y, new_w, new_h = target.x, target.y, target.width, target.height

        # Only reposition/resize if changed (avoids unnecessary layout calls)
        if widget.bounds.x != new_x || widget.bounds.y != new_y || widget.bounds.width != new_w || widget.bounds.height != new_h
          {% if flag?(:DEBUG_BLIT) %}
            File.open("/tmp/blit_trace.log", "a") do |f|
              f.puts "REPOSITION: #{widget.class.name.split("::").last}##{widget.path_id} (#{widget.bounds.width.round(1)}x#{widget.bounds.height.round(1)}) → (#{new_w.round(1)}x#{new_h.round(1)}) at (#{new_x.round(1)},#{new_y.round(1)})"
            end
          {% end %}
          # Only invalidate primitive cache if SIZE changed (not just position).
          # Position-only changes: cached widget_backend texture is still valid,
          # just needs to be blitted at the new position. Avoids expensive primitive
          # regeneration + full re-render for every scroll frame.
          size_changed = widget.bounds.width != new_w || widget.bounds.height != new_h
          cell_constraints = BoxConstraints.tight(Size.new(new_w, new_h))
          widget.layout(cell_constraints, Vec2.new(new_x, new_y))
          widget.invalidate_primitive_cache if size_changed
          any_changed = true
        end
      end

      # Clear and re-render sticky layers to reflect new cell positions.
      # Use mark_needs_clear_and_render (NOT mark_needs_layout) — lighter:
      # no sibling validation, NeedsRender semantics, but still clears old pixels.
      # This is the FALLBACK path (a sticky cell has no cached texture yet); the common scroll/resize
      # case goes through compute_sticky_blit_plans, which is per-layer (only touches changed layers).
      {% if flag?(:probe) %}
        # Which pass moved the sticky cells this frame? The code says the two run either/or, so a
        # frame served by NEITHER is a third case worth seeing.
        if CrymbleUI::BlitProbe.on?
          CrymbleUI::BlitProbe.emit("reposition pass ran, any_changed=#{any_changed}")
        end
      {% end %}
      # Clear when a cell MOVED (its old pixels are stale where it used to be) or when a sticky cell
      # was DESTROYED. A destroyed cell leaves its ink behind and the cell created in its place
      # paints only its own box — and between every pair of rows there is a grid_spacing strip that
      # NO cell ever paints (row_height_pixels is `grid_spacing + content`, while the cell is laid
      # out at `row_sizes[row] - grid_spacing`). Those strips are the clear's share of the layer, so
      # skipping the clear leaves the old rows' glyphs sitting in them: "each number with remnants of
      # other numbers under it" (Wolfgang, 2026-09-16), reproduced 4 times out of 4 by slamming the
      # scrollbar to the very top, where 137 of 341 sampled strip pixels held old ink.
      #
      # `any_changed` alone could not see it, because on such a jump NOTHING MOVES: every sticky cell
      # is destroyed and recreated, and a brand-new cell is laid out at its final position.
      #
      # This costs nothing in the common case. A scroll that recycles cells a row at a time leaves
      # most sticky cells holding a cached texture, so it is served by compute_sticky_blit_plans,
      # whose fast path clears the buffer anyway; we only land here when NO sticky cell has a texture,
      # which is precisely the frame that replaced all of them at once.
      if any_changed || cells_destroyed
        sv = @content_scroll_view
        sv.try(&.sticky_row_layer).try(&.mark_needs_clear_and_render)
        sv.try(&.sticky_col_layer).try(&.mark_needs_clear_and_render)
        sv.try(&.sticky_corner_layer).try(&.mark_needs_clear_and_render)
      end
      {% if flag?(:verify_bounds) %} verify_sticky_positions! {% end %}
    end

    # The per-axis context StickyMath.compound_axis places a merged span with - one for both passes (this one
    # and the blit plan), built once per pass. Y passes shifted: nil (physical-only) - pending its own arc.
    private def sticky_axis_views : {AxisView, AxisView}
      scroll = painted_scroll
      {AxisView.new(
        sizes: placed_col_sizes, cum: placed_col_cum, ruler_offset: ruler_col_width_pixels,
        sticky_extent: sticky_col_width_pixels + ruler_col_width_pixels,
        viewport_extent: bounds.width, scroll_q: scroll.x,
        shifted: @cached_col_shifted, park: OFFSCREEN_PARK),
       AxisView.new(
        sizes: placed_row_sizes, cum: placed_row_cum, ruler_offset: ruler_row_height_pixels,
        sticky_extent: sticky_row_height_pixels + ruler_row_height_pixels,
        viewport_extent: bounds.height, scroll_q: scroll.y,
        shifted: nil, park: OFFSCREEN_PARK)}
    end

    # Where a sticky cell belongs this frame, in the matrix's own space - the one rule both passes apply. A plain
    # cell is its line on each axis (painted_col / painted_row: pinned on its sticky axis, moved by painted_scroll
    # on the other), inset by the grid gap. A merged span on a SCROLLING axis is placed by
    # StickyMath.compound_axis (it pins at the band edge and shrinks as its constituents scroll under it - zero
    # when wholly out); on its sticky axis it keeps its laid-out start and extent.
    #
    # X KEEPS the box-level pin. The ink rule that replaces it on Y has no horizontal counterpart: `ink_region`
    # is consumed by the `vcentered_*` family, and cell text is hard left-aligned at padding (text.cr) with no
    # `hcentered_*` owner anywhere. Take this away without a replacement and a column header scrolls out with its
    # span - measured in the demo, field report 2026-09-06 image #49 ("1a"/"2a" scrolling out immediately).
    # A SPAN keeps compound_axis on Y too, and the reason is not the pin: `compound_axis` also computes the span's
    # extent under SHIFTED-OUT constituents (AxisView#shifted, the sticky-tail work), so a span's height is NOT
    # `cum[hi+1] - cum[lo]` once the grid compacts; giving Y the natural span was tried twice and backed out twice
    # (compound_shifted_visibility_spec's equivalence lock). KNOWN COST, unfixed: the clipping sits a group label
    # at the MIDDLE of the visible slice, and once the slice gets short the label can fall outside it (field
    # report 2026-09-06, image #45); the box pin engages at a threshold and shifts the label 1-3px while the ruler
    # beside it moves smoothly (field report 2026-09-06 (a)).
    private def sticky_cell_rect(key : Tuple(Int32, Int32), widget : Widget, col_view : AxisView, row_view : AxisView) : Rect
      row, col = key
      bounding = get_bounding_box(key)
      compound = bounding[0] != bounding[1]
      x, w = if !compound
               pos, pitch = painted_col(col)
               {pos, pitch - grid_spacing}
             elsif col < sticky_col_count
               {placed_col_start(col), widget.bounds.width}
             else
               pos, extent = Widgets::VirtualMatrix::StickyMath.compound_axis(col_view, bounding[0][1], bounding[1][1], placed_col_start(col))
               {pos, extent == 0.0 ? 0.0 : {extent - grid_spacing, 1.0}.max}
             end
      y, h = if !compound
               pos, pitch = painted_row(row)
               {pos, pitch - grid_spacing}
             elsif row < sticky_row_count
               {placed_row_start(row), widget.bounds.height}
             else
               pos, extent = Widgets::VirtualMatrix::StickyMath.compound_axis(row_view, bounding[0][0], bounding[1][0], placed_row_start(row))
               {pos, extent == 0.0 ? 0.0 : {extent - grid_spacing, 1.0}.max}
             end
      Rect.new(x, y, w, h)
    end
  end
end
