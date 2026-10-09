module CrymbleUI
  class VirtualMatrix < Widget
    # Why the CURSOR cell looks the way it does on a given frame, on demand: CRYMBLE_CARET_LOG=1.
    # Read once (this sits inside the per-cell loop of every frame). One line per frame, cursor cell
    # only, recording the blit-vs-render decision ALONGSIDE the caret state and the scroll — the
    # pair a "caret still visible after leaving" report needs, since a caret that is gone from the
    # widget but present in a BLITTED texture looks identical on screen and identical to every
    # state-level assertion.
    CARET_LOG = !ENV["CRYMBLE_CARET_LOG"]?.nil?

    private def log_caret_frame(key, decision : String, widget : Widget) : Nil
      return unless CARET_LOG
      return unless key == cursor_rc
      STDERR.puts "[caret] #{key} #{decision.ljust(16)} caret=#{cursor_cell_draws_edit_caret?} " \
                  "needs_render=#{widget.needs_render?} cache=#{widget.has_valid_primitive_cache?} " \
                  "scroll_y=#{scroll_offset.y.round(1)} y=#{widget.bounds.y.round(1)} " \
                  "h=#{widget.bounds.height.round(1)}"
    end
    # Check if sticky cells can use the blit-plan fast path.
    # Returns false on first frame or if any non-compound sticky cell lacks a cached texture.
    # Compound cells and rulers are handled via blit_plan_render_widgets (rendered after blits).
    private def sticky_cells_can_use_blit_plan? : Bool
      sticky_rows = sticky_row_count
      sticky_cols = sticky_col_count
      return false if sticky_rows == 0 && sticky_cols == 0

      return false unless @cached_col_sizes && @cached_row_sizes

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
        # Counted whether or not it needs render. The comment above says why that is safe: the
        # fast path routes a dirty cell to blit_plan_render_widgets and renders it normally. But
        # excluding dirty cells here made PATH SELECTION depend on how many cells happen to be
        # dirty — so anything that legitimately dirties every visible sticky cell on a frame (the
        # ink rule does, when their band moves) silently diverted that frame to the reposition
        # path, which marks layers rather than repainting, and the cell was left waiting for paint.
        # That is caret_leaves_with_editor_spec: measured with CRYMBLE_CARET_LOG, the closing frame
        # went from "RENDER fresh" to a bare "LAYOUT" with cache=false and nothing after it.
        cells_with_backend += 1 if widget.widget_backend
      end
      cells_with_backend > 0  # Need at least one cell with cached texture
    end

    # Compute blit plans for sticky layers — the FAST-PATH sibling of
    # reposition_sticky_cells: the two run EITHER/OR per frame (update_visible_cells
    # picks one on sticky_cells_can_use_blit_plan?), so compound positioning MUST
    # agree between them — both delegate to StickyMath.compound_axis.
    # Non-compound sticky cells: blit cached widget_backend at current bounds position (O(blit)).
    # Compound cells + rulers: added to blit_plan_render_widgets for normal rendering.
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
      # Each band's origin in content space (its layer's content rect) - once, not per cell: a cell's blit
      # destination is content position minus it, like every render into a layer buffer
      corner_origin = sticky_corner_layer.try(&.content_rect)
      row_origin = sticky_row_layer.try(&.content_rect)
      col_origin = sticky_col_layer.try(&.content_rect)

      return unless @cached_col_sizes && @cached_row_sizes
      # The SAME contexts and the same placement rule (sticky_cell_rect) as the layout pass - the passes run
      # either/or per frame and cannot disagree.
      col_view, row_view = sticky_axis_views

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
          layer, layer_origin = sticky_corner_layer, corner_origin
          target = corner_entries
          render_list = corner_render
        elsif is_sticky_row
          layer, layer_origin = sticky_row_layer, row_origin
          target = row_entries
          render_list = row_render
        else
          layer, layer_origin = sticky_col_layer, col_origin
          target = col_entries
          render_list = col_render
        end
        next unless layer && layer_origin

        # Check if compound cell needs full re-render or can be blitted
        bounding = get_bounding_box(key)
        is_compound = bounding[0] != bounding[1]
        target_rect = sticky_cell_rect(key, widget, col_view, row_view)
        if is_compound && (!is_sticky_col || !is_sticky_row)
          # Compound cell that may resize on scroll. Always reposition (sets correct
          # bounds including OFFSCREEN_PARK when off-screen). Then decide render vs blit.
          place_compound_in_blit_plan(widget, target_rect)
          # Compound cells resize/reposition on scroll+resize — conservatively activate their layer.
          if is_sticky_row && is_sticky_col
            corner_active = true
          elsif is_sticky_row
            row_active = true
          else
            col_active = true
          end
          if wb && !widget.needs_render? && widget.has_valid_primitive_cache?
            # Compound cell only moved — blit cached texture. Cell-texture→layer dests
            # floor the difference (PixelSnap.origin) so they land on the SAME layer
            # pixel the render path stamps (round_to_layer_pixels) — truncation
            # diverged at negative fractional coords.
            dest_x = PixelSnap.origin(vm_abs.x + widget.bounds.x - layer_origin.x)
            dest_y = PixelSnap.origin(vm_abs.y + widget.bounds.y - layer_origin.y)
            log_caret_frame(key, "BLIT compound", widget)
            target << BlitEntry.new(widget, widget.backend_generation, dest_x, dest_y)
          else
            # Resized, needs render, or newly created (no wb) — render normally.
            # Without this, new compound cells appear blank until the next frame
            # (visible during scrollbar thumb drag where cell update is deferred).
            log_caret_frame(key, "RENDER compound", widget)
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
        # Non-compound cells keep their column/row size (during a RESIZE the resized line's headers
        # genuinely change size — scroll never does, so this is a no-op there). A size change means the
        # cached texture is the wrong size → invalidate so it re-renders fresh below.
        new_x, new_y, new_w, new_h = target_rect.x, target_rect.y, target_rect.width, target_rect.height
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
        {% if flag?(:probe) %}
          # Per-cell, only when something actually changed, so an idle app logs nothing.
          if (moved || size_changed) && CrymbleUI::BlitProbe.on?
            CrymbleUI::BlitProbe.emit(
              "blit cell #{row},#{col} sticky=#{is_sticky_row ? "row" : ""}#{is_sticky_col ? "col" : ""} " \
              "moved=#{moved} size_changed=#{size_changed} render_fresh=#{render_fresh} " \
              "cached_texture=#{!wb.nil?} to=(#{new_x.round(1)},#{new_y.round(1)},#{new_w.round(1)}x#{new_h.round(1)})")
          end
        {% end %}
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
          log_caret_frame(key, "RENDER no-tex", widget)
          render_list << widget unless widget.bounds.x < -100.0
          next
        end

        # Size changed (cached texture is the WRONG size) or stale content → render normally. This is what
        # lets the blit-plan run during a RESIZE: only the resized line's header re-renders; every other
        # sticky cell merely MOVED → blit its cached texture at the new position below.
        if render_fresh
          log_caret_frame(key, "RENDER fresh", widget)
          render_list << widget unless widget.bounds.x < -100.0
          next
        end

        dest_x = PixelSnap.origin(vm_abs.x + new_x - layer_origin.x)
        dest_y = PixelSnap.origin(vm_abs.y + new_y - layer_origin.y)
        log_caret_frame(key, "BLIT", widget)
        {% if flag?(:probe) %}
          # render_layer's fast path does a FULL-TEXTURE blit: backend.blit(entry.widget.widget_backend, ...).
          # So the painted extent is the SOURCE TEXTURE's size, not the cell's box. If a cached texture is
          # smaller than the box it now occupies, the remainder keeps whatever the layer clear left -
          # which is what a strip of bare layer background inside a cell's own box looks like.
          if CrymbleUI::BlitProbe.on?
            sw = wb.width
            sh = wb.height
            bw = widget.bounds.width.round(1)
            bh = widget.bounds.height.round(1)
            mismatch = (sw - bw).abs > 1.0 || (sh - bh).abs > 1.0
            if mismatch
              CrymbleUI::BlitProbe.emit(
                "blit SIZE MISMATCH cell #{row},#{col} texture=#{sw}x#{sh} box=#{bw}x#{bh} " \
                "dest=(#{dest_x},#{dest_y}) render_fresh=#{render_fresh} moved=#{moved}")
            end
          end
        {% end %}
        target << BlitEntry.new(widget, widget.backend_generation, dest_x, dest_y)
      end

      # A resize always changes the resized axis's ruler (labels reposition to the new sizes) even if no
      # header cell happens to move → activate that axis's layer so its ruler re-renders. The corner
      # labels only change when a STICKY line is resized. (Scroll needs no such rule: its cells move, and
      # a moved cell already activated the layer above.)
      row_active ||= resize_axis.col?
      col_active ||= resize_axis.row?
      corner_active ||= (resize_axis.col? && resize_index < sticky_cols) || (resize_axis.row? && resize_index < sticky_rows)

      {% if flag?(:probe) %}
        # The verdict. A cell that moved while its layer stayed INACTIVE is candidate (i): the
        # activation test missed a case, and nothing will clear what it left behind.
        if CrymbleUI::BlitProbe.on? && (row_active || col_active || corner_active ||
                                        !row_entries.empty? || !col_entries.empty? || !corner_entries.empty?)
          CrymbleUI::BlitProbe.emit(
            "blit actives row=#{row_active} col=#{col_active} corner=#{corner_active} " \
            "entries row=#{row_entries.size} col=#{col_entries.size} corner=#{corner_entries.size} " \
            "render row=#{row_render.size} col=#{col_render.size} corner=#{corner_render.size} " \
            "scroll=#{scroll_offset.x.round(1)},#{scroll_offset.y.round(1)}")
        end
      {% end %}

      # Set blit plans ONLY on ACTIVE layers (triggers the fast path in render_layer: clear the buffer,
      # blit the moved data cells, then render the rulers + size-changed cells). An INACTIVE layer keeps
      # its pixels untouched — the point of the per-layer gate. An active layer's clear wipes its ruler,
      # so the ruler is added to render_list here (it must re-render even if its own content is unchanged).
      if sticky_row_layer && row_active
        row_render << @col_ruler_widget.not_nil! if @col_ruler_widget && show_rulers
        sticky_row_layer.blit_plan = row_entries
        sticky_row_layer.blit_plan_render_widgets = row_render.empty? ? nil : row_render # never a stale list left behind
        sticky_row_layer.mark_needs_full_render
      end
      if sticky_col_layer && col_active
        col_render << @row_ruler_widget.not_nil! if @row_ruler_widget && show_rulers
        sticky_col_layer.blit_plan = col_entries
        sticky_col_layer.blit_plan_render_widgets = col_render.empty? ? nil : col_render # never a stale list left behind
        sticky_col_layer.mark_needs_full_render
      end
      if sticky_corner_layer && corner_active
        corner_render << @corner_ruler_widget.not_nil! if @corner_ruler_widget && show_rulers
        corner_render << @corner_row_strip_widget.not_nil! if @corner_row_strip_widget && show_rulers
        sticky_corner_layer.blit_plan = corner_entries
        sticky_corner_layer.blit_plan_render_widgets = corner_render.empty? ? nil : corner_render # never a stale list left behind
        sticky_corner_layer.mark_needs_full_render
      end

      {% if flag?(:cache_validation) %}
        validate_sticky_cell_bounds_invariant(sticky_rows, sticky_cols)
      {% end %}
      {% if flag?(:verify_bounds) %} verify_sticky_positions! {% end %}
    end

    # Every non-compound sticky cell whose bounds differ from its line (painted_col / painted_row, asked NOW):
    # pinned on its sticky axis, moved by painted_scroll on the other. That is the "sticky cell positioned from a
    # stale cache" bug (the column-widen ruler/data desync, 2026-05-30) - bounds set from an old position, or not
    # refreshed this frame. The rule is the one the passes place cells with, so this catches a pass that did not
    # run or skipped a cell, not a wrong rule (the pixel specs do that). A few comparisons over the header cells.
    private def stale_sticky_cells(sticky_rows : Int32, sticky_cols : Int32) : Array(String)
      found = [] of String
      @active_cells.each do |key, widget|
        row, col = key
        next unless row < sticky_rows || col < sticky_cols
        bb = get_bounding_box(key)
        next if bb[0] != bb[1] # compound cells size themselves; checked elsewhere
        exp_x = painted_col(col)[0]
        exp_y = painted_row(row)[0]
        next unless (widget.bounds.x - exp_x).abs > 1.0 || (widget.bounds.y - exp_y).abs > 1.0
        found << "key=(#{row},#{col}) expected=(#{exp_x.round(1)},#{exp_y.round(1)}) actual=(#{widget.bounds.x.round(1)},#{widget.bounds.y.round(1)}) wb=#{widget.widget_backend ? "yes" : "NIL"}"
      end
      found
    end

    # Dev assertion (build with -Dverify_bounds, e.g. in CI): the frame the bounds go wrong.
    {% if flag?(:verify_bounds) %}
      private def verify_sticky_positions!
        return if sticky_row_count == 0 && sticky_col_count == 0
        stale_sticky_cells(sticky_row_count, sticky_col_count).each do |v|
          STDERR.puts "[VERIFY_BOUNDS] matrix##{@id}: sticky cell #{v} scroll=(#{scroll_offset.x.round(1)},#{scroll_offset.y.round(1)})"
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
    private def validate_sticky_cell_bounds_invariant(sticky_rows : Int32, sticky_cols : Int32)
      violations = stale_sticky_cells(sticky_rows, sticky_cols)

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

    # A merged span's target rect (sticky_cell_rect) applied on the fast path - layout, so its content reflows at
    # a new extent; its cached texture dropped when the size changed.
    private def place_compound_in_blit_plan(widget : Widget, target : Rect) : Nil
      return if widget.bounds == target
      size_changed = widget.bounds.size != target.size
      widget.layout(BoxConstraints.tight(target.size), target.position)
      widget.invalidate_primitive_cache if size_changed
    end
  end
end
