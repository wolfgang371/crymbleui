require "../../src/crymble-ui"

# SFML AUTOTEST - a layer inside scrolled content in the REAL renderer (the headless
# spec/rendering/scrolled_layer_space_spec.cr, read back through the SFML compositor and the window's own pixels).
# Scenes: a scroll view in a scroll view with the inner scrolled half out of the outer view - nothing of it above
# the view; the outer scrolled then the panel raised (a full repaint) - the inner's content where it is drawn; a
# grid in a scroll view scrolled - its header row where the grid is drawn. Every sample is read twice: from the window
# and from capture_composited_frame, which must agree.
#
# Content is an L-marker: a 4px top band and a 4px left stripe over a body colour, so a shift by the scroll (>= 8
# here) on either axis shows.
#
# Run: source setup.sh
#      crystal build spec/autotest/scrolled_layer_space_autotest.cr -o /tmp/sls_autotest
#      DISPLAY=:0 timeout 60 /tmp/sls_autotest      (exit 0: every check held)

lib LibCSFML
  fun sfTexture_updateFromRenderWindow(texture : Texture, render_window : RenderWindow, offset : Vector2u)
end

private BAND   = CrymbleUI::Color.new(220, 40, 40, 255)
private STRIPE = CrymbleUI::Color.new(40, 40, 220, 255)
private BODY   = CrymbleUI::Color.new(40, 200, 40, 255)
private FILL   = CrymbleUI::Color.new(90, 90, 90, 255)
private HEAD   = CrymbleUI::Color.new(0, 0, 90, 255)
private CELL   = CrymbleUI::Color.new(230, 230, 230, 255)

class SlaSwatch < CrymbleUI::Widget
  def initialize(@width : Float64, @height : Float64, @color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@width, @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

class SlaMarker < SlaSwatch
  def initialize(width : Float64, height : Float64, id : String? = nil)
    super(width, height, BODY, id)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), BODY),
     CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, 4.0, bounds.height), STRIPE),
     CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, 4.0), BAND)].map(&.as(CrymbleUI::DrawPrimitive))
  end
end

# Fills the cell it is laid out in.
class SlaFill < CrymbleUI::Widget
  def initialize(@color : CrymbleUI::Color)
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width.finite? ? constraints.max_width : 40.0,
      constraints.max_height.finite? ? constraints.max_height : 10.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

# Row 0 a sticky header.
class SlaGridAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...20).to_a + [0], (0...6).to_a}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    SlaFill.new(row == 0 ? HEAD : CELL)
  end
end

class ScrolledLayerSpaceAutoTest < CrymbleUI::App
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("scrolled layer space autotest", 900, 600)
    nested = CrymbleUI::WindowPanel.new("nested", 20.0, 40.0, 420.0, 420.0, id: "p")
    outer = CrymbleUI::ScrollView.new(CrymbleUI::ScrollDirection::Both, max_height: 300.0, id: "outer")
    inner = CrymbleUI::ScrollView.new(max_height: 60.0, id: "inner").tap(&.set_content(SlaMarker.new(300.0, 200.0)))
    outer.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap do |v|
      v.add_child(SlaSwatch.new(900.0, 100.0, FILL))
      v.add_child(CrymbleUI::HStack.new(spacing: 0.0).tap { |h| h.add_child(SlaSwatch.new(30.0, 60.0, FILL)); h.add_child(inner) })
      v.add_child(SlaSwatch.new(900.0, 600.0, FILL))
    end)
    nested.add_child(outer)
    gridded = CrymbleUI::WindowPanel.new("grid", 460.0, 40.0, 420.0, 420.0, id: "gp")
    outer2 = CrymbleUI::ScrollView.new(max_height: 300.0, id: "outer2")
    # its cursor overlay paints nothing (delta 0): the checks read cells where its bands would lie
    vm = CrymbleUI::VirtualMatrix.new(adapter: SlaGridAdapter.new, id: "grid", cursor_highlight_delta: 0)
    vm.shrink_to_content = true
    outer2.set_content(CrymbleUI::VStack.new(spacing: 0.0).tap { |v| v.add_child(SlaSwatch.new(380.0, 100.0, FILL)); v.add_child(vm); v.add_child(SlaSwatch.new(380.0, 600.0, FILL)) })
    gridded.add_child(outer2)
    window.add_child(nested)
    window.add_child(gridded)
    window
  end
end

class SlaDriver
  getter failures = 0
  @frame = 0
  @steps = [] of {Int32, Proc(Nil)}

  def initialize(@app : ScrolledLayerSpaceAutoTest, @renderer : CrymbleUI::SFMLRenderer)
  end

  private def log(s : String) : Nil
    puts s
    STDOUT.flush
  end

  private def find(id : String) : CrymbleUI::Widget
    @app.find(id) || raise "no widget #{id}"
  end

  private def scroll(id : String, x : Float64, y : Float64) : Nil
    find(id).as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(x, y))
  end

  # The window's pixels as composited now (the frame composited again into the back buffer and read there), and
  # the frame capture of the same state.
  private def images : {SF::Image, SF::Image}
    window = @renderer.window.not_nil!
    dm = @app.drag_manager
    @renderer.render_all_layers(@app.root.not_nil!, dm.ghost_layer, dm.highlight_layer)
    size = window.size
    texture = SF::Texture.new(size.x, size.y)
    LibCSFML.sfTexture_updateFromRenderWindow(texture, window, LibCSFML::Vector2u.new(x: 0_u32, y: 0_u32))
    {texture.copy_to_image, @renderer.capture_composited_frame(@app)}
  end

  private def check(what : String, shots : {SF::Image, SF::Image}, x : Float64, y : Float64, expected : CrymbleUI::Color, equal : Bool = true) : Nil
    {"window", "capture"}.each_with_index do |source, i|
      px = shots[i].get_pixel(x.to_i, y.to_i)
      same = px.r == expected.r && px.g == expected.g && px.b == expected.b
      ok = same == equal
      @failures += 1 unless ok
      log "  #{ok ? "ok  " : "FAIL"} #{what} (#{source}) at (#{x.to_i},#{y.to_i}): rgb #{px.r},#{px.g},#{px.b} #{equal ? "==" : "!="} #{expected.r},#{expected.g},#{expected.b}"
    end
  end

  def plan : Nil
    @steps << {30, -> {
      inner = find("inner")
      view = find("outer").viewport_bounds
      scroll("outer", 0.0, inner.absolute_bounds.y - view.y + 20.0) # the inner's top 20 above the view's top
      nil
    }}
    @steps << {10, -> {
      shots = images
      view = find("outer").viewport_bounds
      x = find("inner").viewport_bounds.x
      log "the inner scrolled half out of the outer view (composited, not repainted):"
      check("control - its content inside the view", shots, x + 20.0, view.y + 5.0, BODY)
      check("nothing of it above the view", shots, x + 20.0, view.y - 5.0, BODY, equal: false)
      check("nothing of its band above the view", shots, x + 20.0, view.y - 18.0, BAND, equal: false)
      nil
    }}
    @steps << {5, -> { scroll("outer", 6.0, 8.0); nil }}
    @steps << {10, -> { find("p").as(CrymbleUI::WindowPanel).bring_to_front; nil }}
    @steps << {10, -> {
      shots = images
      abs = find("inner").absolute_bounds
      x, y = abs.x - 6.0, abs.y - 8.0 # by hand: laid out, minus the outer scroll
      log "a scroll view in a scroll view, the outer scrolled (6, 8), then a full repaint:"
      check("the marker's top band", shots, x + 12.0, y + 2.0, BAND)
      check("the marker's left stripe", shots, x + 2.0, y + 12.0, STRIPE)
      check("the marker's body", shots, x + 8.0, y + 8.0, BODY)
      nil
    }}
    @steps << {5, -> { scroll("outer2", 0.0, 60.0); nil }}
    @steps << {10, -> { find("gp").as(CrymbleUI::WindowPanel).bring_to_front; nil }}
    @steps << {10, -> {
      shots = images
      grid = find("grid")
      drawn = grid.viewport_bounds
      log "a grid in a scroll view scrolled 60:"
      # (below the grid's 20px column ruler)
      check("its header where the grid is drawn", shots, drawn.x + 60.0, drawn.y + 28.0, HEAD)
      check("nothing of it where it is laid out (60 lower)", shots, drawn.x + 60.0, drawn.y + 88.0, HEAD, equal: false)
      nil
    }}
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

app = ScrolledLayerSpaceAutoTest.new
app.build_tree
root = app.root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(width: root.width, height: root.height, title: root.title)
driver = SlaDriver.new(app, renderer)
driver.plan
CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: 16_000_000), repeating: true) { driver.on_frame }
renderer.run(app)
