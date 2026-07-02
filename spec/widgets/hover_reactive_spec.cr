require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/button"
require "../../src/widgets/menu_item"
require "../../src/widgets/combo_box_item"
require "../../src/widgets/menu"
require "../../src/widgets/window"

# @hovered cluster: button / menu_item / combo_box_item / menu read a plain
# @hovered ivar in to_primitives and re-render only via a manual mark_needs_render in
# on_mouse_enter/exit. Making `hovered` a reactive_property means the value is captured
# while painting, so setting it re-renders automatically -- a new hover path can't
# forget the mark.

private def assert_hover_reactive(widget)
  renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
  app = TestApp.new
  widget.bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 30.0)
  window = CrymbleUI::Window.new("t", 200, 100)
  window.add_child(widget)
  app.root_widget = window
  renderer.render_frame(app) # the widget renders and captures `hovered`

  widget.hovered = true               # reactive setter -- NO manual mark_needs_render
  widget.needs_render?.should be_true # the auto-captured node went stale
end

describe "hover state is reactive (auto-capture, no manual mark)" do
  it "Button" { assert_hover_reactive(CrymbleUI::Button.new("B") { }) }
  it "MenuItem" { assert_hover_reactive(CrymbleUI::MenuItem.new("M") { }) }
  it "ComboBoxItem" { assert_hover_reactive(CrymbleUI::ComboBoxItem.new("C")) }
  it "Menu" { assert_hover_reactive(CrymbleUI::Menu.new("Mn")) }
end
