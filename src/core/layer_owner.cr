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

    # Resize clip delta: during ancestor resize drag, layers must shrink (not expand)
    # to prevent ghost pixels from cache_extent pre-rendered content.
    # Format: {dw, dh, dx, dy} — cumulative delta from resize start.
    @resize_clip_delta : Tuple(Float64, Float64, Float64, Float64)?

    # Expose internal layer for renderer
    # Override this if using a different field name (e.g., Window uses @root_layer)
    def layer : Layer?
      @internal_layer
    end

    # Pull-based bounds: compute the correct bounds for a given layer.
    # Override in each LayerOwner to return the appropriate bounds.
    # Default: return absolute_bounds (correct for simple single-layer widgets).
    def compute_bounds_for_layer(layer : Layer) : Rect
      apply_resize_clip(absolute_bounds, layer)
    end

    # Apply resize clamping during ancestor resize drag.
    # Content layers only shrink (not expand) to prevent ghost pixels.
    # Override shrink_on_resize? per-layer to allow expansion (e.g., cursor overlay).
    protected def apply_resize_clip(natural : Rect, layer : Layer) : Rect
      if delta = @resize_clip_delta
        dw, dh, dx, dy = delta
        # Capture baseline on first resize_move — stable for entire drag
        orig = layer.resize_baseline || begin
          layer.resize_baseline = natural
          natural
        end
        clamped_dw = {dw, 0.0}.min  # Only shrink
        clamped_dh = {dh, 0.0}.min
        Rect.new(orig.x + dx, orig.y + dy, orig.width + clamped_dw, orig.height + clamped_dh)
      else
        layer.resize_baseline = nil  # Clear baseline when not resizing
        natural
      end
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
    # With pull-based bounds, position_changed and resize_start are no longer needed.
    # resize_move/end are kept to track @resize_clip_delta for content clamping.

    # Called during ancestor resize with cumulative delta from start
    # dw/dh: change from original size at resize start
    # dx/dy: position change (for left/top resize)
    def on_ancestor_resize_move(dw : Float64, dh : Float64, dx : Float64 = 0.0, dy : Float64 = 0.0)
      @resize_clip_delta = {dw, dh, dx, dy}
    end

    # Called when ancestor resize completes
    # Clean up any captured state
    def on_ancestor_resize_end
      @resize_clip_delta = nil
    end

    # Called when ancestor's z-index changed (e.g., bring-to-front)
    # base_z: the ancestor's new z-index (layer owner computes own offset)
    def on_ancestor_z_index_changed(base_z : Int32)
      # Default: no-op
    end
  end
end
