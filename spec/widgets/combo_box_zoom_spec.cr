require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# DSL-style App that creates NEW widget instances on each build()
# This mimics real DSL apps and tests reconciliation behavior after zoom
class ComboBoxZoomTestApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    # Create NEW instances each time (DSL behavior)
    window = CrymbleUI::Window.new("Test", 400, 300)
    vstack = CrymbleUI::VStack.new
    combo = CrymbleUI::ComboBox.new(
      items: ["Argentina", "Australia", "Austria", "Belgium"],
      selected: 0,
      width: 200.0,
      id: "combo"
    )

    vstack.children << combo
    combo.parent = vstack
    window.children << vstack
    vstack.parent = window

    window
  end
end

describe "ComboBox zoom behavior" do
  it "all dropdown items render at same height after zoom change" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ComboBoxZoomTestApp.new
    app.build_tree
    renderer.render_frame(app)

    # Open dropdown by clicking on ComboBox center
    combo = app.find("combo").as(CrymbleUI::ComboBox)
    click_at(app, combo.absolute_bounds.center)
    renderer.render_frame(app)

    # Re-find combo after rebuild (DSL creates new instances)
    combo = app.find("combo").as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true

    popup = combo.current_popup.not_nil!
    initial_heights = popup.item_widgets.map(&.bounds.height)

    # All initial heights should be equal
    initial_heights.uniq.size.should eq 1
    initial_height = initial_heights.first

    # Zoom in (simulating what SFML renderer does)
    CrymbleUI::FontSizing.zoom_in
    app.root.try(&.mark_needs_layout)  # SFML does this after zoom
    app.rebuild
    renderer.render_frame(app)

    # Re-find combo and popup after rebuild
    combo = app.find("combo").as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true
    new_popup = combo.current_popup.not_nil!
    new_heights = new_popup.item_widgets.map(&.bounds.height)

    # THIS SHOULD FAIL IF BUG EXISTS: All items should have SAME height
    new_heights.uniq.size.should eq 1

    # Heights should be larger than before (zoom increased)
    new_heights.first.should be > initial_height
  end

  it "items maintain equal heights through multiple zoom cycles" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = ComboBoxZoomTestApp.new
    app.build_tree
    renderer.render_frame(app)

    # Open dropdown by clicking on ComboBox center
    combo = app.find("combo").as(CrymbleUI::ComboBox)
    click_at(app, combo.absolute_bounds.center)
    renderer.render_frame(app)

    # Zoom in multiple times (simulating SFML behavior)
    3.times do
      CrymbleUI::FontSizing.zoom_in
      app.root.try(&.mark_needs_layout)
      app.rebuild
      renderer.render_frame(app)
    end

    # Zoom out multiple times
    3.times do
      CrymbleUI::FontSizing.zoom_out
      app.root.try(&.mark_needs_layout)
      app.rebuild
      renderer.render_frame(app)
    end

    # Check final state - all heights should be equal
    combo = app.find("combo").as(CrymbleUI::ComboBox)
    popup = combo.current_popup.not_nil!
    final_heights = popup.item_widgets.map(&.bounds.height)

    # All items should have SAME height after zoom cycles
    final_heights.uniq.size.should eq 1
  end
end
