require "../../src/crymble-ui"

# SFML autotest: Diagnose "watery/greyish" Button in VirtualMatrix after zoom.
#
# Pure SFML approach: saves PNGs and analyzes pixels using SFML's Image#get_pixel.
# Key test: replicates the EXACT compositor drawing (texture_rect sampling) into a
# temporary RenderTexture to isolate whether compositing introduces the watery effect.
#
# Usage:
#   crystal build spec/autotest/watery_button_autotest.cr -o bin/watery_button_autotest
#   DISPLAY=:0 timeout 45 ./bin/watery_button_autotest
#   cat /tmp/watery_button_detail.log

include CrymbleUI
include CrymbleUI::Widgets::VirtualMatrix

DETAIL_FILE  = "/tmp/watery_button_detail.log"
WINDOW_TITLE = "Watery Button Test"

class TutorialAdapter
  include MatrixAdapter

  @total_rows : Int32
  @total_cols : Int32

  def initialize(@data_rows : Int32, @data_cols : Int32)
    @total_rows = 2 + @data_rows
    @total_cols = 2 + @data_cols
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    rows = (2...@total_rows).to_a + [1, 0]
    cols = (2...@total_cols).to_a + [1, 0]
    {rows, cols}
  end

  def get_sizes : {Array(Float64), Array(Float64)}
    row_heights = Array.new(@total_rows) { |r| r < 2 ? 1.5 : 1.0 }
    col_widths = Array.new(@total_cols) { |c| c < 2 ? 3.0 : 5.0 }
    {row_heights, col_widths}
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    white = Color.new(255, 255, 255, 255)
    if row < 2 && col < 2
      Text.new("", background_color: white)
    elsif col < 2
      Text.new("r#{row}", background_color: white)
    elsif row < 2
      Text.new("c#{col}", background_color: white)
    elsif row == 11 && col == 5
      Button.new("Click") { }
    else
      TextInput.new(value: "(#{row - 2},#{col - 2})", mode: TextInputMode::QuickEntry)
    end
  end
end

# Pixel scanning helper
struct ScanResult
  property blue_count : Int32 = 0
  property non_blue_count : Int32 = 0
  property non_blue_samples : Array(String) = [] of String
end

def scan_button_row(img : SF::Image, bx : Int32, by : Int32, bw : Int32, y : Int32, name : String) : ScanResult
  result = ScanResult.new
  (bx...(bx + bw)).each do |x|
    next if x < 0 || x >= img.size.x.to_i || y < 0 || y >= img.size.y.to_i
    px = img.get_pixel(x, y)
    if px.r == 0 && px.g == 120 && px.b == 215 && px.a == 255
      result.blue_count += 1
    else
      result.non_blue_count += 1
      if result.non_blue_samples.size < 8
        result.non_blue_samples << "    #{name}[#{x},#{y}]=RGBA(#{px.r},#{px.g},#{px.b},#{px.a})"
      end
    end
  end
  result
end

class WateryButtonAutoTest < CrymbleUI::App
  enum Phase
    Settle
    CaptureBeforeZoom
    ApplyZoom
    SettleAfterZoom
    CaptureAfterZoom
    Done
  end

  record Capture,
    wb_scanline : ScanResult,
    cl_scanline : ScanResult,
    comp_alpha_scanline : ScanResult,
    comp_none_scanline : ScanResult,
    smooth : Bool,
    wb_size : {Int32, Int32},
    btn_abs : String

  @phase = Phase::Settle
  @scheduled_first = false
  @before : Capture? = nil
  @after : Capture? = nil

  def build : CrymbleUI::Widget
    if @phase == Phase::Settle && !@scheduled_first && scheduler_ready?
      @scheduled_first = true
      schedule(1200) { run_phase }
    end

    adapter = TutorialAdapter.new(1000, 1000)
    window(WINDOW_TITLE, 900, 600) do
      vstack(padding: 10.0, spacing: 5.0) do
        text("Watery button pixel capture test")
        button("Standalone Button (reference)", id: "ref_btn") { }
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "matrix",
            content_background_color: Color.new(200, 200, 205, 255),
            cursor_highlight_delta: -40))
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

  private def schedule(delay_ms : Int32, &block)
    CrymbleUI::Widget.scheduler.schedule(
      Time::Span.new(nanoseconds: delay_ms.to_i64 * 1_000_000),
      &block
    )
  end

  private def run_phase
    case @phase
    when .settle?
      log("=== PHASE: Settle ===")
      @phase = Phase::CaptureBeforeZoom
      schedule(800) { run_phase }

    when .capture_before_zoom?
      log("=== PHASE: Capture BEFORE zoom (#{CrymbleUI::FontSizing.zoom_percentage}) ===")
      # Trigger window framebuffer capture on NEXT render frame
      CrymbleUI::SFMLRenderer.capture_window_after_composite("/tmp/watery_window_before.png")
      root.try &.mark_needs_render  # Force a composite pass
      @before = capture_all("before")
      @phase = Phase::ApplyZoom
      schedule(500) { run_phase }

    when .apply_zoom?
      log("=== PHASE: Apply zoom ===")
      CrymbleUI::FontSizing.zoom_in
      root.try &.mark_needs_layout
      log("  Zoomed to #{CrymbleUI::FontSizing.zoom_percentage}")
      @phase = Phase::SettleAfterZoom
      schedule(500) { run_phase }

    when .settle_after_zoom?
      log("=== PHASE: Settle after zoom ===")
      @phase = Phase::CaptureAfterZoom
      schedule(1500) { run_phase }

    when .capture_after_zoom?
      log("=== PHASE: Capture AFTER zoom (#{CrymbleUI::FontSizing.zoom_percentage}) ===")
      # Trigger window framebuffer capture on NEXT render frame
      CrymbleUI::SFMLRenderer.capture_window_after_composite("/tmp/watery_window_after.png")
      root.try &.mark_needs_render  # Force a composite pass
      @after = capture_all("after")
      log("")
      compare_and_report
      schedule(500) { quit }

    when .done?
      quit
    end
  end

  private def capture_all(label : String) : Capture?
    vm = find("matrix").as?(CrymbleUI::VirtualMatrix)
    unless vm
      log("  ERROR: no matrix widget")
      return nil
    end

    button = nil.as(Button?)
    vm.active_cells.each_value do |w|
      if w.is_a?(Button)
        button = w
        break
      end
    end
    unless button
      log("  ERROR: no Button in active_cells")
      return nil
    end

    btn_abs = button.absolute_bounds
    log("  Button absolute_bounds: #{btn_abs}")

    # Also find the standalone reference button
    standalone_btn = find("ref_btn").as?(Button)
    if sb = standalone_btn
      sb_abs = sb.absolute_bounds
      log("  Standalone button absolute_bounds: #{sb_abs}")
      if wb = sb.widget_backend
        if wb.is_a?(CrSFMLBackend)
          wb.as(CrSFMLBackend).display
          img = wb.as(CrSFMLBackend).texture.copy_to_image
          img.save_to_file("/tmp/watery_standalone_wb_#{label}.png")
          w = img.size.x.to_i
          sb_scan = scan_button_row(img, 0, 0, w, 2, "standalone_wb")
          sb_scan.non_blue_samples.each { |s| log(s) }
          log("  STANDALONE WB y=2: #{sb_scan.blue_count} blue, #{sb_scan.non_blue_count} non-blue / #{w}")
        end
      end
    end

    # --- 1. Widget backend ---
    wb_scan = ScanResult.new
    wb_size = {0, 0}
    if wb = button.widget_backend
      if wb.is_a?(CrSFMLBackend)
        wb.as(CrSFMLBackend).display
        img = wb.as(CrSFMLBackend).texture.copy_to_image
        img.save_to_file("/tmp/watery_wb_#{label}.png")
        w = img.size.x.to_i
        h = img.size.y.to_i
        wb_size = {w, h}
        log("  Widget backend: #{w}x#{h}")

        # Scan at y=2 (near top, avoids border)
        wb_scan = scan_button_row(img, 0, 0, w, 2, "wb")
        wb_scan.non_blue_samples.each { |s| log(s) }
        log("  WB y=2: #{wb_scan.blue_count} blue, #{wb_scan.non_blue_count} non-blue / #{w}")

        # Full-button average color
        total_r = 0_i64
        total_g = 0_i64
        total_b = 0_i64
        pixel_count = 0
        (0...h).each do |iy|
          (0...w).each do |ix|
            px = img.get_pixel(ix, iy)
            total_r += px.r.to_i64
            total_g += px.g.to_i64
            total_b += px.b.to_i64
            pixel_count += 1
          end
        end
        if pixel_count > 0
          avg_r = (total_r.to_f64 / pixel_count).round(1)
          avg_g = (total_g.to_f64 / pixel_count).round(1)
          avg_b = (total_b.to_f64 / pixel_count).round(1)
          log("  WB AVERAGE COLOR: R=#{avg_r} G=#{avg_g} B=#{avg_b} (#{pixel_count} pixels)")
        end
      end
    end

    # --- 2. Content layer ---
    layer = vm.content_layer
    cl_scan = ScanResult.new
    smooth = false

    if layer
      if backend = layer.backend
        if backend.is_a?(CrSFMLBackend)
          sfml_be = backend.as(CrSFMLBackend)
          sfml_be.display

          # Check smooth setting
          smooth = sfml_be.texture.smooth?
          log("  Content layer texture.smooth? = #{smooth}")

          img = sfml_be.texture.copy_to_image
          img.save_to_file("/tmp/watery_cl_#{label}.png")
          log("  Content layer: #{img.size.x}x#{img.size.y}")

          # Button position in content layer buffer
          buf_x = (btn_abs.x - layer.bounds.x - layer.buffer_origin.x).to_i
          buf_y = (btn_abs.y - layer.bounds.y - layer.buffer_origin.y).to_i
          btn_w = btn_abs.width.to_i
          log("  Button in content layer: (#{buf_x},#{buf_y})")

          cl_scan = scan_button_row(img, buf_x, buf_y, btn_w, buf_y + 2, "cl")
          cl_scan.non_blue_samples.each { |s| log(s) }
          log("  CL y=#{buf_y + 2}: #{cl_scan.blue_count} blue, #{cl_scan.non_blue_count} non-blue / #{btn_w}")
        end
      end
    end

    # --- 3. Overlay layer ---
    if overlay = vm.cursor_overlay_layer
      if ob = overlay.backend
        if ob.is_a?(CrSFMLBackend)
          ob.as(CrSFMLBackend).display
          ovl_img = ob.as(CrSFMLBackend).texture.copy_to_image
          ovl_img.save_to_file("/tmp/watery_overlay_#{label}.png")
          log("  Overlay: #{ovl_img.size.x}x#{ovl_img.size.y}, blend=#{overlay.blend_mode}")
        end
      end
    end

    # --- 4. ALL LAYERS ENUMERATION ---
    # Check every active layer: does it overlap the button area?
    if r = root
      all_layers = Layer.active_layers(r).sort_by(&.z_index)
      log("  ALL LAYERS (#{all_layers.size} total, sorted by z_index):")
      all_layers.each do |l|
        lb = l.bounds
        overlaps_btn = !(lb.x + lb.width < btn_abs.x || lb.x > btn_abs.x + btn_abs.width ||
                         lb.y + lb.height < btn_abs.y || lb.y > btn_abs.y + btn_abs.height)
        vpc = l.viewport_cache ? "VP_CACHE" : "regular"
        log("    z=#{l.z_index} #{l.id} bounds=(#{lb.x.round(1)},#{lb.y.round(1)},#{lb.width.round(1)},#{lb.height.round(1)}) #{vpc} blend=#{l.blend_mode} opacity=#{l.opacity} #{overlaps_btn ? "** OVERLAPS BUTTON **" : ""}")
        if overlaps_btn && l.backend && l.backend.is_a?(CrSFMLBackend)
          be = l.backend.as(CrSFMLBackend)
          be.display
          img = be.texture.copy_to_image
          # Sample at button position within this layer
          if l.viewport_cache
            # viewport_cache: button in buffer coords
            sample_x = (btn_abs.x - l.bounds.x - l.buffer_origin.x).to_i + btn_abs.width.to_i // 2
            sample_y = (btn_abs.y - l.bounds.y - l.buffer_origin.y).to_i + 2
          else
            # regular layer: button position - layer bounds
            sample_x = (btn_abs.x - l.bounds.x).to_i + btn_abs.width.to_i // 2
            sample_y = (btn_abs.y - l.bounds.y).to_i + 2
          end
          if sample_x >= 0 && sample_y >= 0 && sample_x < img.size.x.to_i && sample_y < img.size.y.to_i
            px = img.get_pixel(sample_x, sample_y)
            log("      pixel at button center: RGBA(#{px.r},#{px.g},#{px.b},#{px.a})")
          else
            log("      button center out of bounds for layer backend (#{img.size.x}x#{img.size.y})")
          end
        end
      end
    end

    # --- 5. FULL COMPOSITOR SIMULATION (ALL LAYERS) ---
    # Replicate the EXACT compositor: clear window background, draw ALL layers in z-order
    if r = root
      all_layers = Layer.active_layers(r).sort_by(&.z_index)
      temp_full = SF::RenderTexture.new(900_u32, 600_u32)
      temp_full.clear(SF::Color.new(245, 245, 245, 255))  # Window background color

      all_layers.each do |l|
        next unless be = l.backend
        next unless be.is_a?(CrSFMLBackend)
        sfml_be = be.as(CrSFMLBackend)

        dest_x = l.bounds.x.round(:ties_away).to_f32
        dest_y = l.bounds.y.round(:ties_away).to_f32

        clip_w = l.bounds.width.ceil.to_i
        clip_h = l.bounds.height.ceil.to_i

        sprite = SF::Sprite.new(sfml_be.texture)
        if l.viewport_cache
          vp_x = (l.scroll_offset.x - l.buffer_origin.x).to_i
          vp_y = (l.scroll_offset.y - l.buffer_origin.y).to_i
          buf_w = sfml_be.width
          buf_h = sfml_be.height
          vp_x = vp_x.clamp(0, [buf_w - clip_w, 0].max)
          vp_y = vp_y.clamp(0, [buf_h - clip_h, 0].max)
          sprite.texture_rect = SF.int_rect(vp_x, vp_y, clip_w, clip_h)
        else
          sprite.texture_rect = SF.int_rect(0, 0, clip_w, clip_h)
        end
        sprite.position = SF.vector2f(dest_x, dest_y)

        blend_states = case l.blend_mode
                       when BlendMode::Additive    then SF::RenderStates.new(SF::BlendAdd)
                       when BlendMode::Subtractive then SF::RenderStates.new(SF::BlendSubtract)
                       when BlendMode::Multiply    then SF::RenderStates.new(SF::BlendMultiply)
                       else                          SF::RenderStates::Default
                       end
        temp_full.draw(sprite, blend_states)
      end
      temp_full.display
      full_img = temp_full.texture.copy_to_image
      full_img.save_to_file("/tmp/watery_full_composite_#{label}.png")
      log("  Full compositor sim saved to /tmp/watery_full_composite_#{label}.png")

      # Sample VirtualMatrix button from full composite
      btn_cy = btn_abs.y.to_i + 2
      full_scan = scan_button_row(full_img, btn_abs.x.to_i, btn_abs.y.to_i, btn_abs.width.to_i, btn_cy, "full_comp")
      full_scan.non_blue_samples.each { |s| log(s) }
      log("  FULL_COMP(matrix_btn) y=#{btn_cy}: #{full_scan.blue_count} blue, #{full_scan.non_blue_count} non-blue / #{btn_abs.width.to_i}")

      # Also sample standalone button from full composite
      if sb = standalone_btn
        sb_abs = sb.absolute_bounds
        sb_cy = sb_abs.y.to_i + sb_abs.height.to_i // 2  # mid-height for standalone (taller)
        sb_scan = scan_button_row(full_img, sb_abs.x.to_i, sb_abs.y.to_i, sb_abs.width.to_i, sb_cy, "full_comp_ref")
        sb_scan.non_blue_samples.each { |s| log(s) }
        log("  FULL_COMP(standalone) y=#{sb_cy}: #{sb_scan.blue_count} blue, #{sb_scan.non_blue_count} non-blue / #{sb_abs.width.to_i}")
      end
    end

    # --- 6. SINGLE LAYER COMPOSITOR SIMULATION ---
    # Replicate the EXACT drawing from sfml_renderer.cr composite_viewport_cache_layer
    comp_alpha_scan = ScanResult.new
    comp_none_scan = ScanResult.new

    if layer && (backend = layer.backend) && backend.is_a?(CrSFMLBackend)
      sfml_be = backend.as(CrSFMLBackend)

      viewport_x = (layer.scroll_offset.x - layer.buffer_origin.x).to_i
      viewport_y = (layer.scroll_offset.y - layer.buffer_origin.y).to_i
      viewport_w = layer.bounds.width.ceil.to_i
      viewport_h = layer.bounds.height.ceil.to_i
      buffer_w = sfml_be.width
      buffer_h = sfml_be.height
      viewport_x = viewport_x.clamp(0, [buffer_w - viewport_w, 0].max)
      viewport_y = viewport_y.clamp(0, [buffer_h - viewport_h, 0].max)

      log("  Compositor sim: texture_rect=(#{viewport_x},#{viewport_y},#{viewport_w},#{viewport_h})")
      log("    buffer=(#{buffer_w}x#{buffer_h}) scroll=#{layer.scroll_offset} buf_origin=#{layer.buffer_origin}")

      # Button position in viewport output
      btn_vp_x = (btn_abs.x - layer.bounds.x).to_i
      btn_vp_y = (btn_abs.y - layer.bounds.y).to_i
      btn_w = btn_abs.width.to_i
      log("    Button in viewport: (#{btn_vp_x},#{btn_vp_y})")

      # A) BlendAlpha compositing (what the real compositor does)
      temp_a = SF::RenderTexture.new(viewport_w.to_u32, viewport_h.to_u32)
      temp_a.clear(SF::Color.new(200, 200, 205, 255))  # content_background_color
      sprite_a = SF::Sprite.new(sfml_be.texture)
      sprite_a.texture_rect = SF.int_rect(viewport_x, viewport_y, viewport_w, viewport_h)
      sprite_a.position = SF.vector2f(0, 0)
      sprite_a.color = SF::Color::White
      temp_a.draw(sprite_a)  # Default = BlendAlpha
      temp_a.display
      img_a = temp_a.texture.copy_to_image
      img_a.save_to_file("/tmp/watery_comp_alpha_#{label}.png")

      comp_alpha_scan = scan_button_row(img_a, btn_vp_x, btn_vp_y, btn_w, btn_vp_y + 2, "comp_alpha")
      comp_alpha_scan.non_blue_samples.each { |s| log(s) }
      log("  COMP_ALPHA y=#{btn_vp_y + 2}: #{comp_alpha_scan.blue_count} blue, #{comp_alpha_scan.non_blue_count} non-blue / #{btn_w}")

      # B) BlendNone compositing (for comparison)
      temp_n = SF::RenderTexture.new(viewport_w.to_u32, viewport_h.to_u32)
      temp_n.clear(SF::Color.new(200, 200, 205, 255))
      sprite_n = SF::Sprite.new(sfml_be.texture)
      sprite_n.texture_rect = SF.int_rect(viewport_x, viewport_y, viewport_w, viewport_h)
      sprite_n.position = SF.vector2f(0, 0)
      sprite_n.color = SF::Color::White
      temp_n.draw(sprite_n, SF::RenderStates.new(SF::BlendNone))
      temp_n.display
      img_n = temp_n.texture.copy_to_image
      img_n.save_to_file("/tmp/watery_comp_none_#{label}.png")

      comp_none_scan = scan_button_row(img_n, btn_vp_x, btn_vp_y, btn_w, btn_vp_y + 2, "comp_none")
      comp_none_scan.non_blue_samples.each { |s| log(s) }
      log("  COMP_NONE y=#{btn_vp_y + 2}: #{comp_none_scan.blue_count} blue, #{comp_none_scan.non_blue_count} non-blue / #{btn_w}")

      # C) Direct texture_rect=0,0 (like a regular non-viewport layer — control test)
      temp_z = SF::RenderTexture.new(viewport_w.to_u32, viewport_h.to_u32)
      temp_z.clear(SF::Color.new(200, 200, 205, 255))
      sprite_z = SF::Sprite.new(sfml_be.texture)
      sprite_z.texture_rect = SF.int_rect(0, 0, viewport_w, viewport_h)
      sprite_z.position = SF.vector2f(0, 0)
      sprite_z.color = SF::Color::White
      temp_z.draw(sprite_z)
      temp_z.display
      img_z = temp_z.texture.copy_to_image
      img_z.save_to_file("/tmp/watery_comp_origin_#{label}.png")

      # For origin test, button position is shifted by viewport offset
      btn_orig_x = btn_vp_x + viewport_x
      btn_orig_y = btn_vp_y + viewport_y
      if btn_orig_x + btn_w <= img_z.size.x.to_i && btn_orig_y + 2 < img_z.size.y.to_i
        orig_scan = scan_button_row(img_z, btn_orig_x, btn_orig_y, btn_w, btn_orig_y + 2, "comp_origin")
        orig_scan.non_blue_samples.each { |s| log(s) }
        log("  COMP_ORIGIN y=#{btn_orig_y + 2}: #{orig_scan.blue_count} blue, #{orig_scan.non_blue_count} non-blue / #{btn_w}")
      end
    end

    Capture.new(
      wb_scanline: wb_scan,
      cl_scanline: cl_scan,
      comp_alpha_scanline: comp_alpha_scan,
      comp_none_scanline: comp_none_scan,
      smooth: smooth,
      wb_size: wb_size,
      btn_abs: btn_abs.to_s
    )
  end

  private def compare_and_report
    b = @before
    a = @after
    unless b && a
      log("ERROR: missing capture data")
      return
    end

    log("=== COMPARISON ===")
    log("  Texture smooth: before=#{b.smooth}, after=#{a.smooth}")
    log("")

    {% for field in ["wb_scanline", "cl_scanline", "comp_alpha_scanline", "comp_none_scanline"] %}
      log("  {{ field.id }}:")
      log("    Before: #{b.{{ field.id }}.blue_count} blue, #{b.{{ field.id }}.non_blue_count} non-blue")
      log("    After:  #{a.{{ field.id }}.blue_count} blue, #{a.{{ field.id }}.non_blue_count} non-blue")
      b_pct = b.{{ field.id }}.blue_count == 0 ? 0.0 : (b.{{ field.id }}.blue_count * 100.0 / (b.{{ field.id }}.blue_count + b.{{ field.id }}.non_blue_count))
      a_pct = a.{{ field.id }}.blue_count == 0 ? 0.0 : (a.{{ field.id }}.blue_count * 100.0 / (a.{{ field.id }}.blue_count + a.{{ field.id }}.non_blue_count))
      log("    Blue%%: #{b_pct.round(1)}%% -> #{a_pct.round(1)}%%")
      log("")
    {% end %}

    log("=== SAVED PNGs ===")
    log("  /tmp/watery_wb_{before,after}.png         — widget backend")
    log("  /tmp/watery_cl_{before,after}.png         — content layer")
    log("  /tmp/watery_overlay_{before,after}.png    — cursor overlay")
    log("  /tmp/watery_comp_alpha_{before,after}.png — compositor sim (BlendAlpha)")
    log("  /tmp/watery_comp_none_{before,after}.png  — compositor sim (BlendNone)")
    log("  /tmp/watery_comp_origin_{before,after}.png — compositor sim (texture_rect 0,0)")
  end

  private def log(msg : String)
    File.open(DETAIL_FILE, "a") { |f| f.puts msg }
    puts msg
  end
end

# Clear log
File.write(DETAIL_FILE, "")

# Bootstrap and run
app = WateryButtonAutoTest.new
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
