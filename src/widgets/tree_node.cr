require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"

module CrymbleUI
  # Internal header widget for TreeNode - renders the triangle indicator and header text.
  # This is a leaf widget (no children) so its widget_backend only covers the header area,
  # preventing the full-bounds overwrite that occurred when TreeNode rendered its own primitives.
  class TreeNodeHeader < Widget
    include PrimitiveBuilder
    include FontScalable

    TRIANGLE_SIZE = TreeNode::TRIANGLE_SIZE
    INDENT = TreeNode::INDENT
    HEADER_PADDING = TreeNode::HEADER_PADDING

    @header : String

    # Theme colors resolve live (nil = follow Theme.current; explicit value wins)
    theme_property text_color, text_default
    theme_property indicator_color, text_default

    def initialize(
      @header : String,
      font_scale : Int32 = 0,
      text_color : ThemeColor? = nil,
      indicator_color : ThemeColor? = nil
    )
      @text_color = text_color
      @indicator_color = indicator_color
      @font_scale.set(font_scale)
      super(id: nil)
    end

    def label : String?
      "header"
    end

    # The expanded state is the parent TreeNode's single source of truth -- read it
    # here, NOT a stored copy. Reading it in to_primitives auto-captures the TreeNode's
    # `expanded` Source, so any change re-renders the triangle with no layout push.
    def expanded? : Bool
      parent.as?(TreeNode).try(&.expanded) || false
    end

    def measure(constraints : BoxConstraints) : Size
      header_size = measure_text(@header, font_size)
      header_height = header_size.height + HEADER_PADDING * 2
      header_width = INDENT + header_size.width + HEADER_PADDING * 2
      constraints.constrain(Size.new(header_width, header_height))
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      header_size = measure_text(@header, font_size)
      header_height = header_size.height + HEADER_PADDING * 2

      # Triangle center position
      tri_cx = TRIANGLE_SIZE + 2.0
      tri_cy = header_height / 2.0

      primitives do
        if expanded?
          # Downward-pointing triangle (expanded)
          fill_triangle(
            Vec2.new(tri_cx - TRIANGLE_SIZE/2, tri_cy - TRIANGLE_SIZE/3),
            Vec2.new(tri_cx + TRIANGLE_SIZE/2, tri_cy - TRIANGLE_SIZE/3),
            Vec2.new(tri_cx, tri_cy + TRIANGLE_SIZE/2),
            indicator_color
          )
        else
          # Right-pointing triangle (collapsed)
          fill_triangle(
            Vec2.new(tri_cx - TRIANGLE_SIZE/3, tri_cy - TRIANGLE_SIZE/2),
            Vec2.new(tri_cx + TRIANGLE_SIZE/2, tri_cy),
            Vec2.new(tri_cx - TRIANGLE_SIZE/3, tri_cy + TRIANGLE_SIZE/2),
            indicator_color
          )
        end

        # Header text — vertically centered to line up with the triangle (tri_cy)
        text_x = INDENT
        text_y = vcentered_text_y(header_height, font_scale)
        draw_text(@header, Vec2.new(text_x, text_y), text_color, font_scale)
      end
    end

    # Clicking the header toggles the parent TreeNode
    def on_click
      if tree_node = parent.as?(TreeNode)
        tree_node.toggle
      end
    end

    # Header is clickable
    def focusable? : Bool
      true
    end

    def trigger_click
      on_click
    end
  end

  # Collapsible tree node widget with triangle indicator and header text
  #
  # TreeNode is a PURE CONTAINER - it has no to_primitives of its own.
  # The header (triangle + text) is rendered by a TreeNodeHeader child widget.
  # This prevents the full-bounds widget_backend overwrite bug where parent blit
  # would overwrite children pixels on selective re-render.
  #
  # Usage:
  #   tree_node("Root", expanded: true) do
  #     text("Child 1")
  #     tree_node("Nested") do
  #       text("Child 2")
  #     end
  #   end
  class TreeNode < Widget
    include FontScalable

    INDENT = 20.0
    TRIANGLE_SIZE = 8.0
    HEADER_PADDING = 4.0

    # Header text
    @header : String

    # Whether the node is expanded (children visible)
    reactive_property expanded : Bool = false, reconcile: true

    # Theme colors resolve live (nil = follow Theme.current; explicit value wins)
    theme_property text_color, text_default
    theme_property indicator_color, text_default

    # Click callback for toggle
    property on_toggle_callback : Proc(Nil)?

    # The header child widget (always first child)
    @header_widget : TreeNodeHeader

    def initialize(
      @header : String,
      expanded : Bool = false,
      id : String? = nil,
      font_scale : Int32 = 0,
      text_color : ThemeColor? = nil,
      indicator_color : ThemeColor? = nil,
      on_toggle : Proc(Nil)? = nil
    )
      @expanded = Source(Bool).new(expanded)
      @_build_expanded = expanded
      @text_color = text_color
      @indicator_color = indicator_color
      @font_scale.set(font_scale)
      super(id: id)
      @on_toggle_callback = on_toggle

      # Create header as first child - it renders the triangle + header text.
      # Forward the nullable ivars (not the getters) so a nil stays nil and the
      # header resolves the theme color LIVE itself (snapshot-drop).
      @header_widget = TreeNodeHeader.new(
        @header,
        font_scale: font_scale,
        text_color: @text_color,
        indicator_color: @indicator_color
      )
      add_child(@header_widget)
    end

    # Override label for path_id generation
    def label : String?
      @header
    end

    # DSL children (excludes the internal header widget)
    def dsl_children : Array(Widget)
      @children.size > 1 ? @children[1..] : [] of Widget
    end

    # Measure header + children (if expanded)
    def measure(constraints : BoxConstraints) : Size
      Widget.increment_measure_count
      header_size = @header_widget.measure(constraints)
      header_height = header_size.height
      header_width = header_size.width

      total_height = header_height
      max_width = header_width

      if expanded
        dsl_children.each do |child|
          child_constraints = BoxConstraints.loose(Size.new(
            (constraints.max_width - INDENT).clamp(0.0, constraints.max_width),
            constraints.max_height
          ))
          child_size = child.measure(child_constraints)
          total_height += child_size.height
          max_width = Math.max(max_width, child_size.width + INDENT)
        end
      end

      constraints.constrain(Size.new(max_width, total_height))
    end

    # Layout header and children
    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)

      # Layout header (always visible, first child)
      header_constraints = BoxConstraints.loose(Size.new(size.width, size.height))
      @header_widget.layout(header_constraints, Vec2.new(0.0, 0.0))
      header_height = @header_widget.bounds.height

      # (No expanded push: the header pulls the TreeNode's `expanded` Source directly.)

      # Layout DSL children below header with indentation (positions relative to TreeNode)
      if expanded
        y_offset = header_height
        remaining_height = size.height - header_height
        dsl_children.each do |child|
          child_constraints = BoxConstraints.loose(Size.new(
            (size.width - INDENT).clamp(0.0, size.width),
            remaining_height
          ))
          child.layout(child_constraints, Vec2.new(INDENT, y_offset))
          child_size = child.measure(child_constraints)
          y_offset += child_size.height
          remaining_height = (remaining_height - child_size.height).clamp(0.0, Float64::MAX)
        end
      else
        # Collapsed: reset dsl_children bounds to zero to prevent stale rendering.
        # Without this, children retain old bounds from the expanded state and get
        # rendered at stale positions during the next full_render pass.
        # Also invalidate constraints so re-expand triggers full perform_layout
        # (otherwise can_skip_layout? returns true → size stays 0×0).
        dsl_children.each(&.zero_bounds!)
      end
    end

    # Pure container - no primitives (header renders via TreeNodeHeader child)
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive
    end

    # Toggle expansion (called by TreeNodeHeader.on_click)
    def toggle
      self.expanded = !expanded
      @on_toggle_callback.try &.call
      mark_needs_layout
    end

    # TreeNode itself is not focusable/clickable — only TreeNodeHeader handles toggle
    def focusable? : Bool
      false
    end
  end
end
