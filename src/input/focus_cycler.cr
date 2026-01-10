require "../core/widget"
require "../core/types"

module CrymbleUI
  # Handles Tab/Shift-Tab focus cycling
  # Order: top-to-bottom, left-to-right (reading order)
  class FocusCycler
    # Collect all focusable widgets in tab order
    # Returns widgets sorted by reading order: (y, x)
    def collect_focusable_widgets(root : Widget) : Array(Widget)
      focusables = [] of Widget
      collect_recursive(root, focusables)

      # Sort by reading order: primary Y (top-to-bottom), secondary X (left-to-right)
      focusables.sort_by! do |widget|
        bounds = widget.absolute_bounds
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

    private def collect_recursive(widget : Widget, result : Array(Widget))
      # Add widget if focusable
      result << widget if widget.focusable?

      # Recurse into children
      widget.children.each do |child|
        collect_recursive(child, result)
      end
    end
  end
end
