require "./layer"
require "../rendering/render_backend"

module CrymbleUI
  class Layer
    # A never-emitted painting layer (a widget whose render_layer names a layer no longer in the tree) is a
    # defect: strict, it raises; otherwise the widget's layers go where its nearest ancestor paints, and the
    # count says it happened. Strict in specs (spec_helper) and in checked builds.
    class_property strict_nesting : Bool = {{ flag?(:verify_bounds) || flag?(:cache_validation) }}
    class_property orphaned_nestings : Int32 = 0
    # perf-audit: widgets the composite order's walk visited, and layers it emitted (one of each per re-collect)
    class_property composite_walk_visits : Int32 = 0
    class_property composite_emits : Int32 = 0

    # Bumped when the composite SET or ORDER changes without a layout: a boundary re-z'd (a panel raised, a
    # LayerBox or popup), or a layer owner attached to or detached from the tree by its container (a grid's
    # cells). The renderer re-collects after a layout, and compares this at the start of each frame and around
    # each owner's flush.
    class_getter order_version : Int32 = 0

    def self.reorder! : Nil
      @@order_version &+= 1
    end

    # The layers of `root`'s tree in COMPOSITE order, back to front - the one order the renderer, a frame
    # capture and Window#collect_all_layers share:
    # - a layer owner's layers come in their own z order (z is local to its owner);
    # - directly after each layer X come the layer owners PAINTED INTO X (Widget#painting_layer: a sticky
    #   header cell is painted into the sticky band, not the grid's content), each with everything painted
    #   into its own layers, before X's next sibling layer - so what covers a widget covers the layers inside
    #   it. Owners painted into the same X order by sibling_key;
    # - overlays (Widget#composites_as_overlay? - popups) come after the whole tree: popups in the tree by z
    #   then tree order, then the Window's overlays (and popups inside them) by z then opening order - the
    #   order Window#hit_test checks them in, reversed.
    # Ownerless layers (the drag ghost) are no part of it. O(widgets): one walk down, one emit.
    def self.composite_order(root : Widget) : Array(Layer)
      CompositeOrder.new(root).layers
    end

    # How `owner` orders among the widgets painted into the same layer, whose owner is `ranker`: the rank
    # `ranker` gives it, then boundaries after plain content, by their z, then `index` (tree order). The one
    # key for painting (composite_order) and for hit testing (Widget#children_in_hit_order).
    def self.sibling_key(ranker : Widget?, owner : Widget, index : Int32) : {Int32, Int32, Int32, Int32}
      rank = ranker && ranker.ranks_children? ? ranker.composite_rank(owner) : 0
      if owner.responds_to?(:compositing_z_index) && !overlay?(owner) # boundary?, with the type narrowed
        {rank, 1, owner.compositing_z_index, index}
      else
        {rank, 0, 0, index}
      end
    end

    # A compositing z-boundary (WindowPanel, LayerBox): ordered by its z among what is painted into the same
    # layer. An overlay (a popup) answers compositing_z_index too - for its place among the overlays - but is
    # no boundary.
    def self.boundary?(widget : Widget) : Bool
      widget.responds_to?(:compositing_z_index) && !overlay?(widget)
    end

    def self.overlay?(widget : Widget) : Bool
      widget.responds_to?(:composites_as_overlay?) && widget.composites_as_overlay?
    end
  end

  # One pass of Layer.composite_order: record every layer owner under the layer it is painted into, then emit
  # depth-first from the roots.
  private class CompositeOrder
    # A layer owner, its own layers (in their z order) and its place in tree order.
    private record Group, owner : Widget, layers : Array(Layer), index : Int32

    @nested = Hash(Layer, Array(Group)).new.compare_by_identity
    @owned = Set(Layer).new.compare_by_identity
    @roots = [] of Group
    @tree_popups = [] of Group
    @overlays = [] of Group
    getter layers = [] of Layer

    def initialize(root : Widget)
      walk(root, root.render_layer)
      rehome_orphans if @nested.each_key.any? { |x| !@owned.includes?(x) }
      emit_sorted(@roots, nil)
      emit_overlays
      assert_complete
    end

    # `painting`: the layer `widget` is painted into; `opened`: inside a Window overlay.
    private def walk(widget : Widget, painting : Layer?, opened = false) : Nil
      Layer.composite_walk_visits += 1
      if own = own_layers(widget)
        group = Group.new(widget, own, @owned.size) # its first layer's position in the walk: tree order
        own.each { |l| @owned << l }
        if Layer.overlay?(widget)
          (opened ? @overlays : @tree_popups) << group
        elsif p = painting
          (@nested[p] ||= [] of Group) << group
        else
          @roots << group
        end
      end
      below = widget.layer || painting
      widget.children.each { |child| walk(child, child.render_layer || below, opened) }
      if widget.responds_to?(:overlays)
        widget.overlays.each { |overlay| walk(overlay, overlay.render_layer || below, opened: true) }
      end
    end

    # The widget's own layers in their z order (insertion order among equals), or nil - no allocation for the
    # many widgets that own none.
    private def own_layers(widget : Widget) : Array(Layer)?
      primary = widget.layer
      return primary.try { |l| [l] } unless widget.responds_to?(:each_owned_layer)
      layers = primary ? [primary] : [] of Layer
      widget.each_owned_layer { |l| layers << l }
      return nil if layers.empty?
      layers.each_with_index.to_a.sort_by! { |(l, i)| {l.z_index, i} }.map(&.[0])
    end

    # Groups painted into a layer no widget in the tree owns can never be emitted: strict, a defect; otherwise
    # each goes under the nearest ancestor's layer (or render_layer) that IS owned - the rule of
    # Widget#painting_layer, skipping what is stale - counted.
    private def rehome_orphans : Nil
      @nested.keys.each do |x|
        next if @owned.includes?(x)
        groups = @nested.delete(x).not_nil!
        raise CompositeOrderError.new("#{groups.map(&.owner.class).join(", ")} painted into layer #{x.id}, which no widget in the tree owns") if Layer.strict_nesting
        groups.each do |g|
          Layer.orphaned_nestings += 1
          if home = owned_painting_layer(g.owner)
            (@nested[home] ||= [] of Group) << g
          else
            @roots << g
          end
        end
      end
    end

    private def owned_painting_layer(owner : Widget) : Layer?
      node = owner.parent
      while node
        {node.layer, node.render_layer}.each { |l| return l if l && @owned.includes?(l) }
        node = node.parent
      end
      nil
    end

    private def emit(group : Group) : Nil
      group.layers.each do |layer|
        Layer.composite_emits += 1
        @layers << layer
        emit_sorted(@nested[layer]?, layer.owner_widget)
      end
    end

    # The groups painted into one layer, whose owner is `ranker`, in order.
    private def emit_sorted(groups : Array(Group)?, ranker : Widget?) : Nil
      return unless groups
      groups.sort_by { |g| Layer.sibling_key(ranker, g.owner, g.index) }.each { |g| emit(g) }
    end

    private def emit_overlays : Nil
      {@tree_popups, @overlays}.each do |tier|
        tier.sort_by { |g| {overlay_z(g.owner), g.index} }.each { |g| emit(g) }
      end
    end

    private def overlay_z(owner : Widget) : Int32
      owner.responds_to?(:compositing_z_index) ? owner.compositing_z_index : 0
    end

    # Every recorded layer emitted exactly once.
    private def assert_complete : Nil
      return if @layers.size == @owned.size
      raise CompositeOrderError.new("composite order emitted #{@layers.size} of #{@owned.size} layers") if Layer.strict_nesting
      Layer.orphaned_nestings += 1
    end
  end
end
