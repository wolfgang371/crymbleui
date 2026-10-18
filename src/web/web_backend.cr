require "../core/types"
require "../rendering/render_backend"
require "../rendering/pixel_snap"
require "../rendering/clip_math"
require "../rendering/draw_primitive"
require "../core/widget"
require "./js"
require "./web_font"

module CrymbleUI
  # A RenderBackend on a canvas of the page (the web flavour's CrSFMLBackend). It paints what CrSFMLBackend paints
  # for the same calls - the same shapes (an outline is four inner rects, a line a rotated rect), the same text
  # model (baseline at y + size, snapped position) and the GPU's pixel-centre rule for filled geometry; only glyph
  # antialiasing is the browser's. tools/wasm/conformance compares the two backend by backend.
  #
  # A canvas is top-down and live, so there is no FBO flip and nothing to flush: display is a no-op and a backend
  # is a valid blit source the moment it was drawn.
  class WebBackend
    include RenderBackend

    getter canvas : Int32
    @width : Int32
    @height : Int32
    @clip_stack = [] of Rect

    def initialize(@width : Int32, @height : Int32)
      @canvas = LibCrymbleWeb.canvas_new(@width, @height)
    end

    # The page's own canvas (id 0), sized by the page.
    def self.window : WebBackend
      new(0)
    end

    private def initialize(@canvas : Int32)
      LibCrymbleWeb.canvas_size(@canvas, out w, out h)
      @width = w
      @height = h
    end

    # The page resized its canvas. (The clip survives: the page keeps it per canvas and applies it to every draw.)
    def resized : Nil
      LibCrymbleWeb.canvas_size(@canvas, out w, out h)
      @width = w
      @height = h
    end

    def width : Int32
      @width
    end

    def height : Int32
      @height
    end

    def clear(color : Color)
      assert_live("clear")
      LibCrymbleWeb.clear(@canvas, rgba(color))
    end

    def fill_rect(bounds : Rect, color : Color)
      assert_live("fill_rect")
      fill_box(bounds.x, bounds.y, bounds.width, bounds.height, color)
    end

    # Four filled rects INSIDE bounds - CrSFMLBackend's outline.
    def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)
      assert_live("draw_rect")
      x, y, w, h, t = bounds.x, bounds.y, bounds.width, bounds.height, width
      fill_box(x, y, w, t, color)
      fill_box(x, y + h - t, w, t, color)
      fill_box(x, y, t, h, color)
      fill_box(x + w - t, y, t, h, color)
    end

    # A rect of the line's length and width, rotated by the line's angle about its own top-left corner placed at
    # (x1, y1 - width/2) - CrSFMLBackend's SFML RectangleShape, corner for corner.
    def draw_line(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64, color : Color, width : Float64 = 1.0)
      assert_live("draw_line")
      dx = x2 - x1
      dy = y2 - y1
      length = Math.sqrt(dx * dx + dy * dy)
      angle = Math.atan2(dy, dx)
      cos = Math.cos(angle)
      sin = Math.sin(angle)
      ox = x1
      oy = y1 - width / 2.0
      xy = StaticArray[ox, oy,
        ox + length * cos, oy + length * sin,
        ox + length * cos - width * sin, oy + length * sin + width * cos,
        ox - width * sin, oy + width * cos]
      LibCrymbleWeb.fill_polygon(@canvas, xy.to_unsafe, 4, rgba(color))
    end

    def draw_circle(center_x : Float64, center_y : Float64, radius : Float64, color : Color, fill : Bool = true)
      assert_live("draw_circle")
      LibCrymbleWeb.circle(@canvas, center_x, center_y, radius, fill, rgba(color))
    end

    def fill_triangle(p1 : Vec2, p2 : Vec2, p3 : Vec2, color : Color)
      assert_live("fill_triangle")
      xy = StaticArray[p1.x, p1.y, p2.x, p2.y, p3.x, p3.y]
      LibCrymbleWeb.fill_polygon(@canvas, xy.to_unsafe, 3, rgba(color))
    end

    # Line by line, as sf::Text lays a multi-line string out: each line's baseline one line spacing (the font's)
    # below the previous one.
    def draw_text(text : String, position : Vec2, color : Color, size : Float64)
      assert_live("draw_text")
      x = PixelSnap.snap(position.x)
      y = PixelSnap.snap(position.y)
      step = Widget.font.as(WebFont).line_spacing(size)
      text.split('\n').each_with_index do |line, i|
        next if line.empty?
        LibCrymbleWeb.text(@canvas, line.to_unsafe, line.bytesize, x, y + i * step, size.round, rgba(color))
      end
    end

    # As CrSFMLBackend: embedded bytes when the source has them, else the key as a path (read through WASI); a
    # source that cannot be read draws nothing and is tried again next time. The page keeps every image it was
    # handed by key, so the bytes go over once (a disk image is read once, as CrSFMLBackend caches its texture).
    # An image the page has not decoded yet draws nothing - the page reports the decode as an invalidation, and
    # the renderer renders again.
    @@handed_over = Set(String).new

    def draw_image(source : ImageSource, bounds : Rect, color : Color)
      assert_live("draw_image")
      bytes = if @@handed_over.includes?(source.key)
                Bytes.empty
              else
                source.bytes || begin
                  File.read(source.key).to_slice
                rescue
                  return
                end
              end
      @@handed_over << source.key
      LibCrymbleWeb.image(@canvas, source.key.to_unsafe, source.key.bytesize, bytes.to_unsafe, bytes.size,
        bounds.x, bounds.y, bounds.width, bounds.height, rgba(color))
    end

    def display
      assert_live("display")
    end

    def blit(source : RenderBackend, dest_x : Int32, dest_y : Int32)
      assert_live("blit")
      assert_live_other(source, "blit", "source")
      src = same_kind(source)
      LibCrymbleWeb.copy(@canvas, src.canvas, 0, 0, src.width, src.height, dest_x, dest_y)
    end

    def blit_region(source : RenderBackend, src_x : Int32, src_y : Int32, width : Int32, height : Int32, dest_x : Int32, dest_y : Int32)
      assert_live("blit_region")
      assert_live_other(source, "blit_region", "source")
      LibCrymbleWeb.copy(@canvas, same_kind(source).canvas, src_x, src_y, width, height, dest_x, dest_y)
    end

    # Composite a region of `source` onto this backend (the window) with the layer's opacity and blend mode.
    def composite(source : WebBackend, src_x : Int32, src_y : Int32, width : Int32, height : Int32,
                  dest_x : Int32, dest_y : Int32, opacity : Float64, blend_mode : BlendMode) : Nil
      assert_live("composite")
      assert_live_other(source, "composite", "source")
      LibCrymbleWeb.composite(@canvas, source.canvas, src_x, src_y, width, height, dest_x, dest_y, opacity, blend_mode.value)
    end

    def push_clip(rect : Rect)
      assert_live("push_clip")
      @clip_stack << rect
      apply_clip
    end

    def pop_clip
      assert_live("pop_clip")
      @clip_stack.pop
      apply_clip
    end

    def clip_depth : Int32
      @clip_stack.size
    end

    # A canvas clip also limits clears, as SFML's scissor does: the same suspension around a full-target clear.
    def suspend_clip
      assert_live("suspend_clip")
      LibCrymbleWeb.unclip(@canvas)
    end

    def resume_clip
      assert_live("resume_clip")
      apply_clip
    end

    def capture_region_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Array(UInt32)
      assert_live("capture_region_pixels")
      buf = Bytes.new(w * h * 4)
      LibCrymbleWeb.read_pixels(@canvas, x, y, w, h, buf.to_unsafe)
      Array(UInt32).new(w * h) do |i|
        (buf[i * 4].to_u32 << 24) | (buf[i * 4 + 1].to_u32 << 16) | (buf[i * 4 + 2].to_u32 << 8) | buf[i * 4 + 3].to_u32
      end
    end

    protected def release_payload : Nil
      LibCrymbleWeb.canvas_free(@canvas) unless @canvas == 0
    end

    private def apply_clip : Nil
      if box = ClipMath.device_box(@clip_stack)
        x0, y0, x1, y1 = box
        LibCrymbleWeb.clip(@canvas, x0, y0, x1, y1)
      else
        LibCrymbleWeb.unclip(@canvas)
      end
    end

    # A float rect filled the way the rasterizer fills it: PixelSnap's fill edges, y flipped as on a RenderTexture -
    # every canvas but the window stands for one.
    private def fill_box(x : Float64, y : Float64, w : Float64, h : Float64, color : Color) : Nil
      LibCrymbleWeb.fill_rect(@canvas, PixelSnap.fill_edge(x), fill_edge_y(y), PixelSnap.fill_edge(x + w), fill_edge_y(y + h),
        rgba(color))
    end

    private def fill_edge_y(v : Float64) : Int32
      @canvas == 0 ? PixelSnap.fill_edge(v) : PixelSnap.fill_edge_y_flipped(v)
    end

    private def same_kind(source : RenderBackend) : WebBackend
      source.as?(WebBackend) || raise "blit between mismatched backend types (#{source.class}) — one renderer pass is backend-homogeneous"
    end

    private def rgba(color : Color) : UInt32
      (color.r.to_u32 << 24) | (color.g.to_u32 << 16) | (color.b.to_u32 << 8) | color.a.to_u32
    end
  end
end
