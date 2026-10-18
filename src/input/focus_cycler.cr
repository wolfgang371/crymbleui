require "../core/widget"
require "../core/types"

module CrymbleUI
  # Handles Tab/Shift-Tab focus cycling
  # Order: top-to-bottom, left-to-right (reading order)
  class FocusCycler
    # The Tab stops of `scope` - focusable, enabled, shown - in reading order: (y, x). A WindowPanel is a wall for
    # every walk but its own: from a panel Tab never leaves it, from the window body it never enters one.
    def collect_focusable_widgets(scope : Widget) : Array(Widget)
      focusables = [] of Widget
      collect_recursive(scope, scope, focusables)

      # Sort by reading order: primary Y (top-to-bottom), secondary X (left-to-right).
      # PAINTED position, not laid-out: "reading order" is what the user sees, and widgets on
      # either side of a scrolled view are only comparable once both are in window space.
      focusables.sort_by! do |widget|
        bounds = widget.viewport_bounds
        # Use integers for stable sorting (avoid float precision issues)
        {bounds.y.to_i, bounds.x.to_i}
      end

      focusables
    end

    # Find next widget in tab order
    # Returns nil if focusables is empty
    def find_next(
      current : Widget?,
      focusables : Array(Widget),
      forward : Bool
    ) : Widget?
      return focusables.first? if current.nil?
      return nil if focusables.empty?

      current_index = focusables.index(current)
      return focusables.first? if current_index.nil?

      if forward
        next_index = (current_index + 1) % focusables.size
      else
        next_index = (current_index - 1 + focusables.size) % focusables.size
      end

      focusables[next_index]
    end

    private def collect_recursive(widget : Widget, scope : Widget, result : Array(Widget))
      return if widget.is_a?(WindowPanel) && !widget.same?(scope)
      result << widget if widget.focusable? && widget.enabled?

      # Don't recurse into focus scope widgets (e.g., VirtualMatrix)
      # Their children are managed internally, not part of the tab order
      return if widget.is_focus_scope?

      widget.shown_children.each do |child|
        collect_recursive(child, scope, result)
      end
    end
  end
end
