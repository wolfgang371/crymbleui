require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/layout/vstack"
require "../../src/widgets/text"

# A WindowPanel built (or zoomed) narrower than its content floors WIDER (content-aware floor). The
# title-bar chrome must fill that grown width. Regression: perform_layout laid out the chrome at the
# pre-grow width and only afterwards grew width to the content floor, leaving a stale background strip
# on the right of the title bar (seen live as a white strip after Ctrl+Plus, which grows the content
# past the panel's width). Fix: apply the width floor BEFORE laying out the chrome.
class NarrowFloorPanelApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("T", 900, 600) do
      window_panel(title: "Info", id: "info", x: 100.0, y: 100.0, width: 120.0, height: 240.0) do
        vstack(spacing: 4.0) do
          text("Framework: CrymbleUI")
          text("Open Panels: 3")
        end
      end
    end
  end
end

describe "WindowPanel title bar fills the content-floored width" do
  it "leaves no stale background strip on the right of the title bar" do
    CrymbleUI::FontSizing.reset_zoom
    renderer = CrymbleUI::Testing::TestRenderer.new(900, 600)
    app = NarrowFloorPanelApp.new
    app.build_tree
    renderer.settle_rendering(app)

    panel = app.find("info").as(CrymbleUI::WindowPanel)
    active = CrymbleUI::Theme.current.panel_title_bar_active
    w = panel.width
    y = (panel.y + panel.title_bar_height / 2).to_i

    is_active = ->(x : Int32) do
      px = renderer.backend.get_pixel(x, y)
      !px.nil? && px.r == active.r && px.g == active.g && px.b == active.b
    end
    last_blue = (panel.x.to_i..(panel.x + w).to_i).select { |x| is_active.call(x) }.max? || -1

    w.should be > 120.0 # precondition: the panel floored wider than its built 120px
    # The title-bar blue must reach the panel's right edge (allow 2px for the 1px chrome border).
    ((panel.x + w) - last_blue).should be <= 3.0
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end
end
