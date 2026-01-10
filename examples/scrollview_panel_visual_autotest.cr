require "../src/crymble"

# Automated SFML visual test for ScrollView-in-Panel drag/resize rendering
# Uses ACTUAL PIXEL SAMPLING to detect visual bugs
#
# Tests:
# 1. First drag: content should MOVE with panel (sample pixels to verify)
# 2. Resize: scrollbar thumb should UPDATE (sample scrollbar pixels)
#
# Usage:
#   shards build scrollview_panel_visual_autotest
#   DISPLAY=:0 ./bin/scrollview_panel_visual_autotest
#   cat /tmp/autotest_visual_results.log
#
class ScrollViewPanelVisualAutoTest < CrymbleUI::App
  @test_phase = 0
  @test_results = [] of String
  @scheduled_first = false

  # Track pixel samples for comparison
  @initial_content_pixel : String = ""
  @initial_scrollbar_pixel_mid : String = ""
  @initial_scrollbar_pixel_bottom : String = ""
  @old_sample_x : Int32 = 0
  @sample_y : Int32 = 0

  # Distinctive color for content buttons
  BUTTON_BLUE = CrymbleUI::Color.new(100, 150, 200, 255)

  # Panel dimensions
  PANEL_X = 100.0
  PANEL_Y = 50.0
  PANEL_WIDTH = 300.0
  PANEL_HEIGHT = 250.0
  TITLE_BAR_HEIGHT = 28.0

  # Drag/resize amounts
  DRAG_AMOUNT = 80.0
  RESIZE_GROW = 100.0

  def build : CrymbleUI::Widget
    # Schedule first test phase after scheduler is ready
    if @test_phase == 0 && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule_next_phase(500)  # Wait for initial render to complete
    end

    window("ScrollView-in-Panel Visual AutoTest", 600, 400) do
      window_panel(title: "Test Panel", x: PANEL_X, y: PANEL_Y,
                   width: PANEL_WIDTH, height: PANEL_HEIGHT,
                   resizable: true, id: "test_panel") do
        vstack(spacing: 5.0, padding: 5.0) do
          text("AutoTest Items:", font_scale: -1)
          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "test_sv") do
              vstack(spacing: 5.0) do
                # 15 buttons - scrollable content, thumb change visible on resize
                15.times do |i|
                  btn = button("Item #{i + 1}") { }
                  btn.background_color = BUTTON_BLUE
                end
              end
            end
          end
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
    panel = find("test_panel").as?(CrymbleUI::WindowPanel)
    sv = find("test_sv").as?(CrymbleUI::ScrollView)

    case @test_phase
    # === INITIAL STATE - Sample reference pixels ===
    when 0
      log_separator("INITIAL STATE")
      log_state("INITIAL", panel, sv)

      if p = panel
        if s = sv
          # Calculate sample positions
          sv_abs = s.absolute_bounds
          @old_sample_x = (sv_abs.x + 40).to_i  # Inside content area
          @sample_y = (sv_abs.y + 30).to_i

          # Sample initial content pixel
          if content_layer = s.content_layer
            if backend = content_layer.backend.as?(CrymbleUI::CrSFMLBackend)
              # Convert absolute coords to layer-local coords
              local_x = @old_sample_x - content_layer.bounds.x.to_i
              local_y = @sample_y - content_layer.bounds.y.to_i
              @initial_content_pixel = backend.debug_sample_pixel(local_x, local_y)
              log_pixel("INITIAL_CONTENT", @old_sample_x, @sample_y, @initial_content_pixel)
            end
          end

          # Sample initial scrollbar pixels (mid and bottom of track)
          if scrollbar_layer = s.scrollbar_layer
            if backend = scrollbar_layer.backend.as?(CrymbleUI::CrSFMLBackend)
              sb_bounds = scrollbar_layer.bounds
              mid_y = (sb_bounds.height / 2).to_i
              bottom_y = (sb_bounds.height - 30).to_i
              scrollbar_x = (sb_bounds.width - 8).to_i  # Right side where scrollbar is

              @initial_scrollbar_pixel_mid = backend.debug_sample_pixel(scrollbar_x, mid_y)
              @initial_scrollbar_pixel_bottom = backend.debug_sample_pixel(scrollbar_x, bottom_y)
              log_pixel("INITIAL_SCROLLBAR_MID", scrollbar_x, mid_y, @initial_scrollbar_pixel_mid)
              log_pixel("INITIAL_SCROLLBAR_BOTTOM", scrollbar_x, bottom_y, @initial_scrollbar_pixel_bottom)
            end
          end
        end
      end

      @test_phase = 1
      schedule_next_phase(200)

    # === FIRST DRAG: Start ===
    when 1
      log_separator("FIRST DRAG TEST")
      if p = panel
        title_bar_x = p.x + p.width / 2
        title_bar_y = p.y + TITLE_BAR_HEIGHT / 2
        handle_mouse_down(CrymbleUI::Vec2.new(title_bar_x, title_bar_y))
      end
      @test_phase = 2
      schedule_next_phase(100)

    # === FIRST DRAG: Move ===
    when 2
      if p = panel
        new_x = p.x + DRAG_AMOUNT + p.width / 2
        title_bar_y = p.y + TITLE_BAR_HEIGHT / 2
        handle_mouse_move(CrymbleUI::Vec2.new(new_x, title_bar_y))
      end
      @test_phase = 3
      schedule_next_phase(200)  # Wait for render

    # === FIRST DRAG: Verify pixels ===
    when 3
      log_state("DURING_FIRST_DRAG", panel, sv)
      verify_content_moved("FIRST_DRAG_CONTENT_MOVED", panel, sv)
      @test_phase = 4
      schedule_next_phase(100)

    # === FIRST DRAG: End ===
    when 4
      if p = panel
        handle_mouse_up(CrymbleUI::Vec2.new(p.x + p.width / 2, p.y + TITLE_BAR_HEIGHT / 2))
      end
      @test_phase = 5
      schedule_next_phase(300)

    # === RESIZE: Start ===
    when 5
      log_separator("RESIZE TEST")
      log_state("BEFORE_RESIZE", panel, sv)

      # Re-sample scrollbar before resize
      if s = sv
        if scrollbar_layer = s.scrollbar_layer
          if backend = scrollbar_layer.backend.as?(CrymbleUI::CrSFMLBackend)
            sb_bounds = scrollbar_layer.bounds
            mid_y = (sb_bounds.height / 2).to_i
            bottom_y = (sb_bounds.height - 30).to_i
            scrollbar_x = (sb_bounds.width - 8).to_i

            @initial_scrollbar_pixel_mid = backend.debug_sample_pixel(scrollbar_x, mid_y)
            @initial_scrollbar_pixel_bottom = backend.debug_sample_pixel(scrollbar_x, bottom_y)
            log_pixel("PRE_RESIZE_SCROLLBAR_MID", scrollbar_x, mid_y, @initial_scrollbar_pixel_mid)
            log_pixel("PRE_RESIZE_SCROLLBAR_BOTTOM", scrollbar_x, bottom_y, @initial_scrollbar_pixel_bottom)
          end
        end
      end

      if p = panel
        resize_x = p.x + p.width - 5
        resize_y = p.y + p.height - 5
        handle_mouse_down(CrymbleUI::Vec2.new(resize_x, resize_y))
      end
      @test_phase = 6
      schedule_next_phase(100)

    # === RESIZE: Grow ===
    when 6
      if p = panel
        resize_x = p.x + p.width - 5
        resize_y = p.y + p.height + RESIZE_GROW - 5
        handle_mouse_move(CrymbleUI::Vec2.new(resize_x, resize_y))
      end
      @test_phase = 7
      schedule_next_phase(300)  # Longer wait for resize render

    # === RESIZE: Verify scrollbar thumb changed ===
    when 7
      log_state("DURING_RESIZE", panel, sv)
      verify_scrollbar_thumb_changed("RESIZE_SCROLLBAR_UPDATED", panel, sv)
      @test_phase = 8
      schedule_next_phase(100)

    # === RESIZE: End ===
    when 8
      if p = panel
        handle_mouse_up(CrymbleUI::Vec2.new(p.x + p.width, p.y + p.height))
      end
      @test_phase = 9
      schedule_next_phase(300)

    # === OUTPUT RESULTS ===
    when 9
      output_results
      @test_phase = 10
      schedule_next_phase(500)

    when 10
      quit
    end
  end

  # Verify content pixels moved (OLD position should NOT have content)
  private def verify_content_moved(test_name : String, panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    passed = true
    reason = ""

    if p = panel
      if s = sv
        if content_layer = s.content_layer
          if backend = content_layer.backend.as?(CrymbleUI::CrSFMLBackend)
            # Sample at OLD absolute position (where content WAS before drag)
            # Content should have moved, so this pixel should NOT be button blue anymore
            local_x = @old_sample_x - content_layer.bounds.x.to_i
            local_y = @sample_y - content_layer.bounds.y.to_i

            current_pixel = backend.debug_sample_pixel(local_x, local_y)
            log_pixel("DRAG_OLD_POS_NOW", @old_sample_x, @sample_y, current_pixel)

            # If pixel is still BUTTON_BLUE at old position, content didn't move!
            if pixel_matches_blue?(current_pixel)
              # Check if it's in the viewport region (not displaced outside)
              if local_x >= 0 && local_x < content_layer.bounds.width.to_i &&
                 local_y >= 0 && local_y < content_layer.bounds.height.to_i
                # Pixel is still blue at old layer-local coords = content IS at old position
                # This is the BUG - content should have moved with panel
                passed = false
                reason = "Content still at OLD position (pixel=#{current_pixel}) - DISPLACED!"
              end
            end

            # Also check NEW position (old_x + drag_amount in layer coords)
            new_local_x = local_x + DRAG_AMOUNT.to_i
            if new_local_x >= 0 && new_local_x < backend.width
              new_pixel = backend.debug_sample_pixel(new_local_x, local_y)
              log_pixel("DRAG_NEW_POS", @old_sample_x + DRAG_AMOUNT.to_i, @sample_y, new_pixel)
            end
          else
            passed = false
            reason = "content_layer backend is not CrSFMLBackend"
          end
        else
          passed = false
          reason = "content_layer is nil"
        end
      else
        passed = false
        reason = "ScrollView not found"
      end
    else
      passed = false
      reason = "Panel not found"
    end

    result = passed ? "PASS" : "FAIL"
    @test_results << "#{test_name}: #{result}#{passed ? "" : " - #{reason}"}"
  end

  # Verify scrollbar thumb pixels changed after resize
  private def verify_scrollbar_thumb_changed(test_name : String, panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    passed = true
    reason = ""

    if s = sv
      if scrollbar_layer = s.scrollbar_layer
        if backend = scrollbar_layer.backend.as?(CrymbleUI::CrSFMLBackend)
          sb_bounds = scrollbar_layer.bounds
          mid_y = (sb_bounds.height / 2).to_i
          bottom_y = (sb_bounds.height - 30).to_i
          scrollbar_x = (sb_bounds.width - 8).to_i

          current_mid = backend.debug_sample_pixel(scrollbar_x, mid_y)
          current_bottom = backend.debug_sample_pixel(scrollbar_x, bottom_y)

          log_pixel("POST_RESIZE_SCROLLBAR_MID", scrollbar_x, mid_y, current_mid)
          log_pixel("POST_RESIZE_SCROLLBAR_BOTTOM", scrollbar_x, bottom_y, current_bottom)

          # After resize grow, thumb should be larger
          # If bottom pixel was TRACK color and is now THUMB color, thumb grew
          # OR if both are same as before, thumb didn't change = BUG
          if current_mid == @initial_scrollbar_pixel_mid && current_bottom == @initial_scrollbar_pixel_bottom
            passed = false
            reason = "Scrollbar pixels unchanged after resize - thumb not updated!"
          end

          # Log effective viewport for debugging
          File.open("/tmp/autotest_visual_state.log", "a") do |f|
            f.puts "  effective_viewport_height: #{s.effective_viewport_height.round(1)}"
            f.puts "  content_size.height: #{s.content_size.height.round(1)}"
            f.puts "  thumb_ratio: #{(s.effective_viewport_height / s.content_size.height).round(3)}"
          end
        else
          passed = false
          reason = "scrollbar_layer backend is not CrSFMLBackend"
        end
      else
        passed = false
        reason = "scrollbar_layer is nil"
      end
    else
      passed = false
      reason = "ScrollView not found"
    end

    result = passed ? "PASS" : "FAIL"
    @test_results << "#{test_name}: #{result}#{passed ? "" : " - #{reason}"}"
  end

  private def pixel_matches_blue?(pixel_str : String) : Bool
    # Parse "RGBA(r,g,b,a)" and check if it's close to BUTTON_BLUE
    if match = pixel_str.match(/RGBA\((\d+),(\d+),(\d+),(\d+)\)/)
      r = match[1].to_i
      g = match[2].to_i
      b = match[3].to_i
      # BUTTON_BLUE is (100, 150, 200, 255)
      (r - 100).abs < 20 && (g - 150).abs < 20 && (b - 200).abs < 20
    else
      false
    end
  end

  private def log_separator(title : String)
    File.open("/tmp/autotest_visual_state.log", "a") do |f|
      f.puts "\n=== #{title} ==="
    end
  end

  private def log_state(phase : String, panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    File.open("/tmp/autotest_visual_state.log", "a") do |f|
      f.puts "#{phase}:"
      if p = panel
        f.puts "  Panel: pos=(#{p.x.round(1)},#{p.y.round(1)}) size=(#{p.width.round(1)},#{p.height.round(1)})"
      end
      if s = sv
        f.puts "  ScrollView.bounds: #{s.bounds}"
        f.puts "  ScrollView.absolute_bounds: #{s.absolute_bounds}"
        if content_layer = s.content_layer
          f.puts "  content_layer.bounds: #{content_layer.bounds}"
        end
        if scrollbar_layer = s.scrollbar_layer
          f.puts "  scrollbar_layer.bounds: #{scrollbar_layer.bounds}"
        end
      end
    end
  end

  private def log_pixel(label : String, x : Int32, y : Int32, pixel : String)
    File.open("/tmp/autotest_visual_state.log", "a") do |f|
      f.puts "  #{label} at (#{x},#{y}): #{pixel}"
    end
  end

  private def output_results
    File.open("/tmp/autotest_visual_results.log", "w") do |f|
      f.puts "=== ScrollView-in-Panel Visual AutoTest Results ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts ""

      passes = @test_results.count { |r| r.includes?("PASS") }
      fails = @test_results.count { |r| r.includes?("FAIL") }

      f.puts "SUMMARY: #{passes} passed, #{fails} failed"
      f.puts ""
      @test_results.each { |r| f.puts r }
      f.puts ""
      f.puts "See /tmp/autotest_visual_state.log for detailed pixel samples"
    end

    # Print to console
    puts "\n=== Visual AutoTest Results ==="
    puts "SUMMARY: #{@test_results.count { |r| r.includes?("PASS") }} passed, #{@test_results.count { |r| r.includes?("FAIL") }} failed"
    @test_results.each { |r| puts r }
    puts "\nLogs written to /tmp/autotest_visual_*.log"
  end
end

# Run the application
app = ScrollViewPanelVisualAutoTest.new
CrymbleUI.run(app)
