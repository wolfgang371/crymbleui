require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"

# The matrix must forward the ALT modifier to a proxy-focused cell editor.
#
# `VirtualMatrix#on_key_down` accepts `alt` and then drops it at every proxy forward, so a
# cell editor sees Alt+X as a bare X. Nothing reads `alt` in any widget today, which is what
# makes this change behaviour-neutral — and also what makes it invisible until a widget
# needs the modifier, at which point it looks like the widget is broken rather than the
# routing. The editor is the last link in a chain that already carries `alt` correctly
# (SFMLRenderer -> FocusManager#dispatch_key -> handle_key_down -> the focused widget).
#
# The second example is the mirror that guards the forwarding's blast radius: the branch
# that handles Enter/Space calls the app's activation hook FIRST, and that ordering is what
# a host relies on for drill-down. Forwarding a modifier must not disturb it.

# NOT `private`: Widget's reconcile macro generates a top-level `old_widget.as(...)`
# for every widget subclass, which cannot name a file-private type. Prefixed instead,
# since the whole group compiles into one binary.
class AltForwardRecordingCell < CrymbleUI::TextInput
  getter seen_alt : Bool = false
  getter seen_key : SF::Keyboard::Key? = nil

  def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
    @seen_alt = alt
    @seen_key = key
    super
  end
end

private class AltAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32); end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    AltForwardRecordingCell.new(value: "R#{row}C#{col}", mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

private def setup_alt_matrix
  matrix = CrymbleUI::VirtualMatrix.new(AltAdapter.new(5, 3), id: "alt_matrix")
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 300.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  CrymbleUI::Widget.focus_manager.focus(matrix)
  matrix
end

describe "VirtualMatrix alt forwarding" do
  it "hands the alt modifier to the proxy-focused cell editor" do
    matrix = setup_alt_matrix
    cell = matrix.active_cells[{0, 0}]?.as(AltForwardRecordingCell)

    # Reachability: the cell must actually receive the key at all, or "saw alt" would be
    # vacuously false for a reason unrelated to the modifier.
    matrix.on_key_down(SF::Keyboard::Key::K, false, false, true)
    cell.seen_key.should eq(SF::Keyboard::Key::K)

    cell.seen_alt.should be_true
  end

  it "hands alt to the editor on the Escape path too" do
    matrix = setup_alt_matrix
    cell = matrix.active_cells[{0, 0}]?.as(AltForwardRecordingCell)

    matrix.on_key_down(SF::Keyboard::Key::Escape, false, false, true)
    cell.seen_key.should eq(SF::Keyboard::Key::Escape)
    cell.seen_alt.should be_true
  end

  it "hands alt to the editor on the arrow path when the editor wants arrows" do
    matrix = setup_alt_matrix
    cell = matrix.active_cells[{0, 0}]?.as(AltForwardRecordingCell)
    cell.enter_edit_mode # FullEdit — only then does the matrix forward arrows
    cell.wants_arrow_keys?.should be_true

    matrix.on_key_down(SF::Keyboard::Key::Down, false, false, true)
    cell.seen_key.should eq(SF::Keyboard::Key::Down)
    cell.seen_alt.should be_true
  end

  it "still gives the app's activation hook first refusal on a BARE Enter" do
    # The mirror. Drill-down in a host application depends on this ordering, and it is the
    # one thing the forwarding change could disturb.
    matrix = setup_alt_matrix
    fired = 0
    matrix.on_cell_activate = ->(_rc : Tuple(Int32, Int32)) do
      fired += 1
      false # decline, so the proxy still gets its turn as it does today
    end

    matrix.on_key_down(SF::Keyboard::Key::Enter, false, false)
    fired.should eq(1)
  end
end
