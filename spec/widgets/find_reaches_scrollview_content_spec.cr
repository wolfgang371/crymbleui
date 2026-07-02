require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/scroll_view"
require "../../src/layout/vstack"
require "../../src/layout/hstack"

# Verifies the seam the localized stress_panel_demo flash will rely on: App#find(id) must reach a button
# in a FLOORED grid AND a button in a grid inside a ScrollView (materialized content). If find reaches
# both, an App-owned clock can toggle the selected cell's colour by id (localized, no rebuild).

private class FindReachApp < CrymbleUI::App
  private def grid(prefix : String, id : String) : CrymbleUI::VStack
    g = CrymbleUI::VStack.new(id: id, spacing: 2.0)
    5.times do |r|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      5.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}", id: "#{prefix}::#{r},#{c}", font_scale: -5, padding: 3.0) { }) }
      g.add_child(hs)
    end
    g
  end

  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("T", 1200, 900)
    p1 = CrymbleUI::WindowPanel.new("F", 20.0, 60.0, 700.0, 600.0)
    p1.add_child(grid("gf", "gf"))
    window.add_child(p1)

    p2 = CrymbleUI::WindowPanel.new("S", 750.0, 60.0, 420.0, 600.0)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both, id: "sv")
    sv.set_content(grid("gs", "gs"))
    p2.add_child(sv)
    window.add_child(p2)
    window
  end
end

describe "App#find reaches buttons in a floored grid AND a ScrollView-contained grid" do
  it "finds a cell by id in both panels (localized-flash seam)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1200, 900)
    app = FindReachApp.new
    app.build_tree
    renderer.settle_rendering(app)

    app.find("gf::2,3").should_not be_nil # floored grid
    app.find("gs::2,3").should_not be_nil # grid inside the ScrollView

    # And the found button is really a Button whose colour we can set (the localized-flash write).
    btn = app.find("gs::2,3").as?(CrymbleUI::Button).not_nil!

    # THE crux: setting the colour via find must be a LOCALIZED re-render, NOT an app rebuild — else a
    # 400ms flash clock would blanket-repaint all 800 cells (the 70%-CPU, unresponsive demo). needs_rebuild?
    # must stay false after the write.
    app.needs_rebuild?.should be_false
    btn.background_color = CrymbleUI::Color.new(255, 165, 0, 255)
    app.needs_rebuild?.should be_false # the write did NOT request a rebuild → localized, cheap
  end
end
