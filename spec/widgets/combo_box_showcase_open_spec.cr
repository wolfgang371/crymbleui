require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/window_panel"
require "../../src/widgets/text"
require "../../src/layout/vstack"
require "../../src/layout/hstack"
require "../../src/testing/test_renderer"
require "../../src/testing/gui_test_helpers"

# / fta_combo_showcase: verify the showcase ComboBox "opens then immediately closes"
# regression is not live, headlessly, in the showcase CONTEXT — a ComboBox in an HStack inside a
# WindowPanel, with an on_select that flips the Theme. Faithful path: real App mouse dispatch +
# the SFML rebuild-on-needs_layout loop, pumped several frames (the "closes a few frames later"
# window). Asserts the popup STAYS open AND its items actually render (pixels), not just popup_open?.
private SHOWCASE_THEMES = ["Light", "Dark"]

class ShowcaseComboApp < CrymbleUI::App
  property combo_index : Int32 = 0

  def build : CrymbleUI::Widget
    window("Showcase", 950, 780) do
      window_panel("Controls", 20.0, 20.0, 420.0, 220.0, id: "panel") do
        vstack(padding: 12.0, spacing: 8.0) do
          text("Controls", font_scale: 1)
          hstack(spacing: 10.0) do
            text("Theme:", font_scale: -1)
            combo_box(items: SHOWCASE_THEMES, selected: @combo_index, id: "theme_combo") do |idx, _val|
              CrymbleUI::Theme.set(idx == 0 ? :light : :dark)
              self.combo_index = idx
            end
          end
        end
      end
    end
  end
end

private def pump(app, renderer, frames = 5)
  frames.times do
    app.rebuild if app.root.try(&.needs_layout?)
    renderer.render_frame(app)
  end
end

private def item_has_dark_pixels?(item) : Bool
  wb = item.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
  return false unless wb
  (5..40).each do |x|
    (5..25).each do |y|
      if (p = wb.get_pixel(x, y)) && p.r < 50 && p.g < 50 && p.b < 50
        return true
      end
    end
  end
  false
end

describe "showcase ComboBox opens and STAYS open (fta_combo_showcase)" do
  it "click-to-open leaves the popup open with rendered items (no immediate close)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(950, 780)
    app = ShowcaseComboApp.new
    app.build_tree
    renderer.settle_rendering(app)

    combo = app.find("theme_combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.collapsed?.should be_true

    abs = combo.absolute_bounds
    click = CrymbleUI::Vec2.new(abs.x + abs.width / 2, abs.y + abs.height / 2)
    app.handle_mouse_down(click)
    app.handle_mouse_up(click)

    pump(app, renderer, 5) # SFML loop: rebuild-on-needs_layout + render, several frames

    combo = app.find("theme_combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true # must NOT have immediately closed

    popup = combo.current_popup.not_nil!
    popup.item_widgets.size.should eq(SHOWCASE_THEMES.size)
    popup.item_widgets.each do |item|
      item_has_dark_pixels?(item).should be_true, "item '#{item.label}' text not rendered"
    end
  end
end
