require "../core/layer"

module CrymbleUI
  # Render-state dump — the first thing to reach for on a "looks wrong on screen" bug.
  #
  # Visual desyncs (data frozen, cells at the wrong place, blank strips) are almost never an
  # offset/logic problem — the logical state is usually fine. The bug is in WHICH layer something is
  # drawn on and at WHAT bounds. This dumps every active layer's backend buffer to a PNG plus a text
  # report of each layer's geometry and EVERY widget's bounds, so you can SEE the rendered state
  # instead of guessing from numbers. (Hard-won: a sticky-cell desync once cost hours of offset
  # logging because the offsets were all healthy — the freeze was purely in cell bounds on a layer
  # that didn't even hold the data we assumed it did.)
  module RenderDebug
    # Dump all active layers under `root` to `dir` (PNG per layer + report.txt). Returns the report.
    # Cheap and on-demand — wire it to a dev keybind, never to a per-frame path.
    def self.dump(root : Widget, dir : String = "/tmp/render_dump") : String
      Dir.mkdir_p(dir)
      report = String.build do |s|
        s << "=== render dump (#{Layer.active_layers(root).size} active layers) ===\n"
        Layer.active_layers(root).sort_by(&.z_index).each do |layer|
          b = layer.backend
          buf = (b && b.responds_to?(:width)) ? "#{b.width}x#{b.height}" : "none"
          s << "\nLAYER #{layer.id}  z=#{layer.z_index}  bounds=#{layer.bounds}  scroll=#{layer.scroll_offset}" \
               "  buffer_origin=#{layer.buffer_origin}  viewport_cache=#{layer.viewport_cache}" \
               "  backend=#{buf}  needs_render=#{layer.needs_render?}  widgets=#{layer.widgets.size}\n"
          # Save the rendered buffer (real GPU backends expose a texture; headless backends don't).
          if b && b.responds_to?(:texture)
            path = File.join(dir, "#{layer.id}.png")
            begin
              b.texture.copy_to_image.save_to_file(path)
              s << "  → #{path}\n"
            rescue ex
              s << "  (png save failed: #{ex.message})\n"
            end
          end
          # Every widget's bounds on the layer — the data positions offsets can't reveal.
          layer.widgets.each do |w|
            s << "    #{w.class.name.split("::").last}##{w.id || "?"} bounds=#{w.bounds}\n"
          end
        end
      end
      File.write(File.join(dir, "report.txt"), report)
      report
    end
  end
end
