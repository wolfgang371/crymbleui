require "../../src/crymble-ui"

# SFML AUTOTEST - where the drop highlight shows in the REAL renderer: the headless placement spec
# (spec/rendering/drop_highlight_placement_spec.cr) read back through the SFML compositor and the window's own
# pixels. Two scenes: a target a scroll view clips (incl. the clip edge - a pixel of PixelSnap bleed would
# show above it), and a target partly under a panel in front.
#
# The window is read, not Testing::LayerCapture: that composites the tree's layers (Layer.active_layers),
# which leaves out the drag's ownerless ghost and highlight. The CONTROL proves the read sees them: the pixel
# under the ghost is neither the wash nor the bare target.
#
# Run: source setup.sh
#      crystal build spec/autotest/drop_highlight_autotest.cr -o /tmp/dhl_autotest
#      DISPLAY=:0 timeout 60 /tmp/dhl_autotest      (exit 0: every check held)

lib LibCSFML
  fun sfTexture_updateFromRenderWindow(texture : Texture, render_window : RenderWindow, offset : Vector2u)
end

private WASH = CrymbleUI::Color.new(255, 0, 0, 255)
private GREY = CrymbleUI::Color.new(200, 200, 200, 255)
private NAVY = CrymbleUI::Color.new(0, 0, 120, 255)

class DhlSwatch < CrymbleUI::Widget
  def initialize(@height : Float64, @color : CrymbleUI::Color, @width : Float64? = nil)
    super(id: nil)
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

private def dhl_zone(height : Float64, id : String? = nil) : CrymbleUI::DropZoneBox
  CrymbleUI::DropZoneBox.new(accept_types: ["text"], hover_color: WASH, highlight_opacity: 1.0, id: id)
    .tap(&.add_child(DhlSwatch.new(height, GREY)))
end

class DropHighlightAutoTest < CrymbleUI::App
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("drop highlight autotest", 900, 640)
    chip = CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new("x"), id: "chip")
    chip.add_child(DhlSwatch.new(20.0, CrymbleUI::Color.new(0, 0, 200, 255), 20.0))
    window.add_child(CrymbleUI::VStack.new.tap(&.add_child(chip)))

    clip = CrymbleUI::WindowPanel.new("clip", 20.0, 60.0, 260.0, 280.0, id: "clip")
    sv = CrymbleUI::ScrollView.new(max_height: 120.0, id: "sv")
    sv.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |s| s.add_child(dhl_zone(200.0, "a")); s.add_child(DhlSwatch.new(400.0, NAVY)) })
    clip.add_child(CrymbleUI::VStack.new(spacing: 0.0).tap { |s| s.add_child(DhlSwatch.new(60.0, CrymbleUI::Color.new(0, 150, 0, 255))); s.add_child(sv) })

    back = CrymbleUI::WindowPanel.new("back", 320.0, 60.0, 260.0, 280.0, id: "back")
    back.add_child(dhl_zone(200.0, "b"))
    front = CrymbleUI::WindowPanel.new("front", 460.0, 100.0, 180.0, 180.0, id: "front")
    front.add_child(DhlSwatch.new(160.0, NAVY))

    [clip, back, front].each { |p| window.add_child(p) }
    window
  end
end

# One pointer drag per scene, the window read after it settles.
class DhlDriver
  getter failures = 0
  @frame = 0
  @steps = [] of {Int32, Proc(Nil)} # {frames to wait first, what to do}

  def initialize(@app : DropHighlightAutoTest, @renderer : CrymbleUI::SFMLRenderer)
  end

  private def log(s : String) : Nil
    puts s
    STDOUT.flush
  end

  private def find(id : String) : CrymbleUI::Widget
    @app.find(id) || raise "no widget #{id}"
  end

  # The window's pixels as composited now: the frame is composited again into the back buffer (the one just
  # displayed is gone with the swap) and read from there.
  private def window_image : SF::Image
    window = @renderer.window.not_nil!
    root = @app.root.not_nil!
    dm = @app.drag_manager
    @renderer.render_all_layers(root, dm.ghost_layer, dm.highlight_layer)
    size = window.size
    texture = SF::Texture.new(size.x, size.y)
    LibCSFML.sfTexture_updateFromRenderWindow(texture, window, LibCSFML::Vector2u.new(x: 0_u32, y: 0_u32))
    texture.copy_to_image
  end

  private def check(scene : String, what : String, image : SF::Image, x : Int32, y : Int32, wash : Bool) : Nil
    px = image.get_pixel(x, y)
    is_wash = px.r == WASH.r && px.g == WASH.g && px.b == WASH.b
    ok = is_wash == wash
    @failures += 1 unless ok
    log "  #{ok ? "ok  " : "FAIL"} #{scene}: #{what} at (#{x},#{y}) is #{is_wash ? "" : "not "}the wash (rgb #{px.r},#{px.g},#{px.b})"
  end

  # The control: the ghost is there, over the wash, so the read sees the drag's own layers.
  private def control(scene : String, image : SF::Image, at : CrymbleUI::Vec2) : Nil
    px = image.get_pixel(at.x.to_i, at.y.to_i)
    plain = {WASH, GREY}.any? { |c| px.r == c.r && px.g == c.g && px.b == c.b }
    @failures += 1 if plain
    log "  #{plain ? "FAIL" : "ok  "} #{scene}: control - under the ghost (rgb #{px.r},#{px.g},#{px.b}) is neither wash nor bare target"
  end

  private def expect_target(scene : String, target : CrymbleUI::Widget?) : Nil
    return if (t = @app.drag_manager.state.current_target) && (target.nil? || t.same?(target))
    @failures += 1
    log "  FAIL #{scene}: VOID - the drag is not over the intended target"
  end

  # A drag from the chip onto `at`, then `checks` on the window once it settled, then the drop.
  private def scene(name : String, at : Proc(CrymbleUI::Vec2), target : Proc(CrymbleUI::Widget?), &checks : SF::Image, CrymbleUI::Vec2 -> Nil) : Nil
    point = CrymbleUI::Vec2.zero
    @steps << {10, -> {
      from = find("chip").viewport_bounds.center
      point = at.call
      @app.handle_mouse_down(from)
      @app.handle_mouse_move(from + CrymbleUI::Vec2.new(0.0, 12.0))
      @app.handle_mouse_move(point)
      @app.handle_mouse_move(point)
      nil
    }}
    @steps << {10, -> {
      log "#{name}:"
      expect_target(name, target.call)
      image = window_image
      checks.call(image, point)
      control(name, image, point)
      @app.handle_mouse_up(point)
      nil
    }}
  end

  def plan : Nil
    @steps << {30, -> {
      find("sv").as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 50.0))
      find("front").as(CrymbleUI::WindowPanel).bring_to_front
      nil
    }}

    scene("scroll clip", -> {
      a, view = find("a").viewport_bounds, find("sv").viewport_bounds
      CrymbleUI::Vec2.new(a.center.x - 60.0, view.y + 30.0)
    }, -> { find("a").as(CrymbleUI::Widget?) }) do |image, _|
      a, view = find("a").viewport_bounds, find("sv").viewport_bounds
      x = (a.center.x + 60.0).to_i
      check("scroll clip", "inside the view", image, x, (view.y + 10.0).to_i, true)
      check("scroll clip", "the view's first row", image, x, view.y.ceil.to_i, true)
      check("scroll clip", "the row above the view (edge bleed)", image, x, view.y.floor.to_i - 1, false)
      check("scroll clip", "above the view", image, x, (view.y - 10.0).to_i, false)
    end

    scene("covered", -> {
      b = find("b").viewport_bounds
      CrymbleUI::Vec2.new(b.x + 30.0, b.y + 150.0)
    }, -> { find("b").as(CrymbleUI::Widget?) }) do |image, _|
      b, front = find("b").viewport_bounds, find("front").viewport_bounds
      check("covered", "the uncovered part", image, (b.x + 30.0).to_i, (b.y + 90.0).to_i, true)
      check("covered", "under the panel in front", image, (front.x + 20.0).to_i, (front.y + 60.0).to_i, false)
    end

    @steps << {5, -> {
      log(@failures == 0 ? "ALL CHECKS HELD" : "#{@failures} CHECK(S) FAILED")
      exit(@failures == 0 ? 0 : 1)
    }}
  end

  def on_frame : Nil
    return if @steps.empty?
    @frame += 1
    wait, step = @steps.first
    return if @frame < wait
    @steps.shift
    @frame = 0
    step.call
  end
end

app = DropHighlightAutoTest.new
app.build_tree
root = app.root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(width: root.width, height: root.height, title: root.title)
driver = DhlDriver.new(app, renderer)
driver.plan
CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: 16_000_000), repeating: true) { driver.on_frame }
renderer.run(app)
