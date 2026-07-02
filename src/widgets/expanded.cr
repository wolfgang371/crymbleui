require "../core/widget"
require "../core/types"

module CrymbleUI
  # Wrapper widget that tells HStack/VStack to expand this child to fill remaining space.
  #
  # Usage:
  #   hstack do
  #     text("Label")
  #     expanded { text_input(id: "main") }  # Fills remaining width
  #     expanded(flex: 2) { content }        # Gets 2x the space
  #     expanded(fit: :loose) { button }     # Allocates space, child uses natural size
  #   end
  class Expanded < Widget
    # If fill_area is true, fill both axes (container use case)
    # If fill_area is false (default), fill only tight axis (flexible item use case)
    getter fill_area : Bool

    # Flex factor for proportional distribution (default 1)
    # Higher values get proportionally more space
    getter flex : Int32

    # Fit mode controls how children are laid out:
    # - :tight (default) - child is forced to fill allocated space
    # - :loose - child uses natural size within allocated space
    getter fit : Symbol

    def initialize(id : String? = nil, @fill_area : Bool = false, @flex : Int32 = 1, @fit : Symbol = :tight)
      super(id: id)
    end

    def measure(constraints : BoxConstraints) : Size
      # Return first child's intrinsic size (parent will override during layout)
      return Size.zero if @children.empty?
      @children.first.measure(constraints)
    end

    # Passthrough: the flex contributes nothing of its own; its min is its child's min.
    def min_intrinsic_height(width : Float64) : Float64
      return 0.0 if @children.empty?
      @children.first.min_intrinsic_height(width)
    end

    # Passthrough on the width axis too — the width dual.
    def min_intrinsic_width(height : Float64) : Float64
      return 0.0 if @children.empty?
      @children.first.min_intrinsic_width(height)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      # Measure child to get natural size
      child_size = Size.zero
      if !@children.empty?
        child_size = @children.first.measure(constraints)
      end

      if @fill_area
        # Fill both axes to max available space
        width = constraints.max_width.finite? ? constraints.max_width : child_size.width
        height = constraints.max_height.finite? ? constraints.max_height : child_size.height
      else
        # Fill tight axis (main axis from parent), use natural size for loose axis (cross axis)
        tight_width = constraints.min_width == constraints.max_width
        tight_height = constraints.min_height == constraints.max_height

        width = tight_width ? constraints.max_width : child_size.width.clamp(constraints.min_width, constraints.max_width)
        height = tight_height ? constraints.max_height : child_size.height.clamp(constraints.min_height, constraints.max_height)
      end

      @bounds = Rect.new(position.x, position.y, width, height)

      # Layout children based on fit mode
      if @fit == :loose
        # Loose fit: child uses natural size within allocated space
        child_constraints = BoxConstraints.loose(Size.new(@bounds.width, @bounds.height))
      else
        # Tight fit (default): child must fill allocated space
        child_constraints = BoxConstraints.tight(Size.new(@bounds.width, @bounds.height))
      end

      y_offset = 0.0
      @children.each do |child|
        child.layout(child_constraints, Vec2.new(0.0, y_offset))
        y_offset += child.bounds.height
      end
    end
  end
end
