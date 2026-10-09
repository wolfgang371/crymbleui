module CrymbleUI
  class VirtualMatrix < Widget
    # === SCROLL HANDLING ===

    # The wheel, in the input frame; returns what the grid did NOT take, in that frame (ScrollView#on_mouse_wheel
    # states the rule): an axis it moved on is taken, an axis it cannot move on goes on to the next scroller.
    # Under shift it reads delta.y as x and ignores delta.x, which therefore goes on untouched.
    def on_mouse_wheel(delta : Vec2, point : Vec2, shift : Bool = false) : Vec2
      return delta unless absolute_bounds.contains_point(point)

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
      end

      if shift
        Vec2.new(delta.x, new_offset.x == old_offset.x ? delta.y : 0.0)
      else
        Vec2.new(new_offset.x == old_offset.x ? delta.x : 0.0, new_offset.y == old_offset.y ? delta.y : 0.0)
      end
    end

    # === MOUSE HANDLING ===

    # NO screen→content conversion here any more: every point a widget is handed already arrives
    # in the widget's own space (App converts once, via Widget#to_content — see
    # docs/RENDERING_LAWS.md § Coordinate spaces). This file used to accumulate
    # ancestor ScrollView offsets itself; keeping that would convert twice and land the cursor on
    # the wrong cell.

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

      # a content point is where the grid PAINTS content: at the whole scroll (painted_scroll)
      whole = painted_scroll
      local_x = in_sticky_col ? data_x : data_x + whole.x
      local_y = in_sticky_row ? data_y : data_y + whole.y
      return nil if local_x < 0 || local_y < 0

      # O(log N) binary search on the placed cumulative sizes - where cells are placed
      col = placed_col_cum.bsearch_index { |p| p > local_x.to_i32 } # snap-exempt: content-space bsearch key
      return nil unless col # beyond all columns
      row = placed_row_cum.bsearch_index { |p| p > local_y.to_i32 } # snap-exempt: content-space bsearch key
      return nil unless row # beyond all rows
      {row - 1, col - 1}
    end

    # The scrollbar area goes to the ScrollView; every other point inside is the grid's own. Cell widgets are
    # direct children, yet never hit: the grid takes every press, click, wheel and drag over a cell and forwards
    # what a cell acts on through proxy focus (trigger_click, on_mouse_up, on_key_down) - a cell hit directly
    # would steal the focus from the grid.
    def hit_test(point : Vec2) : Widget?
      abs = absolute_bounds
      return nil unless abs.contains_point(point)

      # Check ScrollView scrollbar area FIRST - delegate if it's a scrollbar hit
      if sv = @content_scroll_view
        if sv.point_in_scrollbar_area?(point)
          return sv
        end
      end

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
    # Would content sizing overwrite a drag on this line? While the mode is on, of every line —
    # `interactive_resize`'s own rationale ("a drag would only be overwritten by the next
    # re-measure, so offering it is a lie"), and under shrink-only sizing that is true of pinned
    # lines too: they are measured like any other, they simply never grow. An earlier version
    # exempted them, which was correct only while the mode did not size them at all.
    #
    # The refusal is the LIBRARY's, not the consumer's: `interactive_resize` stays a separate hard
    # veto for a consumer that wants no resizing whatsoever.
    #
    # DECIDED 2026-09-13, do not re-propose: letting a drag mark that line "manual" and exempting
    # it from sizing thereafter was offered and DECLINED. It would lift this refusal, at the price
    # of a per-line manual flag to persist and a mode that silently stops following some lines.
    # What made the refusal hurt was never the refusal — it was that a pinned line could not grow
    # and a spanning cell sized nothing, so a cut label had no way out at all. Both are fixed
    # (bounded pinned growth, and spans sizing the lines they cover), and the mode is a toggle:
    # switch it off and every line drags again.
    private def line_is_content_sized?(axis : ResizeAxis, index : Int32) : Bool
      @auto_size
    end

    private def detect_resize_edge(point : Vec2) : Tuple(ResizeAxis, Int32)?
      # One gate for the whole gesture: this is the only route to both `on_mouse_down`'s resize
      # start and `preferred_cursor`'s handle, so refusing here refuses both.
      return nil unless interactive_resize
      sx = point.x - absolute_bounds.x
      sy = point.y - absolute_bounds.y

      ruler_h = ruler_row_height_pixels
      ruler_w = ruler_col_width_pixels

      # A border is a line's far edge where it is painted (painted_col / painted_row): a sticky line's in its
      # band, a scrolling line's only where it shows past the band.
      if show_rulers && sy < ruler_h
        band_right = ruler_w + sticky_col_width_pixels
        (0...@cols).each do |c|
          x, pitch = painted_col(c)
          edge = x + pitch
          next if c >= sticky_col_count && edge < band_right
          if (sx - edge).abs < resize_tolerance
            return nil if line_is_content_sized?(ResizeAxis::Col, c)
            return {ResizeAxis::Col, c}
          end
          break if c >= sticky_col_count && edge > sx + resize_tolerance
        end
      end

      if show_rulers && sx < ruler_w
        band_bottom = ruler_h + sticky_row_height_pixels
        (0...@rows).each do |r|
          y, pitch = painted_row(r)
          edge = y + pitch
          next if r >= sticky_row_count && edge < band_bottom
          if (sy - edge).abs < resize_tolerance
            return nil if line_is_content_sized?(ResizeAxis::Row, r)
            return {ResizeAxis::Row, r}
          end
          break if r >= sticky_row_count && edge > sy + resize_tolerance
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

    def on_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left) : Bool
      bring_containing_panel_to_front
      request_focus
      # Every press, whatever the button or the place: its release must put back what it found.
      @source_before_press = @drag_source_provisional ? nil : @drag_source_cell
      @press_in_progress = true
      # Right-click: move cursor to clicked cell, then bubble for context menu
      if button == MouseButton::Right
        content_point = point
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

      content_point = point

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

        # Double-click on same cell: first give on_cell_activate callback a
        # chance (e.g. drill-down into aggregate cells); if it returns true the
        # activation is handled and proxy forwarding is skipped. Otherwise fall
        # back to proxy forwarding (opens ComboBox, edit mode, etc.).
        if double_click?(cell)
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
          @last_click_time = Time.instant
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

      content_x = point.x
      content_y = point.y
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

    # A double-click OPENS the editor, and it opens with the caret at the end of the value — which
    # in a cell taller than the viewport is off screen, so the cell reads as "not focused" (field
    # report). Scoping the mouse path out was wrong: a single click does put the caret where the
    # user clicked, but the click that OPENS an editor does not.
    def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
      handled = handle_mouse_up(point, button)
      snap_to_caret
      handled
    end

    private def handle_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
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
      # A press that did not become a drag: its candidate goes, the committed source it found comes back.
      end_press(@source_before_press) if @press_in_progress
    end

    # End this instance's press with `source` as the committed drag source. Only the instance holding the
    # press may - the one that saw it, or the one a drag's on_drag_start handed it to: one merely built
    # after it (a click across a rebuild) may just have been handed the host's source by its build.
    private def end_press(source : Tuple(Int32, Int32)?) : Nil
      @press_in_progress = false
      return if source == @drag_source_cell && !@drag_source_provisional
      @drag_source_cell = source
      @drag_source_provisional = false
      mark_drag_overlay_dirty
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

    # Both key entry points wrap their handler so the caret is followed AFTER the editor has moved
    # it. The existing pre-forward `snap_to_cursor` calls stay: they materialise an off-screen cell
    # and re-establish proxy focus, which has to happen before the key is delivered. What they
    # cannot do is see where the caret ends up — the editor has not consumed the key yet — and with
    # cells that can exceed the viewport that is the difference between typing and typing blind.
    # One wrapper each, rather than a call at every forward site: `on_key_down` alone has
    # seven navigation snaps and five proxy forwards, several behind an early `return true`.
    def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
      handled = handle_key_down(key, control, shift, alt)
      snap_to_caret
      handled
    end

    private def handle_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
      {% if flag?(:CURSOR_PERF) %}
        _kd_start = Time.instant
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
          # Every forward below passes `alt` through unchanged. The matrix has no opinion on
          # what a modifier means — that is the editor's to interpret — and dropping it here
          # made a chord that arrives correctly all the way from the renderer
          # (dispatch_key -> handle_key_down -> the focused widget) reach the cell as a bare
          # key, which reads as a broken widget rather than as broken routing.
          proxy.on_key_down(key, control, shift, alt)
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
            return true if proxy.on_key_down(key, control, shift, alt)
          end
          clear_proxy_focus
        when SF::Keyboard::Key::Tab
          # Don't forward Tab to the proxy — fall through (no return) to the
          # grid-nav Tab case below, which round-robins the cell cursor.
        when SF::Keyboard::Key::Enter, SF::Keyboard::Key::Space
          # A MODIFIED Enter on a multi-line text editor is an AUTHORING chord, not an
          # activation, so the editor gets first refusal and Alt/Ctrl/Shift+Enter inserts a
          # break instead of drilling. Gated three ways, each for its own reason: on Enter alone,
          # because this branch also handles Space and Ctrl+Space on a Bool cell must still
          # reach on_cell_activate; on the proxy being a TextInput, because ComboBox returns
          # true for Enter (a Ctrl+Enter on a reference cell would silently expand its
          # dropdown instead of drilling); and on that editor actually being multi-line, so
          # a numeric or aggregate cell keeps today's behaviour exactly.
          if key == SF::Keyboard::Key::Enter && (alt || control || shift) &&
             (ti = proxy).is_a?(TextInput) && ti.multiline
            return true if ti.on_key_down(key, control, shift, alt)
          end

          # App-level activation (e.g. drill-down) gets priority over the
          # proxy's default Enter/Space handler. If on_cell_activate returns
          # true, skip proxy forward entirely.
          if @on_cell_activate.try(&.call(cursor_rc))
            return true
          end
          if proxy.on_key_down(key, control, shift, alt)
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
          return true if proxy.on_key_down(key, control, shift, alt)
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
          _kd_ms = (Time.instant - _kd_start).total_milliseconds
          File.open("/tmp/cursor_perf_tut22.log", "a") { |f| f.puts "KEY_UP: #{_kd_ms.round(2)}ms cursor=#{cursor_rc} scroll=#{scroll_offset.y.round(1)} active_cells=#{@active_cells.size} rows=#{@rows} cols=#{@cols}" }
        {% end %}
        true
      when SF::Keyboard::Key::Down
        move_cursor(:down, control, shift)
        snap_to_cursor
        mark_needs_render
        {% if flag?(:CURSOR_PERF) %}
          _kd_ms = (Time.instant - _kd_start).total_milliseconds
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
      handled = handle_text_input(char)
      snap_to_caret
      handled
    end

    private def handle_text_input(char : Char) : Bool
      # Never reached with an invalidation pending: the matrix raises the input barrier when one is
      # announced (bind_adapter_invalidation), so events queued behind it wait for the frame that
      # flushes it (EventBatch).
      # Snap to cursor first — if cell was off-screen, this recreates it
      # and re-establishes proxy focus via update_visible_cells
      snap_to_cursor(for_edit: true)

      # App-level activation (e.g. drill-down on aggregate cells) takes
      # priority over edit mode. If on_cell_activate returns true, the first
      # typed character opens the drilled view instead of seeding edit text.
      if @on_cell_activate.try(&.call(cursor_rc))
        return true
      end

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
      src = @drag_source_cell || return nil
      adapter = @adapter || return nil
      # Window space (the ghost is drawn by the window): the drag box where it is painted in the matrix
      # (painted_rect - its visible part, a header's as placed), moved to where the matrix itself is painted
      # (it may sit in a scrolled panel). A grid that has placed no cells yet - a rebuild replaced the pressed
      # one and its first layout is still to come - answers with the box's lines, where that layout puts a
      # plain box. Nothing of it painted (a committed source scrolled wholly out) is an EMPTY rect, never nil:
      # nil would make DragManager fall back to the whole matrix's rect.
      origin = viewport_bounds.position
      box = adapter.cell_get_drag_bounding_box(src[0], src[1])
      painted = @active_cells.empty? ? box_lines_rect(box) : painted_rect(box)
      return Rect.new(origin.x, origin.y, 0.0, 0.0) unless painted
      Rect.new(origin.x + painted.x, origin.y + painted.y, painted.width, painted.height)
    end

    # A box's extent by its lines (painted_col / painted_row), in the matrix's own space.
    private def box_lines_rect(box : Region) : Rect
      x, _ = painted_col(box[0][1])
      y, _ = painted_row(box[0][0])
      right = painted_col(box[1][1]).sum
      bottom = painted_row(box[1][0]).sum
      Rect.new(x, y, right - x, bottom - y)
    end

    # Draggable: return data for the cell clicked in on_mouse_down - nothing for a cell the adapter no longer
    # has: DragManager may ask after a data change shrank the grid (a rebuild during the press), and a
    # stale coordinate is no drag.
    def get_drag_data : DragData?
      if src = @drag_source_cell
        if (adapter = @adapter) && adapter_has_cell?(adapter, src)
          name = adapter.cell_get_name(src[0], src[1])
          CellDragData.new(src[0], src[1], name, source_path: drag_path, owner_key: @drag_owner_key)
        end
      end
    end

    # The adapter's CURRENT extent (its scroll order), not this instance's @rows/@cols from its last build.
    private def adapter_has_cell?(adapter, cell : {Int32, Int32}) : Bool
      rows, cols = adapter.get_scrollorder
      cell[0] < rows.size && cell[1] < cols.size
    end

    # Simple ghost: just a themed semi-transparent fill (no border, no text)
    def create_ghost_preview : Widget?
      SimpleGhostWidget.new
    end

    def on_drag_start(data : DragData)
      # A grid that did not see the press - a rebuild replaced the one that did, or the host set a source
      # while the button was held - takes the gesture over: its drag end puts back the committed source it
      # has now (the host's word, as built).
      unless @press_in_progress
        @source_before_press = @drag_source_provisional ? nil : @drag_source_cell
        @press_in_progress = true
      end
      # The drag crossed the threshold — the source is now committed, so its
      # decal may paint (it was provisional through the mouse-down candidate).
      if data.is_a?(CellDragData)
        @drag_source_cell = {data.row, data.col}
      end
      @drag_source_provisional = false
      mark_drag_overlay_dirty
    end

    # A drag ends without a mouse-up, so its press ends here. Dropped nowhere, the committed source the
    # press found comes back; after a drop, rows may have moved and its old place can hold another
    # record - the host re-arms its source through on_cell_drop_handler.
    def on_drag_end(data : DragData, dropped : Bool)
      end_press(dropped ? nil : @source_before_press) if @press_in_progress
      @drag_target_cell = nil
      mark_drag_overlay_dirty
    end

    # DropTarget: a cell of this grid's own, or another owner's where a cross handler takes it. A cell from
    # another grid names a place in THAT grid's data - applied here as a native move it would move this
    # grid's cell at those coordinates.
    def accepts_drop?(data : DragData) : Bool
      data.is_a?(CellDragData) && (own_payload?(data) || (!@cross_drop_handler.nil? && !data.owner_key.nil?))
    end

    # Whether a cell payload is this grid's own: both tagged - the same owner key (the host's claim);
    # neither - the same grid (its path); one tagged, one not - another's.
    private def own_payload?(data : CellDragData) : Bool
      mine = @drag_owner_key
      theirs = data.owner_key
      return mine == theirs if mine && theirs
      mine.nil? && theirs.nil? && data.source_path == drag_path
    end

    # This grid as reconcile identifies it: per ancestor its id, else its index and class among its
    # siblings (reconcile pairs an id-less child by position and type) - the same for the grid a rebuild
    # puts in its place, different for two id-less siblings. A node its parent keeps outside its children
    # (a window overlay, a menu item) has no such index: its instance names it, which a rebuild that
    # migrates it keeps. Walks to the root (O(depth) string building): only an untagged grid asks, per
    # accepts_drop? - a drag move, and once a frame while a drag is over it (DragManager#follow_pointer).
    private def drag_path : String
      segments = [] of String
      node : Widget? = self
      while node
        segments << (node.id || id_less_segment(node))
        node = node.parent
      end
      segments.reverse.join("/")
    end

    private def id_less_segment(node : Widget) : String
      parent = node.parent || return "0:#{node.class.name}"
      index = parent.children.index { |c| c.same?(node) } || return "@#{node.object_id}:#{node.class.name}"
      "#{index}:#{node.class.name}"
    end

    # Disable DragManager's widget-level highlight (we highlight individual cells instead)
    def highlight_opacity : Float64
      0.0
    end

    def on_drop(data : DragData, position : Vec2)
      return unless data.is_a?(CellDragData) && accepts_drop?(data) # one gate, for a direct call too
      return unless target = point_to_cell(position)
      # Another owner's cell: its (row, col) are meaningless here - the app reconstructs the source cell
      # from the payload's owner_key and routes it through its own dispatcher.
      unless own_payload?(data)
        # accepts_drop? let another's cell in only with a handler to take it
        @cross_drop_handler.not_nil!.call(data, target[0], target[1])
        return
      end
      if adapter = @adapter
        new_cursor = adapter.cell_move(data.row, data.col, target[0], target[1])
        set_cursor_from_cell(new_cursor)
        mark_needs_render
        @on_cell_drop_handler.try &.call
      end
    end

    # Also called once a frame while the pointer is still (DragManager#follow_pointer): the overlay
    # re-renders only when the cell under the pointer changed.
    def on_drag_over(data : DragData, position : Vec2)
      cell = point_to_cell(position)
      return if cell == @drag_target_cell
      @drag_target_cell = cell
      mark_drag_overlay_dirty
    end

    def on_drag_leave(data : DragData)
      @drag_target_cell = nil
      mark_drag_overlay_dirty
    end
  end
end
