require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"

describe "WindowPanel zoom click stability" do
  it "title_bar_height is integer-valued at all zoom levels" do
    panel = CrymbleUI::WindowPanel.new("Panel", 50.0, 50.0, 300.0, 200.0)

    # Default zoom (100%): 14.0 * 1.0 + 16.0 = 30.0 (integer)
    panel.title_bar_height.should eq(panel.title_bar_height.round)

    # 110% zoom: 14.0 * 1.1 + 16.0 = 31.4 (fractional!)
    CrymbleUI::FontSizing.zoom_in
    panel.title_bar_height.should eq(panel.title_bar_height.round)

    # 125% zoom: 14.0 * 1.25 + 16.0 = 33.5 (fractional!)
    CrymbleUI::FontSizing.zoom_in
    panel.title_bar_height.should eq(panel.title_bar_height.round)

    # 150% zoom: 14.0 * 1.5 + 16.0 = 37.0 (integer)
    CrymbleUI::FontSizing.zoom_in
    panel.title_bar_height.should eq(panel.title_bar_height.round)

    # 80% zoom: 14.0 * 0.8 + 16.0 = 27.2 (fractional!)
    CrymbleUI::FontSizing.reset_zoom
    CrymbleUI::FontSizing.zoom_out
    CrymbleUI::FontSizing.zoom_out
    panel.title_bar_height.should eq(panel.title_bar_height.round)
  end
end
