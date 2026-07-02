require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/multi_combo_box"
require "../../src/widgets/window"

# follow-up (user 2026-06-20): clicking a row's BODY (the text, not the ✓ gutter)
# must SELECT ONLY THAT ITEM and close — like a regular single-select ComboBox —
# regardless of the prior selection. It must NOT toggle (toggle = depends on prior
# membership, which is the gutter's job). This exhaustively checks every prior state.

class SelOneApp < CrymbleUI::App
  state selected : Set(Int32) = Set(Int32).new
  ITEMS = ["Apple", "Banana", "Cherry", "Date"]

  def build : CrymbleUI::Widget
    window("Test", 400, 400) do
      combo_box(items: ITEMS, selected: selected, id: "mc") do |new_set|
        self.selected = new_set
      end
    end
  end
end

# Regression for the real embrace bug (History branch selector, 2026-06-20): an app whose
# "effective" selection RE-SEEDS a default when the stored set is empty. The OLD per-item
# (index, now_on) callback could not select-one against it — removing the old item emptied
# the set, the app re-seeded the default, and the subsequent add produced {default, clicked}
# ("2 branches" instead of "1"). The full-set callback hands the app the final {clicked}
# atomically, so the empty intermediate state never occurs.
class DefaultSeedingApp < CrymbleUI::App
  DEFAULT = 0
  state stored : Set(Int32) = Set(Int32).new # empty ⇒ "use the default"
  ITEMS = ["Apple", "Banana", "Cherry"]

  def effective : Set(Int32)
    stored.empty? ? Set{DEFAULT} : stored
  end

  def build : CrymbleUI::Widget
    window("Test", 400, 400) do
      combo_box(items: ITEMS, selected: effective, id: "mc") do |new_set|
        self.stored = new_set # store exactly what the widget computed (atomic)
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

# Click the BODY (well right of the GUTTER_WIDTH=20 column) of popup row `idx`.
private def click_body(app, renderer, mc, idx)
  item = mc.current_popup.not_nil!.item_widgets[idx]
  b = item.absolute_bounds
  pos = CrymbleUI::Vec2.new(b.x + 60.0, b.y + b.height / 2)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
end

describe "MultiComboBox body click = select-one (regular combobox semantics)" do
  # Every prior selection, clicking row 1 (Banana) — the result must ALWAYS be {1}.
  priors = [
    Set(Int32).new,  # none selected
    Set{1},          # only the clicked one
    Set{0},          # only a different one
    Set{0, 1},       # the clicked one + another
    Set{0, 2},       # two others (clicked not among them)
    Set{0, 1, 2, 3}, # all selected
  ]

  priors.each do |prior|
    it "prior #{prior.to_a.sort} → body-click row 1 selects exactly {1} and closes" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
      app = SelOneApp.new
      app.build_tree
      app.selected = prior.dup
      app.rebuild
      renderer.settle_rendering(app)

      mc = open_mc(app, renderer)
      click_body(app, renderer, mc, 1)

      mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
      mc.selected.should eq(Set{1})  # exactly the clicked item — NOT a toggle
      app.selected.should eq(Set{1}) # the app's state agrees
      mc.popup_open?.should be_false # popup closed
    end
  end

  it "body-click select-one works against a DEFAULT-SEEDING app (the embrace bug)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
    app = DefaultSeedingApp.new
    app.build_tree
    renderer.settle_rendering(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{0}) # the seeded default (Apple) shows checked

    # Body-click "Cherry" (2). Must become EXACTLY {2}, not {0, 2}.
    abs = mc.absolute_bounds
    pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    click_body(app, renderer, mc, 2)

    app.as(DefaultSeedingApp).effective.should eq(Set{2}) # exactly Cherry — NOT {0, 2}
    app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox).selected.should eq(Set{2})
  end

  it "the GUTTER still toggles (regression: body=select-one must not change gutter behavior)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
    app = SelOneApp.new
    app.build_tree
    app.selected = Set{0}
    app.rebuild
    renderer.settle_rendering(app)

    mc = open_mc(app, renderer)
    # Click the gutter (left of GUTTER_WIDTH) of row 1 — should ADD 1, keep popup open.
    item = mc.current_popup.not_nil!.item_widgets[1]
    b = item.absolute_bounds
    pos = CrymbleUI::Vec2.new(b.x + 6.0, b.y + b.height / 2)
    app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{0, 1}) # toggled ON, added to the existing selection
    mc.popup_open?.should be_true    # gutter keeps the list open
  end
end
