# The web flavour's garbage-collection regime, soaked: collection only BETWEEN ticks (the page calls soak_gc after
# soak_tick, when no wasm frame - and so no pointer held only in a wasm local - is live). Each tick makes garbage,
# keeps a sliding window of live rows (Array#shift: an interior pointer into the buffer - the reason the toolchain
# builds Boehm with ALL_INTERIOR_POINTERS) and objects with finalizers. soak_check recomputes every kept row from
# the tick number alone.
class Store
  class_property rows = [] of Array(String)
  class_property finalized = 0
end

class Finalized
  def finalize
    Store.finalized += 1
  end
end

fun soak_init : Int32
  GC.init
  Crystal.init_runtime
  GC.disable
  LibCrystalMain.__crystal_main(0, Pointer(Pointer(UInt8)).null)
  0
end

fun soak_tick(t : Int32) : Int32
  garbage = Array(String).new(5_000) { |i| "cell #{t}/#{i}" }
  10.times { Finalized.new }
  Store.rows << ["tick #{t}", garbage[t % 5_000]]
  Store.rows.shift if Store.rows.size > 100
  garbage.size
end

fun soak_gc : Int32
  GC.enable
  GC.collect
  GC.disable
  0
end

# 0 when every kept row reads what was written, else 1000000 + the first bad tick.
fun soak_check(last : Int32) : Int32
  Store.rows.each_with_index do |row, k|
    t = last - Store.rows.size + 1 + k
    return 1_000_000 + t unless row == ["tick #{t}", "cell #{t}/#{t % 5_000}"]
  end
  0
end

fun soak_finalized : Int32
  Store.finalized
end

fun soak_heap_kb : Int32
  (GC.stats.heap_size // 1024).to_i
end
