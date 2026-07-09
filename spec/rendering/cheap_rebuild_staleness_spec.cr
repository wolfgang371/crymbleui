require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/layout/vstack"
require "../../src/rendering/layer_renderer"

CELL_RED    = CrymbleUI::Color.new(200, 30, 30, 255)
CELL_GREEN  = CrymbleUI::Color.new(30, 200, 30, 255)
CELL_BLUE   = CrymbleUI::Color.new(30, 30, 200, 255)
PARENT_FILL = CrymbleUI::Color.new(180, 120, 40, 255)
STACK_BG1   = CrymbleUI::Color.new(60, 60, 60, 255)
STACK_BG2   = CrymbleUI::Color.new(130, 130, 130, 255)

# Fixed-measure OPAQUE cell (full FillRect) — a safe same-bounds content change (colour flip) that a
# text widget can't model (text change = width change = structural). Colour is a plain ivar (not
# reconciled), so each fresh build() carries the new colour.
class SolidCell < CrymbleUI::Widget
  property color : CrymbleUI::Color

  def initialize(@color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(60.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color)] of CrymbleUI::DrawPrimitive
  end
end

# PARTIAL-cover cell: a small FillRect in the centre, leaving a wide uncovered border that shows the
# BACKGROUND behind it. This is the faithful ghost probe — if a selective re-render used the wrong
# background (flat layer bg instead of the memorized parent fill), the uncovered border would change.
class PartialCell < CrymbleUI::Widget
  property color : CrymbleUI::Color

  def initialize(@color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(60.0, 20.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(20.0, 6.0, 20.0, 8.0), @color)] of CrymbleUI::DrawPrimitive # centre only
  end
end

# Content lives inside a WindowPanel (a NESTED layer owner) — the panel layer is NOT auto-NeedsLayout
# on rebuild (only the window ROOT layer is, via request_rebuild), so its assessment can go selective.
# This mirrors embrace (Shapes are panels).
private def panel_window(w = 240, h = 220)
  window = CrymbleUI::Window.new("T", w, h)
  panel = CrymbleUI::WindowPanel.new("P", x: 16.0, y: 16.0, width: (w - 32).to_f, height: (h - 32).to_f, id: "panel")
  window.add_child(panel)
  {window, panel}
end

# Two opaque cells on one panel layer; toggling `on` flips only cell_a's colour (same bounds).
class TwoCellApp < CrymbleUI::App
  property on : Bool = false

  def build : CrymbleUI::Widget
    window, panel = panel_window
    vstack = CrymbleUI::VStack.new(spacing: 6.0, padding: 8.0)
    vstack.add_child(SolidCell.new(@on ? CELL_GREEN : CELL_RED, id: "cell_a"))
    vstack.add_child(SolidCell.new(CELL_BLUE, id: "cell_b"))
    panel.add_child(vstack)
    window
  end
end

# A partial-cover leaf over a COLOURED PARENT FILL on the same panel layer; toggling `on` flips the
# leaf's covered colour (same bounds). The uncovered border must keep showing the parent fill.
class ParentFillApp < CrymbleUI::App
  property on : Bool = false

  def build : CrymbleUI::Widget
    window, panel = panel_window
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 24.0, background_color: PARENT_FILL)
    vstack.add_child(PartialCell.new(@on ? CELL_GREEN : CELL_RED, id: "cell"))
    panel.add_child(vstack)
    window
  end
end

# A coloured container (its fill toggles) WITH a child — guard A: a changed container must full-clear,
# not selectively blit over (and erase) its child.
class ContainerFillApp < CrymbleUI::App
  property alt : Bool = false

  def build : CrymbleUI::Widget
    window, panel = panel_window
    vstack = CrymbleUI::VStack.new(spacing: 0.0, padding: 24.0, background_color: @alt ? STACK_BG2 : STACK_BG1)
    vstack.add_child(SolidCell.new(CELL_RED, id: "cell")) # child colour never changes
    panel.add_child(vstack)
    window
  end
end

# Cheap rebuild — a rebuild that changed nothing must re-render NOTHING (per-layer content staleness);
# a rebuild that changed something must re-render the affected layer with a full clear (no ghost).
# See docs/plans/. frame_widget_count counts only ACTUALLY re-rasterized widgets (skipped layers /
# cache hits = 0), identically headless and SFML.

private def lr
  CrymbleUI::LayerRenderer
end

# A matrix-free, cursor-free app whose build() reconstructs a fresh tree from @labels each rebuild
# (TestApp.build returns the same instance → no real reconcile, so it can't be used here). Buttons
# (filled backgrounds) make get_pixel over a vacated row a reliable ghost probe.
class StaticStackApp < CrymbleUI::App
  property labels : Array(String) = ["Alpha", "Beta", "Gamma", "Delta"]
  property gap : Float64 = 4.0

  def build : CrymbleUI::Widget
    window("Spike", 400, 320) do
      window_panel("P", x: 20.0, y: 20.0, width: 300.0, height: 260.0, id: "panel") do
        vstack(id: "stack", spacing: @gap) do
          @labels.each_with_index do |lbl, i|
            button(lbl, id: "row_#{i}") { }
          end
        end
      end
    end
  end
end

# Two independent panels on their own layers — for cross-panel isolation.
class TwoPanelApp < CrymbleUI::App
  property show_a : Bool = true

  def build : CrymbleUI::Widget
    window("Multi", 500, 320) do
      window_panel("A", x: 20.0, y: 20.0, width: 220.0, height: 110.0, id: "pa") do
        button("AAA", id: "btn_a") { } if @show_a
      end
      window_panel("B", x: 20.0, y: 150.0, width: 220.0, height: 110.0, id: "pb") do
        button("BBB", id: "btn_b") { }
      end
    end
  end
end

private def center_pixel(renderer, widget)
  b = widget.absolute_bounds
  renderer.backend.get_pixel((b.x + b.width / 2).to_i, (b.y + b.height / 2).to_i)
end

describe "cheap rebuild — per-layer content staleness" do
  it "a same-content rebuild re-renders ZERO widgets" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 320)
    app = StaticStackApp.new
    app.build_tree
    renderer.settle_rendering(app)

    lr.reset_frame_counters
    app.request_rebuild # identical tree — nothing changed
    renderer.render_frame(app)
    puts "\n[cheap-rebuild spike] same-content rebuild → frame_widget_count = #{lr.frame_widget_count}"
    lr.frame_widget_count.should eq 0
  end

  it "a rebuild that REMOVES a row leaves no ghost at the vacated position" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 320)
    app = StaticStackApp.new
    app.build_tree
    renderer.settle_rendering(app)

    last = app.find("row_3").not_nil!
    lb = last.absolute_bounds
    px = (lb.x + lb.width / 2).to_i
    py = (lb.y + lb.height / 2).to_i
    pixel_before = renderer.backend.get_pixel(px, py) # inside the button fill

    app.labels = ["Alpha", "Beta", "Gamma"] # drop the last row
    app.request_rebuild
    renderer.render_frame(app)

    pixel_after = renderer.backend.get_pixel(px, py)
    # the vacated region must NOT still show the removed button's pixels (ghost)
    pixel_after.should_not eq(pixel_before)
  end

  it "a same-content rebuild KEEPS the carried pixels (skip must not blank the buffer)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 320)
    app = StaticStackApp.new
    app.build_tree
    renderer.settle_rendering(app)

    before = center_pixel(renderer, app.find("row_1").not_nil!)
    app.request_rebuild
    renderer.render_frame(app)
    # skipped layer ⇒ carried buffer re-blits ⇒ the button pixel is still there, unchanged (not blank)
    center_pixel(renderer, app.find("row_1").not_nil!).should eq(before)
  end

  it "a rebuild that MOVES rows (no content change) is NOT skipped (no moved-freeze)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 320)
    app = StaticStackApp.new
    app.build_tree
    renderer.settle_rendering(app)

    app.gap = 34.0 # wider spacing → every row shifts down; local primitives unchanged
    lr.reset_frame_counters
    app.request_rebuild
    renderer.render_frame(app)
    puts "[cheap-rebuild moved] row-move rebuild → frame_widget_count = #{lr.frame_widget_count}"
    # absolute_bounds changed ⇒ signature differs ⇒ the layer re-renders (a version/local-only key
    # would wrongly skip and freeze the rows at their old positions)
    lr.frame_widget_count.should be > 0
  end

  it "a rebuild changing panel A does not disturb panel B (cross-layer isolation)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(500, 320)
    app = TwoPanelApp.new
    app.build_tree
    renderer.settle_rendering(app)

    b_before = center_pixel(renderer, app.find("btn_b").not_nil!)
    ab = app.find("btn_a").not_nil!.absolute_bounds # capture A's button position before it's removed
    ax = (ab.x + ab.width / 2).to_i
    ay = (ab.y + ab.height / 2).to_i
    a_before = renderer.backend.get_pixel(ax, ay) # button fill

    app.show_a = false # only panel A changes (button removed)
    app.request_rebuild
    renderer.render_frame(app)

    # A re-rendered — the removed button's fill is gone (panel bg now), B untouched (buffer survives)
    renderer.backend.get_pixel(ax, ay).should_not eq(a_before)
    center_pixel(renderer, app.find("btn_b").not_nil!).should eq(b_before)
  end
end

describe "cheap rebuild — intra-layer selective render (milestone 2)" do
  it "an opaque same-bounds content change re-renders ONLY the changed widget" do
    renderer = CrymbleUI::Testing::TestRenderer.new(220, 160)
    app = TwoCellApp.new
    app.build_tree
    renderer.settle_rendering(app)

    b_before = center_pixel(renderer, app.find("cell_b").not_nil!)
    app.on = true # only cell_a's colour changes; same bounds
    lr.reset_frame_counters
    app.request_rebuild
    renderer.render_frame(app)

    puts "\n[cheap-rebuild selective] one content change → frame_widget_count = #{lr.frame_widget_count}"
    lr.frame_widget_count.should eq 1                                       # ONLY cell_a (milestone-1 full-clear = 2)
    center_pixel(renderer, app.find("cell_b").not_nil!).should eq(b_before) # sibling pixels intact
    renderer.exceptions_caught.should eq 0
  end

  it "a partial-cover leaf over a parent fill keeps the parent-fill background (no wrong-bg ghost)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(220, 160)
    app = ParentFillApp.new
    app.build_tree
    renderer.settle_rendering(app)

    cell = app.find("cell").not_nil!
    cb = cell.absolute_bounds
    ux = (cb.x + 5).to_i # local x=5 → left of the centre FillRect (x in [20,40]) → uncovered
    uy = (cb.y + 10).to_i
    renderer.backend.get_pixel(ux, uy).should eq(PARENT_FILL) # sanity: uncovered shows the parent fill

    app.on = true # flip the covered colour; same bounds → selective
    lr.reset_frame_counters
    app.request_rebuild
    renderer.render_frame(app)

    # the selective re-render restored the MEMORIZED parent fill → uncovered border still PARENT_FILL,
    # NOT the flat layer bg, NOT stale; and no swallowed invariant-(h) self-capture assert.
    renderer.backend.get_pixel(ux, uy).should eq(PARENT_FILL)
    renderer.exceptions_caught.should eq 0
    lr.frame_widget_count.should eq 1
  end

  it "a changed CONTAINER fill full-clears so its child is not erased (guard A)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(220, 160)
    app = ContainerFillApp.new
    app.build_tree
    renderer.settle_rendering(app)

    app.alt = true # the VStack's fill colour changes; it HAS a child
    lr.reset_frame_counters
    app.request_rebuild
    renderer.render_frame(app)

    # guard A → full-clear → the child re-renders; a wrong selective blit of the container would have
    # painted its fill over (erased) the child.
    center_pixel(renderer, app.find("cell").not_nil!).should eq(CELL_RED)
    renderer.exceptions_caught.should eq 0
  end
end
