require "../core/widget"
require "../core/types"
require "../dsl/primitive_builder"

module CrymbleUI
  # Container widget with optional visible border
  # When border is visible, adds padding and draws border around child
  # When border is hidden, acts as transparent pass-through container
  #
  # Key: Children are positioned INSIDE the padded area, so border is never covered
  #
  # ## Example
  # ```crystal
  # border_box(border_color: Color.new(255, 0, 0, 255), border_width: 2.0) do
  #   button("Content") { }
  # end
  # ```
  class BorderBox < Widget
    include PrimitiveBuilder

    # Border properties
    @border_color : Color?
    @border_width : Float64

    def initialize(
      @border_color : Color? = nil,
      @border_width : Float64 = 2.0,
      id : String? = nil
    )
      super(id: id)
    end

    def label : String?
      "border_box"
    end

    # Border color getter/setter
    def border_color : Color?
      @border_color
    end

    def border_color=(color : Color?)
      @border_color = color
      mark_needs_layout  # Border affects padding/layout
      mark_needs_render
    end

    # Border width getter/setter
    def border_width : Float64
      @border_width
    end

    def border_width=(width : Float64)
      @border_width = width
      mark_needs_layout
      mark_needs_render
    end

    # Padding for border (border line + visual padding inside)
    private def border_padding : Float64
      @border_color ? @border_width + 4.0 : 0.0
    end

    # Measure: child size + border padding
    def measure(constraints : BoxConstraints) : Size
      padding = border_padding

      if @children.empty?
        return Size.new(padding * 2, padding * 2)
      end

      # Measure child with reduced constraints (accounting for border padding)
      child = @children.first
      child_constraints = BoxConstraints.loose(Size.new(
        (constraints.max_width - padding * 2).clamp(0.0, Float64::MAX),
        (constraints.max_height - padding * 2).clamp(0.0, Float64::MAX)
      ))
      child_size = child.measure(child_constraints)

      # Total size = child + border padding on all sides
      total_size = Size.new(
        child_size.width + padding * 2,
        child_size.height + padding * 2
      )

      constraints.constrain(total_size)
    end

    # Layout: position child inside padded area
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)

      return if @children.empty?

      padding = border_padding
      child = @children.first

      # Child constraints = available space minus padding
      child_constraints = BoxConstraints.loose(Size.new(
        size.width - padding * 2,
        size.height - padding * 2
      ))

      # Position child inside padded area (relative to this widget)
      child.layout(child_constraints, Vec2.new(padding, padding))
    end

    # Draw border as 4 filled rectangles (inside bounds, not clipped)
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      if color = @border_color
        primitives do
          w = @border_width
          # Top edge
          fill_rect(Rect.new(0.0, 0.0, bounds.width, w), color)
          # Bottom edge
          fill_rect(Rect.new(0.0, bounds.height - w, bounds.width, w), color)
          # Left edge (between top and bottom)
          fill_rect(Rect.new(0.0, w, w, bounds.height - 2*w), color)
          # Right edge (between top and bottom)
          fill_rect(Rect.new(bounds.width - w, w, w, bounds.height - 2*w), color)
        end
      else
        [] of DrawPrimitive
      end
    end
  end
end
