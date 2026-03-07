require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"
require "../input/shortcut_format"

module CrymbleUI
  # Button widget with text and click handling
  class Button < Widget
    include PrimitiveBuilder
    include FontScalable
    # Hover brightness offset (dynamic - must follow theme changes)

    # Text content
    @text : String

    def text : String
      @text
    end

    def text=(value : String)
      @text = value
      mark_needs_render
    end

    # Shortcut (optional)
    @shortcut : String?         # Raw shortcut string (e.g., "^S")
    @shortcut_display : String? # Platform-specific display (e.g., "Ctrl+S")

    def shortcut : String?
      @shortcut
    end

    def shortcut=(value : String?)
      @shortcut = value
      @shortcut_display = ShortcutFormat.to_display(value)
      mark_needs_render
    end

    # Parse shortcut to display format

    # Get display text with shortcut (if present)
    def display_text : String
      if sc = @shortcut_display
        "#{@text} (#{sc})"
      else
        @text
      end
    end

    # Visual properties
    render_property text_color : Color
    render_property background_color : Color
    render_property border_color : Color
    layout_property padding : Float64

    # Hover state
    @hovered : Bool = false

    property on_click_callback : Proc(Nil)?

    # Primary constructor - accepts optional on_click Proc
    def initialize(
      @text : String,
      shortcut : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      @text_color : Color = Theme.current.button_text,
      @background_color : Color = Theme.current.button_background,
      @border_color : Color = Theme.current.button_border,
      @padding : Float64 = 10.0,
      on_click : Proc(Nil)? = nil,
    )
      @font_scale = font_scale
      super(id: id)
      @shortcut = shortcut
      @shortcut_display = Shortcut.to_display(shortcut)
      @on_click_callback = on_click
    end

    # Convenience constructor for block syntax: Button.new("text") { click_handler }
    def self.new(
      text : String,
      shortcut : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : Color = Theme.current.button_text,
      background_color : Color = Theme.current.button_background,
      border_color : Color = Theme.current.button_border,
      padding : Float64 = 10.0,
      &block : -> Nil
    )
      new(text, shortcut, id, font_scale, text_color, background_color, border_color, padding, on_click: block)
    end

    # Override label for path_id generation
    def label : String?
      @text
    end

    # Measure button size including padding
    def measure(constraints : BoxConstraints) : Size
      Widget.increment_measure_count # Instrumentation for performance tests
      # Use actual text measurement (visual bounds) with display_text (includes shortcut)
      text_size = measure_text(display_text, font_size)
      text_width = text_size.width
      text_height = text_size.height

      # Add padding on all sides
      width = text_width + (@padding * 2)
      height = text_height + (@padding * 2)

      # Constrain to box constraints
      size = Size.new(width, height)
      constraints.constrain(size)
    end

    # Layout the button at the given position
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      new_bounds = Rect.new(position, size)

      # Check if size changed (requires re-rendering due to text centering)
      # Position-only changes don't require re-render (widget-local coords)
      old_bounds = @bounds
      size_changed = old_bounds.nil? || (old_bounds.width != new_bounds.width || old_bounds.height != new_bounds.height)

      @bounds = new_bounds

      if size_changed
        mark_needs_render
      end
    end

    # Generate primitives for rendering
    # Primitives are in widget-local coordinates (0,0 origin)
    # Renderer will add widget.bounds offset when drawing
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      # Calculate hover/focus colors if hovered or focus_highlighted
      bg_color = @background_color
      border_color = @border_color

      if @hovered || focus_highlighted?
        hover_brightness = Theme.current.brightness_hover
        bg_color = @background_color.highlight(hover_brightness)
        border_color = @border_color.highlight(hover_brightness)
      end

      # Calculate text position in widget-local coordinates
      text_size = measure_text(display_text, font_size)
      # Center both horizontally and vertically within bounds
      text_x = (bounds.width - text_size.width) / 2.0
      text_y = (bounds.height - font_size) / 2.0
      text_position = Vec2.new(text_x, text_y)

      # Create widget-local rect at (0,0)
      local_rect = Rect.new(Vec2.zero, Size.new(bounds.width, bounds.height))

      primitives do
        fill_rect(local_rect, bg_color)
        draw_rect(local_rect, border_color, 1.0)
        draw_text(display_text, text_position, @text_color, @font_scale)
      end
    end

    # Handle mouse enter (hover start)
    def on_mouse_enter
      @hovered = true
      mark_needs_render
    end

    # Handle mouse exit (hover end)
    def on_mouse_exit
      @hovered = false
      mark_needs_render
    end

    # Override on_click to call callback
    def on_click
      @on_click_callback.try &.call
    end

    # Button is focusable for keyboard navigation
    def focusable? : Bool
      true
    end

    # Trigger click programmatically (used for keyboard activation with Enter/Space)
    def trigger_click
      on_click
    end
  end
end
