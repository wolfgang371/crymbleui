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
