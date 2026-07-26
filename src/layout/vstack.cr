require "../core/widget"
require "../core/types"
require "../dsl/primitive_builder"
require "../widgets/expanded"

module CrymbleUI
    # Vertical stack layout widget
    # Arranges children vertically with optional spacing and padding
    class VStack < Widget
        include PrimitiveBuilder

        reactive_property spacing : Float64 = 0.0, layout: true
        reactive_property padding : Float64 = 0.0, layout: true
        reactive_property background_color : Color?

        def initialize(id : String? = nil, spacing : Float64 = 0.0, padding : Float64 = 0.0, background_color : Color? = nil)
            @spacing = Source(Float64).new(spacing)
            @padding = Source(Float64).new(padding)
            @background_color = Source(Color?).new(background_color)
            super(id: id)
        end

        # Draw background if color is set
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            if color = background_color
                primitives do
                    fill_background(bounds, color)
                end
            else
                [] of DrawPrimitive
            end
        end

        # Measure total size needed for all children
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

        # Min height = Σ children.min at the padded inner width + spacing + padding — mirrors measure's
        # stacking, composing children's min instead of natural. Own chain, so no INFINITY→MAX clamp.
        def min_intrinsic_height(width : Float64) : Float64
            return padding * 2 if @children.empty?
            inner_max_width = (width - padding * 2).clamp(0.0, Float64::MAX)
            total_height = 0.0
            @children.each_with_index do |child, index|
                total_height += child.min_intrinsic_height(inner_max_width)
                total_height += spacing if index < @children.size - 1
            end
            total_height + padding * 2
        end

        # Min width = MAX child min-width at the padded inner height (width is the CROSS axis of a vertical
        # stack — mirrors measure's max_width; no spacing). The width dual of min_intrinsic_height.
        def min_intrinsic_width(height : Float64) : Float64
            return padding * 2 if @children.empty?
            inner_max_height = (height - padding * 2).clamp(0.0, Float64::MAX)
            max_width = 0.0
            @children.each do |child|
                max_width = Math.max(max_width, child.min_intrinsic_width(inner_max_height))
            end
            max_width + padding * 2
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

        # Fast path for VStack without Expanded children
        # Matches original dacd384 behavior - single pass, minimal measure calls
        private def perform_layout_simple(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position.x, position.y, size.width, size.height)
            inner_width = size.width - padding * 2

            y_offset = padding
            @children.each do |child|
                child_constraints = BoxConstraints.loose(Size.new(inner_width, Float64::INFINITY))
                child.layout(child_constraints, Vec2.new(padding, y_offset))
                # Advance by what the child ACTUALLY occupies, not a second measure of it. A skipped
                # child keeps its previous size, and a fresh measure can disagree with it — that gap is
                # what let a stale subtree be overrun by the sibling below it. Also one measure fewer.
                y_offset += child.bounds.height + spacing
            end
        end

        # Two-pass layout for VStack with Expanded children
        # Pass 1: Measure fixed children, calculate remaining space
        # Pass 2: Layout all children with flex distribution
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
                    y_offset += child.bounds.height + spacing # actual extent, see perform_layout_simple
                end
            end
        end
    end

    # Alias for easy composite widget creation
    # Users can extend CompositeWidget to create custom widgets with automatic layout
    alias CompositeWidget = VStack
end
