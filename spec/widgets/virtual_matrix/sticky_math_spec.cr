require "../../spec_helper"
require "../../../src/widgets/virtual_matrix/sticky_math"

include CrymbleUI::Widgets::VirtualMatrix

# Inverse permutation of a scroll_order: inv[physical_index] = its position in scroll order.
# This is what the matrix caches per resize and what sticky_fast/visible_indices_in_range now
# take for O(1) shifted-membership.
private def inverse_perm(order : Array(Int32)) : Array(Int32)
  inv = Array.new(order.size, 0)
  order.each_with_index { |phys, i| inv[phys] = i }
  inv
end

describe StickyMath do
  describe ".visibility_range_min" do
    it "returns 0 for first element" do
      # With uniform sizes, first element should be visible at position 0
      result = StickyMath.visibility_range_min(0, [10, 10, 10, 10], [0, 1, 2, 3])
      result.should eq(0)
    end

    it "returns cumulative offset for later elements" do
      # Element 1 becomes visible after scrolling past element 0 (10 pixels)
      result = StickyMath.visibility_range_min(1, [10, 10, 10, 10], [0, 1, 2, 3])
      result.should eq(10)

      result = StickyMath.visibility_range_min(2, [10, 10, 10, 10], [0, 1, 2, 3])
      result.should eq(20)

      result = StickyMath.visibility_range_min(3, [10, 10, 10, 10], [0, 1, 2, 3])
      result.should eq(30)
    end

    it "respects scroll_order" do
      # scroll_order [3,1,4,2,0] means:
      # - element 3 scrolls out first (at position 0-10)
      # - element 1 scrolls out second (at position 10-20)
      # - element 4 scrolls out third (at position 20-30)
      # - element 2 scrolls out fourth (at position 30-40)
      # - element 0 scrolls out last (at position 40-50)
      sizes = [10, 10, 10, 10, 10]
      scroll_order = [3, 1, 4, 2, 0]

      StickyMath.visibility_range_min(0, sizes, scroll_order).should eq(40) # Last to scroll out
      StickyMath.visibility_range_min(1, sizes, scroll_order).should eq(10) # Second to scroll out
      StickyMath.visibility_range_min(2, sizes, scroll_order).should eq(30) # Fourth to scroll out
      StickyMath.visibility_range_min(3, sizes, scroll_order).should eq(0)  # First to scroll out
      StickyMath.visibility_range_min(4, sizes, scroll_order).should eq(20) # Third to scroll out
    end
  end

  describe ".visibility_range_max" do
    it "returns 0 when element fits in window" do
      # Window 25 pixels, elements 10 pixels each
      # Elements 0 and 1 can be fully visible without scrolling
      StickyMath.visibility_range_max(0, [10, 10, 10, 10], [0, 1, 2, 3], 25).should eq(0)
      StickyMath.visibility_range_max(1, [10, 10, 10, 10], [0, 1, 2, 3], 25).should eq(0)
    end

    it "returns scroll offset needed for later elements" do
      # Element 2 at position 20, size 10, ends at 30
      # Window is 25 pixels, so need to scroll to 30 - 25 = 5
      StickyMath.visibility_range_max(2, [10, 10, 10, 10], [0, 1, 2, 3], 25).should eq(5)

      # Element 3 at position 30, size 10, ends at 40
      # Need to scroll to 40 - 25 = 15
      StickyMath.visibility_range_max(3, [10, 10, 10, 10], [0, 1, 2, 3], 25).should eq(15)
    end

    it "respects scroll_order for max calculation" do
      sizes = [10, 10, 10, 10, 10]
      scroll_order = [3, 1, 4, 2, 0]

      # max uses sizes directly (accumulates by index order)
      # element 0: ends at 10, window 25 -> max(10-25, 0) = 0
      # element 1: ends at 20, window 25 -> max(20-25, 0) = 0
      # element 2: ends at 30, window 25 -> max(30-25, 0) = 5
      # element 3: ends at 40, window 25 -> max(40-25, 0) = 15
      # element 4: ends at 50, window 25 -> max(50-25, 0) = 25
      StickyMath.visibility_range_max(0, sizes, scroll_order, 25).should eq(0)
      StickyMath.visibility_range_max(1, sizes, scroll_order, 25).should eq(0)
      StickyMath.visibility_range_max(2, sizes, scroll_order, 25).should eq(5)
      StickyMath.visibility_range_max(3, sizes, scroll_order, 25).should eq(15)
      StickyMath.visibility_range_max(4, sizes, scroll_order, 25).should eq(25)
    end
  end

  describe ".calc_visibles" do
    it "returns correct firsts and nums for full visibility" do
      # All elements visible
      nums, firsts = StickyMath.calc_visibles(5, Set{0, 1, 2, 3, 4})

      # nums[i] = count of visible elements <= i
      # with extra leading 0, so nums has length n+1
      nums.should eq([0, 1, 2, 3, 4, 5])

      # firsts[i] = first visible element >= i
      firsts.should eq([0, 1, 2, 3, 4])
    end

    it "handles gaps in visibility" do
      # Only elements 2, 4, 5, 6, 8 visible (10 total elements)
      nums, firsts = StickyMath.calc_visibles(10, Set{2, 4, 5, 6, 8})

      # nums: count of visible elements <= index
      # index:       0,1,2,3,4,5,6,7,8,9
      # is_visible:  0,0,1,0,1,1,1,0,1,0
      # nums:       [0,0,0,1,1,2,3,4,4,5,5]
      nums.should eq([0, 0, 0, 1, 1, 2, 3, 4, 4, 5, 5])

      # firsts: first visible element at or after index
      # index:       0,1,2,3,4,5,6,7,8,9
      # firsts:      2,2,2,4,4,5,6,8,8,-1
      firsts.should eq([2, 2, 2, 4, 4, 5, 6, 8, 8, -1])
    end
  end

  describe ".sticky" do
    it "returns all elements visible when viewport covers everything" do
      sizes = [10, 10, 10]
      scroll_order = [0, 1, 2]
      min_pos = 0
      max_pos = 30 # Full content fits

      offset, positions, shifting_index, indices, indices_with_beyond = StickyMath.sticky(sizes, scroll_order, min_pos, max_pos)

      offset.should eq(0)
      shifting_index.should eq(0) # First element is at the shift boundary
      indices.should eq([0, 1, 2])
      indices.each { |i| positions[i]?.should_not be_nil }
    end

    it "computes offset for scrolled-out elements" do
      sizes = [10, 10, 10, 10]
      scroll_order = [0, 1, 2, 3]
      min_pos = 15 # Scrolled 15 pixels
      max_pos = 40 # Window 25 pixels wide

      offset, positions, shifting_index, indices, _ = StickyMath.sticky(sizes, scroll_order, min_pos, max_pos)

      # Element 0 is fully scrolled out (10 pixels < 15)
      # Element 1 is partially visible (10-20 crosses 15)
      offset.should eq(10) # Only element 0 fully out
      shifting_index.should eq(1) # Element 1 is at shift boundary
      indices.should contain(1)
      indices.should contain(2)
      indices.should contain(3)
    end

    it "includes all non-shifted elements regardless of viewport end" do
      sizes = [10, 10, 10, 10, 10]
      scroll_order = [0, 1, 2, 3, 4]
      min_pos = 0
      max_pos = 25 # Only shows first 2.5 elements

      offset, positions, shifting_index, indices, indices_with_beyond = StickyMath.sticky(sizes, scroll_order, min_pos, max_pos)

      offset.should eq(0)
      # All elements should be in visible set (none shifted out at scroll=0)
      indices.should eq([0, 1, 2, 3, 4])
      # indices_with_beyond should equal indices (no beyond-viewport filtering)
      indices.to_set.subset_of?(indices_with_beyond).should be_true
    end

    it "handles sticky scroll_order correctly" do
      # scroll_order [2,0,1] means:
      # - element 2 scrolls out first
      # - element 0 scrolls out second
      # - element 1 scrolls out last (stays sticky longest)
      sizes = [10, 10, 10]
      scroll_order = [2, 0, 1]
      min_pos = 15 # Scrolled past element 2 (first in scroll_order)
      max_pos = 40

      offset, positions, shifting_index, indices, _ = StickyMath.sticky(sizes, scroll_order, min_pos, max_pos)

      # Element 2 (first in scroll_order) is fully scrolled out
      offset.should eq(10)
      shifting_index.should eq(0) # Element 0 is now at shift boundary
      indices.should contain(0)
      indices.should contain(1)
    end

    it "correctly positions elements relative to scroll" do
      sizes = [10, 20, 15]
      scroll_order = [0, 1, 2]
      min_pos = 0
      max_pos = 45

      offset, positions, shifting_index, indices, _ = StickyMath.sticky(sizes, scroll_order, min_pos, max_pos)

      # Positions should accumulate: 0, 10, 30
      positions[0].should eq(0)
      positions[1].should eq(10)
      positions[2].should eq(30)
      positions[-1].should eq(45) # Dummy element at end
    end

    it "includes all non-shifted columns in visible set" do
      # Task board layout: 13 columns with sticky groups
      # scroll_order groups: [2,3,4,1, 6,7,8,5, 10,11,12,9, 0]
      # Col 0 is the stickiest (last to scroll out) but physically leftmost
      sizes = [83, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103]
      order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]

      # At scroll=350, viewport_end=1010
      # 3 elements shifted out (scroll_order[0..2] = cols 2,3,4)
      _, _, _, visible, _ = StickyMath.sticky(sizes, order, 350, 1010)

      # Col 0 (sticky, not shifted) MUST be visible — needed for positions hash
      visible.should contain(0)
      # Cols 10,11 (within viewport at cumulative 927,1030) MUST be visible
      visible.should contain(10)
      visible.should contain(11)
      # Only shifted-out cols should be absent
      visible.should_not contain(2)
      visible.should_not contain(3)
      visible.should_not contain(4)
    end
  end

  describe "performance: O(visible), not O(num_shifted) [seam fix]" do
    # The freeze: a far thumb-drag drives num_shifted ≈ grid size; per-scroll work used to
    # scale with it (building sorted_shifted / shifted_set). After the seam fix, per-call work
    # must scale only with the visible window. StickyMath.work counts shifted-proportional
    # cells examined; the bounds below are generous but far under num_shifted (~9000).
    it "sticky_fast stays O(visible) at far scroll (identity order)" do
      n = 10_000
      sizes = Array.new(n, 20)
      order = (0...n).to_a
      cumulative = order.map { |el| sizes[el] }.accumulate { |x, y| x + y }
      physical_cum = sizes.accumulate(0) { |a, b| a + b }
      min_pos = 9000 * 20
      max_pos = min_pos + 300
      num_shifted = cumulative.bsearch_index { |p| p >= min_pos } || n
      num_shifted.should be > 8000 # sanity: genuinely far-scrolled
      scroll_rank = inverse_perm(order)

      StickyMath.reset_work
      StickyMath.sticky_fast(sizes, order, scroll_rank, num_shifted, cumulative, physical_cum, min_pos, max_pos, 0)
      StickyMath.work.should be < 100
    end

    it "sticky_fast stays O(visible) at far scroll (grouped order, interior holes)" do
      n = 10_000
      sizes = Array.new(n, 20)
      # grouped: groups of 4 (3 data + 1 header); header scrolls out AFTER its data.
      order = [] of Int32
      (0...n).step(4) do |base|
        (1..3).each { |o| order << base + o if base + o < n }
        order << base
      end
      cumulative = order.map { |el| sizes[el] }.accumulate { |x, y| x + y }
      physical_cum = sizes.accumulate(0) { |a, b| a + b }
      min_pos = 9000 * 20
      max_pos = min_pos + 300
      num_shifted = cumulative.bsearch_index { |p| p >= min_pos } || n
      scroll_rank = inverse_perm(order)

      StickyMath.reset_work
      StickyMath.sticky_fast(sizes, order, scroll_rank, num_shifted, cumulative, physical_cum, min_pos, max_pos, 1)
      StickyMath.work.should be < 100
    end

    it "visible_indices_in_range stays O(visible) at far scroll" do
      n = 10_000
      sizes = Array.new(n, 20)
      order = (0...n).to_a
      cumulative = order.map { |el| sizes[el] }.accumulate { |x, y| x + y }
      physical_cum = sizes.accumulate(0) { |a, b| a + b }
      min_pos = 9000 * 20
      max_pos = min_pos + 300
      num_shifted = cumulative.bsearch_index { |p| p >= min_pos } || n
      scroll_rank = inverse_perm(order)

      StickyMath.reset_work
      StickyMath.visible_indices_in_range(physical_cum, scroll_rank, num_shifted, min_pos, max_pos, 0)
      StickyMath.work.should be < 100
    end

    it "sticky_fast viewport matches sticky() ground truth with interior (shifted) holes" do
      # Correctness guard for the membership the perf path must preserve: grouped order where a
      # pinned header sits physically before its scrolled-out data, so shifted cells are interior
      # to [first_idx,last_idx]. Mirrors the n=13 task board.
      sizes = [83, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103, 103]
      order = [2, 3, 4, 1, 6, 7, 8, 5, 10, 11, 12, 9, 0]
      cumulative = order.map { |el| sizes[el] }.accumulate { |x, y| x + y }
      physical_cum = sizes.accumulate(0) { |a, b| a + b }
      min_pos = 350
      max_pos = 1010
      num_shifted = cumulative.bsearch_index { |p| p >= min_pos } || order.size
      scroll_rank = inverse_perm(order)

      _, _, _, truth_visible, _ = StickyMath.sticky(sizes, order, min_pos, max_pos)
      _, _, _, fast_visible, _ = StickyMath.sticky_fast(sizes, order, scroll_rank, num_shifted, cumulative, physical_cum, min_pos, max_pos, 1)

      # shifted-out, physically-interior cols (3,4) must NOT appear in the fast viewport
      [3, 4].each { |c| fast_visible.should_not contain(c) }
      # no dupes, and every fast-visible cell is a real non-shifted cell per the ground truth
      fast_visible.sort.should eq(fast_visible.uniq.sort)
      fast_visible.each { |idx| truth_visible.should contain(idx) }
      fast_visible.should contain(0) # sticky col survives
    end
  end

  describe "Array#accumulate extension" do
    it "accumulates with default initial value" do
      result = [1, 2, 3, 4].accumulate { |a, b| a + b }
      result.should eq([1, 3, 6, 10])
    end

    it "accumulates with explicit initial value" do
      result = [1, 2, 3].accumulate(10) { |a, b| a + b }
      result.should eq([10, 11, 13, 16])
    end

    it "works with multiplication" do
      result = [1, 2, 3, 4].accumulate(1) { |a, b| a * b }
      result.should eq([1, 1, 2, 6, 24])
    end
  end
end
