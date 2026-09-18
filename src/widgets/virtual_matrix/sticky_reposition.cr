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
    # - sticky_row cells: x = true_x - scroll_offset.x, y = true_y (fixed vertically)
    # - sticky_col cells: x = true_x (fixed horizontally), y = true_y - scroll_offset.y
    # - sticky_corner cells: x = true_x, y = true_y (fixed both ways)
    # - content cells: not touched (viewport_cache handles scroll)
    private def reposition_sticky_cells(cells_destroyed : Bool = false)
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return if sticky_rows == 0 && sticky_cols == 0
      return if @active_cells.empty?

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return unless col_sizes && row_sizes

      col_cum = @cached_col_physical_cum
      row_cum = @cached_row_physical_cum

      # ONE content-space scroll quantization per axis for the whole pass. The park
      # predicates and the per-constituent visibility gates below are the same
      # expression on this value — sharing the local (here and in the blit-plan
      # mirror) makes a mixed quantization basis, where reposition and the blit
      # plan disagree about whether a header is parked, structurally impossible.
      scroll_x_i = scroll_offset.x.to_i.to_f64
      scroll_y_i = scroll_offset.y.to_i.to_f64

      # Per-axis compound-disposition context, built ONCE per pass — the same
      # StickyMath.compound_axis serves the blit-plan fast path, so the two
      # passes cannot disagree on a compound header's extent or park state.
      # Y passes shifted: nil (physical-only) — pending its own arc.
      col_view = AxisView.new(
        sizes: col_sizes, cum: col_cum, ruler_offset: ruler_col_width_pixels,
        sticky_extent: sticky_col_width_pixels + ruler_col_width_pixels,
        viewport_extent: bounds.width, scroll_q: scroll_x_i,
        shifted: @cached_col_shifted, park: OFFSCREEN_PARK)
      row_view = AxisView.new(
        sizes: row_sizes, cum: row_cum, ruler_offset: ruler_row_height_pixels,
        sticky_extent: sticky_row_height_pixels + ruler_row_height_pixels,
        viewport_extent: bounds.height, scroll_q: scroll_y_i,
        shifted: nil, park: OFFSCREEN_PARK)

      any_changed = false

      @active_cells.each do |key, widget|
        row, col = key
        is_sticky_row = row < sticky_rows
        is_sticky_col = col < sticky_cols
        next unless is_sticky_row || is_sticky_col

        # Grid-order position (for sticky dimensions that don't scroll)
        # Ruler offsets shift all data cells right/down within the sticky layers
        ruler_x_offset = ruler_col_width_pixels
        ruler_y_offset = ruler_row_height_pixels
        true_x = ruler_x_offset + (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
        true_y = ruler_y_offset + (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)

        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]
        # The layout pass's half of CRYMBLE_CARET_LOG. Without it, "no [caret] line this frame" is
        # ambiguous between "no frame ran" and "the OTHER pass ran" — and the two have opposite
        # fixes. The blit-path half lives in blit_plan.cr; the passes run either/or per frame.
        log_caret_frame(key, "LAYOUT", widget)
        # Compound cells derive BOTH screen-space position AND visible extent per
        # axis from StickyMath.compound_axis (shared with the blit-plan fast path):
        # (a) correct screen-space position (not content-space)
        # (b) extent shrinks as constituents shift out (prevents sibling overlap)
        #
        # KNOWN COST of (b), unfixed: the clipping means a group label sits at the MIDDLE of the
        # visible slice rather than at the leading edge like everything else naming the same
        # region, and once the slice gets short the label can fall outside it and not be drawn at
        # all (field report 2026-09-06, image #45: "a" absent, then appearing after one line of
        # scroll). Replacing this with the shared ink rule was tried three times and backed out
        # three times — see the compound branch below for the measured reason.
        compound_w = 0.0
        compound_h = 0.0

        if !is_sticky_col
          if is_compound
            # X KEEPS the box-level pin. The ink rule that replaces it on Y has no horizontal
            # counterpart: `ink_region` is consumed by the `vcentered_*` family, and cell text
            # is hard left-aligned at padding (text.cr) with no `hcentered_*` owner anywhere. Take
            # this away without a replacement and a column header scrolls out with its span —
            # measured in the demo, field report 2026-09-06 image #49 ("1a"/"2a" scrolling out
            # immediately). Asymmetric because the two axes genuinely are.
            new_x, compound_w = Widgets::VirtualMatrix::StickyMath.compound_axis(
              col_view, bounding[0][1], bounding[1][1], true_x)
          else
            # Non-compound: screen-space position = content position − live scroll. Sticky layers
            # are NOT viewport_cache (see this file's header), so the cell bounds must carry the
            # scroll themselves. Using the cached @viewport_col_positions here was a bug: those
            # StickyMath positions are recomputed only when a whole column crosses the boundary, so
            # they dropped the sub-column scroll and froze the cells whenever scroll < one column.
            content_x = (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
            new_x = ruler_x_offset + content_x - scroll_x_i
          end
        else
          new_x = true_x
        end

        if !is_sticky_row
          if is_compound
            # A SPAN keeps StickyMath.compound_axis on BOTH axes, and the reason is not the pin.
            # Giving Y the natural span was tried twice and backed out twice; the second attempt
            # broke compound_shifted_visibility_spec's equivalence lock, which is the measured
            # reason: `compound_axis` also computes the span's extent under SHIFTED-OUT
            # constituents (AxisView#shifted, the sticky-tail work), so a span's height is NOT
            # `cum[hi+1] - cum[lo]` once the grid compacts. A naive sum makes the two passes
            # disagree, and a divergence between them is a visible jump when the frame type flips.
            #
            # The cost of keeping it is field report 2026-09-06 (a): the box pin engages at a
            # threshold and shifts the label 1-3px while the ruler beside it moves smoothly.
            # Fixing that means teaching the shared rule about shifted constituents, not deleting
            # the function that already knows.
            new_y, compound_h = Widgets::VirtualMatrix::StickyMath.compound_axis(
              row_view, bounding[0][0], bounding[1][0], true_y)
          else
            # Non-compound: screen-space position = content position − live scroll (see the X path
            # above for why the cached @viewport_row_positions branch was a freeze bug).
            content_y = (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
            new_y = ruler_y_offset + content_y - scroll_y_i
          end
        else
          new_y = true_y
        end

        # Compute target size: compound cells use visible size, others keep current
        # Allow zero size for cells fully behind sticky header (prevents overlap assertions)
        if is_compound
          new_w = is_sticky_col ? widget.bounds.width : (compound_w == 0.0 ? 0.0 : {compound_w - grid_spacing, 1.0}.max)
          new_h = is_sticky_row ? widget.bounds.height : (compound_h == 0.0 ? 0.0 : {compound_h - grid_spacing, 1.0}.max)
        else
          # Use fresh sizes from col_sizes/row_sizes — during resize drag,
          # widget.bounds still has stale width from initial layout
          new_w = (col_sizes[col] - grid_spacing).to_f64
          new_h = (row_sizes[row] - grid_spacing).to_f64
        end

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
  end
end
