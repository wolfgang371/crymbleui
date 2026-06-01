require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"

module CrymbleUI
  # Edit mode for TextInput (Excel-like behavior)
  enum TextInputMode
    QuickEntry # Arrows move focus, typing replaces content
    FullEdit   # Arrows move cursor, Enter/Esc exits
  end

  # Events fired by TextInput for richer interaction
  enum TextInputEvent
    Change    # Text changed (each keystroke)
    Submit    # Enter pressed (confirm)
    Cancel    # Escape pressed (abort)
    Blur      # Focus lost
    ArrowUp   # Up arrow pressed (for parent navigation)
    ArrowDown # Down arrow pressed (for parent navigation)
  end

  # TextInput widget for single-line text entry
  #
  # ## Usage
  #
  # ```
  # text_input(placeholder: "Username") { |v| @username = v }
  # text_input(id: "email", width: 200.0, value: @email) { |v| @email = v }
  # ```
  class TextInput < Widget
    include PrimitiveBuilder
    include FontScalable

    # Layout constants
    BORDER_WIDTH = 1.0
    CURSOR_WIDTH = 1.0

    # Cursor blink interval (Windows standard)
    CURSOR_BLINK_INTERVAL = 530.milliseconds

    # Double-click detection threshold
    DOUBLE_CLICK_THRESHOLD_MS = 300

    # Current text value
    @value : String

    def value : String
      @value
    end

    def value=(v : String)
      @value = v
      # Clamp cursor position to valid range
      @cursor_pos = @cursor_pos.clamp(0, @value.size)
      mark_needs_render
    end

    # Display-only prefix drawn at the cell's left edge before the
    # editable value. Mirror of CrymbleUI::ComboBox's "»value" chrome,
    # but available on any TextInput. NEVER appears in @value, the
    # cursor, or selection — it occupies its own rendered width and the
    # editable text starts after it. Empty string (the default) means
    # no prefix is drawn and the widget behaves exactly as before.
    render_property prefix : String

    # Placeholder text (shown when value is empty)
    render_property placeholder : String

    # Visual properties
    render_property text_color : Color
    render_property background_color : Color
    render_property border_color : Color
    render_property focused_border_color : Color
    render_property placeholder_color : Color
    layout_property padding : Float64

    # Explicit width (nil = fill available space)
    @explicit_width : Float64?

    # Cursor position (index into value string)
    @cursor_pos : Int32 = 0

    # Selection anchor (start of selection, nil = no selection)
    # Selection range is between @selection_anchor and @cursor_pos
    @selection_anchor : Int32? = nil

    # Selection highlight color (dynamic - must follow theme changes)

    # QuickEntry mode background tint (subtle cream to distinguish from FullEdit)


    # Cursor blink state
    reconcile_property cursor_visible : Bool = true
    @blink_timer_id : Int32? = nil

    # Edit mode state (Excel-like behavior)
    # FullEdit = normal text input (Enter submits, arrows move cursor)
    # QuickEntry = grid/list navigation (Enter enters edit, arrows navigate)
    reconcile_property edit_mode : TextInputMode = TextInputMode::FullEdit
    @default_mode : TextInputMode = TextInputMode::FullEdit  # Initial mode (for focus reset)
    reconcile_property pending_replace : Bool = false # Set to true on focus; first keystroke replaces content

    # Value saved on focus for undo on Escape
    reconcile_property value_on_focus : String? = nil

    # Double-click detection
    @last_click_time : Time::Instant = Time.instant - 1.hour

    # Does this widget want to consume arrow keys?
    # In FullEdit mode, arrows move cursor; in QuickEntry, arrows should navigate focus
    def wants_arrow_keys? : Bool
      @edit_mode == TextInputMode::FullEdit
    end

    # Track if we entered FullEdit from QuickEntry (for Enter key behavior)
    @was_quick_entry : Bool = false

    # Enter FullEdit mode (double-click or Enter in QuickEntry)
    def enter_edit_mode
      @was_quick_entry = @edit_mode == TextInputMode::QuickEntry
      @edit_mode = TextInputMode::FullEdit
      @pending_replace = false
    end

    # Exit FullEdit mode (Enter or Esc in FullEdit)
    def exit_edit_mode
      @edit_mode = @default_mode
      @was_quick_entry = false
    end

    # On-change callback (simple value change)
    @on_change : Proc(String, Nil)?

    # On-event callback (richer interaction: Change, Submit, Cancel)
    @on_event : Proc(String, TextInputEvent, Nil)?

    # Horizontal arrow intercept: called before Left/Right is processed.
    # Bool param: true=Right, false=Left. Return true to consume (TextInput won't process).
    property on_horizontal_arrow : Proc(Bool, Bool)?

    # Vertical arrow intercept: called before Up/Down is processed.
    # Bool param: true=Down, false=Up. Return true to consume (TextInput won't process).
    property on_vertical_arrow : Proc(Bool, Bool)?

    # Setter for on_event (allows parent widgets like ComboBox to set it)
    def on_event=(callback : Proc(String, TextInputEvent, Nil)?)
      @on_event = callback
    end

    # Primary constructor - accepts optional on_change Proc
    def initialize(
      value : String = "",
      id : String? = nil,
      width : Float64? = nil,
      @placeholder : String = "",
      @prefix : String = "",
      font_scale : Int32 = 0,
      @text_color : Color = Theme.current.input_text,
      @background_color : Color = Theme.current.input_background,
      @border_color : Color = Theme.current.input_border,
      @focused_border_color : Color = Theme.current.input_border_focused,
      @placeholder_color : Color = Theme.current.input_placeholder,
      @padding : Float64 = 4.0,
      mode : TextInputMode = TextInputMode::FullEdit,
      on_event : Proc(String, TextInputEvent, Nil)? = nil,
      on_change : Proc(String, Nil)? = nil,
    )
      @font_scale = font_scale
      super(id: id)
      @value = value
      @explicit_width = width
      @cursor_pos = value.size # Start cursor at end
      @edit_mode = mode
      @default_mode = mode
      @on_change = on_change
      @on_event = on_event
    end

    # Convenience constructor for block syntax: TextInput.new { |value| handler }
    def self.new(
      value : String = "",
      id : String? = nil,
      width : Float64? = nil,
      placeholder : String = "",
      prefix : String = "",
      font_scale : Int32 = 0,
      text_color : Color = Theme.current.input_text,
      background_color : Color = Theme.current.input_background,
      border_color : Color = Theme.current.input_border,
      focused_border_color : Color = Theme.current.input_border_focused,
      placeholder_color : Color = Theme.current.input_placeholder,
      padding : Float64 = 4.0,
      mode : TextInputMode = TextInputMode::FullEdit,
      on_event : Proc(String, TextInputEvent, Nil)? = nil,
      &block : String -> Nil
    )
      new(value, id, width, placeholder, prefix, font_scale, text_color, background_color, border_color, focused_border_color, placeholder_color, padding, mode, on_event, on_change: block)
    end

    # Override label for path_id generation
    def label : String?
      "text_input"
    end

    # TextInput can receive keyboard focus
    def focusable? : Bool
      true
    end

    def preferred_cursor(point : Vec2) : CursorType?
      CursorType::Text
    end

    # Copy state from old widget during reconciliation
    # Preserves cursor position, selection (with clamping), and restarts timer
    def copy_state_from(old_widget : Widget)
      auto_copy_reconcile_properties(old_widget)
      super

      return unless old_widget.is_a?(TextInput)
      old = old_widget.as(TextInput)

      # Clamp cursor_pos to new value length (value may have changed during rebuild)
      @cursor_pos = old.@cursor_pos.clamp(0, @value.size)

      # Clamp selection anchor too
      if anchor = old.@selection_anchor
        @selection_anchor = anchor.clamp(0, @value.size)
      end

      # Restart blink timer if focused (timer was on old widget instance)
      start_cursor_blink if focused?
    end

    # === SELECTION HELPERS ===

    # Check if there's an active selection
    def has_selection? : Bool
      !@selection_anchor.nil?
    end

    # Get the ordered selection range (start, end)
    # Returns nil if no selection
    def selection_range : Tuple(Int32, Int32)?
      anchor = @selection_anchor
      return nil unless anchor
      if anchor <= @cursor_pos
        {anchor, @cursor_pos}
      else
        {@cursor_pos, anchor}
      end
    end

    # Get the selected text
    def selected_text : String
      range = selection_range
      return "" unless range
      @value[range[0]...range[1]]
    end

    # Delete the selected text and update cursor
    private def delete_selection
      range = selection_range
      return unless range
      @value = @value[0...range[0]] + @value[range[1]..]
      @cursor_pos = range[0]
      clear_selection
      notify_change
    end

    # Clear the selection
    private def clear_selection
      @selection_anchor = nil
    end

    # Start or extend selection from current position
    private def start_selection_if_needed
      @selection_anchor = @cursor_pos if @selection_anchor.nil?
    end

    # Measure text input size
    def measure(constraints : BoxConstraints) : Size
      # Height: tight constraints → fill exactly; loose → natural, clamped to max
      height = font_size + (@padding * 2) + (BORDER_WIDTH * 2)
      if constraints.min_height == constraints.max_height && constraints.max_height.finite?
        height = constraints.max_height  # Tight: fill cell (e.g., merged VirtualMatrix cells)
      elsif constraints.max_height.finite?
        height = Math.min(height, constraints.max_height)  # Loose: clamp down only
      end

      # Width: prefer explicit, but always respect constraint max
      width = @explicit_width || constraints.max_width
      # Clamp to constraint (tight constraints must be respected)
      width = Math.min(width, constraints.max_width) if constraints.max_width.finite?
      # Fallback if still infinite
      width = 200.0 if !width.finite?

      constraints.constrain(Size.new(width, height))
    end

    # Layout the text input
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)
    end

    # Generate primitives for rendering
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      # Determine border color based on focus state
      current_border_color = effectively_focused? ? @focused_border_color : @border_color

      # Local bounds rect
      local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

      # Inner content area
      content_x = BORDER_WIDTH + @padding
      content_y = BORDER_WIDTH + @padding
      content_width = bounds.width - (BORDER_WIDTH + @padding) * 2
      content_height = bounds.height - (BORDER_WIDTH + @padding) * 2

      # Display-only prefix — drawn at the left edge in @text_color, never
      # part of the editable value. After drawing, shift content_x by the
      # rendered prefix width so the value text / cursor / selection all
      # auto-align past the prefix (every downstream calculation uses
      # content_x as the anchor, so a single shift here propagates).
      prefix_width = @prefix.empty? ? 0.0 : measure_text(@prefix, font_size).width

      # Text to display (value or placeholder)
      display_empty = @value.empty?
      display_text = display_empty ? @placeholder : @value
      display_color = display_empty ? @placeholder_color : @text_color

      # Text position — vertically centered in content area
      # At natural height content_h ≈ font_size so offset ≈ 0 (no-op).
      # In tall merged cells, text centers properly and scrolls out
      # when the cell shrinks behind a sticky row header.
      text_y = content_y + (content_height - font_size) / 2.0
      prefix_position = Vec2.new(content_x, text_y)
      content_x = content_x + prefix_width
      text_position = Vec2.new(content_x, text_y)

      primitives do
        fill_rect(local_bounds, @background_color)

        # Draw border as 4 filled rectangles (avoids SFML outline_thickness clipping)
        # Drawn INSIDE bounds for pixel-perfect alignment
        fill_rect(Rect.new(0.0, 0.0, bounds.width, BORDER_WIDTH), current_border_color)                          # Top
        fill_rect(Rect.new(0.0, bounds.height - BORDER_WIDTH, bounds.width, BORDER_WIDTH), current_border_color) # Bottom
        fill_rect(Rect.new(0.0, 0.0, BORDER_WIDTH, bounds.height), current_border_color)                         # Left
        fill_rect(Rect.new(bounds.width - BORDER_WIDTH, 0.0, BORDER_WIDTH, bounds.height), current_border_color) # Right

        # Draw prefix (if any) before the value/cursor/selection area.
        draw_text(@prefix, prefix_position, @text_color, @font_scale) unless @prefix.empty?

        # Draw selection highlight (before text so it's behind)
        # Show selection for: actual selection OR pending_replace (all text will be replaced)
        show_selection = has_selection? || (@pending_replace && effectively_focused?)
        if !display_empty && show_selection
          # For pending_replace: select all text; otherwise use actual selection
          sel_start, sel_end = if has_selection?
                                 range = selection_range
                                 range ? range : {0, 0}
                               else
                                 {0, @value.size} # Select all for pending_replace
                               end
          # Calculate x positions for selection start and end
          sel_start_x = content_x + measure_text(@value[0...sel_start], font_size).width
          sel_end_x = content_x + measure_text(@value[0...sel_end], font_size).width
          sel_width = sel_end_x - sel_start_x
          if sel_width > 0
            sel_rect = Rect.new(sel_start_x, text_y, sel_width, font_size)
            fill_rect(sel_rect, Theme.current.input_selection)
          end
        end

        # Draw text (or placeholder)
        unless display_text.empty?
          draw_text(display_text, text_position, display_color, @font_scale)
        end

        # Draw cursor (only when focused and visible)
        if effectively_focused? && @cursor_visible && !display_empty
          # Calculate cursor x position based on text before cursor
          text_before_cursor = @value[0...@cursor_pos]
          cursor_x_offset = measure_text(text_before_cursor, font_size).width
          cursor_x = content_x + cursor_x_offset

          # Cursor line
          cursor_rect = Rect.new(cursor_x, text_y, CURSOR_WIDTH, font_size)
          fill_rect(cursor_rect, @text_color)
        elsif effectively_focused? && @cursor_visible && display_empty
          # Cursor at start when empty
          cursor_rect = Rect.new(content_x, text_y, CURSOR_WIDTH, font_size)
          fill_rect(cursor_rect, @text_color)
        end
      end
    end

    # === FOCUS HANDLING ===

    # Called when widget gains focus
    def on_focus
      @cursor_visible = true
      @edit_mode = @default_mode
      @pending_replace = @default_mode == TextInputMode::QuickEntry  # Only in QuickEntry mode
      @value_on_focus = @value # Save for undo on Escape
      @was_quick_entry = false
      start_cursor_blink
      mark_needs_render
    end

    # Called when widget loses focus
    def on_blur
      stop_cursor_blink
      @cursor_visible = false
      @edit_mode = @default_mode
      @was_quick_entry = false
      clear_selection
      mark_needs_render
      # Fire Blur event so parent widgets (e.g., ComboBox) can respond
      @on_event.try &.call(@value, TextInputEvent::Blur)
    end

    # === PROXY FOCUS (for VirtualMatrix cell hosting) ===

    # Activate proxy focus — set up cursor, blink, and QuickEntry state
    def activate_proxy_focus
      super
      @cursor_visible = true
      @value_on_focus = @value
      start_cursor_blink
      self.pending_replace = true if @edit_mode == TextInputMode::QuickEntry
    end

    # Deactivate proxy focus — stop cursor blink, clear selection
    def deactivate_proxy_focus
      super
      stop_cursor_blink
      @cursor_visible = false
      @selection_anchor = nil
    end

    # Start cursor blinking timer
    private def start_cursor_blink
      stop_cursor_blink # Clear any existing timer
      @blink_timer_id = schedule_timer(CURSOR_BLINK_INTERVAL, repeating: true) do
        @cursor_visible = !@cursor_visible
        mark_needs_render
      end
    end

    # Stop cursor blinking timer
    private def stop_cursor_blink
      if timer_id = @blink_timer_id
        cancel_timer(timer_id)
        @blink_timer_id = nil
      end
    end

    # === KEYBOARD INPUT ===

    # Handle text input (printable characters)
    def on_text_input(char : Char)
      # In QuickEntry mode, first keystroke replaces entire content
      if @edit_mode == TextInputMode::QuickEntry && @pending_replace
        @value = char.to_s
        @cursor_pos = 1
        @pending_replace = false
        clear_selection
      else
        # Delete selection first if any
        if has_selection?
          delete_selection
        end

        # Insert character at cursor position
        @value = @value[0...@cursor_pos] + char.to_s + @value[@cursor_pos..]
        @cursor_pos += 1
      end

      # Reset cursor visibility on input
      @cursor_visible = true
      restart_cursor_blink

      notify_change
      mark_needs_render
    end

    # Public method to insert a character programmatically
    # Used by ComboBox to insert initial typed character after expand
    def insert_char(char : Char)
      # Insert at cursor position (no QuickEntry replacement)
      @value = @value[0...@cursor_pos] + char.to_s + @value[@cursor_pos..]
      @cursor_pos += 1

      notify_change
      mark_needs_render
    end

    # Handle key down events
    def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
      # === CLIPBOARD OPERATIONS ===
      # Ctrl+C or Ctrl+Insert = Copy
      if (control && key == SF::Keyboard::Key::C) || (control && key == SF::Keyboard::Key::Insert)
        copy_selection
        return true
      end

      # Ctrl+X or Shift+Delete = Cut
      if (control && key == SF::Keyboard::Key::X) || (shift && key == SF::Keyboard::Key::Delete)
        cut_selection
        return true
      end

      # Ctrl+V or Shift+Insert = Paste
      if (control && key == SF::Keyboard::Key::V) || (shift && key == SF::Keyboard::Key::Insert)
        paste_clipboard
        return true
      end

      # Ctrl+A = Select All
      if control && key == SF::Keyboard::Key::A
        select_all
        return true
      end

      case key
      when SF::Keyboard::Key::Enter
        if @edit_mode == TextInputMode::QuickEntry && @value == @value_on_focus
          # QuickEntry with no change: Enter switches to FullEdit mode for editing
          enter_edit_mode
          true
        elsif @edit_mode == TextInputMode::QuickEntry
          # QuickEntry with changed content: let parent handle (commit + stay in place)
          false
        else
          # FullEdit: Enter fires Submit and releases proxy focus
          exit_edit_mode if @was_quick_entry
          notify_submit
          deactivate_proxy_focus
          false # let parent handle (commit)
        end
      when SF::Keyboard::Key::Backspace
        if has_selection?
          delete_selection
          reset_cursor_blink
          mark_needs_render
        elsif @cursor_pos > 0
          @value = @value[0...(@cursor_pos - 1)] + @value[@cursor_pos..]
          @cursor_pos -= 1
          reset_cursor_blink
          notify_change
          mark_needs_render
        end
        @pending_replace = false # Any editing clears pending replace
        true
      when SF::Keyboard::Key::Delete
        if has_selection?
          delete_selection
          reset_cursor_blink
          mark_needs_render
        elsif @cursor_pos < @value.size
          @value = @value[0...@cursor_pos] + @value[(@cursor_pos + 1)..]
          reset_cursor_blink
          notify_change
          mark_needs_render
        end
        @pending_replace = false # Any editing clears pending replace
        true
      when SF::Keyboard::Key::Left
        # Let parent intercept (e.g., ComboBoxPopup closes on Left/Right)
        if @on_horizontal_arrow.try(&.call(false))
          return false
        end
        # In QuickEntry mode, let FocusManager handle arrow navigation
        return false if @edit_mode == TextInputMode::QuickEntry && !shift

        if shift
          # Extend selection left
          start_selection_if_needed
          if @cursor_pos > 0
            @cursor_pos -= 1
            reset_cursor_blink
            mark_needs_render
          end
        else
          # Move cursor left, clear selection
          if has_selection?
            # Move to start of selection
            range = selection_range
            @cursor_pos = range[0] if range
            clear_selection
          elsif @cursor_pos > 0
            @cursor_pos -= 1
          end
          reset_cursor_blink
          mark_needs_render
        end
        true
      when SF::Keyboard::Key::Right
        # Let parent intercept (e.g., ComboBoxPopup closes on Left/Right)
        if @on_horizontal_arrow.try(&.call(true))
          return false
        end
        # In QuickEntry mode, let FocusManager handle arrow navigation
        return false if @edit_mode == TextInputMode::QuickEntry && !shift

        if shift
          # Extend selection right
          start_selection_if_needed
          if @cursor_pos < @value.size
            @cursor_pos += 1
            reset_cursor_blink
            mark_needs_render
          end
        else
          # Move cursor right, clear selection
          if has_selection?
            # Move to end of selection
            range = selection_range
            @cursor_pos = range[1] if range
            clear_selection
          elsif @cursor_pos < @value.size
            @cursor_pos += 1
          end
          reset_cursor_blink
          mark_needs_render
        end
        true
      when SF::Keyboard::Key::Up
        # Let parent intercept (e.g., type-to-filter ComboBox closes on Up/Down)
        if @on_vertical_arrow.try(&.call(false))
          return false
        end
        # Always fire ArrowUp event for parent widgets (e.g., ComboBoxPopup item navigation)
        notify_arrow_up

        # In QuickEntry mode, let FocusManager handle navigation
        return false if @edit_mode == TextInputMode::QuickEntry

        # In FullEdit mode, Up moves cursor to start (like Home)
        clear_selection
        @cursor_pos = 0
        reset_cursor_blink
        mark_needs_render
        true
      when SF::Keyboard::Key::Down
        # Let parent intercept (e.g., type-to-filter ComboBox closes on Up/Down)
        if @on_vertical_arrow.try(&.call(true))
          return false
        end
        # Always fire ArrowDown event for parent widgets (e.g., ComboBoxPopup item navigation)
        notify_arrow_down

        # In QuickEntry mode, let FocusManager handle navigation
        return false if @edit_mode == TextInputMode::QuickEntry

        # In FullEdit mode, Down moves cursor to end (like End)
        clear_selection
        @cursor_pos = @value.size
        reset_cursor_blink
        mark_needs_render
        true
      when SF::Keyboard::Key::Home
        if shift
          # Extend selection to start
          start_selection_if_needed
          @cursor_pos = 0
        else
          clear_selection
          @cursor_pos = 0
        end
        reset_cursor_blink
        mark_needs_render
        true
      when SF::Keyboard::Key::End
        if shift
          # Extend selection to end
          start_selection_if_needed
          @cursor_pos = @value.size
        else
          clear_selection
          @cursor_pos = @value.size
        end
        reset_cursor_blink
        mark_needs_render
        true
      when SF::Keyboard::Key::Escape
        # Check if value was modified since focus
        value_changed = @value_on_focus && @value != @value_on_focus

        # Undo any changes made
        if value_changed
          if saved_value = @value_on_focus
            @value = saved_value
            @cursor_pos = @value.size
            clear_selection
          end
        end

        if @was_quick_entry
          # Came from QuickEntry: exit back to QuickEntry mode, stay focused
          exit_edit_mode
          @pending_replace = true
          notify_cancel
          mark_needs_render
        else
          # Default FullEdit mode or QuickEntry mode: release focus
          notify_cancel
          release_focus
        end
        true
      else
        false # Not handled
      end
    end

    # === CLIPBOARD OPERATIONS ===

    # Copy selected text to clipboard
    private def copy_selection
      return unless has_selection?
      Widget.clipboard.string = selected_text
    end

    # Cut selected text to clipboard
    private def cut_selection
      return unless has_selection?
      Widget.clipboard.string = selected_text
      delete_selection
      reset_cursor_blink
      mark_needs_render
    end

    # Paste from clipboard at cursor position
    private def paste_clipboard
      text = Widget.clipboard.string
      return if text.empty?

      # Delete selection first if any
      if has_selection?
        delete_selection
      end

      # Insert pasted text at cursor
      @value = @value[0...@cursor_pos] + text + @value[@cursor_pos..]
      @cursor_pos += text.size
      reset_cursor_blink
      notify_change
      mark_needs_render
    end

    # Select all text
    private def select_all
      return if @value.empty?
      @selection_anchor = 0
      @cursor_pos = @value.size
      mark_needs_render
    end

    # Reset cursor to visible state and restart blink timer
    private def reset_cursor_blink
      @cursor_visible = true
      restart_cursor_blink
    end

    # Restart the cursor blink timer
    private def restart_cursor_blink
      stop_cursor_blink
      start_cursor_blink
    end

    # Notify on_change callback and fire Change event
    private def notify_change
      @on_change.try &.call(@value)
      @on_event.try &.call(@value, TextInputEvent::Change)
    end

    # Fire Submit event (Enter pressed to confirm)
    private def notify_submit
      @on_event.try &.call(@value, TextInputEvent::Submit)
    end

    # Fire Cancel event (Escape pressed to abort)
    private def notify_cancel
      @on_event.try &.call(@value, TextInputEvent::Cancel)
    end

    # Fire ArrowUp event (Up arrow pressed)
    private def notify_arrow_up
      @on_event.try &.call(@value, TextInputEvent::ArrowUp)
    end

    # Fire ArrowDown event (Down arrow pressed)
    private def notify_arrow_down
      @on_event.try &.call(@value, TextInputEvent::ArrowDown)
    end

    # === MOUSE INPUT ===

    # Click to focus and clear selection, detect double-click
    def on_click
      now = Time.instant

      # Check for double-click
      if (now - @last_click_time).total_milliseconds < DOUBLE_CLICK_THRESHOLD_MS
        on_double_click
        @last_click_time = Time.instant - 1.hour # Reset to far past to prevent triple-click triggering
      else
        clear_selection
        request_focus
        @last_click_time = now
      end
    end

    # Double-click to enter FullEdit mode
    def on_double_click
      enter_edit_mode
      mark_needs_render
    end
  end
end
