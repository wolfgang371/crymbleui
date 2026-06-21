require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"

module CrymbleUI
  # Checkbox widget for boolean or tristate selection.
  #
  # ## Overview
  #
  # Checkbox provides both binary (bool) and tristate (CheckState) support.
  # The type is auto-detected based on the parameter you pass.
  #
  # ## Basic Usage (Boolean)
  #
  # ```
  # # Manual control with block
  # state accepted : Bool = false
  # checkbox("Accept terms", checked: self.accepted) do
  #   self.accepted = !self.accepted
  # end
  #
  # # Auto-toggle with macro (no block)
  # state accepted : Bool = false
  # checkbox("Accept terms", bind: accepted)
  # ```
  #
  # ## Tristate Usage
  #
  # ```
  # state select_all : CheckState = CheckState::Unchecked
  # checkbox("Select all", state: self.select_all) do
  #   self.select_all = case self.select_all
  #                     when CheckState::Unchecked     then CheckState::Checked
  #                     when CheckState::Checked       then CheckState::Indeterminate
  #                     when CheckState::Indeterminate then CheckState::Unchecked
  #                     end
  # end
  # ```
  #
  # ## How It Works
  #
  # 1. **User clicks** → Checkbox calls the provided block
  # 2. **Block executes** → User code updates state (with any logic)
  # 3. **State changes** → Triggers rebuild via state macro
  # 4. **Next frame** → Checkbox renders with new checked/state value
  #
  # ## Benefits
  #
  # - **User control**: Block decides what happens on click
  # - **Flexible logic**: Can add validation, side effects, etc.
  # - **Efficient**: State change triggers rebuild, checkbox updates automatically
  # - **Type-safe**: Bool and CheckState are distinct types
  #
  class Checkbox < Widget
    include PrimitiveBuilder
    include FontScalable

    # Visual properties
    reactive_property text : String
    reactive_property checked : Bool
    reactive_property check_state : CheckState
    theme_property text_color, checkbox_text
    reactive_property box_scale : Int32, layout: true # Relative scale like font_scale: -2, -1, 0, +1, +2
    theme_property box_color, checkbox_box
    theme_property check_color, checkbox_check
    reactive_property background_color : Color?
    reactive_property spacing : Float64, layout: true

    # Dynamic effective box size (always scales with zoom via FontSizing)
    def effective_box_size : Float64
      FontSizing.calculate_size(box_scale) * 1.15 # 15% larger than font at same scale
    end

    # Dynamic checkmark line thickness
    def checkmark_line_thickness : Float64
      effective_box_size * 0.2
    end

    # Dynamic checkmark junction radius
    def checkmark_junction_radius : Float64
      effective_box_size * 0.1
    end

    # Click callback
    @on_click : Proc(Nil)?

    # Primary constructor - accepts optional on_click Proc
    def initialize(
      text : String,
      checked : Bool = false,
      check_state : CheckState = CheckState::Unchecked,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : Color? = nil,
      box_scale : Int32 = 0, # Relative scale like font_scale: -2, -1, 0, +1, +2
      box_color : Color? = nil,
      check_color : Color? = nil,
      spacing : Float64 = 8.0,
      background_color : Color? = nil,
      on_click : Proc(Nil)? = nil,
    )
      @text = Source(String).new(text)
      @checked = Source(Bool).new(checked)
      @check_state = Source(CheckState).new(check_state)
      @background_color = Source(Color?).new(background_color)
      @box_scale = Source(Int32).new(box_scale)
      @spacing = Source(Float64).new(spacing)
      @font_scale.set(font_scale)
      super(id: id)
      @text_color = text_color
      @box_color = box_color
      @check_color = check_color
      @on_click = on_click
    end

    # Convenience constructor for block syntax: Checkbox.new("label") { handler }
    def self.new(
      text : String,
      checked : Bool = false,
      check_state : CheckState = CheckState::Unchecked,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : Color? = nil,
      box_scale : Int32 = 0,
      box_color : Color? = nil,
      check_color : Color? = nil,
      spacing : Float64 = 8.0,
      background_color : Color? = nil,
      &block : -> Nil
    )
      new(text, checked, check_state, id, font_scale, text_color, box_scale, box_color, check_color, spacing, background_color: background_color, on_click: block)
    end

    # Override label for path_id generation
    def label : String?
      "checkbox"
    end

    # Measure checkbox size
    def measure(constraints : BoxConstraints) : Size
      # Width: box + spacing + text width
      box = effective_box_size
      text_width = measure_text(text, font_size).width
      width = box + spacing + text_width

      # Height: max of box and font size
      height = [box, font_size].max + 4.0 # Extra padding

      constraints.constrain(Size.new(width, height))
    end

    # Layout the checkbox at the given position
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)
    end

    # Toggle checked state and fire callback.
    # Auto-toggles so Checkbox works without a user-provided block
    # (e.g. as a VirtualMatrix cell or standalone widget).
    def trigger_click
      self.checked = !checked
      @on_click.try &.call
    end

    # Checkbox is focusable for keyboard navigation
    def focusable? : Bool
      true
    end

    # Generate primitives for rendering
    # Primitives are in widget-local coordinates (0,0 origin)
    # Renderer will add widget.bounds offset when drawing
    # Focus highlight brightness (dynamic - must follow theme changes)

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      focus_brightness = Theme.current.brightness_focus
      # Get dynamic sizes
      box = effective_box_size
      line_thickness = checkmark_line_thickness
      junction_radius = checkmark_junction_radius

      # Calculate box bounds in widget-local coordinates (left-aligned)
      box_x = 0.0
      box_y = (bounds.height - box) / 2.0
      box_rect = Rect.new(box_x, box_y, box, box)

      # Determine actual state
      actual_state = if checked
                       CheckState::Checked
                     else
                       check_state
                     end

      # Calculate text position
      text_x = box_x + box + spacing
      text_y = vcentered_text_y(box, font_scale, box_y)
      text_position = Vec2.new(text_x, text_y)

      # Calculate box color (highlight when focus_highlighted, same as button hover)
      actual_box_color = focus_highlighted? ? box_color.highlight(focus_brightness) : box_color
      # Calculate text color (highlight when focus_highlighted for visible flash)
      actual_text_color = focus_highlighted? ? text_color.highlight(focus_brightness) : text_color

      primitives do
        if bg = background_color
          fill_rect(Rect.new(0.0, 0.0, bounds.width, bounds.height), bg)
        end
        # Box outline + state mark — the shared checkbox visual (PrimitiveBuilder#draw_check_glyph).
        # box_color carries the focus highlight; check_color stays the plain theme color.
        draw_check_glyph(actual_state, box_rect, box_color: actual_box_color, check_color: check_color,
          line_thickness: line_thickness, junction_radius: junction_radius)

        # Draw label text
        draw_text(text, text_position, actual_text_color, font_scale)
      end
    end
  end
end
