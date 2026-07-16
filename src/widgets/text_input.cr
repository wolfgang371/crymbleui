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
    Toggle    # Space pressed while `toggle_on_space` is set (e.g. a checkable combo row toggle)
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

    # Current text value — tracked Source for auto-capture in to_primitives
    reactive_property value : String

    # Override the macro-generated setter to also clamp cursor position
    def value=(v : String)
      @value.set(v)
      @cursor_pos.set(cursor_pos.clamp(0, v.size))
    end

    # Display-only prefix drawn at the cell's left edge before the
    # editable value. Mirror of CrymbleUI::ComboBox's "»value" chrome,
    # but available on any TextInput. NEVER appears in @value, the
    # cursor, or selection — it occupies its own rendered width and the
    # editable text starts after it. Empty string (the default) means
    # no prefix is drawn and the widget behaves exactly as before.
    reactive_property prefix : String

    # Placeholder text (shown when value is empty)
    reactive_property placeholder : String

    # Visual properties — theme colors resolve live (nil = follow Theme.current; explicit value wins)
    theme_property text_color, input_text
    theme_property background_color, input_background
    theme_property border_color, input_border
    theme_property focused_border_color, input_border_focused
    theme_property placeholder_color, input_placeholder
    reactive_property padding : Float64, layout: true

    # Explicit width (nil = fill available space)
    @explicit_width : Float64?

    # Cursor position (index into value string)
    reactive_property cursor_pos : Int32 = 0

    # Selection anchor (start of selection, nil = no selection)
    # Selection range is between @selection_anchor and @cursor_pos
    reactive_property selection_anchor : Int32? = nil

    # Selection highlight color (dynamic - must follow theme changes)

    # QuickEntry mode background tint (subtle cream to distinguish from FullEdit)


    # Cursor blink state
    reactive_property cursor_visible : Bool = true, reconcile: true
    @blink_timer_id : Int32? = nil

    # Edit mode state (Excel-like behavior)
    # FullEdit = normal text input (Enter submits, arrows move cursor)
    # QuickEntry = grid/list navigation (Enter enters edit, arrows navigate)
    reactive_property edit_mode : TextInputMode = TextInputMode::FullEdit, reconcile: true
    @default_mode : TextInputMode = TextInputMode::FullEdit  # Initial mode (for focus reset)
    reactive_property pending_replace : Bool = false, reconcile: true # Set to true on focus; first keystroke replaces content

    # Value saved on focus for undo on Escape
    reactive_property value_on_focus : String? = nil, reconcile: true

    # Double-click detection
    @last_click_time : Time::Instant = Time.instant - 1.hour

    # Does this widget want to consume arrow keys?
    # In FullEdit mode, arrows move cursor; in QuickEntry, arrows should navigate focus
    def wants_arrow_keys? : Bool
      edit_mode == TextInputMode::FullEdit
    end

    # Track if we entered FullEdit from QuickEntry (for Enter key behavior)
    @was_quick_entry : Bool = false

    # Enter FullEdit mode (double-click or Enter in QuickEntry)
    def enter_edit_mode
      @was_quick_entry = edit_mode == TextInputMode::QuickEntry
      @edit_mode.set(TextInputMode::FullEdit)
      @pending_replace.set(false)
      # Full-edit (character mode): the caret appears + blinks now.
      @cursor_visible.set(true)
      start_cursor_blink
    end

    # Exit FullEdit mode (Enter or Esc in FullEdit)
    def exit_edit_mode
      @edit_mode.set(@default_mode)
      @was_quick_entry = false
      # Back to cell-nav (QuickEntry): re-arm the fresh "type-to-replace" state so
      # there's no caret (and no blink) until you type again. A default-FullEdit
      # widget stays in character mode.
      if edit_mode == TextInputMode::QuickEntry
        @pending_replace.set(true)
        stop_cursor_blink
      end
    end

    # On-change callback (simple value change)
    @on_change : Proc(String, Nil)?

    # On-event callback (richer interaction: Change, Submit, Cancel)
    @on_event : Proc(String, TextInputEvent, Nil)?

    # Opt-in: when set, a typed space fires a `Toggle` event INSTEAD of inserting a
    # space character. Used by a checkable ComboBoxPopup so Space toggles the
    # highlighted row/header. A space arrives as a TextEntered char (on_text_input),
    # NOT as on_key_down(Space) — and the two SFML events are independent, so the
    # suppression must live here, on the char path. Default false → generic TextInput
    # is unaffected. Trade-off: such a filter can't contain a literal space.
    property toggle_on_space : Bool = false

    # Horizontal arrow intercept: called before Left/Right is processed.
    # Bool param: true=Right, false=Left. Return true to consume: TextInput skips
    # its own processing AND on_key_down reports the key handled, so the renderer's
    # spatial-navigate fallback (FocusManager#navigate on an *unhandled* arrow) is
    # NOT triggered. The intercept owns any resulting movement (e.g. a ComboBox
    # commits the highlight and re-dispatches the arrow to its owning grid).
    property on_horizontal_arrow : Proc(Bool, Bool)?

    # Vertical arrow intercept: called before Up/Down is processed.
    # Bool param: true=Down, false=Up. Return true to consume (same contract as
    # on_horizontal_arrow above).
    property on_vertical_arrow : Proc(Bool, Bool)?

    # Tab intercept: called before Tab/Shift+Tab would cycle focus. Bool param: shift.
    # Return true to consume so FocusManager keeps focus here instead of cycling out
    # (e.g. a ComboBox popup commits the highlight and re-dispatches Tab to its owning
    # focus-scope). Same true-on-consume contract as the arrow intercepts above.
    property on_tab : Proc(Bool, Bool)?

    # Setter for on_event (allows parent widgets like ComboBox to set it)
    def on_event=(callback : Proc(String, TextInputEvent, Nil)?)
      @on_event = callback
    end

    # Primary constructor - accepts optional on_change Proc
    def initialize(
      value : String = "",
      id : String? = nil,
      width : Float64? = nil,
      placeholder : String = "",
      prefix : String = "",
      font_scale : Int32 = 0,
      text_color : Color? = nil,
      background_color : Color? = nil,
      border_color : Color? = nil,
      focused_border_color : Color? = nil,
      placeholder_color : Color? = nil,
      padding : Float64 = 4.0,
      mode : TextInputMode = TextInputMode::FullEdit,
      on_event : Proc(String, TextInputEvent, Nil)? = nil,
      on_change : Proc(String, Nil)? = nil,
    )
      @placeholder = Source(String).new(placeholder)
      @prefix = Source(String).new(prefix)
      @value = Source(String).new(value)
      @cursor_pos = Source(Int32).new(value.size) # Start cursor at end
      @selection_anchor = Source(Int32?).new(nil)
      @padding = Source(Float64).new(padding)
      @text_color = text_color
      @background_color = background_color
      @border_color = border_color
      @focused_border_color = focused_border_color
      @placeholder_color = placeholder_color
      @font_scale.set(font_scale)
      super(id: id)
      @explicit_width = width
      @edit_mode.set(mode)
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
      text_color : Color? = nil,
      background_color : Color? = nil,
      border_color : Color? = nil,
      focused_border_color : Color? = nil,
      placeholder_color : Color? = nil,
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
      @cursor_pos.set(old.cursor_pos.clamp(0, value.size))

      # Clamp selection anchor too
      if anchor = old.selection_anchor
        @selection_anchor.set(anchor.clamp(0, value.size))
      end

      # Restart blink only while a caret is actually shown (actively editing, not
      # the fresh type-to-replace state). A matrix cell is PROXY-focused, so use
      # effectively_focused? (a bare focused? left the caret frozen after a reconcile).
      start_cursor_blink if effectively_focused? && !pending_replace
    end

    # === SELECTION HELPERS ===

    # Check if there's an active selection
    def has_selection? : Bool
      !selection_anchor.nil?
    end

    # Get the ordered selection range (start, end)
    # Returns nil if no selection
    def selection_range : Tuple(Int32, Int32)?
      anchor = selection_anchor
      return nil unless anchor
      if anchor <= cursor_pos
        {anchor, cursor_pos}
      else
        {cursor_pos, anchor}
      end
    end

    # Get the selected text
    def selected_text : String
      range = selection_range
      return "" unless range
      value[range[0]...range[1]]
    end

    # Delete the selected text and update cursor
    private def delete_selection
      range = selection_range
      return unless range
      @value.set(value[0...range[0]] + value[range[1]..])
      @cursor_pos.set(range[0])
      clear_selection
      notify_change
    end

    # Clear the selection
    private def clear_selection
      @selection_anchor.set(nil)
    end

    # Start or extend selection from current position
    private def start_selection_if_needed
      @selection_anchor.set(cursor_pos) if selection_anchor.nil?
    end

    # Measure text input size
    def measure(constraints : BoxConstraints) : Size
      # Height: tight constraints → fill exactly; loose → natural, clamped to max
      height = font_size + (padding * 2) + (BORDER_WIDTH * 2)
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
      current_border_color = effectively_focused? ? focused_border_color : border_color

      # Local bounds rect
      local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

      # Inner content area
      content_x = BORDER_WIDTH + padding
      content_y = BORDER_WIDTH + padding
      content_width = bounds.width - (BORDER_WIDTH + padding) * 2
      content_height = bounds.height - (BORDER_WIDTH + padding) * 2

      # Display-only prefix — drawn at the left edge in @text_color, never
      # part of the editable value. After drawing, shift content_x by the
      # rendered prefix width so the value text / cursor / selection all
      # auto-align past the prefix (every downstream calculation uses
      # content_x as the anchor, so a single shift here propagates).
      prefix_width = prefix.empty? ? 0.0 : measure_text(prefix, font_size).width

      # Text to display (value or placeholder)
      display_empty = value.empty?
      display_text = display_empty ? placeholder : value
      display_color = display_empty ? placeholder_color : text_color

      # Text position — vertically centered in content area
      # At natural height content_h ≈ font_size so offset ≈ 0 (no-op).
      # In tall merged cells, text centers properly and scrolls out
      # when the cell shrinks behind a sticky row header.
      text_y = vcentered_text_y(content_height, font_scale, content_y)
      prefix_position = Vec2.new(content_x, text_y)
      content_x = content_x + prefix_width
      text_position = Vec2.new(content_x, text_y)

      primitives do
        fill_rect(local_bounds, background_color)

        # Draw border as 4 filled rectangles (avoids SFML outline_thickness clipping)
        # Drawn INSIDE bounds for pixel-perfect alignment
        fill_rect(Rect.new(0.0, 0.0, bounds.width, BORDER_WIDTH), current_border_color)                          # Top
        fill_rect(Rect.new(0.0, bounds.height - BORDER_WIDTH, bounds.width, BORDER_WIDTH), current_border_color) # Bottom
        fill_rect(Rect.new(0.0, 0.0, BORDER_WIDTH, bounds.height), current_border_color)                         # Left
        fill_rect(Rect.new(bounds.width - BORDER_WIDTH, 0.0, BORDER_WIDTH, bounds.height), current_border_color) # Right

        # Draw prefix (if any) before the value/cursor/selection area.
        draw_text(prefix, prefix_position, text_color, font_scale) unless prefix.empty?

        # Draw selection highlight (before text so it's behind). Only a REAL
        # selection (full-edit / Ctrl+A) highlights — QuickEntry (cell mode) shows
        # no select-all highlight; typing still overwrites via pending_replace.
        show_selection = has_selection?
        if !display_empty && show_selection
          # For pending_replace: select all text; otherwise use actual selection
          sel_start, sel_end = if has_selection?
                                 range = selection_range
                                 range ? range : {0, 0}
                               else
                                 {0, value.size} # Select all for pending_replace
                               end
          # Calculate x positions for selection start and end
          sel_start_x = content_x + measure_text(value[0...sel_start], font_size).width
          sel_end_x = content_x + measure_text(value[0...sel_end], font_size).width
          sel_width = sel_end_x - sel_start_x
          if sel_width > 0
            sel_rect = Rect.new(sel_start_x, text_y, sel_width, font_size)
            fill_rect(sel_rect, Theme.current.input_selection)
          end
        end

        # Draw text (or placeholder)
        unless display_text.empty?
          draw_text(display_text, text_position, display_color, font_scale)
        end

        # Draw cursor once you're actively entering text (NOT the fresh
        # type-to-replace state). A fresh cursor cell shows no caret — the matrix
        # cell-flash marks it — and the caret appears the moment you type / enter
        # full-edit.
        if effectively_focused? && cursor_visible && !pending_replace && !display_empty
          # Calculate cursor x position based on text before cursor
          text_before_cursor = value[0...cursor_pos]
          cursor_x_offset = measure_text(text_before_cursor, font_size).width
          cursor_x = content_x + cursor_x_offset

          # Cursor line
          cursor_rect = Rect.new(cursor_x, text_y, CURSOR_WIDTH, font_size)
          fill_rect(cursor_rect, text_color)
        elsif effectively_focused? && cursor_visible && !pending_replace && display_empty
          # Cursor at start when empty
          cursor_rect = Rect.new(content_x, text_y, CURSOR_WIDTH, font_size)
          fill_rect(cursor_rect, text_color)
        end
      end
    end

    # === FOCUS HANDLING ===

    # Called when widget gains focus
    def on_focus
      @cursor_visible.set(true)
      @edit_mode.set(@default_mode)
      @pending_replace.set(@default_mode == TextInputMode::QuickEntry)  # Only in QuickEntry mode
      @value_on_focus.set(value) # Save for undo on Escape
      @was_quick_entry = false
      start_cursor_blink
      mark_needs_render
    end

    # Reset the transient edit decoration a (real or proxy) focus left on the cell: stop the
    # caret blink, hide the caret, drop FullEdit back to @default_mode, clear was_quick_entry,
    # and drop any selection. Both on_blur (real focus) and deactivate_proxy_focus (proxy/cell
    # focus) MUST run this so the two focus lifecycles stay in lockstep — their DRIFT (deactivate
    # had silently dropped the mode reset) was the stuck-edit-mode-on-navigation bug.
    private def reset_transient_edit_state
      stop_cursor_blink
      @cursor_visible.set(false)
      @edit_mode.set(@default_mode)
      @was_quick_entry = false
      clear_selection
    end

    # Called when widget loses focus
    def on_blur
      reset_transient_edit_state
      mark_needs_render
      # Fire Blur event so parent widgets (e.g., ComboBox) can respond
      @on_event.try &.call(value, TextInputEvent::Blur)
    end

    # === PROXY FOCUS (for VirtualMatrix cell hosting) ===

    # Activate proxy focus — set up cursor, blink, and QuickEntry state
    def activate_proxy_focus
      super
      @cursor_visible.set(true)
      @value_on_focus.set(value)
      # A fresh cursor cell has no caret/blink — the caret starts blinking when you
      # type (on_text_input restarts it) or enter full-edit (enter_edit_mode).
      start_cursor_blink if edit_mode == TextInputMode::FullEdit
      self.pending_replace = true if edit_mode == TextInputMode::QuickEntry
    end

    # Deactivate proxy focus — tear down the QuickEntry edit decoration the cell
    # showed while the cursor occupied it (select-all highlight + caret).
    #
    # @pending_replace mirrors what activate_proxy_focus sets; clearing it here
    # keeps the abandoned cell out of "type-to-replace" state (and, since it is a
    # reconcile_property, stops a stale `true` migrating onto the next instance on
    # rebuild).
    #
    # invalidate_primitive_cache is defense-in-depth at the source: super's
    # mark_needs_render only sets a transient needs_render flag, which the per-frame
    # clear_render_state sweep wipes if this cell scrolls out of view before it is
    # repainted (the Tab-wraparound ghost). Dropping the primitive cache is a
    # PERSISTENT signal — the fast path won't blit a stale highlighted texture while
    # the cache is nil, so the cell repaints clean the next time it is in-buffer.
    # The framework-level cause (a full render culls dirty off-viewport cells) is
    # fixed in LayerRenderer (it keeps dirty off-viewport cells in the render set).
    def deactivate_proxy_focus
      super
      reset_transient_edit_state
      # Forget the caret position too, so re-navigating onto this cell (or F2-ing back in)
      # lands fresh like a new cell instead of resurrecting the previous edit session's
      # position. Proxy-only (matrix cells re-navigate); standalone on_blur leaves its caret.
      @cursor_pos.set(value.size)
      @pending_replace.set(false)
      invalidate_primitive_cache
    end

    # A TextInput draws its caret once you're actively entering text — i.e. NOT in
    # the fresh "type-to-replace" state (pending_replace). A fresh cursor cell draws
    # no caret, so the matrix cell-flash marks it (like ComboBox/Checkbox/Nil); the
    # moment you type or enter full-edit the caret appears and the matrix suppresses
    # its whole-cell flash (the caret is then the indicator).
    def draws_edit_caret? : Bool
      effectively_focused? && !pending_replace
    end

    # Start cursor blinking timer
    private def start_cursor_blink
      stop_cursor_blink # Clear any existing timer
      @blink_timer_id = schedule_timer(CURSOR_BLINK_INTERVAL, repeating: true) do
        @cursor_visible.set(!cursor_visible)
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
      # Space-as-toggle (opt-in): fire Toggle and DON'T insert the space. This is the
      # only seam that suppresses the char — on_key_down's return can't, since the
      # TextEntered event is dispatched independently of KeyPressed.
      if @toggle_on_space && char == ' '
        @on_event.try &.call(value, TextInputEvent::Toggle)
        return
      end

      # In QuickEntry mode, first keystroke replaces entire content
      if edit_mode == TextInputMode::QuickEntry && pending_replace
        @value.set(char.to_s)
        @cursor_pos.set(1)
        @pending_replace.set(false)
        clear_selection
      else
        # Delete selection first if any
        if has_selection?
          delete_selection
        end

        # Insert character at cursor position
        @value.set(value[0...cursor_pos] + char.to_s + value[cursor_pos..])
        @cursor_pos.set(cursor_pos + 1)
      end

      # Reset cursor visibility on input
      @cursor_visible.set(true)
      restart_cursor_blink

      notify_change
    end

    # Public method to insert a character programmatically
    # Used by ComboBox to insert initial typed character after expand
    def insert_char(char : Char)
      # Insert at cursor position (no QuickEntry replacement)
      @value.set(value[0...cursor_pos] + char.to_s + value[cursor_pos..])
      @cursor_pos.set(cursor_pos + 1)

      notify_change
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
        # QuickEntry: the cell owner cuts the whole cell — decline so Ctrl+X
        # bubbles to its panel shortcut. Shift+Delete (no cell-op) stays
        # editor-handled.
        return false if edit_mode == TextInputMode::QuickEntry && control
        cut_selection
        return true
      end

      # Ctrl+V or Shift+Insert = Paste
      if (control && key == SF::Keyboard::Key::V) || (shift && key == SF::Keyboard::Key::Insert)
        # QuickEntry: the cell owner pastes the cell — decline so Ctrl+V
        # bubbles. Shift+Insert (no cell-op) stays editor-handled.
        return false if edit_mode == TextInputMode::QuickEntry && control
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
        if edit_mode == TextInputMode::QuickEntry
          # QuickEntry: Enter ENTERS full-edit mode (F2-style toggle). Committing
          # and moving is the arrow keys' job (accept-and-move) — Enter never moves.
          enter_edit_mode
          true
        else
          # FullEdit: Enter LEAVES full-edit — the parent (matrix) commits and
          # re-arms QuickEntry on the SAME cell (no cursor move, no dead cell).
          exit_edit_mode if @was_quick_entry
          notify_submit
          deactivate_proxy_focus
          false # let parent handle (commit + re-arm)
        end
      when SF::Keyboard::Key::Backspace
        if has_selection?
          delete_selection
          reset_cursor_blink
        elsif cursor_pos > 0
          @value.set(value[0...(cursor_pos - 1)] + value[cursor_pos..])
          @cursor_pos.set(cursor_pos - 1)
          reset_cursor_blink
          notify_change
        end
        @pending_replace.set(false) # Any editing clears pending replace
        true
      when SF::Keyboard::Key::Delete
        # QuickEntry: the host owns bare Delete (e.g. a delete shortcut) — decline
        # so it bubbles to the host. Without this the proxy consumes it and the
        # host's delete shortcut would be dead.
        return false if edit_mode == TextInputMode::QuickEntry
        if has_selection?
          delete_selection
          reset_cursor_blink
        elsif cursor_pos < value.size
          @value.set(value[0...cursor_pos] + value[(cursor_pos + 1)..])
          reset_cursor_blink
          notify_change
        end
        @pending_replace.set(false) # Any editing clears pending replace
        true
      when SF::Keyboard::Key::Left
        # Parent intercept consumed it (re-dispatches to the grid). Return true so
        # the renderer does NOT then spatially navigate focus out of the matrix.
        if @on_horizontal_arrow.try(&.call(false))
          return true
        end
        # In QuickEntry mode, let FocusManager handle arrow navigation
        return false if edit_mode == TextInputMode::QuickEntry && !shift

        if shift
          # Extend selection left
          start_selection_if_needed
          if cursor_pos > 0
            @cursor_pos.set(cursor_pos - 1)
            reset_cursor_blink
          end
        else
          # Move cursor left, clear selection
          if has_selection?
            # Move to start of selection
            range = selection_range
            @cursor_pos.set(range[0]) if range
            clear_selection
          elsif cursor_pos > 0
            @cursor_pos.set(cursor_pos - 1)
          end
          reset_cursor_blink
        end
        true
      when SF::Keyboard::Key::Right
        # Parent intercept consumed it (re-dispatches to the grid). Return true so
        # the renderer does NOT then spatially navigate focus out of the matrix.
        if @on_horizontal_arrow.try(&.call(true))
          return true
        end
        # In QuickEntry mode, let FocusManager handle arrow navigation
        return false if edit_mode == TextInputMode::QuickEntry && !shift

        if shift
          # Extend selection right
          start_selection_if_needed
          if cursor_pos < value.size
            @cursor_pos.set(cursor_pos + 1)
            reset_cursor_blink
          end
        else
          # Move cursor right, clear selection
          if has_selection?
            # Move to end of selection
            range = selection_range
            @cursor_pos.set(range[1]) if range
            clear_selection
          elsif cursor_pos < value.size
            @cursor_pos.set(cursor_pos + 1)
          end
          reset_cursor_blink
        end
        true
      when SF::Keyboard::Key::Up
        # Parent intercept consumed it (commit + re-dispatch to the grid). Return
        # true so the renderer does NOT then spatially navigate focus out of the matrix.
        if @on_vertical_arrow.try(&.call(false))
          return true
        end
        # Always fire ArrowUp event for parent widgets (e.g., ComboBoxPopup item navigation)
        notify_arrow_up

        # In QuickEntry mode, let FocusManager handle navigation
        return false if edit_mode == TextInputMode::QuickEntry

        # In FullEdit mode, Up moves cursor to start (like Home)
        clear_selection
        @cursor_pos.set(0)
        reset_cursor_blink
        true
      when SF::Keyboard::Key::Down
        # Parent intercept consumed it (commit + re-dispatch to the grid). Return
        # true so the renderer does NOT then spatially navigate focus out of the matrix.
        if @on_vertical_arrow.try(&.call(true))
          return true
        end
        # Always fire ArrowDown event for parent widgets (e.g., ComboBoxPopup item navigation)
        notify_arrow_down

        # In QuickEntry mode, let FocusManager handle navigation
        return false if edit_mode == TextInputMode::QuickEntry

        # In FullEdit mode, Down moves cursor to end (like End)
        clear_selection
        @cursor_pos.set(value.size)
        reset_cursor_blink
        true
      when SF::Keyboard::Key::Home
        if shift
          # Extend selection to start
          start_selection_if_needed
          @cursor_pos.set(0)
        else
          clear_selection
          @cursor_pos.set(0)
        end
        reset_cursor_blink
        true
      when SF::Keyboard::Key::End
        if shift
          # Extend selection to end
          start_selection_if_needed
          @cursor_pos.set(value.size)
        else
          clear_selection
          @cursor_pos.set(value.size)
        end
        reset_cursor_blink
        true
      when SF::Keyboard::Key::Escape
        # Undo any edits made since focus (restore value + caret), THEN always drop the
        # selection — Escape abandons the edit interaction, selection and all (mirrors on_blur).
        # The selection was previously cleared only on the value-changed path, so an
        # unchanged-value Escape left the characters stranded as selected.
        if (saved_value = value_on_focus) && value != saved_value
          @value.set(saved_value)
          @cursor_pos.set(saved_value.size)
        end
        clear_selection

        if @was_quick_entry
          # Came from QuickEntry: exit back to QuickEntry mode, stay focused
          exit_edit_mode
          @pending_replace.set(true)
          notify_cancel
          mark_needs_render
        else
          # Default FullEdit mode or QuickEntry mode: release focus
          notify_cancel
          release_focus
        end
        true
      when SF::Keyboard::Key::Tab
        # Let a focus-stealing overlay editor (e.g. a ComboBox popup) commit and
        # re-dispatch Tab to its owning focus-scope. Consume (return true) so
        # FocusManager keeps focus here rather than cycling out; decline (false, incl.
        # no callback / standalone) so it cycles normally. See on_tab's polarity note.
        @on_tab.try(&.call(shift)) || false
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
      @value.set(value[0...cursor_pos] + text + value[cursor_pos..])
      @cursor_pos.set(cursor_pos + text.size)
      reset_cursor_blink
      notify_change
    end

    # Select all text
    private def select_all
      return if value.empty?
      @selection_anchor.set(0)
      @cursor_pos.set(value.size)
    end

    # Reset cursor to visible state and restart blink timer
    private def reset_cursor_blink
      @cursor_visible.set(true)
      restart_cursor_blink
    end

    # Restart the cursor blink timer
    private def restart_cursor_blink
      stop_cursor_blink
      start_cursor_blink
    end

    # Notify on_change callback and fire Change event
    private def notify_change
      @on_change.try &.call(value)
      @on_event.try &.call(value, TextInputEvent::Change)
    end

    # Fire Submit event (Enter pressed to confirm)
    private def notify_submit
      @on_event.try &.call(value, TextInputEvent::Submit)
    end

    # Fire Cancel event (Escape pressed to abort)
    private def notify_cancel
      @on_event.try &.call(value, TextInputEvent::Cancel)
    end

    # Fire ArrowUp event (Up arrow pressed)
    private def notify_arrow_up
      @on_event.try &.call(value, TextInputEvent::ArrowUp)
    end

    # Fire ArrowDown event (Down arrow pressed)
    private def notify_arrow_down
      @on_event.try &.call(value, TextInputEvent::ArrowDown)
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
