require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"

module CrymbleUI
  # ComboBoxItem widget - a selectable row in a ComboBox
  #
  # ## Usage
  #
  # ```
  # combo_box_item("Apple", value: "apple") { |val| puts "Selected: #{val}" }
  # combo_box_item("Banana") # value defaults to label
  # ```
  #
  class ComboBoxItem < Widget
    include PrimitiveBuilder
    include FontScalable

    # Layout constants
    PADDING = 8.0
    # Two brightness levels for prominent flash toggle effect
    HIGHLIGHT_BRIGHTNESS_HIGH = 0.20
    HIGHLIGHT_BRIGHTNESS_LOW  = 0.08

    # Dynamic item height (scales with font zoom)
    def item_height : Float64
      FontSizing.calculate_size(font_scale) + PADDING * 2
    end

    # Label text
    reactive_property label_text : String

    # Value for data binding (returned in callback)
    @value : String

    def value : String
      @value
    end

    def value=(val : String)
      @value = val
    end

    # Visual properties
    theme_property text_color, combo_text
    theme_property background_color, combo_background
    theme_property hover_color, combo_hover
    theme_property selected_color, combo_selected
    reactive_property text_background_color : Color?

    # State
    reactive_property selected : Bool = false
    @hovered : Bool = false

    def selected? : Bool
      selected
    end

    # Alias: highlighted = selected (for ComboBoxPopup arrow key navigation)
    def highlighted? : Bool
      selected
    end

    def highlighted=(value : Bool)
      self.selected = value
    end

    # When non-nil, this item is in "checkable" mode.
    # True = checked (✓), false = unchecked (☐).
    # The gutter region click fires @on_toggle; body region keeps the existing on_click path.
    property checked : Bool? = nil

    # Gutter width for the ✓/☐ column (pixels from left edge)
    GUTTER_WIDTH = 20.0

    # Toggle callback — fired on gutter click for checkable items
    @on_toggle : Proc(Nil)?

    property on_toggle : Proc(Nil)?

    # Click callback
    @on_click_callback : Proc(String, Nil)?

    # Primary constructor - accepts optional on_click Proc
    def initialize(
      label : String,
      value : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : Color? = nil,
      background_color : Color? = nil,
      hover_color : Color? = nil,
      selected_color : Color? = nil,
      text_background_color : Color? = nil,
      on_click : Proc(String, Nil)? = nil,
    )
      @label_text = Source(String).new(label)
      @text_background_color = Source(Color?).new(text_background_color)
      @font_scale.set(font_scale)
      super(id: id)
      @value = value || label
      @text_color = text_color
      @background_color = background_color
      @hover_color = hover_color
      @selected_color = selected_color
      @on_click_callback = on_click
    end

    # Convenience constructor for block syntax: ComboBoxItem.new("label") { |value| handler }
    def self.new(
      label : String,
      value : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : Color? = nil,
      background_color : Color? = nil,
      hover_color : Color? = nil,
      selected_color : Color? = nil,
      text_background_color : Color? = nil,
      &block : String -> Nil
    )
      new(label, value, id, font_scale, text_color, background_color, hover_color, selected_color, text_background_color, on_click: block)
    end

    # Override label for path_id generation
    def label : String?
      "listboxitem"
    end

    # Measure item size
    def measure(constraints : BoxConstraints) : Size
      text_size = measure_text(label_text, font_size)
      width = text_size.width + PADDING * 2
      height = item_height
      Size.new(width, height)
    end

    # Layout
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      # Use constraint width if available (fill parent)
      width = constraints.max_width.finite? ? constraints.max_width : size.width
      @bounds = Rect.new(position.x, position.y, width, size.height)
    end

    # Mouse events
    def on_mouse_enter
      @hovered = true
      mark_needs_render
    end

    def on_mouse_exit
      @hovered = false
      mark_needs_render
    end

    # For checkable items: split the click region in on_mouse_up so we can
    # fire toggle (stay open) vs select (close) with no double-fire.
    def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
      return unless button == MouseButton::Left
      if @checked != nil
        # Checkable mode: decide by horizontal position
        local_x = point.x - absolute_bounds.x
        if local_x < GUTTER_WIDTH
          @on_toggle.try &.call
        else
          @on_click_callback.try &.call(@value)
        end
      end
      # Non-checkable items: fall through to on_click (trigger_click path)
    end

    def on_click
      # For checkable items on_mouse_up already handled everything — skip double-fire.
      return if @checked != nil
      @on_click_callback.try &.call(@value)
    end

    # Generate primitives
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      # Determine background color based on state
      # text_background_color replaces background_color when set (for per-item customization)
      base_bg = text_background_color || background_color

      bg_color = if selected
                   # Flash by toggling between two brightness levels for prominent effect
                   brightness = focus_highlighted? ? HIGHLIGHT_BRIGHTNESS_HIGH : HIGHLIGHT_BRIGHTNESS_LOW
                   base_bg.highlight(brightness)
                 elsif @hovered
                   base_bg.highlight(HIGHLIGHT_BRIGHTNESS_LOW) # Subtle hover
                 else
                   base_bg
                 end

      # Background rect
      bg_rect = Rect.new(0.0, 0.0, bounds.width, bounds.height)

      # Text position (vertically centered)
      text_x = PADDING
      text_y = (bounds.height - font_size) / 2.0
      text_pos = Vec2.new(text_x, text_y)

      primitives do
        fill_rect(bg_rect, bg_color)
        # MultiComboBox checkbox items show a ✓/☐ gutter. Read the reactive getters
        # (label_text / text_color / font_scale), never the ivars — under t029 those are now
        # a Source / a raw ThemeColor override, not the painted value.
        if (c = checked) != nil
          gutter_pos = Vec2.new(2.0, text_y)
          glyph = c ? "✓" : "☐"
          draw_text(glyph, gutter_pos, text_color, font_scale)
          # Shift label text to the right of the gutter
          draw_text(label_text, Vec2.new(GUTTER_WIDTH + PADDING, text_y), text_color, font_scale)
        else
          draw_text(label_text, text_pos, text_color, font_scale)
        end
      end
    end
  end
end
