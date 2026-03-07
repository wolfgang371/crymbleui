module CrymbleUI
  class VirtualMatrix < Widget
    # === SCROLL HANDLING ===

    def on_mouse_wheel(delta : Vec2, point : Vec2, shift : Bool = false) : Bool
      return false unless absolute_bounds.contains_point(point)

      old_offset = @scroll_offset
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
        @scroll_offset = new_offset
        @last_synced_scroll_offset = new_offset
        {% if flag?(:DEBUG_BLIT) %}
          File.open("/tmp/blit_trace.log", "a") do |f|
            f.puts ">>> MOUSE_WHEEL: (#{old_offset.x.round(1)},#{old_offset.y.round(1)}) → (#{@scroll_offset.x.round(1)},#{@scroll_offset.y.round(1)}) delta=(#{delta.x},#{delta.y})"
          end
        {% end %}

        # VIEWPORT_CACHE: Update layer scroll_offset for smooth panning
        # Widget positions don't change, only the viewport offset changes
        if layer = @content_layer
          layer.scroll_offset = @scroll_offset
        end

        # Sync to ScrollView (for scrollbar thumb position)
        # Use silent setter to avoid triggering layout (scroll is O(1) compositing)
        if sv = @content_scroll_view
          sv.set_scroll_offset_for_sync(@scroll_offset)
        end

        # Always call update_visible_cells to check for new cells at viewport edges
        # The function has early-exit optimization when indices don't change
        # Use content layer dimensions (excludes scrollbar width) to match sync_from_scroll_view
        vp_w = @content_layer.try(&.bounds.width) || bounds.width
        vp_h = @content_layer.try(&.bounds.height) || bounds.height
        if vp_w > 0 && vp_h > 0
          update_visible_cells(vp_w, vp_h)
        end

        # Mark for render to display the updated viewport
        mark_needs_render
        mark_cursor_overlay_dirty

        return true
      end

      false
    end

    # === MOUSE HANDLING ===

    private def point_to_cell(point : Vec2) : Tuple(Int32, Int32)?
      content_x = absolute_bounds.x
      content_y = absolute_bounds.y

      screen_x = point.x - content_x
      screen_y = point.y - content_y

      # Clicks in ruler strips don't select cells
      return nil if screen_y < ruler_row_height_pixels && @show_rulers
      return nil if screen_x < ruler_col_width_pixels && @show_rulers

      # Subtract ruler offsets to get data-area coordinates
      data_x = screen_x - ruler_col_width_pixels
      data_y = screen_y - ruler_row_height_pixels

      # Sticky headers occupy fixed screen bands. Clicks within a sticky band
      # must map to the sticky row/col, not the hidden content underneath.
      in_sticky_col = data_x < sticky_col_width_pixels && sticky_col_count > 0
      in_sticky_row = data_y < sticky_row_height_pixels && sticky_row_count > 0

      local_x = in_sticky_col ? data_x : data_x + @scroll_offset.x
      local_y = in_sticky_row ? data_y : data_y + @scroll_offset.y
      return nil if local_x < 0 || local_y < 0

      # Find column — O(log N) binary search on cached physical cumulative array
      col_cum = @cached_col_physical_cum
      if col_cum
        col = col_cum.bsearch_index { |p| p > local_x.to_i32 }
        col = col ? {col - 1, 0}.max : @cols - 1
      else
        col = 0
        acc_x = 0.0
        while col < @cols && acc_x + col_width_pixels(col) <= local_x
          acc_x += col_width_pixels(col)
          col += 1
        end
      end

      # Find row — O(log N) binary search on cached physical cumulative array
      row_cum = @cached_row_physical_cum
      if row_cum
        row = row_cum.bsearch_index { |p| p > local_y.to_i32 }
        row = row ? {row - 1, 0}.max : @rows - 1
      else
        row = 0
        acc_y = 0.0
        while row < @rows && acc_y + row_height_pixels(row) <= local_y
          acc_y += row_height_pixels(row)
          row += 1
        end
      end

      return nil if row >= @rows || col >= @cols
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
      if @show_rulers && sy < ruler_h
        # local_x is in grid space (subtract ruler_w offset, then handle scroll)
        grid_x = sx - ruler_w
        local_x = (grid_x < sticky_col_width_pixels && sticky_col_count > 0) ? grid_x : grid_x + @scroll_offset.x
        acc = 0.0
        (0...@cols).each do |c|
          acc += col_width_pixels(c)
          return {ResizeAxis::Col, c} if (local_x - acc).abs < resize_tolerance
          break if acc > local_x + resize_tolerance
        end
      end

      # Row borders: only in row ruler strip (left ruler_w pixels)
      if @show_rulers && sx < ruler_w
        # local_y is in grid space (subtract ruler_h offset, then handle scroll)
        grid_y = sy - ruler_h
        local_y = (grid_y < sticky_row_height_pixels && sticky_row_count > 0) ? grid_y : grid_y + @scroll_offset.y
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
      edge = detect_resize_edge(point)
      return nil unless edge
      case edge[0]
      when ResizeAxis::Col then CursorType::SizeHorizontal
      when ResizeAxis::Row then CursorType::SizeVertical
      else nil
      end
    end

    def on_mouse_down(point : Vec2) : Bool
      bring_containing_panel_to_front
      request_focus

      # Sync scroll offset from ScrollView (user may have scrolled via scrollbar)
      if sv = @content_scroll_view
        @scroll_offset = sv.scroll_offset
      end

      # Check resize edge first
      if edge = detect_resize_edge(point)
        self.resize_axis = edge[0]
        self.resize_index = edge[1]
        sx = point.x - absolute_bounds.x
        sy = point.y - absolute_bounds.y
        if edge[0] == ResizeAxis::Col
          grid_x = sx - ruler_col_width_pixels
          self.resize_start_mouse = grid_x + (grid_x >= sticky_col_width_pixels ? @scroll_offset.x : 0.0)
          self.resize_start_size = get_col_width(edge[1])
        else
          grid_y = sy - ruler_row_height_pixels
          self.resize_start_mouse = grid_y + (grid_y >= sticky_row_height_pixels ? @scroll_offset.y : 0.0)
          self.resize_start_size = get_row_height(edge[1])
        end
        return true
      end

      if cell = point_to_cell(point)
        row, col = cell
        set_cursor_from_cell({row, col})
        update_cell_states
        mark_needs_render
      end
      true
    end

    def on_mouse_move(point : Vec2)
      return unless resize_axis != ResizeAxis::None

      sx = point.x - absolute_bounds.x
      sy = point.y - absolute_bounds.y

      if resize_axis == ResizeAxis::Col
        grid_x = sx - ruler_col_width_pixels
        current = grid_x + (grid_x >= sticky_col_width_pixels ? @scroll_offset.x : 0.0)
        delta_pixels = current - resize_start_mouse
        new_width = (resize_start_size + delta_pixels / frame_height).clamp(MIN_COL_WIDTH, Float64::MAX)
        set_col_width_for_drag(resize_index, new_width)
      else
        grid_y = sy - ruler_row_height_pixels
        current = grid_y + (grid_y >= sticky_row_height_pixels ? @scroll_offset.y : 0.0)
        delta_pixels = current - resize_start_mouse
        new_height = (resize_start_size + delta_pixels / frame_height).clamp(MIN_ROW_HEIGHT, Float64::MAX)
        set_row_height_for_drag(resize_index, new_height)
      end

      # Invalidate ruler widgets (they read cached sizes which just changed)
      @col_ruler_widget.try(&.mark_needs_render)
      @row_ruler_widget.try(&.mark_needs_render)

      # Update corner widget bounds for sticky col/row resizes (no full layout needed)
      ruler_w = ruler_col_width_pixels
      ruler_h = ruler_row_height_pixels
      if crw = @corner_ruler_widget
        corner_w = ruler_w + sticky_col_width_pixels
        crw.layout(BoxConstraints.tight(Size.new(corner_w, ruler_h)), Vec2.zero)
        crw.mark_needs_render
      end
      if strip = @corner_row_strip_widget
        strip.layout(BoxConstraints.tight(Size.new(ruler_w, sticky_row_height_pixels)), Vec2.new(0.0, ruler_h))
        strip.mark_needs_render
      end

      # Sync sticky layer bounds to match new dimensions (avoids full layout)
      if sv = @content_scroll_view
        sv.sticky_row_height = sticky_row_height_pixels + ruler_row_height_pixels
        sv.sticky_col_width = sticky_col_width_pixels + ruler_col_width_pixels
        sv.update_sticky_layer_bounds
      end

      # Refresh cells and render without layout (O(1) per move)
      vp_w = @content_layer.try(&.bounds.width) || bounds.width
      vp_h = @content_layer.try(&.bounds.height) || bounds.height
      update_visible_cells(vp_w, vp_h) if vp_w > 0 && vp_h > 0
      mark_needs_render
      mark_cursor_overlay_dirty
    end

    def on_mouse_up(point : Vec2)
      if resize_axis != ResizeAxis::None
        # Update ScrollView content size directly (avoids mark_needs_layout → rebuild
        # in DSL apps, which would recreate the adapter and lose user-edited cell data)
        if sv = @content_scroll_view
          sv.content_size = Size.new(total_content_width, total_content_height)
        end
        mark_needs_render
      end
      self.resize_axis = ResizeAxis::None
    end

    # === FOCUS ===

    def on_focus
      super
      update_proxy_focus
    end

    def on_blur
      stop_cursor_flash
      clear_proxy_focus
    end

    # === KEYBOARD HANDLING ===

    def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool) : Bool
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

      # Proxy focus forwarding: if a focusable cell widget has proxy focus,
      # forward events to it (except arrows in QuickEntry and Tab)
      if proxy = @proxy_focused_widget
        case key
        when SF::Keyboard::Key::Up, SF::Keyboard::Key::Down,
             SF::Keyboard::Key::Left, SF::Keyboard::Key::Right
          if proxy.wants_arrow_keys?
            # FullEdit mode: arrows go to TextInput for cursor movement
            return true if proxy.on_key_down(key, control, shift)
          end
          # QuickEntry mode: fall through to grid navigation below
        when SF::Keyboard::Key::Tab
          # Don't forward Tab — let VirtualMatrix handle it (or pass to FocusManager)
        when SF::Keyboard::Key::Enter, SF::Keyboard::Key::Space
          # Forward to proxy first (TextInput handles Enter for mode switching)
          if proxy.on_key_down(key, control, shift)
            return true
          end
          # Fallback: trigger click for Button/Checkbox-like widgets
          proxy.trigger_click
          return true
        else
          # Forward everything else (Escape, Backspace, Delete, Home, End, etc.)
          return true if proxy.on_key_down(key, control, shift)
        end
      end

      # Grid navigation
      case key
      when SF::Keyboard::Key::Tab
        false  # Fall through to FocusManager
      when SF::Keyboard::Key::Up
        move_cursor(:up, control, shift)
        snap_to_cursor
        update_cell_states
        mark_needs_render
        {% if flag?(:CURSOR_PERF) %}
          _kd_ms = (Time.monotonic - _kd_start).total_milliseconds
          File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "KEY_UP: #{_kd_ms.round(2)}ms cursor=#{@cursor_rc} scroll=#{@scroll_offset.y.round(1)} active_cells=#{@active_cells.size} rows=#{@rows} cols=#{@cols}" }
        {% end %}
        true
      when SF::Keyboard::Key::Down
        move_cursor(:down, control, shift)
        snap_to_cursor
        update_cell_states
        mark_needs_render
        {% if flag?(:CURSOR_PERF) %}
          _kd_ms = (Time.monotonic - _kd_start).total_milliseconds
          File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "KEY_DOWN: #{_kd_ms.round(2)}ms cursor=#{@cursor_rc} scroll=#{@scroll_offset.y.round(1)} active_cells=#{@active_cells.size} rows=#{@rows} cols=#{@cols}" }
        {% end %}
        true
      when SF::Keyboard::Key::Left
        move_cursor(:left, control, shift)
        snap_to_cursor
        update_cell_states
        mark_needs_render
        true
      when SF::Keyboard::Key::Right
        move_cursor(:right, control, shift)
        snap_to_cursor
        update_cell_states
        mark_needs_render
        true
      when SF::Keyboard::Key::Home
        move_cursor(:home, control, shift)
        snap_to_cursor
        update_cell_states
        mark_needs_render
        true
      when SF::Keyboard::Key::End
        move_cursor(:end, control, shift)
        snap_to_cursor
        update_cell_states
        mark_needs_render
        true
      else
        false
      end
    end

    def on_text_input(char : Char) : Bool
      # Snap to cursor first — if cell was off-screen, this recreates it
      # and re-establishes proxy focus via update_visible_cells
      snap_to_cursor(for_edit: true)

      # Proxy focus forwarding: forward text to the proxy-focused cell widget
      if proxy = @proxy_focused_widget
        proxy.on_text_input(char)
        return true
      end

      false
    end
  end
end
