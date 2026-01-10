require "../spec_helper"
require "../../src/input/focus_manager"
require "../../src/widgets/scroll_view"

# Test that ScrollView scrolls to keep focused widget visible
# User bug report: When moving focus outside visible area, scroller doesn't follow
describe "ScrollView focus scrolling" do
  describe "#scroll_to_visible" do
    it "scrolls down when focused widget is below viewport" do
      # Create a tall ScrollView with many buttons
      scroll_view = CrymbleUI::ScrollView.new(id: "scroll")
      vstack = CrymbleUI::VStack.new

      # Add 20 buttons (each ~34px tall, so total ~680px)
      buttons = [] of CrymbleUI::Button
      20.times do |i|
        btn = CrymbleUI::Button.new("Button #{i}", id: "btn#{i}") { }
        buttons << btn
        vstack.add_child(btn)
      end

      scroll_view.set_content(vstack)

      # Layout ScrollView with small viewport (150px height)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      scroll_view.layout(constraints, CrymbleUI::Vec2.zero)

      # Initially at top
      scroll_view.scroll_offset.y.should eq(0.0)

      # Button at bottom is outside viewport (e.g., button 15)
      target_button = buttons[15]
      target_bounds = target_button.bounds  # Relative to content

      # Verify button is below viewport
      (target_bounds.y + target_bounds.height).should be > 150.0

      # Call scroll_to_visible to bring button into view
      scroll_view.scroll_to_visible(target_button)

      # Scroll offset should have increased to show the button
      # Button should now be within the visible viewport
      # After scrolling, the button's top should be within viewport
      visible_top = scroll_view.scroll_offset.y
      visible_bottom = visible_top + 150.0

      (target_bounds.y >= visible_top).should be_true
      (target_bounds.y + target_bounds.height <= visible_bottom).should be_true
    end

    it "scrolls up when focused widget is above viewport" do
      scroll_view = CrymbleUI::ScrollView.new(id: "scroll")
      vstack = CrymbleUI::VStack.new

      buttons = [] of CrymbleUI::Button
      20.times do |i|
        btn = CrymbleUI::Button.new("Button #{i}", id: "btn#{i}") { }
        buttons << btn
        vstack.add_child(btn)
      end

      scroll_view.set_content(vstack)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      scroll_view.layout(constraints, CrymbleUI::Vec2.zero)

      # Scroll down first (button 0 is now above viewport)
      scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 300.0))

      # Button 0 is at top, now above viewport
      target_button = buttons[0]

      # Call scroll_to_visible to bring button into view
      scroll_view.scroll_to_visible(target_button)

      # Scroll offset should have decreased
      scroll_view.scroll_offset.y.should be < 300.0

      # Button 0 should now be visible
      visible_top = scroll_view.scroll_offset.y
      target_bounds = target_button.bounds
      target_bounds.y.should be >= visible_top
    end

    it "does nothing when widget is already visible" do
      scroll_view = CrymbleUI::ScrollView.new(id: "scroll")
      vstack = CrymbleUI::VStack.new

      buttons = [] of CrymbleUI::Button
      5.times do |i|
        btn = CrymbleUI::Button.new("Button #{i}", id: "btn#{i}") { }
        buttons << btn
        vstack.add_child(btn)
      end

      scroll_view.set_content(vstack)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 300.0))
      scroll_view.layout(constraints, CrymbleUI::Vec2.zero)

      # All buttons should be visible (viewport is 300px, content is ~170px)
      initial_offset = scroll_view.scroll_offset.y

      scroll_view.scroll_to_visible(buttons[2])

      # Offset should not change
      scroll_view.scroll_offset.y.should eq(initial_offset)
    end
  end

  describe "focus navigation integration" do
    it "scrolls when arrow key focuses widget outside viewport" do
      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      scroll_view = CrymbleUI::ScrollView.new(id: "scroll")
      vstack = CrymbleUI::VStack.new

      buttons = [] of CrymbleUI::Button
      20.times do |i|
        btn = CrymbleUI::Button.new("Button #{i}", id: "btn#{i}") { }
        buttons << btn
        vstack.add_child(btn)
      end

      scroll_view.set_content(vstack)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      scroll_view.layout(constraints, CrymbleUI::Vec2.zero)

      # Focus first button
      fm.focus(buttons[0])

      # Navigate down repeatedly until we reach a button outside viewport
      # This simulates pressing down arrow key multiple times
      15.times do
        fm.navigate(:down, root: scroll_view)
      end

      # The focused widget should be visible in the viewport
      focused = fm.focused_widget.not_nil!
      focused_bounds = focused.bounds

      visible_top = scroll_view.scroll_offset.y
      visible_bottom = visible_top + 150.0

      # BUG: This will fail because ScrollView doesn't auto-scroll on focus change
      focused_bounds.y.should be >= visible_top
      (focused_bounds.y + focused_bounds.height).should be <= visible_bottom
    end
  end

  describe "scroll_to_visible with nested layout" do
    it "scrolls to nested widget in grid layout (VStack → HStack → Button)" do
      # Bug: scroll_to_visible uses widget.bounds (relative to immediate parent)
      # but needs bounds relative to content for nested layouts
      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      scroll_view = CrymbleUI::ScrollView.new(
        direction: CrymbleUI::ScrollDirection::Both,
        id: "scroll"
      )

      # Create grid: VStack of HStacks of Buttons
      grid = CrymbleUI::VStack.new(spacing: 5.0)
      buttons = [] of Array(CrymbleUI::Button)

      # 20 rows x 5 columns - enough to require scrolling
      20.times do |row|
        row_buttons = [] of CrymbleUI::Button
        hrow = CrymbleUI::HStack.new(spacing: 5.0)
        5.times do |col|
          btn = CrymbleUI::Button.new("#{row},#{col}", id: "btn_#{row}_#{col}") { }
          row_buttons << btn
          hrow.add_child(btn)
        end
        buttons << row_buttons
        grid.add_child(hrow)
      end

      scroll_view.set_content(grid)

      # Small viewport that only shows ~4 rows
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(300.0, 150.0))
      scroll_view.layout(constraints, CrymbleUI::Vec2.zero)

      # Initially at top
      scroll_view.scroll_offset.y.should eq(0.0)

      # Focus a button that's below the viewport (e.g., row 15)
      target_button = buttons[15][0]  # Button (15,0)
      fm.focus(target_button)

      # After focus, scroll should have adjusted to show the button
      # The button's position in content coordinates should be visible
      visible_top = scroll_view.scroll_offset.y
      visible_bottom = visible_top + 150.0

      # Calculate button position relative to content (walk up to content widget)
      # Row 15 is at approximately: 15 * (button_height + spacing)
      # With button height ~34px and spacing 5px, that's ~15 * 39 = 585px
      # Scroll should have increased significantly
      scroll_view.scroll_offset.y.should be > 100.0, "Scroll should have moved to show row 15"
    end

    it "accounts for scrollbar when scrolling to widget" do
      # Bug: scroll_to_visible uses viewport_size but ignores scrollbar
      # Widget at bottom gets covered by horizontal scrollbar
      fm = CrymbleUI::FocusManager.new
      CrymbleUI::Widget.focus_manager = fm

      scroll_view = CrymbleUI::ScrollView.new(
        direction: CrymbleUI::ScrollDirection::Both,
        id: "scroll"
      )

      # Create grid that's larger than viewport in both directions
      # to ensure both scrollbars are visible
      grid = CrymbleUI::VStack.new(spacing: 5.0)
      buttons = [] of Array(CrymbleUI::Button)

      20.times do |row|
        row_buttons = [] of CrymbleUI::Button
        hrow = CrymbleUI::HStack.new(spacing: 5.0)
        10.times do |col|
          btn = CrymbleUI::Button.new("#{row},#{col}", id: "btn_#{row}_#{col}") { }
          row_buttons << btn
          hrow.add_child(btn)
        end
        buttons << row_buttons
        grid.add_child(hrow)
      end

      scroll_view.set_content(grid)

      # Small viewport where scrollbars will be visible
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(200.0, 150.0))
      scroll_view.layout(constraints, CrymbleUI::Vec2.zero)

      # Focus a button that's at the bottom edge
      target_button = buttons[15][0]
      fm.focus(target_button)

      # The widget should be FULLY visible (not covered by scrollbar)
      # Scrollbar is 16px, so effective visible height is 150 - 16 = 134
      # (We know scrollbar is visible because content is larger than viewport)
      effective_visible_height = 150.0 - 16.0  # viewport height minus scrollbar
      visible_top = scroll_view.scroll_offset.y
      visible_bottom = visible_top + effective_visible_height

      # Get button bounds relative to content
      target_bounds = target_button.bounds
      parent = target_button.parent
      while parent && parent != scroll_view.children.first?
        target_bounds = CrymbleUI::Rect.new(
          target_bounds.x + parent.bounds.x,
          target_bounds.y + parent.bounds.y,
          target_bounds.width,
          target_bounds.height
        )
        parent = parent.parent
      end

      # Widget bottom should be within effective visible area (above scrollbar)
      (target_bounds.y + target_bounds.height).should be <= visible_bottom,
        "Widget should be fully visible above the scrollbar"
    end
  end
end
