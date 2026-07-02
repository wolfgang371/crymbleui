require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/multi_combo_box"
require "../../src/widgets/window"

# a multi-select ComboBox via the `selected : Set(Int32)` overload.
# Clicking a row's ✓ gutter TOGGLES membership and keeps the popup open;
# clicking the row body selects-only-that and closes. The selection must
# SURVIVE a DSL rebuild (the reconcile bug the gate caught: a build-shadow
# that compares the same mutated Set to itself would revert the toggle).

# App holds the Set immutably — each toggle stores a NEW Set (the contract).
class MultiSelApp < CrymbleUI::App
  state selected : Set(Int32) = Set{0}

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      combo_box(items: ["Apple", "Banana", "Cherry"], selected: @selected, id: "mc") do |new_set|
        self.selected = new_set
      end
    end
  end
end

# App with many items for filter testing
class MultiSelFilterApp < CrymbleUI::App
  state selected : Set(Int32) = Set(Int32).new

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      combo_box(items: ["Apple", "Apricot", "Banana", "Cherry"], selected: @selected, id: "mc") do |new_set|
        self.selected = new_set
      end
    end
  end
end

# App with all items pre-selected
class MultiSelAllApp < CrymbleUI::App
  state selected : Set(Int32) = Set{0, 1, 2}

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      combo_box(items: ["Alpha", "Beta", "Gamma"], selected: @selected, id: "mc") do |new_set|
        self.selected = new_set
      end
    end
  end
end

# App with empty items list
class MultiSelEmptyApp < CrymbleUI::App
  state selected : Set(Int32) = Set(Int32).new

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      combo_box(items: [] of String, selected: @selected, id: "mc") do |new_set|
        self.selected = new_set
      end
    end
  end
end

# App with a custom summary function
class MultiSelSummaryApp < CrymbleUI::App
  state selected : Set(Int32) = Set{0, 2}
  ITEMS = ["Red", "Green", "Blue"]

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      combo_box(items: ITEMS, selected: @selected, id: "mc",
        summary: ->(s : Set(Int32)) { s.map { |i| ITEMS[i] }.join(", ") }) do |new_set|
        self.selected = new_set
      end
    end
  end
end

private def open_and_get(app, renderer) : CrymbleUI::MultiComboBox
  mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
  abs = mc.absolute_bounds
  pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
  mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
  mc.popup_open?.should be_true
  mc
end

# Click the ✓ gutter (left) of popup row `idx`.
private def click_gutter(app, renderer, mc, idx)
  item = mc.current_popup.not_nil!.item_widgets[idx]
  b = item.absolute_bounds
  pos = CrymbleUI::Vec2.new(b.x + 6.0, b.y + b.height / 2)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
end

# Click the body (right of gutter) of popup row `idx`.
private def click_body(app, renderer, mc, idx)
  item = mc.current_popup.not_nil!.item_widgets[idx]
  b = item.absolute_bounds
  # Click well to the right of the gutter (GUTTER_WIDTH=20, so 40px is safe)
  pos = CrymbleUI::Vec2.new(b.x + 40.0, b.y + b.height / 2)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
end

# Click the header item (select-all) by its body
private def click_header(app, renderer, mc)
  hdr = mc.current_popup.not_nil!.header_item.not_nil!
  b = hdr.absolute_bounds
  pos = CrymbleUI::Vec2.new(b.x + 40.0, b.y + b.height / 2)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); renderer.render_frame(app)
end

describe "MultiComboBox (selected : Set(Int32))" do
  # ===== HEADLINE TESTS =====

  it "toggling a row's ✓ gutter adds to the set and keeps the popup OPEN" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelApp.new
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)
    click_gutter(app, renderer, mc, 1) # toggle "Banana" on

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{0, 1})
    mc.popup_open?.should be_true # stays open on a toggle
  end

  it "the toggled selection SURVIVES a DSL rebuild (reconcile)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelApp.new
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)
    click_gutter(app, renderer, mc, 1)
    app.rebuild # the bug: a same-object build-shadow would revert this

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{0, 1})
  end

  # ===== BODY CLICK =====

  it "body click selects ONLY that item and CLOSES the popup" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelApp.new
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)
    click_body(app, renderer, mc, 1) # click body of "Banana"

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{1})
    mc.popup_open?.should be_false
  end

  # ===== TRISTATE HEADER =====

  it "header click selects ALL items" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelApp.new # starts with Set{0}
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)
    mc.current_popup.not_nil!.header_item.should_not be_nil

    click_header(app, renderer, mc)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{0, 1, 2})
  end

  it "header click when all selected deselects ALL items" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelAllApp.new # starts with Set{0,1,2}
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)
    click_header(app, renderer, mc)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set(Int32).new)
  end

  # ===== TOGGLE WHILE FILTERED → ORIGINAL INDEX =====

  it "toggle while filtered maps to the correct ORIGINAL item index" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelFilterApp.new # items: Apple=0, Apricot=1, Banana=2, Cherry=3
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)

    # Type "Ban" to filter — only "Banana" (original index 2) remains
    popup = mc.current_popup.not_nil!
    popup.filter_items("Ban")
    renderer.render_frame(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    # After filtering, item_widgets[0] is "Banana" (original index 2)
    click_gutter(app, renderer, mc, 0)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    # Should contain index 2 (Banana), not index 0 (Apple)
    mc.selected.should contain(2)
    mc.selected.should_not contain(0)
    mc.popup_open?.should be_true
  end

  # ===== SUMMARY TEXT =====

  it "collapsed cell shows the custom summary text" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelSummaryApp.new # selected: {0, 2}, items: Red/Green/Blue
    app.build_tree
    renderer.settle_rendering(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)

    # Extract DrawText primitives from the collapsed widget
    primitives = mc.to_primitives(mc.bounds)
    text_primitives = primitives.select(&.is_a?(CrymbleUI::DrawText)).map(&.as(CrymbleUI::DrawText))
    texts = text_primitives.map(&.text)

    # The summary "Red, Blue" should appear (order is sorted by index: 0=Red, 2=Blue)
    texts.any? { |t| t.includes?("Red") && t.includes?("Blue") }.should be_true
  end

  it "default summary: a SINGLE pick shows the item NAME (not '1 of 3')" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelApp.new # selected: {0} of [Apple, Banana, Cherry]
    app.build_tree
    renderer.settle_rendering(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    texts = mc.to_primitives(mc.bounds).compact_map { |p| p.as?(CrymbleUI::DrawText).try(&.text) }
    texts.any?(&.includes?("Apple")).should be_true   # the name
    texts.any?(&.includes?("1 of 3")).should be_false # NOT the count form
  end

  it "default summary: MANY picks show 'N of M (names…)' using the width" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelAllApp.new # selected {0,1,2} of [Alpha, Beta, Gamma], no custom summary
    app.build_tree
    renderer.settle_rendering(app)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    texts = mc.to_primitives(mc.bounds).compact_map { |p| p.as?(CrymbleUI::DrawText).try(&.text) }
    label = texts.find(&.includes?("of")).not_nil!
    label.should contain("3 of 3") # the count
    label.should contain("Alpha")  # the name list fills the space
  end

  # ===== EDGE CASES =====

  it "empty items list: popup opens without crashing" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelEmptyApp.new
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)
    mc.selected.should eq(Set(Int32).new)
    mc.popup_open?.should be_true
  end

  it "all-preselected round-trip: toggle off then on preserves identity" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = MultiSelAllApp.new # Set{0,1,2}
    app.build_tree
    renderer.settle_rendering(app)

    mc = open_and_get(app, renderer)
    click_gutter(app, renderer, mc, 0) # toggle Alpha off (popup stays open)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{1, 2})
    mc.popup_open?.should be_true # still open

    # Toggle Alpha back on — popup is still open
    click_gutter(app, renderer, mc, 0)

    mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
    mc.selected.should eq(Set{0, 1, 2})
  end

  # ===== REGRESSION CANARY =====

  it "non-checkable ComboBoxItem has unchanged primitive count (inert canary)" do
    # A non-checkable item produces exactly 2 primitives: fill_rect + draw_text
    item = CrymbleUI::ComboBoxItem.new("TestItem")
    bounds = CrymbleUI::Rect.new(0.0, 0.0, 150.0, 24.0)
    prims = item.to_primitives(bounds)
    fill_rects = prims.count(&.is_a?(CrymbleUI::FillRect))
    draw_texts = prims.count(&.is_a?(CrymbleUI::DrawText))

    fill_rects.should eq(1)
    draw_texts.should eq(1)
    prims.size.should eq(2)
  end

  it "checkable ComboBoxItem draws a REAL checkbox in the gutter (not a text glyph)" do
    item = CrymbleUI::ComboBoxItem.new("TestItem")
    item.check_state_fn = -> { CrymbleUI::CheckState::Checked }
    bounds = CrymbleUI::Rect.new(0.0, 0.0, 150.0, 24.0)
    prims = item.to_primitives(bounds)

    # Gutter is the real checkbox visual: box (4 edge fill_rects) + a checkmark
    # (2 lines + 1 junction) — NOT an extra text glyph. The only DrawText is the label.
    prims.count(&.is_a?(CrymbleUI::DrawText)).should eq(1)   # label only
    prims.count(&.is_a?(CrymbleUI::DrawLine)).should eq(2)   # checkmark strokes
    prims.count(&.is_a?(CrymbleUI::DrawCircle)).should eq(1) # junction
    prims.count(&.is_a?(CrymbleUI::FillRect)).should eq(5)   # 1 bg + 4 box edges
  end
end
