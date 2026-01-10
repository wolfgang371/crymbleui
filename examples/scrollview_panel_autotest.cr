require "../src/crymble"

# Automated SFML visual test for ScrollView-in-Panel bugs
# Uses ACTUAL SCREEN PIXEL SAMPLING (from RenderWindow) to detect visual bugs
#
# Tests with MULTIPLE OVERLAPPING PANELS (required to reproduce bugs):
# 1. Bug 1: Ghost content when panels overlap (back panel shows front panel's content)
# 2. Bug 2: Scrollbar bleeding through (scrollbar renders on top of front panel)
# 3. Bug 3: Scrollbar thumb not updating during resize
#
# Usage:
#   shards build scrollview_panel_autotest
#   DISPLAY=:0 ./bin/scrollview_panel_autotest
#   cat /tmp/autotest_results.log
#
# The tests should FAIL if bugs are present (TDD: failing test first)

# Module to store renderer reference for screen capture
module ScreenCapture
  @@renderer : CrymbleUI::SFMLRenderer? = nil

  def self.renderer=(r : CrymbleUI::SFMLRenderer)
    @@renderer = r
  end

  def self.renderer : CrymbleUI::SFMLRenderer?
    @@renderer
  end

  # Capture window contents to an image for pixel sampling
  def self.capture_window : SF::Image?
    return nil unless renderer = @@renderer
    return nil unless window = renderer.window

    texture = SF::Texture.new(window.size.x, window.size.y)
    texture.update(window)
    texture.copy_to_image
  end

  # Sample a pixel from the screen at absolute coordinates
  def self.sample_pixel(x : Int32, y : Int32) : SF::Color?
    return nil unless image = capture_window
    return nil if x < 0 || y < 0 || x >= image.size.x.to_i || y >= image.size.y.to_i
    image.get_pixel(x, y)
  end

  # Format pixel as string for logging
  def self.pixel_to_string(pixel : SF::Color) : String
    "RGBA(#{pixel.r},#{pixel.g},#{pixel.b},#{pixel.a})"
  end
end

# Custom run function that stores renderer reference
def run_with_screen_capture(app : CrymbleUI::App)
  app.build_tree
  root = app.root
  raise "App.build() must return a Window widget" unless root.is_a?(CrymbleUI::Window)

  window_widget = root.as(CrymbleUI::Window)
  renderer = CrymbleUI::SFMLRenderer.new(
    width: window_widget.width,
    height: window_widget.height,
    title: window_widget.title
  )

  # Store renderer for screen capture
  ScreenCapture.renderer = renderer

  renderer.run(app)
end

# Custom widget matching StatusIndicator from showcase_demo
class TestStatusIndicator < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  property active : Bool
  property size : Float64

  def initialize(@active = false, @size = 12.0)
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@size, @size)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    color = @active ? CrymbleUI::Color.new(100, 255, 100, 255) : CrymbleUI::Color.new(255, 100, 100, 255)
    primitives do
      draw_circle(CrymbleUI::Vec2.new(bounds.width / 2, bounds.height / 2), @size / 2, color, fill: true)
    end
  end
end

class ScrollViewPanelAutoTest < CrymbleUI::App
  @test_phase = 0
  @test_results = [] of String
  @scheduled_first = false
  @items_count = 30  # Need more items so scrollbar is still needed after resize

  # Panel 1 (back): ScrollView panel - similar to showcase's "Preview (ScrollView)"
  PANEL1_X = 100.0
  PANEL1_Y = 50.0
  PANEL1_WIDTH = 290.0
  PANEL1_HEIGHT = 280.0

  # Panel 2 (front): Overlapping panel - starts overlapping Panel 1
  PANEL2_X = 200.0   # Overlaps Panel 1 by ~190px
  PANEL2_Y = 100.0   # Overlaps Panel 1 by ~230px
  PANEL2_WIDTH = 250.0
  PANEL2_HEIGHT = 200.0

  TITLE_BAR_HEIGHT = 28.0

  # For Bug 2 test: distinctive color for front panel content
  FRONT_PANEL_COLOR = CrymbleUI::Color.new(80, 80, 200, 255)  # Blue

  # Track sample positions
  @scrollview_content_x : Int32 = 0
  @scrollview_content_y : Int32 = 0
  @scrollbar_x : Int32 = 0
  @scrollbar_mid_y : Int32 = 0
  @overlap_sample_x : Int32 = 0
  @overlap_sample_y : Int32 = 0

  # Track initial pixel colors
  @initial_scrollbar_thumb_pixel : SF::Color? = nil
  @initial_scrollbar_bottom_pixel : SF::Color? = nil

  def build : CrymbleUI::Widget
    # Schedule first test phase after scheduler is ready
    if @test_phase == 0 && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule_next_phase(500)  # Wait for initial render
    end

    window("ScrollView-in-Panel AutoTest (Overlapping)", 700, 500) do
      # Panel 1 (BACK): ScrollView panel
      window_panel(title: "Preview (ScrollView)", x: PANEL1_X, y: PANEL1_Y,
                   width: PANEL1_WIDTH, height: PANEL1_HEIGHT,
                   resizable: true, id: "scrollview_panel") do
        vstack(spacing: 10.0, padding: 10.0) do
          hstack(spacing: 10.0) do
            text("Items:", font_scale: -1)
            button("Add 5") { }
            button("Remove 5") { }
          end

          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "test_sv") do
              vstack(spacing: 5.0) do
                @items_count.times do |i|
                  hstack(spacing: 8.0) do
                    widget TestStatusIndicator.new(active: i.even?, size: 10.0)
                    text("Item #{i + 1}", font_scale: -1)
                  end
                end
              end
            end
          end
        end
      end

      # Panel 2 (FRONT): Overlapping panel with solid color content
      window_panel(title: "Overlapping Panel", x: PANEL2_X, y: PANEL2_Y,
                   width: PANEL2_WIDTH, height: PANEL2_HEIGHT,
                   resizable: false, id: "front_panel") do
        vstack(spacing: 10.0, padding: 10.0) do
          text("This panel overlaps the ScrollView panel", font_scale: -1)
          # Blue colored buttons to make overlap detection easy
          5.times do |i|
            btn = button("Front Item #{i + 1}") { }
            btn.background_color = FRONT_PANEL_COLOR
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
    sv_panel = find("scrollview_panel").as?(CrymbleUI::WindowPanel)
    front_panel = find("front_panel").as?(CrymbleUI::WindowPanel)
    sv = find("test_sv").as?(CrymbleUI::ScrollView)

    case @test_phase
    # === PHASE 0: INITIAL STATE - Calculate sample positions ===
    when 0
      log_separator("INITIAL STATE (OVERLAPPING PANELS)")
      log_state("INITIAL", sv_panel, front_panel, sv)

      if s = sv
        sv_abs = s.absolute_bounds

        # Sample point in ScrollView content area (should be covered by front panel initially)
        @scrollview_content_x = (sv_abs.x + 50).to_i
        @scrollview_content_y = (sv_abs.y + 100).to_i

        # Scrollbar position (right side of ScrollView)
        @scrollbar_x = (sv_abs.x + sv_abs.width - 8).to_i
        @scrollbar_mid_y = (sv_abs.y + sv_abs.height / 2).to_i

        # Sample point in the OVERLAP region (inside both panels' bounds)
        # This is where scrollbar might bleed through
        @overlap_sample_x = @scrollbar_x
        @overlap_sample_y = @scrollbar_mid_y

        log_info("Sample positions: content=(#{@scrollview_content_x},#{@scrollview_content_y}) scrollbar=(#{@scrollbar_x},#{@scrollbar_mid_y})")
      end

      @test_phase = 1
      schedule_next_phase(200)

    # === PHASE 1: BUG 1 TEST (INITIAL) - Check for ghost/corrupted content at overlap ===
    when 1
      log_separator("BUG 1 TEST: INITIAL RENDER WITH OVERLAP")

      # The ScrollView content that's BEHIND the front panel might show corrupted/ghost content
      # Sample the portion of ScrollView that's NOT covered by front panel
      verify_initial_render_correct("INITIAL_SCROLLVIEW_RENDER", sv_panel, front_panel, sv)

      @test_phase = 2
      schedule_next_phase(200)

    # === PHASE 2: BUG 2 TEST - Check scrollbar bleed-through ===
    when 2
      log_separator("BUG 2 TEST: SCROLLBAR BLEED-THROUGH")

      # With panels overlapping, sample at scrollbar position
      # The front panel should HIDE the scrollbar, so we should NOT see scrollbar colors
      verify_scrollbar_not_bleeding("SCROLLBAR_HIDDEN_BY_FRONT_PANEL", sv_panel, front_panel, sv)

      @test_phase = 3
      schedule_next_phase(200)

    # === PHASE 3: Start dragging FRONT panel away ===
    when 3
      log_separator("DRAGGING FRONT PANEL AWAY")
      log_state("BEFORE_DRAG", sv_panel, front_panel, sv)

      if fp = front_panel
        # Mouse down on front panel title bar
        title_x = fp.x + fp.width / 2
        title_y = fp.y + TITLE_BAR_HEIGHT / 2
        handle_mouse_down(CrymbleUI::Vec2.new(title_x, title_y))
      end
      @test_phase = 4
      schedule_next_phase(200)  # Wait a bit after mouse down

    # === PHASE 4: Small move to START revealing ScrollView (Bug 1 might show here) ===
    when 4
      if fp = front_panel
        # Move front panel just 50px - partially revealing ScrollView
        new_x = fp.x + 50.0 + fp.width / 2
        title_y = fp.y + TITLE_BAR_HEIGHT / 2
        handle_mouse_move(CrymbleUI::Vec2.new(new_x, title_y))
      end
      @test_phase = 5
      schedule_next_phase(300)  # Wait for render

    # === PHASE 5: Check for ghost content after SMALL move ===
    when 5
      log_state("AFTER_SMALL_MOVE", sv_panel, front_panel, sv)
      verify_no_ghost_content("NO_GHOST_AFTER_SMALL_MOVE", sv_panel, front_panel, sv)
      @test_phase = 6
      schedule_next_phase(100)

    # === PHASE 6: Continue moving front panel fully away ===
    when 6
      if fp = front_panel
        # Move front panel 300px total (fully away from ScrollView panel)
        new_x = PANEL2_X + 300.0 + fp.width / 2
        title_y = fp.y + TITLE_BAR_HEIGHT / 2
        handle_mouse_move(CrymbleUI::Vec2.new(new_x, title_y))
      end
      @test_phase = 7
      schedule_next_phase(300)  # Wait for render

    # === PHASE 7: Check for ghost content after FULL move ===
    when 7
      log_state("AFTER_FULL_MOVE", sv_panel, front_panel, sv)
      verify_no_ghost_content("NO_GHOST_AFTER_FULL_MOVE", sv_panel, front_panel, sv)
      @test_phase = 8
      schedule_next_phase(100)

    # === PHASE 8: Release mouse ===
    when 8
      if fp = front_panel
        handle_mouse_up(CrymbleUI::Vec2.new(fp.x + fp.width / 2, fp.y + TITLE_BAR_HEIGHT / 2))
      end
      log_state("AFTER_DRAG_RELEASE", sv_panel, front_panel, sv)
      @test_phase = 9
      schedule_next_phase(300)

    # === PHASE 9: BUG 3 SETUP - Sample scrollbar before resize ===
    when 9
      log_separator("BUG 3 TEST: SCROLLBAR THUMB DURING RESIZE")
      log_state("BEFORE_RESIZE", sv_panel, front_panel, sv)

      # Sample scrollbar thumb position BEFORE resize
      if s = sv
        sv_abs = s.absolute_bounds
        @scrollbar_x = (sv_abs.x + sv_abs.width - 8).to_i
        @scrollbar_mid_y = (sv_abs.y + sv_abs.height / 2).to_i

        if pixel = ScreenCapture.sample_pixel(@scrollbar_x, @scrollbar_mid_y)
          @initial_scrollbar_thumb_pixel = pixel
          log_screen_pixel("PRE_RESIZE_SCROLLBAR_MID", @scrollbar_x, @scrollbar_mid_y, pixel)
        end

        # Also sample near bottom of scrollbar track
        bottom_y = (sv_abs.y + sv_abs.height - 30).to_i
        if pixel = ScreenCapture.sample_pixel(@scrollbar_x, bottom_y)
          @initial_scrollbar_bottom_pixel = pixel
          log_screen_pixel("PRE_RESIZE_SCROLLBAR_BOTTOM", @scrollbar_x, bottom_y, pixel)
        end
      end

      @test_phase = 10
      schedule_next_phase(100)

    # === PHASE 10: Start resize of ScrollView panel ===
    when 10
      if svp = sv_panel
        # Mouse down on resize corner
        resize_x = svp.x + svp.width - 5
        resize_y = svp.y + svp.height - 5
        handle_mouse_down(CrymbleUI::Vec2.new(resize_x, resize_y))
      end
      @test_phase = 11
      schedule_next_phase(100)

    # === PHASE 11: Resize panel (grow by 50px - small enough to keep scrollbar needed) ===
    when 11
      if svp = sv_panel
        resize_x = svp.x + svp.width - 5
        resize_y = svp.y + svp.height + 50.0 - 5  # Grow 50px (smaller to keep scrollbar)
        handle_mouse_move(CrymbleUI::Vec2.new(resize_x, resize_y))
      end
      @test_phase = 12
      schedule_next_phase(600)  # Longer wait for resize render

    # === PHASE 12: BUG 3 TEST - Verify scrollbar thumb changed ===
    when 12
      log_state("DURING_RESIZE", sv_panel, front_panel, sv)
      verify_scrollbar_thumb_updated("SCROLLBAR_THUMB_UPDATED_DURING_RESIZE", sv_panel, sv)
      @test_phase = 13
      schedule_next_phase(100)

    # === PHASE 13: Release resize ===
    when 13
      if svp = sv_panel
        handle_mouse_up(CrymbleUI::Vec2.new(svp.x + svp.width, svp.y + svp.height))
      end
      @test_phase = 14
      schedule_next_phase(300)

    # === PHASE 14: Output results ===
    when 14
      output_results
      @test_phase = 15
      schedule_next_phase(500)

    when 15
      quit
    end
  end

  # BUG 1: Verify initial render is correct (no corruption in visible portion of ScrollView)
  private def verify_initial_render_correct(test_name : String, sv_panel : CrymbleUI::WindowPanel?, front_panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    passed = true
    reason = ""

    if svp = sv_panel
      if fp = front_panel
        if s = sv
          sv_abs = s.absolute_bounds

          # Find portion of ScrollView that's NOT covered by front panel
          # Front panel covers from (fp.x, fp.y) to (fp.x + fp.width, fp.y + fp.height)
          # ScrollView visible area to the LEFT of front panel
          uncovered_x = (sv_abs.x + 10).to_i  # 10px into ScrollView
          uncovered_y = (sv_abs.y + 10).to_i  # 10px into ScrollView

          # This point should be BEFORE the front panel's left edge
          if uncovered_x < fp.x.to_i
            if pixel = ScreenCapture.sample_pixel(uncovered_x, uncovered_y)
              log_screen_pixel("UNCOVERED_SV_AREA", uncovered_x, uncovered_y, pixel)

              # This should show ScrollView content (indicators, text, panel background)
              # It should NOT show front panel content (blue buttons)
              if is_front_panel_color?(pixel)
                passed = false
                reason = "Front panel content bleeding into uncovered ScrollView area at (#{uncovered_x},#{uncovered_y})! Pixel=#{ScreenCapture.pixel_to_string(pixel)}"
              end

              # Also check it's not completely wrong (random garbage)
              # Valid colors: gray background (~240), green indicator (~100,255,100), red indicator (~255,100,100), black text
              is_valid = is_panel_background?(pixel) || is_indicator_color?(pixel) || is_text_color?(pixel)
              unless is_valid
                log_info("Pixel color #{ScreenCapture.pixel_to_string(pixel)} - might be corrupted rendering")
              end
            end
          else
            log_info("ScrollView fully covered by front panel - skipping initial render test")
          end
        else
          passed = false
          reason = "ScrollView not found"
        end
      else
        passed = false
        reason = "Front panel not found"
      end
    else
      passed = false
      reason = "ScrollView panel not found"
    end

    result = passed ? "PASS" : "FAIL"
    @test_results << "#{test_name}: #{result}#{passed ? "" : " - #{reason}"}"
  end

  # BUG 2: Verify scrollbar is hidden by front panel (not bleeding through)
  private def verify_scrollbar_not_bleeding(test_name : String, sv_panel : CrymbleUI::WindowPanel?, front_panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    passed = true
    reason = ""

    if fp = front_panel
      if s = sv
        # Calculate overlap region where scrollbar should be HIDDEN
        sv_abs = s.absolute_bounds
        scrollbar_x = (sv_abs.x + sv_abs.width - 8).to_i
        scrollbar_y = (sv_abs.y + 50).to_i  # Mid-scrollbar area

        # Check if this point is inside front panel bounds
        fp_right = fp.x + fp.width
        fp_bottom = fp.y + fp.height

        if scrollbar_x >= fp.x && scrollbar_x <= fp_right && scrollbar_y >= fp.y && scrollbar_y <= fp_bottom
          # This point SHOULD be covered by front panel
          # Sample the pixel - should NOT be scrollbar color (gray/dark gray)
          if pixel = ScreenCapture.sample_pixel(scrollbar_x, scrollbar_y)
            log_screen_pixel("OVERLAP_REGION", scrollbar_x, scrollbar_y, pixel)

            # Scrollbar colors are typically gray (~150-200)
            # If we see gray at this position, scrollbar is bleeding through!
            if is_scrollbar_color?(pixel)
              passed = false
              reason = "Scrollbar visible at (#{scrollbar_x},#{scrollbar_y}) where front panel should hide it! Pixel=#{ScreenCapture.pixel_to_string(pixel)}"
            end
          else
            log_error("Failed to sample pixel at overlap region")
          end
        else
          log_info("Scrollbar not in overlap region - skipping bleed-through test")
        end
      else
        passed = false
        reason = "ScrollView not found"
      end
    else
      passed = false
      reason = "Front panel not found"
    end

    result = passed ? "PASS" : "FAIL"
    @test_results << "#{test_name}: #{result}#{passed ? "" : " - #{reason}"}"
  end

  # BUG 1: Verify no ghost content from front panel in REVEALED ScrollView area
  # After front panel moves, sample the area that WAS covered but is NOW exposed
  # Should see ScrollView content, NOT front panel blue (ghost)
  private def verify_no_ghost_content(test_name : String, sv_panel : CrymbleUI::WindowPanel?, front_panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    passed = true
    reason = ""

    if fp = front_panel
      if s = sv
        sv_abs = s.absolute_bounds

        # Calculate the REVEALED area: between original front panel position and current position
        # Original front panel was at PANEL2_X (200), now it's at fp.x
        original_fp_x = PANEL2_X.to_i
        current_fp_x = fp.x.to_i

        # The revealed strip is from original_fp_x to current_fp_x
        # Sample in the MIDDLE of this revealed strip, within ScrollView bounds
        if current_fp_x > original_fp_x
          revealed_center_x = (original_fp_x + current_fp_x) / 2
          # Make sure we're within ScrollView bounds
          revealed_center_x = {revealed_center_x, sv_abs.x.to_i + 5}.max
          revealed_center_x = {revealed_center_x, (sv_abs.x + sv_abs.width).to_i - 5}.min

          sample_y : Int32 = (sv_abs.y + sv_abs.height / 2).to_i  # Middle of ScrollView

          log_info("Revealed area: x=#{original_fp_x} to #{current_fp_x}, sampling at (#{revealed_center_x}, #{sample_y})")

          # Only sample if the revealed area is within ScrollView bounds
          if revealed_center_x >= sv_abs.x.to_i && revealed_center_x <= (sv_abs.x + sv_abs.width).to_i
            sample_points = [
              {revealed_center_x.to_i, sample_y},
              {revealed_center_x.to_i, sample_y - 30},
              {revealed_center_x.to_i, sample_y + 30},
            ]

            sample_points.each do |(sx, sy)|
              x = sx.to_i
              y = sy.to_i
              # Skip if point is still inside front panel
              next if x >= fp.x.to_i && x <= (fp.x + fp.width).to_i && y >= fp.y.to_i && y <= (fp.y + fp.height).to_i

              if pixel = ScreenCapture.sample_pixel(x, y)
                log_screen_pixel("REVEALED_AREA", x, y, pixel)

                # Ghost = front panel blue appearing where ScrollView should be
                if is_front_panel_color?(pixel)
                  passed = false
                  reason = "Ghost content (BLUE) at (#{x},#{y}) in revealed area! Pixel=#{ScreenCapture.pixel_to_string(pixel)}"
                  break
                end
              end
            end
          else
            log_info("Revealed area outside ScrollView bounds - skipping")
          end
        else
          log_info("Front panel hasn't moved right yet - skipping ghost check")
        end
      else
        passed = false
        reason = "ScrollView not found"
      end
    else
      passed = false
      reason = "Front panel not found"
    end

    result = passed ? "PASS" : "FAIL"
    @test_results << "#{test_name}: #{result}#{passed ? "" : " - #{reason}"}"
  end

  # BUG 3: Verify scrollbar thumb SIZE updated during resize
  # After resize grow, thumb should be LARGER (more of track covered by thumb color)
  private def verify_scrollbar_thumb_updated(test_name : String, sv_panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    passed = true
    reason = ""

    if s = sv
      sv_abs = s.absolute_bounds

      # Calculate expected thumb ratio based on viewport/content
      viewport_h = s.effective_viewport_height
      content_h = s.content_size.height
      expected_thumb_ratio = (viewport_h / content_h).clamp(0.1, 1.0)

      # Sample along the scrollbar track to measure actual thumb coverage
      scrollbar_x = (sv_abs.x + sv_abs.width - 8).to_i
      track_top = (sv_abs.y + 5).to_i      # Top of track (below any padding)
      track_bottom = (sv_abs.y + sv_abs.height - 5).to_i  # Bottom of track
      track_height = track_bottom - track_top

      # Sample 10 points along the track
      thumb_pixels = 0
      track_pixels = 0
      10.times do |i|
        sample_y = (track_top + (track_height * i / 9)).to_i
        if pixel = ScreenCapture.sample_pixel(scrollbar_x, sample_y)
          log_screen_pixel("SCROLLBAR_TRACK_#{i}", scrollbar_x, sample_y, pixel)
          # Thumb is darker gray (~150-180), track is lighter (~200-230)
          if pixel.r < 190 && pixel.g < 190 && pixel.b < 190
            thumb_pixels += 1
          else
            track_pixels += 1
          end
        end
      end

      actual_thumb_ratio = thumb_pixels.to_f / 10.0

      File.open("/tmp/autotest_state.log", "a") do |f|
        f.puts "  viewport_height: #{viewport_h.round(1)}"
        f.puts "  content_height: #{content_h.round(1)}"
        f.puts "  expected_thumb_ratio: #{expected_thumb_ratio.round(3)}"
        f.puts "  actual_thumb_ratio: #{actual_thumb_ratio.round(3)} (#{thumb_pixels}/10 samples)"
      end

      # The actual thumb ratio should be close to expected (within 20%)
      # If thumb didn't update, actual will be much smaller than expected
      ratio_diff = (actual_thumb_ratio - expected_thumb_ratio).abs
      if ratio_diff > 0.25  # Allow 25% tolerance
        passed = false
        reason = "Thumb size mismatch! Expected ~#{(expected_thumb_ratio * 100).round}% but got ~#{(actual_thumb_ratio * 100).round}% (#{thumb_pixels}/10 dark pixels)"
      end
    else
      passed = false
      reason = "ScrollView not found"
    end

    result = passed ? "PASS" : "FAIL"
    @test_results << "#{test_name}: #{result}#{passed ? "" : " - #{reason}"}"
  end

  private def is_scrollbar_color?(pixel : SF::Color) : Bool
    # Scrollbar track/thumb is typically gray (150-220 for all RGB)
    # Not too dark (below 100) and not colored
    gray_range = pixel.r > 140 && pixel.r < 230 &&
                 pixel.g > 140 && pixel.g < 230 &&
                 pixel.b > 140 && pixel.b < 230
    # Also check it's actually gray (R≈G≈B)
    is_gray = (pixel.r.to_i - pixel.g.to_i).abs < 30 &&
              (pixel.g.to_i - pixel.b.to_i).abs < 30
    gray_range && is_gray
  end

  private def is_front_panel_color?(pixel : SF::Color) : Bool
    # FRONT_PANEL_COLOR is (80, 80, 200) - distinctive blue
    (pixel.r.to_i - 80).abs < 40 &&
    (pixel.g.to_i - 80).abs < 40 &&
    (pixel.b.to_i - 200).abs < 40
  end

  private def is_panel_background?(pixel : SF::Color) : Bool
    # Panel background is light gray (~240, 240, 240)
    pixel.r > 220 && pixel.g > 220 && pixel.b > 220 &&
    (pixel.r.to_i - pixel.g.to_i).abs < 20 &&
    (pixel.g.to_i - pixel.b.to_i).abs < 20
  end

  private def is_indicator_color?(pixel : SF::Color) : Bool
    # Green indicator: (100, 255, 100)
    green = (pixel.r.to_i - 100).abs < 50 && pixel.g > 200 && (pixel.b.to_i - 100).abs < 50
    # Red indicator: (255, 100, 100)
    red = pixel.r > 200 && (pixel.g.to_i - 100).abs < 50 && (pixel.b.to_i - 100).abs < 50
    green || red
  end

  private def is_text_color?(pixel : SF::Color) : Bool
    # Text is black or very dark
    pixel.r < 80 && pixel.g < 80 && pixel.b < 80
  end

  private def pixels_equal?(a : SF::Color, b : SF::Color) : Bool
    a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
  end

  private def log_separator(title : String)
    File.open("/tmp/autotest_state.log", "a") do |f|
      f.puts "\n=== #{title} ==="
    end
  end

  private def log_state(phase : String, sv_panel : CrymbleUI::WindowPanel?, front_panel : CrymbleUI::WindowPanel?, sv : CrymbleUI::ScrollView?)
    File.open("/tmp/autotest_state.log", "a") do |f|
      f.puts "#{phase}:"
      if svp = sv_panel
        f.puts "  ScrollView Panel: pos=(#{svp.x.round(1)},#{svp.y.round(1)}) size=(#{svp.width.round(1)},#{svp.height.round(1)})"
      end
      if fp = front_panel
        f.puts "  Front Panel: pos=(#{fp.x.round(1)},#{fp.y.round(1)}) size=(#{fp.width.round(1)},#{fp.height.round(1)})"
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

  private def log_screen_pixel(label : String, x : Int32, y : Int32, pixel : SF::Color)
    File.open("/tmp/autotest_state.log", "a") do |f|
      f.puts "  #{label} at (#{x},#{y}): #{ScreenCapture.pixel_to_string(pixel)}"
    end
  end

  private def log_info(msg : String)
    File.open("/tmp/autotest_state.log", "a") do |f|
      f.puts "  INFO: #{msg}"
    end
  end

  private def log_error(msg : String)
    File.open("/tmp/autotest_state.log", "a") do |f|
      f.puts "  ERROR: #{msg}"
    end
  end

  private def output_results
    File.open("/tmp/autotest_results.log", "w") do |f|
      f.puts "=== ScrollView-in-Panel OVERLAPPING PANELS AutoTest Results ==="
      f.puts "Timestamp: #{Time.local}"
      f.puts ""

      passes = @test_results.count { |r| r.includes?("PASS") }
      fails = @test_results.count { |r| r.includes?("FAIL") }

      f.puts "SUMMARY: #{passes} passed, #{fails} failed"
      f.puts ""
      @test_results.each { |r| f.puts r }
      f.puts ""
      f.puts "Tests:"
      f.puts "  Bug 1: Ghost content when dragging front panel away"
      f.puts "  Bug 2: Scrollbar bleeding through front panel"
      f.puts "  Bug 3: Scrollbar thumb not updating during resize"
      f.puts ""
      f.puts "See /tmp/autotest_state.log for detailed pixel samples"
    end

    # Print to console
    puts "\n=== OVERLAPPING PANELS AutoTest Results ==="
    puts "SUMMARY: #{@test_results.count { |r| r.includes?("PASS") }} passed, #{@test_results.count { |r| r.includes?("FAIL") }} failed"
    @test_results.each { |r| puts r }
    puts "\nLogs written to /tmp/autotest_*.log"
  end
end

# Run the application with screen capture support
app = ScrollViewPanelAutoTest.new
run_with_screen_capture(app)
