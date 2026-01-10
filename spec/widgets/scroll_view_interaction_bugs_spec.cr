require "../spec_helper"
require "../../src/testing/test_renderer"

# ScrollView Interaction Bugs - Round 2
# CRITICAL: Tests must validate SPECIFIC CORRECT BEHAVIOR, not just "something changed"
#
# Bug (a): Hit-test coordinate system error - returns wrong widget after scroll
# Bug (c): Scrollbar drag evaluates BOTH axes in Both direction
# Bug (d): Horizontal touchpad scroll broken by delta.y preference

describe "ScrollView Interaction Bugs (Round 2)" do
  # === Bug (a): Hit-Test Coordinate System Error ===
  # Root cause: hit_test adds scroll_offset to window coords, but absolute_bounds
  # is ALSO in window coords - double-counting causes ~3 button offset

  describe "Bug (a): Hit-test returns CORRECT widget after scroll" do
    it "hit_test returns button that is VISUALLY at click position after scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Create buttons with unique IDs, ~25px each
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "scroll")
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times do |i|
        vstack.add_child(CrymbleUI::Button.new("Button #{i}", id: "btn_#{i}") { })
      end
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      # Measure button height from layout
      btn0 = vstack.children[0]
      btn6 = vstack.children[6]
      button_height = btn6.bounds.y - btn0.bounds.y  # Should be ~180px for 6 buttons
      single_button = button_height / 6.0  # ~30px per button

      # Scroll down 150px (~5 buttons worth)
      scroll_offset = 150.0
      scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, scroll_offset))
      renderer.render_frame(app)

      # Calculate which button should be VISUALLY at top after scroll
      # If scroll_offset = 150 and buttons are ~30px each, btn_5 should be at top
      expected_button_index = (scroll_offset / single_button).to_i
      expected_button_id = "btn_#{expected_button_index}"

      # Click at top of visible content area
      abs = scroll_view.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 50.0, abs.y + 15.0)

      # CRITICAL TEST: hit_test must return the VISUALLY displayed button
      hit = scroll_view.hit_test(click_pos)
      hit.should_not be_nil

      # The hit widget should be btn_5 (or close), NOT btn_0!
      # Allow +/-1 button tolerance for rounding
      actual_id = hit.not_nil!.id
      actual_id.should_not be_nil
      actual_index = actual_id.not_nil!.gsub("btn_", "").to_i

      # BUG: Currently returns btn_0 (or nearby) instead of btn_5
      (actual_index - expected_button_index).abs.should be <= 1
    end

    # CRITICAL: Test with NESTED parents like the real demo
    it "hit_test works correctly with nested parent containers" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      # Mimic demo structure: vstack with padding containing scroll_view
      outer_vstack = CrymbleUI::VStack.new(padding: 20.0, spacing: 10.0)
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "scroll")
      inner_vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times do |i|
        inner_vstack.add_child(CrymbleUI::Button.new("Button #{i}", id: "btn_#{i}") { })
      end
      scroll_view.set_content(inner_vstack)
      outer_vstack.add_child(scroll_view)

      window.add_child(outer_vstack)
      app.root_widget = window
      renderer.render_frame(app)

      # Measure button height
      btn0 = inner_vstack.children[0]
      btn6 = inner_vstack.children[6]
      single_button = (btn6.bounds.y - btn0.bounds.y) / 6.0

      # Scroll down 150px
      scroll_offset = 150.0
      scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, scroll_offset))
      renderer.render_frame(app)

      expected_button_index = (scroll_offset / single_button).to_i

      # Click at top of scroll_view (which has parent offset from outer_vstack padding)
      abs = scroll_view.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 50.0, abs.y + 15.0)

      # DEBUG

      hit = scroll_view.hit_test(click_pos)
      hit.should_not be_nil
      actual_id = hit.not_nil!.id
      actual_id.should_not be_nil
      actual_index = actual_id.not_nil!.gsub("btn_", "").to_i


      # CRITICAL: With parent offset, hit_test must still work correctly
      (actual_index - expected_button_index).abs.should be <= 1
    end

    it "hover updates to CORRECT widget after scroll (specific ID check)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "scroll")
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times do |i|
        vstack.add_child(CrymbleUI::Button.new("Button #{i}", id: "btn_#{i}") { })
      end
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      abs = scroll_view.absolute_bounds
      mouse_pos = CrymbleUI::Vec2.new(abs.x + 50.0, abs.y + 15.0)

      # Initial hover should be btn_0
      app.update_hover(mouse_pos)
      hover_before = app.hovered_widget
      hover_before.should_not be_nil
      hover_before.not_nil!.id.should eq "btn_0"

      # Scroll down 200px (~7 buttons)
      scroll_view.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 200.0))
      renderer.render_frame(app)

      # Re-detect hover at same screen position
      app.update_hover(mouse_pos)
      hover_after = app.hovered_widget

      # CRITICAL: Must be btn_6 or btn_7, NOT btn_0!
      hover_after.should_not be_nil
      actual_id = hover_after.not_nil!.id
      actual_id.should_not be_nil
      actual_index = actual_id.not_nil!.gsub("btn_", "").to_i

      # BUG: Currently still returns btn_0 or nearby (hit_test coordinate error)
      actual_index.should be >= 5  # Should be around btn_6-7 after 200px scroll
    end

    # CRITICAL: Test hover update via MOUSE WHEEL (how users actually scroll)
    it "hover updates correctly when scrolling via mouse wheel events" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      outer_vstack = CrymbleUI::VStack.new(padding: 20.0, spacing: 10.0)
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "scroll")
      inner_vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times do |i|
        inner_vstack.add_child(CrymbleUI::Button.new("Button #{i}", id: "btn_#{i}") { })
      end
      scroll_view.set_content(inner_vstack)
      outer_vstack.add_child(scroll_view)

      window.add_child(outer_vstack)
      app.root_widget = window
      renderer.render_frame(app)

      abs = scroll_view.absolute_bounds
      mouse_pos = CrymbleUI::Vec2.new(abs.x + 50.0, abs.y + 15.0)

      # Initial hover should be btn_0
      app.update_hover(mouse_pos)
      hover_before = app.hovered_widget
      hover_before.should_not be_nil
      hover_before.not_nil!.id.should eq "btn_0"

      # Scroll via MOUSE WHEEL (like real user interaction)
      # delta.y = -5.0 means scroll down, repeated 10 times for ~150px scroll
      10.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -5.0), mouse_pos)
        renderer.render_frame(app)
      end

      # Get actual scroll offset
      scroll_y = scroll_view.scroll_offset.y
      btn0 = inner_vstack.children[0]
      btn6 = inner_vstack.children[6]
      single_button = (btn6.bounds.y - btn0.bounds.y) / 6.0
      expected_btn_index = (scroll_y / single_button).to_i


      # Check hover at original mouse position
      app.update_hover(mouse_pos)
      hover_after = app.hovered_widget

      hover_after.should_not be_nil
      actual_id = hover_after.not_nil!.id
      actual_id.should_not be_nil
      actual_index = actual_id.not_nil!.gsub("btn_", "").to_i


      # Must be close to expected, NOT btn_0!
      (actual_index - expected_btn_index).abs.should be <= 1
    end

    # CRITICAL: Test hover update via SCROLLBAR DRAG
    it "hover updates correctly after scrollbar thumb drag" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      outer_vstack = CrymbleUI::VStack.new(padding: 20.0, spacing: 10.0)
      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "scroll")
      inner_vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times do |i|
        inner_vstack.add_child(CrymbleUI::Button.new("Button #{i}", id: "btn_#{i}") { })
      end
      scroll_view.set_content(inner_vstack)
      outer_vstack.add_child(scroll_view)

      window.add_child(outer_vstack)
      app.root_widget = window
      renderer.render_frame(app)

      abs = scroll_view.absolute_bounds
      scrollbar_width = 16.0
      arrow_size = 16.0

      # Mouse position in content area (where we check hover)
      content_mouse_pos = CrymbleUI::Vec2.new(abs.x + 50.0, abs.y + 15.0)

      # Initial hover should be btn_0
      app.update_hover(content_mouse_pos)
      hover_before = app.hovered_widget
      hover_before.should_not be_nil
      hover_before.not_nil!.id.should eq "btn_0"

      # Drag scrollbar thumb down significantly
      thumb_x = abs.x + scroll_view.bounds.width - scrollbar_width / 2.0
      thumb_y = abs.y + arrow_size + 10.0  # Just below up arrow
      app.handle_mouse_down(CrymbleUI::Vec2.new(thumb_x, thumb_y))
      drag_target = CrymbleUI::Vec2.new(thumb_x, thumb_y + 80.0)  # Drag down 80px
      app.handle_mouse_move(drag_target)
      renderer.render_frame(app)
      app.handle_mouse_up(drag_target)

      scroll_y = scroll_view.scroll_offset.y
      btn0 = inner_vstack.children[0]
      btn6 = inner_vstack.children[6]
      single_button = (btn6.bounds.y - btn0.bounds.y) / 6.0
      expected_btn_index = (scroll_y / single_button).to_i


      # Check hover at content area position
      app.update_hover(content_mouse_pos)
      hover_after = app.hovered_widget

      hover_after.should_not be_nil
      actual_id = hover_after.not_nil!.id
      actual_id.should_not be_nil
      actual_index = actual_id.not_nil!.gsub("btn_", "").to_i


      # Must be close to expected, NOT btn_0!
      (actual_index - expected_btn_index).abs.should be <= 1
    end
  end

  # === Bug (c): Scrollbar Drag Evaluates BOTH Axes ===
  # Root cause: DraggingThumb mode doesn't track WHICH scrollbar was clicked
  # Previous test used exact coords (delta.x=0), real mouse has jitter

  describe "Bug (c): Scrollbar drag axis isolation with JITTER" do
    it "vertical scrollbar drag with horizontal jitter only changes Y" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)

      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      32.times do |row|
        hstack = CrymbleUI::HStack.new(spacing: 5.0)
        32.times { |col| hstack.add_child(CrymbleUI::Button.new("#{row},#{col}") { }) }
        vstack.add_child(hstack)
      end
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x
      initial_y = scroll_view.scroll_offset.y

      # Find vertical scrollbar thumb
      abs = scroll_view.absolute_bounds
      scrollbar_width = 16.0
      arrow_size = 16.0
      thumb_x = abs.x + scroll_view.bounds.width - scrollbar_width / 2.0
      thumb_y = abs.y + arrow_size + 15.0

      # Start drag on vertical scrollbar
      app.handle_mouse_down(CrymbleUI::Vec2.new(thumb_x, thumb_y))

      # CRITICAL: Drag with REALISTIC JITTER (5px horizontal drift)
      # Real mouse movement is never perfectly vertical
      drag_target = CrymbleUI::Vec2.new(thumb_x + 5.0, thumb_y + 50.0)
      app.handle_mouse_move(drag_target)
      renderer.render_frame(app)

      app.handle_mouse_up(drag_target)

      # BUG: X should NOT change even with 5px horizontal jitter!
      # Currently, any delta.x causes horizontal scroll
      scroll_view.scroll_offset.x.should eq initial_x
      scroll_view.scroll_offset.y.should be > initial_y
    end

    it "horizontal scrollbar drag with vertical jitter only changes X" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)

      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times do
        hstack = CrymbleUI::HStack.new(spacing: 5.0)
        20.times { hstack.add_child(CrymbleUI::Button.new("B") { }) }
        vstack.add_child(hstack)
      end
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x
      initial_y = scroll_view.scroll_offset.y

      # Find horizontal scrollbar thumb
      abs = scroll_view.absolute_bounds
      scrollbar_width = 16.0
      arrow_size = 16.0
      track_height = scroll_view.viewport_size.height - scrollbar_width
      thumb_x = abs.x + arrow_size + 15.0
      thumb_y = abs.y + track_height + scrollbar_width / 2.0

      # Start drag on horizontal scrollbar
      app.handle_mouse_down(CrymbleUI::Vec2.new(thumb_x, thumb_y))

      # CRITICAL: Drag with REALISTIC JITTER (5px vertical drift)
      drag_target = CrymbleUI::Vec2.new(thumb_x + 50.0, thumb_y - 5.0)
      app.handle_mouse_move(drag_target)
      renderer.render_frame(app)

      app.handle_mouse_up(drag_target)

      # BUG: Y should NOT change even with 5px vertical jitter!
      scroll_view.scroll_offset.y.should eq initial_y
      scroll_view.scroll_offset.x.should be > initial_x
    end
  end

  # === Bug (d): Horizontal Touchpad Scroll Broken ===
  # Root cause: Logic `delta.y != 0 ? delta.y : delta.x` prefers Y over X

  describe "Bug (d): Horizontal touchpad scroll" do
    it "pure horizontal touchpad swipe (delta.x only) scrolls horizontal scrollview" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      20.times { hstack.add_child(CrymbleUI::Button.new("Wide Button") { }) }
      scroll_view.set_content(hstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x

      # Pure horizontal touchpad swipe: delta.x = -1.0, delta.y = 0.0
      point = CrymbleUI::Vec2.new(200.0, 150.0)
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.0), point, shift: false)

      # BUG: Currently prefers delta.y, so delta.x=0 check fails
      scroll_view.scroll_offset.x.should be > initial_x
    end

    it "touchpad with BOTH deltas uses larger magnitude for horizontal scrollview" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      20.times { hstack.add_child(CrymbleUI::Button.new("Wide Button") { }) }
      scroll_view.set_content(hstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x

      # Touchpad with BOTH deltas: delta.x = -1.0 (horizontal), delta.y = 0.01 (tiny vertical)
      # Should use the larger magnitude (delta.x)
      point = CrymbleUI::Vec2.new(200.0, 150.0)
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.01), point, shift: false)

      # BUG: Currently prefers delta.y even though delta.x has larger magnitude
      scroll_view.scroll_offset.x.should be > initial_x
    end

    it "vertical wheel does NOT scroll horizontal scrollview (strict axis matching)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      20.times { hstack.add_child(CrymbleUI::Button.new("Wide Button") { }) }
      scroll_view.set_content(hstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x

      # Vertical wheel (most common): delta.y = -5.0, delta.x = 0.0
      point = CrymbleUI::Vec2.new(200.0, 150.0)
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -5.0), point, shift: false)

      # Strict behavior: horizontal scrollview ignores vertical wheel
      # Use shift+vertical wheel or horizontal wheel to scroll horizontally
      scroll_view.scroll_offset.x.should eq initial_x
    end

    it "shift+vertical wheel scrolls horizontal scrollview" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
      hstack = CrymbleUI::HStack.new(spacing: 5.0)
      20.times { hstack.add_child(CrymbleUI::Button.new("Wide Button") { }) }
      scroll_view.set_content(hstack)

      window.add_child(scroll_view)
      app.root_widget = window
      renderer.render_frame(app)

      initial_x = scroll_view.scroll_offset.x

      # Shift+vertical wheel swaps axes: becomes horizontal scroll
      point = CrymbleUI::Vec2.new(200.0, 150.0)
      scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -5.0), point, shift: true)

      # With shift, vertical wheel becomes horizontal scroll
      scroll_view.scroll_offset.x.should be > initial_x
    end
  end
end
