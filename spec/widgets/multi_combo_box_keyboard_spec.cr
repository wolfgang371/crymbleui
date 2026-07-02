require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/multi_combo_box"
require "../../src/widgets/window"

# keyboard navigation for the CHECKABLE popup.
# - the "(select all)" header is a first-class nav element (ArrowUp from the
#   first item reaches it; ArrowDown returns); it participates in the active
#   highlight (so it can never silently drop out of the nav model);
# - Space TOGGLES the highlighted element (header = select-all/none; row =
#   membership) and KEEPS the popup open — driven through on_text_input (the
#   live TextEntered path), and it must NOT type a literal space into the filter;
# - Enter CONFIRMS & CLOSES, preserving a multi-selection (it must not collapse
#   the whole selection to the highlighted row, the single-select behaviour).
# The single (non-checkable) ComboBox is unaffected (its specs stay green).

private def kpress(key : SF::Keyboard::Key, control = false, shift = false)
  CrymbleUI::Widget.focus_manager.handle_key_down(key, control, shift)
end

class KbMultiApp < CrymbleUI::App
  state selected : Set(Int32) = Set{0}

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      combo_box(items: ["Apple", "Banana", "Cherry"], selected: @selected, id: "mc") { |s| self.selected = s }
    end
  end
end

private def open_mc(app, r) : CrymbleUI::MultiComboBox
  mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
  abs = mc.absolute_bounds
  pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
  app.handle_mouse_down(pos); app.handle_mouse_up(pos); r.render_frame(app)
  mc = app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
  mc.popup_open?.should be_true
  mc
end

private def mc_of(app) : CrymbleUI::MultiComboBox
  app.find("mc").not_nil!.as(CrymbleUI::MultiComboBox)
end

# Count "ink" pixels (differ from the row's far-right background) over `rect` in the
# COMPOSITED window buffer. Used to assert the header row is actually PAINTED — the
# vanish bug leaves the header's widget state + geometry intact but its pixels blank,
# so only a composited-pixel check catches it (mirrors the SFML execution model;
# TestRenderer#composite_layer_to_window is built to match SFML — layer_renderer.cr).
private def row_ink(backend, rect : CrymbleUI::Rect) : Int32
  x0 = rect.x.to_i; y0 = rect.y.to_i
  x1 = (rect.x + rect.width).to_i; y1 = (rect.y + rect.height).to_i
  bg = backend.get_pixel(x1 - 2, (y0 + y1) // 2)
  return -1 unless bg
  n = 0
  (y0...y1).each do |y|
    (x0...x1).each do |x|
      p = backend.get_pixel(x, y)
      next unless p
      n += 1 if (p.r.to_i - bg.r.to_i).abs > 18 || (p.g.to_i - bg.g.to_i).abs > 18 || (p.b.to_i - bg.b.to_i).abs > 18
    end
  end
  n
end

describe "MultiComboBox keyboard navigation" do
  it "ArrowUp from the first item reaches the (select all) header" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r)
    pop = mc.current_popup.not_nil!
    pop.highlighted_index.should eq(0)        # item 0 highlighted on open
    pop.header_highlighted?.should be_false

    kpress(SF::Keyboard::Key::Up)
    r.settle_rendering(app)

    pop = mc_of(app).current_popup.not_nil!
    pop.header_highlighted?.should be_true               # header is now the active element
    pop.header_item.not_nil!.highlighted?.should be_true # ...and it carries the highlight
    pop.item_widgets.none?(&.highlighted?).should be_true # no item highlighted while on the header
  end

  it "ArrowDown from the header returns to the first item" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r)
    kpress(SF::Keyboard::Key::Up) # to header
    r.settle_rendering(app)
    mc_of(app).current_popup.not_nil!.header_highlighted?.should be_true

    kpress(SF::Keyboard::Key::Down) # back to first item
    r.settle_rendering(app)
    pop = mc_of(app).current_popup.not_nil!
    pop.header_highlighted?.should be_false
    pop.highlighted_index.should eq(0)
  end

  it "Space toggles the highlighted row, keeps the popup open, and does NOT type into the filter" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r) # selected {0}
    kpress(SF::Keyboard::Key::Down) # highlight item 1 (Banana)
    r.settle_rendering(app)
    pop = mc_of(app).current_popup.not_nil!
    pop.text_input.value.should eq("")

    pop.text_input.on_text_input(' ') # the live TextEntered path for a space
    r.settle_rendering(app)

    mc = mc_of(app)
    mc.selected.should eq(Set{0, 1})           # Banana toggled ON
    mc.popup_open?.should be_true              # stays open
    mc.current_popup.not_nil!.text_input.value.should eq("") # NOT a typed space
  end

  it "Space on the highlighted header toggles select-all and keeps the popup open" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r)
    kpress(SF::Keyboard::Key::Up) # to header
    r.settle_rendering(app)
    pop = mc_of(app).current_popup.not_nil!

    pop.text_input.on_text_input(' ')
    r.settle_rendering(app)

    mc = mc_of(app)
    mc.selected.should eq(Set{0, 1, 2})
    mc.popup_open?.should be_true
  end

  it "Enter confirms & closes WITHOUT replacing a multi-selection" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r) # selected {0}
    # Build a 2-element selection via Space on item 1.
    kpress(SF::Keyboard::Key::Down) # highlight Banana
    r.settle_rendering(app)
    mc_of(app).current_popup.not_nil!.text_input.on_text_input(' ') # toggle Banana on → {0,1}
    r.settle_rendering(app)
    mc_of(app).selected.should eq(Set{0, 1})

    kpress(SF::Keyboard::Key::Down) # highlight Cherry (item 2)
    r.settle_rendering(app)
    kpress(SF::Keyboard::Key::Enter) # confirm & close
    r.settle_rendering(app)

    mc = mc_of(app)
    mc.popup_open?.should be_false
    mc.selected.should eq(Set{0, 1}) # preserved — NOT collapsed to {2}
  end

  it "the highlighted nav position (header) survives a rebuild while the popup is open" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r)
    kpress(SF::Keyboard::Key::Up) # header highlighted
    r.settle_rendering(app)
    mc_of(app).current_popup.not_nil!.header_highlighted?.should be_true

    app.rebuild # reconcile carries the popup by identity
    r.settle_rendering(app)

    mc_of(app).current_popup.not_nil!.header_highlighted?.should be_true
  end

  # Regression for the live-only "(select all) vanishes on the first arrow" bug.
  # ROOT CAUSE: move_highlight marked the POPUP CONTAINER NeedsRender; selective
  # re-render then repainted the container over its CLEAN direct children's regions
  # WITHOUT repainting them, blanking the header (the items survive on the
  # ScrollView's own layer; the TextInput survives via its cursor-blink churn). The
  # header's widget state + geometry stay intact through the vanish — only its pixels
  # go — so this is asserted at the PIXEL level. Tested with a plain ArrowDown, where
  # the header is NEVER the highlighted element (the case a naive "dirty the header"
  # fix misses). Fails pre-fix: header_ink drops to 0 after the arrow.
  it "the (select all) header stays painted across plain arrow navigation (no vanish)" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 360)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r)
    pop = mc.current_popup.not_nil!
    hb = pop.header_item.not_nil!.absolute_bounds
    row_ink(r.backend, hb).should be > 50 # header is painted on open

    kpress(SF::Keyboard::Key::Down) # highlight moves to item 1 — header is never highlighted
    r.settle_rendering(app)
    pop = mc_of(app).current_popup.not_nil!
    pop.highlighted_index.should eq(1)                                   # the highlight DID move...
    row_ink(r.backend, pop.header_item.not_nil!.absolute_bounds).should be > 50 # ...and the header is STILL painted

    kpress(SF::Keyboard::Key::Down) # and again
    r.settle_rendering(app)
    pop = mc_of(app).current_popup.not_nil!
    pop.highlighted_index.should eq(2)
    row_ink(r.backend, pop.header_item.not_nil!.absolute_bounds).should be > 50
  end

  # the STRUCTURAL backstop — a popup must not wipe its clean direct children
  # when it is marked NeedsRender by ANY path (not just move_highlight). Simulate a
  # future self-mark directly and assert a clean child (the header) stays painted.
  it "a clean child survives an explicit popup self-mark (NeedsRender)" do
    r = CrymbleUI::Testing::TestRenderer.new(400, 360)
    app = KbMultiApp.new; app.build_tree; r.settle_rendering(app)
    mc = open_mc(app, r)
    pop = mc.current_popup.not_nil!
    hb = pop.header_item.not_nil!.absolute_bounds
    row_ink(r.backend, hb).should be > 50 # painted on open

    pop.mark_needs_render # the footgun: any future self-mark of the open popup
    r.settle_rendering(app)
    row_ink(r.backend, mc_of(app).current_popup.not_nil!.header_item.not_nil!.absolute_bounds).should be > 50
  end
end
