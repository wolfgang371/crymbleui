module CrymbleUI
  class VirtualMatrix < Widget
    # === CURSOR AND NAVIGATION ===

    # Set cursor from cell coordinates.
    # Stores the exact clicked cell, not the top-left of merged region.
    # This allows cursor to be at any cell within a compound region.
    def set_cursor_from_cell(cell : Tuple(Int32, Int32))
      old_cursor = cursor_rc
      self.cursor_rc =cell
      clamp_cursor
      mark_cursor_overlay_dirty
      start_cursor_flash if cursor_rc != old_cursor
      update_proxy_focus if cursor_rc != old_cursor
    end

    # Move cursor in direction with optional modifiers
    def move_cursor(direction : Symbol, ctrl : Bool = false, shift : Bool = false)
      old_cursor = cursor_rc
      row, col = cursor_rc

      case direction
      when :up
        if ctrl
          row = 0
        else
          row = {row - 1, 0}.max
        end
      when :down
        if ctrl
          row = @rows - 1
        else
          row = {row + 1, @rows - 1}.min
        end
      when :left
        if ctrl
          col = 0
        else
          col = {col - 1, 0}.max
        end
      when :right
        if ctrl
          col = @cols - 1
        else
          col = {col + 1, @cols - 1}.min
        end
      when :home
        if ctrl
          row = 0
          col = 0
        else
          col = 0
        end
      when :end
        if ctrl
          row = @rows - 1
          col = @cols - 1
        else
          col = @cols - 1
        end
      when :tab
        # Tab wraps to next row, Shift+Tab wraps to previous row
        total_cells = @rows * @cols
        return if total_cells == 0 # degenerate grid: nothing to move to (avoid % 0)
        flat_index = row * @cols + col
        if shift
          flat_index -= 1
        else
          flat_index += 1
        end
        # Wrap around
        flat_index = flat_index % total_cells
        flat_index = total_cells + flat_index if flat_index < 0
        row = flat_index // @cols
        col = flat_index % @cols
      end

      self.cursor_rc ={row, col}
      clamp_cursor
      mark_cursor_overlay_dirty
      start_cursor_flash if cursor_rc != old_cursor
      update_proxy_focus if cursor_rc != old_cursor
    end

    # Clamp cursor to valid bounds
    private def clamp_cursor
      row = cursor_rc[0].clamp(0, {@rows - 1, 0}.max)
      col = cursor_rc[1].clamp(0, {@cols - 1, 0}.max)
      self.cursor_rc ={row, col}
    end

    # === PROXY FOCUS ===

    # Commit pending TextInput edits before deactivating proxy focus.
    # If the proxy-focused widget is a TextInput whose value differs from
    # value_on_focus, call adapter.cell_assign to persist the change.
    private def commit_proxy_edit
      return unless (widget = @proxy_focused_widget) && (rc = @proxy_focused_rc)
      @proxy_focused_rc = nil # prevent re-entrancy: cell_assign → invalidate_all! → clear_proxy_focus → commit_proxy_edit
      if widget.is_a?(TextInput)
        orig = widget.value_on_focus
        if orig && widget.value != orig
          if new_rc = @adapter.try &.cell_assign(rc[0], rc[1], widget.value)
            # Preserve any cursor delta already applied (e.g., arrow key moved before commit)
            delta_row = cursor_rc[0] - rc[0]
            delta_col = cursor_rc[1] - rc[1]
            self.cursor_rc ={new_rc[0] + delta_row, new_rc[1] + delta_col}
          end
        end
      end
    end

    # Update proxy focus to match the current cursor cell.
    # Called when cursor moves, when VirtualMatrix gains focus, or when cursor cell is created.
    private def update_proxy_focus
      # Don't establish proxy on cells that are about to be destroyed
      return if @pending_invalidate_all

      cell_widget = @active_cells[cursor_rc]?

      # The coordinate to store as @proxy_focused_rc. For a cursor on a NON-handle sub-cell of
      # a merged region, normalize to the region's STATIC top-left (bounding[0] below) so
      # commit_proxy_edit persists to the same coordinate the cell is PAINTED at (paint
      # normalizes identically, vm:1720-1723) and the stored rc stays consistent with the
      # handle widget @proxy_focused_widget points at — otherwise commit's delta math mixes a
      # raw-rc delta with the canonical new_rc and mislands the cursor. A directly-keyed cell
      # (non-merged, or the cursor on a region's dynamic handle) keeps cursor_rc; in the rare
      # scrolled-off case where the dynamic handle isn't the static top-left the adapter
      # re-normalizes it (embrace map_index) and a for_edit snap re-canonicalizes on next
      # establish. Reuse the bounding box already computed here — no extra get_bounding_box.
      handle_rc = cursor_rc

      # If cursor is on a non-handle cell within a merged region,
      # find the widget at the handle cell instead.
      unless cell_widget
        bounding = get_bounding_box(cursor_rc)
        if bounding[0] != bounding[1]  # Is merged
          handle_rc = bounding[0]      # canonical top-left of the merged region
          (bounding[0][0]..bounding[1][0]).each do |r|
            (bounding[0][1]..bounding[1][1]).each do |c|
              if w = @active_cells[{r, c}]?
                cell_widget = w
                break
              end
            end
            break if cell_widget
          end
        end
      end

      target = (cell_widget && cell_widget.focusable?) ? cell_widget : nil

      # No change needed
      return if @proxy_focused_widget == target

      # Commit edit and deactivate old
      commit_proxy_edit
      @proxy_focused_widget.try(&.deactivate_proxy_focus)

      # Activate new
      @proxy_focused_widget = target
      @proxy_focused_rc = target ? handle_rc : nil
      target.try(&.activate_proxy_focus)
    end

    # True when the cursor cell is in character-edit mode (draws its own caret) —
    # the whole-cell cursor flash is then suppressed (the caret is the indicator).
    # In cell-nav mode this is false, so the flash marks the cell (consistent across
    # cell types). Order-independent guard consulted by the overlay paint.
    def cursor_cell_draws_edit_caret? : Bool
      !!@proxy_focused_widget.try(&.draws_edit_caret?)
    end

    # Deactivate proxy focus entirely (on blur or cell destruction)
    private def clear_proxy_focus
      commit_proxy_edit
      @proxy_focused_widget.try(&.deactivate_proxy_focus)
      @proxy_focused_widget = nil
      @proxy_focused_rc = nil
    end

    # === END PROXY FOCUS ===

    # Mark cursor overlay for full re-render with new cursor position.
    # Uses mark_needs_clear_and_render (not mark_needs_layout) to force a buffer
    # clear + full render. This prevents ghost bands where old cursor bands
    # remain in the layer buffer after cursor moves. Lighter than mark_needs_layout:
    # avoids NeedsLayout semantics (sibling validation, disabled viewport culling).
    def mark_cursor_overlay_dirty
      # mark_needs_clear_and_render, NOT mark_needs_render: the render trigger is purely version-keyed
      # (the dirty-walk backstop was removed), and mark_needs_render moves no rev the trigger sees — so a
      # TIMER-driven flash toggle (no input event to force a redraw) would never wake the render loop, and
      # the cursor would only repaint when some other timer moved the aggregate (aliasing the ~400ms blink
      # to whenever that fires). clear_rev IS in frame_aggregate_rev, and a clear is anyway correct here:
      # the overlay's content toggles between drawing the cursor and nothing, so the old cursor must be
      # cleared. (Cursor MOVEMENT is event-driven and already forces a redraw; only the flash needs this.)
      @cursor_overlay_layer.try &.mark_needs_clear_and_render
    end

    # Re-render the drag decal layer (source/target cell highlights). Called on
    # every drag-state change — kept separate from the cursor overlay so the
    # 400ms cursor-flash tick doesn't needlessly repaint the drag decals.
    def mark_drag_overlay_dirty
      if overlay = @drag_overlay_layer
        if widget = overlay.widgets.first?
          overlay.mark_needs_render(widget)
        end
      end
    end

    CURSOR_FLASH_MS = 400

    # Start or restart cursor flash cycle on the overlay layer.
    private def start_cursor_flash
      # Cancel existing timer
      if timer_id = @cursor_flash_timer_id
        Widget.scheduler.cancel(timer_id)
      end

      # Start highlighted immediately (visual feedback on keypress)
      @cursor_flash_on = true
      @cursor_overlay_widget.try { |cow| cow.flash_on = true }
      mark_cursor_overlay_dirty

      # Schedule repeating toggle — direct_render overlay re-renders cheaply (~1ms)
      @cursor_flash_timer_id = Widget.scheduler.schedule(CURSOR_FLASH_MS.milliseconds, repeating: true) do
        @cursor_flash_on = !@cursor_flash_on
        @cursor_overlay_widget.try { |cow| cow.flash_on = @cursor_flash_on }
        mark_cursor_overlay_dirty
      end
    end

    # Stop cursor flash
    private def stop_cursor_flash
      if timer_id = @cursor_flash_timer_id
        Widget.scheduler.cancel(timer_id)
        @cursor_flash_timer_id = nil
      end
      @cursor_flash_on = false
      @cursor_overlay_widget.try { |cow| cow.flash_on = false }
      mark_cursor_overlay_dirty
    end

    # Cancel cursor flash timer without visual side-effects.
    # Used during reconciliation to prevent orphaned timers on old instances.
    def stop_cursor_flash_for_transfer
      if timer_id = @cursor_flash_timer_id
        Widget.scheduler.cancel(timer_id)
        @cursor_flash_timer_id = nil
      end
    end

    # Auto-scroll to keep cursor visible.
    # Follows the on_mouse_wheel pattern: render-only, no layout.
    # When for_edit is true, snaps to show the full merged region (for typing/editing).
    # When for_edit is false (default), snaps to the single cursor cell (for navigation).
    def snap_to_cursor(for_edit : Bool = false)
      {% if flag?(:CURSOR_PERF) %}
        _snap_start = Time.monotonic
      {% end %}
      return unless @content_layer
      return if @rows == 0 || @cols == 0 # degenerate grid: no cell to scroll into view

      row, col = cursor_rc
      viewport_width = @content_layer.try(&.bounds.width) || @bounds.width
      viewport_height = @content_layer.try(&.bounds.height) || @bounds.height

      # Build sizes and scroll_order (same as update_visible_cells)
      col_sizes = @cached_col_sizes ||= (0...@cols).map { |c| col_width_pixels(c).to_i32 }
      row_sizes = @cached_row_sizes ||= (0...@rows).map { |r| row_height_pixels(r).to_i32 }

      # For editing, use full bounding box so the entire merged region is visible.
      # For navigation, just ensure the single cursor cell is visible.
      if for_edit
        bounding = get_bounding_box(cursor_rc)
        min_row, min_col = bounding[0]
        max_row, max_col = bounding[1]
      else
        min_row, min_col = cursor_rc
        max_row, max_col = cursor_rc
      end

      # Geometric snap: use data positions relative to sticky header sizes.
      # In CrymbleUI, content scrolls uniformly in content_layer and sticky headers
      # are painted on separate layers on top. scroll_order does NOT affect visual
      # clipping of content cells, so visibility depends purely on geometry.
      new_scroll_x = scroll_offset.x
      new_scroll_y = scroll_offset.y

      # Horizontal: snap only for non-sticky columns
      unless min_col < sticky_col_count
        data_pos_x = (0...min_col).sum { |c| col_sizes[c] }
        merged_width = (min_col..max_col).sum { |c| col_sizes[c] }
        sticky_w = (sticky_col_width_pixels + ruler_col_width_pixels).to_i32
        ruler_col_w_i = ruler_col_width_pixels.to_i32
        scroll_x_i = scroll_offset.x.to_i32
        vp_w = viewport_width.to_i32

        # Cell content-space position includes ruler offset: ruler_col_w + data_pos_x
        screen_left = ruler_col_w_i + data_pos_x - scroll_x_i
        screen_right = ruler_col_w_i + data_pos_x + merged_width - scroll_x_i

        if screen_left < sticky_w
          # Left edge hidden behind sticky header + ruler → snap left
          new_scroll_x = (ruler_col_w_i + data_pos_x - sticky_w).to_f64
        elsif screen_right > vp_w
          # Right edge off-screen → snap right
          new_scroll_x = (ruler_col_w_i + data_pos_x + merged_width - vp_w).to_f64
        end
      end

      # Vertical: snap only for non-sticky rows
      unless min_row < sticky_row_count
        data_pos_y = (0...min_row).sum { |r| row_sizes[r] }
        merged_height = (min_row..max_row).sum { |r| row_sizes[r] }
        sticky_h = (sticky_row_height_pixels + ruler_row_height_pixels).to_i32
        ruler_row_h_i = ruler_row_height_pixels.to_i32
        scroll_y_i = scroll_offset.y.to_i32
        vp_h = viewport_height.to_i32

        # Cell content-space position includes ruler offset: ruler_row_h + data_pos_y
        screen_top = ruler_row_h_i + data_pos_y - scroll_y_i
        screen_bottom = ruler_row_h_i + data_pos_y + merged_height - scroll_y_i

        if screen_top < sticky_h
          # Top edge hidden behind sticky header + ruler → snap up
          new_scroll_y = (ruler_row_h_i + data_pos_y - sticky_h).to_f64
        elsif screen_bottom > vp_h
          # Bottom edge off-screen → snap down
          new_scroll_y = (ruler_row_h_i + data_pos_y + merged_height - vp_h).to_f64
        end
      end

      # Clamp scroll values
      new_scroll_y = new_scroll_y.clamp(0.0, max_content_scroll_y)
      new_scroll_x = new_scroll_x.clamp(0.0, max_content_scroll_x)

      if new_scroll_y != scroll_offset.y || new_scroll_x != scroll_offset.x
        {% if flag?(:DEBUG_BLIT) %}
          old_scroll = scroll_offset
        {% end %}
        {% if flag?(:DEBUG_BLIT) %}
          File.open("/tmp/blit_trace.log", "a") do |f|
            f.puts ">>> SCROLL: (#{old_scroll.x.round(1)},#{old_scroll.y.round(1)}) → (#{new_scroll_x.round(1)},#{new_scroll_y.round(1)})"
          end
        {% end %}
        self.scroll_offset = Vec2.new(new_scroll_x, new_scroll_y)  # custom setter: Source.set + apply_scroll
        {% if flag?(:CURSOR_PERF) %}
          _snap_ms = (Time.monotonic - _snap_start).total_milliseconds
          File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "  SNAP_TO_CURSOR(scroll): #{_snap_ms.round(2)}ms" }
        {% end %}
      else
        {% if flag?(:CURSOR_PERF) %}
          _snap_ms = (Time.monotonic - _snap_start).total_milliseconds
          if _snap_ms > 0.05
            File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "  SNAP_TO_CURSOR(no-scroll): #{_snap_ms.round(2)}ms" }
          end
        {% end %}
      end
    end
  end
end
