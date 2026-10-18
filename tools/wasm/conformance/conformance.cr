# The web flavour's conformance program: ONE crymble-ui app, built in both flavours, that draws the same cases into
# backends from the running renderer's create_widget_backend (native: CrSFMLBackend; web: WebBackend) and into the
# window, and prints what it reads back - one `CONF {...}` JSON line per case, then `CONF-END <count>`.
# tools/wasm/conformance.sh runs both and diff.mjs compares them.
#
# It runs as an ordinary app (CrymbleUI.run) so both sides take their real path; the cases run from a timer, after
# a first pass that asks for every image once (the page decodes an image asynchronously - a first draw paints
# nothing, by design).
require "../../../src/crymble-ui"

{% unless flag?(:wasm32) %}
  lib LibCSFML
    fun sfTexture_updateFromRenderWindow(texture : Texture, render_window : RenderWindow, offset : Vector2u)
  end
{% end %}

module CrymbleUI
  # The two things a case needs from the renderer beyond create_widget_backend: compositing a backend into the
  # window as the compositor does, and reading the window back before it is presented.
  class WindowRenderer
    def conformance_composite(backend : RenderBackend, dest_x : Int32, dest_y : Int32, opacity : Float64,
                              blend_mode : BlendMode) : Nil
      draw_layer_region(backend, CompositeRegion.new(dest_x, dest_y, 0, 0, backend.width, backend.height), opacity, blend_mode)
    end
  end

  {% if flag?(:wasm32) %}
    class WebRenderer
      def conformance_clear(color : Color) : Nil
        @window.clear(color)
      end

      def conformance_read(w : Int32, h : Int32) : Array(UInt32)
        @window.capture_region_pixels(0, 0, w, h)
      end
    end
  {% else %}
    class SFMLRenderer
      def conformance_clear(color : Color) : Nil
        @window.not_nil!.clear(SF::Color.new(color.r, color.g, color.b, color.a))
      end

      def conformance_read(w : Int32, h : Int32) : Array(UInt32)
        window = @window.not_nil!
        texture = SF::Texture.new(window.size.x, window.size.y)
        LibCSFML.sfTexture_updateFromRenderWindow(texture, window, LibCSFML::Vector2u.new(x: 0_u32, y: 0_u32))
        image = texture.copy_to_image
        Array(UInt32).new(w * h) do |i|
          px = image.get_pixel(i % w, i // w)
          (px.r.to_u32 << 24) | (px.g.to_u32 << 16) | (px.b.to_u32 << 8) | px.a.to_u32
        end
      end
    end
  {% end %}
end

module Conformance
  alias C = CrymbleUI::Color
  alias R = CrymbleUI::Rect
  alias V = CrymbleUI::Vec2

  W  = 48 # a backend case's size
  H  = 32
  WW = 96 # the window region a composite case reads
  WH = 64

  PAPER  = C.new(230, 230, 230, 255)
  INK    = C.new(20, 90, 200, 255)
  RED    = C.new(220, 30, 30, 255)
  CLEAR  = C.new(0, 0, 0, 0)
  WINDOW = C.new(200, 220, 240, 255)
  LOGO   = embed_image("tutorials/crystal_logo.png")

  # A case: what it covers (a RenderBackend method), how diff.mjs compares it, and the drawing. A "contract" case
  # also draws what RenderBackend's contract says the result is (with fills), and each flavour is held to that.
  record Case, name : String, covers : String, kind : String, draw : Proc(CrymbleUI::RenderBackend, Nil),
    expected : Proc(CrymbleUI::RenderBackend, Nil)? = nil
  # A window case composites backends into the window and reads the window back.
  record WindowCase, name : String, blend : String, draw : Proc(Nil)

  CASES        = [] of Case
  WINDOW_CASES = [] of WindowCase

  def self.add(name, covers, kind = "geometry", &draw : CrymbleUI::RenderBackend -> Nil)
    CASES << Case.new(name, covers, kind, draw)
  end

  def self.add_contract(name, covers, expected : CrymbleUI::RenderBackend -> Nil, &draw : CrymbleUI::RenderBackend -> Nil)
    CASES << Case.new(name, covers, "contract", draw, expected)
  end

  def self.renderer
    CrymbleUI.renderer.not_nil!
  end

  def self.backend(w = W, h = H, clear = PAPER) : CrymbleUI::RenderBackend
    b = renderer.create_widget_backend(w, h)
    b.clear(clear)
    b
  end

  # The instrument first: an asymmetric pattern a flipped or blank read-back cannot reproduce.
  add("instrument", "fill_rect") do |b|
    b.fill_rect(R.new(0.0, 0.0, 3.0, 2.0), RED)
    b.fill_rect(R.new(W - 5.0, H - 3.0, 5.0, 3.0), INK)
  end

  add("fill_rect fractional", "fill_rect") do |b|
    b.fill_rect(R.new(3.3, 4.6, 10.4, 7.5), INK)
    b.fill_rect(R.new(20.5, 4.5, 8.0, 6.0), RED)
    b.fill_rect(R.new(32.49, 12.51, 9.02, 9.98), INK)
  end
  add("fill_rect translucent", "fill_rect") { |b| b.fill_rect(R.new(4.0, 4.0, 30.0, 20.0), C.new(200, 30, 30, 100)) }
  add("draw_rect 1", "draw_rect") { |b| b.draw_rect(R.new(3.0, 3.0, 20.0, 12.0), INK) }
  add("draw_rect fractional 2.5", "draw_rect") { |b| b.draw_rect(R.new(4.4, 5.7, 30.3, 18.2), RED, 2.5) }
  add("draw_line axis", "draw_line") do |b|
    b.draw_line(2.0, 5.0, 40.0, 5.0, INK)
    b.draw_line(10.5, 2.0, 10.5, 28.0, RED, 3.0)
  end
  add("draw_line diagonal", "draw_line") do |b|
    b.draw_line(3.0, 3.0, 44.0, 28.0, INK, 2.0)
    b.draw_line(40.3, 4.7, 6.2, 26.1, RED)
  end
  add("draw_circle fill", "draw_circle") { |b| b.draw_circle(16.3, 15.7, 9.4, INK) }
  add("draw_circle outline", "draw_circle") { |b| b.draw_circle(30.0, 16.0, 11.0, RED, fill: false) }
  add("fill_triangle", "fill_triangle") { |b| b.fill_triangle(V.new(3.0, 28.0), V.new(24.5, 2.2), V.new(44.7, 25.3), INK) }
  add("draw_text 16", "draw_text", "text") { |b| b.draw_text("Ag Wy", V.new(3.4, 4.6), INK, 16.0) }
  add("draw_text tab", "draw_text", "text") { |b| b.draw_text("a\tb", V.new(2.0, 4.0), C.new(0, 0, 0, 255), 16.0) }
  add("draw_text 14 lines", "draw_text", "text") { |b| b.draw_text("AB 12\ncd {}", V.new(2.0, 0.5), C.new(0, 0, 0, 255), 14.0) }
  add("draw_image tinted", "draw_image", "image") do |b|
    b.draw_image(LOGO, R.new(4.0, 0.0, 32.0, 32.0), C.new(255, 100, 100, 160))
  end
  add("draw_image downscaled", "draw_image", "image") { |b| b.draw_image(LOGO, R.new(30.0, 8.0, 14.0, 14.0), C.new(255, 255, 255, 255)) }
  add("blit", "blit") do |b|
    src = backend(20, 12)
    src.fill_rect(R.new(0.0, 0.0, 10.0, 12.0), INK)
    src.fill_rect(R.new(10.0, 0.0, 10.0, 6.0), RED)
    src.display
    b.blit(src, 5, 7)
    src.dispose
  end
  # blit_region's contract: the source rows [src_y, src_y + h) land top-down at dest_y (TestRenderBackend's copy).
  add_contract("blit_region", "blit_region", ->(b : CrymbleUI::RenderBackend) do
    b.fill_rect(R.new(3.0, 4.0, 5.0, 15.0), INK)
    b.fill_rect(R.new(8.0, 4.0, 13.0, 5.0), RED)
    nil
  end) do |b|
    src = backend(30, 20)
    src.fill_rect(R.new(0.0, 0.0, 15.0, 20.0), INK)
    src.fill_rect(R.new(15.0, 0.0, 15.0, 7.0), RED)
    src.display
    b.blit_region(src, 10, 2, 18, 15, 3, 4)
    src.dispose
  end
  add_contract("blit_region self-overlapping", "blit_region", ->(b : CrymbleUI::RenderBackend) do
    b.fill_rect(R.new(2.0, 2.0, 20.0, 6.0), INK)
    b.fill_rect(R.new(2.0, 8.0, 20.0, 6.0), RED)
    b.fill_rect(R.new(7.0, 5.0, 20.0, 6.0), INK)
    b.fill_rect(R.new(7.0, 11.0, 20.0, 6.0), RED)
    nil
  end) do |b|
    b.fill_rect(R.new(2.0, 2.0, 20.0, 6.0), INK)
    b.fill_rect(R.new(2.0, 8.0, 20.0, 6.0), RED)
    b.display
    b.blit_region(b, 2, 2, 20, 12, 7, 5)
  end
  add("push_clip fractional", "push_clip") do |b|
    b.push_clip(R.new(5.5, 3.2, 20.1, 10.7))
    b.fill_rect(R.new(0.0, 0.0, W.to_f, H.to_f), INK)
    b.pop_clip
  end
  add("push_clip nested", "push_clip") do |b|
    b.push_clip(R.new(4.0, 4.0, 30.0, 20.0))
    b.push_clip(R.new(20.0, 10.0, 25.0, 20.0))
    b.fill_rect(R.new(0.0, 0.0, W.to_f, H.to_f), RED)
    b.pop_clip
    b.fill_rect(R.new(0.0, 0.0, 12.0, H.to_f), INK)
    b.pop_clip
  end
  add("pop_clip", "pop_clip") do |b|
    b.push_clip(R.new(10.0, 10.0, 5.0, 5.0))
    b.pop_clip
    b.fill_rect(R.new(2.0, 2.0, 30.0, 20.0), INK)
  end
  add("clear under a suspended clip", "clear") do |b|
    b.push_clip(R.new(10.0, 10.0, 10.0, 10.0))
    b.suspend_clip
    b.clear(C.new(250, 240, 200, 255))
    b.resume_clip
    b.fill_rect(R.new(0.0, 0.0, W.to_f, H.to_f), INK)
    b.pop_clip
  end

  # Window cases: translucent ink on a transparent backend (the cursor overlay's real alphas, 60 and 100) and an
  # opaque pattern, composited as a layer is.
  def self.overlay(alpha : Int32, w = 60, h = 40) : CrymbleUI::RenderBackend
    b = backend(w, h, CLEAR)
    b.fill_rect(R.new(0.0, 0.0, w.to_f, h / 2), C.new(255, 220, 60, alpha))
    b.fill_rect(R.new(10.0, h / 2, w - 20.0, h / 2), C.new(40, 120, 255, alpha))
    b.display
    b
  end

  {% for blend in %w(Normal Additive Subtractive Multiply) %}
    {% for alpha in [60, 100] %}
      WINDOW_CASES << WindowCase.new("composite {{blend.id}} alpha {{alpha}}", {{blend}}, -> do
        opaque = backend(50, 30)
        opaque.fill_rect(R.new(5.0, 5.0, 20.0, 20.0), INK)
        opaque.display
        renderer.conformance_composite(opaque, 4, 4, 1.0, CrymbleUI::BlendMode::Normal)
        layer = overlay({{alpha}})
        renderer.conformance_composite(layer, 20, 14, 0.8, CrymbleUI::BlendMode::{{blend.id}})
        opaque.dispose
        layer.dispose
        nil
      end)
    {% end %}
  {% end %}
  # a layer composited, drawn on, composited again: the page keeps each layer prepared for compositing until it is
  # drawn on - a stale preparation would show the first content
  WINDOW_CASES << WindowCase.new("composite a layer drawn on since", "Normal", -> do
    layer = backend(50, 30)
    layer.fill_rect(R.new(0.0, 0.0, 50.0, 30.0), RED)
    layer.display
    renderer.conformance_composite(layer, 6, 6, 1.0, CrymbleUI::BlendMode::Normal)
    layer.fill_rect(R.new(10.0, 5.0, 30.0, 20.0), INK)
    layer.display
    renderer.conformance_composite(layer, 6, 6, 1.0, CrymbleUI::BlendMode::Normal)
    layer.dispose
    nil
  end)
  # an opaque layer in every mode (the page takes a one-operation path for a source with no translucent texel)
  {% for blend in %w(Additive Subtractive Multiply) %}
    WINDOW_CASES << WindowCase.new("composite {{blend.id}} opaque", {{blend}}, -> do
      layer = backend(50, 30, C.new(90, 160, 40, 255))
      layer.fill_rect(R.new(10.0, 5.0, 20.0, 20.0), C.new(200, 120, 250, 255))
      layer.display
      renderer.conformance_composite(layer, 12, 10, 0.8, CrymbleUI::BlendMode::{{blend.id}})
      layer.dispose
      nil
    end)
  {% end %}
  # shapes straight onto the window (render_primitives - an overlay's path) - a polygon on the window, unlike one on
  # a backend, is not y-flipped (the tie rule)
  WINDOW_CASES << WindowCase.new("window-direct line and triangle", "Normal", -> do
    renderer.render_primitives([CrymbleUI::DrawLine.new(V.new(4.0, 5.0), V.new(60.0, 5.0), RED),
                                CrymbleUI::DrawLine.new(V.new(70.5, 3.0), V.new(70.5, 40.0), INK, 3.0),
                                CrymbleUI::FillTriangle.new(V.new(10.5, 50.5), V.new(40.0, 20.5), V.new(55.5, 50.5), INK)] of CrymbleUI::DrawPrimitive)
    nil
  end)
  # a fill straight onto the window (render_primitives - an overlay's path), on fractional edges
  WINDOW_CASES << WindowCase.new("window-direct fill_rect fractional", "Normal", -> do
    renderer.render_primitives([CrymbleUI::FillRect.new(R.new(10.5, 8.5, 20.0, 12.3), RED),
                                CrymbleUI::FillRect.new(R.new(40.3, 20.7, 9.4, 7.5), INK)] of CrymbleUI::DrawPrimitive)
    nil
  end)
  {% for blend in %w(Additive Subtractive) %}
    WINDOW_CASES << WindowCase.new("composite {{blend.id}} full window", {{blend}}, -> do
      layer = overlay(100, WW, WH)
      renderer.conformance_composite(layer, 0, 0, 1.0, CrymbleUI::BlendMode::{{blend.id}})
      layer.dispose
      nil
    end)
  {% end %}

  # Every drawing method of RenderBackend has a case: a method added without one fails the run.
  NOT_DRAWING = %w(width height display clip_depth capture_region_pixels release_payload dispose suspend_clip assert_inside
    resume_clip disposed? assert_live assert_live_other)

  def self.uncovered : Array(String)
    methods = {{ CrymbleUI::RenderBackend.methods.map(&.name.stringify).uniq }}
    methods.reject { |m| NOT_DRAWING.includes?(m) || CASES.any? { |c| c.covers == m } }
  end

  def self.hex(pixels : Array(UInt32)) : String
    String.build { |s| pixels.each { |p| s << p.to_s(16).rjust(8, '0') } }
  end

  def self.emit(name, kind, w, h, pixels)
    puts %(CONF {"case":#{name.to_json},"kind":#{kind.to_json},"w":#{w},"h":#{h},"px":"#{hex(pixels)}"})
  end

  def self.warm_images : Nil
    b = backend
    CASES.each { |c| c.draw.call(b) if c.kind == "image" }
    b.dispose
  end

  # A file dialog's first look at the disk, as the program's FIRST file-system calls: list a folder and stat each
  # entry while the listing is open. In the page, wasi-libc then looks for its preopened directories with that
  # folder's fd open - a shim answering ENOTSUP for it there made wasi-libc exit (71); this line never printed.
  def self.list_folder : Nil
    entries = [] of String
    Dir.each_child(".") { |name| entries << name if File.info?(name) }
    puts "CONF-LISTED #{entries.size}"
  end

  def self.run_all : Nil
    if (missing = uncovered).any?
      puts "CONF-ERROR RenderBackend methods without a case: #{missing.join(", ")}"
    end
    CASES.each do |c|
      b = backend
      c.draw.call(b)
      b.display
      emit(c.name, c.kind, W, H, b.capture_region_pixels(0, 0, W, H))
      b.dispose
      if expected = c.expected
        b = backend
        expected.call(b)
        b.display
        emit("#{c.name} (contract)", c.kind, W, H, b.capture_region_pixels(0, 0, W, H))
        b.dispose
      end
    end
    WINDOW_CASES.each do |c|
      renderer.conformance_clear(WINDOW)
      c.draw.call
      emit(c.name, "composite", WW, WH, renderer.conformance_read(WW, WH))
    end
    metrics
    puts "CONF-END #{CASES.size + CASES.count(&.expected) + WINDOW_CASES.size}"
    STDOUT.flush
  end

  # Text metrics through the Font the flavour installed: widths, offsets, line spacing (a two-line height) and the
  # reference height, at the sizes the widgets use.
  def self.metrics : Nil
    font = CrymbleUI::Widget.font.not_nil!
    rows = [] of String
    [12.0, 16.0, 24.0].each do |size|
      ["Ag", "Hello, World", "  lead", "trail  ", "x\ny", "{[|]}", "0123456789", "a\tb"].each do |text|
        m = font.measure_text(text, size)
        left, top = font.get_text_offsets(text, size)
        rows << %({"size":#{size},"text":#{text.to_json},"w":#{m.width},"h":#{m.height},"left":#{left},"top":#{top},"ref":#{font.reference_height(size)}})
      end
    end
    puts %(CONF-METRICS [#{rows.join(",")}])
  end
end

class ConformanceApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("conformance", Conformance::WW, Conformance::WH) { vstack { text("conformance") } }
  end

  def on_start
    Conformance.list_folder
    after(100.milliseconds) { Conformance.warm_images }
    after(800.milliseconds) do
      Conformance.run_all
      quit
    end
  end
end

CrymbleUI.run(ConformanceApp.new)
