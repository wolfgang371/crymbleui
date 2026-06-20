require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/multi_combo_box"
require "../../src/widgets/window"

# Visual-state regression for MultiComboBox (user-reported 2026-06-20: the
# checkboxes don't update AND use a wrong visual). T-030 makes the per-item check
# PULL-based and renders the REAL tristate Checkbox (box + mark), not a text glyph.
#
# These assert through a real render on the RESOLVED CheckState (the same pull the
# renderer reads) AND on the rendered PRIMITIVES (a Checked gutter draws a checkmark
# = 2 DrawLines; Unchecked draws box-only = 0; the header's partial = 1 dash line) —
# so they catch both a stale capture and a wrong/empty visual.

class MCVisualApp < CrymbleUI::App
  state selected : Set(Int32) = Set{0}

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      combo_box(items: ["Apple", "Banana", "Cherry"], selected: @selected, id: "mc") do |new_set|
        self.selected = new_set
      end
    end
  end
end

private def open_mc(app, renderer)
  mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
  abs = mc.absolute_bounds
  pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
  app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
end

private def click_gutter(app, renderer, mc, idx)
  item = mc.current_popup.not_nil!.item_widgets[idx]
  b = item.absolute_bounds
  pos = CrymbleUI::Vec2.new(b.x + 6.0, b.y + b.height / 2)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
end

# The state the renderer will read — resolved through the SAME pull closure.
private def state_of(mc, idx) : CrymbleUI::CheckState
  mc.current_popup.not_nil!.item_widgets[idx].check_state_fn.not_nil!.call
end

# The RENDERED truth: a Checked gutter draws a checkmark (2 DrawLines), Unchecked
# draws box-only (0), Indeterminate draws a dash (1). Counting DrawLines in the
# freshly computed primitives is what the user actually sees.
private def gutter_lines(item) : Int32
  item.to_primitives(item.bounds).count(&.is_a?(CrymbleUI::DrawLine))
end

describe "MultiComboBox checkbox visual state" do
  it "the item gutter reflects @selected right after a toggle (resolved + rendered)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MCVisualApp.new
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_mc(app, renderer)
    pop = mc.current_popup.not_nil!
    state_of(mc, 0).should eq(CrymbleUI::CheckState::Checked) # preselected
    state_of(mc, 1).should eq(CrymbleUI::CheckState::Unchecked)
    gutter_lines(pop.item_widgets[0]).should eq(2) # rendered checkmark
    gutter_lines(pop.item_widgets[1]).should eq(0) # rendered box-only

    click_gutter(app, renderer, mc, 1)
    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{0, 1})
    state_of(mc, 1).should eq(CrymbleUI::CheckState::Checked)
    gutter_lines(mc.current_popup.not_nil!.item_widgets[1]).should eq(2) # now renders a check
  end

  it "the item gutter still reflects @selected after a parent rebuild" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MCVisualApp.new
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_mc(app, renderer)
    click_gutter(app, renderer, mc, 1)
    app.rebuild # embrace's request_rebuild path
    renderer.render_frame(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.popup_open?.should be_true # popup survives the rebuild
    mc.current_popup.should_not be_nil
    state_of(mc, 0).should eq(CrymbleUI::CheckState::Checked)
    state_of(mc, 1).should eq(CrymbleUI::CheckState::Checked) # NOT stale after the rebuild
    gutter_lines(mc.current_popup.not_nil!.item_widgets[1]).should eq(2)
  end

  it "the carried-over popup refreshes when @selected changes via a rebuild" do
    # The demo/embrace bug: a sync rebuild fires while the popup is open, and the
    # carried-over popup must reflect the NEW @selected (the old push assumed it was
    # already current → frozen checkboxes). Now the items pull the carried Source.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MCVisualApp.new # selected {0}
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_mc(app, renderer)
    state_of(mc, 0).should eq(CrymbleUI::CheckState::Checked)

    # Change the selection WITHOUT touching the popup gutter, then rebuild.
    app.selected = Set{1}
    app.rebuild
    renderer.render_frame(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.current_popup.should_not be_nil
    state_of(mc, 0).should eq(CrymbleUI::CheckState::Unchecked) # 0 no longer selected
    state_of(mc, 1).should eq(CrymbleUI::CheckState::Checked)   # 1 now selected
    gutter_lines(mc.current_popup.not_nil!.item_widgets[0]).should eq(0)
    gutter_lines(mc.current_popup.not_nil!.item_widgets[1]).should eq(2)
  end

  it "an item AUTO-CAPTURES the selection (re-renders on .set, no manual mark)" do
    # Proves the pull edge exists: after the captured Source changes, the item's node
    # is stale with NO mark_needs_render — auto-capture, not a push.
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MCVisualApp.new # {0}
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_mc(app, renderer)
    renderer.render_frame(app) # ensure the items have captured @selection
    item0 = mc.current_popup.not_nil!.item_widgets[0]

    mc.selected = Set{2}               # Source-backed setter — NO mark_needs_render
    item0.needs_render?.should be_true # the captured node was dirtied by the .set
  end

  it "the (select all) header shows a PARTIAL (Indeterminate) state when some are selected" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MCVisualApp.new # Set{0} of 3 → partial
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_mc(app, renderer)
    hdr = mc.current_popup.not_nil!.header_item.not_nil!
    hdr.check_state_fn.not_nil!.call.should eq(CrymbleUI::CheckState::Indeterminate)
    gutter_lines(hdr).should eq(1) # the indeterminate dash (not 0 = empty, not 2 = full check)
  end
end
