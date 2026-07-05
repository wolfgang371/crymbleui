require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_popup"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# Helper methods for interaction tests
def click_on(app, widget)
  bounds = widget.absolute_bounds
  center = CrymbleUI::Vec2.new(bounds.x + bounds.width/2, bounds.y + bounds.height/2)
  app.handle_mouse_down(center)
  app.handle_mouse_up(center)
end

def press_key(key : SF::Keyboard::Key, control = false, shift = false)
  CrymbleUI::Widget.focus_manager.handle_key_down(key, control, shift)
end

# DSL-style app that creates NEW instances on each build() (like real apps)
class ComboBoxDSLApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property selected_value : String = ""
  property selected_index : Int32 = 0

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      vstack do
        combo_box(
          items: ["Apple", "Banana", "Cherry"],
          selected: self.selected_index,
          width: 150.0,
          id: "test_combo"
        ) do |idx, val|
          self.selected_index = idx
          self.selected_value = val
        end
      end
    end
  end
end

# DSL-style app with MANY items for scroll testing
class ComboBoxManyItemsApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property selected_value : String = ""
  property selected_index : Int32 = 0

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      vstack do
        combo_box(
          items: (1..20).map { |i| "Item #{i}" },
          selected: self.selected_index,
          width: 150.0,
          id: "test_combo"
        ) do |idx, val|
          self.selected_index = idx
          self.selected_value = val
        end
      end
    end
  end
end

describe "ComboBox interaction bugs (DSL-style)" do
  # Bug (a): Arrow keys should navigate highlight without freezing
  describe "arrow key navigation" do
    it "arrow down moves highlight and ESC still works" do
      app = ComboBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      # Open popup by clicking
      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      click_on(app, combo)
      renderer.settle_rendering(app)

      # Re-find after rebuild
      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      combo.popup_open?.should be_true, "Popup should be open"
      popup = combo.current_popup.not_nil!
      popup.highlighted_index.should eq 0

      # Press Down arrow
      press_key(SF::Keyboard::Key::Down)
      renderer.settle_rendering(app)

      # Re-find and verify highlight moved
      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      combo.popup_open?.should be_true, "Popup should still be open after arrow key"
      popup = combo.current_popup.not_nil!
      popup.highlighted_index.should eq 1

      # ESC should still work (verify not frozen)
      press_key(SF::Keyboard::Key::Escape)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      combo.popup_open?.should be_false, "ESC should close popup (not frozen)"
    end

    it "arrow up moves highlight" do
      app = ComboBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      click_on(app, combo)
      renderer.settle_rendering(app)

      # Move down first, then up
      press_key(SF::Keyboard::Key::Down)
      press_key(SF::Keyboard::Key::Down)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      popup = combo.current_popup.not_nil!
      popup.highlighted_index.should eq 2

      press_key(SF::Keyboard::Key::Up)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      popup = combo.current_popup.not_nil!
      popup.highlighted_index.should eq 1
    end
  end

  # Bug (b): Single Enter should select, not require double press
  describe "Enter key selection" do
    it "single Enter selects highlighted item and closes popup" do
      app = ComboBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      click_on(app, combo)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      combo.popup_open?.should be_true

      # Press Enter ONCE - should select and close
      press_key(SF::Keyboard::Key::Enter)
      renderer.settle_rendering(app)

      # Verify: selection made AND popup closed
      app.selected_value.should eq("Apple")
      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      combo.popup_open?.should be_false, "Single Enter should close popup"
    end

    it "arrow + Enter selects navigated item" do
      app = ComboBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      click_on(app, combo)
      renderer.settle_rendering(app)

      # Navigate to Banana (index 1)
      press_key(SF::Keyboard::Key::Down)
      renderer.settle_rendering(app)

      # Press Enter to select
      press_key(SF::Keyboard::Key::Enter)
      renderer.settle_rendering(app)

      app.selected_value.should eq("Banana")
    end
  end

  # Bug (c): Scrolled items should be clipped, not overpaint TextInput
  describe "scroll clipping" do
    it "scrolled items don't render above TextInput" do
      app = ComboBoxManyItemsApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      click_on(app, combo)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      popup = combo.current_popup.not_nil!
      text_input = popup.text_input

      # Scroll down several times
      popup_center = CrymbleUI::Vec2.new(
        popup.absolute_bounds.x + popup.bounds.width / 2,
        popup.absolute_bounds.y + popup.bounds.height / 2
      )
      5.times do
        app.handle_mouse_wheel(CrymbleUI::Vec2.new(0.0, -3.0), popup_center)
      end
      renderer.settle_rendering(app)

      # Re-find popup (may have rebuilt)
      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      popup = combo.current_popup.not_nil!

      # Check items with negative Y bounds (scrolled above viewport)
      # These should either: not exist, have zero height, or be clipped
      text_input_bottom = popup.text_input.bounds.y + popup.text_input.bounds.height
      items_above_text = popup.item_widgets.count do |item|
        item.bounds.y < 0  # Item position is above VStack origin
      end

      # If items have negative Y, they MUST be clipped (not rendered)
      # This test checks that items don't visually overpaint TextInput
      # We verify by checking that no item's absolute_bounds overlaps TextInput
      popup.item_widgets.each do |item|
        item_abs = item.absolute_bounds
        text_abs = popup.text_input.absolute_bounds
        # Item should not overlap with TextInput's area
        overlaps = !(item_abs.x + item_abs.width <= text_abs.x ||
                     text_abs.x + text_abs.width <= item_abs.x ||
                     item_abs.y + item_abs.height <= text_abs.y ||
                     text_abs.y + text_abs.height <= item_abs.y)
        overlaps.should be_false, "Item '#{item.label_text}' at #{item_abs} overlaps TextInput at #{text_abs}"
      end
    end
  end

  # Bug (d): Only one item should show hover highlight at a time
  describe "hover highlight" do
    it "only one item shows hover at a time" do
      app = ComboBoxDSLApp.new
      app.build_tree
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      click_on(app, combo)
      renderer.settle_rendering(app)

      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      popup = combo.current_popup.not_nil!

      # Move mouse to first item
      item0 = popup.item_widgets[0]
      item0_center = CrymbleUI::Vec2.new(
        item0.absolute_bounds.x + item0.bounds.width / 2,
        item0.absolute_bounds.y + item0.bounds.height / 2
      )
      app.handle_mouse_move(item0_center)
      renderer.settle_rendering(app)

      # Now move to second item
      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      popup = combo.current_popup.not_nil!
      item1 = popup.item_widgets[1]
      item1_center = CrymbleUI::Vec2.new(
        item1.absolute_bounds.x + item1.bounds.width / 2,
        item1.absolute_bounds.y + item1.bounds.height / 2
      )
      app.handle_mouse_move(item1_center)
      renderer.settle_rendering(app)

      # Re-find and check hover states
      combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
      popup = combo.current_popup.not_nil!

      # Count items with hover state
      hovered_count = popup.item_widgets.count { |item| app.is_widget_hovered?(item) }
      hovered_count.should eq 1
    end
  end

  # Existing tests below
  it "can click item to select and close popup" do
    app = ComboBoxDSLApp.new
    app.build_tree  # Build widget tree first
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    renderer.settle_rendering(app)

    # Find combo by ID
    combo = app.find("test_combo")
    combo.should_not be_nil, "Could not find combo by ID 'test_combo'"
    combo = combo.not_nil!.as(CrymbleUI::ComboBox)
    combo.should_not be_nil

    # 1. Click to open popup
    combo_center = CrymbleUI::Vec2.new(
      combo.absolute_bounds.x + combo.bounds.width / 2,
      combo.absolute_bounds.y + combo.bounds.height / 2
    )
    app.handle_mouse_down(combo_center)
    app.handle_mouse_up(combo_center)
    renderer.settle_rendering(app)

    # Re-find combo after rebuild (DSL creates new instances!)
    combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true, "Popup should be open after clicking combo"

    popup = combo.current_popup.not_nil!
    popup.item_widgets.size.should eq 3

    # 2. Click on second item (Banana)
    item = popup.item_widgets[1]
    item_center = CrymbleUI::Vec2.new(
      item.absolute_bounds.x + item.bounds.width / 2,
      item.absolute_bounds.y + item.bounds.height / 2
    )

    app.handle_mouse_down(item_center)
    app.handle_mouse_up(item_center)
    renderer.settle_rendering(app)

    # Verify selection and popup closed
    # Re-find combo after rebuild
    combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
    app.as(ComboBoxDSLApp).selected_value.should eq("Banana")
    combo.popup_open?.should be_false, "Popup should be closed after selection"
  end

  it "can click outside to close popup" do
    app = ComboBoxDSLApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    renderer.settle_rendering(app)

    combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)

    # Open popup
    combo_center = CrymbleUI::Vec2.new(
      combo.absolute_bounds.x + combo.bounds.width / 2,
      combo.absolute_bounds.y + combo.bounds.height / 2
    )
    app.handle_mouse_down(combo_center)
    app.handle_mouse_up(combo_center)
    renderer.settle_rendering(app)

    combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    # Click outside popup (but inside window)
    outside = CrymbleUI::Vec2.new(350.0, 250.0)
    app.handle_mouse_down(outside)
    app.handle_mouse_up(outside)
    renderer.settle_rendering(app)

    combo = app.find("test_combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_false, "Popup should close when clicking outside"
  end
end
