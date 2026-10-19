# Must NOT compile (tools/wasm/spec.sh): a type argument needs instance_sizeof(GuardCell) while the program is typed,
# before GuardImpl(Int32) exists - the module-typed field is laid out as a pointer then, so the number is too small,
# and the compiler's check of every folded number against the final layout must stop the build, naming it.
module GuardIface(T)
end

struct GuardImpl(T)
  include GuardIface(T)

  def initialize(@a : Int64, @b : Int64)
  end
end

class GuardCell
  def initialize(@iface : GuardIface(Int32), @tail : Int32)
  end
end

early = ->{ StaticArray(UInt8, instance_sizeof(GuardCell)).new(0_u8).size }
GuardCell.new(GuardImpl(Int32).new(1, 2), 3)
puts early.call
