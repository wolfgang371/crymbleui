require "../core/widget"
require "../core/types"
require "../core/theme"
require "../dsl/primitive_builder"
require "../dsl/builder"

module CrymbleUI
  enum SplitDirection
    Horizontal # panes side by side, vertical bars
    Vertical   # panes stacked, horizontal bars
  end

  # Panes side by side (or stacked) with a draggable bar in each gap: the classic splitter.
  #
  #   split(id: "cols", ratios: [0.2, 0.3, 0.5]) do
  #     tags_pane
  #     split(:vertical, id: "rows") { top_pane; bottom_pane }
  #     preview_pane
  #   end
  #
  # Each child added is a pane. The panes share the length left after the bars by `ratios` (missing
  # ones get an equal share), so they scale with the window. Dragging a bar moves only its two
  # neighbours, neither below `min_size`. The bar under the mouse lights up and shows the resize cursor.
  #
  # The ratios survive a DSL rebuild (the build's value only wins when it CHANGES), and so does a drag
  # in progress: a rebuild between press and release hands the drag to this widget's replacement.
  #
  # The bars are widgets of their own (SplitBar, inserted between the panes), and the split paints
  # nothing itself: the chrome/content law (LAYER_RENDERING_ARCHITECTURE.md). A container repaints
  # its whole area, so a split that drew its bars wiped every pane whenever a bar lit up - the panes,
  # rightly not dirty, never painted again.
  class SplitView < Widget
    BAR = 6.0

    getter direction : SplitDirection
    getter min_size : Float64
    reactive_property ratios : Array(Float64) = [] of Float64, layout: true, reconcile: true
    # While a bar is dragged: which, where the press was (along the axis), the pane sizes then.
    reconcile_property drag_bar : Int32? = nil
    reconcile_property drag_from : Float64 = 0.0
    reconcile_property drag_sizes : Array(Float64) = [] of Float64

    def initialize(@direction : SplitDirection = SplitDirection::Horizontal, ratios : Array(Float64)? = nil,
                   @min_size : Float64 = 40.0, id : String? = nil)
      super(id: id)
      @ratios = Source(Array(Float64)).new(ratios || [] of Float64)
    end

    def horizontal? : Bool
      @direction.horizontal?
    end

    # A pane, with a bar before it when it is not the first.
    def add_child(child : Widget)
      super(SplitBar.new(self, panes.size - 1)) unless child.is_a?(SplitBar) || panes.empty?
      super(child)
    end

    def panes : Array(Widget)
      @children.reject(&.is_a?(SplitBar))
    end

    def bars : Array(Widget)
      @children.select(&.is_a?(SplitBar))
    end

    # Length along the axis, in widget space.
    private def along(size : Size) : Float64
      horizontal? ? size.width : size.height
    end

    private def along(point : Vec2) : Float64
      horizontal? ? point.x : point.y
    end

    # The panes' lengths for a total `length` (bars excluded), from the ratios.
    private def pane_lengths(length : Float64) : Array(Float64)
      n = panes.size
      return [] of Float64 if n == 0
      r = ratios
      shares = Array.new(n) { |i| (r[i]? || 0.0) > 0 ? r[i] : 1.0 / n }
      sum = shares.sum
      available = {length - BAR * (n - 1), 0.0}.max
      shares.map { |s| available * s / sum }
    end

    def measure(constraints : BoxConstraints) : Size
      w = constraints.max_width.finite? ? constraints.max_width : 400.0
      h = constraints.max_height.finite? ? constraints.max_height : 300.0
      constraints.constrain(Size.new(w, h))
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)
      offset = 0.0
      lengths = pane_lengths(along(size))
      i = 0
      @children.each do |child|
        length = child.is_a?(SplitBar) ? BAR : (lengths[i]? || 0.0).tap { i += 1 }
        child_size = horizontal? ? Size.new(length, size.height) : Size.new(size.width, length)
        child_pos = horizontal? ? Vec2.new(offset, 0.0) : Vec2.new(0.0, offset)
        child.layout(BoxConstraints.tight(child_size), child_pos)
        offset += length
      end
    end

    # Bar `i` (between pane i and i+1) in window coordinates (to press it).
    def bar_window_rect(i : Int32) : Rect
      bars[i].viewport_bounds
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive # chrome is the bars' own (see above)
    end

    # A press on bar `bar` (its SplitBar hands it on), at `point` in window-equivalent widget space.
    def start_drag(bar : Int32, point : Vec2)
      self.drag_bar = bar
      self.drag_from = along(point)
      self.drag_sizes = panes.map { |c| along(c.bounds.size) }
    end

    def drag_to(point : Vec2)
      bar = drag_bar || return
      sizes = drag_sizes.dup
      return unless sizes.size == panes.size
      pair = sizes[bar] + sizes[bar + 1]
      first = (sizes[bar] + along(point) - drag_from).clamp({min_size, pair / 2}.min, {pair - min_size, pair / 2}.max)
      sizes[bar] = first
      sizes[bar + 1] = pair - first
      total = sizes.sum
      self.ratios = sizes.map { |s| s / total }
    end

    def end_drag
      self.drag_bar = nil
    end

    def label : String
      "split"
    end
  end

  # The bar between two panes of a SplitView: lit while hovered or dragged, the resize cursor, and
  # the drag - kept by the split, so it survives a rebuild that replaces both.
  class SplitBar < Widget
    include PrimitiveBuilder

    getter index : Int32
    reactive_property hovered : Bool = false

    def initialize(@split : SplitView, @index : Int32)
      super(id: nil)
    end

    def measure(constraints : BoxConstraints) : Size
      constraints.constrain(Size.new(constraints.max_width, constraints.max_height))
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, measure(constraints))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      theme = Theme.current
      color = theme.separator_color
      color = color.highlight(theme.brightness_hover) if hovered || @split.drag_bar == @index
      primitives { fill_background(bounds, color) }
    end

    def preferred_cursor(point : Vec2) : CursorType?
      @split.horizontal? ? CursorType::SizeHorizontal : CursorType::SizeVertical
    end

    def on_mouse_enter
      self.hovered = true
    end

    def on_mouse_exit
      self.hovered = false
    end

    def on_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left)
      super
      @split.start_drag(@index, point) if button == MouseButton::Left
    end

    def on_mouse_move(point : Vec2)
      @split.drag_to(point)
    end

    def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
      @split.end_drag
    end

    def suppresses_drag? : Bool
      true # a bar drag is ours, not a drag-and-drop
    end

    def label : String
      "split bar"
    end
  end

  module DSL
    module BuilderMethods
      # A SplitView over the children the block builds (each one a pane).
      def split(direction : Symbol = :horizontal, ratios : Array(Float64)? = nil, min_size : Float64 = 40.0,
                id : String? = nil, &block)
        dir = direction == :vertical ? SplitDirection::Vertical : SplitDirection::Horizontal
        view = SplitView.new(dir, ratios, min_size, id)
        current_container.add_child(view)
        with_container(view, &block)
        view
      end
    end
  end
end
