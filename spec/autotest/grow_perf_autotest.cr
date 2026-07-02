require "../../src/crymble-ui"

# SFML autotest — attribute the per-frame cost of a panel GROW for a FLOORED panel vs a SCROLLVIEW panel,
# in the real --release SFML build (real font/GPU/GC costs), driven programmatically (no human drag).
#
# Run:  crystal build --release spec/autotest/grow_perf_autotest.cr -o /tmp/grow_perf_autotest
#       DISPLAY=:0 CRYMBLE_PERF=1 /tmp/grow_perf_autotest 2> /tmp/grow_perf.log
# Then read the [PERF] lines between the ### FLOORED-RESIZE / ### SCROLL-RESIZE markers: the (flush=… collect=…)
# breakdown inside render= attributes the cost to layout_children (flush) vs the viewport-cull walk (collect).
class GrowPerfAutotest < CrymbleUI::App
  ROWS  =  20
  COLS  =  20
  MOVES =  25
  DELAY =  50

  @phase = 0
  @scheduled = false
  @move = 0
  @start_x = 0.0

  def build : CrymbleUI::Widget
    if @phase == 0 && !@scheduled && scheduler_ready?
      @scheduled = true
      schedule_next(700)
    end

    window("GrowPerf Autotest", 1600, 950) do
      window_panel(title: "Floored", x: 20.0, y: 60.0, width: 600.0, height: 620.0, resizable: true, id: "floored") do
        vstack(spacing: 2.0) do
          ROWS.times do |r|
            hstack(spacing: 2.0) do
              COLS.times { |c| button("#{r},#{c}", font_scale: -5, padding: 3.0) { } }
            end
          end
        end
      end

      window_panel(title: "Scroll", x: 1000.0, y: 60.0, width: 420.0, height: 620.0, resizable: true, id: "scroll") do
        scroll_view(direction: CrymbleUI::ScrollDirection::Both, id: "scroll_sv") do
          vstack(spacing: 2.0) do
            ROWS.times do |r|
              hstack(spacing: 2.0) do
                COLS.times { |c| button("#{r},#{c}", font_scale: -5, padding: 3.0) { } }
              end
            end
          end
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
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000)) do
      run_phase
    end
  end

  private def panel(id : String) : CrymbleUI::WindowPanel?
    find(id).as?(CrymbleUI::WindowPanel)
  end

  private def start_resize(id : String)
    return unless p = panel(id)
    @start_x = p.x + p.width - 3.0
    handle_mouse_down(CrymbleUI::Vec2.new(@start_x, p.y + p.height / 2.0))
  end

  private def move_resize(id : String)
    return unless p = panel(id)
    handle_mouse_move(CrymbleUI::Vec2.new(@start_x + @move * 6.0, p.y + p.height / 2.0))
  end

  private def end_resize(id : String)
    return unless p = panel(id)
    handle_mouse_up(CrymbleUI::Vec2.new(p.x + p.width, p.y + p.height / 2.0))
  end

  # Scroll the ScrollView to its far (bottom-right) corner — the near-capacity band where the
  # over-allocated buffer runs into the data extent, so the leading margin (M) shrinks toward zero.
  private def scroll_to_far_corner
    return unless sv = find("scroll_sv").as?(CrymbleUI::ScrollView)
    max = CrymbleUI::Vec2.new(
      Math.max(0.0, sv.content_size.width - sv.viewport_size.width),
      Math.max(0.0, sv.content_size.height - sv.viewport_size.height)
    )
    sv.set_scroll_offset_for_test(max)
  end

  # emit the per-frame viewport-cache recenter counters (previous frame's tally — the SFML frame
  # loop resets them each frame). Read the delta between the NEARCAP and (healthy) SCROLL sweeps: the
  # near-capacity small-M blit-shift cost is PRE-EXISTING; a realloc/full-recenter STORM is not.
  private def emit_recenter(tag : String)
    STDERR.puts "[RECENTER #{tag}] full=#{CrymbleUI::LayerRenderer.frame_full_recenter_count} " \
                "blit_shift=#{CrymbleUI::LayerRenderer.frame_blit_shift_count} " \
                "realloc=#{CrymbleUI::LayerRenderer.frame_realloc_count}"
  end

  private def run_phase
    case @phase
    when 0
      STDERR.puts "### FLOORED-RESIZE-START"
      start_resize("floored")
      @move = 0
      @phase = 1
      schedule_next(DELAY)
    when 1
      @move += 1
      move_resize("floored")
      if @move >= MOVES
        end_resize("floored")
        STDERR.puts "### FLOORED-RESIZE-END size=#{panel("floored").try(&.width).try(&.round)}"
        @phase = 2
        schedule_next(500)
      else
        schedule_next(DELAY)
      end
    when 2
      STDERR.puts "### SCROLL-RESIZE-START"
      start_resize("scroll")
      @move = 0
      @phase = 3
      schedule_next(DELAY)
    when 3
      @move += 1
      move_resize("scroll")
      emit_recenter("healthy") # control: full over-allocated margin (M = 2·cache_extent)
      if @move >= MOVES
        end_resize("scroll")
        STDERR.puts "### SCROLL-RESIZE-END size=#{panel("scroll").try(&.width).try(&.round)}"
        @phase = 4
        schedule_next(500)
      else
        schedule_next(DELAY)
      end
    when 4
      # Near-capacity: scroll the ScrollView to the far corner, THEN resize — the small-M band where a
      # grow eats the leading margin, so each grow-frame recenters via blit-shift (pre-existing baseline).
      STDERR.puts "### NEARCAP-RESIZE-START"
      scroll_to_far_corner
      start_resize("scroll")
      @move = 0
      @phase = 5
      schedule_next(DELAY)
    when 5
      @move += 1
      move_resize("scroll")
      emit_recenter("nearcap")
      if @move >= MOVES
        end_resize("scroll")
        STDERR.puts "### NEARCAP-RESIZE-END size=#{panel("scroll").try(&.width).try(&.round)}"
        @phase = 6
        schedule_next(500)
      else
        schedule_next(DELAY)
      end
    when 6
      STDERR.puts "### DONE"
      quit
    end
  end
end

app = GrowPerfAutotest.new
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
