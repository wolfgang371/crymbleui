require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/text_input"
require "../../src/testing/test_renderer"
require "../../src/input/keyboard_dispatch"
require "../../src/testing/keys"

# A keystroke's modifiers belong to the KEYSTROKE, not to the moment it is dispatched.
#
# The run loop drains SFML's queue only between frames, so under a burst (AutoHotkey typing into
# embrace, 2026-09-22) a slow frame leaves a backlog, and the input source is already further along
# when the backlog is handled. The TextEntered branch used to ask the LIVE keyboard whether Ctrl was
# down: text queued as plain typing was dropped whole whenever the script happened to be holding
# Ctrl for a later chord at drain time. Tab never asked, so navigation stayed in step while cells
# came out empty — the reported symptom exactly.
#
# These examples feed KeyboardDispatch the LibCSFML::Event values the run loop polls (built with
# Testing::Keys), one by one: the dispatch itself, not the batching (TestRenderer#deliver). The live
# keyboard is not part of the fixture, so a dispatch that consults it decides on the machine the
# spec runs on, where nobody holds Ctrl.

private class KeyboardDispatchSpecAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  getter data = {} of Tuple(Int32, Int32) => String

  def initialize(@rows : Int32, @cols : Int32)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: @data[{row, col}]? || "", mode: CrymbleUI::TextInputMode::QuickEntry)
  end

  def cell_assign(row : Int32, col : Int32, value : String) : Tuple(Int32, Int32)
    @data[{row, col}] = value
    {row, col}
  end
end

private alias Keys = CrymbleUI::Testing::Keys

private def build_dispatch_fixture(rows = 3, cols = 3)
  adapter = KeyboardDispatchSpecAdapter.new(rows, cols)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "m")
  renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(600.0, 400.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  CrymbleUI::Widget.focus_manager.focus(matrix)
  dispatch = CrymbleUI::KeyboardDispatch.new(CrymbleUI::Widget.focus_manager, CrymbleUI::ShortcutManager.new)
  {app, matrix, adapter, dispatch}
end

describe CrymbleUI::KeyboardDispatch do
  it "a Ctrl chord's text is not typed, even when Ctrl is up by the time the queue drains" do
    app, matrix, adapter, dispatch = build_dispatch_fixture
    CrymbleUI::FontSizing.zoom_in
    begin
      # Ctrl+0 as queued: X11 delivers TextEntered('0') for it (Windows delivers none).
      events = [Keys.pressed(SF::Keyboard::Key::LControl, control: true),
                Keys.pressed(SF::Keyboard::Key::Num0, control: true), Keys.text('0'),
                Keys.released(SF::Keyboard::Key::Num0, control: true),
                Keys.released(SF::Keyboard::Key::LControl, control: true)] +
               Keys.tap(SF::Keyboard::Key::Tab)
      events.each { |e| dispatch.handle(e, app) }

      adapter.data[{0, 0}]?.should be_nil                            # no stray '0' in the cell
      CrymbleUI::FontSizing.zoom_index.should eq(CrymbleUI::FontSizing::DEFAULT_ZOOM_INDEX) # the chord still reset zoom
      matrix.cursor_rc.should eq({0, 1})
    ensure
      CrymbleUI::FontSizing.reset_zoom
    end
  end

  it "an AutoHotkey burst lands every value in its own cell (plain text between Ctrl chords)" do
    app, matrix, adapter, dispatch = build_dispatch_fixture
    values = ["alpha", "b", "", "delta 4", "echo", "f", "golf", "h 8", "india"]
    events = [] of LibCSFML::Event
    values.each_with_index do |value, i|
      events.concat(Keys.typed(value) + Keys.tap(SF::Keyboard::Key::Tab))
      # a Ctrl chord after each row, as the script adds records with Ctrl+R
      events.concat(Keys.ctrl(SF::Keyboard::Key::R)) if i % 3 == 2
    end
    events.each { |e| dispatch.handle(e, app) }

    values.each_with_index do |value, i|
      next if value.empty?
      adapter.data[{i // 3, i % 3}]?.should eq(value)
    end
    matrix.cursor_rc.should eq({0, 0}) # nine Tabs round-robin a 3x3 grid back to the start
  end

  it "AltGr text is typed: Windows reports it as Ctrl+Alt" do
    app, matrix, adapter, dispatch = build_dispatch_fixture
    events = [Keys.pressed(SF::Keyboard::Key::LControl, control: true),
              Keys.pressed(SF::Keyboard::Key::RAlt, control: true, alt: true),
              Keys.pressed(SF::Keyboard::Key::Q, control: true, alt: true),
              Keys.text('@')] + Keys.tap(SF::Keyboard::Key::Tab)
    events.each { |e| dispatch.handle(e, app) }

    adapter.data[{0, 0}]?.should eq("@")
  end

  # The mouse wheel has no modifier flags of its own; Ctrl+wheel zooms and Shift+wheel scrolls
  # sideways off this state. X11 flags a modifier key's own event with the state BEFORE it.
  it "holds a modifier from its own press to its own release, and forgets it on focus loss" do
    app, _matrix, _adapter, dispatch = build_dispatch_fixture
    dispatch.handle(Keys.pressed(SF::Keyboard::Key::LControl, control: false), app)
    dispatch.control?.should be_true
    dispatch.handle(Keys.released(SF::Keyboard::Key::LControl, control: true), app)
    dispatch.control?.should be_false

    dispatch.handle(Keys.pressed(SF::Keyboard::Key::LShift), app)
    dispatch.shift?.should be_true
    focus_lost = LibCSFML::Event.new
    focus_lost.type = LibCSFML::EventType::FocusLost
    dispatch.handle(focus_lost, app)
    dispatch.shift?.should be_false
  end
end
