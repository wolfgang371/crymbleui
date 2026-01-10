require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# DSL-style App that mimics combo_box_demo for gap bug reproduction
class ComboBoxZoomGapTestApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Test", 600, 400)
    vstack = CrymbleUI::VStack.new(spacing: 15.0)

    # Countries list - like in the demo (15 items)
    countries = [
      "Argentina", "Australia", "Austria", "Belgium", "Brazil",
      "Canada", "Chile", "China", "Colombia", "Denmark",
      "France", "Germany", "India", "Japan", "Mexico"
    ]
    combo = CrymbleUI::ComboBox.new(items: countries, selected: 0, width: 300.0, id: "countries")

    vstack.children << combo
    combo.parent = vstack
    window.children << vstack
    vstack.parent = window

    window
  end
end

describe "ComboBox zoom gap bug" do
  # Exact reproduction steps:
  # 1. Open third combobox (click)
  # 2. 4x Ctrl+Plus (zoom in to ~146%)
  # 3. Enter '0' (filters to items starting with '0' - none match)
  # 4. Ctrl+0 (zoom reset to 100%)
  # 5. Backspace → GAP APPEARS
  it "no gap after zoom cycle and backspace" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app = ComboBoxZoomGapTestApp.new
    app.build_tree
    renderer.render_frame(app)

    # 1. Click ComboBox to open popup
    combo = app.find("countries").as(CrymbleUI::ComboBox)
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    combo.popup_open?.should be_true
    popup = combo.current_popup.not_nil!

    # 2. Zoom in 4x (Ctrl+Plus)
    4.times do
      CrymbleUI::FontSizing.zoom_in
      app.root.try(&.mark_needs_layout)
      app.rebuild
      renderer.render_frame(app)
    end

    # Re-find after rebuild (DSL creates new instances)
    combo = app.find("countries").as(CrymbleUI::ComboBox)
    popup = combo.current_popup.not_nil!

    # 3. Type '0' (filters to empty - no items start with '0')
    CrymbleUI::Widget.focus_manager.handle_text_input('0')
    renderer.render_frame(app)

    # Verify filter worked - no items match '0'
    popup.filtered_items.size.should eq 0
    popup.item_widgets.size.should eq 0

    # 4. Reset zoom (Ctrl+0)
    CrymbleUI::FontSizing.reset_zoom
    app.root.try(&.mark_needs_layout)
    app.rebuild
    renderer.render_frame(app)

    # Re-find after rebuild
    combo = app.find("countries").as(CrymbleUI::ComboBox)
    popup = combo.current_popup.not_nil!

    # 5. Backspace (clears filter, items reappear)
    CrymbleUI::Widget.focus_manager.handle_key_down(SF::Keyboard::Key::Backspace, false, false)
    renderer.render_frame(app)

    # Items should be back
    popup.filtered_items.size.should eq 15

    # Calculate gaps
    text_input = popup.text_input
    scroll_view = popup.children[1].as(CrymbleUI::ScrollView)
    first_item = popup.item_widgets.first?

    text_input_bottom = text_input.absolute_bounds.y + text_input.absolute_bounds.height
    scroll_view_top = scroll_view.absolute_bounds.y
    text_scroll_gap = scroll_view_top - text_input_bottom

    # ASSERTION: Gap between TextInput bottom and ScrollView top should be 0 (or minimal)
    text_scroll_gap.should be_close(0.0, 2.0), "Gap between TextInput and ScrollView: #{text_scroll_gap}"

    # ASSERTION: First item should be at ScrollView top (no gap)
    if item = first_item
      first_item_top = item.absolute_bounds.y
      scroll_item_gap = first_item_top - scroll_view_top
      scroll_item_gap.should be_close(0.0, 2.0), "Gap between ScrollView and first item: #{scroll_item_gap}"
    end
  end

  # Compare with baseline (no zoom cycle) to see if gap only appears after zoom
  it "no gap without zoom cycle (baseline)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app = ComboBoxZoomGapTestApp.new
    app.build_tree
    renderer.render_frame(app)

    # 1. Click ComboBox to open popup
    combo = app.find("countries").as(CrymbleUI::ComboBox)
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    popup = combo.current_popup.not_nil!

    # Skip zoom steps - just type and backspace

    # Type '0' (filters to empty)
    CrymbleUI::Widget.focus_manager.handle_text_input('0')
    renderer.render_frame(app)

    # Backspace (clears filter)
    CrymbleUI::Widget.focus_manager.handle_key_down(SF::Keyboard::Key::Backspace, false, false)
    renderer.render_frame(app)

    # Verify items are back
    popup.filtered_items.size.should eq 15

    # Calculate gap
    text_input = popup.text_input
    scroll_view = popup.children[1].as(CrymbleUI::ScrollView)

    text_input_bottom = text_input.absolute_bounds.y + text_input.absolute_bounds.height
    scroll_view_top = scroll_view.absolute_bounds.y
    text_scroll_gap = scroll_view_top - text_input_bottom

    # Should be no gap
    text_scroll_gap.should be_close(0.0, 2.0)
  end
end
