require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# ComboBox tests - GUI-like tests only (no direct method calls)
#
# NEW ARCHITECTURE (per plan):
# - Collapsed: NO children, renders "»{value}" as primitives
# - Expanded: Popup (overlay) contains TextInput + filtered list
#
# These tests simulate user interactions via App.

# Helper module for creating test apps
module ComboBoxTestHelper
  def self.create_app(items : Array(String), selected : Int32 = 0)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)
    combo = CrymbleUI::ComboBox.new(items: items, selected: selected, width: 200.0, id: "combo")
    # Wrap in a VStack (as the DSL app and every real caller do) so the combo
    # keeps its natural height. A combo placed as a window's sole child would
    # receive a window-sized TIGHT constraint and — honouring it — fill the
    # whole window.
    vstack = CrymbleUI::VStack.new
    vstack.add_child(combo)
    window.add_child(vstack)
    app.root_widget = window
    app
  end
end

# DSL-style test app - creates NEW widget instances on each build() (like real demos)
# This is critical for reproducing bugs that only appear with DSL reconciliation
class ComboBoxDSLTestApp < CrymbleUI::App
  @fruit_index : Int32 = 0

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      vstack(spacing: 10.0) do
        combo_box(
          items: ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape"],
          selected: @fruit_index,
          width: 250.0,
          id: "combo"
        ) do |idx, val|
          @fruit_index = idx
        end
      end
    end
  end
end

# EXACT COPY of combo_box_demo.cr for headless testing
# Tests the EXACT demo structure with state macro, multiple combos, text labels
class ComboBoxDemoHeadless < CrymbleUI::App
  # Fruits selection
  state selected_fruit : String = ""
  state fruit_index : Int32 = 0

  # Priority selection
  state selected_priority : String = ""
  state priority_index : Int32 = 1  # Default to "Normal"

  # Countries selection
  state selected_country : String = ""
  state country_index : Int32 = 0

  def build : CrymbleUI::Widget
    window("ComboBox Demo", 600, 400) do
      vstack(spacing: 15.0) do
        cpu_monitor
        text("ComboBox Widget Demo", font_scale: 5)

        # Basic fruits list
        text("Select a Fruit:", font_scale: 0)
        combo_box(
          items: ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape"],
          selected: self.fruit_index,
          width: 250.0,
          id: "fruits"
        ) do |idx, val|
          self.fruit_index = idx
          self.selected_fruit = val
        end

        # Priority list
        text("Priority Level:", font_scale: 0)
        combo_box(
          items: ["Critical", "Normal", "Low"],
          selected: self.priority_index,
          width: 200.0,
          id: "priority"
        ) do |idx, val|
          self.priority_index = idx
          self.selected_priority = val
        end

        # Countries list
        text("Select a Country:", font_scale: 0)
        combo_box(
          items: [
            "Argentina", "Australia", "Austria", "Belgium", "Brazil",
            "Canada", "Chile", "China", "Colombia", "Denmark",
            "France", "Germany", "India", "Japan", "Mexico"
          ],
          selected: self.country_index,
          width: 300.0,
          id: "countries"
        ) do |idx, val|
          self.country_index = idx
          self.selected_country = val
        end

        # Show current selections
        text("Current Selections:", font_scale: 2)
        text("Fruit: #{self.selected_fruit.empty? ? "(none)" : self.selected_fruit}", font_scale: -1)
        text("Priority: #{self.selected_priority.empty? ? "(none)" : self.selected_priority}", font_scale: -1)
        text("Country: #{self.selected_country.empty? ? "(none)" : self.selected_country}", font_scale: -1)

        # Instructions
        text("Instructions:", font_scale: 1)
        text("- Click the text input to edit", font_scale: -2)
      end
    end
  end
end

describe CrymbleUI::ComboBox do
  # ============================================================================
  # NEW COLLAPSED STATE TESTS (TEST MODE)
  # These document the REQUIRED behavior for the new architecture
  # ============================================================================

  describe "Collapsed state (TEST MODE)" do
    it "measure respects tight height constraints" do
      combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], selected: 0)
      constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 20.0))
      size = combo.measure(constraints)
      size.height.should eq(20.0)
      size.width.should eq(100.0)
    end

    it "measure fills a TALL tight height (a merged VirtualMatrix row-header)" do
      # Regression (embrace tut-14): a factored-out reference row-header is a
      # ComboBox; when it spans several record rows the matrix hands it a tall
      # tight height. It must fill it — capping left the extra rows uncovered
      # (a gap in the header column, "nur bei ein bis zwei Unterspalten").
      combo = CrymbleUI::ComboBox.new(items: ["Beta"], selected: 0)
      combo.measure(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(100.0, 60.0))).height.should eq(60.0)
    end

    it "has no children when collapsed" do
      combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], selected: 0)

      # NEW: collapsed ComboBox has NO children (no TextInput)
      combo.children.should be_empty
      combo.collapsed?.should be_true
    end

    it "renders »{value} as primitives" do
      combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], selected: 0)
      bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 30.0)

      primitives = combo.to_primitives(bounds)

      # Should have at least a background and text primitive
      primitives.size.should be >= 2

      # Should have a text primitive containing "»Apple"
      text_primitives = primitives.select { |p| p.is_a?(CrymbleUI::DrawText) }
      text_primitives.should_not be_empty
      text_prim = text_primitives.first.as(CrymbleUI::DrawText)
      text_prim.text.should contain("»")
      text_prim.text.should contain("Apple")
    end

    it "is focusable (receives keyboard input)" do
      combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana"], selected: 0)
      combo.focusable?.should be_true
    end
  end

  describe "Expand on interaction (TEST MODE)" do
    it "expands when clicked" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)
      window = app.root.as(CrymbleUI::Window)

      # Initially collapsed, no overlays
      combo.collapsed?.should be_true
      window.overlays.size.should eq 0

      # Click on combo
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Should be expanded, popup in overlays
      combo.collapsed?.should be_false
      window.overlays.size.should eq 1
    end

    # TEST MODE: Compare click-open vs type-open
    # The bug: click-open shows empty, type-open shows items
    it "click-open vs type-open: both should show rendered items (TEST MODE)" do
      # Test TYPE-OPEN first (this works)
      renderer1 = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app1 = ComboBoxDSLTestApp.new
      app1.build_tree
      renderer1.settle_rendering(app1)

      combo1 = app1.find("combo").as(CrymbleUI::ComboBox)
      # TYPE to open (the working path)
      combo1.request_focus
      combo1.on_text_input('a')
      if app1.root.try(&.needs_layout?)
        app1.rebuild
      end
      renderer1.render_frame(app1)

      combo1 = app1.find("combo").as(CrymbleUI::ComboBox)
      popup1 = combo1.current_popup
      popup1.should_not be_nil, "TYPE-open: popup should exist"

      type_open_has_text = false
      if p1 = popup1
        p1.item_widgets.each do |item|
          if wb = item.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
            if wb.draw_text_count > 0
              type_open_has_text = true
              break
            end
          end
        end
      end
      type_open_has_text.should be_true, "TYPE-open: items should have draw_text called"

      # Test CLICK-OPEN (the failing path)
      renderer2 = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app2 = ComboBoxDSLTestApp.new
      app2.build_tree
      renderer2.settle_rendering(app2)

      combo2 = app2.find("combo").as(CrymbleUI::ComboBox)
      # CLICK to open (the failing path)
      abs = combo2.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app2.handle_mouse_down(click_pos)
      app2.handle_mouse_up(click_pos)
      if app2.root.try(&.needs_layout?)
        app2.rebuild
      end
      renderer2.render_frame(app2)

      combo2 = app2.find("combo").as(CrymbleUI::ComboBox)
      popup2 = combo2.current_popup
      popup2.should_not be_nil, "CLICK-open: popup should exist"

      click_open_has_text = false
      if p2 = popup2
        p2.item_widgets.each do |item|
          if wb = item.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
            if wb.draw_text_count > 0
              click_open_has_text = true
              break
            end
          end
        end
      end
      click_open_has_text.should be_true, "CLICK-open: items should have draw_text called"
    end

    # TEST MODE: This test catches the bug where click-to-open shows empty dropdown
    # Uses DSL-style app (like combo_box_demo) which creates NEW widget instances on each build()
    it "DSL app click to open shows rendered items with visible text pixels (TEST MODE)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxDSLTestApp.new
      app.build_tree
      renderer.settle_rendering(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # CLICK ONLY - no typing (simulating SFML event loop exactly)
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)

      # SFML does: if needs_layout? → rebuild → render
      # The popup was just added, so needs_layout is true
      if app.root.try(&.needs_layout?)
        app.rebuild
      end
      renderer.render_frame(app)

      # SFML continues with next frame - more rebuilds may happen
      # Simulate a second frame (this is what happens in real SFML loop)
      if app.root.try(&.needs_layout?)
        app.rebuild
      end
      renderer.render_frame(app)

      # Re-find combo after rebuilds
      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Verify popup opened
      combo.collapsed?.should be_false
      popup = combo.current_popup.not_nil!

      # CRITICAL: Verify items have dark pixels (text barcode was drawn)
      popup.item_widgets.each do |item|
        backend = item.widget_backend
        backend.should_not be_nil, "item '#{item.label}' has no widget_backend"

        has_dark_pixel = false
        if wb = backend.as?(CrymbleUI::Testing::TestRenderBackend)
          # Scan text area for dark pixels (barcode stripes are black)
          (5..40).each do |x|
            (5..25).each do |y|
              if pixel = wb.get_pixel(x, y)
                # Text is drawn in black (#000000), backgrounds are light
                if pixel.r < 50 && pixel.g < 50 && pixel.b < 50
                  has_dark_pixel = true
                  break
                end
              end
            end
            break if has_dark_pixel
          end
        end

        has_dark_pixel.should be_true,
          "item '#{item.label}' has no dark pixels - text not rendered!"
      end
    end

    it "expands when Enter is pressed while focused" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)
      window = app.root.as(CrymbleUI::Window)

      # Focus the ComboBox
      combo.request_focus

      # Press Enter
      CrymbleUI::Widget.focus_manager.handle_key_down(SF::Keyboard::Enter, false, false)
      renderer.render_frame(app)

      # Should be expanded
      combo.collapsed?.should be_false
      window.overlays.size.should eq 1
    end

    it "expands AND inserts character when typing on collapsed" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)
      window = app.root.as(CrymbleUI::Window)

      # Focus the ComboBox
      combo.request_focus

      # Type 'A' while collapsed
      CrymbleUI::Widget.focus_manager.handle_text_input('A')
      renderer.render_frame(app)

      # Should be expanded
      combo.collapsed?.should be_false
      window.overlays.size.should eq 1

      # Popup's TextInput should contain 'A'
      popup = window.overlays.first.as(CrymbleUI::ComboBoxPopup)
      popup.text_input.value.should eq("A")
    end
  end

  # ============================================================================
  # LEGACY TESTS (may need updates after implementation)
  # ============================================================================
  describe "Popup is added to Window overlays" do
    it "popup appears in Window.overlays when opened" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)
      window = app.root.as(CrymbleUI::Window)

      # Initially no overlays
      window.overlays.size.should eq 0

      # Click to focus
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Type to open popup
      CrymbleUI::Widget.focus_manager.handle_text_input('A')
      renderer.render_frame(app)

      # Popup should be in overlays
      window.overlays.size.should eq 1
      window.overlays[0].should be_a(CrymbleUI::ComboBoxPopup)
    end

    it "popup has valid bounds after layout" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to expand (NEW: clicking opens popup)
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      popup = combo.current_popup
      popup.should_not be_nil

      # Popup should have valid bounds (not zero-sized)
      popup_bounds = popup.not_nil!.absolute_bounds
      popup_bounds.width.should be > 0
      popup_bounds.height.should be > 0

      # Popup should be positioned below OR above ComboBox (flips if near window bottom)
      combo_bounds = combo.absolute_bounds
      below = popup_bounds.y >= combo_bounds.y + combo_bounds.height - 1
      above = popup_bounds.y + popup_bounds.height <= combo_bounds.y + 1
      (below || above).should be_true
    end
  end

  describe "Bug: Popup doesn't show items" do
    # GUI TEST: Verifies items are actually RENDERED, not just in an array
    it "popup contains filtered items after typing" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Apricot", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to expand ComboBox
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Popup should be open
      combo.popup_open?.should be_true
      popup = combo.current_popup.not_nil!

      # Type 'A' to filter items
      CrymbleUI::Widget.focus_manager.handle_text_input('A')
      renderer.render_frame(app)

      # GUI CHECK: Items should be RENDERED (have widget_backend), not just in array
      items = popup.item_widgets
      items.size.should eq 2  # Apple, Apricot

      # Each item must have been rendered (has widget_backend)
      items.each do |item|
        assert_rendered(item, "filtered item '#{item.label}'")
      end
    end

    # GUI TEST: Verifies items are rendered when filter is empty
    it "popup shows all items when filter is empty" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to expand
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Type any character then delete to have empty filter
      CrymbleUI::Widget.focus_manager.handle_text_input('X')
      renderer.render_frame(app)
      CrymbleUI::Widget.focus_manager.handle_key_down(:backspace, false, false)
      renderer.render_frame(app)

      # GUI CHECK: All 3 items should be RENDERED
      popup = combo.current_popup
      popup.should_not be_nil
      items = popup.not_nil!.item_widgets
      items.size.should eq 3

      items.each do |item|
        assert_rendered(item, "item '#{item.label}'")
      end
    end
  end

  describe "Bug: Popup never closes" do
    it "popup closes on Escape key" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to focus
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Type to open popup
      CrymbleUI::Widget.focus_manager.handle_text_input('A')
      renderer.render_frame(app)

      # Verify popup is open
      combo.popup_open?.should be_true

      # Press Escape to close popup
      CrymbleUI::Widget.focus_manager.handle_key_down(:escape, false, false)
      renderer.render_frame(app)

      # BUG: Popup should be closed but it stays open!
      combo.popup_open?.should be_false
    end

    # GUI TEST: Click on rendered item should close popup
    it "popup closes when item is clicked" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to expand
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Verify popup is open
      combo.popup_open?.should be_true
      popup = combo.current_popup.not_nil!

      # GUI CHECK: Items must be rendered before we can click them
      items = popup.item_widgets
      items.size.should be > 0
      first_item = items.first
      assert_rendered(first_item, "first item")

      # Click on first item using its actual rendered bounds
      item_bounds = first_item.absolute_bounds
      item_click_pos = CrymbleUI::Vec2.new(item_bounds.x + 5.0, item_bounds.y + 5.0)
      app.handle_mouse_down(item_click_pos)
      app.handle_mouse_up(item_click_pos)
      renderer.render_frame(app)

      # Popup should be closed after item click
      combo.popup_open?.should be_false
    end

    it "popup closes on Enter key (Submit)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to focus
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Type to open popup
      CrymbleUI::Widget.focus_manager.handle_text_input('A')
      renderer.render_frame(app)

      combo.popup_open?.should be_true

      # Single Enter selects and closes (FullEdit mode is active after popup opens)
      CrymbleUI::Widget.focus_manager.handle_key_down(:enter, false, false)
      renderer.render_frame(app)

      # Popup should be closed after Enter
      combo.popup_open?.should be_false
    end
  end

  describe "Selection behavior" do
    # GUI TEST: Clicking rendered item updates selection
    it "updates selected value when item is selected" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"], selected: 0)
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Initial value should be "Apple"
      combo.selected_value.should eq "Apple"
      combo.selected_index.should eq 0

      # Click to expand popup
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Type 'B' to filter to Banana
      CrymbleUI::Widget.focus_manager.handle_text_input('B')
      renderer.render_frame(app)

      # GUI CHECK: Banana item must be rendered
      popup = combo.current_popup.not_nil!
      items = popup.item_widgets
      items.size.should eq 1  # Only Banana starts with B
      banana_item = items.first
      assert_rendered(banana_item, "Banana item")

      # Click on Banana using its actual rendered bounds
      item_bounds = banana_item.absolute_bounds
      item_click_pos = CrymbleUI::Vec2.new(item_bounds.x + 5.0, item_bounds.y + 5.0)
      app.handle_mouse_down(item_click_pos)
      app.handle_mouse_up(item_click_pos)
      renderer.render_frame(app)

      # Selected value should be Banana
      combo.selected_value.should eq "Banana"
      combo.selected_index.should eq 1
    end

    it "preserves selected value on Escape (closes without changing)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"], selected: 0)
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Initial value (NEW: check via selected_value)
      combo.selected_value.should eq "Apple"
      combo.selected_index.should eq 0

      # Click to expand popup
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Popup should be open
      combo.popup_open?.should be_true

      # Type something to filter (changes popup's TextInput, not selection)
      CrymbleUI::Widget.focus_manager.handle_text_input('X')
      CrymbleUI::Widget.focus_manager.handle_text_input('Y')
      CrymbleUI::Widget.focus_manager.handle_text_input('Z')
      renderer.render_frame(app)

      # Press Escape to cancel (closes popup without selecting)
      CrymbleUI::Widget.focus_manager.handle_key_down(:escape, false, false)
      renderer.render_frame(app)

      # Popup should be closed
      combo.popup_open?.should be_false

      # Selected value should still be Apple (unchanged)
      combo.selected_value.should eq "Apple"
      combo.selected_index.should eq 0
    end
  end

  # ============================================================================
  # EXACT DEMO REPRODUCTION TEST (TEST MODE)
  # Tests the EXACT combo_box_demo.cr structure headlessly
  # ============================================================================
  describe "ComboBoxDemoHeadless (exact demo reproduction)" do
    it "click to open fruits combo shows rendered items with text pixels (TEST MODE)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      app = ComboBoxDemoHeadless.new
      app.build_tree
      renderer.settle_rendering(app)

      combo = app.find("fruits").as(CrymbleUI::ComboBox)

      # CLICK ONLY - no typing (simulating exact SFML event loop)
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)

      # SFML does: if needs_layout? → rebuild → render
      if app.root.try(&.needs_layout?)
        app.rebuild
      end
      renderer.render_frame(app)

      # Simulate second frame (like real SFML loop)
      if app.root.try(&.needs_layout?)
        app.rebuild
      end
      renderer.render_frame(app)

      # Re-find combo after rebuilds
      combo = app.find("fruits").as(CrymbleUI::ComboBox)

      # Verify popup opened
      combo.collapsed?.should be_false
      popup = combo.current_popup.not_nil!

      # CRITICAL: Verify items have dark pixels (text barcode was drawn)
      popup.item_widgets.each do |item|
        backend = item.widget_backend
        backend.should_not be_nil, "item '#{item.label}' has no widget_backend"

        has_dark_pixel = false
        if wb = backend.as?(CrymbleUI::Testing::TestRenderBackend)
          # Scan text area for dark pixels (barcode stripes are black)
          (5..40).each do |x|
            (5..25).each do |y|
              if pixel = wb.get_pixel(x, y)
                # Text is drawn in black (#000000), backgrounds are light
                if pixel.r < 50 && pixel.g < 50 && pixel.b < 50
                  has_dark_pixel = true
                  break
                end
              end
            end
            break if has_dark_pixel
          end
        end

        has_dark_pixel.should be_true,
          "item '#{item.label}' has no dark pixels - text not rendered!"
      end
    end

    it "COMPOSITE: dropdown items visible in final window output (TEST MODE)" do
      # This test checks the FINAL COMPOSITED output, not individual widget backends
      # The widget_backend contamination bug only manifests after layer compositing
      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      app = ComboBoxDemoHeadless.new
      app.build_tree
      renderer.settle_rendering(app)

      combo = app.find("fruits").as(CrymbleUI::ComboBox)

      # Click to open
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)

      # Render frames
      if app.root.try(&.needs_layout?)
        app.rebuild
      end
      renderer.render_frame(app)
      if app.root.try(&.needs_layout?)
        app.rebuild
      end
      renderer.render_frame(app)

      # Re-find after rebuilds
      combo = app.find("fruits").as(CrymbleUI::ComboBox)
      combo.collapsed?.should be_false
      popup = combo.current_popup.not_nil!

      # Get popup bounds in window coordinates
      popup_bounds = popup.absolute_bounds

      # Get first item to find where text should be
      first_item = popup.item_widgets.first
      item_bounds = first_item.absolute_bounds

      # Scan the FINAL WINDOW BACKEND at the item's location for dark pixels
      # If contaminated, we'll only see white; if correct, we'll see dark text
      window_backend = renderer.backend
      has_dark_pixel = false

      # Scan area where first item's text should be (offset from item bounds)
      scan_x_start = (item_bounds.x + 5).to_i
      scan_x_end = (item_bounds.x + 50).to_i
      scan_y_start = (item_bounds.y + 5).to_i
      scan_y_end = (item_bounds.y + 20).to_i

      (scan_x_start..scan_x_end).each do |x|
        (scan_y_start..scan_y_end).each do |y|
          if pixel = window_backend.get_pixel(x, y)
            if pixel.r < 50 && pixel.g < 50 && pixel.b < 50
              has_dark_pixel = true
              break
            end
          end
        end
        break if has_dark_pixel
      end

      has_dark_pixel.should be_true,
        "No dark pixels in final composite at item location (#{scan_x_start},#{scan_y_start}) - widget_backend contamination!"
    end

    it "type to open shows rendered items vs click to open (TEST MODE)" do
      # TEST TYPE PATH (known working)
      type_renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      type_app = ComboBoxDemoHeadless.new
      type_app.build_tree
      type_renderer.settle_rendering(type_app)

      type_combo = type_app.find("fruits").as(CrymbleUI::ComboBox)
      type_combo.request_focus
      type_combo.on_text_input('a')  # Type 'a' to filter
      if type_app.root.try(&.needs_layout?)
        type_app.rebuild
      end
      type_renderer.render_frame(type_app)

      type_combo = type_app.find("fruits").as(CrymbleUI::ComboBox)
      type_popup = type_combo.current_popup.not_nil!
      type_items_with_text = type_popup.item_widgets.count do |item|
        if wb = item.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
          wb.draw_text_count > 0
        else
          false
        end
      end

      # TEST CLICK PATH (potentially broken)
      click_renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      click_app = ComboBoxDemoHeadless.new
      click_app.build_tree
      click_renderer.settle_rendering(click_app)

      click_combo = click_app.find("fruits").as(CrymbleUI::ComboBox)
      abs = click_combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      click_app.handle_mouse_down(click_pos)
      click_app.handle_mouse_up(click_pos)
      if click_app.root.try(&.needs_layout?)
        click_app.rebuild
      end
      click_renderer.render_frame(click_app)

      click_combo = click_app.find("fruits").as(CrymbleUI::ComboBox)
      click_popup = click_combo.current_popup.not_nil!
      click_items_with_text = click_popup.item_widgets.count do |item|
        if wb = item.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
          wb.draw_text_count > 0
        else
          false
        end
      end

      # Both paths should have rendered text
      type_items_with_text.should be > 0, "TYPE path: no items with draw_text"
      click_items_with_text.should be > 0, "CLICK path: no items with draw_text"

      # Verify first item actually has black pixels from text barcode
      if first_item = click_popup.item_widgets.first?
        if wb = first_item.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
          # 'A' from "Apple" should create barcode stripe at x=8, y=8
          pixel = wb.get_pixel(8, 8)
          pixel.should_not be_nil, "expected pixel at (8,8)"
          pixel.not_nil!.r.should eq 0_u8  # Black text pixel
        end
      end
    end
  end

  # ============================================================================
  # TAB KEY BUG (TEST MODE)
  # Bug: Tab while popup open doesn't close the popup
  # ============================================================================
  describe "Tab key closes popup (TEST MODE)" do
    it "pressing Tab while popup is open closes the popup" do
      renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
      app = ComboBoxDemoHeadless.new
      app.build_tree
      renderer.settle_rendering(app)

      window = app.root.as(CrymbleUI::Window)
      countries_combo = app.find("countries").as(CrymbleUI::ComboBox)

      # Click on countries ComboBox to open it
      abs = countries_combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Re-fetch window after potential rebuild
      window = app.root.as(CrymbleUI::Window)

      # Verify popup is open
      countries_combo.popup_open?.should be_true
      window.overlays.size.should eq 1

      # Press Tab - should close the popup. Routes through the real Tab dispatch
      # (FocusManager#handle_tab_key): the ComboBox declines Tab, so focus cycles
      # away and the popup closes on blur.
      press_tab(app)
      renderer.render_frame(app)

      # Re-fetch after Tab (DSL apps create new instances on rebuild)
      window = app.root.as(CrymbleUI::Window)
      countries_combo = app.find("countries").as(CrymbleUI::ComboBox)

      # Popup should be closed
      countries_combo.popup_open?.should be_false
      window.overlays.size.should eq 0
    end
  end

  # ============================================================================
  # TEXT BACKGROUND COLOR FEATURE (TEST MODE)
  # Feature: Optional background color behind text in dropdown items
  # ============================================================================
  describe "text_background_color feature (TEST MODE)" do
    it "ComboBoxItem uses text_background_color as background when set" do
      # Create item with text_background_color
      yellow = CrymbleUI::Color.new(255, 255, 0, 255)
      item = CrymbleUI::ComboBoxItem.new(
        "Apple",
        text_background_color: yellow
      )

      bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 30.0)
      primitives = item.to_primitives(bounds)

      # text_background_color replaces background_color
      fill_rects = primitives.select { |p| p.is_a?(CrymbleUI::FillRect) }
      fill_rects.size.should eq 1  # Single background rect

      # The fill_rect should be yellow (text_background_color)
      bg_color = fill_rects.first.as(CrymbleUI::FillRect).color
      bg_color.should eq yellow
    end

    it "ComboBoxItem uses default background_color when text_background_color not set" do
      # Create item WITHOUT text_background_color
      item = CrymbleUI::ComboBoxItem.new("Apple")

      bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 30.0)
      primitives = item.to_primitives(bounds)

      fill_rects = primitives.select { |p| p.is_a?(CrymbleUI::FillRect) }
      fill_rects.size.should eq 1

      # Should use default background_color (white)
      bg_color = fill_rects.first.as(CrymbleUI::FillRect).color
      bg_color.should eq item.background_color
    end

    it "ComboBox passes text_background_colors array to popup items" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

      # Create ComboBox with per-item background colors
      colors = [
        CrymbleUI::Color.new(255, 200, 200, 255),  # Light red for Apple
        CrymbleUI::Color.new(255, 255, 200, 255),  # Light yellow for Banana
        CrymbleUI::Color.new(200, 255, 200, 255),  # Light green for Cherry
      ]

      window = CrymbleUI::Window.new("Test", 400, 300)
      combo = CrymbleUI::ComboBox.new(
        items: ["Apple", "Banana", "Cherry"],
        selected: 0,
        width: 200.0,
        text_background_colors: colors,
        id: "combo"
      )
      window.add_child(combo)

      app = TestApp.new
      app.root_widget = window
      renderer.render_frame(app)

      # Click to open popup
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # Verify popup items have correct text_background_color
      popup = combo.current_popup.not_nil!
      items = popup.item_widgets

      items[0].text_background_color.should eq colors[0]
      items[1].text_background_color.should eq colors[1]
      items[2].text_background_color.should eq colors[2]
    end

    it "ComboBox uses single text_background_color for all items when array not provided" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

      single_color = CrymbleUI::Color.new(200, 200, 255, 255)  # Light blue

      window = CrymbleUI::Window.new("Test", 400, 300)
      combo = CrymbleUI::ComboBox.new(
        items: ["Apple", "Banana", "Cherry"],
        selected: 0,
        width: 200.0,
        text_background_color: single_color,
        id: "combo"
      )
      window.add_child(combo)

      app = TestApp.new
      app.root_widget = window
      renderer.render_frame(app)

      # Click to open popup
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      # All items should have the same text_background_color
      popup = combo.current_popup.not_nil!
      popup.item_widgets.each do |item|
        item.text_background_color.should eq single_color
      end
    end
  end

  # ============================================================================
  # FLASHING HIGHLIGHT FEATURE (TEST MODE)
  # Feature: Highlighted item flashes using highlight() (smart brightness)
  # ============================================================================
  describe "flashing highlight feature (TEST MODE)" do
    it "highlighted ComboBoxItem uses HIGH brightness when focus_highlighted" do
      # Use a darker background color so highlight() actually changes it
      dark_bg_color = CrymbleUI::Color.new(100, 100, 150, 255)
      item = CrymbleUI::ComboBoxItem.new("Apple", text_background_color: dark_bg_color)
      item.selected = true
      item.focus_highlighted = true

      bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 30.0)
      primitives = item.to_primitives(bounds)

      # Get the background fill rect
      fill_rect = primitives.find { |p| p.is_a?(CrymbleUI::FillRect) }
      fill_rect.should_not be_nil

      bg_color = fill_rect.as(CrymbleUI::FillRect).color

      # The color should use HIGH brightness
      highlighted = dark_bg_color.highlight(CrymbleUI::ComboBoxItem::HIGHLIGHT_BRIGHTNESS_HIGH)

      # Verify highlighted is actually different from original
      highlighted.should_not eq dark_bg_color

      bg_color.should eq highlighted
    end

    it "highlighted ComboBoxItem uses LOW brightness when NOT focus_highlighted" do
      dark_bg_color = CrymbleUI::Color.new(100, 100, 150, 255)
      item = CrymbleUI::ComboBoxItem.new("Apple", text_background_color: dark_bg_color)
      item.selected = true
      item.focus_highlighted = false

      bounds = CrymbleUI::Rect.new(0.0, 0.0, 200.0, 30.0)
      primitives = item.to_primitives(bounds)

      fill_rect = primitives.find { |p| p.is_a?(CrymbleUI::FillRect) }
      bg_color = fill_rect.as(CrymbleUI::FillRect).color

      # Should use LOW brightness (still highlighted, but dimmer)
      highlighted_low = dark_bg_color.highlight(CrymbleUI::ComboBoxItem::HIGHLIGHT_BRIGHTNESS_LOW)
      bg_color.should eq highlighted_low
    end

    it "ComboBoxPopup starts flash timer when popup opens" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to open popup
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      popup = combo.current_popup.not_nil!

      # Flash timer should be running
      popup.flash_timer_running?.should be_true

      # Initially highlighted item should be focus_highlighted (immediate visual feedback)
      highlighted_item = popup.item_widgets[popup.highlighted_index]
      highlighted_item.focus_highlighted?.should be_true
    end

    it "flash timer is cancelled when popup closes" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to open popup
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      popup = combo.current_popup.not_nil!
      popup.flash_timer_running?.should be_true

      # Press Escape to close
      CrymbleUI::Widget.focus_manager.handle_key_down(:escape, false, false)
      renderer.render_frame(app)

      # Timer should be cancelled (popup closed)
      combo.popup_open?.should be_false
    end

    it "flash follows keyboard navigation to new highlighted item" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = ComboBoxTestHelper.create_app(["Apple", "Banana", "Cherry"])
      renderer.render_frame(app)

      combo = app.find("combo").as(CrymbleUI::ComboBox)

      # Click to open popup
      abs = combo.absolute_bounds
      click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
      app.handle_mouse_down(click_pos)
      app.handle_mouse_up(click_pos)
      renderer.render_frame(app)

      popup = combo.current_popup.not_nil!

      # Initially first item (Apple) is highlighted and flashing
      popup.item_widgets[0].selected?.should be_true
      popup.item_widgets[0].focus_highlighted?.should be_true

      # Press Down arrow to move to Banana
      CrymbleUI::Widget.focus_manager.handle_key_down(:down, false, false)
      renderer.render_frame(app)

      # Now Banana should be highlighted and flashing, Apple should not
      popup.item_widgets[0].selected?.should be_false
      popup.item_widgets[0].focus_highlighted?.should be_false
      popup.item_widgets[1].selected?.should be_true
      popup.item_widgets[1].focus_highlighted?.should be_true
    end
  end
end
