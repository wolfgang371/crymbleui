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
    reactive_property text : String

    # Shortcut (optional) — raw string (e.g., "^S"); reactive so it re-renders on change
    reactive_property shortcut : String? = nil

    # Platform-specific display (e.g., "Ctrl+S") — derived live from the raw shortcut
    def shortcut_display : String?
      ShortcutFormat.to_display(shortcut)
    end

    # Get display text with shortcut (if present)
    def display_text : String
      if sc = shortcut_display
        "#{text} (#{sc})"
      else
        text
      end
    end

    # Visual properties — theme colors resolve live (nil = follow Theme.current; explicit value wins)
    theme_property text_color, button_text
    theme_property background_color, button_background
    theme_property border_color, button_border
    reactive_property text_align : TextAlign = TextAlign::Center
    reactive_property padding : Float64, layout: true

    # Hover state (reactive: read in to_primitives auto-captures; the setter re-renders)
    reactive_property hovered : Bool = false

    property on_click_callback : Proc(Nil)?

    # Primary constructor - accepts optional on_click Proc
    def initialize(
      text : String,
      shortcut : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : ThemeColor? = nil,
      background_color : ThemeColor? = nil,
      border_color : ThemeColor? = nil,
      text_align : TextAlign = TextAlign::Center,
      padding : Float64 = 10.0,
      on_click : Proc(Nil)? = nil,
    )
      @text = Source(String).new(text)
      @text_align = Source(TextAlign).new(text_align)
      @padding = Source(Float64).new(padding)
      @text_color = text_color
      @background_color = background_color
      @border_color = border_color
      @font_scale.set(font_scale)
      super(id: id)
      @shortcut = Source(String?).new(shortcut)
      @on_click_callback = on_click
    end

    # Convenience constructor for block syntax: Button.new("text") { click_handler }
    def self.new(
      text : String,
      shortcut : String? = nil,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : ThemeColor? = nil,
      background_color : ThemeColor? = nil,
      border_color : ThemeColor? = nil,
      text_align : TextAlign = TextAlign::Center,
      padding : Float64 = 10.0,
      &block : -> Nil
    )
      new(text, shortcut, id, font_scale, text_color, background_color, border_color, text_align, padding, on_click: block)
    end

    # Override label for path_id generation
    def label : String?
      text
    end

    # Measure button size including padding
    def measure(constraints : BoxConstraints) : Size
      Widget.increment_measure_count # Instrumentation for performance tests
      # Use actual text measurement (visual bounds) with display_text (includes shortcut)
      text_size = measure_text(display_text, font_size)
      text_width = text_size.width
      text_height = text_size.height

      # Add padding on all sides
      width = text_width + (padding * 2)
      height = text_height + (padding * 2)

      # Constrain to box constraints
      size = Size.new(width, height)
      constraints.constrain(size)
    end

    # Layout the button at the given position
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)
    end

    # Generate primitives for rendering
    # Primitives are in widget-local coordinates (0,0 origin)
    # Renderer will add widget.bounds offset when drawing
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      # Calculate hover/focus colors if hovered or focus_highlighted.
      # Read the getters (live theme), NOT the @ivars (nullable override store). Locals are renamed
      # (bg/bd/txt) so they don't shadow the same-named getters on the RHS.
      bg_color = background_color
      bd_color = border_color
      txt_color = text_color

      if !enabled?
        txt_color = Color.new(txt_color.r, txt_color.g, txt_color.b, (txt_color.a // 3).to_u8)
      elsif hovered || focus_highlighted?
        hover_brightness = Theme.current.brightness_hover
        bg_color = bg_color.highlight(hover_brightness)
        bd_color = bd_color.highlight(hover_brightness)
      end

      # Calculate text position in widget-local coordinates
      text_size = measure_text(display_text, font_size)
      # Horizontal alignment based on text_align property
      text_x = case text_align
      when TextAlign::Left  then padding
      when TextAlign::Right then bounds.width - text_size.width - padding
      else                       (bounds.width - text_size.width) / 2.0 # Center (default)
      end
      text_y = vcentered_text_y(bounds.height, font_scale)
      text_position = Vec2.new(text_x, text_y)

      # Create widget-local rect at (0,0)
      local_rect = Rect.new(Vec2.zero, Size.new(bounds.width, bounds.height))

      primitives do
        fill_rect(local_rect, bg_color)
        draw_rect(local_rect, bd_color, 1.0)
        draw_text(display_text, text_position, txt_color, font_scale)
      end
    end

    # Handle mouse enter (hover start)
    def on_mouse_enter
      self.hovered = true
    end

    # Handle mouse exit (hover end)
    def on_mouse_exit
      self.hovered = false
    end

    # Override on_click to call callback
    def on_click
      return unless enabled?
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
