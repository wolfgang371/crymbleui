require "../core/layer"
require "../core/widget"
require "./test_renderer"

module CrymbleUI
  module Testing
    # Leak oracle for render surfaces.
    #
    # A surface is LEAKED iff it is undisposed AND the live tree can no longer reach it. Counting
    # undisposed surfaces cannot express that — the live generation is legitimately undisposed, and
    # it grows with how much is on screen, so any absolute bound is either slack or wrong. Under
    # SFML an unreachable surface is a driver-side RenderTexture the collector cannot reclaim, so
    # "unreachable but unreleased" is exactly the shape of an unbounded process.
    #
    # Scope the question with TestRenderBackend.census_start / census_take, then pass the census
    # here: the answer is about the surfaces that interaction created, not the whole process.
    module SurfaceLeaks
      # Censused surfaces that survive unreleased with nothing left to reach them. `app` adds what only the App
      # owns - the drag's ghost and highlight layers - for a question asked mid-drag.
      def self.stranded(root : Widget,
                        renderer : TestRenderer,
                        created : Enumerable(TestRenderBackend),
                        app : App? = nil) : Array(TestRenderBackend)
        live = reachable(root, renderer, app)
        created.reject { |surface| surface.disposed? || live.includes?(surface.object_id) }
      end

      # The other direction of the same invariant: surfaces the live tree still reaches that were RELEASED -
      # the next draw would read freed memory. Empty unless a release reached too far.
      def self.disposed_live(root : Widget, renderer : TestRenderer, app : App? = nil) : Array(RenderBackend)
        owned(root, renderer, app).select(&.disposed?)
      end

      # Everything still legitimately owned: widgets via @children from the root, the window's overlays,
      # widgets standing on an active layer (plus their subtrees), the layers' own surfaces, the drag's layers
      # (given the app), and the RENDERER's window buffer.
      #
      # That last one is not pedantry — it was a false positive the first time this was measured,
      # reported as a stranded window-sized texture. The renderer owns its window buffer directly
      # and no walk of the widget tree will ever find it. Deliberately NOT included: TestRenderer's
      # @layer_backends / @widget_backends registries, which are append-only by design and would
      # mask real leaks by declaring every backend ever made "reachable".
      def self.reachable(root : Widget, renderer : TestRenderer, app : App? = nil) : Set(UInt64)
        owned(root, renderer, app).map(&.object_id).to_set
      end

      private def self.owned(root : Widget, renderer : TestRenderer, app : App?) : Array(RenderBackend)
        live = [renderer.backend.as(RenderBackend)]
        collect_owned(root, live)
        root.as?(Window).try(&.overlays.each { |overlay| collect_owned(overlay, live) })

        drag = app.try { |a| [a.drag_manager.ghost_layer, a.drag_manager.highlight_layer].compact } || [] of Layer
        (Layer.active_layers(root) + drag).each do |layer|
          layer.backend.try { |backend| live << backend }
          # Membership in layer.widgets does NOT confer reachability. A widget can sit in a live
          # layer's list while its parent chain no longer reaches the root — that is exactly the
          # orphan the sweep is meant to drop, and counting it as reachable would whitelist the
          # leak this oracle exists to catch. The drag's own layers hold widgets no tree reaches.
          layer.widgets.each { |widget| collect_owned(widget, live) if drag.includes?(layer) || reaches_root?(widget, root) }
        end
        live
      end

      private def self.collect_owned(widget : Widget, live : Array(RenderBackend)) : Nil
        widget.widget_backend.try { |backend| live << backend }
        widget.background_backend.try { |backend| live << backend }
        widget.children.each { |child| collect_owned(child, live) }
      end

      # The same criterion Layer's orphan sweeps use: walk UP to the root.
      private def self.reaches_root?(widget : Widget, root : Widget) : Bool
        current : Widget? = widget
        while current
          return true if current == root
          current = current.parent
        end
        false
      end
    end
  end
end
