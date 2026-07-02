require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"
require "../../src/testing/gui_test_helpers"

# pixel coverage: the core ComboBox flow — clicking an item must change the COLLAPSED
# combo's DISPLAYED TEXT in pixels, not merely the internal selected_index. An internal-state
# test (selected_index == 2) passes even if the collapsed combo never re-renders the new label.
# This drives the real App dispatch and compares the combo's own backend pixels before/after.
class SelectPixelComboApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("SelectPixel", 400, 300) do
      vstack(padding: 20.0, spacing: 8.0) do
        combo_box(items: ["Apple", "Banana", "Cherry"], selected: 0, id: "combo")
      end
    end
  end
end

private def pump_frames(app, renderer, frames = 4)
  frames.times do
    app.rebuild if app.root.try(&.needs_layout?)
    renderer.render_frame(app)
  end
end

# All dark (text) pixels in a widget's own backend, as a comparable set.
private def text_pixels(widget) : Array(Tuple(Int32, Int32))
  result = [] of Tuple(Int32, Int32)
  return result unless wb = widget.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
  (0...wb.width).each do |x|
    (0...wb.height).each do |y|
      if (p = wb.get_pixel(x, y)) && p.r < 50 && p.g < 50 && p.b < 50
        result << {x, y}
      end
    end
  end
  result
end

private def click_widget(app, widget)
  b = widget.absolute_bounds
  c = CrymbleUI::Vec2.new(b.x + b.width / 2, b.y + b.height / 2)
  app.handle_mouse_down(c)
  app.handle_mouse_up(c)
end

describe "ComboBox selection updates the displayed text in pixels" do
  it "selecting 'Cherry' changes the collapsed combo's rendered text (not just selected_index)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = SelectPixelComboApp.new
    app.build_tree
    renderer.settle_rendering(app)

    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    before = text_pixels(combo)
    before.should_not be_empty # "Apple" is drawn

    # Open the popup, then click the "Cherry" row — all through the real App dispatch.
    click_widget(app, combo)
    pump_frames(app, renderer)
    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    popup = combo.current_popup.not_nil!
    cherry = popup.item_widgets[2] # index 2 = "Cherry"
    click_widget(app, cherry)
    pump_frames(app, renderer)

    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_false      # closed after a body click
    combo.selected_index.should eq(2)      # internal state updated...
    after = text_pixels(combo)
    after.should_not be_empty              # ...and the new label is drawn...
    after.should_not eq(before)            # ...AND it visibly differs from "Apple".
  end
end
