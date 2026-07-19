require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/text_input"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# Two-way Source binding: a caller-owned Source(String) handed to a TextInput via `bind:` becomes
# the widget's value cell — edits write straight back to the Source (no callback, no rebuild), and
# every widget that reads the Source re-renders. The app owns the Source and re-passes it each build,
# so the binding survives reconcile with no widget-side carry.

# One bound input driven by an app-owned Source (for reconcile + real-tree tests).
private class OneBindApp < CrymbleUI::App
  getter src : CrymbleUI::Source(String)

  def initialize(@src : CrymbleUI::Source(String))
    super()
  end

  def build : CrymbleUI::Widget
    window("Bind", 400, 300) do
      text_input(bind: @src, id: "a")
    end
  end
end

# Two inputs bound to the SAME Source (for the shared-cell test).
private class TwoBindApp < CrymbleUI::App
  getter src : CrymbleUI::Source(String)

  def initialize(@src : CrymbleUI::Source(String))
    super()
  end

  def build : CrymbleUI::Widget
    window("Bind2", 400, 300) do
      vstack do
        text_input(bind: @src, id: "a")
        text_input(bind: @src, id: "b")
      end
    end
  end
end

describe "TextInput two-way Source binding (bind:)" do
  it "writes edits back to the bound Source with no callback and no rebuild" do
    src = CrymbleUI::Source(String).new("")
    input = CrymbleUI::TextInput.new(bind: src) # FullEdit, no on_change
    input.on_focus
    CrymbleUI::App.reset_rebuild_count
    input.on_text_input('X')

    src.get.should eq("X")                  # write-back through the shared cell
    CrymbleUI::App.rebuild_count.should eq(0) # regression guard: no full rebuild
  end

  it "shares the cell — a second widget bound to the same Source reflects the edit and re-renders" do
    src = CrymbleUI::Source(String).new("")
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TwoBindApp.new(src)
    app.build_tree
    renderer.settle_rendering(app) # both inputs render → both pull-nodes subscribe to `src`

    a = app.find("a").not_nil!.as(CrymbleUI::TextInput)
    b = app.find("b").not_nil!.as(CrymbleUI::TextInput)
    before = b.primitives_version

    a.on_focus
    a.on_text_input('X') # src.set("X") — an EXTERNAL write from b's point of view

    b.value.should eq("X")                     # shared cell: b reads the same Source
    b.primitives_version.should be > before    # b re-rendered (its node was a dependent of `src`)
  end

  it "survives a structural rebuild — the reconciled input keeps the value and still writes to the same Source" do
    src = CrymbleUI::Source(String).new("")
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = OneBindApp.new(src)
    app.build_tree
    renderer.settle_rendering(app)

    app.find("a").not_nil!.as(CrymbleUI::TextInput).tap(&.on_focus).on_text_input('X')
    src.get.should eq("X")

    app.rebuild # build() re-runs → NEW TextInput adopts the SAME src

    reconciled = app.find("a").not_nil!.as(CrymbleUI::TextInput)
    reconciled.value.should eq("X")            # value persisted (adopted, not reseeded to "")
    reconciled.on_text_input('Y')              # and the new instance still writes back
    src.get.should eq("XY")
  end

  it "writes back on a QuickEntry replace (first keystroke replaces, through the shared Source)" do
    src = CrymbleUI::Source(String).new("old")
    input = CrymbleUI::TextInput.new(bind: src, mode: CrymbleUI::TextInputMode::QuickEntry)
    input.on_focus         # arms pending_replace
    input.on_text_input('N') # QuickEntry: first keystroke REPLACES

    src.get.should eq("N")
  end

  it "still fires on_event on a bound input (callback and write-back both happen)" do
    src = CrymbleUI::Source(String).new("")
    changes = [] of String
    input = CrymbleUI::TextInput.new(
      bind: src,
      on_event: ->(v : String, ev : CrymbleUI::TextInputEvent) { changes << v if ev.change?; nil }
    )
    input.on_focus
    input.on_text_input('Z')

    src.get.should eq("Z")     # write-back
    changes.should eq(["Z"])   # side-effect callback still fired
  end

  it "survives an external shrink of the bound Source — no IndexError, cursor clamps on read" do
    src = CrymbleUI::Source(String).new("hello")
    input = CrymbleUI::TextInput.new(bind: src) # FullEdit; cursor initialised at end (5)
    input.on_focus
    src.set("hi") # external shrink to size 2 — the widget's cursor (5) is now stale

    input.on_text_input('X') # must NOT raise; cursor clamps to 2 → "hi" + "X"

    src.get.should eq("hiX")
  end

  it "rejects bind: together with a non-empty value: (mutually exclusive)" do
    src = CrymbleUI::Source(String).new("x")
    expect_raises(ArgumentError, /mutually exclusive/) do
      CrymbleUI::TextInput.new(value: "seed", bind: src)
    end
  end
end
