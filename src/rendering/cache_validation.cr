{% if flag?(:cache_validation) %}
require "../core/types"
require "./render_backend"

module CrymbleUI
  module CacheValidation
    enum CacheLevel
      ImmediateMode  # Phase 1: painter's algorithm via to_primitives() vs cached buffer
      BlitShift      # Phase 1: overlap copy during recenter
      DirtyTracking  # Phase 2: selective render vs full render
      WidgetFastPath # Phase 2: skip re-render for clean widgets
      PrimitiveCache # Phase 3: cached DrawPrimitive arrays
      BlitPlan       # Phase 3: pre-computed sticky positions
      LayoutCache    # Phase 3: skip layout on same constraints
    end

    record Failure,
      cache_level : CacheLevel,
      layer_id : String,
      frame : Int32,
      mismatch_count : Int32,
      total_pixels : Int32,
      first_mismatch : {Int32, Int32, UInt32, UInt32} # x, y, cached_rgba, uncached_rgba

    class ValidationError < Exception
    end

    @@enabled = Set(CacheLevel).new
    @@failures = [] of Failure
    @@frame_counter : Int32 = 0
    @@tolerance : Int32 = 2 # per-channel pixel tolerance

    def self.enable(level : CacheLevel)
      @@enabled.add(level)
    end

    def self.enable_all
      CacheLevel.each { |l| @@enabled.add(l) }
    end

    def self.disable(level : CacheLevel)
      @@enabled.delete(level)
    end

    def self.disable_all
      @@enabled.clear
    end

    def self.enabled?(level : CacheLevel) : Bool
      @@enabled.includes?(level)
    end

    def self.failures : Array(Failure)
      @@failures
    end

    def self.clear_failures!
      @@failures.clear
      @@frame_counter = 0
    end

    def self.increment_frame!
      @@frame_counter += 1
    end

    def self.frame_counter : Int32
      @@frame_counter
    end

    def self.tolerance : Int32
      @@tolerance
    end

    def self.tolerance=(t : Int32)
      @@tolerance = t
    end

    # Raise with details if any failures recorded
    def self.assert_no_failures!
      return if @@failures.empty?

      msg = String.build do |s|
        s << "Cache validation found #{@@failures.size} pixel failure(s):\n"
        @@failures.each_with_index do |f, i|
          s << "  [#{i + 1}] #{f.cache_level} layer=#{f.layer_id} frame=#{f.frame}"
          s << " mismatches=#{f.mismatch_count}/#{f.total_pixels}"
          x, y, cached, uncached = f.first_mismatch
          s << " first_at=(#{x},#{y}) cached=0x#{cached.to_s(16)} uncached=0x#{uncached.to_s(16)}\n"
        end
      end
      raise ValidationError.new(msg)
    end

    # Record a failure
    def self.record_failure(cache_level : CacheLevel, layer_id : String,
                            mismatch_count : Int32, total_pixels : Int32,
                            first_mismatch : {Int32, Int32, UInt32, UInt32})
      @@failures << Failure.new(
        cache_level: cache_level,
        layer_id: layer_id,
        frame: @@frame_counter,
        mismatch_count: mismatch_count,
        total_pixels: total_pixels,
        first_mismatch: first_mismatch
      )
    end

    # Save a side-by-side diff PPM: cached | fresh | diff (red = mismatch)
    # Crops to bounding box of all mismatches + margin for context.
    def self.save_diff_ppm(cached : Array(UInt32), fresh : Array(UInt32),
                            width : Int32, height : Int32, path : String)
      # Find bounding box of all mismatches
      min_x = width
      max_x = 0
      min_y = height
      max_y = 0
      total = width * height

      total.times do |i|
        pa = i < cached.size ? cached[i] : 0_u32
        pb = i < fresh.size ? fresh[i] : 0_u32
        unless pixels_match?(pa, pb)
          x = i % width
          y = i // width
          min_x = x if x < min_x
          max_x = x if x > max_x
          min_y = y if y < min_y
          max_y = y if y > max_y
        end
      end

      return if min_x > max_x # no mismatches

      # Add margin (50px) for context
      margin = 50
      min_x = [min_x - margin, 0].max
      max_x = [max_x + margin, width - 1].min
      min_y = [min_y - margin, 0].max
      max_y = [max_y + margin, height - 1].min

      crop_w = max_x - min_x + 1
      crop_h = max_y - min_y + 1
      # 3 panels side-by-side: cached | fresh | diff
      out_w = crop_w * 3 + 4 # 2px separator between panels

      File.open(path, "w") do |f|
        f.puts "P3"
        f.puts "#{out_w} #{crop_h}"
        f.puts "255"
        crop_h.times do |cy|
          sy = min_y + cy
          # Panel 1: cached
          crop_w.times do |cx|
            sx = min_x + cx
            i = sy * width + sx
            px = i < cached.size ? cached[i] : 0_u32
            f.print "#{(px >> 24) & 0xFF} #{(px >> 16) & 0xFF} #{(px >> 8) & 0xFF} "
          end
          # Separator (white)
          f.print "255 255 255 255 255 255 "
          # Panel 2: fresh
          crop_w.times do |cx|
            sx = min_x + cx
            i = sy * width + sx
            px = i < fresh.size ? fresh[i] : 0_u32
            f.print "#{(px >> 24) & 0xFF} #{(px >> 16) & 0xFF} #{(px >> 8) & 0xFF} "
          end
          # Separator (white)
          f.print "255 255 255 255 255 255 "
          # Panel 3: diff (matching=dark gray, mismatch=red)
          crop_w.times do |cx|
            sx = min_x + cx
            i = sy * width + sx
            pa = i < cached.size ? cached[i] : 0_u32
            pb = i < fresh.size ? fresh[i] : 0_u32
            if pixels_match?(pa, pb)
              # Dim version of cached for context
              r = ((pa >> 24) & 0xFF) // 3
              g = ((pa >> 16) & 0xFF) // 3
              b = ((pa >> 8) & 0xFF) // 3
              f.print "#{r} #{g} #{b} "
            else
              f.print "255 0 0 "
            end
          end
          f.puts
        end
      end
    end

    # Compare two pixel arrays (UInt32 packed RGBA).
    # Returns {mismatch_count, total_pixels, first_mismatch_or_nil}
    def self.compare_pixels(pixels_a : Array(UInt32), pixels_b : Array(UInt32),
                            width : Int32, height : Int32) : {Int32, Int32, {Int32, Int32, UInt32, UInt32}?}
      total = width * height
      mismatch_count = 0
      first_mismatch : {Int32, Int32, UInt32, UInt32}? = nil

      total.times do |i|
        pa = i < pixels_a.size ? pixels_a[i] : 0_u32
        pb = i < pixels_b.size ? pixels_b[i] : 0_u32

        unless pixels_match?(pa, pb)
          mismatch_count += 1
          if first_mismatch.nil?
            x = i % width
            y = i // width
            first_mismatch = {x, y, pa, pb}
          end
        end
      end

      {mismatch_count, total, first_mismatch}
    end

    # Compare two pixels with per-channel tolerance
    private def self.pixels_match?(a : UInt32, b : UInt32) : Bool
      return true if a == b

      # Unpack RGBA channels
      ar = (a >> 24) & 0xFF
      ag = (a >> 16) & 0xFF
      ab = (a >> 8) & 0xFF
      aa = a & 0xFF

      br = (b >> 24) & 0xFF
      bg = (b >> 16) & 0xFF
      bb = (b >> 8) & 0xFF
      ba = b & 0xFF

      tol = @@tolerance.to_u32
      (ar.to_i - br.to_i).abs <= tol &&
        (ag.to_i - bg.to_i).abs <= tol &&
        (ab.to_i - bb.to_i).abs <= tol &&
        (aa.to_i - ba.to_i).abs <= tol
    end
  end
end
{% end %}
