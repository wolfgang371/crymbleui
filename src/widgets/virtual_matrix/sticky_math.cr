module CrymbleUI::Widgets::VirtualMatrix
  # Pure math functions for sticky header behavior.
  module StickyMath
    # Returns the min scroll position (in pixels) such that element `index` is barely fully visible.
    # The left/upper border of the element is on the left/upper side of the window.
    def self.visibility_range_min(index : Int32, sizes_pixel : Array(Int32), scroll_order : Array(Int32)) : Int32
      num_shifted_2_scrolled_pixel_min = scroll_order.map { |el| sizes_pixel[el] }.accumulate { |x, y| x + y }
      i = scroll_order.index(index).not_nil!
      num_shifted_2_scrolled_pixel_min[i] - sizes_pixel[index]
    end

    # Returns the max scroll position (in pixels) such that element `index` is barely fully visible.
    # The right/lower border of the element is on the right/lower side of the window.
    # Returns 0 if no scrolling is needed.
    def self.visibility_range_max(index : Int32, sizes_pixel : Array(Int32), scroll_order : Array(Int32), window_pixel : Int32) : Int32
      num_shifted_2_scrolled_pixel_max = sizes_pixel.accumulate { |x, y| x + y }
      max_pos = num_shifted_2_scrolled_pixel_max[index] - window_pixel
      {max_pos, 0}.max
    end

    # Computes mapping from cell indices to first visible cell and visibility counts.
    # Returns: {nums, firsts}
    # - nums[i]: count of visible elements <= i (has length num+1, with leading 0)
    # - firsts[i]: first visible element >= i (or -1 if none)
    def self.calc_visibles(num : Int32, indices_with_beyond : Set(Int32)) : {Array(Int32), Array(Int32)}
      nums = ([0] + (0...num).map { |i| indices_with_beyond.includes?(i) ? 1 : 0 })
        .accumulate { |a, el| a + el }
      indices_array = indices_with_beyond.to_a.sort
      firsts = (nums[0...-1]).map { |el| indices_array[el]? || -1 }
      {nums, firsts}
    end

    # Main sticky algorithm that computes visible indices given scroll state.
    # This has linear runtime.
    #
    # Arguments:
    # - sizes_pixel: size per element (column/row) in pixels, includes spacing
    # - scroll_order: indices in order they scroll out (first = scrolls out first)
    # - min_pos_pixel: left/top position of the viewport
    # - max_pos_pixel: right/bottom position of the viewport
    #
    # Returns:
    # - offset: total pixel offset of shifted-out elements
    # - positions: Hash mapping visible index → pixel position
    # - shifting_index: the (global) index of the currently shifting element
    # - indices: which rows/cols are visible (paint order)
    # - indices_with_beyond: visible indices including those just beyond viewport
    def self.sticky(sizes_pixel : Array(Int32), scroll_order : Array(Int32), min_pos_pixel : Int32, max_pos_pixel : Int32) : {Int32, Hash(Int32, Int32), Int32, Array(Int32), Set(Int32)}
      raise ArgumentError.new("sizes_pixel and scroll_order must have same size") unless sizes_pixel.size == scroll_order.size

      num_shifted_2_scrolled_pixel = scroll_order.map { |el| sizes_pixel[el] }.accumulate { |x, y| x + y }

      # How many elements are already fully shifted out
      num_shifted = num_shifted_2_scrolled_pixel.bsearch_index { |p| p >= min_pos_pixel } || scroll_order.size

      indices = (0...sizes_pixel.size).to_set
      offset = 0
      shifting_index = scroll_order[num_shifted]? || scroll_order.last

      num_shifted.times do |i|
        el = scroll_order[i]
        indices.delete(el) # All those are already fully shifted out
        offset += sizes_pixel[el]
      end

      indices_with_beyond = indices.dup

      indices_array = indices.to_a.sort

      # Build positions hash: index -> accumulated pixel position
      positions = Hash(Int32, Int32).new
      accumulated = 0
      indices_array.each do |idx|
        positions[idx] = accumulated
        accumulated += sizes_pixel[idx]
      end
      positions[-1] = accumulated # Dummy element at end

      {offset, positions, shifting_index, indices_array, indices_with_beyond}
    end

    # Fast viewport sticky — O(V + S·log S) replacement for O(N) sticky().
    #
    # Algorithm overview:
    #   Given a scroll_order (physical indices reordered so sticky headers come first),
    #   a scroll position determines how many elements are "shifted out" (scrolled past).
    #   Shifted-out elements leave gaps in the physical layout. This function computes
    #   screen-space positions for visible elements by subtracting the cumulative size
    #   of shifted elements that precede each visible element in physical order.
    #
    # Steps:
    #   1. offset = cumulative[num_shifted-1]: total pixels shifted out (O(1) lookup)
    #   2. shifting_index = scroll_order[num_shifted]: the partially-visible edge element
    #   3. sorted_shifted: sort shifted indices for binary search (O(S·log S))
    #   4. shifted_prefix: prefix sums of shifted element sizes for position adjustment
    #   5. Physical range [first_idx..last_idx]: binary search on physical_cum (O(log N))
    #   6. visible = sticky indices (always visible) + physical range - shifted (O(V))
    #   7. positions[idx] = physical_cum[idx] - shifted_prefix[bsearch(idx)] (O(V·log S))
    #
    # Complexity: O(V + S·log S + log N) where V=visible count, S=shifted count, N=total
    #
    # Parameters:
    #   sizes_pixel    - pixel size of each element (indexed by physical index)
    #   scroll_order   - indices in scroll order (sticky first, then scrollable)
    #   num_shifted    - how many scroll_order elements are fully scrolled past
    #   cumulative     - prefix sums of sizes in scroll_order (for offset lookup)
    #   physical_cum   - prefix sums of sizes in physical order (for bsearch)
    #   min/max_pos_pixel - viewport bounds in content-space pixels
    #   sticky_count   - number of sticky (pinned) elements
    #
    # Returns: {offset, positions, shifting_index, visible_indices, sorted_shifted}
    def self.sticky_fast(
        sizes_pixel : Array(Int32),
        scroll_order : Array(Int32),
        num_shifted : Int32,
        cumulative : Array(Int32),
        physical_cum : Array(Int32),
        min_pos_pixel : Int32,
        max_pos_pixel : Int32,
        sticky_count : Int32
    ) : {Int32, Hash(Int32, Int32), Int32, Array(Int32), Array(Int32)}
      n = sizes_pixel.size

      # offset — O(1) from pre-computed cumulative
      offset = num_shifted > 0 ? cumulative[num_shifted - 1] : 0

      # shifting_index — O(1)
      shifting_index = scroll_order[num_shifted]? || scroll_order.last

      # Build sorted shifted indices — O(S log S)
      sorted_shifted = Array(Int32).new(num_shifted)
      num_shifted.times { |i| sorted_shifted << scroll_order[i] }
      sorted_shifted.sort!

      # Build shifted set for O(1) lookup and prefix sums for positions — O(S)
      shifted_set = sorted_shifted.to_set
      shifted_prefix = Array(Int32).new(sorted_shifted.size + 1, 0)
      sorted_shifted.each_with_index do |s, i|
        shifted_prefix[i + 1] = shifted_prefix[i] + sizes_pixel[s]
      end

      # Find visible physical range via bsearch — O(log N)
      first_phys = physical_cum.bsearch_index { |p| p > min_pos_pixel }
      first_idx = first_phys ? {first_phys - 1, 0}.max : n
      last_phys = physical_cum.bsearch_index { |p| p > max_pos_pixel }
      last_idx = last_phys ? {last_phys - 1, n - 1}.min : n - 1

      # Collect visible indices: sticky (always) + physical range — O(V + sticky_count)
      visible = Array(Int32).new
      (0...{sticky_count, n}.min).each do |idx|
        visible << idx unless shifted_set.includes?(idx)
      end
      ({first_idx, sticky_count}.max..last_idx).each do |idx|
        visible << idx unless shifted_set.includes?(idx)
      end

      # Build positions for visible indices only — O(V × log S)
      # positions[idx] = physical_cum[idx] - sum(sizes[s] for s in shifted where s < idx)
      positions = Hash(Int32, Int32).new
      visible.each do |idx|
        k = sorted_shifted.bsearch_index { |s| s >= idx } || sorted_shifted.size
        positions[idx] = physical_cum[idx] - shifted_prefix[k]
      end
      positions[-1] = physical_cum[n] - offset # Sentinel

      {offset, positions, shifting_index, visible, sorted_shifted}
    end

    # Returns visible (non-shifted) indices in a physical range — O(V + S + log N).
    # For creation/destruction regions that only need the index list, not positions.
    def self.visible_indices_in_range(
        physical_cum : Array(Int32),
        scroll_order : Array(Int32),
        num_shifted : Int32,
        min_pos : Int32,
        max_pos : Int32,
        sticky_count : Int32
    ) : Array(Int32)
      n = physical_cum.size - 1

      # Build shifted set — O(S)
      shifted_set = Set(Int32).new(num_shifted)
      num_shifted.times { |i| shifted_set << scroll_order[i] }

      # Find physical range via bsearch — O(log N)
      first_phys = physical_cum.bsearch_index { |p| p > min_pos }
      first_idx = first_phys ? {first_phys - 1, 0}.max : n
      last_phys = physical_cum.bsearch_index { |p| p > max_pos }
      last_idx = last_phys ? {last_phys - 1, n - 1}.min : n - 1

      # Collect: sticky indices + physical range — O(V + sticky_count)
      result = Array(Int32).new
      (0...{sticky_count, n}.min).each do |idx|
        result << idx unless shifted_set.includes?(idx)
      end
      ({first_idx, sticky_count}.max..last_idx).each do |idx|
        result << idx unless shifted_set.includes?(idx)
      end
      result
    end

    # Returns first non-shifted index >= idx, or -1 if none — O(log S + consecutive).
    # Replaces the O(N) calc_visibles firsts array with on-demand lookup.
    def self.first_visible_at_or_after(idx : Int32, sorted_shifted : Array(Int32), n : Int32) : Int32
      return -1 if idx >= n
      pos = sorted_shifted.bsearch_index { |s| s >= idx } || sorted_shifted.size
      current = idx
      while pos < sorted_shifted.size && sorted_shifted[pos] == current
        current += 1
        pos += 1
      end
      current < n ? current : -1
    end
  end
end

# Extension to Array for cumulative (running-sum) operations.
class Array(T)
  # Cumulative fold: returns array where each element is the running aggregate.
  # [1,2,3].accumulate { |a,b| a+b } => [1, 3, 6]
  def accumulate(&block : T, T -> T) : Array(T)
    return [] of T if empty?
    result = Array(T).new(size)
    result << first
    (1...size).each do |i|
      result << yield(result.last, self[i])
    end
    result
  end

  # Cumulative fold with initial value: returns array with initial + running aggregates.
  # [1,2,3].accumulate(0) { |a,b| a+b } => [0, 1, 3, 6]
  def accumulate(initial : T, &block : T, T -> T) : Array(T)
    result = Array(T).new(size + 1)
    result << initial
    each do |el|
      result << yield(result.last, el)
    end
    result
  end
end
