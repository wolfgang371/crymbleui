require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/multi_combo_box"
require "../../src/widgets/window"

# MultiComboBox threads per-item `text_background_colors` through to its
# popup rows — mirroring ComboBox (combo_box_spec.cr "passes text_background_colors
# array to popup items"). Embrace uses it to highlight the pinned branch and mute
# the non-mergeable ones in the History branch combo.
describe "MultiComboBox text_background_colors" do
  it "passes the per-item colors array to its popup items" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    colors = [
      CrymbleUI::Color.new(255, 200, 200, 255), # Apple
      CrymbleUI::Color.new(255, 255, 200, 255), # Banana
      CrymbleUI::Color.new(200, 255, 200, 255), # Cherry
    ]
    window = CrymbleUI::Window.new("Test", 400, 300)
    combo = CrymbleUI::MultiComboBox.new(
      items: ["Apple", "Banana", "Cherry"],
      selected: Set{0},
      width: 200.0,
      text_background_colors: colors,
      id: "mc"
    )
    window.add_child(combo)

    app = TestApp.new
    app.root_widget = window
    renderer.render_frame(app)

    abs = combo.absolute_bounds
    pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(pos)
    app.handle_mouse_up(pos)
    renderer.render_frame(app)

    items = combo.current_popup.not_nil!.item_widgets
    items[0].text_background_color.should eq colors[0]
    items[1].text_background_color.should eq colors[1]
    items[2].text_background_color.should eq colors[2]
  end
end
