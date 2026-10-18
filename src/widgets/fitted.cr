require "../core/widget"
require "../core/layer"
require "../core/layer_owner"

module CrymbleUI
  # A container that shows its one child uniformly SCALED to fit the space it is given (Flutter's FittedBox,
  # BoxFit.contain): the child is laid out with no limit on either axis - its natural size N - and drawn at
  #   f = min over the axes the box bounds (with N > 0) of max / N      (none -> 1; a max of 0 -> 0)
  # into a layer this widget owns, text rasterised at its final size, input landing where it is drawn. No
  # widget inside knows: the scale is declared once (scale_for, compute_scale_for_layer) and applied by the
  # generic walks and the renderer.
  #
  # Its size is the box's constraints applied to N * f. Given more than that (a tight slot, such as a window's
  # single child) it centres the image and the rest is letterbox - what lies behind shows, it paints nothing.
  # In a LOOSE slot it takes only N * f and its parent places it, flush at the slot's start.
  #
  # Refused inside: anything that owns a layer (a scroll view, a window panel, a layer, a popup, another
  # fitted) - checked on every layout, so one appearing on a later rebuild raises in that frame.
  class Fitted < Widget
    include LayerOwner

    # Instrumentation: how often a factor change was applied, and how many widgets the refusal walk
    # visited - process-wide, reset by the spec that reads them.
    class_property apply_scale_calls : Int32 = 0
    class_property refusal_walk_visits : Int32 = 0

    UNBOUNDED = BoxConstraints.new

    # The factor the child is drawn at. Carried across a rebuild, so a fresh instance and the carried layer
    # agree before the next layout - a rebuild that keeps the factor costs no re-scale.
    reconcile_property scale : Float64 = 1.0

    def initialize(id : String? = nil)
      super(id: id)
      # The layer is created LAZILY on first perform_layout, so a reconcile reuses the carried one
      # (LayerOwner @[Reconcile], mirrors LayerBox / ScrollView).
    end

    # The factor that fits `natural` into `constraints`.
    def self.fit_factor(natural : Size, constraints : BoxConstraints) : Float64
      f = Float64::INFINITY
      if constraints.max_width.finite? && natural.width > 0.0 && natural.width.finite?
        f = {f, {constraints.max_width, 0.0}.max / natural.width}.min
      end
      if constraints.max_height.finite? && natural.height > 0.0 && natural.height.finite?
        f = {f, {constraints.max_height, 0.0}.max / natural.height}.min
      end
      f.finite? ? f : 1.0
    end

    def measure(constraints : BoxConstraints) : Size
      child = @children.first? || return constraints.constrain(Size.zero)
      natural = child.measure(UNBOUNDED)
      f = Fitted.fit_factor(natural, constraints)
      constraints.constrain(Size.new(natural.width * f, natural.height * f))
    end

    # It shows its child at whatever size it is given: there is no smallest acceptable size. (The inherited
    # default measures it unbounded on one axis - the child scaled up to the other axis's limit - and a window
    # panel flooring at that could never be narrower than the image at its height-bound factor.)
    def min_intrinsic_width(height : Float64) : Float64
      0.0
    end

    def min_intrinsic_height(width : Float64) : Float64
      0.0
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      raise ArgumentError.new("fitted takes one child - wrap several in a vstack or hstack") if @children.size > 1
      # Before the child is laid out: a laid-out layer owner would make its layer, and fail a second time on
      # the backstop (Widget#enclosing_scroll), naming the wrong thing.
      refuse_layer_owners
      layer = (@internal_layer ||= Layer.new("fitted_#{id || object_id}", Rect.zero, owner_widget: self))
      layer.widgets.clear

      child = @children.first?
      unless child
        @bounds = Rect.new(position, constraints.constrain(Size.zero))
        apply_scale(1.0) unless scale == 1.0
        return
      end

      # Its natural size: laid out with no limit (where it was - a clean child takes the skip)
      child.layout(UNBOUNDED, child.bounds.position)
      natural = child.bounds.size
      f = Fitted.fit_factor(natural, constraints)
      image = Size.new(natural.width * f, natural.height * f)
      size = constraints.constrain(image)
      @bounds = Rect.new(position, size)
      # The image centred in what it was given; the same constraints again, so this only moves it
      at = Vec2.new((size.width - image.width) / 2.0, (size.height - image.height) / 2.0)
      child.layout(UNBOUNDED, at) unless at == child.bounds.position
      layer.widgets << child
      apply_scale(f) unless f == scale
    end

    # A new factor. Every widget of the subtree releases its surfaces and the layer clears and repaints: each
    # widget re-captures its background over the cleared, parent-first buffer at its new device size (as a
    # zoom change does) - never the flat fill a mere size change would give it, which leaves a transparent
    # child's parent showing through as a hole. A live resize changes the factor every frame, so this
    # reallocates every frame: inherent, the sizes change.
    private def apply_scale(f : Float64) : Nil
      Fitted.apply_scale_calls += 1
      self.scale = f
      @internal_layer.try(&.mark_needs_clear_and_render)
      @children.each(&.free_subtree_surfaces)
    end

    # Nothing that owns a layer may be inside: a layer composites at an additive position, and below a scale
    # there is none (Widget#enclosing_scroll). Walked on every layout, before the child is laid out.
    private def refuse_layer_owners : Nil
      @children.each { |child| refuse_layer_owners(child) }
    end

    private def refuse_layer_owners(widget : Widget) : Nil
      Fitted.refusal_walk_visits += 1
      raise ArgumentError.new(refusal(widget)) if widget.is_a?(LayerOwner)
      widget.children.each { |child| refuse_layer_owners(child) }
    end

    private def refusal(owner : Widget) : String
      name = owner.class.name.split("::").last
      where = owner.id ? "##{owner.id} at #{owner.path_id}" : "at #{owner.path_id}"
      remedy = if owner.is_a?(Fitted)
                 "one fitted scales everything inside it - remove the inner one"
               else
                 "put fitted around the content inside the #{name.underscore.tr("_", " ")}, not around it"
               end
      "fitted cannot scale a #{name} (#{where}): #{remedy}"
    end

    # The child is drawn at `scale` about its own origin.
    def scale_for(child : Widget) : Float64
      scale
    end

    # The layer holds the child's content where the child is laid out; its origin is the centre of the scale.
    def compute_bounds_for_layer(layer : Layer) : Rect
      @children.first?.try(&.absolute_bounds) || absolute_bounds
    end

    def compute_scale_for_layer(layer : Layer) : Float64
      scale
    end

    # The child's laid-out rect exceeds this one at a factor below 1; what is painted does not.
    def contains_children? : Bool
      false
    end

    # A click lands where it is drawn: nothing outside the box, nothing in the letterbox (what lies behind
    # takes it), and inside the image the child gets the point in its own (natural) space.
    def hit_test(point : Vec2) : Widget?
      abs = absolute_bounds # one parent-chain walk: the child's origin is this plus its offset
      return nil unless abs.contains_point(point)
      child = @children.first? || return nil
      f = scale
      return nil if f == 0.0
      origin = Vec2.new(abs.x + child.bounds.x, abs.y + child.bounds.y)
      natural = child.bounds.size
      return nil unless Rect.new(origin.x, origin.y, natural.width * f, natural.height * f).contains_point(point)
      child.hit_test(Widget.unscale_about(point, origin, f))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      [] of DrawPrimitive
    end
  end
end
