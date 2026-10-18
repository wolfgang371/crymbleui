require "./web_renderer"

# The web flavour's entry points, exported to the page (web/crymble-web.js). The module is a WASI "reactor": the
# page calls crymble_init once, then crymble_tick per animation frame and crymble_gc after it.
#
# The garbage collector stays DISABLED except inside crymble_gc. WebAssembly keeps a function's locals out of
# linear memory, where the collector cannot see them - inside a tick, an object only a local holds would look
# unreachable. Between two ticks no wasm function is running, so no such local exists, and a collection there sees
# every live object (the data segment and the heap; the shadow stack is empty).

module CrymbleUI
  # The renderer CrymbleUI.run started (crymble-ui.cr) - also the root that keeps the app alive between ticks.
  def self.web_renderer : WebRenderer?
    @@renderer
  end
end

# Set up the runtime, then run the app's own main file (its top level reaches CrymbleUI.run, which on the web
# starts the renderer and returns). 0: the app is running; 1: its top level raised (printed); 2: it returned
# without calling CrymbleUI.run. The ORDER is required: the collector (GC.init, which also registers the data
# segment as roots) before anything allocates, and off before anything else runs - the runtime's set-up (fibers,
# threads, once) holds its objects in wasm locals too.
fun crymble_init : Int32
  GC.init
  GC.disable
  Crystal.init_runtime
  begin
    LibCrystalMain.__crystal_main(0, Pointer(Pointer(UInt8)).null)
  rescue ex
    Crystal::System.print_exception "Unhandled exception", ex
    return 1
  ensure
    STDOUT.flush
    STDERR.flush
  end
  CrymbleUI.web_renderer ? 0 : 2
end

# One frame. 2: rendered; 1: idle; 0: the app closed; -1: the frame raised (printed) - the page stops ticking,
# as a desktop app would have ended. A tick finds the window closed at its start and finishes the run (its logs), so
# the app quitting inside one gets one more - the page ticks no further.
fun crymble_tick : Int32
  return 0 unless renderer = CrymbleUI.web_renderer
  rendered = renderer.tick
  return (rendered ? 2 : 1) if renderer.open?
  renderer.tick
  0
rescue ex
  Crystal::System.print_exception "Unhandled exception", ex
  -1
ensure
  STDOUT.flush
  STDERR.flush
end

# Collect, between ticks, once `threshold` bytes were allocated since the last collection. 1 if it collected.
fun crymble_gc(threshold : Int32) : Int32
  return 0 if GC.stats.bytes_since_gc < threshold.to_u64
  GC.enable
  GC.collect
  GC.disable
  1
end

# The embedded font (the page loads it as a FontFace before crymble_init).
fun crymble_font(ptr : UInt32*, len : UInt32*) : Nil
  ptr.value = CrymbleUI::EmbeddedFont::BYTES.to_unsafe.address.to_u32
  len.value = CrymbleUI::EmbeddedFont::BYTES.bytesize.to_u32
end

# The shortcuts the app has right now - its registered ones and crymble-ui's built-ins - one per line, as
# Shortcut#to_display_string writes them, copied into buf (up to cap bytes); returns the full length in bytes.
fun crymble_shortcuts(buf : UInt8*, cap : Int32) : Int32
  manager = CrymbleUI::Widget.shortcut_manager?
  names = (manager.try(&.registered.map(&.to_display_string)) || [] of String) + CrymbleUI::KeyboardDispatch::BUILT_INS
  text = names.uniq.join('\n')
  buf.copy_from(text.to_unsafe, {text.bytesize, cap}.min) if cap > 0
  text.bytesize
end

# Moves whenever crymble_shortcuts may answer differently.
fun crymble_shortcuts_revision : Int32
  CrymbleUI::Widget.shortcut_manager?.try(&.revision) || 0
end

fun crymble_heap_mb : Int32
  (GC.stats.heap_size // 1_048_576).to_i
end
