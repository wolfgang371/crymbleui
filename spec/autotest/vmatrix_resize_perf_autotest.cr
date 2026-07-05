require "../../src/crymble-ui"

# SFML autotest — attribute the per-frame cost of a slow COLUMN-RESIZE drag on a sticky VirtualMatrix,
# in the real --release SFML build (real font/GPU/GC cost), driven programmatically (no human drag).
#
# Run:  crystal build --release spec/autotest/vmatrix_resize_perf_autotest.cr -o /tmp/vmatrix_resize_perf
#       DISPLAY=:0 CRYMBLE_PERF=1 /tmp/vmatrix_resize_perf 2> /tmp/vmatrix_resize_perf.log
# Then read the [PERF] lines between ### RESIZE-START / ### RESIZE-END — `render=` ms is the per-frame
# re-render cost, `widgets=` is how many widgets actually re-rendered that frame (the rest translate/blit).

# A realistic data cell: fills a background AND draws its text label (so the font cost is real).
class ResizePerfCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(@label : String, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), CrymbleUI::Color.new(45, 50, 55, 255))
      draw_text(@label, CrymbleUI::Vec2.new(4.0, 3.0), CrymbleUI::Color.new(220, 220, 220, 255), font_scale: -2)
    end
  end
end

# 30×40 grid, 2 sticky rows + 2 sticky cols (like the demo). Text cells.
class ResizePerfAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(2...30).to_a + [1, 0], (2...40).to_a + [1, 0]}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    ResizePerfCell.new("r#{row}c#{col}")
  end
end

class ResizePerfApp < CrymbleUI::App
  MOVES = 25
  DELAY = 50

  @phase = 0
  @scheduled = false
  @move = 0
  @bx = 0.0
  @by = 0.0

  def build : CrymbleUI::Widget
    if @phase == 0 && !@scheduled && scheduler_ready?
      @scheduled = true
      schedule_next(700)
    end
    window("VMatrix Resize Perf", 1100, 650) do
      vstack(padding: 8.0) do
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(ResizePerfAdapter.new, id: "m"))
        end
      end
    end
  end

  private def scheduler_ready? : Bool
    CrymbleUI::Widget.scheduler
    true
  rescue
    false
  end

  private def schedule_next(delay_ms : Int32)
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000)) { run_phase }
  end

  private def matrix : CrymbleUI::VirtualMatrix?
    find("m").as?(CrymbleUI::VirtualMatrix)
  end

  # Screen coords of the border after data column 3, in the col-ruler strip.
  private def col_border(m : CrymbleUI::VirtualMatrix, target : Int32)
    col_sizes = m.@cached_col_sizes.not_nil!
    sticky_cols = m.sticky_col_count
    acc = m.ruler_col_width_pixels + m.sticky_col_width_pixels
    border_local = acc + (sticky_cols..target).sum { |i| col_sizes[i].to_f64 }
    @bx = m.absolute_bounds.x + border_local
    @by = m.absolute_bounds.y + m.ruler_row_height_pixels / 2.0
  end

  private def run_phase
    m = matrix
    return unless m
    case @phase
    when 0
      STDERR.puts "### RESIZE-START (slow column-3 widen, #{MOVES} moves @ #{DELAY}ms)"
      col_border(m, 3)
      handle_mouse_down(CrymbleUI::Vec2.new(@bx, @by))
      @move = 0
      @phase = 1
      schedule_next(DELAY)
    when 1
      @move += 1
      # widen by a few px per move (a slow drag)
      handle_mouse_move(CrymbleUI::Vec2.new(@bx + @move * 4.0, @by))
      if @move >= MOVES
        handle_mouse_up(CrymbleUI::Vec2.new(@bx + @move * 4.0, @by))
        STDERR.puts "### RESIZE-END col3_width=#{m.get_col_width(3).round(1)}"
        @phase = 2
        schedule_next(500)
      else
        schedule_next(DELAY)
      end
    when 2
      STDERR.puts "### DONE"
      quit
    end
  end
end

app = ResizePerfApp.new
app.build_tree
root = app.root
raise "App.build() must return a Window widget" unless root.is_a?(CrymbleUI::Window)

window_widget = root.as(CrymbleUI::Window)
renderer = CrymbleUI::SFMLRenderer.new(
  width: window_widget.width,
  height: window_widget.height,
  title: window_widget.title
)
renderer.run(app)
