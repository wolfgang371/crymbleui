require "../core/widget"
require "../core/types"
require "../dsl/primitive_builder"

module CrymbleUI
    # Flow layout — arranges children left-to-right, wrapping to a new row
    # when the next child would overflow the available width. Think CSS
    # flex-wrap or a FlowLayoutPanel: adaptive to the parent's max_width.
    #
    # Typical use: tag lists, filter value checkboxes, button rows where
    # the total child count varies and the container's width changes.
    #
    # Constraints:
    # - Children are measured with loose constraints (max_width = available)
    # - Children shorter than the full width stay on the current row if they fit
    # - A child that alone exceeds available width still gets its own row
    # - Row height is the max child height within that row
    # - Does NOT support Expanded flex children (use HStack/VStack for that)
    class FlowLayout < Widget
        include PrimitiveBuilder

        # Horizontal spacing between items on the same row
        reactive_property hspacing : Float64 = 0.0, layout: true
        # Vertical spacing between rows
        reactive_property vspacing : Float64 = 0.0, layout: true
        reactive_property padding : Float64 = 0.0, layout: true
        reactive_property background_color : Color?

        def initialize(id : String? = nil, hspacing : Float64 = 0.0,
                       vspacing : Float64 = 0.0, padding : Float64 = 0.0,
                       background_color : Color? = nil)
            @hspacing = Source(Float64).new(hspacing)
            @vspacing = Source(Float64).new(vspacing)
            @padding = Source(Float64).new(padding)
            @background_color = Source(Color?).new(background_color)
            super(id: id)
        end

        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            if color = background_color
                primitives do
                    fill_background(bounds, color)
                end
            else
                [] of DrawPrimitive
            end
        end

        # A FlowLayout re-packs its rows against the available width, so a width change can change its
        # arrangement even when its own size (the widest row) stays sub-max. Opt out of the layout
        # relaxation-skip: it must re-flow on any constraint change, not just fill it. (See can_skip_layout?.)
        def layout_depends_on_available_space? : Bool
            true
        end

        # Measure by simulating row packing. Linear in children count.
        def measure(constraints : BoxConstraints) : Size
            return Size.new(padding * 2, padding * 2) if @children.empty?

            inner_max_width = (constraints.max_width - padding * 2).clamp(0.0, Float64::MAX)
            # Height is laid out freely; the flow decides its own height
            inner_max_height = (constraints.max_height - padding * 2).clamp(0.0, Float64::MAX)

            child_constraints = BoxConstraints.loose(Size.new(inner_max_width, inner_max_height))

            used_width = 0.0          # widest row so far
            row_width = 0.0           # accumulated width on current row (no leading hspacing)
            row_height = 0.0          # tallest child on current row
            total_height = 0.0        # accumulated height of completed rows (excl. vspacing)
            rows = 0                  # number of rows started

            @children.each_with_index do |child, index|
                sz = child.measure(child_constraints)
                # Width this child would add if placed on current row
                addend = row_width == 0 ? sz.width : sz.width + hspacing
                if row_width > 0 && row_width + addend > inner_max_width
                    # Wrap: commit current row, start a new one with just this child
                    total_height += row_height
                    used_width = Math.max(used_width, row_width)
                    rows += 1
                    row_width = sz.width
                    row_height = sz.height
                else
                    row_width += addend
                    row_height = Math.max(row_height, sz.height)
                    rows += 1 if index == 0   # count first row start
                end
            end
            # Commit final row
            total_height += row_height
            used_width = Math.max(used_width, row_width)

            # Add inter-row vspacing between (rows - 1) gaps
            total_height += vspacing * (rows - 1).clamp(0, Int32::MAX)

            size = Size.new(used_width + padding * 2, total_height + padding * 2)
            constraints.constrain(size)
        end

        # Min width = the WIDEST single child (+ padding) — a FlowLayout wraps, so it can place one child
        # per row; the floor is the widest child, NOT the packed-into-one-row Σ the greedy measure(INFINITY)
        # default computes. Height has no override: the default min_intrinsic_height already wraps correctly
        # at the given width.
        def min_intrinsic_width(height : Float64) : Float64
            return padding * 2 if @children.empty?
            inner_max_height = (height - padding * 2).clamp(0.0, Float64::MAX)
            widest = 0.0
            @children.each do |child|
                widest = Math.max(widest, child.min_intrinsic_width(inner_max_height))
            end
            widest + padding * 2
        end

        def perform_layout(constraints : BoxConstraints, position : Vec2)
            my_size = measure(constraints)
            @bounds = Rect.new(position.x, position.y, my_size.width, my_size.height)

            inner_max_width = (my_size.width - padding * 2).clamp(0.0, Float64::MAX)

            # Use loose max_height — rows grow tall as needed
            child_constraints = BoxConstraints.loose(Size.new(inner_max_width, Float64::INFINITY))

            x = padding
            y = padding
            row_height = 0.0
            row_has_any = false

            @children.each do |child|
                sz = child.measure(child_constraints)
                addend = row_has_any ? sz.width + hspacing : sz.width
                if row_has_any && x - padding + addend > inner_max_width
                    # Wrap to next row
                    y += row_height + vspacing
                    x = padding
                    row_height = 0.0
                    row_has_any = false
                    addend = sz.width
                end
                x += hspacing if row_has_any
                child.layout(child_constraints, Vec2.new(x, y))
                x += sz.width
                row_height = Math.max(row_height, sz.height)
                row_has_any = true
            end
        end
    end
end
