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
      FontSizing.calculate_size(@font_scale) + PADDING * 2
    end

    # Label text
    @label : String

    def label_text : String
      @label
    end

    def label_text=(value : String)
      @label = value
      mark_needs_render
    end

    # Value for data binding (returned in callback)
    @value : String

    def value : String
      @value
    end

    def value=(val : String)
      @value = val
    end

    # Visual properties
    render_property text_color : Color
    render_property background_color : Color
    render_property hover_color : Color
    render_property selected_color : Color
    render_property text_background_color : Color?

    # State
    @selected : Bool = false
    @hovered : Bool = false

    def selected? : Bool
      @selected
    end

    def selected=(value : Bool)
      return if @selected == value
      @selected = value
      mark_needs_render
    end

    # Alias: highlighted = selected (for ComboBoxPopup arrow key navigation)
    def highlighted? : Bool
      @selected
    end

    def highlighted=(value : Bool)
      self.selected = value
    end

    # Click callback
    @on_click_callback : Proc(String, Nil)?

    # Primary constructor - accepts optional on_click Proc
    def initialize(
      label : String,
      value : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      @text_color : Color = Theme.current.combo_text,
      @background_color : Color = Theme.current.combo_background,
      @hover_color : Color = Theme.current.combo_hover,
      @selected_color : Color = Theme.current.combo_selected,
      @text_background_color : Color? = nil,
      on_click : Proc(String, Nil)? = nil,
    )
      @font_scale = font_scale
      super(id: id)
      @label = label
      @value = value || label
      @on_click_callback = on_click
    end

    # Convenience constructor for block syntax: ComboBoxItem.new("label") { |value| handler }
    def self.new(
      label : String,
      value : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : Color = Theme.current.combo_text,
      background_color : Color = Theme.current.combo_background,
      hover_color : Color = Theme.current.combo_hover,
      selected_color : Color = Theme.current.combo_selected,
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
      text_size = measure_text(@label, font_size)
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

    def on_click
      @on_click_callback.try &.call(@value)
    end

    # Generate primitives
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      # Determine background color based on state
      # text_background_color replaces background_color when set (for per-item customization)
      base_bg = @text_background_color || @background_color

      bg_color = if @selected
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
        draw_text(@label, text_pos, @text_color, @font_scale)
      end
    end
  end
end
