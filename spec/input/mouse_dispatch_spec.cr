require "../spec_helper"
require "../../src/testing/driver"

# THE MOUSE PATH BOTH RENDERERS TAKE (MouseDispatch). A press focuses what it hits, a move drags while a
# button is down and hovers otherwise; TestRenderer#deliver dispatches queued mouse events through the
# same path as SFMLRenderer's run loop, in the same batches, so a spec can put a click and the typing
# after it into ONE batch - no frame between - the way a fast user or a script does.

private K = CrymbleUI::Testing::Keys

# Focusable, but takes no focus of its own on a press - so only the dispatch's focus step can give it.
private class PlainFocusable < CrymbleUI::Widget
  def focusable? : Bool
    true
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(80, 20)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(80, 20))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private def field_app(typed : Array(String))
  app = TestApp.new
  window = CrymbleUI::Window.new("W", 400, 300)
  stack = CrymbleUI::VStack.new(spacing: 10.0)
  stack.add_child(CrymbleUI::TextInput.new(value: "", id: "field") { |v| typed << v })
  stack.add_child(CrymbleUI::Text.new("label", id: "label"))
  stack.add_child(CrymbleUI::Button.new("go", id: "go") { })
  stack.add_child(PlainFocusable.new(id: "plain"))
  window.add_child(stack)
  app.root_widget = window
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  renderer.settle_rendering(app)
  {app, renderer}
end

private def centre_of(app, id) : {Int32, Int32}
  c = app.root.not_nil!.find_by_id(id).not_nil!.viewport_bounds.center
  {c.x.to_i, c.y.to_i}
end

describe CrymbleUI::MouseDispatch do
  # Mutations: drop the focus step from App#handle_mouse_down (it lived in SFMLRenderer alone, so a
  # coordinate spec never saw the focus a real click gives); drop the clear.
  it "focuses what a press hits, keeps focus on a press on something unfocusable, clears it on nothing" do
    app, renderer = field_app([] of String)
    x, y = centre_of(app, "plain")
    renderer.mouse_down(x.to_f, y.to_f)
    renderer.mouse_up(x.to_f, y.to_f)
    CrymbleUI::Widget.focus_manager.focused_widget.try(&.id).should eq("plain")
    x, y = centre_of(app, "field")
    renderer.mouse_down(x.to_f, y.to_f)
    renderer.mouse_up(x.to_f, y.to_f)
    CrymbleUI::Widget.focus_manager.focused_widget.try(&.id).should eq("field")
    lx, ly = centre_of(app, "label")
    renderer.mouse_down(lx.to_f, ly.to_f)
    renderer.mouse_up(lx.to_f, ly.to_f)
    CrymbleUI::Widget.focus_manager.focused_widget.try(&.id).should eq("field")
    renderer.mouse_down(-50.0, -50.0) # outside every widget
    CrymbleUI::Widget.focus_manager.focused_widget.should be_nil
  end

  # Mutation: deliver refusing mouse events (as it did) - or not routing them through the press.
  it "delivers a click and the typing after it in one batch" do
    typed = [] of String
    app, renderer = field_app(typed)
    x, y = centre_of(app, "field")
    renderer.deliver(app, K.click_at(x, y) + K.typed("hi") + K.tap(SF::Keyboard::Key::Enter))
    app.root.not_nil!.find_by_id("field").as(CrymbleUI::TextInput).value.should eq("hi")
  end

  # Mutation: hover on every move (what TestRenderer did) - the drag's target would take the hover.
  it "drags on a move while the button is down, and hovers only when it is up" do
    app, renderer = field_app([] of String)
    x, y = centre_of(app, "field")
    gx, gy = centre_of(app, "go")
    renderer.mouse_down(x.to_f, y.to_f)
    renderer.mouse_move(gx.to_f, gy.to_f)
    app.hovered_widget.try(&.id).should_not eq("go")
    renderer.mouse_up(gx.to_f, gy.to_f)
    renderer.mouse_move(gx.to_f + 1, gy.to_f)
    app.hovered_widget.try(&.id).should eq("go")
  end
end
