require "../core/widget"
require "../core/types"

module CrymbleUI
  # Spatial navigation algorithm for arrow key focus movement
  # Uses geometric analysis to find the "best" widget in a given direction
  #
  # Algorithm:
  # 1. Filter widgets that are in the correct direction
  # 2. Score candidates based on:
  #    - Alignment (prefer same row/column - widgets with overlapping primary axis)
  #    - Distance (prefer closer widgets)
  # 3. Return widget with best (lowest) score
  #
  # Container containment:
  # - Arrow keys are restricted based on ScrollView direction:
  #   - Vertical ScrollView: only up/down allowed
  #   - Horizontal ScrollView: only left/right allowed
  #   - Both ScrollView: all directions allowed
  # - Navigation at boundaries returns nil (focus stays on current widget)
  class FocusNavigator
    # Find the best neighbor widget in the given direction
    # Returns nil if no suitable neighbor found
    def find_neighbor(
      current : Widget,
      candidates : Array(Widget),
      direction : Symbol
    ) : Widget?
      # Check for explicit override first
      if override = current.focus_override
        target_id = case direction
                    when :up    then override.up
                    when :down  then override.down
                    when :left  then override.left
                    when :right then override.right
                    else nil
                    end
        if target_id
          # Find widget with matching ID
          target = candidates.find { |w| w.id == target_id }
          return target if target
        end
      end

      # Check if current widget is inside a ScrollView
      current_scroll = find_scroll_ancestor(current)

      if current_scroll
        # Block perpendicular navigation based on scroll direction
        scroll_dir = get_scroll_direction(current_scroll)
        return nil unless direction_allowed?(scroll_dir, direction)

        # Only search within same ScrollView - no fallback to other panels
        same_scroll_candidates = candidates.select { |w| find_scroll_ancestor(w) == current_scroll }
        return find_neighbor_spatial(current, same_scroll_candidates, direction)
      end

      # Not in ScrollView - search all candidates
      find_neighbor_spatial(current, candidates, direction)
    end

    # Find ScrollView ancestor of a widget (uses duck typing to avoid circular dependency)
    # Returns the ScrollView widget, or nil if not inside one
    private def find_scroll_ancestor(widget : Widget) : Widget?
      current = widget.parent
      while current
        # Check by class name to avoid circular dependency with ScrollView
        return current if current.class.name == "CrymbleUI::ScrollView"
        current = current.parent
      end
      nil
    end

    # Get scroll direction from a ScrollView widget (duck typing)
    private def get_scroll_direction(scroll_view : Widget) : Symbol
      if scroll_view.responds_to?(:direction)
        case scroll_view.direction.to_s
        when "Vertical"   then :vertical
        when "Horizontal" then :horizontal
        when "Both"       then :both
        else :both
        end
      else
        :both  # Default to allowing all directions if direction method not found
      end
    end

    # Check if navigation direction is allowed for the given scroll direction
    private def direction_allowed?(scroll_dir : Symbol, nav_dir : Symbol) : Bool
      case scroll_dir
      when :vertical
        nav_dir == :up || nav_dir == :down
      when :horizontal
        nav_dir == :left || nav_dir == :right
      when :both
        true
      else
        true
      end
    end

    # Core spatial navigation algorithm
    private def find_neighbor_spatial(
      current : Widget,
      candidates : Array(Widget),
      direction : Symbol
    ) : Widget?
      current_bounds = current.absolute_bounds
      current_center = bounds_center(current_bounds)

      # Filter out current widget and find widgets in the correct direction
      valid_candidates = candidates.reject { |w| w == current }

      in_direction = valid_candidates.select do |candidate|
        candidate_bounds = candidate.absolute_bounds
        candidate_center = bounds_center(candidate_bounds)
        in_direction?(current_center, candidate_center, current_bounds, candidate_bounds, direction)
      end

      return nil if in_direction.empty?

      # Score and sort candidates - lower score is better
      scored = in_direction.map do |candidate|
        score = calculate_navigation_score(current_bounds, candidate.absolute_bounds, direction)
        {candidate, score}
      end

      # Return candidate with best (lowest) score
      best = scored.min_by { |pair| pair[1] }
      best[0]
    end

    private def bounds_center(rect : Rect) : Vec2
      Vec2.new(rect.x + rect.width / 2.0, rect.y + rect.height / 2.0)
    end

    # Minimum distance threshold to count as "in direction"
    # Prevents floating-point layout errors from creating false positives
    # (e.g., two widgets in the same column differing by 0.0001 pixels)
    DIRECTION_THRESHOLD = 1.0

    # Check if target is in the given direction from source
    # Requires at least DIRECTION_THRESHOLD pixels difference AND:
    # - For left/right: requires vertical overlap (same row)
    # - For up/down: requires horizontal overlap (same column)
    private def in_direction?(
      source : Vec2,
      target : Vec2,
      source_bounds : Rect,
      target_bounds : Rect,
      direction : Symbol
    ) : Bool
      case direction
      when :up
        target.y < source.y - DIRECTION_THRESHOLD &&
          horizontal_overlap?(source_bounds, target_bounds)
      when :down
        target.y > source.y + DIRECTION_THRESHOLD &&
          horizontal_overlap?(source_bounds, target_bounds)
      when :left
        target.x < source.x - DIRECTION_THRESHOLD &&
          vertical_overlap?(source_bounds, target_bounds)
      when :right
        target.x > source.x + DIRECTION_THRESHOLD &&
          vertical_overlap?(source_bounds, target_bounds)
      else
        false
      end
    end

    # Check if two rects have vertical overlap (same row)
    private def vertical_overlap?(a : Rect, b : Rect) : Bool
      a.y < b.y + b.height && a.y + a.height > b.y
    end

    # Check if two rects have horizontal overlap (same column)
    private def horizontal_overlap?(a : Rect, b : Rect) : Bool
      a.x < b.x + b.width && a.x + a.width > b.x
    end

    # Calculate navigation score (lower = better)
    # Considers: distance and alignment (overlap on secondary axis)
    private def calculate_navigation_score(
      current : Rect,
      target : Rect,
      direction : Symbol
    ) : Float64
      current_center = bounds_center(current)
      target_center = bounds_center(target)

      # Primary axis distance (in direction of movement)
      primary_distance = case direction
      when :up, :down
        (target_center.y - current_center.y).abs
      when :left, :right
        (target_center.x - current_center.x).abs
      else
        0.0
      end

      # Secondary axis offset (perpendicular to movement)
      # Heavily penalize widgets that are not aligned
      secondary_offset = case direction
      when :up, :down
        # Check horizontal overlap
        horizontal_overlap = calculate_overlap(
          current.x, current.x + current.width,
          target.x, target.x + target.width
        )
        if horizontal_overlap > 0.0
          # Overlapping widgets get small bonus based on how close centers are
          (target_center.x - current_center.x).abs * 0.1
        else
          # Non-overlapping widgets get heavy penalty
          (target_center.x - current_center.x).abs * 3.0
        end
      when :left, :right
        # Check vertical overlap
        vertical_overlap = calculate_overlap(
          current.y, current.y + current.height,
          target.y, target.y + target.height
        )
        if vertical_overlap > 0.0
          (target_center.y - current_center.y).abs * 0.1
        else
          (target_center.y - current_center.y).abs * 3.0
        end
      else
        0.0
      end

      # Combined score: primary distance + secondary offset penalty
      primary_distance + secondary_offset
    end

    # Calculate overlap between two ranges [a1, a2] and [b1, b2]
    private def calculate_overlap(a1 : Float64, a2 : Float64, b1 : Float64, b2 : Float64) : Float64
      overlap_start = Math.max(a1, b1)
      overlap_end = Math.min(a2, b2)
      Math.max(0.0, overlap_end - overlap_start)
    end
  end
end
