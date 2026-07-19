require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# Two-way Source binding: a caller-owned Source(Int32) handed to a ComboBox via bind: becomes its
# selected-INDEX cell — a pick writes the Source directly (no callback, no rebuild), and every combo
# reading the same Source updates. Index-only, non-editable (editable free-text can't round-trip an
# Int32). Mirrors checkbox_bind_spec / text_input_bind_spec.

private ITEMS = ["Alpha", "Bravo", "Charlie"]

private class OneBindApp < CrymbleUI::App
  getter src : CrymbleUI::Source(Int32)

  def initialize(@src : CrymbleUI::Source(Int32))
    super()
  end

  def build : CrymbleUI::Widget
    window("Bind", 400, 300) do
      combo_box(items: ITEMS, bind: @src, id: "a")
    end
  end
end

private class TwoBindApp < CrymbleUI::App
  getter src : CrymbleUI::Source(Int32)

  def initialize(@src : CrymbleUI::Source(Int32))
    super()
  end

  def build : CrymbleUI::Widget
    window("Bind2", 400, 300) do
      vstack do
        combo_box(items: ITEMS, bind: @src, id: "a")
        combo_box(items: ITEMS, bind: @src, id: "b")
      end
    end
  end
end

describe "ComboBox two-way Source binding (bind:)" do
  it "writes the picked index back to the bound Source with no callback and no rebuild" do
    src = CrymbleUI::Source(Int32).new(0)
    combo = CrymbleUI::ComboBox.new(ITEMS, bind: src)
    CrymbleUI::App.reset_rebuild_count
    combo.select_and_close(2, ITEMS[2])

    src.get.should eq(2)                      # write-back through the shared cell
    CrymbleUI::App.rebuild_count.should eq(0) # no full rebuild
  end

  it "shares the cell — a second combo bound to the same Source reflects the pick and re-renders" do
    src = CrymbleUI::Source(Int32).new(0)
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TwoBindApp.new(src)
    app.build_tree
    renderer.settle_rendering(app) # both render → both pull-nodes subscribe to `src`

    a = app.find("a").not_nil!.as(CrymbleUI::ComboBox)
    b = app.find("b").not_nil!.as(CrymbleUI::ComboBox)
    before = b.primitives_version

    a.select_and_close(1, ITEMS[1]) # src.set(1) — an external write from b's point of view

    b.selected_index.should eq(1)           # shared cell: b reads the same Source
    b.primitives_version.should be > before # b re-rendered (its node was a dependent of `src`)
  end

  it "survives a structural rebuild — the reconciled combo keeps the index and still writes the Source" do
    src = CrymbleUI::Source(Int32).new(0)
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = OneBindApp.new(src)
    app.build_tree
    renderer.settle_rendering(app)

    app.find("a").not_nil!.as(CrymbleUI::ComboBox).select_and_close(2, ITEMS[2])
    src.get.should eq(2)

    app.rebuild # build() re-runs → NEW ComboBox adopts the SAME src (reconcile:true carry is a no-op)

    reconciled = app.find("a").not_nil!.as(CrymbleUI::ComboBox)
    reconciled.selected_index.should eq(2) # index persisted (adopted, not reseeded to 0)
    reconciled.select_and_close(1, ITEMS[1])
    src.get.should eq(1) # the new instance still writes the same Source
  end

  it "still fires on_select on a bound pick (side-effect + write-back both happen)" do
    src = CrymbleUI::Source(Int32).new(0)
    picks = [] of Int32
    combo = CrymbleUI::ComboBox.new(ITEMS, on_select: ->(i : Int32, _v : String) { picks << i; nil }, bind: src)
    combo.select_and_close(1, ITEMS[1])

    src.get.should eq(1) # write-back
    picks.should eq([1]) # side-effect callback still fired
  end

  it "renders safely when the bound Source holds an out-of-range index (no IndexError, blank display)" do
    src = CrymbleUI::Source(Int32).new(99) # out of range for a 3-item combo (adopted AS-IS, not clamped)
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = OneBindApp.new(src)
    app.build_tree
    renderer.settle_rendering(app) # to_primitives runs; must not raise

    app.find("a").not_nil!.as(CrymbleUI::ComboBox).selected_value.should be_nil # out-of-range → blank
  end

  it "rejects bind: together with editable: or a non-default selected: (index-only)" do
    src = CrymbleUI::Source(Int32).new(0)
    expect_raises(ArgumentError, /index-only/) do
      CrymbleUI::ComboBox.new(ITEMS, editable: true, bind: src)
    end
    expect_raises(ArgumentError, /index-only/) do
      CrymbleUI::ComboBox.new(ITEMS, selected: 1, bind: src)
    end
  end
end
