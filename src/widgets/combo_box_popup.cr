require "./popup"
require "./text_input"
require "./combo_box_item"
require "./scroll_view"
require "../layout/vstack"

module CrymbleUI
  # ComboBoxPopup - A popup container for ComboBox dropdown
  #
  # Architecture:
  # - Contains TextInput at top for filtering
  # - ScrollView containing VStack with ComboBoxItems
  # - Handles arrow key navigation via TextInputEvent
  # - ScrollView provides scrolling with scrollbar indicator
  #
  # ## Usage
  #
  # ```
  # popup = ComboBoxPopup.new(
  #   items: ["Apple", "Banana", "Cherry"],
  #   selected_index: 0,
  #   max_height: 200.0
  # )
  # popup.on_select = ->(idx, val) { ... }
  # popup.on_cancel = -> { ... }
  # ```
  class ComboBoxPopup < Popup
    # Layout constants
    ITEM_SPACING      = 0.0
    FLASH_INTERVAL_MS = 300

    # Index reported to on_select when an editable popup commits free-typed text
    # that is not one of @all_items — distinguishes a custom value from a real
    # item pick.
    CUSTOM_INDEX = -1

    # Override Popup's compute_bounds_for_layer: no border margin expansion
    def compute_bounds_for_layer(layer : Layer) : Rect
      absolute_bounds
    end

    TEXT_INPUT_PADDING = 4.0
    TEXT_INPUT_BORDER  = 1.0

    # Dynamic text input height (scales with font zoom)
    def text_input_height : Float64
      FontSizing.calculate_size(0) + TEXT_INPUT_PADDING * 2 + TEXT_INPUT_BORDER * 2
    end

    # All items (unfiltered)
    @all_items : Array(String)

    # Filtered items (matching current filter)
    @filtered_items : Array(String)

    # Currently highlighted index in filtered list
    @highlighted_index : Int32 = 0

    # in checkable mode the "(select all)" header is a first-class nav
    # element ABOVE the items. When this is set, the header carries the active
    # highlight and @highlighted_index is dormant. Always false in non-checkable
    # mode (no header) → the single ComboBox's index nav is byte-identical.
    @header_highlighted : Bool = false

    # Maximum height before scrolling kicks in
    @max_height : Float64?

    # Explicit width (settable so ComboBox.expand can lock it before filter triggers re-layout)
    property explicit_width : Float64?

    # Internal widgets
    @text_input : TextInput
    @scroll_view : ScrollView
    @vstack : VStack
    @item_widgets : Array(ComboBoxItem)

    # Text background colors for items
    @text_background_color : Color?
    @text_background_colors : Array(Color)?

    # When true, submitting text that matches no item commits it as a custom
    # value (on_select with CUSTOM_INDEX) instead of cancelling. Opt-in: default
    # combos stay pick-from-list only.
    @editable : Bool

    # Flash timer
    @flash_timer_id : Int32?
    @flash_state : Bool = true

    # Checkable mode (opt-in; default off → inert for single-select ComboBox).
    # When set, item gutters render a REAL tristate checkbox PULLED from this Source;
    # a gutter toggle (or the header) mutates the Source and fires on_change. No
    # push/refresh path.
    @selection_source : Source(Set(Int32))? = nil
    # Fired ONCE after any selection mutation (gutter toggle / select-all). The host
    # reads the new full set from the Source — no per-item deltas.
    property on_change : Proc(Nil)?
    # Tristate "(select all)" header item (real child widget) inserted in checkable mode.
    @header_item : ComboBoxItem?

    def checkable? : Bool
      !@selection_source.nil?
    end

    def selection_source : Source(Set(Int32))?
      @selection_source
    end

    # Callbacks
    property on_select : Proc(Int32, String, Nil)?
    property on_cancel : Proc(Nil)?

    def flash_timer_running? : Bool
      !@flash_timer_id.nil?
    end

    def max_height : Float64?
      @max_height
    end

    def item_count : Int32
      @item_widgets.size
    end

    def text_input : TextInput
      @text_input
    end

    def filtered_items : Array(String)
      @filtered_items
    end

    def editable? : Bool
      @editable
    end

    def highlighted_index : Int32
      @highlighted_index
    end

    # is the "(select all)" header the active (highlighted) nav element?
    def header_highlighted? : Bool
      @header_highlighted
    end

    # Enable checkable mode: items PULL their checked state from `source` and a gutter
    # toggle mutates it + fires `on_change`. Rebuilds the items (with pull closures) and
    # inserts the tristate header. Call before layout. There is NO push/refresh path —
    # a Source change re-renders the captured rows automatically (auto-capture).
    def enable_checkable(source : Source(Set(Int32)), on_change : Proc(Nil))
      @selection_source = source
      @on_change = on_change
      @text_input.toggle_on_space = true # Space toggles the highlighted row/header
      rebuild_items
      rebuild_header
    end

    # Expose the header item for testing
    def header_item : ComboBoxItem?
      @header_item
    end

    def initialize(
      items : Array(String) = [] of String,
      selected_index : Int32 = 0,
      max_height : Float64? = nil,
      width : Float64? = nil,
      background_color : Color? = nil,
      border_color : Color? = nil,
      padding : Float64 = 4.0,
      id : String? = nil,
      @text_background_color : Color? = nil,
      @text_background_colors : Array(Color)? = nil,
      @editable : Bool = false,
    )
      # Initialize all instance variables before super
      @all_items = items
      @filtered_items = items.dup
      @max_height = max_height
      @explicit_width = width
      @highlighted_index = selected_index.clamp(0, [items.size - 1, 0].max)
      @item_widgets = [] of ComboBoxItem
      @text_input = TextInput.new(value: "", width: width)
      @vstack = VStack.new
      @scroll_view = ScrollView.new
      @selection_source = nil
      @on_change = nil
      @header_item = nil

      super(
        width: width,
        height: nil, # Auto-size height (up to max_height)
        background_color: background_color,
        border_color: border_color,
        padding: padding,
        z_index: 1000,
        id: id
      )

      # Wire up widgets after super
      @text_input.parent = self
      setup_text_input_events
      @children << @text_input

      # ScrollView contains VStack
      @scroll_view.set_content(@vstack)
      @scroll_view.parent = self
      @children << @scroll_view

      # Build initial item widgets
      rebuild_items

      # Start flash timer for highlighted item
      start_highlight_flash
    end

    # Legacy constructor for compatibility
    def initialize(
      max_height : Float64? = nil,
      background_color : Color? = nil,
      border_color : Color? = nil,
      padding : Float64 = 0.0,
      id : String? = nil,
    )
      # Initialize all instance variables before super
      @all_items = [] of String
      @filtered_items = [] of String
      @max_height = max_height
      @explicit_width = nil
      @highlighted_index = 0
      @item_widgets = [] of ComboBoxItem
      @text_input = TextInput.new(value: "")
      @vstack = VStack.new
      @scroll_view = ScrollView.new
      @text_background_color = nil
      @text_background_colors = nil
      @editable = false
      @selection_source = nil
      @on_change = nil
      @header_item = nil

      super(
        width: nil,
        height: nil,
        background_color: background_color,
        border_color: border_color,
        padding: padding,
        z_index: 1000,
        id: id
      )

      # Wire up widgets after super
      @text_input.parent = self
      setup_text_input_events
      @children << @text_input

      # ScrollView contains VStack
      @scroll_view.set_content(@vstack)
      @scroll_view.parent = self
      @children << @scroll_view
    end

    # Set up TextInput event handling
    private def setup_text_input_events
      @text_input.on_event = ->(value : String, event : TextInputEvent) {
        handle_text_input_event(value, event)
        nil
      }
    end

    # Handle TextInput events
    private def handle_text_input_event(value : String, event : TextInputEvent)
      case event
      when .change?
        filter_items(value)
      when .submit?
        select_highlighted
      when .cancel?, .blur?
        @on_cancel.try(&.call)
      when .arrow_up?
        move_highlight(-1)
      when .arrow_down?
        move_highlight(+1)
      when .toggle?
        toggle_highlighted
      end
    end

    # Space toggles the active nav element — the header (select-all/none) or
    # the highlighted row (membership). Both reuse the widget's own on_toggle (the
    # same path a gutter click takes), so there is one toggle implementation. Keeps
    # the popup open (the host's on_change fires, the popup is NOT collapsed).
    private def toggle_highlighted
      active = @header_highlighted ? @header_item : @item_widgets[@highlighted_index]?
      active.try { |w| w.on_toggle.try(&.call) }
    end

    # Filter items by prefix
    def filter_items(prefix : String)
      prefix_lower = prefix.downcase

      @filtered_items = @all_items.select do |item|
        prefix.empty? || item.downcase.starts_with?(prefix_lower)
      end

      @highlighted_index = 0 # Reset to first match
      @header_highlighted = false # a keystroke re-homes the highlight to the first match, not the header
      rebuild_items
      mark_needs_layout
    end

    # Move highlight up or down. In checkable mode the "(select all)" header sits
    # ABOVE the items: ArrowUp from the first item lands on the header; ArrowDown
    # from the header returns to the first item. Non-checkable mode is unchanged —
    # plain item-index nav (the header path is dead, @header_highlighted stays false).
    def move_highlight(delta : Int32)
      if checkable?
        if @header_highlighted
          # Leave the header downward only if there is an item to land on.
          if delta > 0 && !@filtered_items.empty?
            @header_highlighted = false
            @highlighted_index = 0
          end
        elsif delta < 0 && @highlighted_index <= 0
          @header_highlighted = true # step up off the first item onto the header
        elsif !@filtered_items.empty?
          @highlighted_index = (@highlighted_index + delta).clamp(0, @filtered_items.size - 1)
        end
      else
        return if @filtered_items.empty?
        @highlighted_index = (@highlighted_index + delta).clamp(0, @filtered_items.size - 1)
      end
      update_highlight
      ensure_highlighted_visible
      # NO container-level mark_needs_render here. It marked the POPUP itself NeedsRender,
      # and selective re-render then repainted the container over its CLEAN direct children's
      # regions without repainting them — blanking the "(select all)" header (the reported
      # "vanishes on the first arrow" bug). update_highlight's reactive `highlighted=` /
      # `focus_highlighted=` setters already dirty the widgets that actually changed (items
      # and/or the header), so they repaint; an unchanged header is left untouched, not wiped.
    end

    # Update visual highlight on items (and, in checkable mode, the header). Exactly
    # one element is active: the header when @header_highlighted, else the row at
    # @highlighted_index. The active element flashes (focus_highlighted) in sync.
    private def update_highlight
      @item_widgets.each_with_index do |item, idx|
        is_highlighted = !@header_highlighted && idx == @highlighted_index
        item.highlighted = is_highlighted
        item.focus_highlighted = is_highlighted && @flash_state
      end
      if hdr = @header_item
        hdr.highlighted = @header_highlighted
        hdr.focus_highlighted = @header_highlighted && @flash_state
      end
    end

    # Start the flash timer for highlighted item
    def start_highlight_flash
      # Start highlighted (immediate visual feedback)
      @flash_state = true
      update_flash_state(true)

      @flash_timer_id = Widget.scheduler.schedule(FLASH_INTERVAL_MS.milliseconds, repeating: true) do
        toggle_highlight_flash
      end
    end

    # Stop the flash timer
    def stop_highlight_flash
      if timer_id = @flash_timer_id
        Widget.scheduler.cancel(timer_id)
        @flash_timer_id = nil
      end
      # Reset all items (and the header) to not flashing
      @item_widgets.each { |item| item.focus_highlighted = false }
      @header_item.try { |hdr| hdr.focus_highlighted = false }
    end

    private def toggle_highlight_flash
      @flash_state = !@flash_state
      update_flash_state(@flash_state)
    end

    private def update_flash_state(highlighted : Bool)
      if @header_highlighted
        @header_item.try { |hdr| hdr.focus_highlighted = highlighted }
      else
        @item_widgets[@highlighted_index]?.try { |item| item.focus_highlighted = highlighted }
      end
    end

    # Select the currently highlighted item. In an editable popup, the typed
    # text takes precedence: text that exactly matches an item picks that item;
    # any other non-empty text commits as a custom value (CUSTOM_INDEX). Empty
    # text falls through to the highlighted item — so navigating the list with
    # arrows and pressing Enter behaves as usual.
    def select_highlighted
      # in a checkable (multi-select) popup, Enter CONFIRMS the selection
      # the user built via toggles and CLOSES — it must NOT collapse the selection
      # to the highlighted row (that is the single-select body-click semantics). The
      # selection lives in @selection_source, so the close path preserves it; there
      # is no separate "confirm" callback because closing IS the confirmation.
      if checkable?
        @on_cancel.try(&.call) # close; @selection_source already holds the choice
        return
      end

      if @editable
        typed = @text_input.value
        if idx = @all_items.index(typed)
          @on_select.try(&.call(idx, typed))
          return
        elsif !typed.empty?
          @on_select.try(&.call(CUSTOM_INDEX, typed))
          return
        end
      end

      if @filtered_items.empty? || @highlighted_index < 0 || @highlighted_index >= @filtered_items.size
        # No valid selection — cancel (close without selecting)
        @on_cancel.try(&.call)
        return
      end

      value = @filtered_items[@highlighted_index]
      original_index = @all_items.index(value) || 0
      @on_select.try(&.call(original_index, value))
    end

    # Rebuild item widgets from filtered items.
    # In checkable mode the items get ✓/☐ gutters and on_toggle is wired.
    private def rebuild_items
      @vstack.children.clear
      @item_widgets.clear

      @filtered_items.each_with_index do |item_text, idx|
        # Find original index for callback and per-item colors
        original_index = @all_items.index(item_text) || 0

        # Determine text_background_color for this item
        item_text_bg = if colors = @text_background_colors
                         colors[original_index]? || @text_background_color
                       else
                         @text_background_color
                       end

        item = ComboBoxItem.new(item_text, text_background_color: item_text_bg) do |_value|
          @on_select.try(&.call(original_index, item_text))
        end

        # Checkable mode: the item PULLS its state from @selection_source (read inside
        # the item's to_primitives → auto-captures), and a gutter toggle mutates the
        # Source + fires on_change. oi is captured per row (ORIGINAL, not filtered, index).
        if checkable?
          oi = original_index
          item.check_state_fn = -> {
            src = @selection_source
            (src && src.get.includes?(oi)) ? CheckState::Checked : CheckState::Unchecked
          }
          item.on_toggle = -> {
            if src = @selection_source
              cur = src.get
              now = !cur.includes?(oi)
              src.set(now ? (cur.dup << oi) : cur.dup.tap(&.delete(oi)))
              @on_change.try(&.call)
            end
          }
        end

        item.highlighted = (!@header_highlighted && idx == @highlighted_index)
        item.parent = @vstack
        @vstack.children << item
        @item_widgets << item
      end

      # Mark children as needing layout
      @vstack.mark_needs_layout
      mark_needs_layout
    end

    # ========== CHECKABLE MODE HELPERS ==========

    # Height contributed by the header row (0 if not checkable)
    private def header_item_height : Float64
      @header_item ? ComboBoxItem::PADDING * 2 + FontSizing.calculate_size(0) : 0.0
    end

    # Build (or rebuild) the tristate "select all / none" header item.
    # The header is a real child widget so it receives normal hit dispatch.
    private def rebuild_header
      # Remove any old header from @children
      if old_hdr = @header_item
        @children.delete(old_hdr)
      end

      hdr = ComboBoxItem.new("(select all)", text_background_color: nil) do |_|
        toggle_all # body-click toggles all/none
      end
      # The header PULLS a tristate over ALL items (read inside to_primitives).
      hdr.check_state_fn = -> { header_check_state }
      hdr.on_toggle = -> { toggle_all } # gutter-click toggles all/none too

      hdr.parent = self
      # Insert header as the second child (after TextInput, before ScrollView).
      ti_idx = @children.index(@text_input) || 0
      @children.insert(ti_idx + 1, hdr)
      @header_item = hdr
    end

    # Tristate over ALL items: none → Unchecked, all → Checked, some → Indeterminate.
    private def header_check_state : CheckState
      src = @selection_source
      return CheckState::Unchecked unless src
      return CheckState::Unchecked if @all_items.empty?
      sel = src.get
      n = (0...@all_items.size).count { |i| sel.includes?(i) }
      if n == 0
        CheckState::Unchecked
      elsif n == @all_items.size
        CheckState::Checked
      else
        CheckState::Indeterminate
      end
    end

    # Header click: select all if not already all-selected, else clear all. Mutates the
    # Source (immediate visual) and fires on_change ONCE — the host reads the new full
    # set, so the next rebuild's build-value reconciles to the same selection.
    private def toggle_all
      src = @selection_source
      return unless src
      all_on = !@all_items.empty? && (0...@all_items.size).all? { |i| src.get.includes?(i) }
      if all_on
        src.set(Set(Int32).new)
      else
        newset = Set(Int32).new
        @all_items.each_index { |i| newset << i }
        src.set(newset)
      end
      @on_change.try(&.call)
    end

    # Focus the TextInput
    def focus_text_input
      # IMPORTANT: request_focus FIRST, then enter_edit_mode
      # Because on_focus resets edit_mode to QuickEntry
      @text_input.request_focus
      # Enter FullEdit mode so Enter key fires Submit (not mode toggle)
      @text_input.enter_edit_mode
    end

    # Override label for path_id generation
    def label : String?
      "combo_box_popup"
    end

    # Get item widgets (for testing)
    def item_widgets : Array(ComboBoxItem)
      @item_widgets
    end

    # ========== LAYOUT ==========

    # Measure - TextInput + ScrollView, respect max_height
    def measure(constraints : BoxConstraints) : Size
      # TextInput at top
      text_input_size = @text_input.measure(BoxConstraints.loose(Size.new(
        constraints.max_width,
        text_input_height
      )))

      # Measure VStack content (unconstrained height) to determine ScrollView size
      vstack_constraints = BoxConstraints.loose(Size.new(
        constraints.max_width,
        Float64::INFINITY
      ))
      vstack_size = @vstack.measure(vstack_constraints)

      # Header height (checkable mode only)
      header_h = header_item_height

      # Total size
      width = @explicit_width || [text_input_size.width, vstack_size.width].max + padding * 2
      height = text_input_size.height + header_h + vstack_size.height + padding * 2

      # Respect max_height if set
      if max_h = @max_height
        height = [height, max_h].min
      end

      # Respect constraints
      width = width.clamp(constraints.min_width, constraints.max_width)
      height = height.clamp(constraints.min_height, constraints.max_height)

      Size.new(width, height)
    end

    # Layout popup with TextInput and ScrollView
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)

      # Populate layer.widgets
      if layer = @internal_layer
        layer.widgets.clear
        layer.widgets << self
      end

      # Layout TextInput at top
      text_constraints = BoxConstraints.tight(Size.new(
        @bounds.width - padding * 2,
        text_input_height
      ))
      @text_input.layout(text_constraints, Vec2.new(padding, padding))

      # Layout header (if checkable mode)
      actual_text_input_height = @text_input.bounds.height
      header_top = padding + actual_text_input_height
      header_h = header_item_height
      if hdr = @header_item
        hdr_constraints = BoxConstraints.tight(Size.new(
          @bounds.width - padding * 2,
          header_h
        ))
        hdr.layout(hdr_constraints, Vec2.new(padding, header_top))
      end

      # Layout ScrollView below TextInput (and below header if present)
      scroll_top = header_top + header_h
      available_height = @bounds.height - scroll_top - padding
      scroll_constraints = BoxConstraints.tight(Size.new(
        @bounds.width - padding * 2,
        available_height
      ))
      @scroll_view.layout(scroll_constraints, Vec2.new(padding, scroll_top))

      # Scroll to show highlighted item (important on initial open)
      ensure_highlighted_visible
    end

    # ScrollView handles scrolling via mouse wheel automatically
    # No manual scroll handling needed

    # Scroll to ensure highlighted item is visible
    private def ensure_highlighted_visible
      return if @header_highlighted # the header sits above the scroll area — always visible
      return if @filtered_items.empty?
      return if @highlighted_index < 0 || @highlighted_index >= @item_widgets.size

      item = @item_widgets[@highlighted_index]
      @scroll_view.scroll_to_visible(item)
    end
  end
end
