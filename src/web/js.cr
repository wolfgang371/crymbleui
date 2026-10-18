module CrymbleUI
  # The page's side of the web flavour: what web/crymble.js provides to the wasm module (import module "crymble").
  # Scalars and pointers only - no struct crosses the boundary, so no C-ABI rule for aggregates applies. Colours
  # are packed RGBA (0xRRGGBBAA). Every canvas is an id; canvas 0 is the page's own.
  @[Link(wasm_import_module: "crymble")]
  lib LibCrymbleWeb
    # --- canvases ---
    fun canvas_new(width : Int32, height : Int32) : Int32
    fun canvas_free(id : Int32) : Nil
    fun canvas_size(id : Int32, width : Int32*, height : Int32*) : Nil
    # Clip to the device box [x0, x1) x [y0, y1); unclip drops it. Draws AND clears are clipped (SFML's scissor).
    fun clip(id : Int32, x0 : Int32, y0 : Int32, x1 : Int32, y1 : Int32) : Nil
    fun unclip(id : Int32) : Nil

    # --- drawing (device pixels, as the backend converted them) ---
    fun clear(id : Int32, rgba : UInt32) : Nil
    fun fill_rect(id : Int32, x0 : Int32, y0 : Int32, x1 : Int32, y1 : Int32, rgba : UInt32) : Nil
    # A filled convex polygon (n points at xy: x0, y0, x1, y1, ...), drawn with the pixel-centre rule.
    fun fill_polygon(id : Int32, xy : Float64*, n : Int32, rgba : UInt32) : Nil
    # A circle as SFML draws one: filled, or a 1px outline OUTSIDE the radius.
    fun circle(id : Int32, cx : Float64, cy : Float64, radius : Float64, fill : Bool, rgba : UInt32) : Nil
    # Text with its baseline at y + size (SFML's text model); utf8 is not NUL-terminated.
    fun text(id : Int32, utf8 : UInt8*, len : Int32, x : Float64, y : Float64, size : Float64, rgba : UInt32) : Nil
    # An image (encoded bytes, decoded by the page and cached under key) scaled to the rect, its colours and alpha
    # multiplied by rgba (SFML's sprite colour). False while the image is not decoded yet.
    fun image(id : Int32, key : UInt8*, key_len : Int32, bytes : UInt8*, bytes_len : Int32,
              x : Float64, y : Float64, w : Float64, h : Float64, rgba : UInt32) : Bool
    # Copy a region over the destination, alpha included (BlendNone); overlapping same-canvas copies are safe.
    fun copy(dst : Int32, src : Int32, sx : Int32, sy : Int32, w : Int32, h : Int32, dx : Int32, dy : Int32) : Nil
    # Composite a region onto the destination with an opacity and a BlendMode value - SFML's arithmetic for each.
    fun composite(dst : Int32, src : Int32, sx : Int32, sy : Int32, w : Int32, h : Int32, dx : Int32, dy : Int32,
                  opacity : Float64, blend_mode : Int32) : Nil
    # Read RGBA pixels (row-major, 4 bytes each) into buf.
    fun read_pixels(id : Int32, x : Int32, y : Int32, w : Int32, h : Int32, buf : UInt8*) : Nil

    # --- text metrics: the local bounds SFML's sf::Text reports (left, top, width, height) at size ---
    fun measure(utf8 : UInt8*, len : Int32, size : Float64, out : Float64*) : Nil

    # --- the window and its input ---
    # The next queued input event as scalars (WebRenderer builds the LibCSFML::Event): false when none.
    # mods: bit 0 alt, 1 control, 2 shift, 3 system.
    fun next_event(type : Int32*, i0 : Int32*, i1 : Int32*, i2 : Int32*, f : Float64*, mods : Int32*) : Bool
    fun set_title(utf8 : UInt8*, len : Int32) : Nil
    fun set_cursor(cursor : Int32) : Nil
    # Platform events that invalidated drawn pixels since the last call (an image decoded after it was asked for,
    # a canvas context lost and restored).
    fun invalidations : Int32

    # --- clipboard (the page keeps the text: paste arrives with the browser's paste event) ---
    # Copies the text into buf (up to cap bytes) and returns its full length in bytes.
    fun clipboard_get(buf : UInt8*, cap : Int32) : Int32
    fun clipboard_set(utf8 : UInt8*, len : Int32) : Nil
  end
end
