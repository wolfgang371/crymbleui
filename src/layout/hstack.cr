require "../core/widget"
require "../core/types"
require "../dsl/primitive_builder"
require "../widgets/expanded"

module CrymbleUI
    # Horizontal stack layout widget
    # Arranges children horizontally with optional spacing and padding
    class HStack < Widget
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

            total_width = 0.0
            max_height = 0.0

            # Measure each child with reduced constraints (accounting for padding)
            @children.each_with_index do |child, index|
                child_constraints = BoxConstraints.loose(Size.new(
                    inner_max_width,
                    inner_max_height
                ))

                child_size = child.measure(child_constraints)
                total_width += child_size.width
                max_height = Math.max(max_height, child_size.height)

                # Add spacing between children (not after last)
                total_width += spacing if index < @children.size - 1
            end

            # Add padding to total size
            size = Size.new(total_width + padding * 2, max_height + padding * 2)
            constraints.constrain(size)
        end

        # Min width = Σ children.min at the padded inner height + spacing + padding (width is HStack's
        # STACKING axis — the dual of VStack/height). Own chain, no clamp.
        def min_intrinsic_width(height : Float64) : Float64
            return padding * 2 if @children.empty?
            inner_max_height = (height - padding * 2).clamp(0.0, Float64::MAX)
            total_width = 0.0
            @children.each_with_index do |child, index|
                total_width += child.min_intrinsic_width(inner_max_height)
                total_width += spacing if index < @children.size - 1
            end
            total_width + padding * 2
        end

        # Min height = MAX child min-height at the padded inner width (height is the CROSS axis for a
        # horizontal stack — MAX, no spacing). The cross-axis twin never added; needed once an HStack
        # holds a height-shrinkable child (a fill VirtualMatrix).
        def min_intrinsic_height(width : Float64) : Float64
            return padding * 2 if @children.empty?
            inner_max_width = (width - padding * 2).clamp(0.0, Float64::MAX)
            max_height = 0.0
            @children.each do |child|
                max_height = Math.max(max_height, child.min_intrinsic_height(inner_max_width))
            end
            max_height + padding * 2
        end

        # Layout children horizontally with flex support
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

        # Fast path for HStack without Expanded children
        # Matches original dacd384 behavior - single pass, minimal measure calls
        private def perform_layout_simple(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position.x, position.y, size.width, size.height)
            inner_height = size.height - padding * 2

            child_constraints = BoxConstraints.loose(Size.new(Float64::INFINITY, inner_height))
            sizes = @children.map { |child| child.measure(child_constraints) }
            # Cross-axis: center each child within the natural content band (tallest child),
            # anchored at the top. A short bare label then lines up with a taller combo_box /
            # button beside it; but a row inside a stretched HStack (e.g. a scroll viewport
            # taller than its content) stays at the top instead of floating in the middle.
            content_height = sizes.empty? ? 0.0 : sizes.max_of(&.height)

            x_offset = padding
            @children.each_with_index do |child, i|
                child_size = sizes[i]
                child_y = padding + (content_height - child_size.height) / 2.0
                child.layout(child_constraints, Vec2.new(x_offset, child_y))
                x_offset += child_size.width + spacing
            end
        end

        # Two-pass layout for HStack with Expanded children
        # Pass 1: Measure fixed children, calculate remaining space
        # Pass 2: Layout all children with flex distribution
        private def perform_layout_with_expanded(constraints : BoxConstraints, position : Vec2)
            # Use full available width from constraints
            width = constraints.max_width.finite? ? constraints.max_width : measure(constraints).width
            height = measure(constraints).height

            @bounds = Rect.new(position.x, position.y, width, height)
            inner_width = width - padding * 2
            inner_height = height - padding * 2

            # Pass 1: Measure fixed children, sum flex values, track the tallest (content band)
            fixed_width = 0.0
            total_flex = 0
            content_height = 0.0
            @children.each do |child|
                if child.is_a?(Expanded)
                    total_flex += child.flex
                else
                    child_size = child.measure(BoxConstraints.loose(Size.new(inner_width, inner_height)))
                    fixed_width += child_size.width
                    content_height = Math.max(content_height, child_size.height)
                end
            end

            total_spacing = spacing * (@children.size - 1).clamp(0, Int32::MAX)
            remaining = (inner_width - fixed_width - total_spacing).clamp(0.0, Float64::MAX)
            per_flex_width = total_flex > 0 ? remaining / total_flex : 0.0

            # Pass 2: Layout all children
            x_offset = padding
            @children.each do |child|
                if child.is_a?(Expanded)
                    # Proportional width based on flex factor
                    child_width = per_flex_width * child.flex
                    # Tight width (must fill), loose height (use natural height)
                    child_constraints = BoxConstraints.new(
                        min_width: child_width, max_width: child_width,
                        min_height: 0.0, max_height: inner_height
                    )
                    child.layout(child_constraints, Vec2.new(x_offset, padding))
                    x_offset += child_width + spacing
                else
                    # Use INFINITY for intrinsic-sized widgets (buttons, labels, etc.)
                    child_constraints = BoxConstraints.loose(Size.new(Float64::INFINITY, inner_height))
                    child_size = child.measure(child_constraints)
                    # Cross-axis: center intrinsic-sized children within the content band
                    # (tallest fixed child), anchored at the top. Expanded children keep the
                    # top edge — they fill / carry their own content.
                    child_y = padding + (content_height - child_size.height) / 2.0
                    child.layout(child_constraints, Vec2.new(x_offset, child_y))
                    x_offset += child_size.width + spacing
                end
            end
        end

    end
end
