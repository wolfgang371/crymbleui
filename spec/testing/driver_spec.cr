require "../spec_helper"
require "../../src/testing/driver"
require "../../src/testing/configurable_matrix_adapter"
require "../../src/widgets/popup"
require "../../src/widgets/draggable_box"
require "../../src/widgets/drop_zone_box"

# The test Driver: acting on widgets by id, the way a use case reads. Each case names the mutation
# of the Driver (or of the machinery it shares with real input) that turns it red.

# --- fixtures ----------------------------------------------------------------------------------

# An app over a hand-built window; `on_build` runs on every (re)build, so state set by a handler
# shows up after the rebuild the handler requests.
private class WindowApp < CrymbleUI::App
  property build_count = 0
  getter window : CrymbleUI::Window

  def initialize(&@on_build : CrymbleUI::Window -> Nil)
    super()
    @window = CrymbleUI::Window.new("W", 800, 600, id: "window")
  end

  def build : CrymbleUI::Widget
    @build_count += 1
    @window = CrymbleUI::Window.new("W", 800, 600, id: "window")
    @on_build.call(@window)
    @window
  end
end

private def driver(&build : CrymbleUI::Window -> Nil) : CrymbleUI::Testing::Driver
  CrymbleUI::Testing::Driver.new(WindowApp.new(&build), 800, 600)
end

private def window_of(ui) : CrymbleUI::Window
  ui.app.root.not_nil!.as(CrymbleUI::Window)
end

# Mount a popup as real callers do: an overlay is laid out by the window's layout pass, which
# add_overlay alone does not request.
private def open_popup(ui, popup : CrymbleUI::Popup) : Nil
  window = window_of(ui)
  window.add_overlay(popup)
  window.mark_needs_layout
  ui.settle
end

# A panel with a row whose right-click opens a context menu holding "Rename".
private def context_menu_app(renames : Array(Int32)) : CrymbleUI::Testing::Driver
  driver do |window|
    panel = CrymbleUI::WindowPanel.new("P", 50.0, 50.0, 300.0, 200.0, id: "panel")
    panel.add_child(CrymbleUI::Button.new("row", id: "row") { })
    window.add_child(panel)
    panel.on_right_click_handler = ->(_p : CrymbleUI::Vec2) {
      popup = CrymbleUI::Popup.new(width: 120.0, height: 40.0, id: "ctx")
      popup.target_x = 400.0
      popup.target_y = 300.0
      popup.add_child(CrymbleUI::Button.new("Rename", id: "ctx_rename") {
        renames << 1
        window.remove_overlay(popup)
      })
      popup.on_click_outside_callback = ->{ window.remove_overlay(popup); nil }
      window.add_overlay(popup)
      window.mark_needs_layout # an overlay is laid out by the window's layout pass
      nil
    }
  end
end

private class HookSource < CrymbleUI::DraggableBox
  getter log : Array(String)

  def initialize(@log : Array(String), id : String? = nil, @data : CrymbleUI::DragData? = CrymbleUI::TextDragData.new("x"))
    super(@data, id: id)
  end

  def get_drag_data : CrymbleUI::DragData?
    @data
  end

  def on_drag_start(data : CrymbleUI::DragData)
    @log << "start"
  end

  def on_drag_end(data : CrymbleUI::DragData, dropped : Bool)
    @log << "end:#{dropped}"
  end
end

private class HookTarget < CrymbleUI::DropZoneBox
  def initialize(@log : Array(String), accepts : Array(String) = ["text"], id : String? = nil)
    super(accept_types: accepts, on_drop_handler: ->(_d : CrymbleUI::DragData, _p : CrymbleUI::Vec2) { @log << "drop"; nil }, id: id)
  end

  def on_drag_enter(data : CrymbleUI::DragData)
    @log << "enter"
  end

  def on_drag_leave(data : CrymbleUI::DragData)
    @log << "leave"
  end
end

private class KeyRecorder < CrymbleUI::Widget
  getter keys = [] of String

  def initialize(id : String)
    super(id: id)
  end

  def focusable? : Bool
    true
  end

  def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
    @keys << "#{control ? "Ctrl+" : ""}#{shift ? "Shift+" : ""}#{key}"
    true
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(50, 20)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(50, 20))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

# A plain block of a fixed size - a drop zone as large as its content.
private class Block < CrymbleUI::Widget
  def initialize(@size : CrymbleUI::Size)
    super(id: nil)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    @size
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, @size)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private class OpenThing < CrymbleUI::Widget
  include CrymbleUI::Dismissable
  getter? open = true

  def initialize
    super(id: "open_thing")
  end

  def dismiss_overlay : Bool
    was = @open
    @open = false
    was
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(10, 10)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, CrymbleUI::Size.new(10, 10))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [] of CrymbleUI::DrawPrimitive
  end
end

private def file_info : File::Info
  File.info(__FILE__)
end

private def dir_info : File::Info
  File.info(Dir.tempdir)
end

# A file browser: 30 files and one directory "sub/" holding "inner.emb". One adapter for the whole
# run (it carries the two-click bookkeeping), a small viewport so most rows are off-screen.
private def browser(opened : Array(String), selected : Array(String)) : CrymbleUI::Testing::Driver
  adapter = CrymbleUI::Widgets::DirBrowser::MatrixAdapter.new
  top = [{"sub/", "", "", dir_info}] + (1..30).map { |i| {"f%02d.emb" % i, "1", "d", file_info} }
  adapter.items = top
  adapter.on_select_file = ->(name : String) { selected << name; nil }
  adapter.on_accept = ->(name : String) { opened << name; nil }
  adapter.on_navigate = ->(dir : String) {
    if dir == "sub"
      adapter.items = [{"inner.emb", "1", "d", file_info}]
      adapter.invalidate_all! # a new listing: tell the matrix, as a host's rebuild would
    end
    nil
  }
  ui = driver do |window|
    vm = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "files")
    vm.show_rulers = false
    panel = CrymbleUI::WindowPanel.new("Files", 10.0, 10.0, 400.0, 160.0, id: "files_panel")
    panel.add_child(vm)
    window.add_child(panel)
  end
  ui
end

# Two grid subclasses - public, since the widget reconcile macro names the type (a private class
# does not compile there). A grid that counts mouse-ups and can refuse drops - to see what a drag
# sends it.
class DriverCountingMatrix < CrymbleUI::VirtualMatrix
  getter ups = 0
  property accepts = true

  def on_mouse_up(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left)
    @ups += 1
    super
  end

  def accepts_drop?(data : CrymbleUI::DragData) : Bool
    @accepts && super
  end
end

# A grid whose press requests a rebuild, as an app redrawing on a cursor move would.
class DriverRebuildingMatrix < CrymbleUI::VirtualMatrix
  def on_mouse_down(point : CrymbleUI::Vec2, button : CrymbleUI::MouseButton = CrymbleUI::MouseButton::Left) : Bool
    handled = super
    CrymbleUI::Widget.app?.not_nil!.request_rebuild
    handled
  end
end

# Two panels overlapping, the later one (back) full of a drop zone, the earlier (front) with one or
# none; a spec brings the earlier one to front.
private def overlapping_zones(front_log : Array(String), back_log : Array(String), front_zone : Bool)
  driver do |w|
    source = CrymbleUI::WindowPanel.new("S", 560.0, 400.0, 200.0, 120.0, id: "source") # clear of the other two
    source.add_child(HookSource.new(front_log, id: "src").tap(&.add_child(CrymbleUI::Text.new("field"))))
    w.add_child(source)
    front = CrymbleUI::WindowPanel.new("F", 100.0, 100.0, 300.0, 200.0, id: "front")
    front.add_child(front_zone ? HookTarget.new(front_log, id: "front_zone").tap(&.add_child(Block.new(CrymbleUI::Size.new(250, 150)))) : CrymbleUI::Text.new("no zone"))
    back = CrymbleUI::WindowPanel.new("B", 200.0, 150.0, 300.0, 200.0, id: "back")
    back.add_child(HookTarget.new(back_log, id: "back_zone").tap(&.add_child(Block.new(CrymbleUI::Size.new(250, 150)))))
    w.add_child(front)
    w.add_child(back)
  end
end

# A grid whose cells are checkboxes, recording the cells toggled - to see a click reach a cell.
private class DriverCheckAdapter < MergeableTestAdapter
  getter toggled = [] of {Int32, Int32}

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Checkbox.new("", checked: false) { @toggled << {row, col} }
  end
end

# Grids for cell drags: each {id, adapter} a `kind` of VirtualMatrix in a panel of its own, the
# panels `step` apart - side by side at 390, overlapping below 380. `configure` runs on every build.
private def grids(*specs : {String, CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter}, kind = CrymbleUI::VirtualMatrix,
                  step = 390.0, &configure : CrymbleUI::VirtualMatrix ->) : CrymbleUI::Testing::Driver
  driver do |window|
    specs.each_with_index do |(id, adapter), i|
      vm = kind.new(adapter: adapter, id: id)
      configure.call(vm)
      panel = CrymbleUI::WindowPanel.new(id, 10.0 + i * step, 10.0, 380.0, 300.0, id: "#{id}_panel")
      panel.add_child(vm)
      window.add_child(panel)
    end
  end
end

private def grids(*specs : {String, CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter}, kind = CrymbleUI::VirtualMatrix,
                  step = 390.0) : CrymbleUI::Testing::Driver
  grids(*specs, kind: kind, step: step) { }
end

# A grid whose right-click handler records the point it is handed.
private def menu_grid(adapter, points : Array(CrymbleUI::Vec2)) : CrymbleUI::Testing::Driver
  grids({"grid", adapter}) do |vm|
    vm.on_right_click_handler = ->(at : CrymbleUI::Vec2) { points << at; nil }
  end
end

private class DriverCounterApp < CrymbleUI::App
  property count = 0
  property build_count = 0

  def build : CrymbleUI::Widget
    @build_count += 1
    root = CrymbleUI::VStack.new(id: "container", spacing: 10.0)
    root.add_child(CrymbleUI::Text.new("Count: #{@count}", id: "counter_text"))
    root.add_child(CrymbleUI::Button.new("+", id: "increment") { @count += 1; request_rebuild })
    root
  end
end

# --- cases --------------------------------------------------------------------------------------

describe CrymbleUI::Testing::Driver do
  describe "context menus (right-click, then an item in the popup)" do
    # The entry case. Mutations: walk only the tree in find (the item lives in an overlay);
    # stop the right-click bubble at the clicked widget.
    it "right-clicks a row, then clicks the menu's item by id" do
      renames = [] of Int32
      ui = context_menu_app(renames)
      ui.right_click "row"
      ui.click "ctx_rename"
      renames.should eq([1])
      ui.present?("ctx_rename").should be_false # the item's action closed its popup
    end

    # Mutation: skip dismiss_popups in the act.
    it "closes the menu when the next act clicks elsewhere" do
      ui = context_menu_app([] of Int32)
      ui.right_click "row"
      ui.present?("ctx_rename").should be_true
      ui.click "row"
      ui.present?("ctx_rename").should be_false
    end

    # Mutation: ignore trigger_right_click's false.
    it "raises when nothing at or above the widget handles a right-click" do
      ui = driver { |w| w.add_child(CrymbleUI::Button.new("lonely", id: "lonely") { }) }
      expect_raises(ArgumentError, /no right-click handler/) { ui.right_click "lonely" }
    end
  end

  describe "lookup" do
    # Mutation: search the overlays before the tree.
    it "resolves an id in both the tree and an overlay to the TREE widget" do
      ui = driver { |w| w.add_child(CrymbleUI::Button.new("tree", id: "twin") { }) }
      twin = CrymbleUI::Button.new("overlay", id: "twin") { }
      popup = CrymbleUI::Popup.new(width: 50.0, height: 20.0, id: "p")
      popup.add_child(twin)
      open_popup(ui, popup)
      ui.text("twin").should eq("tree")
    end

    # Mutation: an empty near-id list.
    it "names the ids that look like a missing one" do
      ui = driver do |w|
        w.add_child(CrymbleUI::Button.new("a", id: "menu_file") { })
        w.add_child(CrymbleUI::Button.new("b", id: "menu_edit") { })
      end
      expect_raises(ArgumentError, /menu_file, menu_edit|menu_edit, menu_file/) { ui.find("menu_view") }
    end

    # Mutation: count every match, ignoring the ancestor rule.
    it "only(prefix) finds the one dialog of a kind, not the fields inside it" do
      ui = driver do |w|
        dialog = CrymbleUI::VStack.new(id: "renamer_17")
        dialog.add_child(CrymbleUI::TextInput.new(value: "", id: "renamer_name"))
        w.add_child(dialog)
      end
      ui.only("renamer_").id.should eq("renamer_17")
      expect_raises(ArgumentError, /0 widgets/) { ui.only("creator_") }
    end

    it "only(prefix) raises on two of a kind" do
      ui = driver do |w|
        w.add_child(CrymbleUI::VStack.new(id: "renamer_1"))
        w.add_child(CrymbleUI::VStack.new(id: "renamer_2"))
      end
      expect_raises(ArgumentError, /2 widgets/) { ui.only("renamer_") }
    end

    # Mutation: ignore the scope.
    it "within scopes lookups to a subtree" do
      ui = driver do |w|
        a = CrymbleUI::VStack.new(id: "left")
        a.add_child(CrymbleUI::Button.new("L", id: "ok") { })
        b = CrymbleUI::VStack.new(id: "right")
        b.add_child(CrymbleUI::Button.new("R", id: "ok") { })
        w.add_child(a)
        w.add_child(b)
      end
      ui.within("right") { ui.text("ok").should eq("R") }
      ui.text("ok").should eq("L")
    end

    # Mutation: resolve each scope from the whole tree instead of inside the one before it.
    it "resolves a nested scope inside the outer one" do
      ui = driver do |w|
        %w(first second).each do |name|
          dialog = CrymbleUI::VStack.new(id: "dialog_#{name}")
          browser = CrymbleUI::VStack.new(id: "browser")
          browser.add_child(CrymbleUI::Button.new(name, id: "row") { })
          dialog.add_child(browser)
          w.add_child(dialog)
        end
      end
      ui.within("dialog_second") { ui.within("browser") { ui.text("row").should eq("second") } }
    end
  end

  describe "clicks" do
    # Mutation: skip the enabled check.
    it "raises on a disabled button instead of doing nothing" do
      fired = 0
      ui = driver do |w|
        b = CrymbleUI::Button.new("go", id: "go") { fired += 1 }
        b.enabled = false
        w.add_child(b)
      end
      expect_raises(ArgumentError, /disabled/) { ui.click "go" }
      fired.should eq(0)
    end

    # A refused user action: real input hands the exception to the app's on_event_exception
    # (SFMLRenderer#handle_event). Mutation: `reported` re-raising regardless.
    it "hands a refusal to the app's on_event_exception inside expect_reported" do
      reported = [] of String
      app = WindowApp.new do |w|
        w.add_child(CrymbleUI::Button.new("boom", id: "boom") { raise "cannot do that here" })
      end
      app.on_event_exception = ->(msg : String) { reported << msg; nil }
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      ui.expect_reported(/cannot do that/) { ui.click "boom" }
      reported.should eq ["cannot do that here"]
    end

    # A spec must never pass over a failed assert inside a handler, although the app has the hook.
    it "stays loud outside expect_reported, even when the app reports exceptions" do
      app = WindowApp.new do |w|
        w.add_child(CrymbleUI::Button.new("boom", id: "boom") { raise "an invariant broke" })
      end
      app.on_event_exception = ->(msg : String) { nil }
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      expect_raises(Exception, "an invariant broke") { ui.click "boom" }
    end

    it "fails expect_reported when nothing, or something else, was reported" do
      app = WindowApp.new do |w|
        w.add_child(CrymbleUI::Button.new("ok", id: "ok") { })
        w.add_child(CrymbleUI::Button.new("boom", id: "boom") { raise "an invariant broke" })
      end
      app.on_event_exception = ->(msg : String) { nil }
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      expect_raises(ArgumentError, /raised nothing/) { ui.expect_reported(/cannot/) { ui.click "ok" } }
      expect_raises(ArgumentError, /not .*an invariant broke/) { ui.expect_reported(/cannot/) { ui.click "boom" } }
    end

    it "never hands its own refusal to the app" do
      app = WindowApp.new { |w| w.add_child(CrymbleUI::Text.new("plain", id: "plain")) }
      app.on_event_exception = ->(msg : String) { raise "the refusal reached the app: #{msg}" }
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /no right-click handler/) do
        ui.expect_reported(/x/) { ui.right_click "plain" }
      end
    end

    # Mutation: no settle after the act.
    it "reads the REBUILT tree after a click that requests a rebuild" do
      count = 0
      app = WindowApp.new do |w|
        w.add_child(CrymbleUI::Text.new("count #{count}", id: "count"))
        w.add_child(CrymbleUI::Button.new("inc", id: "inc") { count += 1; CrymbleUI::Widget.app?.not_nil!.request_rebuild })
      end
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      ui.click "inc"
      ui.text("count").should eq("count 1")
    end

    # Mutation: do not set Widget.app in Driver.new (the handler's request goes nowhere).
    it "is the app handlers reach through Widget.app" do
      count = 0
      app = WindowApp.new do |w|
        w.add_child(CrymbleUI::Text.new("count #{count}", id: "count"))
        w.add_child(CrymbleUI::Button.new("inc", id: "inc") { count += 1; CrymbleUI::Widget.app?.try &.request_rebuild })
      end
      CrymbleUI::Widget.app = TestApp.new # someone else's
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      ui.click "inc"
      ui.text("count").should eq("count 1")
    end

    # Mutation: skip the panel raise in the act.
    it "brings the clicked widget's panel to front" do
      ui = driver do |w|
        back = CrymbleUI::WindowPanel.new("Back", 10.0, 10.0, 200.0, 100.0, id: "back")
        back.add_child(CrymbleUI::Button.new("b", id: "back_button") { })
        front = CrymbleUI::WindowPanel.new("Front", 300.0, 10.0, 200.0, 100.0, id: "front")
        w.add_child(back)
        w.add_child(front)
      end
      front = ui.find("front").as(CrymbleUI::WindowPanel)
      front.bring_to_front
      ui.click "back_button"
      (ui.find("back").as(CrymbleUI::WindowPanel).z_index > ui.find("front").as(CrymbleUI::WindowPanel).z_index).should be_true
    end

    # Mutations: skip dismiss_menus in the act (second half); drop the overlay-surface exemption
    # (first half).
    it "keeps an open menu on a click inside a popup, closes it on a click elsewhere" do
      thing = OpenThing.new
      ui = driver do |w|
        w.add_child(thing)
        w.add_child(CrymbleUI::Button.new("elsewhere", id: "elsewhere") { })
      end
      popup = CrymbleUI::Popup.new(width: 100.0, height: 40.0, id: "pop")
      popup.target_x = 500.0
      popup.target_y = 400.0
      popup.add_child(CrymbleUI::Button.new("inside", id: "inside") { })
      open_popup(ui, popup)
      ui.click "inside"
      thing.open?.should be_true
      ui.click "elsewhere"
      thing.open?.should be_false
    end
  end

  describe "drag" do
    # Mutation: skip retarget in drag_onto (no enter, no leave).
    it "runs start, enter, drop, end and leave, in that order" do
      log = [] of String
      ui = driver do |w|
        w.add_child(HookSource.new(log, id: "src").tap(&.add_child(CrymbleUI::Text.new("field", id: "label"))))
        w.add_child(HookTarget.new(log, id: "zone").tap(&.add_child(CrymbleUI::Text.new("zone"))))
      end
      ui.drag "src", onto: "zone"
      log.should eq(["start", "enter", "drop", "end:true", "leave"])
    end

    # Mutation: search downward only (the id sits on the label INSIDE the draggable).
    it "drags the Draggable at or above the id" do
      log = [] of String
      ui = driver do |w|
        w.add_child(HookSource.new(log, id: "src").tap(&.add_child(CrymbleUI::Text.new("field", id: "label"))))
        w.add_child(HookTarget.new(log, id: "zone").tap(&.add_child(CrymbleUI::Text.new("zone"))))
      end
      ui.drag "label", onto: "zone"
      log.should contain("drop")
    end

    # A target that ACCEPTS the data but sits in a closed panel - end_drag's own accepts_drop?
    # would pass it, so only the refusal check stops it. Mutation: retarget to the target
    # regardless of the refusal.
    it "refuses a target inside a closed panel: raises, tells the source, never drops" do
      log = [] of String
      ui = driver do |w|
        w.add_child(HookSource.new(log, id: "src").tap(&.add_child(CrymbleUI::Text.new("field"))))
        panel = CrymbleUI::WindowPanel.new("Shut", 300.0, 10.0, 200.0, 100.0, id: "shut")
        panel.add_child(HookTarget.new(log, id: "zone").tap(&.add_child(CrymbleUI::Text.new("zone"))))
        w.add_child(panel)
      end
      ui.find("shut").as(CrymbleUI::WindowPanel).closed = true
      ui.can_drop?("src", onto: "zone").should be_false
      expect_raises(ArgumentError, /refused: "shut" is/) { ui.drag "src", onto: "zone" }
      log.should_not contain("drop")
      log.should contain("end:false")
    end

    # Mutations: ask accept_reason while pruning (a real drag misses the inner zone); apply it to
    # ancestors (the Driver refuses it).
    it "takes an accepting zone nested inside a refusing one - by id and by a real drag" do
      log = [] of String
      ui = driver do |w|
        w.add_child(HookSource.new(log, id: "src").tap(&.add_child(CrymbleUI::Text.new("field"))))
        outer = HookTarget.new(log, accepts: ["other"], id: "outer")
        outer.add_child(HookTarget.new(log, id: "inner").tap(&.add_child(CrymbleUI::Text.new("inner"))))
        w.add_child(outer)
      end
      ui.drag "src", onto: "inner"
      log.count("drop").should eq(1)

      src = ui.find("src").viewport_bounds.center
      inner = ui.find("inner").viewport_bounds.center
      ui.renderer.simulate_drag(src.x, src.y, inner.x, inner.y)
      log.count("drop").should eq(2)
    end

    # Mutation: stop the drop search at the first DropTarget on the way up - the refusing inner zone
    # would end it.
    it "gives a refusing zone's drop to the accepting zone around it, on a real drag" do
      log = [] of String
      ui = driver do |w|
        w.add_child(HookSource.new(log, id: "src").tap(&.add_child(CrymbleUI::Text.new("field"))))
        outer = HookTarget.new(log, id: "outer")
        outer.add_child(HookTarget.new(log, accepts: ["other"], id: "inner").tap(&.add_child(CrymbleUI::Text.new("inner"))))
        w.add_child(outer)
      end
      src = ui.find("src").viewport_bounds.center
      inner = ui.find("inner").viewport_bounds.center
      ui.renderer.simulate_drag(src.x, src.y, inner.x, inner.y)
      log.count("drop").should eq(1)
    end

    # Mutation: find the drop target in tree order - the later panel's zone takes the drop.
    it "drops into the panel in front, not the one behind it, on a real drag" do
      front_log = [] of String
      back_log = [] of String
      ui = overlapping_zones(front_log, back_log, front_zone: true)
      ui.find("front").as(CrymbleUI::WindowPanel).bring_to_front
      ui.settle
      at = CrymbleUI::Vec2.new(275.0, 230.0)
      {"front_zone", "back_zone"}.each { |z| ui.find(z).viewport_bounds.contains_point(at).should be_true } # instrument
      src = ui.find("src").viewport_bounds.center
      ui.renderer.simulate_drag(src.x, src.y, at.x, at.y)
      front_log.count("drop").should eq(1)
      back_log.count("drop").should eq(0)
    end

    # Mutation: search the panels for a zone instead of asking the hit test - the drop falls through
    # the front panel to the zone behind it.
    it "drops nowhere where the panel in front has no zone, on a real drag" do
      front_log = [] of String
      back_log = [] of String
      ui = overlapping_zones(front_log, back_log, front_zone: false)
      ui.find("front").as(CrymbleUI::WindowPanel).bring_to_front
      ui.settle
      at = CrymbleUI::Vec2.new(275.0, 230.0)
      ui.find("back_zone").viewport_bounds.contains_point(at).should be_true               # instrument
      ui.find("front").as(CrymbleUI::WindowPanel).viewport_bounds.contains_point(at).should be_true
      src = ui.find("src").viewport_bounds.center
      ui.renderer.simulate_drag(src.x, src.y, at.x, at.y)
      back_log.count("drop").should eq(0)
    end

    # Mutation: apply the self rule to the target only (not its ancestors).
    it "refuses a target inside the source" do
      log = [] of String
      ui = driver do |w|
        src = HookSource.new(log, id: "src")
        src.add_child(HookTarget.new(log, id: "zone_in_source").tap(&.add_child(CrymbleUI::Text.new("z"))))
        w.add_child(src)
      end
      expect_raises(ArgumentError, /drag source/) { ui.drag "src", onto: "zone_in_source" }
    end

    # Mutation: skip the "no drag data" check in drag_onto.
    it "raises when the source gives no drag data" do
      log = [] of String
      ui = driver do |w|
        w.add_child(HookSource.new(log, id: "src", data: nil).tap(&.add_child(CrymbleUI::Text.new("field"))))
        w.add_child(HookTarget.new(log, id: "zone").tap(&.add_child(CrymbleUI::Text.new("zone"))))
      end
      expect_raises(ArgumentError, /no drag data/) { ui.drag "src", onto: "zone" }
      log.should_not contain("drop")
    end
  end

  describe "keyboard" do
    # Mutation: skip the focusable check (the text would go to whatever has focus).
    it "raises when typing into a widget that cannot take focus" do
      ui = driver { |w| w.add_child(CrymbleUI::Text.new("label", id: "label")) }
      expect_raises(ArgumentError, /not focusable/) { ui.type "label", "x" }
    end

    it "types into a text input" do
      ui = driver { |w| w.add_child(CrymbleUI::TextInput.new(value: "", id: "name")) }
      ui.type "name", "Area"
      ui.text("name").should eq("Area")
    end

    # Mutations: drop the modifier; skip the focus of `on:`.
    it "presses a chord on the widget named by on:" do
      ui = driver do |w|
        w.add_child(KeyRecorder.new("keys"))
        w.add_child(KeyRecorder.new("other"))
      end
      CrymbleUI::Widget.focus_manager.focus(ui.find("other"))
      ui.press "Ctrl+S", on: "keys"
      ui.find("keys").as(KeyRecorder).keys.should contain("Ctrl+S")
      ui.focused_id.should eq("keys")
    end

    it "raises on an unknown key name" do
      ui = driver { |w| w.add_child(KeyRecorder.new("keys")) }
      expect_raises(ArgumentError, /unknown key "Esc"/) { ui.press "Esc", on: "keys" }
    end
  end

  describe "reads" do
    # Mutation: read only Text widgets (the Button and TextInput answer "").
    it "reads a Text, a Button's label, a TextInput's value, and a container's texts in order" do
      ui = driver do |w|
        bar = CrymbleUI::HStack.new(id: "statusbar")
        bar.add_child(CrymbleUI::Text.new("Renamed", id: "msg"))
        bar.add_child(CrymbleUI::Text.new("3 fields"))
        w.add_child(bar)
        w.add_child(CrymbleUI::Button.new("Save", id: "save") { })
        w.add_child(CrymbleUI::TextInput.new(value: "Area", id: "input"))
      end
      ui.text("msg").should eq("Renamed")
      ui.text("save").should eq("Save")
      ui.text("input").should eq("Area")
      ui.text("statusbar").should eq("Renamed 3 fields")
    end

    # Mutation: return an empty list from Menu#items.
    it "lists a closed menu's items" do
      ui = driver do |w|
        bar = CrymbleUI::MenuBar.new(id: "bar")
        menu = CrymbleUI::Menu.new("File", id: "file")
        menu.add_child(CrymbleUI::MenuItem.new("Load", id: "mi_load")) # moved into the menu at layout
        bar.add_child(menu)
        w.add_child(bar)
      end
      ui.find("file").as(CrymbleUI::Menu).items.compact_map(&.id).should eq(["mi_load"])
    end

    # Mutation: drop the StatusBar branch (it keeps its text in a property, not a Text child).
    it "reads a widget's own text property - a status bar's" do
      ui = driver { |w| w.add_child(CrymbleUI::StatusBar.new("Committed", id: "status")) }
      ui.text("status").should eq("Committed")
    end

    # Mutation: drop the Checkbox branch (it draws its label from a property, not a Text child).
    it "reads a checkbox's label" do
      ui = driver { |w| w.add_child(CrymbleUI::Checkbox.new("Milk", checked: false, id: "done")) }
      ui.text("done").should eq("Milk")
    end

    # Mutation: drop the ComboBox branch (it paints its value, no Text child: it read "").
    it "reads a combo box's selected value" do
      ui = driver { |w| w.add_child(CrymbleUI::ComboBox.new(["Graz", "Linz"], selected: 1, id: "city")) }
      ui.text("city").should eq("Linz")
    end

    # Mutation: return a constant from each.
    it "reads enabled, checked and presence" do
      ui = driver do |w|
        off = CrymbleUI::Button.new("off", id: "off") { }
        off.enabled = false
        w.add_child(off)
        w.add_child(CrymbleUI::Button.new("on", id: "on") { })
        w.add_child(CrymbleUI::Checkbox.new("c", checked: true, id: "box"))
      end
      ui.enabled?("off").should be_false
      ui.enabled?("on").should be_true
      ui.checked?("box").should be_true
      ui.present?("on").should be_true
      ui.present?("gone").should be_false
    end

    # A tri-state box (checkbox(state:)) draws its CheckState, not the Bool. Mutation: read only `checked`.
    it "reads a tri-state checkbox by what it shows" do
      ui = driver do |w|
        w.add_child(CrymbleUI::Checkbox.new("a", check_state: CrymbleUI::CheckState::Checked, id: "on"))
        w.add_child(CrymbleUI::Checkbox.new("b", check_state: CrymbleUI::CheckState::Indeterminate, id: "some"))
        w.add_child(CrymbleUI::Checkbox.new("c", check_state: CrymbleUI::CheckState::Unchecked, id: "off"))
      end
      ui.checked?("on").should be_true
      ui.checked?("some").should be_false # partly is not checked
      ui.checked?("off").should be_false
    end
  end

  describe "hover and time" do
    # Mutation: skip update_hover.
    it "hovers a widget through the app's hover path" do
      ui = driver { |w| w.add_child(CrymbleUI::Button.new("h", id: "hovered") { }) }
      ui.hover "hovered"
      ui.app.hovered_widget.try(&.id).should eq("hovered")
    end

    # Mutation: skip the hit check.
    it "raises when something covers the widget at its centre" do
      ui = driver { |w| w.add_child(CrymbleUI::Button.new("under", id: "under") { }) }
      under = ui.find("under").viewport_bounds
      popup = CrymbleUI::Popup.new(width: under.width + 20, height: under.height + 20, id: "cover")
      popup.target_x = under.x - 10
      popup.target_y = under.y - 10
      open_popup(ui, popup)
      expect_raises(ArgumentError, /covered/) { ui.hover "under" }
    end

    # Mutations: skip running the timers; measure from Time.instant on every call.
    it "advances time, accumulating across calls" do
      ui = driver { |w| w.add_child(CrymbleUI::Text.new("t")) }
      fired = 0
      ui.renderer.scheduler.schedule(1.5.seconds) { fired += 1 }
      ui.advance(1.0)
      fired.should eq(0)
      ui.advance(1.0)
      fired.should eq(1)
    end
  end

  describe "grids and file browsers" do
    # Mutations: skip the reveal; resolve to row 0; forget the +1 for the header row.
    it "opens a file below the fold, by name" do
      opened = [] of String
      ui = browser(opened, [] of String)
      ui.open_file "files", "f27.emb"
      opened.should eq(["f27.emb"])
    end

    # Mutations: click twice; click the row's widget instead of pressing the grid (the press never arms).
    it "selects a file with one click, through the grid's own press" do
      opened = [] of String
      selected = [] of String
      ui = browser(opened, selected)
      ui.find("files").as(CrymbleUI::VirtualMatrix).double_click_interval = 1.hour # the armed click must not time out
      ui.select_file "files", "f03.emb"
      selected.should eq(["f03.emb"])
      opened.should be_empty
      ui.find("files").as(CrymbleUI::VirtualMatrix).double_click?({4, 0}).should be_true # row 0 the header, 1 "sub/"
    end

    # The second click on a row is a double-click to the grid or not, as the clock has it: it opens either
    # way. Mutation: refuse the second press as a double-click.
    it "opens a file whether the grid counts the second click as a double-click or not" do
      [1.hour, 0.seconds].each do |interval|
        opened = [] of String
        ui = browser(opened, [] of String)
        ui.find("files").as(CrymbleUI::VirtualMatrix).double_click_interval = interval
        ui.open_file "files", "f05.emb"
        opened.should eq(["f05.emb"])
      end
    end

    # Mutation: ignore the directory segments.
    it "opens a file inside a directory" do
      opened = [] of String
      ui = browser(opened, [] of String)
      ui.open_file "files", "sub/inner.emb"
      opened.should eq(["inner.emb"])
    end

    # Mutation: skip snap_to_cursor (the cell is never materialized).
    it "reads what an off-screen cell displays" do
      ui = browser([] of String, [] of String)
      ui.cell_text("files", 28, 0).should eq("f27.emb")
    end

    # Mutation: look the cell up by the cursor (clamped) instead of the requested cell.
    it "raises for a cell outside the matrix" do
      ui = browser([] of String, [] of String)
      expect_raises(ArgumentError, /no cell/) { ui.cell_text("files", 99, 0) }
    end

    # Mutations: remove the check from right_click / from drag / test only the id itself; swap the
    # two acts' hints.
    it "refuses acts that would go through a matrix's cell under the mouse" do
      ui = browser([] of String, [] of String)
      ui.find("files").on_right_click_handler = ->(_p : CrymbleUI::Vec2) { nil }
      expect_raises(ArgumentError, /VirtualMatrix.*right_click_cell/) { ui.right_click "files" }
      ui.focus_cell "files", 1, 0
      expect_raises(ArgumentError, /VirtualMatrix/) { ui.right_click "dirbrowser_item_0" }
      log = [] of String
      window_of(ui).add_child(HookSource.new(log, id: "src").tap(&.add_child(CrymbleUI::Text.new("s"))))
      ui.settle
      expect_raises(ArgumentError, /VirtualMatrix.*drag_cell/) { ui.drag "src", onto: "files" }
      expect_raises(ArgumentError, /VirtualMatrix/) { ui.can_drop? "src", onto: "files" }
    end

    # The grid takes every press and keeps the focus, so a widget inside it is never clicked or focused on its
    # own - the grid itself is. Mutations: remove the check from click / from focusable / from hover; test the id
    # itself too.
    it "refuses a click, a key or a hover on a widget inside a grid, takes them on the grid" do
      selected = [] of String
      ui = browser([] of String, selected)
      ui.focus_cell "files", 2, 0
      expect_raises(ArgumentError, /VirtualMatrix.*click_cell/) { ui.click "dirbrowser_item_1" }
      expect_raises(ArgumentError, /VirtualMatrix.*focus_cell/) { ui.press "Enter", on: "dirbrowser_item_1" }
      expect_raises(ArgumentError, /VirtualMatrix.*focus_cell/) { ui.type "dirbrowser_item_1", "x" }
      expect_raises(ArgumentError, /hover on "dirbrowser_item_1" goes through a VirtualMatrix/) { ui.hover "dirbrowser_item_1" }
      selected.should be_empty # instrument: the refused click reached nothing
      ui.click "files" # the click a release over the grid makes: to its cursor cell
      selected.should eq(["f01.emb"])
      ui.press "Down", on: "files"
      ui.cursor("files").should eq({3, 0})
      ui.hover "files"
    end
  end

  describe "cell clicks" do
    # Mutation: skip the press - the grid never hears it (the reveal alone moves the cursor there too).
    it "puts the cursor on the clicked cell, through the grid's own press" do
      ui = grids({"grid", MergeableTestAdapter.new(8, 4)})
      ui.find("grid").as(CrymbleUI::VirtualMatrix).double_click_interval = 1.hour # the armed click must not time out
      ui.click_cell "grid", 3, 2
      ui.cursor("grid").should eq({3, 2})
      ui.find("grid").as(CrymbleUI::VirtualMatrix).double_click?({3, 2}).should be_true # only a press arms it
    end

    # Mutation: skip trigger_click on the release - the checkbox never hears the click.
    it "clicks the cell's widget, as the release over the grid does - a checkbox toggles" do
      adapter = DriverCheckAdapter.new(8, 4)
      ui = grids({"grid", adapter})
      ui.click_cell "grid", 2, 1
      adapter.toggled.should eq([{2, 1}])
    end

    # A cell the sticky header band hides is brought into view first, then clicked. Mutation: skip the
    # reveal - the press lands on the header cell over it (refused, naming it).
    it "reveals a cell the sticky header band hides, then clicks it" do
      ui = grids({"grid", ConfigurableMatrixAdapter.new(1, 1, 30, 2, 1, 1)})
      ui.focus_cell "grid", 20, 1
      vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
      hidden = vm.active_cells.keys.select { |(r, c)| r >= 1 && c == 1 }.find do |cell|
        x, w = vm.painted_col(cell[1])
        y, h = vm.painted_row(cell[0])
        at = vm.viewport_bounds.position + CrymbleUI::Vec2.new(x + w / 2, y + h / 2) # its line centre, in the window
        vm.point_to_cell(at).try(&.[0]) == 0
      end
      hidden = hidden.should_not be_nil # instrument: a data cell's centre lies under the header band
      ui.click_cell "grid", hidden[0], hidden[1]
      ui.cursor("grid").should eq(hidden)
    end

    # Mutation: drop the double-click refusal - the second press activates the cell.
    it "refuses a second click on the same cell as a double-click" do
      ui = grids({"grid", MergeableTestAdapter.new(8, 4)})
      ui.find("grid").as(CrymbleUI::VirtualMatrix).double_click_interval = 1.hour
      ui.click_cell "grid", 2, 1
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /double-click.*click another cell/) do
        ui.click_cell "grid", 2, 1
      end
    end
  end

  describe "cell right-clicks" do
    # Red before right_click_cell existed. The handler gets the press point in window space; that differs
    # from the grid's own space only under a scrolled ancestor - event_point_space_spec pins that half.
    it "runs the grid's right-click handler for the cell, at the press point in window space" do
      points = [] of CrymbleUI::Vec2
      ui = menu_grid(MergeableTestAdapter.new(8, 4), points)
      ui.right_click_cell "grid", 3, 2
      ui.cursor("grid").should eq({3, 2})
      points.size.should eq(1)
      vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
      cell = vm.active_cells[{3, 2}].viewport_bounds
      cell.contains_point(points.first).should be_true # window space: on the cell as painted
    end

    # Mutation: keep the double-click pre-check for a right press.
    it "opens the menu on the cell just clicked - a right press is never a double-click" do
      points = [] of CrymbleUI::Vec2
      ui = menu_grid(MergeableTestAdapter.new(8, 4), points)
      ui.find("grid").as(CrymbleUI::VirtualMatrix).double_click_interval = 1.hour
      ui.click_cell "grid", 2, 1
      ui.right_click_cell "grid", 2, 1
      points.size.should eq(1)
    end

    # Mutation: trigger a click on every release - the checkbox would toggle.
    it "opens the menu on a checkbox cell without toggling it" do
      points = [] of CrymbleUI::Vec2
      adapter = DriverCheckAdapter.new(8, 4)
      ui = menu_grid(adapter, points)
      ui.right_click_cell "grid", 2, 1
      points.size.should eq(1)
      adapter.toggled.should be_empty
    end
  end

  describe "cell drags" do
    # Red before drag_cell existed.
    it "moves a cell onto another cell of the same grid" do
      adapter = MergeableTestAdapter.new(8, 4)
      ui = grids({"grid", adapter})
      ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
      adapter.moves.should eq([{ {1, 1}, {3, 1} }])
    end

    # Mutation: on_drop puts the cursor on the drop target instead of the cell the move returned.
    it "leaves the cursor where the adapter placed the moved cell" do
      adapter = MergeableTestAdapter.new(8, 4)
      adapter.move_result = {5, 2}
      ui = grids({"grid", adapter})
      ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
      ui.cursor("grid").should eq({5, 2})
    end

    # Mutation: drop onto the source grid instead of the target - the source's adapter moves.
    it "hands a drop from another grid to the target's cross-drop handler" do
      a = MergeableTestAdapter.new(8, 4)
      b = MergeableTestAdapter.new(8, 4)
      received = [] of {Int32, Int32, Int32, Int32}
      ui = grids({"a", a}, {"b", b}) do |vm|
        vm.drag_owner_key = vm.id
        vm.cross_drop_handler = ->(data : CrymbleUI::CellDragData, r : Int32, c : Int32) { received << {data.row, data.col, r, c}; nil }
      end
      ui.drag_cell "a", 1, 1, onto: {"b", 2, 2}
      received.should eq([{1, 1, 2, 2}])
      a.moves.should be_empty
      b.moves.should be_empty
    end

    # Mutation: drop the drag-data check - drag_onto's own "gave no drag data" reason surfaces instead.
    it "refuses an empty source cell" do
      adapter = MergeableTestAdapter.new(8, 4)
      adapter.empty_cells << {1, 1}
      ui = grids({"grid", adapter})
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /1,1 has no content to drag/) do
        ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
      end
      adapter.moves.should be_empty
    end

    # A cell from ANOTHER grid names a place in that grid's data: the target never applies it as its own move.
    # Mutation: accept any CellDragData - b moves its own 1,1 (the coordinates of a's cell).
    it "refuses a cell from another untagged grid" do
      a, b = MergeableTestAdapter.new(8, 4), MergeableTestAdapter.new(8, 4)
      ui = grids({"a", a}, {"b", b})
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /was refused: .*does not accept/) do
        ui.drag_cell "a", 1, 1, onto: {"b", 3, 1}
      end
      a.moves.should be_empty
      b.moves.should be_empty
    end

    # The host's claim: grids with one owner key are one owner's. Mutation: own_payload? comparing paths only.
    it "moves natively between grids the host gives one owner key" do
      a, b = MergeableTestAdapter.new(8, 4), MergeableTestAdapter.new(8, 4)
      handed = [] of {Int32, Int32}
      ui = grids({"a", a}, {"b", b}) do |vm|
        vm.drag_owner_key = "one"
        vm.cross_drop_handler = ->(_d : CrymbleUI::CellDragData, r : Int32, c : Int32) { handed << {r, c}; nil }
      end
      ui.drag_cell "a", 1, 1, onto: {"b", 3, 1}
      b.moves.should eq([{ {1, 1}, {3, 1} }])
      a.moves.should be_empty
      handed.should be_empty
    end

    # Another owner's cell with nowhere to route it: refused, and the source's committed mark stays - today it
    # was "dropped" (nothing happened) and the drag's end cleared the host's cut. Mutation: accept a tagged
    # foreign payload without a handler.
    it "refuses another owner's cell where no handler takes it, keeping the source's mark" do
      a, b = MergeableTestAdapter.new(8, 4), MergeableTestAdapter.new(8, 4)
      ui = grids({"a", a}, {"b", b}) { |vm| vm.drag_owner_key = vm.id }
      ui.find("a").as(CrymbleUI::VirtualMatrix).drag_source_cell = {5, 1}
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /does not accept/) do
        ui.drag_cell "a", 1, 1, onto: {"b", 3, 1}
      end
      a.moves.should be_empty
      b.moves.should be_empty
      src = ui.find("a").as(CrymbleUI::VirtualMatrix)
      (src.drag_source_provisional? ? nil : src.drag_source_cell).should eq({5, 1})
    end

    # A grid's own cell is its own, handler or not. Mutation: route to the handler whenever one is set.
    it "moves a tagged grid's own cell natively, not through its cross handler" do
      a = MergeableTestAdapter.new(8, 4)
      handed = [] of {Int32, Int32}
      ui = grids({"a", a}) do |vm|
        vm.drag_owner_key = "one"
        vm.cross_drop_handler = ->(_d : CrymbleUI::CellDragData, r : Int32, c : Int32) { handed << {r, c}; nil }
      end
      ui.drag_cell "a", 1, 1, onto: {"a", 3, 1}
      a.moves.should eq([{ {1, 1}, {3, 1} }])
      handed.should be_empty
    end

    # A cross handler routes OTHER OWNERS' cells; an untagged cell has no owner to route to. Mutation: the
    # handler taking any foreign payload.
    it "refuses an untagged cell on a grid with a cross handler" do
      a, b = MergeableTestAdapter.new(8, 4), MergeableTestAdapter.new(8, 4)
      handed = [] of {Int32, Int32}
      ui = grids({"a", a}, {"b", b}) do |vm|
        next unless vm.id == "b"
        vm.drag_owner_key = "b"
        vm.cross_drop_handler = ->(_d : CrymbleUI::CellDragData, r : Int32, c : Int32) { handed << {r, c}; nil }
      end
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /does not accept/) do
        ui.drag_cell "a", 1, 1, onto: {"b", 3, 1}
      end
      handed.should be_empty
      b.moves.should be_empty
    end

    # Two grids WITHOUT ids side by side, driven by real App input (the Driver names grids by id): each is its
    # own - reconcile tells them apart by index, and so does the payload. Mutation: identity by path_id (the
    # two share ".../VirtualMatrix").
    it "tells two id-less sibling grids apart" do
      a, b = MergeableTestAdapter.new(8, 4), MergeableTestAdapter.new(8, 4)
      ui = driver do |window|
        panel = CrymbleUI::WindowPanel.new("P", 10.0, 10.0, 780.0, 300.0, id: "panel")
        row = CrymbleUI::HStack.new(spacing: 10.0, id: "row")
        row.add_child(CrymbleUI::VirtualMatrix.new(adapter: a))
        row.add_child(CrymbleUI::VirtualMatrix.new(adapter: b))
        panel.add_child(row)
        window.add_child(panel)
      end
      ga, gb = ui.find("row").children.map(&.as(CrymbleUI::VirtualMatrix))
      app = ui.app
      drag = ->(from : CrymbleUI::Vec2, to : CrymbleUI::Vec2) {
        app.handle_mouse_down(from)
        app.handle_mouse_move(from + CrymbleUI::Vec2.new(0.0, 12.0))
        app.handle_mouse_move(to)
        app.drag_manager.dragging?.should be_true # instrument: the drag started
        app.handle_mouse_up(to)
        ui.settle
      }
      drag.call(ga.active_cells[{1, 1}].viewport_bounds.center, gb.active_cells[{3, 1}].viewport_bounds.center)
      a.moves.should be_empty
      b.moves.should be_empty
      ga, gb = ui.find("row").children.map(&.as(CrymbleUI::VirtualMatrix))
      # control: its own cell still moves (another cell - a second press on 1,1 now would be a double-click)
      drag.call(ga.active_cells[{2, 1}].viewport_bounds.center, ga.active_cells[{4, 1}].viewport_bounds.center)
      a.moves.should eq([{ {2, 1}, {4, 1} }])
    end

    # The drop reaches the grid a rebuild put in place of the one the drag started on - the same grid to the
    # user. The grid has no id, so its identity is its index and class, recomputed on the rebuilt grid.
    # Mutations: identity by instance (object_id); an id-less segment made per instance.
    it "moves an id-less grid's own cell after a rebuild during the drag" do
      a = MergeableTestAdapter.new(8, 4)
      ui = driver do |window|
        panel = CrymbleUI::WindowPanel.new("P", 10.0, 10.0, 380.0, 300.0, id: "panel")
        row = CrymbleUI::HStack.new(spacing: 10.0, id: "row")
        row.add_child(CrymbleUI::VirtualMatrix.new(adapter: a))
        panel.add_child(row)
        window.add_child(panel)
      end
      app = ui.app
      before = ui.find("row").children.first.as(CrymbleUI::VirtualMatrix)
      from = before.active_cells[{1, 1}].viewport_bounds.center
      to = before.active_cells[{3, 1}].viewport_bounds.center
      app.handle_mouse_down(from)
      app.handle_mouse_move(from + CrymbleUI::Vec2.new(0.0, 12.0))
      app.drag_manager.dragging?.should be_true # instrument: active before the rebuild
      app.request_rebuild
      ui.settle
      after = ui.find("row").children.first
      after.same?(before).should be_false                # instrument: replaced
      {after.id, after.class}.should eq({nil, before.class}) # id-less, at the same index, of the same class
      app.handle_mouse_move(to)
      app.handle_mouse_up(to)
      a.moves.should eq([{ {1, 1}, {3, 1} }])
    end

    # Mutations: drop the release (the source stays pressed, the next press reads it as pre-existing);
    # release even after a started drag (a mouse-up real input never sends).
    it "releases a press that did not become a drag, and only that one" do
      adapter = MergeableTestAdapter.new(40, 4)
      # One owner for both grids, so b would take a's cell - `b.accepts` alone refuses it below.
      ui = grids({"a", adapter}, {"b", MergeableTestAdapter.new(40, 4)}, kind: DriverCountingMatrix) { |vm| vm.drag_owner_key = "one" }
      ui.app.on_event_exception = ->(_msg : String) { nil }
      a, b = ui.find("a").as(DriverCountingMatrix), ui.find("b").as(DriverCountingMatrix)
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /not on screen/) do
        ui.drag_cell "a", 1, 1, onto: {"a", 39, 1}
      end
      a.ups.should eq(1)
      a.drag_source_cell.should be_nil
      b.accepts = false
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /was refused: .*does not accept/) do
        ui.drag_cell "a", 2, 1, onto: {"b", 2, 1} # the drag starts, the target refuses it
      end
      a.ups.should eq(1)
      a.drag_source_cell.should be_nil # end_drag cleared it
      adapter.move_error = "no such move" # a drag that starts, then fails in the drop
      ui.expect_reported("no such move") { ui.drag_cell "a", 3, 1, onto: {"a", 5, 1} }
      a.ups.should eq(1)
      a.drag_source_cell.should be_nil # end_drag cleared it
    end

    # Mutation: drop the on-screen check - a cell materialized below the fold takes the drop.
    it "refuses a target that is materialized but below the visible area" do
      adapter = MergeableTestAdapter.new(60, 4)
      ui = grids({"grid", adapter})
      vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
      bottom = ui.find("grid_panel").viewport_bounds.bottom
      below = vm.active_cells.keys.select { |(r, c)| c == 1 && vm.active_cells[{r, c}].viewport_bounds.y > bottom }.min_by?(&.[0])
      below = below.should_not be_nil # instrument: the grid keeps cells beyond its viewport
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /not on screen/) do
        ui.drag_cell "grid", 1, 1, onto: {"grid", below[0], below[1]}
      end
      adapter.moves.should be_empty
    end

    # Mutation: treat any refusing target as refused, whatever else the drop reaches - the grid in
    # front would take it in real input.
    it "refuses a refusing target covered by another grid as covered, not as refused" do
      a = MergeableTestAdapter.new(8, 4)
      ui = grids({"a", a}, {"b", MergeableTestAdapter.new(8, 4)}, kind: DriverCountingMatrix, step: 190.0)
      bv = ui.find("b").as(DriverCountingMatrix)
      bv.accepts = false
      a_right = ui.find("a_panel").viewport_bounds.right
      covered = bv.active_cells.keys.find { |(r, c)| r == 2 && bv.active_cells[{r, c}].viewport_bounds.center.x < a_right }
      covered = covered.should_not be_nil # instrument: b overlaps a
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /is covered: a drop at its centre reaches .*"a"/) do
        ui.drag_cell "a", 1, 1, onto: {"b", covered[0], covered[1]}
      end
      a.moves.should be_empty
    end

    # Mutation: search the tree for the drop target instead of starting from the hit test - the drop
    # passes through the panel in front.
    it "refuses a target behind a panel that is no drop target, as a click there would miss it" do
      b = MergeableTestAdapter.new(8, 4)
      ui = grids({"a", MergeableTestAdapter.new(8, 4)}, {"b", b}) { |vm| vm.drag_owner_key = "one" } # b would take a's cell
      bv = ui.find("b").as(CrymbleUI::VirtualMatrix)
      panel = ui.find("b_panel").viewport_bounds
      cover = CrymbleUI::WindowPanel.new("cover", panel.x, panel.y + 60.0, panel.width, 60.0, id: "cover")
      cover.add_child(CrymbleUI::Text.new("on top"))
      window_of(ui).add_child(cover)
      cover.bring_to_front
      ui.settle
      target = bv.active_cells.keys.find { |(r, c)| c == 1 && cover.viewport_bounds.contains_point(bv.active_cells[{r, c}].viewport_bounds.center) }
      target = target.should_not be_nil # instrument: the panel lies over a cell of b
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /is covered: a drop at its centre reaches nothing/) do
        ui.drag_cell "a", 1, 1, onto: {"b", target[0], target[1]}
      end
      b.moves.should be_empty
    end

    # Mutation: check the target before the act (the press brings the source's panel to front, which then
    # covers the target).
    it "refuses a target the source's panel covers once it comes to front" do
      a = MergeableTestAdapter.new(8, 4)
      b = MergeableTestAdapter.new(8, 4)
      ui = grids({"a", a}, {"b", b}, step: 190.0)
      bv = ui.find("b").as(CrymbleUI::VirtualMatrix)
      a_right = ui.find("a_panel").viewport_bounds.right
      covered = bv.active_cells.keys.find { |(r, c)| r == 2 && bv.active_cells[{r, c}].viewport_bounds.center.x < a_right }
      covered = covered.should_not be_nil # instrument: b overlaps a
      centre = bv.active_cells[covered].viewport_bounds.center
      ui.app.root.not_nil!.hit_test(centre).should be(bv) # instrument: b is on top before the drag
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /is covered: a drop at its centre reaches .*"a"/) do
        ui.drag_cell "a", 1, 1, onto: {"b", covered[0], covered[1]}
      end
      b.moves.should be_empty
    end

    # A target wholly under the band has nothing painted to drop on. Mutation: aim at the cell's laid-out rect -
    # the drop lands on the sticky header cell over it.
    it "refuses a target lying under a sticky header band" do
      ui = grids({"grid", ConfigurableMatrixAdapter.new(1, 1, 30, 2, 1, 1)})
      ui.focus_cell "grid", 20, 1 # scrolls the data under the sticky header row
      vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
      hidden = vm.active_cells.keys.select { |(r, c)| r >= 1 && c == 1 }.find do |cell|
        x, w = vm.painted_col(cell[1])
        y, h = vm.painted_row(cell[0])
        at = vm.viewport_bounds.position + CrymbleUI::Vec2.new(x + w / 2, y + h / 2) # its line centre, in the window
        vm.point_to_cell(at).try(&.[0]) == 0
      end
      hidden = hidden.should_not be_nil # instrument: a data cell's centre lies under the header band
      vm.painted_rect({hidden, hidden}).should be_nil # instrument: wholly under the band
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /#{hidden[0]},1 is not on screen/) do
        ui.drag_cell "grid", 20, 1, onto: {"grid", hidden[0], hidden[1]}
      end
    end

    # Mutation: drop the double-click pre-check - the press activates the cell instead.
    it "refuses a press that would be the second click of a double-click, without activating" do
      adapter = MergeableTestAdapter.new(8, 4)
      activated = [] of {Int32, Int32}
      ui = grids({"grid", adapter}) do |vm|
        vm.on_cell_activate = ->(rc : {Int32, Int32}) { activated << rc; true }
      end
      vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
      vm.double_click_interval = 1.hour
      ui.app.request_rebuild
      ui.settle
      ui.find("grid").as(CrymbleUI::VirtualMatrix).double_click_interval.should eq(1.hour) # carried across the rebuild
      ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /double-click/) do
        ui.drag_cell "grid", 1, 1, onto: {"grid", 4, 1}
      end
      activated.should be_empty
      adapter.moves.should eq([{ {1, 1}, {3, 1} }])
    end

    # Mutation: drop the distance check - a click becomes cell_move onto itself.
    it "refuses a drag onto its own cell" do
      adapter = MergeableTestAdapter.new(8, 4)
      ui = grids({"grid", adapter})
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /where the drag starts/) do
        ui.drag_cell "grid", 1, 1, onto: {"grid", 1, 1}
      end
      adapter.moves.should be_empty
    end

    # Mutation: aim at the merged widget's centre - it lies in another row of the merge.
    it "drags a merged cell by its top-left, and refuses a cell inside it" do
      adapter = MergeableTestAdapter.new(8, 4)
      adapter.add_merge({1, 1}, {3, 1})
      ui = grids({"grid", adapter})
      expect_raises(ArgumentError, /2,1 lies inside the merged cell at 1,1/) { ui.drag_cell "grid", 2, 1, onto: {"grid", 5, 1} }
      ui.drag_cell "grid", 1, 1, onto: {"grid", 5, 1}
      adapter.moves.should eq([{ {1, 1}, {5, 1} }])
    end

    # Mutation: aim with absolute_bounds (unscrolled) instead of where the cell is painted.
    it "drags in a scrolled grid" do
      adapter = MergeableTestAdapter.new(60, 4)
      ui = grids({"grid", adapter})
      ui.focus_cell "grid", 40, 1
      ui.find("grid").as(CrymbleUI::VirtualMatrix).scroll_offset.y.should be > 0.0 # instrument
      ui.drag_cell "grid", 40, 1, onto: {"grid", 38, 1}
      adapter.moves.should eq([{ {40, 1}, {38, 1} }])
    end

    # A drop target is handed its own space (DragManager converts), so a grid in a scrolled view takes the drop
    # on the cell under the pointer. Mutation: DragManager handing on_drop the window point.
    it "drags onto a grid inside a scrolled view" do
      adapter = MergeableTestAdapter.new(4, 3)
      ui = driver do |window|
        sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical, id: "sv")
        stack = CrymbleUI::VStack.new(spacing: 0.0)
        5.times { |i| stack.add_child(CrymbleUI::Text.new("above #{i}")) } # room to scroll the grid by more than half a row
        vm = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "grid")
        vm.shrink_to_content = true
        stack.add_child(vm)
        60.times { |i| stack.add_child(CrymbleUI::Text.new("below #{i}")) }
        sv.set_content(stack)
        window.add_child(sv)
      end
      ui.find("sv").as(CrymbleUI::ScrollView).set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 30.0))
      ui.settle
      grid = ui.find("grid")
      grid.viewport_bounds.y.should_not eq(grid.absolute_bounds.y) # instrument: really scrolled
      ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
      adapter.moves.should eq([{ {1, 1}, {3, 1} }])
    end

    # Mutation: drop the ensure in DragManager#end_drag - the raising drop leaves the drag active.
    it "reports a move the adapter refuses, and drags again afterwards" do
      adapter = MergeableTestAdapter.new(8, 4)
      adapter.move_error = "no such move"
      ui = grids({"grid", adapter})
      ui.app.on_event_exception = ->(_msg : String) { nil }
      ui.expect_reported("no such move") { ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1} }
      adapter.move_error = nil
      ui.drag_cell "grid", 2, 1, onto: {"grid", 4, 1} # another cell: a second press on 1,1 is a double-click
      adapter.moves.should eq([{ {2, 1}, {4, 1} }])
    end

    # The press began tracking a drag, as App's does; an act refused before the drop must end it, as App's
    # release does - or the next drag by id finds one "in progress". Mutation: no cancel on the refusal.
    it "leaves no drag pending after a refusal between press and drop" do
      drops = [] of String
      ui = driver do |window|
        {"a" => 8, "b" => 60}.each_with_index do |(id, rows), i|
          panel = CrymbleUI::WindowPanel.new(id, 10.0 + i * 390.0, 10.0, 380.0, 300.0, id: "#{id}_panel")
          panel.add_child(CrymbleUI::VirtualMatrix.new(adapter: MergeableTestAdapter.new(rows, 4), id: id))
          window.add_child(panel)
        end
        tray = CrymbleUI::WindowPanel.new("T", 10.0, 330.0, 380.0, 200.0, id: "tray")
        row = CrymbleUI::HStack.new(spacing: 40.0)
        row.add_child(CrymbleUI::DraggableBox.new(CrymbleUI::TextDragData.new("x"), id: "chip").tap(&.add_child(CrymbleUI::Text.new("chip"))))
        zone = CrymbleUI::DropZoneBox.new(accept_types: ["text"],
          on_drop_handler: ->(d : CrymbleUI::DragData, _p : CrymbleUI::Vec2) { drops << d.as(CrymbleUI::TextDragData).text; nil }, id: "zone")
        row.add_child(zone.tap(&.add_child(CrymbleUI::Text.new("zone"))))
        tray.add_child(row)
        window.add_child(tray)
      end
      expect_raises(CrymbleUI::Testing::Driver::Refusal, /not on screen/) do
        ui.drag_cell "a", 1, 1, onto: {"b", 50, 1}
      end
      ui.app.drag_manager.state.phase.idle?.should be_true
      ui.drag "chip", onto: "zone"
      drops.should eq(["x"])
    end

    # A rebuild between press and threshold replaces the grid; the drag is the gesture's and carries the
    # pressed cell - whatever the rebuilt grid's host marks. Mutation: take the payload from the new instance.
    it "drags the pressed cell across a rebuild between press and threshold" do
      {nil, {5, 1}}.each do |restored|
        adapter = MergeableTestAdapter.new(8, 4)
        builds = 0
        ui = grids({"grid", adapter}, kind: DriverRebuildingMatrix) do |vm|
          builds += 1
          vm.drag_source_cell = restored if builds > 1 && restored
        end
        ui.drag_cell "grid", 1, 1, onto: {"grid", 3, 1}
        adapter.moves.should eq([{ {1, 1}, {3, 1} }])
        vm = ui.find("grid").as(CrymbleUI::VirtualMatrix)
        (vm.drag_source_provisional? ? nil : vm.drag_source_cell).should be_nil # dropped: nothing marked
      end
    end
  end

  # Carried over from the removed WidgetTester: an app whose root is not a Window, driven by id
  # from build to click, reading what the rebuild shows.
  describe "a whole app, from build to click" do
    it "builds the tree, finds, clicks and reads the rebuilt result" do
      app = DriverCounterApp.new
      ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
      ui.present?("counter_text").should be_true
      ui.text("counter_text").should eq("Count: 0")
      ui.find("container").children.size.should eq(2)
      ui.click "increment"
      ui.text("counter_text").should eq("Count: 1")
      app.build_count.should be >= 2
    end
  end

  # Characterizations - they document the boundary, not a defect, and are not RED-proven.
  describe "what the trigger semantics leave out (characterization)" do
    it "fires a button under a modal popup: no hit test" do
      fired = 0
      ui = driver { |w| w.add_child(CrymbleUI::Button.new("under", id: "under") { fired += 1 }) }
      under = ui.find("under").viewport_bounds
      popup = CrymbleUI::Popup.new(width: under.width + 20, height: under.height + 20, id: "modal")
      popup.target_x = under.x - 10
      popup.target_y = under.y - 10
      open_popup(ui, popup)
      ui.click "under"
      fired.should eq(1)
    end

    it "leaves open a popup whose area contains the clicked widget" do
      ui = driver { |w| w.add_child(CrymbleUI::Button.new("under", id: "under") { }) }
      under = ui.find("under").viewport_bounds
      popup = CrymbleUI::Popup.new(width: under.width + 20, height: under.height + 20, id: "around")
      popup.target_x = under.x - 10
      popup.target_y = under.y - 10
      popup.on_click_outside_callback = ->{ window_of(ui).remove_overlay(popup); nil }
      open_popup(ui, popup)
      ui.click "under"
      ui.present?("around").should be_true
    end
  end
end
