require "../spec_helper"
require "../../src/testing/driver"
require "../../src/widgets/dir_picker"

# The directory picker: a panel over a DirBrowser grid that lists directories only and hands the
# chosen one to `on_pick`. Driven through the Driver, as a user would.

# A tree to browse: root/{a/{b/, c/, note.txt}, .hidden/, top.txt}
private def tree : String
  root = File.tempname("dir_picker_spec")
  Dir.mkdir_p("#{root}/a/b")
  Dir.mkdir_p("#{root}/a/c")
  Dir.mkdir_p("#{root}/.hidden")
  File.write("#{root}/a/note.txt", "x")
  File.write("#{root}/top.txt", "x")
  root
end

private class PickerApp < CrymbleUI::App
  getter picked = [] of String
  getter picker : CrymbleUI::DirPicker

  def initialize(start : String)
    super()
    @picker = CrymbleUI::DirPicker.new(start, id: "pick", title: "Choose a folder") { |dir| @picked << dir }
  end

  def build : CrymbleUI::Widget
    window("Picker", 800, 600) do
      text("main", id: "main")
      dir_picker(@picker) if @picker.open?
    end
  end
end

private def names(ui) : Array(String)
  ui.find("pick_files").as(CrymbleUI::VirtualMatrix).adapter
    .as(CrymbleUI::Widgets::DirBrowser::MatrixAdapter).items.map(&.[0])
end

describe CrymbleUI::DirPicker do
  it "lists directories only, parent first, hidden ones on request" do
    root = tree
    ui = CrymbleUI::Testing::Driver.new(PickerApp.new(root), 800, 600)
    names(ui).should eq ["../", "a/"]
    ui.find("pick").as(CrymbleUI::WindowPanel).title.should eq "Choose a folder"

    ui.click "pick_hidden"
    names(ui).should eq ["../", ".hidden/", "a/"]
  end

  it "walks into a directory and back up, and shows where it is" do
    root = tree
    ui = CrymbleUI::Testing::Driver.new(PickerApp.new(root), 800, 600)
    ui.open_file "pick_files", "a"
    names(ui).should eq ["../", "b/", "c/"]
    ui.text("pick_current").should contain Path[root, "a"].to_s

    ui.open_file "pick_files", ".."
    names(ui).should eq ["../", "a/"]
  end

  it "chooses the selected directory, else the one it is in, and closes" do
    root = tree
    app = PickerApp.new(root)
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.open_file "pick_files", "a"
    ui.select_file "pick_files", "c"
    ui.text("pick_current").should contain Path[root, "a", "c"].to_s
    ui.click "pick_ok"
    app.picked.should eq [Path[root, "a", "c"].to_s]
    ui.present?("pick").should be_false

    app.picker.open
    ui.app.request_rebuild
    ui.settle
    ui.click "pick_ok" # nothing selected after reopening: the directory it shows
    app.picked.last.should eq Path[root, "a"].to_s
  end

  it "jumps to an ancestor through the path buttons" do
    root = tree
    ui = CrymbleUI::Testing::Driver.new(PickerApp.new("#{root}/a/b"), 800, 600)
    names(ui).should eq ["../"]
    depth = Path[root].parts.size
    ui.click "pick_path_#{depth - 1}" # the button naming `root`
    names(ui).should eq ["../", "a/"]
  end

  it "cancels with Escape without choosing" do
    root = tree
    app = PickerApp.new(root)
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.press "Escape"
    ui.present?("pick").should be_false
    app.picked.should be_empty
  end

  it "enters the row under the grid's cursor with Enter" do
    root = tree
    ui = CrymbleUI::Testing::Driver.new(PickerApp.new(root), 800, 600)
    ui.focus_cell "pick_files", 2, 0 # row 0 is the header, 1 is "../"
    ui.press "Enter"
    names(ui).should eq ["../", "b/", "c/"]
  end

  it "creates a folder where it is, and chooses it" do
    root = tree
    app = PickerApp.new(root)
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.type "pick_filename", "fresh"
    ui.click "pick_new_folder"
    Dir.exists?("#{root}/fresh").should be_true
    names(ui).should eq ["../", "a/", "fresh/"]
    ui.click "pick_ok"
    app.picked.should eq [Path[root, "fresh"].to_s]
  end
end
