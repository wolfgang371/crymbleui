require "../src/crymble-ui"

# Automated test to reproduce "slow resize finishes on its own" bug
#
# Bug symptom: When resizing a panel slowly, the resize stops mid-drag
# even though the mouse button is still held down.
#
# This means @interaction_mode becomes Idle while mouse is still held.
#
# Test design:
# 1. Create MULTIPLE panels (like showcase_demo)
# 2. Mouse down on one panel's resize handle
# 3. Loop: slow mouse moves with delays (simulate slow drag)
# 4. After EACH move, check: panel.resizing? should be true
# 5. If panel.resizing? becomes false → BUG DETECTED
#
# Usage:
#   shards build slow_resize_autotest
#   DISPLAY=:0 timeout 30 ./bin/slow_resize_autotest

class SlowResizeAutotest < CrymbleUI::App
  @test_phase = 0
  @scheduled = false
  @move_count = 0
  @bug_detected = false

  # Panel positions - multiple panels like showcase_demo
  PANEL1_X = 10.0
  PANEL1_Y = 10.0
  PANEL1_W = 280.0
  PANEL1_H = 250.0

  PANEL2_X = 310.0
  PANEL2_Y = 10.0
  PANEL2_W = 280.0
  PANEL2_H = 250.0

  PANEL3_X = 10.0
  PANEL3_Y = 280.0
  PANEL3_W = 280.0
  PANEL3_H = 200.0

  # Test parameters
  MOVE_DELAY_MS = 200  # Slow moves - 200ms between each
  TOTAL_MOVES = 20     # Do 20 incremental moves
  MOVE_DELTA = 5.0     # 5 pixels per move (slow resize)

  def build : CrymbleUI::Widget
    if @test_phase == 0 && !@scheduled && scheduler_ready?
      @scheduled = true
      schedule_next_phase(500)
    end

    window("Slow Resize Test", 800, 600) do
      # Panel 1 - the one we'll resize
      window_panel(title: "Panel A (resize me)", x: PANEL1_X, y: PANEL1_Y,
                   width: PANEL1_W, height: PANEL1_H,
                   resizable: true, id: "panel_a") do
        vstack(spacing: 5.0, padding: 10.0) do
          text("This panel will be resized")
          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical) do
              vstack(spacing: 5.0) do
                10.times { |i| text("Item #{i + 1}") }
              end
            end
          end
        end
      end

      # Panel 2 - another panel (to test multi-panel scenario)
      window_panel(title: "Panel B", x: PANEL2_X, y: PANEL2_Y,
                   width: PANEL2_W, height: PANEL2_H,
                   resizable: true, id: "panel_b") do
        vstack(spacing: 5.0, padding: 10.0) do
          text("Another panel")
          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical) do
              vstack(spacing: 5.0) do
                8.times { |i| text("Other item #{i + 1}") }
              end
            end
          end
        end
      end

      # Panel 3 - third panel
      window_panel(title: "Panel C", x: PANEL3_X, y: PANEL3_Y,
                   width: PANEL3_W, height: PANEL3_H,
                   resizable: true, id: "panel_c") do
        vstack(spacing: 5.0, padding: 10.0) do
          text("Third panel")
        end
      end
    end
  end

  private def scheduler_ready? : Bool
    begin
      CrymbleUI::Widget.scheduler
      true
    rescue
      false
    end
  end

  private def schedule_next_phase(delay_ms : Int32)
    CrymbleUI::Widget.scheduler.schedule(Time::Span.new(nanoseconds: delay_ms * 1_000_000)) do
      run_test_phase
    end
  end

  private def run_test_phase
    panel = find("panel_a").as?(CrymbleUI::WindowPanel)

    case @test_phase
    when 0
      # Phase 0: Log initial state
      log("=== SLOW RESIZE TEST ===")
      log("Testing: resize should NOT stop while mouse is held")
      log("")
      if p = panel
        log("Initial state:")
        log("  Panel A: pos=(#{p.x},#{p.y}) size=(#{p.width},#{p.height})")
        log("  resizing?: #{p.resizing?}")
      end
      log("")

      @test_phase = 1
      schedule_next_phase(200)

    when 1
      # Phase 1: Start resize (mouse down on bottom-right corner)
      log("=== STARTING RESIZE ===")
      if p = panel
        resize_x = p.x + p.width - 5.0
        resize_y = p.y + p.height - 5.0
        handle_mouse_down(CrymbleUI::Vec2.new(resize_x, resize_y))
        log("Mouse DOWN at (#{resize_x.round(1)}, #{resize_y.round(1)})")

        # Check immediately after mouse down
        # Need to re-find panel after potential rebuild
        panel = find("panel_a").as?(CrymbleUI::WindowPanel)
        if p2 = panel
          log("After mouse down: resizing? = #{p2.resizing?}")
          unless p2.resizing?
            log("BUG: Panel should be resizing after mouse down!")
            @bug_detected = true
          end
        end
      end

      @move_count = 0
      @test_phase = 2
      schedule_next_phase(MOVE_DELAY_MS)

    when 2
      # Phase 2: Incremental slow moves
      @move_count += 1

      # Re-find panel (may have been rebuilt)
      panel = find("panel_a").as?(CrymbleUI::WindowPanel)

      if p = panel
        # Record size BEFORE the move
        size_before = {p.width, p.height}

        # Check BEFORE the move - is panel still resizing?
        unless p.resizing?
          log("")
          log("!!! BUG DETECTED (resizing? = false) !!!")
          log("Move #{@move_count}: Panel stopped resizing!")
          log("  resizing? = #{p.resizing?}")
          log("  interaction_mode would be Idle")
          log("  Mouse is still 'held' but panel stopped responding")
          log("")
          @bug_detected = true
          @test_phase = 3
          schedule_next_phase(100)
          return
        end

        # Calculate target position (fixed increments from start)
        # Start position was at panel edge: (PANEL1_X + PANEL1_W - 5, PANEL1_Y + PANEL1_H - 5)
        target_x = (PANEL1_X + PANEL1_W - 5.0) + (MOVE_DELTA * @move_count)
        target_y = (PANEL1_Y + PANEL1_H - 5.0) + (MOVE_DELTA * @move_count)

        # Do the mouse move
        handle_mouse_move(CrymbleUI::Vec2.new(target_x, target_y))

        # Re-find panel after move (rebuild may have happened)
        panel = find("panel_a").as?(CrymbleUI::WindowPanel)
        if p2 = panel
          size_after = {p2.width, p2.height}

          # Check if panel ACTUALLY grew
          grew = size_after[0] > size_before[0] || size_after[1] > size_before[1]

          log("Move #{@move_count}/#{TOTAL_MOVES}: target (#{target_x.round(1)}, #{target_y.round(1)}) - size #{size_before[0].round(1)}x#{size_before[1].round(1)} -> #{size_after[0].round(1)}x#{size_after[1].round(1)} - grew? #{grew} - resizing? #{p2.resizing?}")

          unless grew
            log("")
            log("!!! BUG DETECTED (panel didn't grow) !!!")
            log("Move #{@move_count}: Panel didn't respond to mouse move!")
            log("  Size stayed at #{size_after[0].round(1)}x#{size_after[1].round(1)}")
            log("  resizing? = #{p2.resizing?}")
            log("")
            @bug_detected = true
            @test_phase = 3
            schedule_next_phase(100)
            return
          end
        end

        if @move_count >= TOTAL_MOVES
          log("")
          log("=== ALL MOVES COMPLETED ===")
          @test_phase = 3
          schedule_next_phase(100)
        else
          # Schedule next slow move
          schedule_next_phase(MOVE_DELAY_MS)
        end
      else
        log("ERROR: Could not find panel_a!")
        @test_phase = 3
        schedule_next_phase(100)
      end

    when 3
      # Phase 3: End resize and report
      log("")
      if p = panel
        handle_mouse_up(CrymbleUI::Vec2.new(p.x + p.width, p.y + p.height))
        log("Mouse UP")
        log("Final panel size: (#{p.width.round(1)}, #{p.height.round(1)})")
      end

      log("")
      if @bug_detected
        log("TEST RESULT: FAILED - Bug reproduced!")
        log("The resize stopped while mouse was still held.")
      else
        log("TEST RESULT: PASSED - Resize continued throughout drag")
      end

      @test_phase = 4
      schedule_next_phase(500)

    when 4
      log("=== DONE ===")
      quit
    end
  end

  private def log(msg : String)
    puts msg
    File.open("/tmp/slow_resize_test.log", "a") do |f|
      f.puts msg
    end
  end
end

# Run
app = SlowResizeAutotest.new
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
