require "../core/widget"
require "../core/types"
require "../dsl/primitive_builder"
require "../widgets/expanded"

module CrymbleUI
  # Abstract base class for custom widgets that combine DSL-based children
  # with custom drawing primitives (background and foreground).
  #
  # ## Usage
  # Subclass DecoratedContainer and override:
  # - `build()` to add children using DSL methods
  # - `draw_background(bounds)` for primitives rendered UNDER children
  # - `draw_foreground(bounds)` for primitives rendered OVER children
  #
  # ## Example
  # ```crystal
  # class FancyCard < CrymbleUI::DecoratedContainer
  #   def initialize(@title : String)
  #     super(padding: 15.0, spacing: 8.0)
  #   end
  #
  #   def draw_background(bounds : Rect) : Array(DrawPrimitive)
  #     primitives do
  #       fill_rect(bounds, Color.new(60, 60, 80, 255))
  #     end
  #   end
  #
  #   def draw_foreground(bounds : Rect) : Array(DrawPrimitive)
  #     primitives do
  #       draw_rect(bounds, Color.new(255, 200, 100, 255), 2.0)
  #     end
  #   end
  #
  #   def build
  #     text(@title, font_scale: 1, color: Color.new(255, 255, 255, 255))
  #     text("Description", font_scale: -1)
  #   end
  # end
  # ```
  #
  # ## Rendering Order
  # 1. Parent's draw_background primitives render first
  # 2. Children render on top (parent-first ordering in rendering pipeline)
  # 3. Parent's draw_foreground primitives render last (after all children)
  abstract class DecoratedContainer < Widget
    include PrimitiveBuilder

    reactive_property spacing : Float64 = 0.0, layout: true
    reactive_property padding : Float64 = 0.0, layout: true

    def initialize(id : String? = nil, spacing : Float64 = 0.0, padding : Float64 = 0.0)
      @spacing = Source(Float64).new(spacing)
      @padding = Source(Float64).new(padding)
      super(id: id)
    end

    # Override to draw primitives UNDER children
    # bounds is widget-local (0,0 origin)
    def draw_background(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive
    end

    # Override to draw primitives OVER children
    # bounds is widget-local (0,0 origin)
    def draw_foreground(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive
    end

    # Background becomes this widget's primitives (rendered before children)
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      draw_background(Rect.new(0.0, 0.0, bounds.width, bounds.height))
    end

    # API for layer_renderer to check for foreground
    def has_foreground? : Bool
      !draw_foreground(Rect.new(0.0, 0.0, bounds.width, bounds.height)).empty?
    end

    # API for layer_renderer to get foreground primitives
    def foreground_primitives : Array(DrawPrimitive)
      draw_foreground(Rect.new(0.0, 0.0, bounds.width, bounds.height))
    end

    # Measure total size needed for all children (VStack-like vertical layout)
    def measure(constraints : BoxConstraints) : Size
      # Account for padding in available space
      inner_max_width = (constraints.max_width - padding * 2).clamp(0.0, Float64::MAX)
      inner_max_height = (constraints.max_height - padding * 2).clamp(0.0, Float64::MAX)

      return Size.new(padding * 2, padding * 2) if @children.empty?

      max_width = 0.0
      total_height = 0.0

      # Measure each child with reduced constraints (accounting for padding)
      @children.each_with_index do |child, index|
        child_constraints = BoxConstraints.loose(Size.new(
          inner_max_width,
          inner_max_height
        ))

        child_size = child.measure(child_constraints)
        max_width = Math.max(max_width, child_size.width)
        total_height += child_size.height

        # Add spacing between children (not after last)
        total_height += spacing if index < @children.size - 1
      end

      # Add padding to total size
      size = Size.new(max_width + padding * 2, total_height + padding * 2)
      constraints.constrain(size)
    end

    # Layout children vertically with flex support
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      # Check if we have any Expanded children
      has_expanded = @children.any? { |c| c.is_a?(Expanded) }

      if has_expanded
        # Two-pass layout for flex distribution
        perform_layout_with_expanded(constraints, position)
      else
        # Fast path: single-pass layout (no extra measure calls)
        perform_layout_simple(constraints, position)
      end
    end

    # Fast path for layout without Expanded children
    private def perform_layout_simple(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position.x, position.y, size.width, size.height)
      inner_width = size.width - padding * 2

      y_offset = padding
      @children.each do |child|
        child_constraints = BoxConstraints.loose(Size.new(inner_width, Float64::INFINITY))
        child.layout(child_constraints, Vec2.new(padding, y_offset))
        y_offset += child.bounds.height + spacing # actual extent, mirrors VStack
      end
    end

    # Two-pass layout for Expanded children
    private def perform_layout_with_expanded(constraints : BoxConstraints, position : Vec2)
      # Use full available height from constraints
      width = measure(constraints).width
      height = constraints.max_height.finite? ? constraints.max_height : measure(constraints).height

      @bounds = Rect.new(position.x, position.y, width, height)
      inner_width = width - padding * 2
      inner_height = height - padding * 2

      # Pass 1: Measure fixed children, sum flex values
      fixed_height = 0.0
      total_flex = 0
      @children.each do |child|
        if child.is_a?(Expanded)
          total_flex += child.flex
        else
          child_size = child.measure(BoxConstraints.loose(Size.new(inner_width, inner_height)))
          fixed_height += child_size.height
        end
      end

      total_spacing = spacing * (@children.size - 1).clamp(0, Int32::MAX)
      remaining = (inner_height - fixed_height - total_spacing).clamp(0.0, Float64::MAX)
      per_flex_height = total_flex > 0 ? remaining / total_flex : 0.0

      # Pass 2: Layout all children
      y_offset = padding
      @children.each do |child|
        if child.is_a?(Expanded)
          # Proportional height based on flex factor
          child_height = per_flex_height * child.flex
          # Tight height (must fill), loose width (use natural width)
          child_constraints = BoxConstraints.new(
            min_width: 0.0, max_width: inner_width,
            min_height: child_height, max_height: child_height
          )
          child.layout(child_constraints, Vec2.new(padding, y_offset))
          y_offset += child_height + spacing
        else
          # Use INFINITY for intrinsic-sized widgets (buttons, labels, etc.)
          child_constraints = BoxConstraints.loose(Size.new(inner_width, Float64::INFINITY))
          child.layout(child_constraints, Vec2.new(padding, y_offset))
          y_offset += child.bounds.height + spacing # actual extent, mirrors VStack
        end
      end
    end
  end
end
