require "spec"
require "file_utils"
require "xml"

# The wasm32 patch's regression suite (tools/wasm/spec.sh builds it with the patched compiler and runs it under
# Node's WASI). Each block names the patch hunk it guards. Collection stays off: a command-style program always
# has live wasm frames, whose locals the collector cannot see (soak.cr tests collection the way the web flavour
# does it - between ticks).
GC.disable

class SpecError < Exception; end

# struct_return.o is linked by spec.sh
lib LibStructReturn
  struct Triple
    a : Int32
    b : Float64
    c : Int32
  end

  fun make_triple(a : Int32, b : Float64, c : Int32) : Triple
end

private def deep(n : Int32) : Int32
  n == 0 ? raise(SpecError.new("deep")) : deep(n - 1) + 1
end

describe "wasm32 exceptions (codegen: the funclet path + llvm.wasm.throw)" do
  it "rescues by type across frames" do
    caught = begin
      deep(6)
      "none"
    rescue ArgumentError
      "wrong"
    rescue e : SpecError
      e.message
    end
    caught.should eq "deep"
  end

  it "runs ensure on the way out, then the outer rescue" do
    log = [] of String
    begin
      begin
        raise SpecError.new("inner")
      ensure
        log << "ensure"
      end
    rescue e
      log << "outer #{e.message}"
    end
    log.should eq ["ensure", "outer inner"]
  end

  it "rescues a raise from inside a rescue, after its ensure" do
    log = [] of String
    begin
      begin
        raise "a"
      rescue
        raise "b"
      ensure
        log << "ensure"
      end
    rescue e
      log << e.message.not_nil!
    end
    log.should eq ["ensure", "b"]
  end

  it "rescues the standard library's raises" do
    [1][5]?.should be_nil
    (begin; [1][5]; rescue IndexError; -1; end).should eq -1
    (begin; {"a" => 1}["b"]; rescue KeyError; -2; end).should eq -2
    (begin; nil.as(Int32?).not_nil!; rescue NilAssertionError; -3; end).should eq -3
  end

  it "makes expect_raises work (the stub that skipped it is gone)" do
    raised = expect_raises(SpecError, "deep") { deep(2) }
    raised.should be_a(SpecError) # the stub returned nil: a vacuous pass
  end
end

class OtherError < Exception; end

# Run time values the optimizer cannot fold (ARGV is empty under spec/run.mjs): the specs below must reach the
# optimized code they guard, not a constant.
private def runtime_zero : Int32
  ARGV.size
end

# A captured block is a closure; calling it with a union (passed by value, an aggregate) is the shape -O3 turns
# into a direct call with a mismatched type on its closure-data-less branch (compiler.cr's stub step). Not inlined,
# and called from one place: the optimizer propagates the proc's function pointer into it while its closure data
# stays unknown - as in Embrace's RootedTree#dfs_up.
@[NoInline]
private def walk_values(values : Array(Int64?), i : Int32, &block : Int64? -> Nil) : Nil
  return if i >= values.size
  block.call(values[i])
  walk_values(values, i + 1, &block)
end

# The same call inside a rescue body: an invoke.
@[NoInline]
private def walk_values_guarded(values : Array(Int64?), i : Int32, failed : Int32, &block : Int64? -> Nil) : Int32
  return failed if i >= values.size
  begin
    block.call(values[i])
  rescue SpecError
    failed += 1
  end
  walk_values_guarded(values, i + 1, failed, &block)
end

private def first_matching(log : Array(String), n : Int32) : Int32
  [1, 2, 3].each do |i|
    begin
      return i if i == n
    ensure
      log << "ensure #{i}"
    end
  end
  0
end

private def nested(depth : Int32, log : Array(String)) : Int64 | String | Nil
  local : Int64 | String | Nil = depth.even? ? depth.to_i64 : "odd #{depth}"
  begin
    raise SpecError.new("bottom #{depth}") if depth == 0
    nested(depth - 1, log)
  rescue e : SpecError
    log << "rescue #{depth} #{local}"
    raise SpecError.new("from #{depth}") if depth < 2
    local
  ensure
    log << "ensure #{depth} #{local}"
  end
end

describe "wasm32 exceptions and procs, built optimized too (raise.cr @[NoInline], compiler.cr's stub step)" do
  it "re-raises the same exception object, class and message kept" do
    original = SpecError.new("same")
    caught = begin
      begin
        raise original
      rescue e
        raise e
      end
    rescue e
      e
    end
    caught.should be(original)
    caught.message.should eq "same"
  end

  it "runs ensure on return, break and next out of a block" do
    log = [] of String
    first_matching(log, 2 + runtime_zero).should eq 2
    [1, 2, 3].each do |i|
      begin
        next if i == 1 + runtime_zero
        break if i == 2 + runtime_zero
      ensure
        log << "block #{i}"
      end
    end
    log.should eq ["ensure 1", "ensure 2", "block 1", "block 2"]
  end

  it "rescues a raise from a closure called through a stored proc and through yield" do
    base = 10 + runtime_zero
    stored = ->(x : Int32) { raise SpecError.new("proc #{x + base}") if x > 0; x }
    called = begin
      stored.call(1)
    rescue e : SpecError
      e.message
    end
    called.should eq "proc 11"
    yielded = begin
      [1].each { |x| raise SpecError.new("yield #{x + base}") }
      "none"
    rescue e : SpecError
      e.message
    end
    yielded.should eq "yield 11"
  end

  it "rescues by A | B, and runs else only when nothing was raised" do
    picks = [0, 1, 2].map do |i|
      begin
        raise OtherError.new("o") if i == 1 + runtime_zero
        raise SpecError.new("s") if i == 2 + runtime_zero
      rescue e : OtherError | SpecError
        e.class.name
      else
        "else"
      end
    end
    picks.should eq ["else", "OtherError", "SpecError"]
  end

  it "rescues a raise from inside an ensure" do
    caught = begin
      begin
        raise SpecError.new("body")
      ensure
        raise OtherError.new("ensure") if runtime_zero == 0
      end
    rescue e
      e
    end
    caught.should be_a(OtherError)
  end

  it "keeps union locals across three nested rescue and ensure frames" do
    log = [] of String
    result = begin
      nested(3 + runtime_zero, log)
    rescue e
      e.message
    end
    result.should eq 2_i64
    log.should eq ["rescue 0 0", "ensure 0 0", "rescue 1 odd 1", "ensure 1 odd 1", "rescue 2 2", "ensure 2 2",
                   "ensure 3 odd 3"]
  end

  it "calls a captured closure with a union argument" do
    sum = runtime_zero.to_i64
    walk_values([1_i64, nil, 5_i64], 0) { |v| sum += v || 10_i64 }
    sum.should eq 16
  end

  it "calls a captured closure with a union argument inside a rescue body" do
    seen = [] of Int64
    failed = walk_values_guarded([1_i64, nil, 5_i64], 0, 0) do |v|
      raise SpecError.new("nil") unless v
      seen << v + runtime_zero
    end
    {failed, seen}.should eq({1, [1_i64, 5_i64]})
  end
end

# Layout numbers (sizeof & co) typed BEFORE the struct that includes a generic module exists: a module-typed
# field was then laid out as a pointer, and the number - fixed while typing - stayed too small. Each example's types
# are its own, so nothing earlier in this file creates the including struct first; each number typed early is
# typed inside a proc that comes before the struct's first `new`.
module LayoutIfaceA(T)
end

struct LayoutImplA(T)
  include LayoutIfaceA(T)

  def initialize(@a : Int64, @b : Int64)
  end

  getter b
end

class LayoutCellA
  def initialize(@iface : LayoutIfaceA(Int32), @tail : Int32)
  end

  getter iface, tail
end

module LayoutIfaceB(T)
end

struct LayoutImplB(T) # all Int32: aligned as a pointer is on wasm32, so the early alignof below is right
  include LayoutIfaceB(T)

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

struct LayoutHolderB
  def initialize(@iface : LayoutIfaceB(Int32), @tail : Int32)
  end
end

struct LayoutHolderS
  def initialize(@iface : LayoutIfaceA(Int16), @tail : Int32)
  end
end

module LayoutIfaceC(T)
end

struct LayoutImplC(T)
  include LayoutIfaceC(T)

  def initialize(@a : Int64)
  end
end

struct LayoutHolderC
  def initialize(@iface : LayoutIfaceC(Int32))
  end
end

class LayoutCellC
  def initialize(@iface : LayoutIfaceC(Int32))
  end
end

struct LayoutHolderD
  def initialize(@iface : LayoutIfaceA(Int8), @tail : Int32)
  end
end

class LayoutCellD
  def initialize(@iface : LayoutIfaceA(UInt8), @tail : Int32)
  end
end

abstract struct LayoutAbstractE
end

struct LayoutSubE(T) < LayoutAbstractE
  def initialize(@a : Int64, @b : Int64)
  end
end

class LayoutCellE
  def initialize(@value : LayoutAbstractE, @tail : Int32)
  end

  getter tail
end

class LayoutCellT
  def initialize(@pair : {LayoutIfaceA(UInt16), Int32}, @tail : Int32)
  end

  getter tail
end

class LayoutCellF
  def initialize(@iface : LayoutIfaceA(UInt32), @tail : Int32)
  end
end

struct LayoutHolderF
  def initialize(@iface : LayoutIfaceA(UInt32), @tail : Int32)
  end
end

# A constant's number: folded by cleanup into a static literal (spec.sh checks the IR - no lazy initializer)
LAYOUT_SPEC_CONSTANT = sizeof(LayoutHolderF)

# Where a field ends inside a struct value or an object - computed by the generated code, not by a fold
private def field_end(base, field : Pointer(Int32)) : UInt64
  field.address - base.address + sizeof(Int32)
end

describe "layout numbers typed before a generic module's struct exists (main_visitor.cr, cleanup_transformer.cr)" do
  it "dup copies the whole object (instance_sizeof)" do
    copy = ->(cell : LayoutCellA) { cell.dup }
    cell = LayoutCellA.new(LayoutImplA(Int32).new(7, 8), 42)
    copied = copy.call(cell)
    copied.tail.should eq 42
    copied.iface.as(LayoutImplA(Int32)).b.should eq 8
    field_end(cell.as(Void*), pointerof(cell.@tail)).should be <= instance_sizeof(LayoutCellA)
  end

  it "sizes a struct holding the module (sizeof), in code and in a type argument after an early alignof" do
    early_size = ->{ sizeof(LayoutHolderS) }
    early_align = ->{ StaticArray(UInt8, alignof(LayoutHolderB)).new(0_u8).size }
    holder_s = LayoutHolderS.new(LayoutImplA(Int16).new(1, 2), 3)
    holder = LayoutHolderB.new(LayoutImplB(Int32).new(1, 2, 3), 4)
    early_size.call.should be >= field_end(pointerof(holder_s), pointerof(holder_s.@tail))
    early_align.call.should eq alignof(LayoutHolderB)
    StaticArray(UInt8, sizeof(LayoutHolderB)).new(0_u8).size.should be >= field_end(pointerof(holder), pointerof(holder.@tail))
  end

  it "aligns by the struct inside (alignof, instance_alignof)" do
    early = ->{ {alignof(LayoutHolderC), instance_alignof(LayoutCellC)} }
    LayoutHolderC.new(LayoutImplC(Int32).new(1))
    LayoutCellC.new(LayoutImplC(Int32).new(1))
    early.call.should eq({alignof(Int64), alignof(Int64)}) # holds an Int64 by value, nothing aligned wider: as one
  end

  it "places the field after the module (offsetof: struct, class, tuple)" do
    early = ->{ {offsetof(LayoutHolderD, @tail), offsetof(LayoutCellD, @tail), offsetof({LayoutIfaceA(Int8), Int32}, 1)} }
    holder = LayoutHolderD.new(LayoutImplA(Int8).new(1, 2), 3)
    cell = LayoutCellD.new(LayoutImplA(UInt8).new(1, 2), 3)
    pair = {LayoutImplA(Int8).new(1, 2).as(LayoutIfaceA(Int8)), 42}
    struct_offset, class_offset, tuple_offset = early.call
    struct_offset.should eq pointerof(holder.@tail).address - pointerof(holder).address
    class_offset.should eq pointerof(cell.@tail).address - cell.as(Void*).address
    (pointerof(pair).as(UInt8*) + tuple_offset).as(Int32*).value.should eq 42 # the tuple's element 1 is there
  end

  it "copies an object whose field is an abstract struct or a tuple holding the module" do
    copy_e = ->(cell : LayoutCellE) { cell.dup }
    copy_t = ->(cell : LayoutCellT) { cell.dup }
    copy_e.call(LayoutCellE.new(LayoutSubE(Int32).new(1, 2), 42)).tail.should eq 42
    copy_t.call(LayoutCellT.new({LayoutImplA(UInt16).new(1, 2), 5}, 42)).tail.should eq 42
  end

  it "still gives type arguments and constants their number" do
    holder = LayoutHolderF.new(LayoutImplA(UInt32).new(1, 2), 3)
    cell = LayoutCellF.new(LayoutImplA(UInt32).new(1, 2), 3)
    bytes = uninitialized UInt8[sizeof(LayoutHolderF)]
    bytes.size.should be >= field_end(pointerof(holder), pointerof(holder.@tail))
    StaticArray(UInt8, instance_sizeof(LayoutCellF)).new(0_u8).size.should be >= field_end(cell.as(Void*), pointerof(cell.@tail))
    LAYOUT_SPEC_CONSTANT.should eq sizeof(LayoutHolderF)
  end
end

describe "wasm32 C ABI: a struct returned by value (abi/wasm32.cr: StructRet)" do
  it "reads every field of a struct a C function returned" do
    t = LibStructReturn.make_triple(3, 1.25, 7)
    {t.a, t.b, t.c}.should eq({6, 2.5, 14})
  end
end

describe "WASI file system" do
  it "opens files (event_loop/wasi.cr #open) and deletes them (system/wasi/file.cr)" do
    File.write("/tmp/spec-file", "x")
    File.read("/tmp/spec-file").should eq "x"
    File.delete("/tmp/spec-file")
    File.exists?("/tmp/spec-file").should be_false
  end

  it "lists an empty directory as empty (system/wasi/dir.cr), so rm_r of a nested tree ends" do
    Dir.mkdir("/tmp/spec-tree")
    Dir.mkdir("/tmp/spec-tree/empty")
    File.write("/tmp/spec-tree/.hidden", "y")
    Dir.children("/tmp/spec-tree/empty").should be_empty
    FileUtils.rm_r("/tmp/spec-tree")
    Dir.exists?("/tmp/spec-tree").should be_false
  end
end

describe "the toolchain's libraries, not the build host's (tools/wasm/pkg-config)" do
  it "compiled the GC binding for the toolchain's Boehm" do
    LibGC::VERSION.should eq "8.2.8"
  end

  it "compiled the XML binding for the toolchain's libxml2, and it parses" do
    LibXML::VERSION.should eq "2.13.8"
    XML.parse("<a>hi</a>").first_element_child.not_nil!.content.should eq "hi"
  end
end
