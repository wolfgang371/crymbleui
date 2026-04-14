require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/window_panel"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# DSL-style app: WindowPanel containing a ComboBox.
# Creates NEW widget instances on each build() - exactly like real apps.
#
# Bug: sort_layers_for_compositing groups layers by parent-panel z-index.
#   - The ComboBoxPopup's layer has owner_widget=ComboBoxPopup, whose parent=Window.
#   - find_panel_z_index walks up: ComboBoxPopup → Window → nil → returns Int32::MIN.
#   - The WindowPanel's layer has find_panel_z_index → WindowPanel.z_index = 1.
#   - After sort: Int32::MIN group (Window base + popup) comes before group 1 (panel).
#   - Compositing order: Window(z=0) → Popup(z=1000) → Panel(z=1).
#   - The panel's texture blits OVER the popup → popup is invisible to user.
#   - User sees no dropdown, clicks again → notify_overlays_of_click fires → collapse.
#
# The test detects this by checking PIXEL COLORS in the composited window buffer:
#   - popup_background = #FFFFFF (white) — from light.json "popup.background"
#   - panel_background = #F0F0F0 (light gray) — from light.json "panel.background"
#   - If popup is on top (correct): pixel at popup location = white
#   - If panel is on top (bug): pixel at popup location = light gray
class ComboBoxPanelApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Host", 600, 400) do
      window_panel("Panel", 50.0, 50.0, 300.0, 200.0, z_index: 1, id: "panel") do
        combo_box(
          items: ["Alpha", "Beta", "Gamma"],
          selected: 0,
          width: 180.0,
          id: "combo"
        ) { |_idx, _val| }
      end
    end
  end
end

describe "ComboBox inside WindowPanel - compositing order" do
  # Regression test for sort_layers_for_compositing breaking ComboBox popup visibility.
  #
  # With simple sort_by!(&.z_index):
  #   popup layer (z=1000) composited AFTER panel layer (z=1) → popup visible on top ✓
  #
  # With sort_layers_for_compositing (buggy):
  #   popup gets group=Int32::MIN, panel gets group=1
  #   Int32::MIN < 1, so popup composited BEFORE panel → panel covers popup → popup invisible ✗
  #
  # This test checks pixel color at the popup area: popup_background (#FFFFFF) vs
  # panel_background (#F0F0F0). These are guaranteed distinct in the light theme.
  it "popup layer is composited above panel layer (popup pixels visible in window buffer)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app = ComboBoxPanelApp.new
    app.build_tree
    renderer.settle_rendering(app)

    # Find initial combo and click to expand
    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    click_on(app, combo)

    # Two frames: first triggers layout+rebuild, second is the steady-state frame
    renderer.render_frame(app)
    renderer.render_frame(app)

    # Re-find combo after potential rebuild
    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true, "Popup should be open"

    popup = combo.current_popup.not_nil!

    # Popup is positioned at (combo.abs.x, combo.abs.y + combo.abs.height)
    popup_abs = popup.absolute_bounds
    popup_abs.width.should be > 0, "Popup must have been laid out (non-zero width)"
    popup_abs.height.should be > 0, "Popup must have been laid out (non-zero height)"

    # Sample a pixel in the interior of the popup background area (avoid border pixels)
    sample_x = (popup_abs.x + popup_abs.width / 2).to_i
    sample_y = (popup_abs.y + 2).to_i  # Near top, skip the TextInput area (want popup bg)

    pixel = renderer.backend.get_pixel(sample_x, sample_y)
    pixel.should_not be_nil, "Pixel at popup location should exist within window bounds"

    if px = pixel
      popup_bg = CrymbleUI::Theme.current.popup_background
      panel_bg = CrymbleUI::Theme.current.panel_background

      # Verify the theme colors are actually distinct (sanity check)
      colors_differ = popup_bg.r != panel_bg.r || popup_bg.g != panel_bg.g || popup_bg.b != panel_bg.b
      colors_differ.should be_true,
        "Test requires popup_background and panel_background to be distinct colors " \
        "(popup=rgb(#{popup_bg.r},#{popup_bg.g},#{popup_bg.b}), panel=rgb(#{panel_bg.r},#{panel_bg.g},#{panel_bg.b}))"

      # The popup background must be visible at the popup's location.
      # If the panel layer covers the popup (bug), we'd see panel_background instead.
      # Allow some tolerance for partial-transparency blending.
      # We check that the pixel is closer to popup_background than panel_background.
      #
      # In light theme: popup=#FFFFFF (255,255,255), panel=#F0F0F0 (240,240,240)
      # Midpoint is ~247 for each channel. If popup is on top: pixel >= 247.
      # If panel is on top (BUG): pixel <= 240.
      diff_from_popup = ((px.r.to_i - popup_bg.r.to_i).abs +
                         (px.g.to_i - popup_bg.g.to_i).abs +
                         (px.b.to_i - popup_bg.b.to_i).abs)
      diff_from_panel = ((px.r.to_i - panel_bg.r.to_i).abs +
                         (px.g.to_i - panel_bg.g.to_i).abs +
                         (px.b.to_i - panel_bg.b.to_i).abs)

      diff_from_popup.should be < diff_from_panel,
        "Pixel at popup center (#{sample_x},#{sample_y}) should be popup_background color " \
        "rgb(#{popup_bg.r},#{popup_bg.g},#{popup_bg.b}), " \
        "but got rgb(#{px.r},#{px.g},#{px.b}). " \
        "Panel bg is rgb(#{panel_bg.r},#{panel_bg.g},#{panel_bg.b}). " \
        "Bug: sort_layers_for_compositing placed panel layer AFTER popup layer, covering it."
    end
  end

  it "popup TextInput stays focused after rebuild (behavioral check)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app = ComboBoxPanelApp.new
    app.build_tree
    renderer.settle_rendering(app)

    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    click_on(app, combo)
    renderer.render_frame(app)
    renderer.render_frame(app)

    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true, "Popup should be open after two frames"

    popup = combo.current_popup.not_nil!
    popup.text_input.focused?.should be_true,
      "TextInput must keep focus after rebuild — if blur fires, on_cancel collapses popup"

    # Typing must work (confirming focus is active and functional)
    CrymbleUI::Widget.focus_manager.handle_text_input('B')
    renderer.render_frame(app)

    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    combo.popup_open?.should be_true, "Popup should remain open while typing"

    popup = combo.current_popup.not_nil!
    popup.text_input.value.should eq("B"),
      "TextInput must accept typed text (empty value means focus was lost)"
    popup.filtered_items.should eq(["Beta"]),
      "Filtered items must update when typing 'B' (only 'Beta' starts with B)"
  end
end
