module CrymbleUI
  class VirtualMatrix < Widget
    # Check if sticky cells can use the blit-plan fast path.
    # Returns false on first frame or if any non-compound sticky cell lacks a cached texture.
    # Compound cells and rulers are handled via blit_plan_render_widgets (rendered after blits).
    private def sticky_cells_can_use_blit_plan? : Bool
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return false if sticky_rows == 0 && sticky_cols == 0

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return false unless col_sizes && row_sizes

      cells_with_backend = 0
      @active_cells.each do |key, widget|
        row, col = key
        next unless row < sticky_rows || col < sticky_cols

        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]
        if is_compound
          is_sticky_row = row < sticky_rows
          is_sticky_col = col < sticky_cols
          # Compound cells that resize on scroll are rendered via blit_plan_render_widgets.
          # They need widget_backend to be blitted when they only moved (not resized).
          if !is_sticky_col || !is_sticky_row
            cells_with_backend += 1 if widget.widget_backend
            next
          end
        end

        # Non-compound cells without widget_backend are freshly created (e.g. bounds grew and a new
        # sticky cell became visible), OR with a backend but needing a fresh render (size changed / stale
        # content). The fast path still runs — compute_sticky_blit_plans routes BOTH to blit_plan_render_
        # widgets (rendered normally after the blits), so we don't bail here. This is what enables the
        # blit-plan during a resize (the resized line's header needs_render; the rest just moved → blit).
        cells_with_backend += 1 if widget.widget_backend && !widget.needs_render?
      end
      cells_with_backend > 0  # Need at least one cell with cached texture
    end

    # Compute blit plans for sticky layers.
    # Called AFTER reposition_sticky_cells (which handles compound cell sizing).
    # Non-compound sticky cells: blit cached widget_backend at current bounds position (O(blit)).
    # Compound cells + rulers: added to blit_plan_render_widgets for normal rendering.
    # This overrides the mark_needs_clear_and_render set by reposition_sticky_cells,
    # replacing full re-render with the much cheaper blit-plan fast path.
    private def compute_sticky_blit_plans
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return if sticky_rows == 0 && sticky_cols == 0
      return if @active_cells.empty?

      sv = @content_scroll_view
      return unless sv

      sticky_row_layer = sv.sticky_row_layer
      sticky_col_layer = sv.sticky_col_layer
      sticky_corner_layer = sv.sticky_corner_layer

      vm_abs = absolute_bounds

      col_sizes = @cached_col_sizes
      row_sizes = @cached_row_sizes
      return unless col_sizes && row_sizes
      col_cum = @cached_col_physical_cum
      row_cum = @cached_row_physical_cum
      ruler_x_offset = ruler_col_width_pixels
      ruler_y_offset = ruler_row_height_pixels

      row_entries = [] of BlitEntry
      col_entries = [] of BlitEntry
      corner_entries = [] of BlitEntry

      # Widgets needing normal rendering after blit-plan:
      # rulers (CachePolicy::Never) + compound cells that resize on scroll
      row_render = [] of Widget
      col_render = [] of Widget
      corner_render = [] of Widget

      # A sticky layer is "active" (needs a clear + re-blit) only if a cell on it actually
      # moved/resized/(re)rendered, or (for a resize) its axis's ruler changed. On a column resize only
      # the col-header layer is active — the row-header layer + corner keep their pixels
      # (correct-by-construction). Same for a single-axis scroll. Rulers are added to render_list
      # per-active-layer at the end (an active layer's clear wipes its ruler, so it must re-render).
      row_active = false
      col_active = false
      corner_active = false

      @active_cells.each do |key, widget|
        row, col = key
        is_sticky_row = row < sticky_rows
        is_sticky_col = col < sticky_cols
        next unless is_sticky_row || is_sticky_col

        wb = widget.widget_backend

        # Determine target layer
        if is_sticky_row && is_sticky_col
          layer = sticky_corner_layer
          target = corner_entries
          render_list = corner_render
        elsif is_sticky_row
          layer = sticky_row_layer
          target = row_entries
          render_list = row_render
        else
          layer = sticky_col_layer
          target = col_entries
          render_list = col_render
        end
        next unless layer

        # Check if compound cell needs full re-render or can be blitted
        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]
        if is_compound && (!is_sticky_col || !is_sticky_row)
          # Compound cell that may resize on scroll. Always reposition (sets correct
          # bounds including OFFSCREEN_PARK when off-screen). Then decide render vs blit.
          reposition_compound_in_blit_plan(widget, key, bounding,
            is_sticky_row, is_sticky_col,
            col_sizes, row_sizes, col_cum, row_cum,
            ruler_x_offset, ruler_y_offset)
          # Compound cells resize/reposition on scroll+resize — conservatively activate their layer.
          if is_sticky_row && is_sticky_col
            corner_active = true
          elsif is_sticky_row
            row_active = true
          else
            col_active = true
          end
          if wb && !widget.needs_render? && widget.has_valid_primitive_cache?
            # Compound cell only moved — blit cached texture
            dest_x = (vm_abs.x + widget.bounds.x - layer.bounds.x).to_i
            dest_y = (vm_abs.y + widget.bounds.y - layer.bounds.y).to_i
            target << BlitEntry.new(wb, dest_x, dest_y)
          else
            # Resized, needs render, or newly created (no wb) — render normally.
            # Without this, new compound cells appear blank until the next frame
            # (visible during scrollbar thumb drag where cell update is deferred).
            render_list << widget unless widget.bounds.x < -100.0  # Skip off-screen
          end
          next
        end

        # Non-compound: always recompute the scroll-adjusted position
        # BEFORE deciding blit vs render. If a newly-visible cell (wb=NIL)
        # carried a stale position from a prior scroll state, render_single_widget
        # would otherwise paint it off-screen — the "newly-visible sticky cell renders blank" bug.
        # Screen-space position = content position − live scroll. (The removed
        # @viewport_col_positions/@viewport_row_positions branch reused the content layer's CACHED
        # StickyMath positions, which drop the sub-column scroll → froze sticky cells for any scroll
        # smaller than one column. Sticky layers aren't viewport_cache, so they carry the scroll.)
        if !is_sticky_col
          content_x = (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
          new_x = ruler_x_offset + content_x - scroll_offset.x.to_i.to_f64
        else
          new_x = ruler_x_offset + (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
        end

        if !is_sticky_row
          content_y = (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
          new_y = ruler_y_offset + content_y - scroll_offset.y.to_i.to_f64
        else
          new_y = ruler_y_offset + (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)
        end

        # Non-compound cells keep their column/row size (during a RESIZE the resized line's headers
        # genuinely change size — scroll never does, so this is a no-op there). A size change means the
        # cached texture is the wrong size → invalidate so it re-renders fresh below.
        new_w = (col_sizes[col] - grid_spacing).to_f64
        new_h = (row_sizes[row] - grid_spacing).to_f64
        size_changed = widget.bounds.width != new_w || widget.bounds.height != new_h
        moved = widget.bounds.x != new_x || widget.bounds.y != new_y
        if moved || size_changed
          widget.bounds = Rect.new(new_x, new_y, new_w, new_h)
        end
        widget.invalidate_primitive_cache if size_changed

        # A cell that will re-render (no cached texture, size changed → wrong-size texture, or stale
        # content) OR that MOVED means its layer must clear + repaint this frame. A cell that did NEITHER
        # contributes nothing — its pixels are already correct, so it must not activate (wake) its layer.
        render_fresh = size_changed || widget.needs_render? || !widget.has_valid_primitive_cache?
        if wb.nil? || render_fresh || moved
          if is_sticky_row && is_sticky_col
            corner_active = true
          elsif is_sticky_row
            row_active = true
          else
            col_active = true
          end
        end

        # No cached texture yet (newly created after bounds grow / viewport shift) → render at the freshly
        # set bounds; cull only if truly off-screen horizontally.
        unless wb
          render_list << widget unless widget.bounds.x < -100.0
          next
        end

        # Size changed (cached texture is the WRONG size) or stale content → render normally. This is what
        # lets the blit-plan run during a RESIZE: only the resized line's header re-renders; every other
        # sticky cell merely MOVED → blit its cached texture at the new position below.
        if render_fresh
          render_list << widget unless widget.bounds.x < -100.0
          next
        end

        dest_x = (vm_abs.x + new_x - layer.bounds.x).to_i
        dest_y = (vm_abs.y + new_y - layer.bounds.y).to_i
        target << BlitEntry.new(wb, dest_x, dest_y)
      end

      # A resize always changes the resized axis's ruler (labels reposition to the new sizes) even if no
      # header cell happens to move → activate that axis's layer so its ruler re-renders. The corner
      # labels only change when a STICKY line is resized. (Scroll needs no such rule: its cells move, and
      # a moved cell already activated the layer above.)
      row_active ||= resize_axis.col?
      col_active ||= resize_axis.row?
      corner_active ||= (resize_axis.col? && resize_index < sticky_cols) || (resize_axis.row? && resize_index < sticky_rows)

      # Set blit plans ONLY on ACTIVE layers (triggers the fast path in render_layer: clear the buffer,
      # blit the moved data cells, then render the rulers + size-changed cells). An INACTIVE layer keeps
      # its pixels untouched — the point of the per-layer gate. An active layer's clear wipes its ruler,
      # so the ruler is added to render_list here (it must re-render even if its own content is unchanged).
      if sticky_row_layer && row_active
        row_render << @col_ruler_widget.not_nil! if @col_ruler_widget && show_rulers
        sticky_row_layer.blit_plan = row_entries
        sticky_row_layer.blit_plan_render_widgets = row_render if row_render.any?
        sticky_row_layer.mark_needs_full_render
      end
      if sticky_col_layer && col_active
        col_render << @row_ruler_widget.not_nil! if @row_ruler_widget && show_rulers
        sticky_col_layer.blit_plan = col_entries
        sticky_col_layer.blit_plan_render_widgets = col_render if col_render.any?
        sticky_col_layer.mark_needs_full_render
      end
      if sticky_corner_layer && corner_active
        corner_render << @corner_ruler_widget.not_nil! if @corner_ruler_widget && show_rulers
        corner_render << @corner_row_strip_widget.not_nil! if @corner_row_strip_widget && show_rulers
        sticky_corner_layer.blit_plan = corner_entries
        sticky_corner_layer.blit_plan_render_widgets = corner_render if corner_render.any?
        sticky_corner_layer.mark_needs_full_render
      end

      {% if flag?(:cache_validation) %}
        validate_sticky_cell_bounds_invariant(col_sizes, row_sizes, col_cum, row_cum,
          ruler_x_offset, ruler_y_offset, sticky_rows, sticky_cols)
      {% end %}
      {% if flag?(:verify_bounds) %} verify_sticky_positions! {% end %}
    end

    # Dev assertion (build with -Dverify_bounds, e.g. in CI). Every non-compound sticky cell's bounds
    # must equal the screen-space position derived INDEPENDENTLY from its index + the LIVE scroll:
    # sticky axis → pinned at the content position; scrolling axis → content position − scroll. This
    # is the exact invariant the "sticky cell positioned from a stale cache" bug (the column-widen
    # ruler/data desync, 2026-05-30) violated. Unlike the cache-validation dual pipeline, it does NOT
    # read the same cached positions the renderer used, so it cannot "agree on garbage"; it fires the
    # frame the bounds go wrong. Cheap (a few comparisons over the handful of sticky header cells).
    {% if flag?(:verify_bounds) %}
      private def verify_sticky_positions!
        srows = sticky_row_count
        scols = sticky_col_count
        return if srows == 0 && scols == 0
        cc = @cached_col_physical_cum
        rc = @cached_row_physical_cum
        return unless cc && rc
        rx = ruler_col_width_pixels
        ry = ruler_row_height_pixels
        sx = scroll_offset.x.to_i.to_f64
        sy = scroll_offset.y.to_i.to_f64
        @active_cells.each do |key, w|
          row, col = key
          next unless row < srows || col < scols
          bb = get_bounding_box(key)
          next if bb[0] != bb[1] # compound cells size themselves; checked elsewhere
          exp_x = col < scols ? rx + cc[col].to_f64 : rx + cc[col].to_f64 - sx
          exp_y = row < srows ? ry + rc[row].to_f64 : ry + rc[row].to_f64 - sy
          if (w.bounds.x - exp_x).abs > 1.0 || (w.bounds.y - exp_y).abs > 1.0
            STDERR.puts "[VERIFY_BOUNDS] matrix##{@id}: sticky cell #{key} at " \
                        "(#{w.bounds.x.round(1)},#{w.bounds.y.round(1)}) expected " \
                        "(#{exp_x.round(1)},#{exp_y.round(1)}) scroll=(#{scroll_offset.x.round(1)},#{scroll_offset.y.round(1)})"
          end
        end
      end
    {% end %}

    # Structural invariant: every active cell's widget.bounds must match
    # the canonical position derived from its (row,col) index and current
    # scroll_offset. Violations of this invariant are the "stale bounds"
    # class of rendering bugs (widget paints at the wrong position, often
    # off-screen → appears blank). cv's dual pipeline can't detect them —
    # both paths read widget.bounds, so both render at the same wrong
    # position and "agree" on garbage. This check catches the bug at its
    # source, one frame after the offending layout runs, with zero false
    # positives and identical behavior in headless and real GUI.
    private def validate_sticky_cell_bounds_invariant(
        col_sizes : Array(Int32), row_sizes : Array(Int32),
        col_cum : Array(Int32)?, row_cum : Array(Int32)?,
        ruler_x_offset : Float64, ruler_y_offset : Float64,
        sticky_rows : Int32, sticky_cols : Int32)
      return unless col_cum && row_cum
      scroll_x_i = scroll_offset.x.to_i.to_f64
      scroll_y_i = scroll_offset.y.to_i.to_f64
      violations = [] of String
      @active_cells.each do |key, widget|
        row, col = key
        # Skip cells outside the sticky corridor (they live on content_layer,
        # repositioned by a different code path).
        next unless row < sticky_rows || col < sticky_cols
        # Compound cells use custom sizing logic; verify separately.
        bb = get_bounding_box(key)
        next if bb[0] != bb[1]

        is_sticky_col = col < sticky_cols
        is_sticky_row = row < sticky_rows
        expected_x = if is_sticky_col
                       ruler_x_offset + col_cum[col].to_f64
                     else
                       ruler_x_offset + col_cum[col].to_f64 - scroll_x_i
                     end
        expected_y = if is_sticky_row
                       ruler_y_offset + row_cum[row].to_f64
                     else
                       ruler_y_offset + row_cum[row].to_f64 - scroll_y_i
                     end
        if (widget.bounds.x - expected_x).abs > 1.0 || (widget.bounds.y - expected_y).abs > 1.0
          violations << "key=(#{row},#{col}) expected=(#{expected_x.round(1)},#{expected_y.round(1)}) actual=(#{widget.bounds.x.round(1)},#{widget.bounds.y.round(1)}) wb=#{widget.widget_backend ? "yes" : "NIL"}"
        end
      end

      # Log every frame (trace) plus register a cv failure when violations
      # exist — the latter makes the failure visible to test assertions.
      File.open("/tmp/crymble_cv_trace.log", "a") do |f|
        f.puts "--- compute_sticky_blit_plans frame=#{CacheValidation.frame_counter} scroll=(#{scroll_offset.x.round(1)},#{scroll_offset.y.round(1)}) active=#{@active_cells.size} violations=#{violations.size}"
        violations.each { |v| f.puts "    !!! BOUNDS-STALE #{v}" }
      end
      if violations.any?
        CacheValidation.record_failure(
          CacheValidation::CacheLevel::LayoutCache,
          "virtual_matrix:#{@id || "?"}",
          violations.size,
          @active_cells.size,
          {0, 0, 0_u32, 0_u32}
        )
      end
    end

    # Reposition a single compound cell within the blit-plan path.
    # Same logic as reposition_sticky_cells but for one cell only.
    # Updates widget bounds and calls invalidate_primitive_cache if size changed.
    private def reposition_compound_in_blit_plan(
        widget : Widget, key : Tuple(Int32, Int32),
        bounding : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32)),
        is_sticky_row : Bool, is_sticky_col : Bool,
        col_sizes : Array(Int32), row_sizes : Array(Int32),
        col_cum : Array(Int32)?, row_cum : Array(Int32)?,
        ruler_x_offset : Float64, ruler_y_offset : Float64)
      row, col = key
      true_x = ruler_x_offset + (col_cum ? col_cum[col].to_f64 : (0...col).sum { |c| col_sizes[c] }.to_f64)
      true_y = ruler_y_offset + (row_cum ? row_cum[row].to_f64 : (0...row).sum { |r| row_sizes[r] }.to_f64)

      compound_w = 0.0
      compound_h = 0.0
      new_x = true_x
      new_y = true_y

      if !is_sticky_col
        bb_c1 = bounding[0][1]
        bb_c2 = bounding[1][1]
        min_screen_x = Float64::MAX
        max_screen_x = -Float64::MAX
        sticky_col_w = sticky_col_width_pixels + ruler_col_width_pixels
        viewport_right = self.bounds.width
        visible_col_count = 0
        single_col_x = 0.0
        single_col_size = 0.0
        (bb_c1..bb_c2).each do |ci|
          next if ci >= col_sizes.size
          true_ci_x = ruler_x_offset + (col_cum ? col_cum[ci].to_f64 : (0...ci).sum { |c| col_sizes[c] }.to_f64)
          unclamped_scr_x = true_ci_x - scroll_offset.x.to_i.to_f64
          col_right = unclamped_scr_x + col_sizes[ci].to_f64
          next if col_right <= sticky_col_w
          next if unclamped_scr_x >= viewport_right
          visible_col_count += 1
          single_col_x = unclamped_scr_x
          single_col_size = col_sizes[ci].to_f64
          scr_x = {unclamped_scr_x, sticky_col_w}.max
          capped_right = {col_right, viewport_right}.min
          min_screen_x = {min_screen_x, scr_x}.min
          max_screen_x = {max_screen_x, capped_right}.max
        end
        if min_screen_x < Float64::MAX
          if visible_col_count > 1
            new_x = min_screen_x
            compound_w = max_screen_x - min_screen_x
          else
            new_x = single_col_x
            compound_w = single_col_size
          end
        else
          # All constituent columns outside viewport. Distinguish scrolled-past
          # (behind sticky header) from not-yet-visible (right of viewport).
          # Without this, row-0 compound headers whose cols are initially right-of-
          # viewport get parked at OFFSCREEN_PARK with w=0 instead of their true
          # off-screen content position — so returning from scroll-right leaves
          # them parked instead of restoring their original layout.
          last_col_right = ruler_x_offset + (col_cum ? col_cum[bb_c2 + 1].to_f64 : (0..bb_c2).sum { |c| col_sizes[c] }.to_f64)
          if last_col_right - scroll_offset.x.to_i.to_f64 <= sticky_col_w
            new_x = OFFSCREEN_PARK
            compound_w = 0.0
          else
            new_x = true_x
            compound_w = (bb_c1..bb_c2).sum { |ci| col_sizes[ci].to_f64 }
          end
        end
      end

      if !is_sticky_row
        bb_r1 = bounding[0][0]
        bb_r2 = bounding[1][0]
        min_screen_y = Float64::MAX
        max_screen_y = -Float64::MAX
        sticky_row_h = sticky_row_height_pixels + ruler_row_height_pixels
        viewport_bottom = self.bounds.height
        visible_row_count = 0
        single_row_y = 0.0
        single_row_size = 0.0
        (bb_r1..bb_r2).each do |ri|
          next if ri >= row_sizes.size
          true_ri_y = ruler_y_offset + (row_cum ? row_cum[ri].to_f64 : (0...ri).sum { |r| row_sizes[r] }.to_f64)
          unclamped_scr_y = true_ri_y - scroll_offset.y.to_i.to_f64
          row_bottom = unclamped_scr_y + row_sizes[ri].to_f64
          next if row_bottom <= sticky_row_h
          next if unclamped_scr_y >= viewport_bottom
          visible_row_count += 1
          single_row_y = unclamped_scr_y
          single_row_size = row_sizes[ri].to_f64
          scr_y = {unclamped_scr_y, sticky_row_h}.max
          capped_bottom = {row_bottom, viewport_bottom}.min
          min_screen_y = {min_screen_y, scr_y}.min
          max_screen_y = {max_screen_y, capped_bottom}.max
        end
        if min_screen_y < Float64::MAX
          if visible_row_count > 1
            new_y = min_screen_y
            compound_h = max_screen_y - min_screen_y
          else
            new_y = single_row_y
            compound_h = single_row_size
          end
        else
          # Mirror of the column path above for rows (row-scroll case).
          last_row_bottom = ruler_y_offset + (row_cum ? row_cum[bb_r2 + 1].to_f64 : (0..bb_r2).sum { |r| row_sizes[r] }.to_f64)
          if last_row_bottom - scroll_offset.y.to_i.to_f64 <= sticky_row_h
            new_y = OFFSCREEN_PARK
            compound_h = 0.0
          else
            new_y = true_y
            compound_h = (bb_r1..bb_r2).sum { |ri| row_sizes[ri].to_f64 }
          end
        end
      end

      new_w = is_sticky_col ? widget.bounds.width : (compound_w == 0.0 ? 0.0 : {compound_w - grid_spacing, 1.0}.max)
      new_h = is_sticky_row ? widget.bounds.height : (compound_h == 0.0 ? 0.0 : {compound_h - grid_spacing, 1.0}.max)

      if widget.bounds.x != new_x || widget.bounds.y != new_y || widget.bounds.width != new_w || widget.bounds.height != new_h
        size_changed = widget.bounds.width != new_w || widget.bounds.height != new_h
        cell_constraints = BoxConstraints.tight(Size.new(new_w, new_h))
        widget.layout(cell_constraints, Vec2.new(new_x, new_y))
        widget.invalidate_primitive_cache if size_changed
      end
    end
  end
end
