module CrymbleUI::Widgets::VirtualMatrix
  # Pure math functions for sticky header behavior.
  module StickyMath
    # Perf instrumentation: counts cells examined that scale with the *shifted*
    # (scrolled-out) set, the work that must stay O(visible) and never O(num_shifted).
    # Per-call (cheap, always-on like @@update_visible_cells_call_count); specs reset + assert.
    @@work : Int64 = 0_i64

    def self.work : Int64
      @@work
    end

    def self.reset_work : Nil
      @@work = 0_i64
    end

    # O(1) "is physical index `idx` scrolled out?" — replaces the O(num_shifted)
    # sorted_shifted / shifted_set construction that made every scroll update scale with the
    # scrolled-out prefix (≈ grid size at far scroll). `scroll_rank` is the inverse of
    # scroll_order (`scroll_rank[physical]` = that cell's position in scroll order), built once
    # per resize; a cell is shifted iff it scrolls out before the seam — its scroll-order
    # position precedes `num_shifted`.
    #
    # There is deliberately NO assumption that shifted cells form a contiguous physical
    # prefix: grouped / pivot headers stay pinned while their data (physically *after* them)
    # scrolls out, so shifted cells are interleaved with visible ones. Membership therefore
    # must be tested per cell — but in O(1), over only the visible window.
    struct ShiftedSet
      getter num_shifted : Int32

      def initialize(@scroll_rank : Array(Int32), @num_shifted : Int32)
      end

      def includes?(idx : Int32) : Bool
        @scroll_rank[idx] < @num_shifted
      end
    end

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

    # Fast viewport sticky — O(V + log N), independent of how far you've scrolled.
    #
    # A scroll position determines how many elements are "shifted out" (`num_shifted`, an
    # O(log N) bsearch). The naive approach materialises that whole scrolled-out set to answer
    # "is cell X shifted?" and to prefix-sum positions — O(num_shifted) per update, which at a
    # far thumb-drag approaches the grid size and freezes the UI. Instead we test membership in
    # O(1) via `ShiftedSet` (cached inverse permutation) and compute positions by walking ONLY
    # the visible physical window `[first_idx..last_idx]`, accumulating the shifted-size prefix
    # as we pass interior holes (a grouped/pivot header pins while its data scrolls out, so
    # shifted cells are interleaved — there is no contiguous-prefix shortcut).
    #
    # The one fact that makes the position base recoverable without scanning the prefix is the
    # weak seam invariant: nothing scrolled out lives physically past the viewport bottom
    # (top-down scroll cannot have passed a cell below it). So the shifted size *before* the
    # window = `offset − (shifted size within the window)`. Asserted under -Dverify_bounds.
    #
    # Parameters: sizes_pixel; scroll_order (only for the shifting edge); scroll_rank (the
    # inverse permutation, for O(1) membership); num_shifted; cumulative (offset lookup);
    # physical_cum; viewport bounds; sticky_count.
    # Returns: {offset, positions, shifting_index, visible_indices, shifted : ShiftedSet}
    def self.sticky_fast(
        sizes_pixel : Array(Int32),
        scroll_order : Array(Int32),
        scroll_rank : Array(Int32),
        num_shifted : Int32,
        cumulative : Array(Int32),
        physical_cum : Array(Int32),
        min_pos_pixel : Int32,
        max_pos_pixel : Int32,
        sticky_count : Int32
    ) : {Int32, Hash(Int32, Int32), Int32, Array(Int32), ShiftedSet}
      n = sizes_pixel.size

      # Degenerate axis (0 rows or 0 columns): nothing to place, nothing sticky.
      # Without this guard `scroll_order.last` (below) raises on the empty array.
      return {0, Hash(Int32, Int32).new, 0, [] of Int32, ShiftedSet.new(scroll_rank, 0)} if scroll_order.empty?

      offset = num_shifted > 0 ? cumulative[num_shifted - 1] : 0        # O(1)
      shifting_index = scroll_order[num_shifted]? || scroll_order.last  # O(1) — the seam edge
      shifted = ShiftedSet.new(scroll_rank, num_shifted)

      # Visible physical range — O(log N)
      first_phys = physical_cum.bsearch_index { |p| p > min_pos_pixel }
      first_idx = first_phys ? {first_phys - 1, 0}.max : n
      last_phys = physical_cum.bsearch_index { |p| p > max_pos_pixel }
      last_idx = last_phys ? {last_phys - 1, n - 1}.min : n - 1
      content_start = {first_idx, sticky_count}.max

      # Weak seam invariant (see above): nothing scrolled out is physically past last_idx.
      {% if flag?(:verify_bounds) %}
        num_shifted.times do |i|
          raise "StickyMath seam invariant violated: shifted #{scroll_order[i]} > last_idx #{last_idx}" if scroll_order[i] > last_idx
        end
      {% end %}

      positions = Hash(Int32, Int32).new
      visible = Array(Int32).new

      # Sticky band [0, sticky_count): always considered; carries its own shifted-size prefix.
      sticky_band = {sticky_count, n}.min
      sticky_running = 0
      sticky_band.times do |idx|
        if shifted.includes?(idx)
          sticky_running += sizes_pixel[idx]
        else
          visible << idx
          positions[idx] = physical_cum[idx] - sticky_running
        end
      end

      # Content window [content_start, last_idx]: base = total shifted − shifted-within-window
      # (weak invariant ⇒ none past last_idx), then one walk accumulating the prefix — O(V).
      shifted_within = 0
      (content_start..last_idx).each { |idx| shifted_within += sizes_pixel[idx] if shifted.includes?(idx) }
      running = offset - shifted_within
      (content_start..last_idx).each do |idx|
        if shifted.includes?(idx)
          running += sizes_pixel[idx]
        else
          visible << idx
          positions[idx] = physical_cum[idx] - running
        end
      end
      positions[-1] = physical_cum[n] - offset # Sentinel

      @@work += sticky_band + {last_idx - content_start + 1, 0}.max # O(visible) cells examined

      {offset, positions, shifting_index, visible, shifted}
    end

    # Returns visible (non-shifted) indices in a physical range — O(V + log N).
    # For creation/destruction regions that only need the index list, not positions.
    # Membership via ShiftedSet (cached inverse permutation) — O(1) per cell, no shifted-set
    # materialisation, so the cost is the visible window, not the scrolled-out prefix.
    def self.visible_indices_in_range(
        physical_cum : Array(Int32),
        scroll_rank : Array(Int32),
        num_shifted : Int32,
        min_pos : Int32,
        max_pos : Int32,
        sticky_count : Int32
    ) : Array(Int32)
      n = physical_cum.size - 1
      shifted = ShiftedSet.new(scroll_rank, num_shifted)

      # Physical range via bsearch — O(log N)
      first_phys = physical_cum.bsearch_index { |p| p > min_pos }
      first_idx = first_phys ? {first_phys - 1, 0}.max : n
      last_phys = physical_cum.bsearch_index { |p| p > max_pos }
      last_idx = last_phys ? {last_phys - 1, n - 1}.min : n - 1
      content_start = {first_idx, sticky_count}.max

      # Collect: sticky band + physical window, interior holes excluded — O(V + sticky_count)
      result = Array(Int32).new
      sticky_band = {sticky_count, n}.min
      sticky_band.times { |idx| result << idx unless shifted.includes?(idx) }
      (content_start..last_idx).each { |idx| result << idx unless shifted.includes?(idx) }
      @@work += sticky_band + {last_idx - content_start + 1, 0}.max # O(visible) cells examined
      result
    end

    # Returns first non-shifted index >= idx, or -1 if none.
    # Walks consecutive shifted cells via O(1) membership — bounded by the shifted run length.
    def self.first_visible_at_or_after(idx : Int32, shifted : ShiftedSet, n : Int32) : Int32
      return -1 if idx >= n
      current = idx
      while current < n && shifted.includes?(current)
        current += 1
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
