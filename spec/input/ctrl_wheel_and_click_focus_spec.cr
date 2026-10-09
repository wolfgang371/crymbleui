require "../spec_helper"
require "file_utils"
require "../../src/testing/driver"
require "../../src/widgets/dir_picker"
require "../../src/widgets/file_dialog"

# Ctrl+wheel: a widget that zooms something of its own takes it; elsewhere it zooms the UI's font.
# focus_on_click: a button or checkbox that leaves the keyboard where it is when clicked.

# A box that zooms its own content (an image viewer's picture, a thumbnail grid).
private class ZoomBox < CrymbleUI::Widget
  getter steps = [] of Float64

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(200.0, 100.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), CrymbleUI::Color.new(9, 9, 9, 255)).as(CrymbleUI::DrawPrimitive)]
  end

  def on_zoom_wheel(steps : Float64, point : CrymbleUI::Vec2) : Bool
    @steps << steps
    true
  end
end

private class WheelApp < CrymbleUI::App
  getter box = ZoomBox.new(id: "zoombox")
  getter clicks = 0
  getter toggles = 0

  def build : CrymbleUI::Widget
    window("W", 800, 600) do
      vstack(spacing: 10.0, padding: 10.0) do
        text_input(id: "field")
        widget(@box)
        button("Plain", id: "plain") { @clicks += 1 }
        b = button("Keep focus", id: "keep") { @clicks += 1 }
        b.focus_on_click = false
        c = checkbox("Keep too", checked: false, id: "keep_check") { @toggles += 1 }
        c.focus_on_click = false
        button("Wheel here", id: "elsewhere") { }
      end
    end
  end
end

private def press_through_app(ui, id : String)
  w = ui.find(id)
  at = w.viewport_bounds.center
  ui.app.handle_mouse_down(at)
  ui.app.handle_mouse_up(at)
  ui.settle
end

describe "Ctrl+wheel" do
  it "goes to a widget that zooms its own content, and leaves the font alone" do
    CrymbleUI::FontSizing.reset_zoom
    app = WheelApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    before = CrymbleUI::FontSizing.zoom_index
    ui.wheel "zoombox", 1.0, ctrl: true
    ui.wheel "zoombox", -2.0, ctrl: true
    app.box.steps.should eq [1.0, -2.0]
    CrymbleUI::FontSizing.zoom_index.should eq before
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end

  it "zooms the font where no widget takes it, and a plain wheel never zooms" do
    CrymbleUI::FontSizing.reset_zoom
    app = WheelApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    before = CrymbleUI::FontSizing.zoom_index
    ui.wheel "zoombox", 1.0
    CrymbleUI::FontSizing.zoom_index.should eq before
    app.box.steps.should be_empty
    ui.wheel "elsewhere", 1.0, ctrl: true
    CrymbleUI::FontSizing.zoom_index.should eq before + 1
  ensure
    CrymbleUI::FontSizing.reset_zoom
  end
end

describe "focus_on_click" do
  it "is on by default: a clicked button takes the keyboard" do
    ui = CrymbleUI::Testing::Driver.new(WheelApp.new, 800, 600)
    CrymbleUI::Widget.focus_manager.focus(ui.find("field"))
    press_through_app(ui, "plain")
    ui.focused_id.should eq "plain"
  end

  it "off: the click acts, and the keyboard stays where it was" do
    app = WheelApp.new
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    CrymbleUI::Widget.focus_manager.focus(ui.find("field"))
    press_through_app(ui, "keep")
    press_through_app(ui, "keep_check")
    app.clicks.should eq 1
    app.toggles.should eq 1
    ui.focused_id.should eq "field"
    ui.type "field", "x" # still typing into it
    ui.text("field").should eq "x"
  end
end

describe "a folder grid without files" do
  it "shows the name column only" do
    root = File.tempname("name_only")
    Dir.mkdir_p("#{root}/a")
    picker = CrymbleUI::DirPicker.new(root, id: "pick") { |_| }
    files = CrymbleUI::FileDialog.new("Load", "*", root, id: "fd") { |_| }
    ui = CrymbleUI::Testing::Driver.new(PickerAndDialog.new(picker, files), 1200, 800)
    ui.find("pick_files").as(CrymbleUI::VirtualMatrix).cols.should eq 1
    ui.find("fd_files").as(CrymbleUI::VirtualMatrix).cols.should eq 3
  ensure
    FileUtils.rm_rf(root) if root
  end
end

private class PickerAndDialog < CrymbleUI::App
  def initialize(@picker : CrymbleUI::DirPicker, @files : CrymbleUI::FileDialog)
    super()
  end

  def build : CrymbleUI::Widget
    window("W", 1200, 800) do
      dir_picker(@picker)
      file_dialog(@files, x: 600.0)
    end
  end
end
