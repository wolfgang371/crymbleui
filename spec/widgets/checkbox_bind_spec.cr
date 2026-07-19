require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/checkbox"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# Two-way Source binding: a caller-owned Source(Bool) handed to a Checkbox via bind: becomes its
# `checked` cell — a click toggles the Source directly (no callback, no rebuild), and every checkbox
# reading the same Source updates. Mirrors text_input_bind_spec. (`toggle:` is the separate plain-state
# sugar; `bind:` is Source-adoption.)

private class OneBindApp < CrymbleUI::App
  getter src : CrymbleUI::Source(Bool)

  def initialize(@src : CrymbleUI::Source(Bool))
    super()
  end

  def build : CrymbleUI::Widget
    window("Bind", 400, 300) do
      checkbox("a", bind: @src, id: "a")
    end
  end
end

private class TwoBindApp < CrymbleUI::App
  getter src : CrymbleUI::Source(Bool)

  def initialize(@src : CrymbleUI::Source(Bool))
    super()
  end

  def build : CrymbleUI::Widget
    window("Bind2", 400, 300) do
      vstack do
        checkbox("a", bind: @src, id: "a")
        checkbox("b", bind: @src, id: "b")
      end
    end
  end
end

describe "Checkbox two-way Source binding (bind:)" do
  it "toggles the bound Source on click with no callback and no rebuild" do
    src = CrymbleUI::Source(Bool).new(false)
    cb = CrymbleUI::Checkbox.new("x", bind: src) # no on_click
    CrymbleUI::App.reset_rebuild_count
    cb.trigger_click

    src.get.should be_true                    # write-back through the shared cell
    CrymbleUI::App.rebuild_count.should eq(0) # no full rebuild
  end

  it "shares the cell — a second checkbox bound to the same Source reflects the toggle and re-renders" do
    src = CrymbleUI::Source(Bool).new(false)
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TwoBindApp.new(src)
    app.build_tree
    renderer.settle_rendering(app) # both render → both pull-nodes subscribe to `src`

    a = app.find("a").not_nil!.as(CrymbleUI::Checkbox)
    b = app.find("b").not_nil!.as(CrymbleUI::Checkbox)
    before = b.primitives_version

    a.trigger_click # src.set(true) — an external write from b's point of view

    b.checked.should be_true                # shared cell: b reads the same Source
    b.primitives_version.should be > before # b re-rendered (its node was a dependent of `src`)
  end

  it "survives a structural rebuild — the reconciled checkbox keeps the value and still writes the Source" do
    src = CrymbleUI::Source(Bool).new(false)
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = OneBindApp.new(src)
    app.build_tree
    renderer.settle_rendering(app)

    app.find("a").not_nil!.as(CrymbleUI::Checkbox).trigger_click
    src.get.should be_true

    app.rebuild # build() re-runs → NEW Checkbox adopts the SAME src

    reconciled = app.find("a").not_nil!.as(CrymbleUI::Checkbox)
    reconciled.checked.should be_true # value persisted (adopted, not reseeded to false)
    reconciled.trigger_click          # and the new instance still writes back
    src.get.should be_false
  end

  it "rejects bind: together with an explicit checked: or a tristate check_state: (boolean-only)" do
    src = CrymbleUI::Source(Bool).new(false)
    expect_raises(ArgumentError, /boolean-only/) do
      CrymbleUI::Checkbox.new("x", checked: true, bind: src)
    end
    expect_raises(ArgumentError, /boolean-only/) do
      CrymbleUI::Checkbox.new("x", check_state: CrymbleUI::CheckState::Indeterminate, bind: src)
    end
  end
end
