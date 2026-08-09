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
      # Censused surfaces that survive unreleased with nothing left to reach them.
      def self.stranded(root : Widget,
                        renderer : TestRenderer,
                        created : Enumerable(TestRenderBackend)) : Array(TestRenderBackend)
        live = reachable(root, renderer)
        created.reject { |surface| surface.disposed? || live.includes?(surface.object_id) }
      end

      # Everything still legitimately owned: widgets via @children from the root, widgets standing
      # on an active layer (plus their subtrees), the layers' own surfaces, and the RENDERER's
      # window buffer.
      #
      # That last one is not pedantry — it was a false positive the first time this was measured,
      # reported as a stranded window-sized texture. The renderer owns its window buffer directly
      # and no walk of the widget tree will ever find it. Deliberately NOT included: TestRenderer's
      # @layer_backends / @widget_backends registries, which are append-only by design and would
      # mask real leaks by declaring every backend ever made "reachable".
      def self.reachable(root : Widget, renderer : TestRenderer) : Set(UInt64)
        live = Set(UInt64).new
        live << renderer.backend.object_id
        collect_owned(root, live)

        Layer.active_layers(root).each do |layer|
          layer.backend.try { |backend| live << backend.object_id }
          # Membership in layer.widgets does NOT confer reachability. A widget can sit in a live
          # layer's list while its parent chain no longer reaches the root — that is exactly the
          # orphan the sweep is meant to drop, and counting it as reachable would whitelist the
          # leak this oracle exists to catch.
          layer.widgets.each { |widget| collect_owned(widget, live) if reaches_root?(widget, root) }
        end
        live
      end

      private def self.collect_owned(widget : Widget, live : Set(UInt64)) : Nil
        widget.widget_backend.try { |backend| live << backend.object_id }
        widget.background_backend.try { |backend| live << backend.object_id }
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
