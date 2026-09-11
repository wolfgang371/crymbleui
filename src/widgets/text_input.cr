require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"
require "./text_lines"

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

  # TextInput widget for text entry.
  #
  # DISPLAY is multi-line whenever the value is: any instance handed a String containing `\n`
  # measures, centres, carets and marks it honestly, because a consumer can set one through
  # `value=` or an adopted `bind:` Source and a widget that renders a value it cannot describe
  # is the worst of both. AUTHORING is opt-in — see `multiline`.
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
    # The padding a TextInput carries unless told otherwise. Named because the class-level
    # measurement helpers below default to it, and a consumer sizing many cells must be able to
    # ask for the width WITHOUT building a widget per measurement.
    DEFAULT_PADDING = 4.0
    CURSOR_WIDTH = 1.0

    # Cursor blink interval (Windows standard)
    CURSOR_BLINK_INTERVAL = 530.milliseconds

    # Double-click detection threshold
    DOUBLE_CLICK_THRESHOLD_MS = 300

    # Current text value — tracked Source for auto-capture in to_primitives.
    # May be a caller-owned Source adopted via `bind:` (two-way binding), so an EXTERNAL writer can
    # change it out from under the cursor; edit entries re-clamp via clamp_indices_to_value.
    reactive_property value : String

    # Override the macro-generated setter to also clamp the cursor to the new length.
    def value=(v : String)
      @value.set(v)
      clamp_indices_to_value
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

    # How far the value is scrolled, in content pixels. TWO axes now: the premise that made
    # this a scalar — "this widget is single-line by construction, so a Vec2 would carry a
    # component nothing ever reads" — is exactly what multi-line values remove. Y matters for
    # the same reason X does: without it, authoring a break on the last visible line of a
    # one-line-tall cell means typing blind.
    #
    # What this STORES is hysteresis, and that is all: it keeps the view still while the caret
    # walks back inside the window it already shows, instead of snapping to the caret and
    # shifting the text a character on every Left press. The offset actually rendered is always
    # re-derived (see effective_scroll_offset), so this may legitimately be stale after a value
    # change, an external write to a bound cell, a resize or a zoom — none of which move the
    # cursor, and none of which any per-handler rule could catch.
    reactive_property scroll_offset : Vec2 = Vec2.zero, reconcile: true

    # Where the view has to sit for the caret to be visible, given where it sat before.
    #
    # Pure and static so it can be reasoned about and tested directly. It is deliberately NOT
    # written back from `to_primitives`: a Source written inside its own memoized recompute
    # replaces the node's dependent set mid-flight, severing the back-edge, after which an
    # external write marks nobody and the widget serves stale primitives forever.
    #
    # The reserve applies ONLY in the overflowing branch. Applied unconditionally it would push
    # an exactly-fitting value to offset 1 and light a left band over a value with nothing
    # hidden; omitted entirely, the caret at end-of-text lands exactly on the box edge and is
    # scissored away — which is the one place scroll-to-caret exists to serve.
    #
    # AXIS-AGNOSTIC: the same invariant governs both axes, so there is one definition and two
    # callers. `caret_extent` is the caret's own extent along the axis — `CURSOR_WIDTH` on X,
    # and a LINE'S INK EXTENT on Y, which is what has to stay inside the box for the line you
    # are typing on to be readable. It is REQUIRED rather than defaulted: a Y caller that
    # forgot it would silently inherit X's one-pixel reserve and scroll by nearly a whole
    # line too little, which no example would name.
    def self.derive_scroll_offset(stored : Float64, caret : Float64,
                                  content : Float64, box : Float64,
                                  caret_extent : Float64) : Float64
      return 0.0 if content <= box || box <= 0.0
      view = Math.max(1.0, box - caret_extent)
      # Keep the caret inside [offset, offset + view] — moving the view only when it leaves.
      held = Math.min(Math.max(stored, caret - view), caret)
      Math.max(0.0, Math.min(held, content - view))
    end

    # Clamp both cursor indices to the current value length. Called at every write/edit ENTRY
    # (value=, copy_state_from, on_text_input, on_key_down) so an operation always starts with valid
    # indices — in particular when an EXTERNAL writer has shrunk a bound value cell (a re-render, not
    # a rebuild, so copy_state_from's clamp never ran). Clamped ONCE at entry, NOT on read, so an
    # operation's own cursor arithmetic (e.g. backspace's `cursor_pos - 1`) is never shifted mid-op.
    # (insert_char is ComboBox-internal, never caller-bound, so it needs no guard.)
    private def clamp_indices_to_value : Nil
      @cursor_pos.set(cursor_pos.clamp(0, value.size))
      @selection_anchor.set(selection_anchor.try(&.clamp(0, value.size)))
    end

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

    # The column a vertical run is aiming for. Without it, walking Down through a short line
    # collapses the caret to that line's end and the run never recovers its column — the exact
    # dishonesty line navigation exists to remove. Reconciled, because a rebuild mid-run must
    # not silently reset the aim.
    reactive_property goal_column : Int32? = nil, reconcile: true

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

    # Opt-in: may this editor AUTHOR a hard line break?
    #
    # Authoring and paste only — NOT display. Any TextInput handed a value containing `\n`
    # measures, centres, carets and marks it honestly, because a consumer can set one
    # through `value=` or an adopted `bind:` Source and a widget that displays a value it
    # cannot describe is the worst resting state. What this flag decides is whether
    # Alt/Ctrl+Enter inserts a break and whether a pasted break survives — so the same
    # widget can keep editing field and table names, which are single-line by design.
    getter multiline : Bool = false

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
      padding : Float64 = DEFAULT_PADDING,
      mode : TextInputMode = TextInputMode::FullEdit,
      on_event : Proc(String, TextInputEvent, Nil)? = nil,
      on_change : Proc(String, Nil)? = nil,
      bind : Source(String)? = nil,
      multiline : Bool = false,
    )
      # bind: adopts a caller-owned value cell (two-way binding). value: seeds a fresh
      # cell. They are mutually exclusive — the bound Source IS the value.
      raise ArgumentError.new("TextInput: bind: and a non-empty value: are mutually exclusive") if bind && !value.empty?
      @placeholder = Source(String).new(placeholder)
      @prefix = Source(String).new(prefix)
      @value = bind || Source(String).new(value) # bind: adopt the caller's cell; else own a fresh one
      @bind_source = bind if bind # stability guard: hold the adopted Source to detect fresh-per-build
      @cursor_pos = Source(Int32).new(@value.get.size) # Start cursor at end (of the adopted/own value)
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
      @multiline = multiline
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
      padding : Float64 = DEFAULT_PADDING,
      mode : TextInputMode = TextInputMode::FullEdit,
      on_event : Proc(String, TextInputEvent, Nil)? = nil,
      multiline : Bool = false,
      &block : String -> Nil
    )
      new(value, id, width, placeholder, prefix, font_scale, text_color, background_color, border_color, focused_border_color, placeholder_color, padding, mode, on_event, on_change: block, multiline: multiline)
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

      # Carry cursor + selection from the old instance, clamped to the new value length
      # (value may have changed during rebuild).
      @cursor_pos.set(old.cursor_pos)
      @selection_anchor.set(old.selection_anchor)
      clamp_indices_to_value

      # Reap the OLD instance's blink timer. transfer_focus (in super) moves focus to
      # THIS new instance WITHOUT firing the old one's on_blur, so its repeating timer
      # would otherwise run forever — pinning the discarded widget tree and forcing a
      # redraw every tick. UNCONDITIONAL: on_focus starts the blink even in the
      # pending_replace state, so a focused field whose new instance does NOT restart the
      # caret (carried pending_replace) would still orphan the old timer.
      # Mirror of VirtualMatrix's stop_cursor_flash_for_transfer.
      old.stop_cursor_blink
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

    # The width this input's own value needs — the text it draws plus the chrome around it, so
    # that nothing would be cut at this width.
    #
    # Deliberately a THIRD question, distinct from the two that already exist:
    #   `measure`             fills the constraint it is given (every dialog field relies on it)
    #   `min_intrinsic_width` the SMALLEST acceptable width — WindowPanel feeds it into
    #                         panel_min_width, and a TextInput may legitimately be narrower than
    #                         its content: it scrolls and paints the cut band
    # Answering either of those with the content width would make a typed-in value a panel's
    # drag floor. The prefix counts: it is drawn inside the same box, ahead of the value.
    # A multi-line value measures as its widest line, which is what `measure_text` returns.
    def content_width : Float64
      w = TextInput.content_width_for(value, font_size, padding)
      w += measure_text(prefix, font_size).width unless prefix.empty?
      w
    end

    # The same question, answerable WITHOUT constructing a widget: a consumer sizing a whole
    # grid cannot afford one TextInput per cell just to measure it. Keeping these here is what
    # stops the chrome arithmetic being copied into every such consumer.
    def self.content_width_for(text : String, font_size : Float64, padding : Float64 = DEFAULT_PADDING) : Float64
      Widget.measure_text(text, font_size).width + (padding + BORDER_WIDTH) * 2
    end

    def self.content_height_for(text : String, font_size : Float64, padding : Float64 = DEFAULT_PADDING) : Float64
      lines = TextLines.of(text)
      height = font_size + (padding + BORDER_WIDTH) * 2
      height += (lines.line_count - 1) * lines.step(font_size) if lines.line_count > 1
      height
    end

    # How many lines this input's value holds. Paired with `content_width` for auto-sizing: a
    # row's policy is expressed in LINES, and recovering a line count from a pixel height would
    # re-derive the chrome arithmetic that content_width exists to keep in one place.
    def content_line_count : Int32
      TextLines.of(value).line_count
    end

    # Measure text input size
    def measure(constraints : BoxConstraints) : Size
      # Height: tight constraints → fill exactly; loose → natural, clamped to max.
      # The loose branch reserves a slot per EXTRA line, so a standalone multi-line editor
      # stops measuring one line while painting N. Written as `font_size + (n-1) * step`
      # rather than the block extent: `ref_h` is the ink and `font_size` the em, so using the
      # extent here would change the loose height of every SINGLE-line input. Cells take the
      # tight branch, so nothing in a table moves either way.
      extra_lines = TextLines.of(value).line_count - 1
      height = font_size + (padding * 2) + (BORDER_WIDTH * 2)
      height += extra_lines * TextLines.of(value).step(font_size) if extra_lines > 0
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

      # Inner content area. The vertical half lives in block_anchor, which owns where a block
      # of N lines sits — kept in one place so the renderer and the scroll derivation cannot
      # disagree about it.
      content_x = BORDER_WIDTH + padding
      content_width = bounds.width - (BORDER_WIDTH + padding) * 2

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

      # The value's line decomposition and block geometry — ONE owner, so centring, the caret,
      # the selection and the cut bands cannot disagree about where line k sits.
      lines = TextLines.of(value)
      fs = font_size
      slot = lines.slot_height(fs)
      step = lines.step(fs)
      ref_h = lines.ref_h(fs)

      # Where the block sits: centred when it fits, otherwise exactly where a single line
      # would — so a multi-line cell shares its row's baseline instead of hanging lower than
      # its neighbours. Identical to the old vcentered_text_y for a single line, at every box
      # height. Derived here and PASSED to the scroll derivation, which needs the same anchor:
      # two computations of it would be two answers to where the block starts.
      text_y = block_anchor(bounds.height, lines)
      prefix_position = Vec2.new(content_x, text_y)
      content_x = content_x + prefix_width

      # The box the value may actually occupy, and the box it is CLIPPED to. One rect, so
      # "is this value cut?" and "where do we cut it?" can never disagree — the reason a
      # cut-content marker can be honest about this widget at all.
      #
      # X ONLY. The Y extent is the full widget height on purpose: a matrix cell is laid out
      # tight at ~17px, which leaves a 7px content box for a 14px font, so text_y is NEGATIVE
      # relative to the content box and the glyphs legitimately overhang it top and bottom.
      # Clipping Y to the content box would shave every cell in every table. Vertical overflow
      # is handled by the block geometry below, not by this rect.
      text_box = Rect.new(content_x, 0.0, content_width - prefix_width, bounds.height)

      # How far the value is scrolled, on BOTH axes, derived by the same method the handlers
      # persist — never written back from here: a Source written inside its own memoized
      # recompute replaces the node's dependent set mid-flight, after which an external write
      # marks nobody and this widget serves stale primitives forever.
      offset = effective_scroll_offset
      scroll_x = offset.x

      # Line k's ink starts at `block_top + k * step`. EVERY answer about vertical position —
      # what is drawn, what is marked, where the caret and the selection go — comes from this
      # one expression. It used to be shared out as a Proc while the visible RANGE was derived
      # separately from the raw scroll offset, and the two disagreed by the anchor: at an
      # ordinary cell that is most of a line, so a line with its ink on screen was reported
      # hidden, the "content above" band lied, and that line lost its own horizontal marker.
      block_top = text_y - offset.y
      line_y = ->(k : Int32) { block_top + k * step }

      # The drawn range, computed rather than searched, so a 500-line value costs O(1) here:
      # line k has ink on screen iff `block_top + k*step + slot > 0` and `< bounds.height`.
      last_index = lines.line_count - 1
      if step > 0.0
        first_drawn = Math.max(0, ((-slot - block_top) / step).floor.to_i + 1)
        last_drawn = Math.min(last_index, ((bounds.height - block_top) / step).ceil.to_i - 1)
      else
        first_drawn = 0
        last_drawn = last_index
      end

      # The VERTICAL hint, asked of the SAME anchored positions the glyphs are drawn from. A
      # line counts as cut until its ink is COMPLETELY inside the box — a bar that goes out
      # the moment a line STARTS to appear says "you have it all" while half of it is still
      # missing, which is the one thing a cut marker must never say.
      #
      # `line_count > 1` is what keeps this off every cell in every table: a SINGLE line's
      # glyphs legitimately overhang a tight row (17px leaves a 7px content box for a 14px
      # font), and an ink test without that guard would light a band everywhere.
      #
      # EVERY line you cannot see counts, empty or not. A break the user typed is part of the
      # value — content sizing grows the row for it, and a row that cannot grow far enough has
      # to say so; the earlier rule (only lines carrying glyphs count) made those two disagree,
      # and a value cut to its first lines went unmarked. Which line is hidden needs no search:
      # the lines are laid out in order, so the FIRST decides what is above and the LAST what
      # is below — O(1) per render, whatever the value's length.
      multi = lines.line_count > 1
      content_above = multi && line_y.call(0) < 0.0
      content_below = multi && line_y.call(last_index) + ref_h > bounds.height

      # ONE box for all four bars: the widget's inner rect, just inside its border. The bars
      # are chrome on the CELL's edge, not part of the scrollable value — so they must not be
      # placed in the text box, which is additionally inset by the padding and would leave the
      # side bars floating a few pixels short of the edge the bottom bar sits on.
      inner = Rect.new(BORDER_WIDTH, BORDER_WIDTH,
        bounds.width - BORDER_WIDTH * 2, bounds.height - BORDER_WIDTH * 2)
      cut_above, cut_below = clipped_block_bands(inner, content_above, content_below)

      # FULL bars on the sides, spanning the cell exactly as the vertical one spans its width
      # — one cue with one shape on both axes. Per-line segments were tried and read as noise:
      # a stub beside one line of a block looks like a rendering artifact rather than the same
      # marker, and all it buys is "which line runs on", which entering the cell shows anyway.
      #
      # `measure_text(value).width` is the WIDEST line, so this lights whenever ANY line
      # overflows — precisely the question a cell-wide bar answers.
      value_box_w = content_width - prefix_width
      cut_left, cut_right = clipped_text_bands(
        Rect.new(content_x, inner.y, value_box_w, inner.height), scroll_x,
        display_empty ? 0.0 : measure_text(value, fs).width, band_box: inner)

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

        # Say so where the value is cut. BEFORE the clipped block, so the band sits behind the
        # glyphs and the caret: it can never obscure the sliver it is reporting on. The colour
        # derives from the background this widget actually paints (a caller may have tinted the
        # cell), so the floor holds against what is really on screen. A placeholder is not
        # content, so an empty value is never marked as cut.
        # All four edges in ONE call: `contrasting_neutral` costs four `pow`, and a call per
        # band would pay that once per lit edge against the very same backdrop.
        mark_clipped_text({cut_left, cut_right, cut_above, cut_below}, on: background_color) unless display_empty

        # The vertical band is emitted here — after the four border fills — so it is never
        # overpainted, and outside the value's clip, because it spans the whole widget rather
        # than the text box. Position plus that emission order is what locates it.
        # Everything that belongs to the VALUE — selection, glyphs, caret — is clipped to the
        # text box. The chrome above and the prefix stay outside it: the prefix is a display
        # affordance anchored to the left edge, not part of the scrollable/clippable value.
        clipped(text_box, within: local_bounds) do
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
            # ONE RECT PER LINE the selection covers. A single rect spanning
            # measure_text(value[0...sel_end]) is meaningless once a block's width is its
            # WIDEST line: it paints line 0 to the width of the longest line and leaves every
            # later line unhighlighted, whatever the user actually selected.
            sel_first = lines.line_at(sel_start)
            sel_last = lines.line_at(sel_end)
            (Math.max(sel_first, first_drawn)..Math.min(sel_last, last_drawn)).each do |k|
              top = line_y.call(k)
              text_k = lines.line_text(k)
              from_col = k == sel_first ? lines.column_at(sel_start) : 0
              to_col = k == sel_last ? lines.column_at(sel_end) : text_k.size
              row_start_x = content_x - scroll_x + measure_text(text_k[0...from_col], fs).width
              row_end_x = content_x - scroll_x + measure_text(text_k[0...to_col], fs).width
              # Reserve the band columns of THIS line. A select-all must not bury the one
              # thing telling you the value continues — and both edges matter, not just the
              # right: Ctrl+A puts the caret at the end, which scrolls to the tail, and there
              # the right band is dark by construction while the LEFT one carries the hint.
              # Which columns those are is a per-line answer now.
              row_start_x = Math.max(row_start_x, cut_left.x + cut_left.width) if cut_left
              row_end_x = Math.min(row_end_x, cut_right.x) if cut_right
              row_width = row_end_x - row_start_x
              fill_rect(Rect.new(row_start_x, top, row_width, slot), Theme.current.input_selection) if row_width > 0
            end
          end

          # Draw text (or placeholder) — ONE CALL PER LINE, not one for the block.
          # SFML renders `\n` natively, so a single call would be tempting and cheaper. But
          # it positions the block by `local_bounds.left`, which SFML reports as the MINIMUM
          # left bearing across lines, while a caret is placed from its own line's
          # measurement. tools/multiline-probe.cr measured that spread on the bundled font at
          # 1px (size 9) and 2px (size 24) — not sub-pixel — so the caret would sit beside
          # the glyphs on some lines. draw_text already compensates for the bearing of the
          # string it is handed, so per-line drawing makes each line start exactly where it
          # was asked to and needs no correction term at all. N == 1 for a single-line value.
          if display_empty
            draw_text(display_text, Vec2.new(content_x - scroll_x, text_y), display_color, font_scale) unless display_text.empty?
          else
            (first_drawn..last_drawn).each do |k|
              # A blank line has nothing to draw, and an empty DrawText is not free: the SFML
              # path builds an SF::Text per call to read its bearings, uncached.
              next if lines.line_empty?(k)
              draw_text(lines.line_text(k), Vec2.new(content_x - scroll_x, line_y.call(k)), display_color, font_scale)
            end
          end

          # Draw cursor once you're actively entering text (NOT the fresh
          # type-to-replace state). A fresh cursor cell shows no caret — the matrix
          # cell-flash marks it — and the caret appears the moment you type / enter
          # full-edit.
          # WHERE the caret is comes from `caret_rect` — one owner for that arithmetic, because a
          # host now asks the same question to scroll it into view and two copies would
          # drift. WHETHER it is drawn is this frame's business: the blink belongs to painting, and
          # deliberately not to `caret_rect`, or the view would stutter with it.
          if cursor_visible && (caret = caret_rect)
            fill_rect(caret, text_color)
          end
        end
      end
    end

    # === FOCUS HANDLING ===

    # Called when widget gains focus
    def on_focus
      # Chain to Widget#on_focus (request_scroll_into_view) so a focused field scrolls into view
      # inside a ScrollView — the base behavior every other focusable keeps (VirtualMatrix also
      # chains super; TextInput was the lone override that dropped it).
      super
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
      @goal_column.set(nil) # a vertical run belongs to the cell it was started in
      # Rest head-anchored. An abandoned cell left scrolled to its tail would sit in a table
      # showing a LEFT band, i.e. "there is more to the left", beside identical cells showing a
      # right band — a difference with no cause the user can see.
      @scroll_offset.set(Vec2.zero)
    end

    # Width the value has to live in: the content box, less whatever the prefix occupies.
    private def value_box_width(width : Float64) : Float64
      width - (BORDER_WIDTH + padding) * 2 - (prefix.empty? ? 0.0 : measure_text(prefix, font_size).width)
    end

    # The Y twin: the band the value's block is anchored into, which is what it may scroll
    # within. There is no prefix term — a prefix sits on the caret's line, so it takes width
    # from the value and no height from it.
    private def value_box_height(height : Float64) : Float64
      height - (BORDER_WIDTH + padding) * 2
    end

    # The offset actually rendered — always DERIVED, never read straight from the property, so
    # a value change / external write / resize / zoom (none of which move the cursor) cannot
    # strand the view. Zero unless the caret is drawn: cursor_pos rests at value.size on every
    # TextInput, so an ungated derivation would scroll every overflowing cell of a fresh sheet
    # to its tail.
    def effective_scroll_offset : Vec2
      return Vec2.zero unless draws_edit_caret?
      fs = font_size
      lines = TextLines.of(value)
      line = lines.line_at(cursor_pos)
      # X is measured along the caret's OWN line. Once a block's width is the widest line,
      # `measure_text(value[0...cursor_pos])` stops meaning "how far along is the caret" —
      # it means "how wide is everything before it", which past the first break is neither.
      prefix = lines.line_text(line)[0...lines.column_at(cursor_pos)]
      x = TextInput.derive_scroll_offset(scroll_offset.x,
        measure_text(prefix, fs).width,
        measure_text(value, fs).width,
        value_box_width(bounds.width), CURSOR_WIDTH)
      # Y works on the caret LINE's top and the block's full extent, both measured FROM THE
      # BLOCK, and against the inner box — the same frame X uses. Measuring the caret from the
      # widget while scrolling against the widget's full height mixes two frames: the offset
      # could then grow to the anchor itself, and walking back to line 1 left the block a
      # padding too high, its first line drawn under the border (field report). The caret's
      # extent on this axis is a line's INK, which is what has to stay inside the box.
      y = TextInput.derive_scroll_offset(scroll_offset.y,
        lines.y_of(line, fs),
        lines.block_extent(fs),
        value_box_height(bounds.height), lines.ref_h(fs))
      Vec2.new(x, y)
    end

    # Where the caret is drawn, in WIDGET-LOCAL coordinates — nil when this widget draws none.
    #
    # For a host that has to scroll the caret into view: a VirtualMatrix cell can now be larger
    # than the viewport, so keeping the CELL visible is no longer enough — the caret moves inside
    # it. The host asks for this rather than re-deriving it, because the block anchor, the
    # per-line step and the editor's own scroll offset all belong to this widget, and a second copy
    # of that arithmetic would drift the day any of them changes.
    #
    # Gated on `draws_edit_caret?`, NOT on the paint condition: the paint gate also carries the
    # ~500ms blink Source, so a rect inheriting it would vanish on half the blink cycle and make
    # the host snap intermittently. It reports where the caret IS, not whether it is lit this frame.
    #
    # The offset it applies is the DERIVED one — the stored property is hysteresis and may be stale
    # after a value change, a resize or a zoom, none of which move the cursor.
    def caret_rect : Rect?
      return nil unless draws_edit_caret?
      fs = font_size
      lines = TextLines.of(value)
      offset = effective_scroll_offset
      slot = measure_text("x", fs).height
      content_y = block_anchor(bounds.height, lines) - offset.y
      content_x = BORDER_WIDTH + padding + (prefix.empty? ? 0.0 : measure_text(prefix, fs).width)
      if value.empty?
        # The empty-value branch draws its caret at the block anchor, with no line to offset along.
        Rect.new(content_x, content_y, CURSOR_WIDTH, slot)
      else
        line = lines.line_at(cursor_pos)
        caret_prefix = lines.line_text(line)[0...lines.column_at(cursor_pos)]
        Rect.new(content_x - offset.x + measure_text(caret_prefix, fs).width,
          content_y + line * lines.step(fs), CURSOR_WIDTH, slot)
      end
    end

    # Where the value's block starts inside the widget, before scrolling: centred when it
    # fits, and otherwise exactly where a single line would sit, so a multi-line cell shares
    # its row's baseline instead of hanging 3px lower than its neighbours.
    private def block_anchor(height : Float64, lines : TextLines) : Float64
      content_y = BORDER_WIDTH + padding
      vcentered_block_y(height - (BORDER_WIDTH + padding) * 2, lines.line_count, font_scale, content_y)
    end

    # Remember where the view ended up, so it holds still while the caret walks back inside it.
    # Called from the input handlers — OUTSIDE any primitive recompute, which is the whole
    # point: writing this Source from inside `to_primitives` would sever its dependency edge.
    private def persist_scroll_offset : Nil
      @scroll_offset.set(effective_scroll_offset)
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

    # Stop cursor blinking timer. `protected` (not `private`) so a reconcile can reap the
    # OLD instance's timer via `old.stop_cursor_blink` (see copy_state_from). Side-effect-free
    # (cancels the timer + nils the id only), so no `_for_transfer` variant is needed.
    protected def stop_cursor_blink
      if timer_id = @blink_timer_id
        cancel_timer(timer_id)
        @blink_timer_id = nil
      end
    end

    # === KEYBOARD INPUT ===

    # Handle text input (printable characters)
    # Wrapper, so the view is remembered at ONE place per handler rather than at each of the
    # two dozen sites that move the caret — several of which are early returns, and four of
    # which (an external write, value=, a resize, a zoom) move no caret at all and so could
    # never be covered by a per-site rule anyway.
    def on_text_input(char : Char)
      handle_text_input(char)
      persist_scroll_offset
    end

    private def handle_text_input(char : Char)
      clamp_indices_to_value # a bound value may have shrunk externally since the last op
      @goal_column.set(nil)  # typing ends a vertical run

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
        splice_at_caret(char.to_s)
      end

      # Reset cursor visibility on input
      @cursor_visible.set(true)
      restart_cursor_blink

      notify_change
    end

    # Move the caret one line up (-1) or down (+1), keeping the column the run aims for.
    #
    # At the block's edges it clamps the POSITION, not the line: Up on the first line goes to
    # the very start and Down on the last to the very end — which is exactly what FullEdit
    # Up/Down have always done ("like Home"/"like End"), so every single-line TextInput in
    # both repos is untouched. Clamping the LINE instead would make both no-ops for a
    # single-line value, silently changing every rename and save-as dialog.
    private def move_caret_by_line(delta : Int32) : Nil
      lines = TextLines.of(value)
      line = lines.line_at(cursor_pos)
      goal = goal_column || lines.column_at(cursor_pos)
      target = line + delta
      if target < 0
        @cursor_pos.set(0)
      elsif target > lines.line_count - 1
        @cursor_pos.set(value.size)
      else
        span = lines.line_end(target) - lines.line_start(target)
        @cursor_pos.set(lines.line_start(target) + Math.min(goal, span))
      end
      @goal_column.set(goal)
    end

    # Replace any selection and splice `text` in at the caret. The one definition of "put
    # this here": typing a character and authoring a line break are the same operation on
    # different strings, and two copies of it would be free to drift.
    private def splice_at_caret(text : String) : Nil
      delete_selection if has_selection?
      @value.set(value[0...cursor_pos] + text + value[cursor_pos..])
      @cursor_pos.set(cursor_pos + text.size)
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
      handled = handle_key_down(key, control, shift, alt)
      persist_scroll_offset
      handled
    end

    private def handle_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
      clamp_indices_to_value # a bound value may have shrunk externally since the last op

      # A vertical run remembers the column it aims for; ANY other key ends the run. Done once
      # here rather than at each of the horizontal and editing sites, several of which are
      # early returns that would quietly keep a stale aim alive.
      unless key == SF::Keyboard::Key::Up || key == SF::Keyboard::Key::Down
        @goal_column.set(nil)
      end

      # === CLIPBOARD OPERATIONS ===
      # The editor touches the clipboard ONLY while it is actually editing text.
      # While PARKED in QuickEntry (focus armed pending_replace, nothing typed yet)
      # this widget is a grid cell, not a text field — so EVERY clipboard key is
      # declined and bubbles to the owner, which is where a cell/row/grid-level copy
      # or paste belongs. Once typing starts (immediate editing clears
      # pending_replace), or in FullEdit, they act on the text.
      #
      # This gates on the EDITOR'S MODE, deliberately not on which shortcuts the
      # consumer happens to have registered. A generic widget cannot know that, and
      # the earlier "decline only the keys that have a competing cell-op" rule
      # silently swallowed Ctrl+C and Shift+Insert from any application that later
      # grew a grid-level copy/paste — the key never reached the owner at all.
      parked = edit_mode == TextInputMode::QuickEntry && pending_replace

      # Ctrl+C or Ctrl+Insert = Copy
      if (control && key == SF::Keyboard::Key::C) || (control && key == SF::Keyboard::Key::Insert)
        return false if parked
        copy_selection
        return true
      end

      # Ctrl+X or Shift+Delete = Cut
      if (control && key == SF::Keyboard::Key::X) || (shift && key == SF::Keyboard::Key::Delete)
        return false if parked
        cut_selection
        return true
      end

      # Ctrl+V or Shift+Insert = Paste
      if (control && key == SF::Keyboard::Key::V) || (shift && key == SF::Keyboard::Key::Insert)
        return false if parked
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
        if multiline && (alt || control || shift)
          # A hard line break. Alt+Enter is Excel's, Ctrl+Enter is Calc's, Shift+Enter is what
          # browsers, editors and chat apps use; none collides with plain Enter = commit, so
          # whichever one a user already has in their fingers works first try.
          #
          # Opening full edit FIRST is load-bearing, not tidiness. A PARKED cell (QuickEntry
          # with pending_replace) draws no caret and REPLACES its whole value on the next
          # typed character — so inserting a break and leaving that state destroys the cell:
          # the user sees a blank-looking line, types the second one, and loses the break and
          # the original value together. enter_edit_mode clears pending_replace and starts
          # the caret, which is what every other editing key here already does.
          #
          # The caret is pinned to the end ONLY on that parked transition. copy_state_from
          # carries cursor_pos from the previous occupant of this widget path, and Escape
          # resets it only when the value CHANGED, so a parked cell can hold a stale
          # mid-string caret and break "Alice" into "Al\nice". Pinning unconditionally would
          # instead jump to the end whenever the user is already editing mid-value.
          if edit_mode == TextInputMode::QuickEntry && pending_replace
            @cursor_pos.set(value.size)
            enter_edit_mode
          end
          splice_at_caret("\n")
          @pending_replace.set(false)
          reset_cursor_blink
          # The loose measure reserves a slot per extra line, so adding one changes this
          # widget's natural height. `value` is not a layout property (every keystroke would
          # re-layout every cell in a grid), so the one edit that can change the LINE COUNT
          # asks for it explicitly. Geometry only — never a rebuild.
          mark_needs_layout
          notify_change
          return true
        end
        if edit_mode == TextInputMode::QuickEntry && pending_replace
          # PARKED QuickEntry (nothing typed yet): Enter opens full character-edit of the
          # EXISTING value (F2-style). Committing/moving is the arrow keys' job — Enter never moves.
          enter_edit_mode
          true
        else
          # FullEdit, OR QuickEntry with a typed replacement: Enter ACCEPTS the value and LEAVES
          # edit — the parent (matrix) commits and re-arms the cursor-flash state on the SAME cell
          # (no cursor move, no dead cell). Typing directly into a cell then Enter must commit +
          # exit, NOT drop into full-edit (the pending_replace guard above is what distinguishes them).
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
        # PARKED QuickEntry (nothing typed yet): the host owns bare Delete (its
        # delete-record shortcut) — decline so it bubbles. Once you've started typing
        # (immediate editing) Delete forward-deletes a character instead, and never
        # bubbles to the destructive record delete. Without the parked decline the host
        # shortcut would be dead.
        return false if edit_mode == TextInputMode::QuickEntry && pending_replace
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

        # In FullEdit, Up moves one LINE up — which for a single-line value is the start,
        # exactly as before.
        clear_selection
        move_caret_by_line(-1)
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

        # In FullEdit, Down moves one LINE down — which for a single-line value is the end,
        # exactly as before.
        clear_selection
        move_caret_by_line(1)
        reset_cursor_blink
        true
      when SF::Keyboard::Key::Home, SF::Keyboard::Key::End
        # PARKED QuickEntry: decline, the discipline Delete and the clipboard keys already
        # follow. A parked cell draws no caret, so moving one has no visible effect — while
        # consuming the key leaves the grid's own Home (column 0) and Ctrl+Home (cell {0,0})
        # dead on every text cell, which is what they were.
        return false if edit_mode == TextInputMode::QuickEntry && pending_replace

        # Home/End work on the LINE; Ctrl+Home/Ctrl+End on the whole value. Identical for a
        # single-line value, where the line IS the value, so nothing existing moves.
        lines = TextLines.of(value)
        line = lines.line_at(cursor_pos)
        target = if key == SF::Keyboard::Key::Home
                   control ? 0 : lines.line_start(line)
                 else
                   control ? value.size : lines.line_end(line)
                 end
        shift ? start_selection_if_needed : clear_selection
        @cursor_pos.set(target)
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

        if @default_mode == TextInputMode::QuickEntry
          # Resting mode is QuickEntry (a grid cell): cancel back to the clean type-to-replace
          # state and stay focused. exit_edit_mode re-arms pending_replace + stops the blink, so
          # the caret disappears — this also un-sticks a cell you TYPED in but never committed
          # (which stays QuickEntry with the caret showing until now).
          exit_edit_mode
          notify_cancel
          mark_needs_render
        else
          # Default FullEdit mode (standalone editor): release focus
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
      Widget.clipboard.text = selected_text
    end

    # Cut selected text to clipboard
    private def cut_selection
      return unless has_selection?
      Widget.clipboard.text = selected_text
      delete_selection
      reset_cursor_blink
    end

    # Reduce a clipboard payload to what this input can hold.
    #
    # Separators become a space rather than being dropped: tab is the TSV field separator, so
    # dropping it would silently weld "Mueller\t30" into "Mueller30". A LINE BREAK is treated
    # the same way only on the single-line path; a multi-line input keeps it, which is the
    # whole point of the flag. Tab becomes a space on BOTH paths — it is structure, not text —
    # as does a lone CR, which is a terminator artifact rather than anything anyone authored.
    #
    # What survives is filtered by the same rule the renderer applies to typed characters
    # (`ord >= 32 && ord != 127`) — a character filter only, not a claim that paste and typing
    # are otherwise equivalent (SPACE, for one, is untypeable here yet manufactured below, and
    # QuickEntry's first typed char replaces where paste inserts).
    #
    # The lone `gsub` collapses the CRLF *pair* so a Windows line break yields ONE break (or
    # one space), not two. The strip cannot come first: `\r` and `\n` are themselves C0, so
    # stripping before mapping would weld two lines into one run-on ("a\r\nb" -> "ab").
    #
    # Content is kept, only flattened — the sole removals are characters the typing path would
    # refuse and the TERMINATING break described below.
    # A multi-line editor keeps `\n` and strips only the TRAILING terminator: a copied cell
    # or row ends with a break that is structure, but a LEADING blank line is content, and
    # stripping both ends (which is right for a single-line field) silently deletes it. TAB
    # still becomes a space on both paths — it is the TSV field separator, so dropping it
    # would weld two columns together — as does a lone CR, which is a terminator artifact
    # rather than a break anyone authored.
    private def sanitize_pasted(text : String) : String
      collapsed = text.gsub("\r\n", "\n")
      # A copied cell or row arrives with a TRAILING line break — that is a
      # terminator, not content. Trim line breaks only, never spaces the user
      # actually copied, so "value\r\n" pastes as "value" and an empty cell ("\r\n")
      # sanitises to empty and therefore leaves the selection untouched instead of
      # replacing it with a space.
      body = multiline ? collapsed.rstrip("\n\r") : collapsed.strip("\n\r")
      String.build(body.bytesize) do |io|
        body.each_char do |ch|
          if ch == '\n' && multiline
            io << ch
          elsif ch == '\n' || ch == '\r' || ch == '\t'
            io << ' '
          elsif ch.ord >= 32 && ch.ord != 127
            io << ch
          end
        end
      end
    end

    # Paste from clipboard at cursor position
    private def paste_clipboard
      # Whatever is on the clipboard is pasted as text — the library does not care who
      # put it there. A consumer that copies structured data and then pastes it into a
      # text field gets that text, flattened by the rules below; that is the user's
      # own doing and not something this widget second-guesses.
      return unless raw = Widget.clipboard.text

      # Guard on the SANITISED result, not the raw payload: a control-only payload is
      # non-empty raw but empty here, and a raw guard would let it through to
      # delete_selection — destroying the selection for a paste that inserts nothing.
      text = sanitize_pasted(raw)
      return if text.empty?

      # Delete selection first if any
      if has_selection?
        delete_selection
      end

      # Insert pasted text at cursor. `text.size` is the SANITISED length in
      # CHARACTERS (never bytes) — the caret must not desync on non-ASCII.
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
