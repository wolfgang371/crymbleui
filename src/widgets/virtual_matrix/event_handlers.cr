module CrymbleUI
  class VirtualMatrix < Widget
    # === SCROLL HANDLING ===

    def on_mouse_wheel(delta : Vec2, point : Vec2, shift : Bool = false) : Bool
      return false unless absolute_bounds.contains_point(point)

      old_offset = scroll_offset
      new_offset = old_offset

      if shift
        # Horizontal scroll: swap axes (like ScrollView)
        new_x = old_offset.x - delta.y * scroll_speed
        new_x = new_x.clamp(0.0, max_content_scroll_x)
        new_offset = Vec2.new(new_x, old_offset.y)
      else
        # Vertical + horizontal scroll (supports touchpad diagonal scrolling)
        new_x = old_offset.x - delta.x * scroll_speed
        new_x = new_x.clamp(0.0, max_content_scroll_x)
        new_y = old_offset.y - delta.y * scroll_speed
        new_y = new_y.clamp(0.0, max_content_scroll_y)
        new_offset = Vec2.new(new_x, new_y)
      end

      if new_offset != old_offset
        {% if flag?(:DEBUG_BLIT) %}
          File.open("/tmp/blit_trace.log", "a") do |f|
            f.puts ">>> MOUSE_WHEEL: (#{old_offset.x.round(1)},#{old_offset.y.round(1)}) → (#{new_offset.x.round(1)},#{new_offset.y.round(1)}) delta=(#{delta.x},#{delta.y})"
          end
        {% end %}
        self.scroll_offset = new_offset  # custom setter: Source.set + apply_scroll
        return true
      end

      false
    end

    # === MOUSE HANDLING ===

    # Accumulate scroll offsets from ancestor ScrollViews.
    # on_mouse_down receives screen-space coordinates, but absolute_bounds
    # is in content-space (doesn't account for ancestor scrolling).
    # Adding ancestor scroll offsets converts screen→content.
    private def ancestor_scroll_offset : Vec2
      offset = Vec2.zero
      current = @parent
      while current
        if current.is_a?(ScrollView)
          offset = Vec2.new(offset.x + current.scroll_offset.x, offset.y + current.scroll_offset.y)
        end
        current = current.parent
      end
      offset
    end

    def point_to_cell(point : Vec2) : Tuple(Int32, Int32)?
      content_x = absolute_bounds.x
      content_y = absolute_bounds.y

      screen_x = point.x - content_x
      screen_y = point.y - content_y

      # Clicks in ruler strips don't select cells
      return nil if screen_y < ruler_row_height_pixels && show_rulers
      return nil if screen_x < ruler_col_width_pixels && show_rulers

      # Subtract ruler offsets to get data-area coordinates
      data_x = screen_x - ruler_col_width_pixels
      data_y = screen_y - ruler_row_height_pixels

      # Sticky headers occupy fixed screen bands. Clicks within a sticky band
      # must map to the sticky row/col, not the hidden content underneath.
      in_sticky_col = data_x < sticky_col_width_pixels && sticky_col_count > 0
      in_sticky_row = data_y < sticky_row_height_pixels && sticky_row_count > 0

      local_x = in_sticky_col ? data_x : data_x + scroll_offset.x
      local_y = in_sticky_row ? data_y : data_y + scroll_offset.y
      return nil if local_x < 0 || local_y < 0

      # Find column — O(log N) binary search on cached physical cumulative array
      col_cum = @cached_col_physical_cum
      if col_cum
        col = col_cum.bsearch_index { |p| p > local_x.to_i32 }
        return nil unless col  # Beyond all columns
        col = {col - 1, 0}.max
      else
        col = 0
        acc_x = 0.0
        while col < @cols && acc_x + col_width_pixels(col) <= local_x
          acc_x += col_width_pixels(col)
          col += 1
        end
        return nil if col >= @cols
      end

      # Find row — O(log N) binary search on cached physical cumulative array
      row_cum = @cached_row_physical_cum
      if row_cum
        row = row_cum.bsearch_index { |p| p > local_y.to_i32 }
        return nil unless row  # Beyond all rows
        row = {row - 1, 0}.max
      else
        row = 0
        acc_y = 0.0
        while row < @rows && acc_y + row_height_pixels(row) <= local_y
          acc_y += row_height_pixels(row)
          row += 1
        end
        return nil if row >= @rows
      end
      {row, col}
    end

    # Override hit_test to delegate scrollbar area hits to ScrollView.
    # Without this, cell widgets (which are direct children)
    # would intercept clicks meant for the scrollbar.
    def hit_test(point : Vec2) : Widget?
      abs = absolute_bounds
      return nil unless abs.contains_point(point)

      # Check ScrollView scrollbar area FIRST - delegate if it's a scrollbar hit
      if sv = @content_scroll_view
        if sv.point_in_scrollbar_area?(point)
          return sv
        end
      end

      # Non-interactive mode: let cell widgets receive direct clicks (no
      # cursor navigation, no proxy forwarding). Used by the `matrix` DSL
      # sugar for summary / listing tables AND by DirBrowser-style
      # dialogs where the cells ARE the action targets.
      #
      # Cell widgets keep their LOGICAL bounds — scrolling shifts only the
      # rendering layer, not widget positions (per ScrollView's
      # "Widget positions don't change, only the viewport offset changes"
      # contract). So we route through `point_to_cell` (which handles
      # ruler offset, sticky bands, AND scroll offset) to find which
      # logical cell the mouse is over, then look up that cell's widget
      # in @active_cells. Without this, descending into children with a
      # raw screen-space point returns whatever cell happens to share
      # the un-scrolled logical position — visibly offset from where the
      # mouse actually is whenever scroll_offset != 0.
      unless @interactive_cells
        ancestor_scroll = ancestor_scroll_offset
        content_point = Vec2.new(point.x + ancestor_scroll.x, point.y + ancestor_scroll.y)
        if sv = @content_scroll_view
          @scroll_offset.set(sv.scroll_offset)
        end
        if cell_rc = point_to_cell(content_point)
          if widget = @active_cells[cell_rc]?
            # Deep hit_test inside the cell widget in case it contains
            # nested children. Pass content_point because the cell's
            # bounds (and its descendants') are in LOGICAL coordinates.
            return widget.hit_test(content_point) || widget
          end
        end
        return nil
      end

      # VirtualMatrix handles all mouse input for the content area.
      # Cell widgets are managed internally via proxy focus — they should never
      # receive direct clicks (which would steal focus from VirtualMatrix).
      self
    end

    # Forward trigger_click to the proxy-focused cell widget.
    # hit_test returns VirtualMatrix (self), so App.handle_mouse_up calls
    # trigger_click on us — we must forward to the cell (Button, Checkbox, etc.).
    def trigger_click
      if proxy = @proxy_focused_widget
        proxy.trigger_click
        # Re-assert focus: proxy widgets (e.g., TextInput.on_click) may call
        # request_focus which steals keyboard focus from VirtualMatrix.
        request_focus
      else
        super
      end
    end

    # === INTERACTIVE RESIZE ===

    # Detect if point is near a column or row border in the header area.
    # Returns {ResizeAxis, index} where index is the col/row to the LEFT/ABOVE the border.
    private def detect_resize_edge(point : Vec2) : Tuple(ResizeAxis, Int32)?
      sx = point.x - absolute_bounds.x
      sy = point.y - absolute_bounds.y

      ruler_h = ruler_row_height_pixels
      ruler_w = ruler_col_width_pixels

      # Column borders: only in column ruler strip (top ruler_h pixels)
      if show_rulers && sy < ruler_h
        # local_x is in grid space (subtract ruler_w offset, then handle scroll)
        grid_x = sx - ruler_w
        local_x = (grid_x < sticky_col_width_pixels && sticky_col_count > 0) ? grid_x : grid_x + scroll_offset.x
        acc = 0.0
        (0...@cols).each do |c|
          acc += col_width_pixels(c)
          return {ResizeAxis::Col, c} if (local_x - acc).abs < resize_tolerance
          break if acc > local_x + resize_tolerance
        end
      end

      # Row borders: only in row ruler strip (left ruler_w pixels)
      if show_rulers && sx < ruler_w
        # local_y is in grid space (subtract ruler_h offset, then handle scroll)
        grid_y = sy - ruler_h
        local_y = (grid_y < sticky_row_height_pixels && sticky_row_count > 0) ? grid_y : grid_y + scroll_offset.y
        acc = 0.0
        (0...@rows).each do |r|
          acc += row_height_pixels(r)
          return {ResizeAxis::Row, r} if (local_y - acc).abs < resize_tolerance
          break if acc > local_y + resize_tolerance
        end
      end

      nil
    end

    def preferred_cursor(point : Vec2) : CursorType?
      ancestor_scroll = ancestor_scroll_offset
      content_point = Vec2.new(point.x + ancestor_scroll.x, point.y + ancestor_scroll.y)
      edge = detect_resize_edge(content_point)
      return nil unless edge
      case edge[0]
      when ResizeAxis::Col then CursorType::SizeHorizontal
      when ResizeAxis::Row then CursorType::SizeVertical
      else nil
      end
    end

    def on_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left) : Bool
      bring_containing_panel_to_front
      request_focus
      @drag_source_was_preexisting = !@drag_source_cell.nil?
      # Right-click: move cursor to clicked cell, then bubble for context menu
      if button == MouseButton::Right
        content_point = Vec2.new(point.x + ancestor_scroll_offset.x, point.y + ancestor_scroll_offset.y)
        if sv = @content_scroll_view
          @scroll_offset.set(sv.scroll_offset)
        end
        if cell = point_to_cell(content_point)
          set_cursor_from_cell(cell)
          mark_needs_render
        end
        super(point, button)
        return true
      end

      # Convert screen-space point to content-space by adding ancestor scroll offsets.
      # App.handle_mouse_down passes screen-space coordinates, but absolute_bounds
      # is in content-space (doesn't account for ancestor ScrollView scrolling).
      content_point = Vec2.new(point.x + ancestor_scroll_offset.x, point.y + ancestor_scroll_offset.y)

      # Sync scroll offset from ScrollView (user may have scrolled via scrollbar)
      if sv = @content_scroll_view
        @scroll_offset.set(sv.scroll_offset)
      end

      # Check resize edge first
      if edge = detect_resize_edge(content_point)
        self.resize_axis = edge[0]
        self.resize_index = edge[1]
        @resize_pending_shift_px = 0 # fresh gesture: the buffer matches the current sizes
        sx = content_point.x - absolute_bounds.x
        sy = content_point.y - absolute_bounds.y
        if edge[0] == ResizeAxis::Col
          grid_x = sx - ruler_col_width_pixels
          self.resize_start_mouse = grid_x + (grid_x >= sticky_col_width_pixels ? scroll_offset.x : 0.0)
          self.resize_start_size = get_col_width(edge[1])
        else
          grid_y = sy - ruler_row_height_pixels
          self.resize_start_mouse = grid_y + (grid_y >= sticky_row_height_pixels ? scroll_offset.y : 0.0)
          self.resize_start_size = get_row_height(edge[1])
        end
        return true
      end

      if cell = point_to_cell(content_point)
        row, col = cell
        now = Time.instant

        # Double-click on same cell: first give on_cell_activate callback a
        # chance (e.g. drill-down into aggregate cells); if it returns true the
        # activation is handled and proxy forwarding is skipped. Otherwise fall
        # back to proxy forwarding (opens ComboBox, edit mode, etc.).
        if {row, col} == @last_click_cell &&
           (now - @last_click_time).total_milliseconds < DOUBLE_CLICK_THRESHOLD_MS
          @last_click_time = Time.instant - 1.hour  # prevent triple-click
          handled = @on_cell_activate.try(&.call({row, col})) || false
          unless handled
            if proxy = @proxy_focused_widget
              proxy.on_mouse_up(Vec2.zero)
            end
          end
        else
          set_cursor_from_cell({row, col})
          mark_needs_render
          @last_click_time = now
          @last_click_cell = {row, col}
          # Set drag source for potential cell drag (DragManager detects threshold).
          # Flag it provisional: DragManager reads it to build the ghost, but the
          # decal stays hidden until on_drag_start commits it — otherwise a plain
          # click would flash the salmon highlight for the mouse-press duration.
          if adapter = @adapter
            if adapter.cell_has_content?(row, col)
              @drag_source_cell = {row, col}
              @drag_source_provisional = true
            else
              @drag_source_cell = nil
            end
          end
        end
      end
      true
    end

    def on_mouse_move(point : Vec2)
      return unless resize_axis != ResizeAxis::None

      # Convert screen-space to content-space (same as on_mouse_down)
      ancestor_scroll = ancestor_scroll_offset
      content_x = point.x + ancestor_scroll.x
      content_y = point.y + ancestor_scroll.y
      sx = content_x - absolute_bounds.x
      sy = content_y - absolute_bounds.y

      if resize_axis == ResizeAxis::Col
        grid_x = sx - ruler_col_width_pixels
        current = grid_x + (grid_x >= sticky_col_width_pixels ? scroll_offset.x : 0.0)
        delta_pixels = current - resize_start_mouse
        new_width = (resize_start_size + delta_pixels / frame_height).clamp(MIN_COL_WIDTH, Float64::MAX)
        set_col_width_for_drag(resize_index, new_width)
      else
        grid_y = sy - ruler_row_height_pixels
        current = grid_y + (grid_y >= sticky_row_height_pixels ? scroll_offset.y : 0.0)
        delta_pixels = current - resize_start_mouse
        new_height = (resize_start_size + delta_pixels / frame_height).clamp(MIN_ROW_HEIGHT, Float64::MAX)
        set_row_height_for_drag(resize_index, new_height)
      end

      # The new size is applied above (cheap). Defer the expensive per-move work —
      # sticky/corner geometry, cell reflow, ruler invalidation — to pre_render_flush
      # so a fast (~125 Hz) drag coalesces to ONE update per frame instead of
      # re-laying-out the whole grid on every event (the 99%-CPU resize bug).
      @pending_resize_update = true
      mark_needs_render
      mark_cursor_overlay_dirty
    end

    def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
      if resize_axis != ResizeAxis::None
        # Persist the new sizes to the adapter (survives shape duplication).
        if adapter = @adapter
          adapter.custom_col_widths = @col_widths.dup
          adapter.custom_row_heights = @row_heights.dup
        end
        # Re-lay-out THIS matrix so the finished resize renders identically to a Ctrl+0 full layout.
        # A column/row resize can flip scrollbar visibility (the content now overflows the viewport),
        # but the incremental drag path only updates pieces — content_size is a reconcile_property
        # with no invalidation — so the horizontal scrollbar stays unrendered and the content area
        # stale until a full layout (the user had to press Ctrl+0 to get a scrollbar). Calling
        # perform_layout directly with the UNCHANGED bounds re-runs setup_scroll_view (→ the
        # ScrollView re-evaluates + re-renders its scrollbars) and update_visible_cells (→ cells
        # reflow into the now scrollbar-reduced content area). Unlike mark_needs_layout it does NOT
        # go through App#prepare_layout, so it triggers neither an app-level layout nor a DSL rebuild
        # — cell widget instances (and any in-progress edit) survive. can_skip_layout? would short-
        # circuit the public layout() here (constraints are unchanged), so we call perform_layout.
        perform_layout(BoxConstraints.tight(@bounds.size), @bounds.position)
        # perform_layout above already did the reflow/geometry for the final sizes,
        # so drop any pending per-frame flag; but the Dynamic ruler nodes read
        # @cached_col_sizes (not a Source), so still invalidate them explicitly.
        @pending_resize_update = false
        mark_ruler_widgets_dirty
        mark_needs_render
      end
      self.resize_axis = ResizeAxis::None
      # Clear drag source if click didn't become a drag — but preserve cut highlights
      if @drag_source_cell && !@drag_source_was_preexisting
        @drag_source_cell = nil
        @drag_source_provisional = false
        mark_drag_overlay_dirty
      end
    end

    # === FOCUS ===

    def on_focus
      super
      start_cursor_flash
      update_proxy_focus
    end

    def on_blur
      stop_cursor_flash
      clear_proxy_focus
    end

    # === KEYBOARD HANDLING ===

    def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
      {% if flag?(:CURSOR_PERF) %}
        _kd_start = Time.monotonic
      {% end %}
      # For editing keys (not navigation/tab), snap to cursor first.
      # If the cursor cell was off-screen, this recreates it and
      # re-establishes proxy focus via update_visible_cells.
      case key
      when SF::Keyboard::Key::Up, SF::Keyboard::Key::Down,
           SF::Keyboard::Key::Left, SF::Keyboard::Key::Right,
           SF::Keyboard::Key::Tab, SF::Keyboard::Key::Home,
           SF::Keyboard::Key::End
        # Navigation keys: handled below, snap_to_cursor called after move_cursor
      else
        snap_to_cursor(for_edit: true)
      end

      # Escape: the proxy gets first shot (TextInput: undo edit, ComboBox:
      # close popup). Panel-scoped Escape shortcuts (dialog close) are handled
      # BEFORE focus dispatch in the SFML renderer. Cancelling a pending cell
      # cut is an app-level concern (the owner's handle_escape) — the matrix no
      # longer carries cell-op vocabulary.
      if key == SF::Keyboard::Key::Escape
        if proxy = @proxy_focused_widget
          proxy.on_key_down(key, control, shift)
        end
        return true
      end

      # Proxy focus forwarding: if a focusable cell widget has proxy focus,
      # forward events to it (except arrows in QuickEntry and Tab)
      if proxy = @proxy_focused_widget
        case key
        when SF::Keyboard::Key::Up, SF::Keyboard::Key::Down,
             SF::Keyboard::Key::Left, SF::Keyboard::Key::Right
          if proxy.wants_arrow_keys?
            return true if proxy.on_key_down(key, control, shift)
          end
          clear_proxy_focus
        when SF::Keyboard::Key::Tab
          # Don't forward Tab to the proxy — fall through (no return) to the
          # grid-nav Tab case below, which round-robins the cell cursor.
        when SF::Keyboard::Key::Enter, SF::Keyboard::Key::Space
          # App-level activation (e.g. drill-down) gets priority over the
          # proxy's default Enter/Space handler. If on_cell_activate returns
          # true, skip proxy forward entirely.
          if @on_cell_activate.try(&.call(cursor_rc))
            return true
          end
          if proxy.on_key_down(key, control, shift)
            return true
          end
          if proxy.is_a?(TextInput)
            # A focused text editor. Enter LEAVES full-edit mode: commit the edit
            # and re-arm QuickEntry on the SAME cell. Enter toggles in/out of
            # full-edit (F2-style) — it does NOT move the cursor (arrow keys do
            # accept-and-move in QuickEntry). This also kills the old
            # cursored-but-un-proxied dead cell (typing silently ignored). Space
            # is TEXT (a separate TextEntered forwarded by on_text_input); consume
            # so it never falls through to grid activation.
            if key == SF::Keyboard::Key::Enter
              clear_proxy_focus   # commit the edit + drop the now-stale proxy
              update_proxy_focus  # re-arm the same cursor cell in QuickEntry
              mark_needs_render
            end
            return true
          end
          proxy.trigger_click
          return true
        else
          return true if proxy.on_key_down(key, control, shift)
        end
      end

      # Grid navigation
      case key
      when SF::Keyboard::Key::Tab
        # Spreadsheet round-robin: Tab advances the cell cursor (wrapping
        # end-of-row to the next row, last cell back to {0,0}), Shift+Tab
        # reverses. The matrix consumes Tab and stays focused — it never
        # cycles focus out (FocusManager#handle_tab_key only cycles when the
        # focused widget declines).
        move_cursor(:tab, shift: shift)
        snap_to_cursor
        mark_needs_render
        true
      when SF::Keyboard::Key::Up
        move_cursor(:up, control, shift)
        snap_to_cursor
        mark_needs_render
        {% if flag?(:CURSOR_PERF) %}
          _kd_ms = (Time.monotonic - _kd_start).total_milliseconds
          File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "KEY_UP: #{_kd_ms.round(2)}ms cursor=#{cursor_rc} scroll=#{scroll_offset.y.round(1)} active_cells=#{@active_cells.size} rows=#{@rows} cols=#{@cols}" }
        {% end %}
        true
      when SF::Keyboard::Key::Down
        move_cursor(:down, control, shift)
        snap_to_cursor
        mark_needs_render
        {% if flag?(:CURSOR_PERF) %}
          _kd_ms = (Time.monotonic - _kd_start).total_milliseconds
          File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "KEY_DOWN: #{_kd_ms.round(2)}ms cursor=#{cursor_rc} scroll=#{scroll_offset.y.round(1)} active_cells=#{@active_cells.size} rows=#{@rows} cols=#{@cols}" }
        {% end %}
        true
      when SF::Keyboard::Key::Left
        return false if alt  # Alt+Left: let shortcut manager handle (e.g., history navigation)
        move_cursor(:left, control, shift)
        snap_to_cursor
        mark_needs_render
        true
      when SF::Keyboard::Key::Right
        return false if alt  # Alt+Right: let shortcut manager handle
        move_cursor(:right, control, shift)
        snap_to_cursor
        mark_needs_render
        true
      when SF::Keyboard::Key::Home
        move_cursor(:home, control, shift)
        snap_to_cursor
        mark_needs_render
        true
      when SF::Keyboard::Key::End
        move_cursor(:end, control, shift)
        snap_to_cursor
        mark_needs_render
        true
      else
        false
      end
    end

    def on_text_input(char : Char) : Bool
      # Service a pending invalidation BEFORE deciding where this character goes. A commit earlier in
      # the SAME poll batch (cursor-down -> cell_assign -> the adapter's invalidate_all!) sets
      # @pending_invalidate_all, and update_proxy_focus then refuses to attach to cells that are
      # about to be destroyed — correct in itself, but it leaves NO proxy at all until the next
      # frame flushes. The run loop drains every queued event before it rebuilds, so the characters
      # queued behind that commit arrived here with nowhere to go and were silently discarded.
      # Field-reported as "type, cursor down, repeat quickly — keys get lost"; a live trace showed
      # 8 of 16 characters destroyed, every loss being a non-first member of its batch.
      # Guarded by spec/widgets/virtual_matrix_batch_text_spec.cr.
      #
      # Attaching to a cell that a pending invalidation will destroy is SAFE: flush_invalidate_all
      # commits the proxy edit (and deactivates it) before tearing any cell down, so a character
      # typed into it reaches the adapter by the same route as any other. Flushing here instead was
      # tried and is wrong — it destroys the cells and nothing recreates them until layout, leaving
      # even less to type into.
      # Snap to cursor — if cell was off-screen, this recreates it
      # and re-establishes proxy focus via update_visible_cells
      snap_to_cursor(for_edit: true)

      # App-level activation (e.g. drill-down on aggregate cells) takes
      # priority over edit mode. If on_cell_activate returns true, the first
      # typed character opens the drilled view instead of seeding edit text.
      if @on_cell_activate.try(&.call(cursor_rc))
        return true
      end

      # An invalidation queued earlier in this batch suppressed the normal re-derive; do it now,
      # explicitly overriding that guard, so the character has its destination.
      update_proxy_focus(force: true) if @proxy_focused_widget.nil?

      # Proxy focus forwarding: forward text to the proxy-focused cell widget
      if proxy = @proxy_focused_widget
        proxy.on_text_input(char)
        return true
      end

      # NOT "unhandled input". A focused matrix with instantiated cells has a destination for a
      # character by construction, so reaching here means a precondition was violated — and the bare
      # `false` this replaces turned that into silently lost user keystrokes rather than a visible
      # failure. An empty cell set (no rows/cols, zero-size viewport) is the one legitimate case.
      assert(@active_cells.empty?,
        "VirtualMatrix '#{id || "unnamed"}' received text at cursor #{cursor_rc} with " \
        "#{@active_cells.size} active cells but no proxy target — the character would be discarded")
      false
    end

    # === CELL DRAG-AND-DROP ===

    # Draggable: ghost bounds = drag bounding box (spans the full multi-cell region)
    def drag_ghost_bounds : Rect?
      if src = @drag_source_cell
        if adapter = @adapter
          bb = adapter.cell_get_drag_bounding_box(src[0], src[1])
          min_r, min_c = bb[0]
          max_r, max_c = bb[1]
          abs = absolute_bounds
          x = abs.x + ruler_col_width_pixels + (0...min_c).sum { |c| col_width_pixels(c) } - scroll_offset.x
          y = abs.y + ruler_row_height_pixels + (0...min_r).sum { |r| row_height_pixels(r) } - scroll_offset.y
          w = (min_c..max_c).sum { |c| col_width_pixels(c) }
          h = (min_r..max_r).sum { |r| row_height_pixels(r) }
          Rect.new(x, y, w, h)
        end
      end
    end

    # Draggable: return data for the cell clicked in on_mouse_down
    def get_drag_data : DragData?
      if src = @drag_source_cell
        if adapter = @adapter
          name = adapter.cell_get_name(src[0], src[1])
          CellDragData.new(src[0], src[1], name, @drag_owner_key)
        end
      end
    end

    # Simple ghost: just a themed semi-transparent fill (no border, no text)
    def create_ghost_preview : Widget?
      SimpleGhostWidget.new
    end

    def on_drag_start(data : DragData)
      # The drag crossed the threshold — the source is now committed, so its
      # decal may paint (it was provisional through the mouse-down candidate).
      @drag_source_provisional = false
      mark_drag_overlay_dirty
    end

    def on_drag_end(data : DragData, dropped : Bool)
      @drag_source_cell = nil
      @drag_target_cell = nil
      @drag_source_provisional = false
      mark_drag_overlay_dirty
    end

    # DropTarget: accept cell data from same matrix
    def accepts_drop?(data : DragData) : Bool
      data.is_a?(CellDragData)
    end

    # Disable DragManager's widget-level highlight (we highlight individual cells instead)
    def highlight_opacity : Float64
      0.0
    end

    def on_drop(data : DragData, position : Vec2)
      return unless data.is_a?(CellDragData)
      return unless target = point_to_cell(position)
      # Cross-owner drop: the payload came from a different matrix, so its
      # (row, col) are meaningless here — a native cell_move would corrupt
      # data. Delegate to the app, which reconstructs the source cell from
      # the payload's owner_key and routes through its own dispatcher.
      if (owner = data.owner_key) && owner != @drag_owner_key
        @cross_drop_handler.try &.call(data, target[0], target[1])
        return
      end
      if adapter = @adapter
        new_cursor = adapter.cell_move(data.row, data.col, target[0], target[1])
        set_cursor_from_cell(new_cursor)
        mark_needs_render
        @on_cell_drop_handler.try &.call
      end
    end

    def on_drag_over(data : DragData, position : Vec2)
      @drag_target_cell = point_to_cell(position)
      mark_drag_overlay_dirty
    end

    def on_drag_leave(data : DragData)
      @drag_target_cell = nil
      mark_drag_overlay_dirty
    end
  end
end
