require "../spec_helper"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/tree_node"
require "../../src/widgets/combo_box"
require "../../src/widgets/text_input"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/simple_matrix"
require "../../src/dsl/builder"
require "../../src/testing/test_renderer"
require "../../src/input/focus_cycler"

# PROTOTYPE harness (step 1): does a faithful, invariant-checking fuzz catch the
# misalignment/scaling/caching class of bugs we fixed this week — automatically?
#
# Two pillars:
#   - strict TestRenderBackend (rejects negative dimensions)        -> overflow class
#   - faithful key dispatch via TestRenderer#key_down               -> focus-escape class
#   - randomized resize sequences checked against layout invariants -> scaling/clip class
#
# Invariants asserted after every resize step:
#   I1  no live layer has a negative width/height        (mid-drag negatives, overflow)
#   I2  the renderer caught zero exceptions              (strict backend / any throw)
#   I3  an embedded matrix's height is invariant under a width-only resize (phantom hscroll)
#   I4  after a round-trip back to the start width, the matrix re-expands  (no-heal / slivers)

# ---- History-Selection-shaped app: resizable panel > tree_node > matrix --------
class FuzzHistoryApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Fuzz", 1300, 800) do
      window_panel("Shape", x: 30.0, y: 30.0, width: 1000.0, height: 700.0,
                   resizable: true, id: "panel") do
        vstack(spacing: 5.0, padding: 5.0) do
          tree_node("History selection", expanded: true, id: "history") do
            matrix(id: "changes", max_height: 200.0) do |m|
              m.header "", "Table", "Records", "Fields", "Cells", ""
              ["Allocations", "Cities", "Persons", "Projects", "Times", "Regions", "Items", "Notes"].each_with_index do |name, i|
                m.row do |r|
                  r << CrymbleUI::Checkbox.new(text: "", checked: true, id: "chk_#{i}").as(CrymbleUI::Widget)
                  r.text(name); r.text("+#{i}"); r.text("+#{i}"); r.text("#{i}")
                  r << CrymbleUI::Button.new("> Shape", padding: 3.0, id: "btn_#{i}").as(CrymbleUI::Widget)
                end
              end
            end
          end
        end
      end
    end
  end
end

private def pump(app, renderer)
  if (root = app.root) && (root.needs_layout? || root.needs_render?)
    app.rebuild
  end
  renderer.render_frame(app)
end

# Assert the always-true layout invariants after a resize step.
private def assert_resize_invariants(renderer, app, ctx : String)
  if root = app.root
    CrymbleUI::Layer.active_layers(root).each do |layer|
      b = layer.bounds
      if b.width < -1.0 || b.height < -1.0
        fail "#{ctx}: layer '#{layer.id}' has negative bounds #{b}"
      end
    end
  end
  if renderer.exceptions_caught != 0
    fail "#{ctx}: renderer caught #{renderer.exceptions_caught} exception(s): #{renderer.last_exception_message}"
  end
end

# Drag the panel's right edge to `target_w` in a few sub-steps, checking invariants
# after each (mid-drag) and after release (settled).
private def fuzz_resize_to(app, renderer, target_w : Float64)
  panel = app.find("panel").as(CrymbleUI::WindowPanel)
  ry = panel.y + panel.height / 2.0
  app.handle_mouse_down(CrymbleUI::Vec2.new(panel.x + panel.width - 3.0, ry))
  pump(app, renderer)
  start_w = panel.width
  4.times do |i|
    w = start_w + (target_w - start_w) * (i + 1) / 4.0
    app.handle_mouse_move(CrymbleUI::Vec2.new(panel.x + w, ry))
    pump(app, renderer)
    assert_resize_invariants(renderer, app, "mid-drag w->#{target_w.round}")
  end
  app.handle_mouse_up(CrymbleUI::Vec2.new(panel.x + target_w, ry))
  pump(app, renderer)
  assert_resize_invariants(renderer, app, "settled w=#{target_w.round}")
end

private def matrix_dims(app)
  vm = app.find("changes").as(CrymbleUI::VirtualMatrix)
  cl = vm.content_layer.not_nil!.bounds
  {vm.bounds.width, cl.width, cl.height}
end

describe "FUZZ: resize + focus invariants (prototype)" do
  it "randomized panel-width resizes keep all layout invariants" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1300, 800)
    app = FuzzHistoryApp.new
    app.build_tree
    renderer.settle_rendering(app)

    base_w, base_cl_w, base_cl_h = matrix_dims(app)
    base_w.should be > 200.0 # sanity: starts wide

    rng = Random.new(0x5EED_i64)
    25.times do
      target = (rng.rand(40..1100)).to_f # includes sub-clamp widths (panel min is 100)
      fuzz_resize_to(app, renderer, target)

      # I3: width-only resize must not change the matrix's height (no phantom h-scrollbar).
      _, _, cl_h = matrix_dims(app)
      cl_h.should be_close(base_cl_h, 0.5)
    end

    # I4: round-trip back to the start width -> the matrix re-expands (heals).
    fuzz_resize_to(app, renderer, 1000.0)
    final_w, final_cl_w, _ = matrix_dims(app)
    final_cl_w.should be_close(base_cl_w, 2.0)
  end

  it "faithful key dispatch: cursor-Up out of a ComboBox cell stays in the matrix" do
    # Matrix with ComboBox cells + a focusable ABOVE it; uses renderer.key_down
    # (the shared dispatch), so no hand-rolled navigate is needed to see a leak.
    adapter = FuzzComboAdapter.new
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "m")
    above = CrymbleUI::Button.new("above", id: "above") { }
    root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    root.add_child(above)
    root.add_child(matrix)
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    app = TestApp.new
    app.root_widget = root
    app.build_tree
    root.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 400.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)
    fm = CrymbleUI::Widget.focus_manager

    fm.focus(matrix)
    renderer.key_down(SF::Keyboard::Key::Down)  # row 1
    renderer.key_down(SF::Keyboard::Key::Right) # col 1 (ComboBox)
    fm.handle_text_input('B')                   # open popup (type-to-filter)
    renderer.render_frame(app)
    matrix.active_cells[{1, 1}]?.as(CrymbleUI::ComboBox).popup_open?.should be_true

    renderer.key_down(SF::Keyboard::Key::Up)    # leave the combo upward

    fm.focused_widget.should_not eq(above)      # must NOT escape to the widget above
    fm.focused_widget.should eq(matrix)
  end

  it "fuzz: arrow/type/enter/escape sequences never let focus escape the matrix" do
    # Matrix surrounded by focusable buttons (above + below). Invariant: while
    # focus is inside the matrix focus scope, NO non-Tab key may move focus onto a
    # sibling (arrows move the cell cursor / dropdown highlight; they never leave
    # the scope — Tab is the only intentional escape, so it's excluded here).
    adapter = FuzzComboAdapter.new(3, 2)
    matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "m")
    above = CrymbleUI::Button.new("above", id: "above") { }
    below = CrymbleUI::Button.new("below", id: "below") { }
    root = CrymbleUI::VStack.new(spacing: 0.0, padding: 0.0)
    root.add_child(above)
    root.add_child(matrix)
    root.add_child(below)
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 500)
    app = TestApp.new
    app.root_widget = root
    app.build_tree
    root.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 500.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)
    fm = CrymbleUI::Widget.focus_manager
    siblings = [above, below] of CrymbleUI::Widget

    rng = Random.new(0xF0C5_i64)
    fm.focus(matrix)
    seq = [] of String
    120.times do
      case rng.rand(7)
      when 0 then seq << "Up";    renderer.key_down(SF::Keyboard::Key::Up)
      when 1 then seq << "Down";  renderer.key_down(SF::Keyboard::Key::Down)
      when 2 then seq << "Left";  renderer.key_down(SF::Keyboard::Key::Left)
      when 3 then seq << "Right"; renderer.key_down(SF::Keyboard::Key::Right)
      when 4 then seq << "type";  fm.handle_text_input('a'); renderer.render_frame(app)
      when 5 then seq << "Enter"; renderer.key_down(SF::Keyboard::Key::Enter)
      else        seq << "Esc";   renderer.key_down(SF::Keyboard::Key::Escape)
      end
      if siblings.includes?(fm.focused_widget)
        fail "focus escaped the matrix to '#{fm.focused_widget.try &.id}' after: #{seq.join(" ")}"
      end
    end
  end

  it "strict TestRenderBackend rejects negative dimensions (overflow-class guard)" do
    # A negative texture size used to be silently masked headless (and only blew up
    # under SFML as 'Arithmetic overflow' from .to_u32). Now it fails loudly.
    expect_raises(ArgumentError, /negative dimensions/) do
      CrymbleUI::Testing::TestRenderBackend.new(-5, 100)
    end
  end
end

class FuzzComboAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32 = 3, @cols : Int32 = 2)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    if col == 1
      CrymbleUI::ComboBox.new(items: ["Apple", "Banana", "Cherry"], selected: 0, id: "combo_#{row}_#{col}")
    else
      CrymbleUI::TextInput.new(value: "R#{row}C#{col}", id: "cell_#{row}_#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
    end
  end
end
