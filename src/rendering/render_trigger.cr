require "../core/app"
require "../core/layer"

module CrymbleUI
  # The version-keyed PULL decision "should the loop render this frame?", extracted from the SFML
  # run-loop so it is ONE headless-callable seam shared by SFMLRenderer (the live loop) and
  # TestRenderer#render_frame_if_needed (specs). It answers purely from app/version state: render iff
  # the frame aggregate moved since the last render.
  #
  # NOT here: the raw SFML event-type forcing (mouse/key/resize always redraw) — that is the windowed
  # adapter's concern, not part of the pull decision whose COMPLETENESS we want to prove in specs.
  #
  # The `|| Layer.any_needs_render?` dirty-walk backstop is GONE — the trigger is now PURE
  # version-keyed pull. Every input it used to catch moves the aggregate: widget content/layout (node
  # primitives_version via touch), scroll (scroll_rev), composite position (position_rev), buffer clear
  # (clear_rev), a bare layer-level dirty-mark — mark_needs_render/full_render/layout (render_rev, the
  # completeness token that closed the last hole: those set @state but no other rev); structural/first-
  # render come via the rebuild trigger. Proven complete by the backstop-off probe + the per-axis
  # render_frame_if_needed completeness specs.
  class RenderTrigger
    @last_aggregate : UInt64 = 0

    # Would the loop render a frame now, by the pull decision?
    def should_render?(app : App) : Bool
      return false unless root = app.root
      Layer.frame_aggregate_rev(root) != @last_aggregate
    end

    # Stamp the baseline after a render, so an unchanged next frame idles until the aggregate moves.
    def record(app : App) : Nil
      if root = app.root
        @last_aggregate = Layer.frame_aggregate_rev(root)
      end
    end
  end
end
