require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/popup"

# Tests for popup event blocking
#
# BUG: When a Popup overlaps a WindowPanel's resize edge, the panel's resize
# cursor "shows through" the popup even though the popup is visually on top.
#
# Root cause: App#get_cursor_for_point only checks panels, not popups.
# Popups don't block cursor changes from widgets below them.

describe "Popup Event Blocking" do
  it "popup blocks resize cursor from panel below" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create a resizable panel with its right edge at x=300
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    panel.resizable = true

    # Create a popup that overlaps the panel's right edge
    # Panel right edge is at x=300 (x=100 + width=200)
    # Popup at x=290 with width=50 covers x=290-340, overlapping the resize edge
    popup = CrymbleUI::Popup.new(width: 50.0, height: 100.0)

    window.add_child(panel)
    window.add_child(popup)
    app.root_widget = window

    # Initial render and layout
    renderer.render_frame(app)

    # Position popup to overlap panel's right edge (similar to how Menu positions dropdowns)
    # Panel right edge is at x=300, position popup at x=290 to overlap
    popup_position = CrymbleUI::Vec2.new(290.0, 100.0)
    popup_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(50.0, 100.0))
    popup.layout(popup_constraints, popup_position)

    renderer.render_frame(app)

    # Mouse move to x=300 (panel's right edge, but INSIDE the popup)
    # Without fix: cursor becomes SizeHorizontal (from panel below)
    # With fix: cursor should be Arrow (popup blocks the panel's resize cursor)
    renderer.mouse_move(300.0, 150.0)

    # Popup should block the resize cursor from the panel below
    renderer.current_cursor.should eq(CrymbleUI::CursorType::Arrow)
  end

  it "popup blocks mouse clicks from reaching panel below" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Create a panel
    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)

    # Create a popup overlapping the panel
    popup = CrymbleUI::Popup.new(width: 50.0, height: 100.0)

    window.add_child(panel)
    window.add_child(popup)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Position popup to overlap panel center
    popup_position = CrymbleUI::Vec2.new(150.0, 120.0)
    popup_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(50.0, 100.0))
    popup.layout(popup_constraints, popup_position)

    renderer.render_frame(app)

    # Click on the overlap area (inside popup, over panel)
    # hit_test should return popup, not panel
    point = CrymbleUI::Vec2.new(175.0, 150.0)
    hit_widget = window.hit_test(point)

    # Click should hit the popup, not the panel below
    hit_widget.should eq(popup)
  end

  it "a popup added via Window#add_overlay (not DSL children) still blocks the panel's resize cursor" do
    # The overlay path (ComboBoxPopup's real mount mechanism, PopupHost#mount_popup) sets
    # popup.parent = window directly and appends to @overlays — NOT to the window's @children.
    # find_all_popups' registry lookup (Popup.all_in_tree) must still find it via widget_in_tree?
    # (parent-chain walk), since Window no longer special-cases @overlays with its own
    # collect_popups_recursive override (the registry subsumes that).
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Panel", 100.0, 100.0, 200.0, 150.0)
    panel.resizable = true
    window.add_child(panel)
    app.root_widget = window

    renderer.render_frame(app)

    popup = CrymbleUI::Popup.new(width: 50.0, height: 100.0)
    window.add_overlay(popup)

    # Same overlap point as the DSL-children test above: panel's right edge at x=300.
    popup_position = CrymbleUI::Vec2.new(290.0, 100.0)
    popup_constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(50.0, 100.0))
    popup.layout(popup_constraints, popup_position)

    renderer.render_frame(app)

    renderer.mouse_move(300.0, 150.0)
    renderer.current_cursor.should eq(CrymbleUI::CursorType::Arrow)
  end
end
