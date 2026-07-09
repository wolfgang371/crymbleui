require "./layer"
require "./types"

module CrymbleUI
  # Mixin for widgets that own their own rendering layer
  #
  # Layer-owning widgets participate in the three-phase rendering pipeline:
  # - Layout: Layer bounds must stay in sync with widget bounds
  # - Render: Widget primitives render to the layer's backend
  # - Composite: Layer textures are blitted to the window in z-order
  #
  # ## Usage
  #
  # Simple case (Popup, WindowPanel, LayerBox):
  # ```crystal
  # class MyPopup < Widget
  #   include LayerOwner
  #
  #   def initialize(...)
  #     super(...)
  #     @internal_layer = Layer.new("popup_#{id}", Rect.zero, z_index: 1000, owner_widget: self)
  #   end
  # end
  # ```
  #
  # Override case (Window with different field name):
  # ```crystal
  # class Window < Widget
  #   include LayerOwner
  #
  #   getter root_layer : Layer?
  #
  #   def layer : Layer?
  #     @root_layer  # Override to return different field
  #   end
  # end
  # ```
  #
  # ## Key Invariants
  #
  # 1. Layer bounds MUST stay in sync with widget.absolute_bounds
  # 2. Layer-owning widgets MUST NOT skip layout (bounds sync would break)
  # 3. Layer widgets must populate layer.widgets in perform_layout
  #
  module LayerOwner
    # Internal layer storage (can be nil for conditional layer ownership)
    # Widgets that always have a layer should create it in initialize()
    # Widgets with conditional layers (MenuBar) create in perform_layout()
    #
    # @[Reconcile]: carry the layer (with its backend + rendered state) across a rebuild instead of
    # discarding the fresh Layer.new the new instance built in initialize — so the reconciled layer is
    # NOT first_render? and its pixels survive (the keystone for a cheap rebuild). Mirrors the existing
    # VirtualMatrix content_layer reconcile. Widget#copy_state_from re-points owner_widget to the new
    # instance afterwards (a stale owner breaks in_tree?/bounds).
    @[Reconcile]
    @internal_layer : Layer?

    # Expose internal layer for renderer
    # Override this if using a different field name (e.g., Window uses @root_layer)
    def layer : Layer?
      @internal_layer
    end

    # Pull-based bounds: compute the correct bounds for a given layer.
    # Override in each LayerOwner to return the appropriate bounds.
    # Default: return absolute_bounds (correct for simple single-layer widgets).
    def compute_bounds_for_layer(layer : Layer) : Rect
      absolute_bounds
    end

    # Layer-owning widgets must not skip layout.
    # Pull-based bounds handles position/size, but perform_layout also:
    # - Populates layer.widgets (renderer needs correct widget references)
    # - Syncs layer z_index (after reconciliation)
    # - Updates layer-specific state (scroll offsets, cache_extent, etc.)
    # Skipping layout could leave these stale, causing rendering artifacts.
    protected def can_skip_layout?(constraints : BoxConstraints) : Bool
      return false if layer
      super
    end

    # Convenience method to check if this widget currently owns a layer
    def has_layer? : Bool
      !layer.nil?
    end

    # Convenience method to get layer (raises if nil)
    # Use when you know the layer exists
    def layer! : Layer
      layer || raise "Layer not initialized for #{self.class.name}"
    end

    # === ANCESTOR NOTIFICATION CALLBACKS ===
    # Called when ancestor's z-index changed (e.g., bring-to-front)
    # base_z: the ancestor's new z-index (layer owner computes own offset)
    def on_ancestor_z_index_changed(base_z : Int32)
      # Default: no-op
    end
  end
end
