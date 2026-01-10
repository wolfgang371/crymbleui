require "../core/types"
require "../core/layer"
require "../core/widget"
require "../core/assert"
require "./draw_primitive"
require "./render_backend"

module CrymbleUI
  # Layer rendering engine - shared logic for SFML and headless rendering
  # Works with any RenderBackend (SFML or test)
  # Contains ALL layer handling: collection, rendering, compositing
  # Renderers just implement backend creation and compositing specifics
  module LayerRenderer
    # Profile data collection - use module-level storage accessible from both instance and class methods
    # Crystal class variables in modules have different scopes for instance vs class methods!
    # Solution: use class methods for all access to ensure single storage location
    class_property profile_data : Array(String) = [] of String
    {% if flag?(:PROFILE) %}
      class_property profile_enabled : Bool = true
    {% else %}
      class_property profile_enabled : Bool = false
    {% end %}

    # Frame-level instrumentation counters (reset each frame)
    class_property frame_layout_count : Int32 = 0
    class_property frame_widget_count : Int32 = 0
    class_property frame_primitive_count : Int32 = 0
    class_property frame_layer_count : Int32 = 0
    class_property frame_composite_count : Int32 = 0               # composite_layer_to_window calls
    class_property frame_viewport_cache_count : Int32 = 0          # viewport_cache layers composited
    class_property frame_layers_total : Int32 = 0                  # total layers collected
    class_property frame_layers_needing_render : Int32 = 0         # layers where needs_render?=true
    class_property frame_widgets_iterated : Int32 = 0              # widgets passed to render_single_widget (before cache check)
    class_property frame_pure_container_skips : Int32 = 0          # pure containers (VStack, HStack) skipped
    class_property frame_empty_leaf_primitives : Int32 = 0         # leaf widgets with empty primitives (potential bug)
    class_property rendered_widgets : Array(String) = [] of String # Widget names rendered this frame

    # Per-phase timing (in milliseconds)
    class_property phase_layout_ms : Float64 = 0.0
    class_property phase_render_ms : Float64 = 0.0
    class_property phase_composite_ms : Float64 = 0.0
    class_property phase_display_ms : Float64 = 0.0

    def self.reset_frame_counters
      @@frame_layout_count = 0
      @@frame_widget_count = 0
      @@frame_primitive_count = 0
      @@frame_layer_count = 0
      @@frame_composite_count = 0
      @@frame_viewport_cache_count = 0
      @@frame_layers_total = 0
      @@frame_layers_needing_render = 0
      @@frame_widgets_iterated = 0
      @@frame_pure_container_skips = 0
      @@frame_empty_leaf_primitives = 0
      @@rendered_widgets.clear
      @@phase_layout_ms = 0.0
      @@phase_render_ms = 0.0
      @@phase_composite_ms = 0.0
      @@phase_display_ms = 0.0
    end

    # Simple profiling helper - wraps a block with timing
    private def profile(name : String, &block)
      if LayerRenderer.profile_enabled
        start = Time.monotonic
        result = yield
        elapsed = Time.monotonic - start
        measurement = "#{name}: #{elapsed.total_milliseconds.round(2)}ms"
        LayerRenderer.profile_data << measurement
        result
      else
        yield
      end
    end

    # Record profile measurement (for external callers)
    def self.record_profile(name : String, duration_ms : Float64)
      return unless profile_enabled
      profile_data << "#{name}: #{duration_ms.round(2)}ms"
    end

    # Flush profile data to file
    def self.flush_profile_data
      return unless profile_enabled
      return if profile_data.empty?

      File.write("/tmp/crymble_profile.txt", profile_data.join("\n"))
    end

    # Abstract methods that renderers must implement
    abstract def ensure_layer_backend(layer : Layer, width : Int32, height : Int32)
    abstract def composite_layer_to_window(layer : Layer)
    abstract def create_widget_backend(width : Int32, height : Int32) : RenderBackend

    # Instrumentation hooks (optional - TestRenderer implements these)
    def increment_compositor_call_count
      # Default: no-op (only TestRenderer tracks this)
    end

    def increment_compositor_skip_count
      # Default: no-op (only TestRenderer tracks this)
    end

    def increment_render_layer_count
      # Default: no-op (only TestRenderer tracks this)
    end

    # === Validation Helpers (Option C: Graceful Degradation) ===

    # Check if layer has valid dimensions for rendering
    private def valid_layer_dimensions?(layer : Layer) : Bool
      layer.bounds.width > 0 && layer.bounds.height > 0 &&
        layer.bounds.width.finite? && layer.bounds.height.finite?
    end

    # Check if widget has valid dimensions for rendering
    private def valid_widget_dimensions?(widget : Widget) : Bool
      abs = widget.absolute_bounds
      abs.width > 0 && abs.height > 0 &&
        abs.width.finite? && abs.height.finite?
    end

    # Convert absolute coordinates to layer-local pixels with proper rounding
    # Round the FINAL layer-local position (not intermediate absolute position)
    # This ensures consistent pixel placement regardless of layer offset
    # (inspired by React Native's "round at the end" strategy)
    private def round_to_layer_pixels(
      absolute_x : Float64,
      absolute_y : Float64,
      layer_offset_x : Float64,
      layer_offset_y : Float64,
    ) : Tuple(Int32, Int32)
      # Calculate layer-local position in float, THEN round once
      # Using .to_i (truncate) for consistency - all widgets truncate same direction
      layer_local_x = (absolute_x - layer_offset_x).to_i
      layer_local_y = (absolute_y - layer_offset_y).to_i
      {layer_local_x, layer_local_y}
    end

    # Render all layers for a widget tree (called by render_frame)
    # ghost_layer: optional drag ghost layer to include in rendering
    # highlight_layer: optional drop zone highlight layer
    def render_all_layers(root_widget : Widget, ghost_layer : Layer? = nil, highlight_layer : Layer? = nil)
      # Collect all layers from widget tree
      layers = profile("collect_layers") { collect_layers(root_widget) }

      # Add highlight layer if present (for drop zone feedback)
      if highlight = highlight_layer
        layers << highlight
      end

      # Add ghost layer if present (for drag-and-drop preview)
      if ghost = ghost_layer
        layers << ghost
      end

      # Instrumentation: track total layers (use explicit module access for correct scoping)
      LayerRenderer.frame_layers_total = layers.size

      {% if flag?(:DEBUG_RENDER) %}
        puts "\n========== RENDER_ALL_LAYERS =========="
        puts "Collected #{layers.size} layers:"
        layers.each_with_index do |layer, i|
          puts "  #{i}: #{layer.id} (z=#{layer.z_index}, widgets=#{layer.widgets.size}, dirty=#{layer.dirty_widgets.size}, needs_render=#{layer.needs_render?})"
          layer.widgets.each_with_index do |w, wi|
            puts "    [#{wi}] #{w.class.name.split("::").last}##{w.path_id} (state=#{w.state})"
          end
        end
      {% end %}

      # Ensure all collected layers have backends (even if they don't need rendering yet)
      # Tests expect to access layer.backend after render_frame
      layers.each do |layer|
        if layer.backend.nil?
          # Viewport_cache layers need larger buffer (viewport + cache extent)
          width, height = if layer.viewport_cache
                            layer.calculate_buffer_size_with_cache
                          else
                            layer.calculate_backend_size(layer.bounds.width, layer.bounds.height)
                          end
          ensure_layer_backend(layer, width, height)
        end
      end

      # Render each layer that needs it
      rendered_count = 0
      profile("render_layers") do
        layers.each do |layer|
          if layer.needs_render?
            LayerRenderer.frame_layers_needing_render += 1 # Instrumentation
            render_layer(layer)
            rendered_count += 1
          end
        end
      end

      {% if flag?(:DEBUG_RENDER) %}
        puts "[RENDERED: #{rendered_count}/#{layers.size} layers needed rendering]"
      {% end %}

      # Composite layers to window (renderer-specific, timed)
      # NOTE: Must run even if rendered_count == 0 because layer.bounds might have changed (drag)
      composite_start = Time.monotonic
      profile("composite") do
        increment_compositor_call_count # Instrumentation
        clear_window_background
        layers.sort_by(&.z_index).each do |layer|
          composite_layer_to_window(layer)
        end
      end
      LayerRenderer.phase_composite_ms = (Time.monotonic - composite_start).total_milliseconds
    end

    # Clear window to background color (renderer-specific)
    abstract def clear_window_background

    # Render a layer to its backend buffer
    private def render_layer(layer : Layer)
      LayerRenderer.frame_layer_count += 1 # Instrumentation

      # Validation (Option C): Skip layers with invalid dimensions
      return unless valid_layer_dimensions?(layer)

      # Ensure layer has backend of correct size
      # Viewport_cache layers need larger buffer (viewport + cache extent)
      width, height = if layer.viewport_cache
                        layer.calculate_buffer_size_with_cache
                      else
                        layer.calculate_backend_size(layer.bounds.width, layer.bounds.height)
                      end

      if layer.backend_needs_resize?(layer.bounds.width, layer.bounds.height)
        # Save old backend before resizing to preserve cached content
        old_backend = layer.backend
        ensure_layer_backend(layer, width, height)

        # Copy old cached pixels to new backend (GPU→GPU blit, very fast)
        # This preserves all cached widget content, avoiding mass re-render
        if old_backend && (new_backend = layer.backend)
          new_backend.blit(old_backend, 0, 0)
        end

        # DON'T reset first_render - old content is preserved
        # Selective rendering will handle only newly visible areas
      end

      return unless backend = layer.backend # Skip if no backend assigned

      # Panel bounds are updated immediately during drag (WindowPanel line 423-428)
      # So widget absolute_bounds are already correct - no offset needed
      # drag_offset was previously used to correct stale bounds, but bounds are no longer stale
      drag_offset = Vec2.new(0.0, 0.0)

      # Selective rendering logic (same for SFML and test)
      # - First render: always full render (layer buffer created)
      # - NeedsLayout: always full render (structural change)
      # - NeedsRender: selective render using dirty_widgets
      # - Layer position changes don't require re-render (buffer just moves during composite)

      # Use WidgetState enum to determine render mode (not heuristics)
      # NeedsLayout = full render, NeedsRender = selective render
      # Full render on first render or layout change (structural change)
      # Viewport_cache is orthogonal - affects compositing, not render mode
      full_render = layer.first_render? || layer.state == WidgetState::NeedsLayout

      {% if flag?(:DEBUG_RENDER) %}
        # DEBUG: Log render decisions
        puts "\n=== LAYER RENDER: #{layer.id} ==="
        puts "  bounds: (#{layer.bounds.x}, #{layer.bounds.y}) #{layer.bounds.width}x#{layer.bounds.height}"
        puts "  state: #{layer.state}"
        puts "  first_render: #{layer.first_render?}"
        puts "  full_render: #{full_render}"
        puts "  dirty_widgets: #{layer.dirty_widgets.size}"
        if !full_render && layer.dirty_widgets.size > 0
          layer.dirty_widgets.each { |w| puts "    - #{w.class.name.split("::").last}##{w.path_id}" }
        end
      {% end %}

      # Clear buffer on full render (to layer background color)
      # Viewport_cache layers DON'T clear every frame - they keep cached content
      # and shift viewport during composite
      if full_render
        backend.clear(layer.background_color)
        # For viewport_cache layers, initialize buffer_origin on first render
        if layer.viewport_cache
          layer.buffer_origin = layer.scroll_offset - Vec2.new(layer.cache_extent, layer.cache_extent)
        end
        {% if flag?(:DEBUG_RENDER) %}
          puts "  [CLEARED BUFFER to bg=#{layer.background_color}]"
        {% end %}
      elsif layer.viewport_cache
        # Handle viewport_cache scroll: check if viewport moved beyond cache extent
        # Returns true if buffer was recentered (needs full render of visible widgets)
        if handle_viewport_cache_scroll(layer, backend)
          full_render = true # Force full render after buffer recenter
        end
      end

      # Translate primitives to layer-local coordinates
      layer_offset_x = layer.bounds.x
      layer_offset_y = layer.bounds.y

      # Collect widgets to render (full or selective)
      widgets_to_render = collect_widgets_to_render(layer, full_render)

      # Validate that siblings don't overlap (invariant check)
      # OPTIMIZATION: Only validate on first render or layout pass, not on scroll frames
      # Scroll doesn't change widget structure, so re-validating is wasted O(n²) work
      if layer.first_render? || layer.state == WidgetState::NeedsLayout
        validate_sibling_bounds(widgets_to_render)
      end

      # Push scissor clip for layer bounds to clip widgets at layer edges
      # This allows smooth clipping of partially-visible widgets (e.g., ScrollView content)
      # Note: scissor is suspended during background capture/restore in render_single_widget
      # because OpenGL scissor is global state and would affect draws to other textures
      #
      # IMPORTANT: For viewport_cache layers, clip to BUFFER size not viewport size!
      # Viewport_cache buffers are larger than viewport (viewport + 2*cache_extent), and widgets
      # render to buffer-relative positions that can exceed viewport dimensions.
      layer_clip_rect = if layer.viewport_cache
                          # Viewport_cache: clip to buffer size (allows rendering beyond viewport)
                          Rect.new(0.0, 0.0, backend.width.to_f64, backend.height.to_f64)
                        else
                          # Normal: clip to viewport (layer bounds)
                          Rect.new(0.0, 0.0, layer.bounds.width, layer.bounds.height)
                        end
      backend.push_clip(layer_clip_rect)

      # Render each widget using per-widget texture approach
      widgets_to_render.each do |widget|
        render_single_widget(widget, backend, layer_offset_x, layer_offset_y, layer, drag_offset)
      end

      # Second pass: render foreground primitives for DecoratedContainers
      # Foreground renders AFTER all children, on top of everything
      widgets_to_render.each do |widget|
        if widget.responds_to?(:has_foreground?) && widget.has_foreground?
          render_foreground_primitives(widget, backend, layer_offset_x, layer_offset_y, layer)
        end
      end

      backend.pop_clip
      backend.display

      # Clear the "just cleared" flag - texture now reflects the rendered content
      layer.buffer_just_cleared = false

      {% if flag?(:DEBUG_TRANSPARENCY) %}
        # DEBUG: Check for transparent pixels in the layer (contamination check)
        check_layer_transparency(layer, backend)
      {% end %}

      layer.clear_render_state
    end

    # Check a layer's backend for transparent pixels (debug helper)
    private def check_layer_transparency(layer : Layer, backend : RenderBackend)
      width = backend.width
      height = backend.height
      transparent_count = 0
      first_transparent_locations = [] of Tuple(Int32, Int32, UInt8)

      # Read all pixels at once (one GPU→CPU transfer)
      begin
        all_pixels = backend.get_pixels(0, 0, width, height)
        all_pixels.each_with_index do |pixel, idx|
          if pixel.a < 255
            transparent_count += 1
            if first_transparent_locations.size < 10
              x = idx % width
              y = idx // width
              first_transparent_locations << {x, y, pixel.a}
            end
          end
        end
      rescue ex
        puts "  ⚠️  LAYER #{layer.id}: Could not check transparency: #{ex.message}"
        return
      end

      if transparent_count > 0
        puts "  ⚠️  LAYER #{layer.id}: #{transparent_count} TRANSPARENT PIXELS DETECTED!"
        first_transparent_locations.each do |loc|
          puts "      at (#{loc[0]}, #{loc[1]}): alpha=#{loc[2]}"
        end
      else
        puts "  ✓ LAYER #{layer.id}: All pixels opaque (#{width}x#{height})"
      end
    end

    # Render a single dirty widget (selective rendering optimization)
    # Uses per-widget texture: widget renders to own backend, then blits to layer
    # Directly renders the widget without tree traversal - O(1) instead of O(n)
    private def render_single_widget(widget : Widget, backend : RenderBackend, offset_x : Float64, offset_y : Float64, layer : Layer, drag_offset : Vec2)
      # Instrumentation: count all widgets passed to this method (before any early exits)
      LayerRenderer.frame_widgets_iterated += 1

      return if widget.skip_render?

      # Get widget absolute bounds for rendering
      widget_abs = widget.absolute_bounds

      # Validation (Option C): Skip widgets with invalid dimensions
      # Catches NaN, Infinity, and zero/negative sizes early
      return unless valid_widget_dimensions?(widget)

      # Apply drag offset for resizing/dragging panels (corrects stale absolute_bounds)
      adjusted_x = widget_abs.x + drag_offset.x
      adjusted_y = widget_abs.y + drag_offset.y

      # Widget size in pixels (for backend creation)
      # CRITICAL: Use ceil() not to_i (truncation) to ensure backend is large enough
      # When bounds.height=31.5, primitives may extend to y=31.5, so backend needs 32 rows
      # Truncation to 31 would clip the bottom border/content
      widget_width = widget_abs.width.ceil.to_i
      widget_height = widget_abs.height.ceil.to_i

      # Skip zero-size widgets (no visible content)
      return if widget_width <= 0 || widget_height <= 0

      # Calculate layer-local position for visibility check
      # Round absolute coords relative to root BEFORE subtracting layer offset
      # This prevents accumulating rounding errors through nested widgets
      layer_local_x, layer_local_y = round_to_layer_pixels(adjusted_x, adjusted_y, offset_x, offset_y)
      layer_width = layer.bounds.width.ceil.to_i
      layer_height = layer.bounds.height.ceil.to_i

      # Viewport_cache layers: use buffer-relative positioning
      # Widget position in buffer = content position - buffer_origin
      # Buffer origin shifts as we scroll (maintains cache window around viewport)
      if layer.viewport_cache
        # Calculate position in buffer coordinates
        buffer_x = layer_local_x - layer.buffer_origin.x.to_i
        buffer_y = layer_local_y - layer.buffer_origin.y.to_i

        # Get actual buffer dimensions
        buffer_width = backend.width
        buffer_height = backend.height

        # Skip widgets completely outside buffer bounds
        if buffer_y + widget_height <= 0 || # completely above buffer
           buffer_x + widget_width <= 0 ||  # completely left of buffer
           buffer_y >= buffer_height ||     # completely below buffer
           buffer_x >= buffer_width         # completely right of buffer
          {% if flag?(:DEBUG_RENDER) %}
            puts "    [SKIP OFF-BUFFER] #{widget.class.name.split("::").last}##{widget.path_id} buffer(#{buffer_x},#{buffer_y})"
          {% end %}
          return
        end

        # Use buffer-relative position for rendering (NOT viewport-relative)
        layer_local_x = buffer_x
        layer_local_y = buffer_y
      else
        # Non-viewport_cache: skip widgets completely outside layer bounds
        if layer_local_y + widget_height <= 0 || # completely above
           layer_local_x + widget_width <= 0 ||  # completely left
           layer_local_y >= layer_height ||      # completely below
           layer_local_x >= layer_width          # completely right
          {% if flag?(:DEBUG_RENDER) %}
            puts "    [SKIP OFF-SCREEN] #{widget.class.name.split("::").last}##{widget.path_id} at layer(#{layer_local_x},#{layer_local_y})"
          {% end %}
          return
        end
      end

      # OPTIMIZATION: For viewport_cache layers, check cache FIRST before get_primitives
      # This skips the get_primitives call for cached widgets (~90% of visible widgets during scroll)
      if layer.viewport_cache
        if existing_backend = widget.widget_backend
          if existing_backend.width == widget_width && existing_backend.height == widget_height
            # Widget has valid cached backend - check if content changed
            if widget.has_valid_primitive_cache? && !widget.needs_render?
              # Fast path: blit cached content, skip ALL other work including get_primitives
              backend.blit(existing_backend, layer_local_x, layer_local_y)
              return
            end
          end
        end
      end

      # EARLY CHECK: Pure containers (VStack, HStack) with no visual content
      # should be skipped entirely - they don't need widget_backend at all.
      # Their children will be rendered separately.
      # This prevents creating uninitialized textures that could cause artifacts.
      primitives = widget.get_primitives(widget.bounds)

      is_pure_container = !widget.children.empty? && primitives.empty?
      if is_pure_container
        LayerRenderer.frame_pure_container_skips += 1
        {% if flag?(:DEBUG_RENDER) %}
          puts "    [SKIP PURE CONTAINER] #{widget.class.name.split("::").last}##{widget.path_id} (children will render)"
        {% end %}
        return
      end

      # DETECTION: Leaf widget with empty primitives is suspicious (potential bug)
      # A widget with no children AND no primitives has nothing to render - why does it exist?
      if widget.children.empty? && primitives.empty?
        LayerRenderer.frame_empty_leaf_primitives += 1
        {% if flag?(:DEBUG_RENDER) %}
          puts "    [WARNING] Empty leaf widget: #{widget.class.name.split("::").last}##{widget.path_id} (no children, no primitives)"
        {% end %}
        # Continue rendering anyway (might be intentionally invisible)
      end

      # Instrumentation: count only actually-rendered widgets (not cached blits)
      LayerRenderer.frame_widget_count += 1
      LayerRenderer.rendered_widgets << "#{widget.class.name.split("::").last}##{widget.path_id}"

      # Track if size changed (for detailed debug output)
      size_changed = false
      old_width = 0
      old_height = 0

      # Ensure widget has backend of correct size
      # Create new backend if missing or size changed
      if widget_backend = widget.widget_backend
        # Check if size changed (need new backend)
        if widget_backend.width != widget_width || widget_backend.height != widget_height
          old_width = widget_backend.width
          old_height = widget_backend.height
          size_changed = true

          {% if flag?(:DEBUG_SIZE_CHANGE) %}
            puts "    ⚠️  [SIZE CHANGE] #{widget.class.name.split("::").last}##{widget.path_id}"
            puts "        OLD: #{old_width}x#{old_height} → NEW: #{widget_width}x#{widget_height}"
            puts "        Layer: #{layer.id}"
          {% end %}

          # CRITICAL: Dispose old backend before replacement to release GPU memory immediately
          # Without this, rapid size changes cause GPU memory accumulation waiting for GC
          widget_backend.dispose

          widget.widget_backend = create_widget_backend(widget_width, widget_height)

          # CRITICAL: Invalidate background_backend when widget size changes!
          # Old background is wrong size → restoring it causes artifacts
          # Must re-capture from layer at new size
          if old_bg = widget.background_backend
            old_bg.dispose # Release GPU memory for old background
          end
          widget.background_backend = nil
        end
      else
        # Create initial backend
        widget.widget_backend = create_widget_backend(widget_width, widget_height)
        # Also invalidate background_backend if it has wrong size (from reconcile)
        # Without this, mismatched background_backend prevents re-capture from layer
        if bg = widget.background_backend
          if bg.width != widget_width || bg.height != widget_height
            bg.dispose # Release GPU memory for mismatched background
            widget.background_backend = nil
          end
        end
      end

      # Safe access: Should always exist after creation above
      widget_backend = widget.widget_backend

      # INVARIANT: Widget backend must exist after creation attempt
      # If this fails, it indicates a bug in backend creation (not expected in normal operation)
      # Use .not_nil! for type narrowing (assert doesn't narrow types in Crystal)
      assert(widget_backend != nil,
        "Widget backend nil for #{widget.path_id} after creation attempt - possible backend allocation failure")
      widget_backend = widget_backend.not_nil!

      # Note: primitives already fetched above (line 387) for pure container check
      # Pure containers already returned early, so we know primitives is non-empty here

      # Track that background was restored (for invariant f check)
      background_restored = false

      # CRITICAL: Suspend scissor clipping during background operations
      # OpenGL scissor is global state - if active on layer backend, it would incorrectly
      # clip draws to widget_backend and background_backend (different textures!)
      backend.suspend_clip

      if background_backend = widget.background_backend
        # Subsequent render: restore background from saved backend (GPU→GPU blit)
        # BUT: size must match! Old background from reconcile may have wrong size.
        if background_backend.width == widget_width && background_backend.height == widget_height
          # Size matches - safe to restore
          {% if flag?(:DEBUG_RENDER) %}
            puts "    [RESTORE BG] #{widget.class.name.split("::").last}##{widget.path_id}"
            puts "      bg_backend=#{background_backend.object_id} → widget_backend=#{widget_backend.object_id}"
          {% end %}
          widget_backend.blit(background_backend, 0, 0)
          background_restored = true
        else
          # Size mismatch! Old background from reconcile has wrong size.
          # Fill with layer background color instead (same as size_changed path)
          {% if flag?(:DEBUG_RENDER) || flag?(:DEBUG_SIZE_CHANGE) %}
            puts "    [FILL BG - SIZE MISMATCH] #{widget.class.name.split("::").last}##{widget.path_id}"
            puts "      background_backend: #{background_backend.width}x#{background_backend.height}"
            puts "      widget needs: #{widget_width}x#{widget_height}"
            puts "      Filling with layer background: #{layer.background_color}"
          {% end %}
          widget_backend.clear(layer.background_color)
          # Dispose old background and create new one at correct size
          background_backend.dispose # Release GPU memory for old background
          new_background = create_widget_backend(widget_width, widget_height)
          new_background.clear(layer.background_color)
          widget.background_backend = new_background
          background_restored = true
        end
      elsif size_changed
        # CRITICAL FIX: Widget size changed - layer contains OLD widget content!
        # Capturing from layer would get contaminated pixels (old anti-aliased text edges).
        # Instead: fill widget_backend with clean layer background color.
        {% if flag?(:DEBUG_RENDER) || flag?(:DEBUG_SIZE_CHANGE) %}
          puts "    [FILL BG - SIZE CHANGE] #{widget.class.name.split("::").last}##{widget.path_id}"
          puts "      OLD: #{old_width}x#{old_height} → NEW: #{widget_width}x#{widget_height}"
          puts "      Filling with layer background: #{layer.background_color}"
        {% end %}
        widget_backend.clear(layer.background_color)
        # Create background_backend filled with layer bg for future RESTORE operations
        background_backend = create_widget_backend(widget_width, widget_height)
        background_backend.clear(layer.background_color)
        widget.background_backend = background_backend
        background_restored = true
      end

      # If background not restored yet (first render), capture from layer
      if !background_restored
        # First render or size changed: capture background region from layer to background backend

        # INVARIANT (h): Background capture purity
        # Widget can only capture background if it has NEVER rendered to layer at current bounds
        # Otherwise it would capture its own old content → garbage accumulation!
        assert(!widget.rendered_to_layer_at_current_bounds?,
          "(h - background capture purity): Widget #{widget.class.name.split("::").last}##{widget.path_id} " +
          "cannot capture background - already rendered to layer at current position! " +
          "This would capture own old content causing garbage accumulation.")

        background_backend = create_widget_backend(widget_width, widget_height)
        widget.background_backend = background_backend

        {% if flag?(:DEBUG_SIZE_CHANGE) %}
          # DEBUG: Extra warning when capturing after size change (potential contamination!)
          if size_changed
            puts "    ⚠️  [CAPTURE AFTER SIZE CHANGE] #{widget.class.name.split("::").last}##{widget.path_id}"
            puts "        Capturing #{widget_width}x#{widget_height} from layer at (#{layer_local_x}, #{layer_local_y})"
            puts "        OLD size was #{old_width}x#{old_height}"
            puts "        ⚠️  Layer may still contain OLD widget content → CONTAMINATION RISK!"
          end
        {% end %}

        {% if flag?(:DEBUG_RENDER) %}
          puts "    [CAPTURE BG] #{widget.class.name.split("::").last}##{widget.path_id} from layer #{layer.id}"
          puts "      Widget abs pos: (#{adjusted_x}, #{adjusted_y}), bounds: #{widget.bounds}"
          puts "      Layer offset: (#{offset_x}, #{offset_y})"
          puts "      Layer-local capture pos: (#{layer_local_x}, #{layer_local_y}), size: #{widget_width}x#{widget_height}"
          puts "      Background backend: #{background_backend.object_id}"
        {% end %}
        {% if flag?(:DEBUG_CAPTURE) %}
          # Sample layer to see what color will be captured
          sample_x = layer_local_x + 5
          sample_y = layer_local_y + 5
          if sample_x >= 0 && sample_y >= 0 && sample_x < backend.width && sample_y < backend.height
            pixels = backend.get_pixels(sample_x, sample_y, 1, 1)
            if pixels.size > 0
              sample = pixels[0]
              puts "  [CAPTURE] #{widget.class.name.split("::").last}##{widget.path_id} at layer(#{layer_local_x},#{layer_local_y})"
              puts "    Layer pixel at +5,+5: rgba(#{sample.r},#{sample.g},#{sample.b},#{sample.a})"
            end
          end
        {% end %}

        # WORKAROUND for SFML RenderTexture limitation (see widget.cr @needs_fresh_background):
        # Layer texture may have stale content that we can't clear without breaking rendering.
        # Two cases where we fill with background color instead of blit_region:
        # 1. buffer_just_cleared: layer was cleared on recenter, texture is stale (Bug 1)
        # 2. needs_fresh_background: widget exited viewport, layer has widget's OLD pixels (Bug 2)
        if layer.buffer_just_cleared || widget.needs_fresh_background?
          background_backend.clear(layer.background_color)
          # Clear the per-widget flag after use
          widget.needs_fresh_background = false
        else
          # Normal path: Copy layer region to background backend (GPU→GPU, very fast)
          background_backend.blit_region(backend, layer_local_x, layer_local_y, widget_width, widget_height, 0, 0)
        end
        # CRITICAL: Finalize background_backend texture before using as blit source (SFML requirement)
        # Without this, SFML sprite creation gets stale/uninitialized texture data → artifacts!
        background_backend.display
        # Initialize widget backend with captured background
        widget_backend.blit(background_backend, 0, 0)
        background_restored = true
      end

      # Resume scissor clipping after background operations
      backend.resume_clip

      # INVARIANT (f): Rendering precondition
      # Widget can only render to widget_backend if first time OR background was restored
      # Catches: rendering to stale/dirty buffer (causes double-rendering)
      assert(background_restored,
        "(f - rendering precondition): Widget #{widget.class.name.split("::").last}##{widget.path_id} " +
        "rendering without cleared buffer (would cause double-rendering)")

      {% if flag?(:DEBUG_RENDER) %}
        # DEBUG: Log widget rendering
        puts "  RENDER: #{widget.class.name.split("::").last}##{widget.path_id} at (#{adjusted_x}, #{adjusted_y}) [#{widget_width}x#{widget_height}]"
        # DEBUG: Log primitive count
        if primitives.size > 0
          puts "    primitives: #{primitives.size}"
        end
      {% end %}

      # primitives already fetched above for is_pure_container check
      LayerRenderer.frame_primitive_count += primitives.size # Instrumentation

      # Render primitives to widget's own backend (widget-local coordinates, no offset needed)
      # Wrap rendering with clipping to prevent content overflow (e.g., text extending beyond widget bounds)
      widget_clip_rect = Rect.new(0.0, 0.0, widget_width.to_f64, widget_height.to_f64)
      widget_backend.push_clip(widget_clip_rect)

      primitives.each do |primitive|
        execute_primitive_on_widget_backend(primitive, widget_backend)
      end

      widget_backend.pop_clip
      widget_backend.display

      # Blit widget's backend (background + primitives) to layer backend
      # Note: pure containers already returned early (line 389), so all widgets here have content
      {% if flag?(:DEBUG_RENDER) %}
        puts "    [BLIT TO LAYER] #{widget.class.name.split("::").last}##{widget.path_id} to layer #{layer.id} at (#{layer_local_x}, #{layer_local_y})"
        puts "      widget_backend=#{widget_backend.object_id} → layer_backend=#{backend.object_id}"
      {% end %}
      {% if flag?(:DEBUG_VP) %}
        # DEBUG: Log viewport_cache widget blits
        if layer.viewport_cache
          puts "    [BLIT_VP] #{widget.class.name.split("::").last} to buffer(#{layer_local_x}, #{layer_local_y}) size=#{widget_width}x#{widget_height}"
        end
      {% end %}
      backend.blit(widget_backend, layer_local_x, layer_local_y)
      {% if flag?(:DEBUG_CAPTURE) %}
        puts "  [BLIT] #{widget.class.name.split("::").last}##{widget.path_id} blitted to layer at (#{layer_local_x},#{layer_local_y})"
      {% end %}

      # Mark widget as having rendered to layer at current bounds
      # This prevents re-capturing background later (would capture own content!)
      widget.mark_rendered_to_layer!
    end

    # Execute primitive on widget's own backend (no coordinate offset needed)
    # Primitives are in widget-local coordinates (0,0 origin)
    # Widget backend also uses 0,0 origin, so no translation needed
    private def execute_primitive_on_widget_backend(primitive : DrawPrimitive, backend : RenderBackend)
      case primitive
      when FillRect
        backend.fill_rect(primitive.bounds, primitive.color)
      when DrawRect
        backend.draw_rect(primitive.bounds, primitive.color, primitive.width)
      when DrawLine
        backend.draw_line(primitive.from.x, primitive.from.y, primitive.to.x, primitive.to.y, primitive.color, primitive.width)
      when DrawText
        backend.draw_text(primitive.text, primitive.position, primitive.color, primitive.size)
      when PushClip
        backend.push_clip(primitive.rect)
      when PopClip
        backend.pop_clip
      when DrawCircle
        backend.draw_circle(primitive.center.x, primitive.center.y, primitive.radius, primitive.color, primitive.fill)
      when FillTriangle
        backend.fill_triangle(primitive.p1, primitive.p2, primitive.p3, primitive.color)
      end
    end

    # Render foreground primitives for DecoratedContainer widgets
    # These render directly to layer backend, on top of all children
    private def render_foreground_primitives(widget : Widget, backend : RenderBackend,
                                             layer_offset_x : Float64, layer_offset_y : Float64,
                                             layer : Layer)
      # Get foreground primitives from widget
      prims = widget.foreground_primitives
      return if prims.empty?

      # Calculate widget position in layer-local coordinates
      widget_abs = widget.absolute_bounds
      layer_local_x = (widget_abs.x - layer_offset_x).to_i
      layer_local_y = (widget_abs.y - layer_offset_y).to_i

      # Execute primitives with offset (primitives are widget-local, layer expects layer-local)
      prims.each do |primitive|
        execute_primitive_with_offset(primitive, backend, layer_local_x.to_f64, layer_local_y.to_f64)
      end
    end

    # Execute a primitive on backend with coordinate offset
    # Used for foreground primitives that need to be positioned on layer
    private def execute_primitive_with_offset(primitive : DrawPrimitive, backend : RenderBackend,
                                              offset_x : Float64, offset_y : Float64)
      case primitive
      when FillRect
        offset_bounds = Rect.new(
          primitive.bounds.x + offset_x,
          primitive.bounds.y + offset_y,
          primitive.bounds.width,
          primitive.bounds.height
        )
        backend.fill_rect(offset_bounds, primitive.color)
      when DrawRect
        offset_bounds = Rect.new(
          primitive.bounds.x + offset_x,
          primitive.bounds.y + offset_y,
          primitive.bounds.width,
          primitive.bounds.height
        )
        backend.draw_rect(offset_bounds, primitive.color, primitive.width)
      when DrawLine
        backend.draw_line(
          primitive.from.x + offset_x, primitive.from.y + offset_y,
          primitive.to.x + offset_x, primitive.to.y + offset_y,
          primitive.color, primitive.width
        )
      when DrawText
        offset_pos = Vec2.new(primitive.position.x + offset_x, primitive.position.y + offset_y)
        backend.draw_text(primitive.text, offset_pos, primitive.color, primitive.size)
      when DrawCircle
        backend.draw_circle(
          primitive.center.x + offset_x, primitive.center.y + offset_y,
          primitive.radius, primitive.color, primitive.fill
        )
      when FillTriangle
        offset_p1 = Vec2.new(primitive.p1.x + offset_x, primitive.p1.y + offset_y)
        offset_p2 = Vec2.new(primitive.p2.x + offset_x, primitive.p2.y + offset_y)
        offset_p3 = Vec2.new(primitive.p3.x + offset_x, primitive.p3.y + offset_y)
        backend.fill_triangle(offset_p1, offset_p2, offset_p3, primitive.color)
      when PushClip
        offset_rect = Rect.new(
          primitive.rect.x + offset_x,
          primitive.rect.y + offset_y,
          primitive.rect.width,
          primitive.rect.height
        )
        backend.push_clip(offset_rect)
      when PopClip
        backend.pop_clip
      end
    end

    # Collect all widgets recursively from a widget tree (for full render)
    # IMPORTANT: Stop recursion at layer boundaries - children of widgets with their own layer
    # should be rendered by that layer, not the parent layer
    # target_layer: the layer we're collecting widgets for (to detect layer boundaries)
    private def collect_all_widgets_recursive(widget : Widget, result : Array(Widget), target_layer : Layer)
      result << widget
      {% if flag?(:DEBUG_COLLECT) %}
        puts "  [COLLECT] #{widget.class.name.split("::").last}##{widget.path_id} to layer '#{target_layer.id}'"
      {% end %}

      # If THIS widget has its own layer that's DIFFERENT from target_layer,
      # don't recurse into its children - they belong to the widget's own layer
      if widget.responds_to?(:layer)
        if widget_layer = widget.layer
          if widget_layer != target_layer
            {% if flag?(:DEBUG_COLLECT) %}
              puts "    [STOP] widget has own layer '#{widget_layer.id}', not recursing children"
            {% end %}
            return # Widget has its own layer, children belong there
          end
        end
      end

      widget.children.each do |child|
        # Stop at layer boundary: if child has its own layer, don't recurse into its children
        # Layer-owning widgets handle their own rendering - don't add to parent's collection
        if child.responds_to?(:layer) && child.layer
          # Don't add layer-owning widget to parent layer
          # Don't recurse into children - they belong to the child's layer
        else
          collect_all_widgets_recursive(child, result, target_layer)
        end
      end
    end

    # Collect VISIBLE widgets recursively for viewport_cache layers
    # OPTIMIZATION: Early-exit when widget is completely outside viewport
    # This reduces iteration from O(total) to O(visible) for large scroll content
    private def collect_visible_widgets_recursive(widget : Widget, result : Array(Widget), target_layer : Layer, viewport : Rect)
      # Get widget bounds in absolute coordinates
      widget_bounds = widget.absolute_bounds

      # Early exit: if widget is completely outside viewport, skip it AND all children
      # This is the key optimization - we don't recurse into off-screen subtrees
      unless viewport_intersects?(viewport, widget_bounds)
        return
      end

      result << widget

      # If THIS widget has its own layer that's DIFFERENT from target_layer,
      # don't recurse into its children - they belong to the widget's own layer
      if widget.responds_to?(:layer)
        if widget_layer = widget.layer
          if widget_layer != target_layer
            return # Widget has its own layer, children belong there
          end
        end
      end

      widget.children.each do |child|
        # Stop at layer boundary: if child has its own layer, don't recurse into its children
        # Layer-owning widgets handle their own rendering - don't add to parent's collection
        if child.responds_to?(:layer) && child.layer
          # Don't add layer-owning widget to parent layer
          # Don't recurse into children - they belong to the child's layer
        else
          collect_visible_widgets_recursive(child, result, target_layer, viewport)
        end
      end
    end

    # Check if viewport intersects with widget bounds
    # Returns true if any part of the widget is visible in the viewport
    private def viewport_intersects?(viewport : Rect, bounds : Rect) : Bool
      # Widget is visible if NOT completely outside viewport
      # Using same logic as render_single_widget visibility check
      !(bounds.right <= viewport.left || # completely left of viewport
        bounds.left >= viewport.right || # completely right of viewport
        bounds.bottom <= viewport.top || # completely above viewport
        bounds.top >= viewport.bottom)   # completely below viewport
    end

    # Collect all layers from widget tree
    private def collect_layers(widget : Widget) : Array(Layer)
      layers = [] of Layer

      # Check if this widget has a layer
      if widget.responds_to?(:layer)
        if layer = widget.layer
          layers << layer
          # Recursively collect child layers
          layer.children.each do |child_layer|
            layers.concat(collect_layers_recursive(child_layer))
          end
        end
      end

      # Check for scrollbar_layer (ScrollView, ComboBox have separate scrollbar overlay)
      if widget.responds_to?(:scrollbar_layer)
        if scrollbar_layer = widget.scrollbar_layer
          layers << scrollbar_layer
        end
      end

      # Check children
      widget.children.each do |child|
        layers.concat(collect_layers(child))
      end

      # Check overlays (Window maintains separate overlay list for popups, etc.)
      # Overlays persist across DSL rebuilds and are auto-migrated
      if widget.responds_to?(:overlays)
        widget.overlays.each do |overlay|
          layers.concat(collect_layers(overlay))
        end
      end

      layers
    end

    # Recursively collect layers from layer tree
    private def collect_layers_recursive(layer : Layer) : Array(Layer)
      layers = [layer]
      layer.children.each do |child|
        layers.concat(collect_layers_recursive(child))
      end
      layers
    end

    # Collect widgets to render based on render mode (full vs selective)
    # UNIFIED RENDERING: Always use per-widget textures (NEW path only)
    private def collect_widgets_to_render(layer : Layer, full_render : Bool) : Array(Widget)
      if full_render
        # Full render: collect widgets recursively from layer.widgets
        all_widgets = [] of Widget

        # OPTIMIZATION: For viewport_cache layers, only collect VISIBLE widgets
        # This reduces iteration from O(total) to O(visible) - huge win for large scroll content
        # BUT: If layer.state is NeedsLayout, widget bounds may be stale (zero size), so skip culling
        if layer.viewport_cache && layer.state != WidgetState::NeedsLayout
          # Calculate viewport bounds in content coordinates
          # Viewport is at scroll_offset, with size layer.bounds.width/height
          viewport = Rect.new(
            layer.scroll_offset.x + layer.bounds.x, # Viewport left edge in content coords
            layer.scroll_offset.y + layer.bounds.y, # Viewport top edge in content coords
            layer.bounds.width,
            layer.bounds.height
          )
          layer.widgets.each do |widget|
            collect_visible_widgets_recursive(widget, all_widgets, layer, viewport)
          end
        else
          layer.widgets.each do |widget|
            collect_all_widgets_recursive(widget, all_widgets, layer)
          end
        end

        all_widgets
      else
        # Selective render: only dirty widgets, but MUST preserve parent-first order!
        # CRITICAL: If child renders before parent, it captures wrong (old) background
        # Solution: collect all widgets, filter to dirty, preserves parent-first order
        all_widgets = [] of Widget
        layer.widgets.each do |widget|
          collect_all_widgets_recursive(widget, all_widgets, layer)
        end
        # Filter to only dirty widgets (preserves parent-first order from collection)
        dirty_set = layer.dirty_widgets
        result = all_widgets.select { |w| dirty_set.includes?(w) }

        result
      end
    end

    # Validate sibling bounds don't overlap (invariant check)
    # INVARIANT (siblings no-overlap): Sibling widgets (same parent) must not have overlapping bounds
    # This simplifies per-widget background memorization (no z-ordering conflicts)
    #
    # IMPORTANT: Touching is allowed! Graphics use half-open intervals [left, right):
    #   Widget A at x=100, width=51 fills pixels [100, 151) = {100, 101, ..., 150}
    #   Widget B at x=151, width=51 fills pixels [151, 202) = {151, 152, ..., 201}
    #   No shared pixels! (see fill_rect implementation: uses (x1...x2) exclusive range)
    #
    # OPTIMIZATION: VStack/HStack are ordered containers - only adjacent siblings can overlap.
    # For these, we use O(n) instead of O(n²).
    private def validate_sibling_bounds(widgets : Array(Widget))
      # Group widgets by parent
      widgets_by_parent = {} of Widget? => Array(Widget)
      widgets.each do |widget|
        parent = widget.parent
        widgets_by_parent[parent] ||= [] of Widget
        widgets_by_parent[parent] << widget
      end

      # Check each group of siblings for overlaps
      widgets_by_parent.each do |parent, siblings|
        next if siblings.size < 2 # Need at least 2 siblings to overlap

        if parent.is_a?(VStack) || parent.is_a?(HStack)
          # O(n): Ordered containers - only check adjacent siblings
          siblings.each_cons(2) do |(widget_a, widget_b)|
            check_sibling_overlap(widget_a, widget_b, parent)
          end
        else
          # O(n²): General case - check all pairs
          siblings.each_with_index do |widget_a, i|
            siblings[(i + 1)..-1].each do |widget_b|
              check_sibling_overlap(widget_a, widget_b, parent)
            end
          end
        end
      end
    end

    # Check if two sibling widgets overlap (helper for validate_sibling_bounds)
    private def check_sibling_overlap(widget_a : Widget, widget_b : Widget, parent : Widget?)
      bounds_a = widget_a.absolute_bounds
      bounds_b = widget_b.absolute_bounds

      # Check for overlap (sharing interior pixels, not just touching)
      # Touching at boundaries is OK - we only fail if they share interior pixels
      # Use epsilon tolerance for floating point comparisons (scrollbar drag can cause tiny FP errors)
      epsilon = 0.01
      overlaps = bounds_a.right - bounds_b.left > epsilon &&
                 bounds_b.right - bounds_a.left > epsilon &&
                 bounds_a.bottom - bounds_b.top > epsilon &&
                 bounds_b.bottom - bounds_a.top > epsilon

      assert(!overlaps,
        "(siblings no-overlap): #{widget_a.class.name.split("::").last}##{widget_a.path_id} at #{bounds_a} overlaps " +
        "#{widget_b.class.name.split("::").last}##{widget_b.path_id} at #{bounds_b} " +
        "(parent: #{parent ? parent.class.name.split("::").last + "#" + parent.path_id : "nil"})")
    end

    # Handle viewport_cache buffer scroll: check if viewport moved beyond cached region
    # Returns true if buffer was recentered and needs full render of visible widgets
    #
    # Design (Hybrid approach):
    # - Buffer = viewport + 2×cache_extent (margin on each side)
    # - Small scroll (within cache_extent): Just move viewport, no re-render needed
    # - Large scroll (beyond buffer bounds): Recenter buffer, full re-render
    #
    # The viewport position within buffer = scroll_offset - buffer_origin
    # Valid range: [0, 0] to [buffer_width - viewport_width, buffer_height - viewport_height]
    private def handle_viewport_cache_scroll(layer : Layer, backend : RenderBackend) : Bool
      # Calculate where viewport should be positioned within the buffer
      viewport_in_buffer_x = layer.scroll_offset.x - layer.buffer_origin.x
      viewport_in_buffer_y = layer.scroll_offset.y - layer.buffer_origin.y

      # Buffer and viewport dimensions
      buffer_width = backend.width.to_f64
      buffer_height = backend.height.to_f64
      viewport_width = layer.bounds.width
      viewport_height = layer.bounds.height

      # Valid range for viewport position in buffer (must fit entirely within buffer)
      max_valid_x = buffer_width - viewport_width
      max_valid_y = buffer_height - viewport_height

      # Check if viewport is still within the cached buffer region
      # Small tolerance for floating point errors
      epsilon = 0.5
      if viewport_in_buffer_x >= -epsilon && viewport_in_buffer_x <= max_valid_x + epsilon &&
         viewport_in_buffer_y >= -epsilon && viewport_in_buffer_y <= max_valid_y + epsilon
        # Fast path: viewport still within buffer, no action needed
        return false
      end

      # Viewport moved outside buffer bounds - need to recenter buffer
      # Clear buffer and reset buffer_origin so viewport is centered in buffer
      {% if flag?(:DEBUG_RENDER) %}
        puts "  [VIEWPORT_CACHE RECENTER] viewport_in_buffer=(#{viewport_in_buffer_x}, #{viewport_in_buffer_y})"
        puts "    max_valid=(#{max_valid_x}, #{max_valid_y})"
        puts "    Recentering buffer_origin from #{layer.buffer_origin} to scroll_offset - cache_extent"
      {% end %}

      backend.clear(layer.background_color)
      layer.buffer_origin = layer.scroll_offset - Vec2.new(layer.cache_extent, layer.cache_extent)

      # Mark buffer as just cleared - widgets should NOT capture from stale texture
      # They should fill with background_color instead (texture won't reflect clear until display())
      layer.buffer_just_cleared = true

      # Clear widget_backend for ALL widgets in content tree so they fully re-render
      # Without this, the fast path (lines 468-479) would blit OLD cached content
      # at NEW buffer positions after buffer_origin changes → shifted garbling bug.
      if scroll_view = layer.owner_widget.as?(ScrollView)
        scroll_view.clear_all_widget_backends
      end

      true # Signal that full render is needed
    end
  end
end

# Flush profile data on exit
at_exit do
  CrymbleUI::LayerRenderer.flush_profile_data
end
