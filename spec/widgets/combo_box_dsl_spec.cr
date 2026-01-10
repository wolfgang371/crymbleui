require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# DSL-style App that creates NEW widget instances on each build()
# This mimics real DSL apps like ComboBoxDemo
class DSLComboBoxApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    # Create NEW instances each time (DSL behavior)
    window = CrymbleUI::Window.new("Test", 400, 300)
    vstack = CrymbleUI::VStack.new
    combo = CrymbleUI::ComboBox.new(items: ["Apple", "Banana", "Cherry"], selected: 0, width: 200.0, id: "combo")

    vstack.children << combo
    combo.parent = vstack
    window.children << vstack
    vstack.parent = window

    window
  end
end

describe "ComboBox DSL-style behavior" do
  # NEW ARCHITECTURE: Clicking on collapsed ComboBox expands it
  # The popup contains TextInput (not ComboBox directly)
  it "popup TextInput receives focus after DSL rebuild" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = DSLComboBoxApp.new
    app.build_tree  # Initial build
    renderer.render_frame(app)

    # Find ComboBox
    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Click on ComboBox to expand (NEW: clicking opens popup)
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    # NEW: Popup should be open with TextInput focused
    combo.popup_open?.should be_true
    popup = combo.current_popup.not_nil!
    popup.text_input.focused?.should be_true

    # Type 'A' to filter
    CrymbleUI::Widget.focus_manager.handle_text_input('A')
    renderer.render_frame(app)

    # Now trigger a DSL rebuild
    app.rebuild
    renderer.render_frame(app)

    # Get the NEW combo (after rebuild)
    new_combo = app.find("combo").as(CrymbleUI::ComboBox)
    new_popup = new_combo.current_popup

    # Popup should still be open (migrated via copy_state_from)
    new_combo.popup_open?.should be_true
    new_popup.should_not be_nil

    # Type another character - should work
    CrymbleUI::Widget.focus_manager.handle_text_input('p')
    renderer.render_frame(app)

    # TextInput text should be "Ap" (A + p)
    new_popup.not_nil!.text_input.value.should eq "Ap"
  end

  it "preserves typed text during DSL rebuild when popup is open" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = DSLComboBoxApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Click to expand (NEW: clicking opens popup)
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    # Type 'B' to filter
    CrymbleUI::Widget.focus_manager.handle_text_input('B')
    renderer.render_frame(app)

    # Verify popup is open and text is 'B'
    combo.popup_open?.should be_true
    combo.current_popup.not_nil!.text_input.value.should eq "B"

    # Trigger DSL rebuild
    app.rebuild
    renderer.render_frame(app)

    # Get NEW combo after rebuild
    new_combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Popup should still be open with preserved text
    new_combo.popup_open?.should be_true
    new_combo.current_popup.not_nil!.text_input.value.should eq "B"
  end

  it "closes popup on Escape key" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = DSLComboBoxApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Click to expand
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    # Re-find combo after rebuild (DSL creates new instances!)
    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Popup should be open
    combo.popup_open?.should be_true

    # Press Escape to close
    CrymbleUI::Widget.focus_manager.handle_key_down(:escape, false, false)
    renderer.render_frame(app)

    # Re-find combo after rebuild
    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Popup should be closed
    combo.popup_open?.should be_false
  end

  it "popup survives DSL rebuild" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = DSLComboBoxApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Click to expand (NEW: clicking alone opens popup)
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    # Popup should be open
    combo.popup_open?.should be_true
    window = app.root.as(CrymbleUI::Window)
    window.overlays.size.should eq 1

    # Trigger rebuild
    app.rebuild
    renderer.render_frame(app)

    # Popup should STILL be open (migrated via copy_state_from and Window.overlays migration)
    new_combo = app.find("combo").as(CrymbleUI::ComboBox)
    new_window = app.root.as(CrymbleUI::Window)

    new_combo.popup_open?.should be_true
    new_window.overlays.size.should eq 1
  end
end
