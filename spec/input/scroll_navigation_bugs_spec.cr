require "../spec_helper"
require "../../src/widgets/window"

# Helper to find ScrollView ancestor of a widget
private def find_scroll_ancestor(widget : CrymbleUI::Widget?) : CrymbleUI::ScrollView?
  current = widget
  while current
    return current.as(CrymbleUI::ScrollView) if current.is_a?(CrymbleUI::ScrollView)
    current = current.parent
  end
  nil
end

# Helper to create a multi-panel layout like scroll_view_demo
private def create_three_panel_layout
    window = CrymbleUI::Window.new("Test", 900, 400)
    hstack = CrymbleUI::HStack.new(spacing: 10.0)

    # Panel 1: Vertical scroll (32 buttons)
    vscroll = CrymbleUI::ScrollView.new(
      direction: CrymbleUI::ScrollDirection::Vertical,
      id: "vscroll"
    )
    vstack1 = CrymbleUI::VStack.new(spacing: 5.0)
    vbuttons = [] of CrymbleUI::Button
    32.times do |i|
      btn = CrymbleUI::Button.new("V-#{i}", id: "v#{i}") { }
      vbuttons << btn
      vstack1.add_child(btn)
    end
    vscroll.set_content(vstack1)

    # Panel 2: Horizontal scroll (32 buttons)
    hscroll = CrymbleUI::ScrollView.new(
      direction: CrymbleUI::ScrollDirection::Horizontal,
      id: "hscroll"
    )
    hstack1 = CrymbleUI::HStack.new(spacing: 5.0)
    hbuttons = [] of CrymbleUI::Button
    32.times do |i|
      btn = CrymbleUI::Button.new("H-#{i}", id: "h#{i}") { }
      hbuttons << btn
      hstack1.add_child(btn)
    end
    hscroll.set_content(hstack1)

    # Panel 3: Both directions (8x8 grid for testing)
    both = CrymbleUI::ScrollView.new(
      direction: CrymbleUI::ScrollDirection::Both,
      id: "both"
    )
    grid = CrymbleUI::VStack.new(spacing: 5.0)
    both_buttons = [] of Array(CrymbleUI::Button)
    8.times do |row|
      row_buttons = [] of CrymbleUI::Button
      hrow = CrymbleUI::HStack.new(spacing: 5.0)
      8.times do |col|
        btn = CrymbleUI::Button.new("#{row},#{col}", id: "b#{row}_#{col}") { }
        row_buttons << btn
        hrow.add_child(btn)
      end
      both_buttons << row_buttons
      grid.add_child(hrow)
    end
    both.set_content(grid)

    hstack.add_child(vscroll)
    hstack.add_child(hscroll)
    hstack.add_child(both)
    window.add_child(hstack)

    # Layout
    constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(900.0, 400.0))
    window.layout(constraints, CrymbleUI::Vec2.zero)

    {window, vscroll, hscroll, both, vbuttons, hbuttons, both_buttons}
end

# Tests for scroll navigation bugs reported in scroll_view_demo
# Bug tracking: (a) works, (b,c,d,e,f,g) are bugs
describe "Scroll Navigation Bugs" do
  describe "Bug (f): Stale hover after keyboard scroll" do
    it "clears hover when widget scrolls out of view" do
      window, vscroll, _, _, vbuttons, _, _ = create_three_panel_layout

      btn0 = vbuttons[0]
      bounds = btn0.bounds

      # Get normal (non-hovered) color
      normal_prims = btn0.to_primitives(bounds)
      normal_bg = normal_prims[0].as(CrymbleUI::FillRect).color

      # Hover over button 0 (visible at top)
      btn0.on_mouse_enter

      # Verify hover is active (brighter color)
      hover_prims = btn0.to_primitives(bounds)
      hover_bg = hover_prims[0].as(CrymbleUI::FillRect).color
      hover_bg.g.should be > normal_bg.g  # Brighter when hovered (check green channel)

      # Scroll the view down so btn0 is no longer visible
      # Simulate keyboard-triggered scroll (e.g., focus moved to btn15)
      vscroll.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 400.0))

      # BUG: btn0 should no longer be hovered since it's off-screen
      # Currently this fails because hover isn't cleared on scroll
      after_scroll_prims = btn0.to_primitives(bounds)
      after_scroll_bg = after_scroll_prims[0].as(CrymbleUI::FillRect).color

      # Should be back to normal color (not hovered)
      after_scroll_bg.should eq(normal_bg), "Button should not be hovered after scrolling off-screen"
    end
  end

  describe "Bug (b,c,g): Cross-panel navigation containment" do
    it "arrow keys stay within same ScrollView" do
      window, _, hscroll, both, _, hbuttons, both_buttons = create_three_panel_layout

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus H-5 in hscroll panel
      h5 = hbuttons[5]
      fm.focus(h5)
      fm.focused_widget.should eq(h5)

      # Press Right multiple times - should stay in hscroll
      10.times do |i|
        fm.navigate(:right, root: window)
        focused = fm.focused_widget

        # BUG: Focus should stay within hscroll panel
        # It currently jumps to "both" panel erratically
        parent_scroll = find_scroll_ancestor(focused)
        parent_scroll.should eq(hscroll), "After #{i+1} Right presses, focus jumped to different panel"
      end
    end

    it "allows Tab to cycle across panels" do
      window, vscroll, hscroll, both, vbuttons, hbuttons, _ = create_three_panel_layout

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus first button in vscroll
      fm.focus(vbuttons[0])

      # Tab should eventually reach hscroll and both panels
      reached_hscroll = false
      reached_both = false

      100.times do
        fm.cycle_focus(forward: true, root: window)
        focused = fm.focused_widget
        break unless focused

        parent_scroll = find_scroll_ancestor(focused)
        reached_hscroll = true if parent_scroll == hscroll
        reached_both = true if parent_scroll == both

        break if reached_hscroll && reached_both
      end

      reached_hscroll.should be_true, "Tab should cycle to hscroll panel"
      reached_both.should be_true, "Tab should cycle to both panel"
    end
  end

  describe "Bug (d): Both-direction cursor down in multi-panel layout" do
    it "cursor down stays in 'both' panel (not jump to hscroll)" do
      # This test uses the multi-panel layout where the bug manifests
      # Bug: cursor down from (0,0) in "both" jumps to hscroll instead of (1,0)
      window, _, hscroll, both, _, _, both_buttons = create_three_panel_layout

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus (0,0) in "both" panel
      btn_0_0 = both_buttons[0][0]
      fm.focus(btn_0_0)
      fm.focused_widget.should eq(btn_0_0)

      # Press Down - should go to (1,0) in same panel
      fm.navigate(:down, root: window)

      focused = fm.focused_widget.not_nil!
      parent_scroll = find_scroll_ancestor(focused)

      # BUG: Focus should stay in "both" panel, not jump to hscroll
      # User reported: "cursor down does not scroll" because it jumps panels
      parent_scroll.should eq(both), "Cursor down should stay in 'both' panel, not jump to hscroll"
    end
  end

  describe "Direction-restricted ScrollView navigation" do
    it "only allows up/down in vertical ScrollView" do
      window, vscroll, _, _, vbuttons, _, _ = create_three_panel_layout

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus V-5 (middle of vertical list)
      v5 = vbuttons[5]
      fm.focus(v5)

      # cursor-left should stay on V-5 (perpendicular to scroll direction)
      fm.navigate(:left, root: window)
      fm.focused_widget.should eq(v5), "cursor-left in vertical ScrollView should stay on current widget"

      # cursor-right should stay on V-5 (perpendicular to scroll direction)
      fm.navigate(:right, root: window)
      fm.focused_widget.should eq(v5), "cursor-right in vertical ScrollView should stay on current widget"

      # cursor-up should move to V-4 (valid direction)
      fm.navigate(:up, root: window)
      fm.focused_widget.should eq(vbuttons[4]), "cursor-up in vertical ScrollView should work"

      # cursor-down should move to V-5 (valid direction)
      fm.navigate(:down, root: window)
      fm.focused_widget.should eq(vbuttons[5]), "cursor-down in vertical ScrollView should work"
    end

    it "only allows left/right in horizontal ScrollView" do
      window, _, hscroll, _, _, hbuttons, _ = create_three_panel_layout

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus H-5 (middle of horizontal list)
      h5 = hbuttons[5]
      fm.focus(h5)

      # cursor-up should stay on H-5 (perpendicular to scroll direction)
      fm.navigate(:up, root: window)
      fm.focused_widget.should eq(h5), "cursor-up in horizontal ScrollView should stay on current widget"

      # cursor-down should stay on H-5 (perpendicular to scroll direction)
      fm.navigate(:down, root: window)
      fm.focused_widget.should eq(h5), "cursor-down in horizontal ScrollView should stay on current widget"

      # cursor-left should move to H-4 (valid direction)
      fm.navigate(:left, root: window)
      fm.focused_widget.should eq(hbuttons[4]), "cursor-left in horizontal ScrollView should work"

      # cursor-right should move to H-5 (valid direction)
      fm.navigate(:right, root: window)
      fm.focused_widget.should eq(hbuttons[5]), "cursor-right in horizontal ScrollView should work"
    end

    it "allows all directions in Both ScrollView" do
      window, _, _, both, _, _, both_buttons = create_three_panel_layout

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus (1,1) in the grid (has neighbors in all directions)
      btn_1_1 = both_buttons[1][1]
      fm.focus(btn_1_1)

      # All four directions should work
      fm.navigate(:up, root: window)
      fm.focused_widget.should eq(both_buttons[0][1]), "cursor-up in Both ScrollView should work"

      fm.focus(btn_1_1)  # Reset to center
      fm.navigate(:down, root: window)
      fm.focused_widget.should eq(both_buttons[2][1]), "cursor-down in Both ScrollView should work"

      fm.focus(btn_1_1)  # Reset to center
      fm.navigate(:left, root: window)
      fm.focused_widget.should eq(both_buttons[1][0]), "cursor-left in Both ScrollView should work"

      fm.focus(btn_1_1)  # Reset to center
      fm.navigate(:right, root: window)
      fm.focused_widget.should eq(both_buttons[1][2]), "cursor-right in Both ScrollView should work"
    end

    it "stays at edges without crossing panels" do
      window, vscroll, hscroll, both, vbuttons, hbuttons, both_buttons = create_three_panel_layout

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # V-0 + cursor-up should stay (top edge of vertical list)
      fm.focus(vbuttons[0])
      fm.navigate(:up, root: window)
      fm.focused_widget.should eq(vbuttons[0]), "cursor-up at top of vertical list should stay"

      # H-0 + cursor-left should stay (left edge of horizontal list)
      fm.focus(hbuttons[0])
      fm.navigate(:left, root: window)
      fm.focused_widget.should eq(hbuttons[0]), "cursor-left at left of horizontal list should stay"

      # (0,0) + cursor-up should stay (top edge of grid)
      fm.focus(both_buttons[0][0])
      fm.navigate(:up, root: window)
      fm.focused_widget.should eq(both_buttons[0][0]), "cursor-up at top of grid should stay"

      # (0,0) + cursor-left should stay (left edge of grid)
      fm.focus(both_buttons[0][0])
      fm.navigate(:left, root: window)
      fm.focused_widget.should eq(both_buttons[0][0]), "cursor-left at left of grid should stay"
    end
  end

  describe "Sub-pixel alignment tolerance" do
    it "ignores candidates with sub-pixel center offset" do
      # Create a 32x32 grid like the demo to reproduce the bug
      # Bug: (0,0) + cursor-left → (2,0) due to tiny positional differences
      window = CrymbleUI::Window.new("Test", 800, 600)
      both = CrymbleUI::ScrollView.new(
        direction: CrymbleUI::ScrollDirection::Both,
        id: "both"
      )
      grid = CrymbleUI::VStack.new(spacing: 5.0)
      both_buttons = [] of Array(CrymbleUI::Button)

      # Use 32x32 grid like the demo to expose the bug
      32.times do |row|
        row_buttons = [] of CrymbleUI::Button
        hrow = CrymbleUI::HStack.new(spacing: 5.0)
        32.times do |col|
          btn = CrymbleUI::Button.new("#{row},#{col}", id: "b#{row}_#{col}") { }
          row_buttons << btn
          hrow.add_child(btn)
        end
        both_buttons << row_buttons
        grid.add_child(hrow)
      end
      both.set_content(grid)
      window.add_child(both)

      # Layout
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus (0,0) - leftmost in its row
      btn_0_0 = both_buttons[0][0]
      fm.focus(btn_0_0)

      # cursor-left should stay on (0,0), not jump to (2,0) or any other row
      fm.navigate(:left, root: window)
      fm.focused_widget.should eq(btn_0_0), "cursor-left from (0,0) should stay on (0,0)"
    end

    it "ignores sub-pixel center differences in direction check" do
      # Test the in_direction? function directly with controlled sub-pixel differences
      # This reproduces the bug where floating-point layout causes
      # widgets in the same column to have slightly different X centers

      navigator = CrymbleUI::FocusNavigator.new

      # Create widgets where widget_b is 0.5px "to the left" of widget_a
      # Both should be considered in the same column (not valid left target)
      widget_a = TestWidget.new(id: "a")
      widget_b = TestWidget.new(id: "b")

      # Position them: widget_a at x=100, widget_b at x=99.5 (sub-pixel left)
      # Both have width 50, so:
      # widget_a center = 100 + 25 = 125.0
      # widget_b center = 99.5 + 25 = 124.5 (0.5px to the left - sub-pixel!)
      widget_a.bounds = CrymbleUI::Rect.new(100.0, 0.0, 50.0, 30.0)
      widget_b.bounds = CrymbleUI::Rect.new(99.5, 50.0, 50.0, 30.0)  # Different Y, sub-pixel X difference

      # Navigate left from widget_a - should NOT find widget_b (only 0.5px difference)
      result = navigator.find_neighbor(widget_a, [widget_a, widget_b], :left)
      result.should be_nil, "Sub-pixel left difference (0.5px) should not count as 'left'"
    end

    it "requires vertical overlap for left/right navigation (varying button widths)" do
      # Bug: (31,0) + cursor-left → (9,0) because:
      # - "31,0" (4 chars) is wider than "9,0" (3 chars)
      # - Button (9,0) center is several pixels left of (31,0) center
      # - Even with 1px threshold, this passes the "is left" check
      # Fix: Require vertical overlap (same row) for left/right navigation

      window = CrymbleUI::Window.new("Test", 800, 600)
      both = CrymbleUI::ScrollView.new(
        direction: CrymbleUI::ScrollDirection::Both,
        id: "both"
      )
      grid = CrymbleUI::VStack.new(spacing: 5.0)
      both_buttons = [] of Array(CrymbleUI::Button)

      32.times do |row|
        row_buttons = [] of CrymbleUI::Button
        hrow = CrymbleUI::HStack.new(spacing: 5.0)
        32.times do |col|
          btn = CrymbleUI::Button.new("#{row},#{col}", id: "b#{row}_#{col}") { }
          row_buttons << btn
          hrow.add_child(btn)
        end
        both_buttons << row_buttons
        grid.add_child(hrow)
      end
      both.set_content(grid)
      window.add_child(both)

      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
      window.layout(constraints, CrymbleUI::Vec2.zero)

      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      # Focus (31,0) - leftmost in row 31
      btn_31_0 = both_buttons[31][0]
      fm.focus(btn_31_0)

      # cursor-left should stay on (31,0), NOT jump to (9,0) or any other row
      fm.navigate(:left, root: window)
      fm.focused_widget.should eq(btn_31_0), "cursor-left from (31,0) should stay on (31,0), not jump to another row"
    end
  end
end
