require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

# WHERE THE DROP HIGHLIGHT SHOWS: over the part of its target that is visible - never outside a scroll view,
# a panel's content or a popup that clips the target, never over a panel, a sticky band or a popup in front
# of it - and over what the target contains, its own child layers included; in the target's colour, for as
# long as the drag is over it, and nowhere once it is not. Read from the composited window pixels. The wash is
# opaque (opacity 1.0), so a pixel either is the wash or is not. The drag ghost sits at the pointer, above
# everything, so no sample may lie under it (`pixel` asserts that).

private WASH  = CrymbleUI::Color.new(255, 0, 0, 255)
private WASH2 = CrymbleUI::Color.new(0, 255, 0, 255)
private GREY  = CrymbleUI::Color.new(200, 200, 200, 255)
private NAVY  = CrymbleUI::Color.new(0, 0, 120, 255)

# A block of one colour and a fixed height, full width.
class DhpSwatch < CrymbleUI::Widget
  def initialize(@height : Float64, @color : CrymbleUI::Color, id : String? = nil, @width : Float64? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@width || (constraints.max_width.finite? ? constraints.max_width : 200.0), @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

private def zone(id : String, wash : CrymbleUI::Color = WASH, &) : CrymbleUI::DropZoneBox
  z = CrymbleUI::DropZoneBox.new(accept_types: ["text"], hover_color: wash, highlight_opacity: 1.0, id: id)
  yield z
  z
end

private def zone(id : String, height : Float64 = 200.0, wash : CrymbleUI::Color = WASH) : CrymbleUI::DropZoneBox
  zone(id, wash) { |z| z.add_child(DhpSwatch.new(height, GREY)) }
end

private def chip : CrymbleUI::Widget
  # Narrow, so its ghost (at the pointer, above everything) stays clear of the sampled pixels.
  CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new("x"), id: "chip").tap(&.add_child(DhpSwatch.new(20.0, CrymbleUI::Color.new(0, 0, 200, 255), width: 20.0)))
end

private def vstack(*children : CrymbleUI::Widget) : CrymbleUI::VStack
  CrymbleUI::VStack.new(spacing: 0.0).tap { |s| children.each { |c| s.add_child(c) } }
end

# A scroll view `height` tall over `content`.
private def scroller(id : String, height : Float64, content : CrymbleUI::Widget) : CrymbleUI::ScrollView
  CrymbleUI::ScrollView.new(max_height: height, id: id).tap(&.set_content(content))
end

# A window holding one panel "p" (20,20, 400x400) with the chip over `content`.
private def one_panel(content : CrymbleUI::Widget) : CrymbleUI::Window
  window = CrymbleUI::Window.new("W", 600, 500)
  panel = CrymbleUI::WindowPanel.new("P", 20.0, 20.0, 400.0, 400.0, id: "p")
  panel.add_child(vstack(chip, content))
  window.add_child(panel)
  window
end

class DhpApp < CrymbleUI::App
  def initialize(&@make : -> CrymbleUI::Widget)
    super()
  end

  def build : CrymbleUI::Widget
    @make.call
  end
end

private def run(&make : -> CrymbleUI::Widget) : {DhpApp, CrymbleUI::Testing::TestRenderer}
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 500)
  app = DhpApp.new(&make)
  CrymbleUI::Widget.app = app
  app.build_tree
  renderer.settle_rendering(app)
  {app, renderer}
end

private def find(app, id : String) : CrymbleUI::Widget
  app.find(id) || raise "no widget #{id}"
end

# Drag the chip onto `at` (one move to cross the threshold, two to settle on the target) and render.
private def hover(app, renderer, at : CrymbleUI::Vec2) : Nil
  from = find(app, "chip").viewport_bounds.center
  app.handle_mouse_down(from)
  app.handle_mouse_move(from + CrymbleUI::Vec2.new(0.0, 12.0))
  move(app, renderer, at)
end

private def move(app, renderer, at : CrymbleUI::Vec2) : Nil
  app.handle_mouse_move(at)
  app.handle_mouse_move(at)
  renderer.render_frame(app)
end

private def rebuild(app, renderer) : Nil
  app.request_rebuild
  renderer.settle_rendering(app)
end

private GHOST_CLEAR = 60.0 # further from the pointer than the ghost reaches (the chip is 20x20)

# The composited pixel at `at` - never one the drag ghost covers.
private def pixel(app, renderer, at : CrymbleUI::Vec2) : CrymbleUI::Color
  app.drag_manager.ghost_layer.try(&.bounds.contains_point(at)).should_not be_true # instrument: clear of the ghost
  renderer.backend.get_pixel(at.x.to_i, at.y.to_i).not_nil!
end

private def target_id(app) : String?
  app.drag_manager.state.current_target.try(&.id)
end

describe "the drop highlight" do
  it "shows only over the part of the target a scroll view keeps visible" do
    app, renderer = run do
      one_panel(vstack(DhpSwatch.new(80.0, CrymbleUI::Color.new(0, 150, 0, 255)),
        scroller("sv", 120.0, vstack(zone("a"), DhpSwatch.new(400.0, NAVY)))))
    end
    find(app, "sv").as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 50.0))
    renderer.settle_rendering(app)
    a = find(app, "a").viewport_bounds
    view = find(app, "sv").viewport_bounds
    (a.y < view.y).should be_true # instrument: A reaches above the scroll view
    hover(app, renderer, CrymbleUI::Vec2.new(a.center.x - GHOST_CLEAR, view.y + 10.0))
    pixel(app, renderer, CrymbleUI::Vec2.new(a.center.x + GHOST_CLEAR, view.y + 10.0)).should eq(WASH) # the visible part
    pixel(app, renderer, CrymbleUI::Vec2.new(a.center.x + GHOST_CLEAR, view.y - 10.0)).should_not eq(WASH) # above the scroll view
  end

  it "stays under a panel in front of the target" do
    app, renderer = run do
      window = CrymbleUI::Window.new("W", 600, 500)
      # The chip outside both panels: pressing it must not bring the back panel to front.
      window.add_child(vstack(chip))
      back = CrymbleUI::WindowPanel.new("B", 20.0, 60.0, 300.0, 300.0, id: "back")
      back.add_child(zone("z"))
      front = CrymbleUI::WindowPanel.new("F", 200.0, 100.0, 200.0, 200.0, id: "front")
      front.add_child(DhpSwatch.new(180.0, NAVY))
      window.add_child(back)
      window.add_child(front)
      window
    end
    find(app, "front").as(CrymbleUI::WindowPanel).bring_to_front
    renderer.settle_rendering(app)
    z = find(app, "z").viewport_bounds
    covered = CrymbleUI::Vec2.new(260.0, z.y + 100.0)
    find(app, "front").viewport_bounds.contains_point(covered).should be_true # instrument
    hover(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0, z.y + 150.0))
    front_z = find(app, "front").as(CrymbleUI::WindowPanel).z_index
    (front_z > find(app, "back").as(CrymbleUI::WindowPanel).z_index).should be_true # instrument: front is in front
    pixel(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0, z.y + 150.0 - GHOST_CLEAR)).should eq(WASH) # the uncovered part
    pixel(app, renderer, covered).should_not eq(WASH)                                                 # under the panel in front
  end

  # The target's subtree owns a layer with an auxiliary (a scroll view and its scrollbar): the wash lies over
  # both - they are the target's own pixels.
  it "covers what the target contains, a child's own layers included" do
    app, renderer = run do
      one_panel(zone("z") { |z| z.add_child(scroller("inner_sv", 100.0, DhpSwatch.new(300.0, CrymbleUI::Color.new(0, 120, 0, 255)))) })
    end
    inner = find(app, "inner_sv").viewport_bounds
    at = CrymbleUI::Vec2.new(inner.x + 20.0, inner.y + 10.0)
    hover(app, renderer, at)
    target_id(app).should eq("z") # instrument: the zone, not something inside
    pixel(app, renderer, at + CrymbleUI::Vec2.new(GHOST_CLEAR, GHOST_CLEAR)).should eq(WASH)
    pixel(app, renderer, CrymbleUI::Vec2.new(inner.right - 3.0, inner.y + 10.0 + GHOST_CLEAR)).should eq(WASH) # its scrollbar
  end

  it "leaves the scrollbar of a scroll view around the target unwashed" do
    app, renderer = run do
      one_panel(scroller("sv", 150.0, vstack(zone("z", 300.0))))
    end
    view = find(app, "sv").viewport_bounds
    hover(app, renderer, CrymbleUI::Vec2.new(view.x + 30.0, view.y + 10.0))
    pixel(app, renderer, CrymbleUI::Vec2.new(view.x + 30.0, view.y + 10.0 + GHOST_CLEAR)).should eq(WASH)
    pixel(app, renderer, CrymbleUI::Vec2.new(view.right - 3.0, view.y + 10.0 + GHOST_CLEAR)).should_not eq(WASH) # the scrollbar's column
  end

  # Retargeting from a zone in the front panel to one in the back panel: the back zone's wash stays under the
  # front panel - and moving to another target re-collects no layers (the wash is placed per frame).
  it "follows a retarget across panels in its new place, re-collecting nothing" do
    app, renderer = run do
      window = CrymbleUI::Window.new("W", 600, 500)
      window.add_child(vstack(chip))
      back = CrymbleUI::WindowPanel.new("B", 20.0, 60.0, 300.0, 300.0, id: "back")
      back.add_child(zone("b"))
      front = CrymbleUI::WindowPanel.new("F", 200.0, 100.0, 200.0, 200.0, id: "front")
      front.add_child(zone("f", 180.0))
      window.add_child(back)
      window.add_child(front)
      window
    end
    find(app, "front").as(CrymbleUI::WindowPanel).bring_to_front
    renderer.settle_rendering(app)
    f = find(app, "f").viewport_bounds
    b = find(app, "b").viewport_bounds
    covered = CrymbleUI::Vec2.new(260.0, b.y + 100.0)
    f.contains_point(covered).should be_true # instrument: the front zone covers that part of the back zone
    hover(app, renderer, CrymbleUI::Vec2.new(f.right - 10.0, f.bottom - 10.0))
    target_id(app).should eq("f") # instrument
    pixel(app, renderer, covered).should eq(WASH)
    before = CrymbleUI::LayerRenderer.frame_layer_recollect_count
    at = CrymbleUI::Vec2.new(b.x + 30.0, b.y + 150.0)
    move(app, renderer, at)
    target_id(app).should eq("b") # instrument
    CrymbleUI::LayerRenderer.frame_layer_recollect_count.should eq(before)
    pixel(app, renderer, at - CrymbleUI::Vec2.new(0.0, GHOST_CLEAR)).should eq(WASH) # the back zone, uncovered
    pixel(app, renderer, covered).should eq(GREY)                                     # the front zone over it, unwashed
  end

  # The target scrolls partly out under a still pointer, then back: the wash shrinks with it, then covers the
  # whole visible target again.
  it "grows back with a target scrolled partly out and in again" do
    app, renderer = run do
      one_panel(scroller("sv", 200.0, vstack(zone("a", 150.0), DhpSwatch.new(400.0, NAVY))))
    end
    sv = find(app, "sv").as(CrymbleUI::ScrollView)
    view = sv.viewport_bounds
    top = CrymbleUI::Vec2.new(view.x + 30.0 + GHOST_CLEAR, view.y + 5.0)
    hover(app, renderer, CrymbleUI::Vec2.new(view.x + 30.0, view.y + 80.0)) # over A before the scroll and after
    pixel(app, renderer, top).should eq(WASH)
    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 60.0))
    renderer.render_frame(app)
    target_id(app).should eq("a") # instrument: still over A
    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 0.0))
    renderer.render_frame(app)
    pixel(app, renderer, top).should eq(WASH) # the part that had scrolled out
  end

  it "takes the colour of the target it moves to" do
    app, renderer = run { one_panel(vstack(zone("a", 100.0), zone("b", 100.0, WASH2))) }
    a = find(app, "a").viewport_bounds
    b = find(app, "b").viewport_bounds
    hover(app, renderer, CrymbleUI::Vec2.new(a.x + 30.0, a.center.y))
    move(app, renderer, CrymbleUI::Vec2.new(b.x + 30.0, b.center.y))
    target_id(app).should eq("b") # instrument
    pixel(app, renderer, CrymbleUI::Vec2.new(b.x + 30.0 + GHOST_CLEAR, b.center.y)).should eq(WASH2)
    pixel(app, renderer, CrymbleUI::Vec2.new(a.x + 30.0 + GHOST_CLEAR, a.center.y)).should eq(GREY)
  end

  # A zone that takes its colour from the theme: switching the theme mid-drag re-colours the wash.
  it "follows a theme switch mid-drag" do
    light = CrymbleUI::Theme.current.dropzone_hover
    CrymbleUI::Theme.set(:dark)
    dark = CrymbleUI::Theme.current.dropzone_hover
    CrymbleUI::Theme.set(:light)
    (light == dark).should be_false # instrument: the themes differ in this colour
    begin
      app, renderer = run do
        one_panel(CrymbleUI::DropZoneBox.new(accept_types: ["text"], highlight_opacity: 1.0, id: "z")
          .tap(&.add_child(DhpSwatch.new(150.0, GREY))))
      end
      z = find(app, "z").viewport_bounds
      hover(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0, z.center.y))
      sample = CrymbleUI::Vec2.new(z.x + 30.0 + GHOST_CLEAR, z.center.y)
      pixel(app, renderer, sample).should eq(light)
      CrymbleUI::Theme.set(:dark)
      renderer.settle_rendering(app)
      app.drag_manager.dragging?.should be_true # instrument
      pixel(app, renderer, sample).should eq(dark)
    ensure
      CrymbleUI::Theme.set(:light)
    end
  end

  it "takes the theme's drag highlight for a target that names no colour" do
    CrymbleUI::Theme.set(:dark)
    begin
      app, renderer = run { one_panel(DhpPlainTarget.new(150.0, GREY, id: "t")) }
      t = find(app, "t").viewport_bounds
      hover(app, renderer, CrymbleUI::Vec2.new(t.x + 30.0, t.center.y))
      target_id(app).should eq("t") # instrument
      pixel(app, renderer, CrymbleUI::Vec2.new(t.x + 30.0 + GHOST_CLEAR, t.center.y)).should eq(CrymbleUI::Theme.current.drag_highlight)
    ensure
      CrymbleUI::Theme.set(:light)
    end
  end

  # A rebuild mid-drag replaces every widget; the drag's ghost and wash are the drag's own and survive it.
  it "survives a rebuild, then follows the next retarget" do
    app, renderer = run { one_panel(vstack(zone("a", 100.0), zone("b", 100.0))) }
    a = find(app, "a").viewport_bounds
    b = find(app, "b").viewport_bounds
    hover(app, renderer, CrymbleUI::Vec2.new(a.x + 30.0, a.center.y))
    rebuild(app, renderer)
    at = CrymbleUI::Vec2.new(b.x + 30.0, b.center.y)
    move(app, renderer, at)
    target_id(app).should eq("b") # instrument
    pixel(app, renderer, at + CrymbleUI::Vec2.new(GHOST_CLEAR, 0.0)).should eq(WASH)
    renderer.backend.get_pixel(at.x.to_i, at.y.to_i).not_nil!.should_not eq(WASH) # the ghost over the wash
  end

  it "moves to the widget a rebuild put in place of its target, the pointer still" do
    app, renderer = run { one_panel(zone("z", 150.0)) }
    old = find(app, "z")
    z = old.viewport_bounds
    hover(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0, z.center.y))
    rebuild(app, renderer)
    now = find(app, "z")
    now.same?(old).should be_false # instrument: the target was replaced
    app.drag_manager.state.current_target.same?(now).should be_true
    pixel(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0 + GHOST_CLEAR, z.center.y)).should eq(WASH)
    old.as(CrymbleUI::DropZoneBox).drag_hover?.should be_false # the replaced one is hovered no more
  end

  it "forgets the hover of a target a rebuild removed" do
    shown = true
    app, renderer = run { one_panel(shown ? zone("z", 150.0) : DhpSwatch.new(150.0, GREY)) }
    old = find(app, "z")
    z = old.viewport_bounds
    hover(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0, z.center.y))
    old.as(CrymbleUI::DropZoneBox).drag_hover?.should be_true # instrument
    shown = false
    rebuild(app, renderer)
    app.drag_manager.dragging?.should be_true # instrument
    old.as(CrymbleUI::DropZoneBox).drag_hover?.should be_false
    pixel(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0 + GHOST_CLEAR, z.center.y)).should eq(GREY)
  end

  it "is gone when the pointer leaves the target for a gap" do
    app, renderer = run { one_panel(vstack(zone("z", 100.0), DhpSwatch.new(100.0, NAVY))) }
    z = find(app, "z").viewport_bounds
    hover(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0, z.center.y))
    move(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0, z.bottom + 50.0))
    target_id(app).should be_nil # instrument
    pixel(app, renderer, CrymbleUI::Vec2.new(z.x + 30.0 + GHOST_CLEAR, z.center.y)).should eq(GREY)
  end

  {% for ending in %w[drop escape] %}
    it "is gone once the drag ends ({{ ending.id }})" do
      app, renderer = run { one_panel(zone("z", 150.0)) }
      z = find(app, "z").viewport_bounds
      at = CrymbleUI::Vec2.new(z.x + 30.0, z.center.y)
      hover(app, renderer, at)
      {% if ending == "drop" %} app.handle_mouse_up(at) {% else %} app.handle_escape {% end %}
      renderer.render_frame(app)
      app.drag_manager.dragging?.should be_false # instrument
      pixel(app, renderer, at + CrymbleUI::Vec2.new(GHOST_CLEAR, 0.0)).should eq(GREY)
    end
  {% end %}

  it "is gone when its target scrolls out under a still pointer" do
    app, renderer = run { one_panel(scroller("sv", 200.0, vstack(zone("a", 100.0), DhpSwatch.new(400.0, NAVY)))) }
    sv = find(app, "sv").as(CrymbleUI::ScrollView)
    view = sv.viewport_bounds
    at = CrymbleUI::Vec2.new(view.x + 30.0, view.y + 50.0)
    hover(app, renderer, at)
    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 150.0))
    renderer.render_frame(app)
    target_id(app).should be_nil # instrument
    pixel(app, renderer, at + CrymbleUI::Vec2.new(GHOST_CLEAR, 0.0)).should eq(NAVY)
  end

  it "is gone when its target's panel closes" do
    app, renderer = run do
      window = CrymbleUI::Window.new("W", 600, 500)
      window.add_child(vstack(chip))
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 60.0, 300.0, 300.0, id: "p")
      panel.add_child(zone("z"))
      window.add_child(panel)
      window
    end
    z = find(app, "z").viewport_bounds
    at = CrymbleUI::Vec2.new(z.x + 30.0, z.y + 100.0)
    hover(app, renderer, at)
    find(app, "p").as(CrymbleUI::WindowPanel).close
    renderer.settle_rendering(app)
    target_id(app).should be_nil # instrument
    pixel(app, renderer, at + CrymbleUI::Vec2.new(GHOST_CLEAR, 0.0)).should_not eq(WASH)
  end

  # The target is gone from the frame's layers while the highlight still names it - between a change to the
  # tree and the drag's re-resolve. No layer paints it, so there is no place for its wash: none is drawn.
  it "is not drawn when no layer of this frame paints its target" do
    app, renderer = run do
      window = CrymbleUI::Window.new("W", 600, 500)
      window.add_child(vstack(chip))
      panel = CrymbleUI::WindowPanel.new("P", 20.0, 60.0, 300.0, 300.0, id: "p")
      panel.add_child(zone("z"))
      window.add_child(panel)
      window
    end
    z = find(app, "z").viewport_bounds
    at = CrymbleUI::Vec2.new(z.x + 30.0, z.y + 100.0)
    hover(app, renderer, at)
    root = app.root.not_nil!
    root.remove_child(find(app, "p"))
    dm = app.drag_manager
    dm.highlight_layer.try(&.composite_anchor).should_not be_nil # instrument: the highlight still names the target
    renderer.invalidate_layer_cache
    renderer.render_all_layers(root, dm.ghost_layer, dm.highlight_layer)
    pixel(app, renderer, at + CrymbleUI::Vec2.new(GHOST_CLEAR, 0.0)).should_not eq(WASH)
  end

  # A target in a popup: washed inside the popup, clipped to it, and under a second popup over it.
  it "stays inside a popup's bounds and under a popup in front" do
    popups = [] of CrymbleUI::Popup # overlays are not in `find`'s reach
    app, renderer = run do
      window = CrymbleUI::Window.new("W", 600, 500)
      window.add_child(vstack(chip))
      low = CrymbleUI::Popup.new(width: 300.0, height: 150.0, z_index: 1000, id: "low")
      low.target_x, low.target_y = 50.0, 100.0
      low.add_child(zone("z", 300.0))
      high = CrymbleUI::Popup.new(width: 100.0, height: 60.0, z_index: 1500, id: "high")
      high.target_x, high.target_y = 250.0, 120.0
      high.add_child(DhpSwatch.new(60.0, NAVY))
      window.add_overlay(low)
      window.add_overlay(high)
      popups = [low, high]
      window
    end
    low, high = popups.map(&.viewport_bounds)
    at = CrymbleUI::Vec2.new(low.x + 20.0, low.y + 20.0)
    hover(app, renderer, at)
    target_id(app).should eq("z") # instrument
    pixel(app, renderer, CrymbleUI::Vec2.new(low.x + 20.0, low.bottom - 10.0)).should eq(WASH)   # inside the popup
    pixel(app, renderer, CrymbleUI::Vec2.new(low.x + 20.0, low.bottom + 10.0)).should_not eq(WASH) # below it: clipped
    pixel(app, renderer, high.center).should eq(NAVY)                                             # the popup in front
  end

  # Moving from a zone to the zone around it: the outer one's wash, the inner one's gone.
  it "moves from an inner target to the one around it" do
    app, renderer = run do
      one_panel(zone("outer") { |o| o.add_child(vstack(DhpSwatch.new(150.0, GREY), zone("inner", 100.0, WASH2))) })
    end
    inner = find(app, "inner").viewport_bounds
    hover(app, renderer, CrymbleUI::Vec2.new(inner.x + 30.0, inner.center.y))
    target_id(app).should eq("inner") # instrument
    pixel(app, renderer, CrymbleUI::Vec2.new(inner.x + 30.0 + GHOST_CLEAR, inner.center.y)).should eq(WASH2)
    move(app, renderer, CrymbleUI::Vec2.new(inner.x + 30.0, inner.y - 100.0))
    target_id(app).should eq("outer") # instrument
    pixel(app, renderer, CrymbleUI::Vec2.new(inner.x + 30.0 + GHOST_CLEAR, inner.center.y)).should eq(WASH)
  end

  it "is released with the drag, and a second drag draws afresh" do
    app, renderer = run { one_panel(zone("z", 150.0)) }
    baseline = CrymbleUI::Layer.registry_size
    z = find(app, "z").viewport_bounds
    at = CrymbleUI::Vec2.new(z.x + 30.0, z.center.y)
    hover(app, renderer, at)
    released = [app.drag_manager.ghost_layer, app.drag_manager.highlight_layer].map(&.not_nil!.widgets.first)
    released.each(&.widget_backend.should_not(be_nil)) # instrument: both painted
    app.handle_mouse_up(at)
    renderer.render_frame(app)
    CrymbleUI::Layer.registry_size.should eq(baseline)
    released.each(&.widget_backend.should(be_nil))
    hover(app, renderer, at)
    pixel(app, renderer, at + CrymbleUI::Vec2.new(GHOST_CLEAR, 0.0)).should eq(WASH)
    renderer.backend.get_pixel(at.x.to_i, at.y.to_i).not_nil!.should_not eq(WASH) # the ghost over the wash
  end
end

# A drop target that leaves its highlight colour to DropTarget.
class DhpPlainTarget < DhpSwatch
  include CrymbleUI::DropTarget

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    true
  end

  def on_drop(data : CrymbleUI::DragData, position : CrymbleUI::Vec2)
  end

  def highlight_opacity : Float64
    1.0
  end
end
