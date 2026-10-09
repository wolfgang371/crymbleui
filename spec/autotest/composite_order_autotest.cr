require "../../src/crymble-ui"

# SFML AUTOTEST - the composite order in the REAL renderer (the headless spec/rendering/composite_order_spec.cr,
# read back through the SFML compositor and the window's own pixels). Scenes: a grid whose cells hold a scroll view,
# scrolled under the sticky header (the header over the nested content and scrollbar; below the band both visible);
# a scroll view in a sticky header cell (visible over the band); the window's statusbar over a panel taller than
# the panel area.
#
# The window is read, not Testing::LayerCapture (it composites the tree's layers itself). The CONTROL: a pixel of
# the nested scroll view's content where nothing covers it - the read sees nested layers at all.
#
# Run: source setup.sh
#      crystal build spec/autotest/composite_order_autotest.cr -o /tmp/co_autotest
#      DISPLAY=:0 timeout 60 /tmp/co_autotest      (exit 0: every check held)

lib LibCSFML
  fun sfTexture_updateFromRenderWindow(texture : Texture, render_window : RenderWindow, offset : Vector2u)
end

private HEAD  = CrymbleUI::Color.new(0, 0, 90, 255)
private INNER = CrymbleUI::Color.new(0, 200, 0, 255)
private NAVY  = CrymbleUI::Color.new(0, 0, 120, 255)

class CoaSwatch < CrymbleUI::Widget
  def initialize(@height : Float64, @color : CrymbleUI::Color)
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(constraints.max_width.finite? ? constraints.max_width : 100.0, @height)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @color).as(CrymbleUI::DrawPrimitive)]
  end
end

private def coa_scroller(id : String) : CrymbleUI::ScrollView
  CrymbleUI::ScrollView.new(max_height: 10.0, id: id).tap(&.set_content(CoaSwatch.new(40.0, INNER)))
end

# Row 0 a sticky header whose column-1 cell holds a scroll view; every other cell holds one too.
class CoaGridAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(1...20).to_a + [0], [0, 1]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    if row == 0
      return CoaSwatch.new(10.0, HEAD) unless col == 1
      return CrymbleUI::VStack.new(spacing: 0.0).tap(&.add_child(coa_scroller("hdr_sv")))
    end
    CrymbleUI::VStack.new(spacing: 0.0).tap(&.add_child(coa_scroller("sv_#{row}_#{col}")))
  end
end

class CompositeOrderAutoTest < CrymbleUI::App
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("composite order autotest", 900, 600)
    grid_panel = CrymbleUI::WindowPanel.new("grid", 20.0, 40.0, 400.0, 300.0, z_index: 1, id: "gp")
    # its cursor overlay paints nothing (delta 0): the checks read row 0 and column 0, where its bands would lie
    vm = CrymbleUI::VirtualMatrix.new(adapter: CoaGridAdapter.new, id: "grid", cursor_highlight_delta: 0)
    grid_panel.add_child(vm)
    tall = CrymbleUI::WindowPanel.new("tall", 480.0, 40.0, 300.0, 800.0, z_index: 2, id: "tall")
    tall.add_child(CoaSwatch.new(780.0, NAVY))
    window.add_child(grid_panel)
    window.add_child(tall)
    window.add_child(CrymbleUI::StatusBar.new("Ready", id: "status"))
    window
  end
end

class CoaDriver
  getter failures = 0
  @frame = 0
  @steps = [] of {Int32, Proc(Nil)}

  def initialize(@app : CompositeOrderAutoTest, @renderer : CrymbleUI::SFMLRenderer)
  end

  private def log(s : String) : Nil
    puts s
    STDOUT.flush
  end

  private def find(id : String) : CrymbleUI::Widget
    @app.find(id) || raise "no widget #{id}"
  end

  # The window's pixels as composited now (the frame composited again into the back buffer and read there).
  private def window_image : SF::Image
    window = @renderer.window.not_nil!
    dm = @app.drag_manager
    @renderer.render_all_layers(@app.root.not_nil!, dm.ghost_layer, dm.highlight_layer)
    size = window.size
    texture = SF::Texture.new(size.x, size.y)
    LibCSFML.sfTexture_updateFromRenderWindow(texture, window, LibCSFML::Vector2u.new(x: 0_u32, y: 0_u32))
    texture.copy_to_image
  end

  private def check(what : String, image : SF::Image, at : CrymbleUI::Vec2, expected : CrymbleUI::Color, equal : Bool = true) : Nil
    px = image.get_pixel(at.x.to_i, at.y.to_i)
    same = px.r == expected.r && px.g == expected.g && px.b == expected.b
    ok = same == equal
    @failures += 1 unless ok
    log "  #{ok ? "ok  " : "FAIL"} #{what} at (#{at.x.to_i},#{at.y.to_i}): rgb #{px.r},#{px.g},#{px.b} #{equal ? "==" : "!="} #{expected.r},#{expected.g},#{expected.b}"
  end

  def plan : Nil
    @steps << {30, -> {
      find("grid").as(CrymbleUI::VirtualMatrix).scroll_offset = CrymbleUI::Vec2.new(0.0, 8.0)
      nil
    }}
    @steps << {20, -> {
      image = window_image
      vm = find("grid").as(CrymbleUI::VirtualMatrix)
      header = vm.active_cells[{0, 0}].viewport_bounds
      c = find("sv_1_0").viewport_bounds
      s = find("sv_3_0").viewport_bounds
      under = (c.y + header.bottom) / 2.0
      log "grid, cells holding a scroll view, under the sticky header:"
      check("control - uncovered nested content", image, CrymbleUI::Vec2.new(c.x + 10.0, s.y + 5.0), INNER)
      check("the header over the nested content", image, CrymbleUI::Vec2.new(c.x + 10.0, under), HEAD)
      check("the header over the nested scrollbar", image, CrymbleUI::Vec2.new(c.right - 3.0, under), HEAD)
      h = find("hdr_sv").viewport_bounds
      log "a scroll view in a sticky header cell:"
      check("its content over the band", image, CrymbleUI::Vec2.new(h.x + 10.0, h.y + 5.0), INNER)
      st = find("status").viewport_bounds
      log "the window's statusbar over a panel reaching it:"
      check("the statusbar, not the panel", image, CrymbleUI::Vec2.new(find("tall").viewport_bounds.x + 50.0, st.y + st.height / 2.0), NAVY, equal: false)
      check("control - the panel above the bar", image, CrymbleUI::Vec2.new(find("tall").viewport_bounds.x + 50.0, st.y - 30.0), NAVY)
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

app = CompositeOrderAutoTest.new
app.build_tree
root = app.root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(width: root.width, height: root.height, title: root.title)
driver = CoaDriver.new(app, renderer)
driver.plan
CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: 16_000_000), repeating: true) { driver.on_frame }
renderer.run(app)
