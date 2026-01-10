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
  # ```crystal
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
    ITEM_SPACING = 0.0
    FLASH_INTERVAL_MS = 300
    TEXT_INPUT_PADDING = 4.0
    TEXT_INPUT_BORDER = 1.0

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

    # Maximum height before scrolling kicks in
    @max_height : Float64?

    # Explicit width
    @explicit_width : Float64?

    # Internal widgets
    @text_input : TextInput
    @scroll_view : ScrollView
    @vstack : VStack
    @item_widgets : Array(ComboBoxItem)

    # Text background colors for items
    @text_background_color : Color?
    @text_background_colors : Array(Color)?

    # Flash timer
    @flash_timer_id : Int32?
    @flash_state : Bool = true

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

    def highlighted_index : Int32
      @highlighted_index
    end

    def initialize(
      items : Array(String) = [] of String,
      selected_index : Int32 = 0,
      max_height : Float64? = nil,
      width : Float64? = nil,
      background_color : Color = Color.white,
      border_color : Color = Color.new(180, 180, 180, 255),
      padding : Float64 = 4.0,
      id : String? = nil,
      @text_background_color : Color? = nil,
      @text_background_colors : Array(Color)? = nil
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
      background_color : Color = Color.white,
      border_color : Color = Color.new(180, 180, 180, 255),
      padding : Float64 = 0.0,
      id : String? = nil
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
      end
    end

    # Filter items by prefix
    def filter_items(prefix : String)
      prefix_lower = prefix.downcase

      @filtered_items = @all_items.select do |item|
        prefix.empty? || item.downcase.starts_with?(prefix_lower)
      end

      @highlighted_index = 0 # Reset to first match
      rebuild_items
      mark_needs_layout
    end

    # Move highlight up or down
    def move_highlight(delta : Int32)
      return if @filtered_items.empty?

      @highlighted_index = (@highlighted_index + delta).clamp(0, @filtered_items.size - 1)
      update_highlight
      ensure_highlighted_visible
      mark_needs_render
    end

    # Update visual highlight on items
    private def update_highlight
      @item_widgets.each_with_index do |item, idx|
        is_highlighted = (idx == @highlighted_index)
        item.highlighted = is_highlighted
        # Sync flash state with highlighted item
        item.focus_highlighted = is_highlighted && @flash_state
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
      # Reset all items to not flashing
      @item_widgets.each { |item| item.focus_highlighted = false }
    end

    private def toggle_highlight_flash
      @flash_state = !@flash_state
      update_flash_state(@flash_state)
    end

    private def update_flash_state(highlighted : Bool)
      if idx = @highlighted_index
        @item_widgets[idx]?.try { |item| item.focus_highlighted = highlighted }
      end
    end

    # Select the currently highlighted item
    def select_highlighted
      return if @filtered_items.empty?
      return if @highlighted_index < 0 || @highlighted_index >= @filtered_items.size

      value = @filtered_items[@highlighted_index]
      original_index = @all_items.index(value) || 0
      @on_select.try(&.call(original_index, value))
    end

    # Rebuild item widgets from filtered items
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
        item.highlighted = (idx == @highlighted_index)
        item.parent = @vstack
        @vstack.children << item
        @item_widgets << item
      end

      # Mark children as needing layout
      @vstack.mark_needs_layout
      mark_needs_layout
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

      # Total size
      width = @explicit_width || [text_input_size.width, vstack_size.width].max + @padding * 2
      height = text_input_size.height + vstack_size.height + @padding * 2

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

      # Update internal layer bounds
      if layer = @internal_layer
        # BUG FIX: Use absolute_bounds for layer positioning (layers need absolute coordinates)
        # Previously used @bounds.dup which is relative to parent
        abs = absolute_bounds
        layer.bounds = Rect.new(abs.x, abs.y, abs.width, abs.height)
        layer.widgets.clear
        layer.widgets << self
      end

      # Layout TextInput at top
      text_constraints = BoxConstraints.tight(Size.new(
        @bounds.width - @padding * 2,
        text_input_height
      ))
      @text_input.layout(text_constraints, Vec2.new(@padding, @padding))

      # Layout ScrollView below TextInput
      # Use ACTUAL text input height (from bounds) to avoid gap from formula mismatch
      actual_text_input_height = @text_input.bounds.height
      scroll_top = @padding + actual_text_input_height
      available_height = @bounds.height - scroll_top - @padding
      scroll_constraints = BoxConstraints.tight(Size.new(
        @bounds.width - @padding * 2,
        available_height
      ))
      @scroll_view.layout(scroll_constraints, Vec2.new(@padding, scroll_top))

      # Scroll to show highlighted item (important on initial open)
      ensure_highlighted_visible
    end

    # ScrollView handles scrolling via mouse wheel automatically
    # No manual scroll handling needed

    # Scroll to ensure highlighted item is visible
    private def ensure_highlighted_visible
      return if @filtered_items.empty?
      return if @highlighted_index < 0 || @highlighted_index >= @item_widgets.size

      item = @item_widgets[@highlighted_index]
      @scroll_view.scroll_to_visible(item)
    end
  end
end
