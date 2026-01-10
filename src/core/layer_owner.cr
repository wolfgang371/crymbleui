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
    @internal_layer : Layer?

    # Expose internal layer for renderer
    # Override this if using a different field name (e.g., Window uses @root_layer)
    def layer : Layer?
      @internal_layer
    end

    # Layer-owning widgets should not skip layout
    # Layer.bounds must stay synchronized with widget.absolute_bounds
    # If we skip layout, bounds can drift and compositing breaks
    #
    # This guard is called by Widget#layout via can_skip_layout?
    # Returns false if we have a layer, forcing layout to run
    #
    # Note: We call super instead of previous_def because Widget defines can_skip_layout?
    protected def can_skip_layout?(constraints : BoxConstraints) : Bool
      # Never skip if we own a layer - bounds must stay in sync
      return false if layer

      # For conditional layer owners (MenuBar), allow skip if no layer yet
      # Call super to check constraint caching in Widget base class
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

    # Helper to sync layer bounds with widget absolute_bounds
    # Call this in perform_layout after setting @bounds
    protected def sync_layer_bounds
      if layer = self.layer
        layer.bounds = absolute_bounds
      end
    end

    # Helper to sync layer bounds with custom rect (for border expansion, etc.)
    # Used by Popup which expands layer bounds for border stroke
    protected def sync_layer_bounds(bounds : Rect)
      if layer = self.layer
        layer.bounds = bounds
      end
    end

    # === ANCESTOR NOTIFICATION CALLBACKS ===
    # Override these in layer-owning widgets that need to respond to ancestor changes.
    # Default implementations are no-ops.

    # Called when an ancestor's position changed (e.g., during drag)
    # delta: the position change in absolute coordinates
    def on_ancestor_position_changed(delta : Vec2)
      # Default: no-op
    end

    # Called when an ancestor starts resizing
    # Capture any state needed to compute deltas during resize
    def on_ancestor_resize_start
      # Default: no-op
    end

    # Called during ancestor resize with cumulative delta from start
    # dw/dh: change from original size at resize start
    def on_ancestor_resize_move(dw : Float64, dh : Float64)
      # Default: no-op
    end

    # Called when ancestor resize completes
    # Clean up any captured state
    def on_ancestor_resize_end
      # Default: no-op
    end

    # Called when ancestor's z-index changed (e.g., bring-to-front)
    # base_z: the ancestor's new z-index (layer owner computes own offset)
    def on_ancestor_z_index_changed(base_z : Int32)
      # Default: no-op
    end
  end
end
