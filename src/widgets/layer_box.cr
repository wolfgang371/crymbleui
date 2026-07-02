require "../core/widget"
require "../core/layer"
require "../core/layer_owner"
require "../dsl/primitive_builder"

module CrymbleUI
    # LayerBox - Simple widget with its own layer for demonstrating layer hierarchy
    # Creates a child layer at specified position with higher z-index
    class LayerBox < Widget
        include PrimitiveBuilder
        include LayerOwner

        reactive_property x : Float64, layout: true
        reactive_property y : Float64, layout: true
        reactive_property width : Float64?, layout: true   # nil = fill available width from constraints
        reactive_property height : Float64?, layout: true  # nil = fill available height from constraints

        property z_index : Int32
        reactive_property background_color : Color = Color.new(0, 0, 0, 0)  # Fully transparent by default

        # Alignment properties for automatic positioning
        property alignment : Alignment = Alignment::None
        property width_spec : SizeSpec = nil
        property height_spec : SizeSpec = nil
        property margin : Float64 = 0.0

        # @internal_layer provided by LayerOwner mixin

        # A LayerBox is its own compositing z-boundary (asked by the renderer's
        # find_panel_z_index polymorphically, not via is_a?(LayerBox)).
        def compositing_z_index : Int32
            z_index
        end

        def initialize(x : Float64, y : Float64, width : Float64?, height : Float64?,
                       @z_index : Int32 = 1, id : String? = nil,
                       @alignment : Alignment = Alignment::None,
                       @width_spec : SizeSpec = nil,
                       @height_spec : SizeSpec = nil,
                       @margin : Float64 = 0.0)
            @x = Source(Float64).new(x)
            @y = Source(Float64).new(y)
            @width = Source(Float64?).new(width)
            @height = Source(Float64?).new(height)
            super(id: id)
            # Create layer with higher z-index to appear on top
            # Layer buffer always transparent (allows seeing content below)
            # Widget background rendered separately via to_primitives if needed
            @internal_layer = Layer.new("layer_#{id}", Rect.zero, z_index: @z_index, background_color: Color.new(0, 0, 0, 0), owner_widget: self)
        end

        # layer getter provided by LayerOwner mixin

        # Pull-based layer bounds: LayerBox positions itself via @bounds
        def compute_bounds_for_layer(layer : Layer) : Rect
            @bounds
        end

        def measure(constraints : BoxConstraints) : Size
            # Use explicit dimensions if set, otherwise use constraints
            w = width || constraints.max_width
            h = height || constraints.max_height
            Size.new(w, h)
        end

        def perform_layout(constraints : BoxConstraints, position : Vec2)
            # Use explicit dimensions if set, otherwise fill available space from constraints
            actual_width = width || constraints.max_width
            actual_height = height || constraints.max_height
            @bounds = Rect.new(x, y, actual_width, actual_height)

            # Update layer
            if layer = @internal_layer
                layer.z_index = @z_index

                # Populate layer with children
                layer.widgets.clear
                children.each { |child| layer.widgets << child }
            end

            # Stack children vertically (default vstack behavior)
            current_y = 0.0
            children.each do |child|
                # Allow children their natural width
                child_constraints = BoxConstraints.new(
                    min_width: 0.0,  # Allow natural width
                    max_width: actual_width,  # But constrain to layer width
                    min_height: 0.0,
                    max_height: actual_height - current_y
                )
                child.layout(child_constraints, Vec2.new(0.0, current_y))
                current_y += child.bounds.height
            end
        end

        # Override hit_test to only respond to hits on children (click-through empty space)
        # This allows overlays to pass clicks through transparent areas to layers below
        def hit_test(point : Vec2) : Widget?
            return nil unless absolute_bounds.contains_point(point)

            # Check if any children handle this click
            children.reverse_each do |child|
                if hit = child.hit_test(point)
                    return hit
                end
            end

            # Return nil instead of self - pass through to layers below
            nil
        end

        # Render background rectangle for the overlay (if background_color has alpha > 0)
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            return [] of DrawPrimitive if background_color.a == 0

            # Render full-bounds background rectangle in widget-local coordinates
            primitives do
                fill_background(bounds, background_color)
            end
        end

        # Clip children to LayerBox bounds (prevents overflow)
        def clip_children : Rect?
            absolute_bounds
        end

        # Called by Window.perform_layout on window resize
        # Recalculates position based on alignment and percentage sizes
        def constrain_to_window_bounds(window_bounds : Rect)
            return if @alignment == Alignment::None

            # Resolve sizes from specs (percentage, pixel, or measure children)
            actual_width = resolve_size(@width_spec, width, window_bounds.width, :width)
            actual_height = resolve_size(@height_spec, height, window_bounds.height, :height)

            # Calculate position based on alignment
            new_x, new_y = calculate_aligned_position(@alignment, actual_width, actual_height, window_bounds, @margin)
            self.x = new_x
            self.y = new_y
            self.width = actual_width
            self.height = actual_height

            # Sync bounds
            @bounds = Rect.new(new_x, new_y, actual_width, actual_height)
            mark_needs_layout
        end

        private def resolve_size(spec : SizeSpec, fallback : Float64?, max : Float64, dimension : Symbol) : Float64
            case spec
            when Percent
                spec.value * max
            when Float64
                spec
            else
                # No spec: use fallback OR measure children for natural size
                return fallback if fallback
                measure_children_natural_size(dimension, max)
            end
        end

        private def measure_children_natural_size(dimension : Symbol, max : Float64) : Float64
            return max if children.empty?

            # Measure children with loose constraints to get their natural sizes
            loose = BoxConstraints.new(max_width: max, max_height: max)

            # For vertical stacking (default), width is max of children, height is sum
            if dimension == :width
                max_width = 0.0
                children.each do |child|
                    size = child.measure(loose)
                    max_width = size.width if size.width > max_width
                end
                max_width > 0 ? max_width : max
            else
                total_height = 0.0
                children.each do |child|
                    size = child.measure(loose)
                    total_height += size.height
                end
                total_height > 0 ? total_height : max
            end
        end

        private def calculate_aligned_position(alignment : Alignment, w : Float64, h : Float64,
                                                bounds : Rect, margin : Float64) : {Float64, Float64}
            case alignment
            when Alignment::TopLeft
                {bounds.x + margin, bounds.y + margin}
            when Alignment::TopCenter
                {bounds.x + (bounds.width - w) / 2.0, bounds.y + margin}
            when Alignment::TopRight
                {bounds.x + bounds.width - w - margin, bounds.y + margin}
            when Alignment::MiddleLeft
                {bounds.x + margin, bounds.y + (bounds.height - h) / 2.0}
            when Alignment::Center
                {bounds.x + (bounds.width - w) / 2.0, bounds.y + (bounds.height - h) / 2.0}
            when Alignment::MiddleRight
                {bounds.x + bounds.width - w - margin, bounds.y + (bounds.height - h) / 2.0}
            when Alignment::BottomLeft
                {bounds.x + margin, bounds.y + bounds.height - h - margin}
            when Alignment::BottomCenter
                {bounds.x + (bounds.width - w) / 2.0, bounds.y + bounds.height - h - margin}
            when Alignment::BottomRight
                {bounds.x + bounds.width - w - margin, bounds.y + bounds.height - h - margin}
            else
                {x, y}  # None - keep current position
            end
        end
    end
end
