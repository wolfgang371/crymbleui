require "../spec_helper"
require "file_utils"
require "../../src/testing/driver"
require "../../src/widgets/file_dialog"

# The open/save dialog, as a user meets it (moved here from embrace's dirbrowser_usability_spec;
# what stays there is embrace's own: overwrite confirmation, status-bar texts).
# NOT covered here (say so rather than claim it): the drive buttons (Windows only), a click on Cancel, sorting by a
# header click through the grid (sort_by is checked on the model), and the parent lookup of a folder without search
# permission (it needs permission tricks).

# dir/{sub/, a.embrace, b.embrace, note.txt}
private def fixture_dir : String
  dir = File.tempname("file_dialog_spec")
  Dir.mkdir_p(File.join(dir, "sub"))
  File.write(File.join(dir, "a.embrace"), "one")
  File.write(File.join(dir, "b.embrace"), "two")
  File.write(File.join(dir, "note.txt"), "not matching the wildcard")
  dir
end

private class DialogApp < CrymbleUI::App
  getter accepted = [] of String
  getter dialog : CrymbleUI::FileDialog

  def initialize(dir : String, focus_list = false)
    super()
    @dialog = CrymbleUI::FileDialog.new("Load file...", "*.embrace", dir, id: "fd") { |path| @accepted << path }
    @dialog.focus_list = focus_list
  end

  def build : CrymbleUI::Widget
    window("Files", 1200, 800) do
      text("main", id: "main")
      file_dialog(@dialog) if @dialog.open?
    end
  end
end

private def names(dialog) : Array(String)
  dialog.items.map(&.name)
end

describe CrymbleUI::FileDialog do
  it "lists folders, then the files matching the wildcard; 'All files' shows the rest" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    names(app.dialog).should eq ["../", "sub/", "a.embrace", "b.embrace"]
    ui.find("fd").as(CrymbleUI::WindowPanel).title.should eq "Load file... (*.embrace)"
    ui.click "fd_all_files"
    names(app.dialog).should contain "note.txt"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "opens sorted ascending and keeps the direction while browsing" do
    dir = fixture_dir
    dialog = CrymbleUI::FileDialog.new("Load", "*.embrace", dir) { |_| }
    dialog.sort_ascending.should be_true
    dialog.navigate("sub")
    dialog.navigate("..")
    dialog.sort_ascending.should be_true
    dialog.sort_by(0)
    dialog.sort_ascending.should be_false
    dialog.sort_by(1)
    {dialog.sort_column, dialog.sort_ascending}.should eq({1, true})
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "focuses the filename field when it opens (Save as)" do
    dir = fixture_dir
    ui = CrymbleUI::Testing::Driver.new(DialogApp.new(dir))
    ui.focused_id.should eq "fd_filename"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "accepts a typed name with Enter, appending the wildcard's extension" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.type "fd_filename", "typed"
    ui.press "Enter"
    app.accepted.should eq [File.join(dir, "typed.embrace")]
    ui.present?("fd").should be_false
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  # Ok follows the field as it is typed in - a repaint, not a rebuild per keystroke.
  it "greys Ok while the name is empty, and Enter accepts nothing then" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.enabled?("fd_ok").should be_false
    ui.press "Enter"
    app.accepted.should be_empty
    ui.present?("fd").should be_true
    rebuilds = CrymbleUI::App.rebuild_count
    ui.type "fd_filename", "x"
    ui.enabled?("fd_ok").should be_true
    ui.press "Backspace", on: "fd_filename"
    ui.enabled?("fd_ok").should be_false
    CrymbleUI::App.rebuild_count.should eq(rebuilds) # two keystrokes, no rebuild
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "takes a file with two clicks, and puts the first click's file in the name field" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.select_file "fd_files", "b.embrace"
    ui.text("fd_filename").should eq "b.embrace"
    app.accepted.should be_empty
    ui.select_file "fd_files", "b.embrace" # the second click
    app.accepted.should eq [File.join(dir, "b.embrace")]
    ui.present?("fd").should be_false
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "needs two clicks to enter a directory, and keeps a typed name while browsing" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.type "fd_filename", "keep"
    ui.select_file "fd_files", "sub"
    app.dialog.path.should eq Path[dir]
    app.dialog.selected_name.should eq "sub/"
    ui.select_file "fd_files", "sub"
    app.dialog.path.should eq Path[dir, "sub"]
    ui.text("fd_filename").should eq "keep"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "walks the list with the arrow keys and acts on the row under the cursor with Enter (Load)" do
    dir = fixture_dir
    app = DialogApp.new(dir, focus_list: true)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.focused_id.should eq "fd_files"
    2.times { ui.press "Down" } # header -> ../ -> sub/
    ui.press "Enter"
    app.dialog.path.should eq Path[dir, "sub"]
    app.accepted.should be_empty
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "creates a folder from the name field, lists and selects it" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.type "fd_filename", "fresh"
    ui.click "fd_new_folder"
    Dir.exists?(File.join(dir, "fresh")).should be_true
    names(app.dialog).should contain "fresh/"
    app.dialog.selected_name.should eq "fresh/"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "raises File::Error for a folder it cannot create or open, and stays where it is" do
    dir = fixture_dir
    dialog = CrymbleUI::FileDialog.new("Load", "*.embrace", dir) { |_| }
    expect_raises(File::Error) { dialog.create_folder("a.embrace") } # a file has the name
    FileUtils.rm_rf(File.join(dir, "sub")) # listed, then gone
    expect_raises(File::Error) { dialog.navigate("sub/") }
    dialog.path.should eq Path[dir]
    names(dialog).should_not contain "sub/"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "jumps to an ancestor with the path buttons and closes with Escape" do
    dir = fixture_dir
    app = DialogApp.new(File.join(dir, "sub"))
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.click "fd_path_#{Path[dir].parts.size - 1}"
    app.dialog.path.should eq Path[dir]
    ui.press "Escape"
    ui.present?("fd").should be_false
    app.accepted.should be_empty
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "is painted: every row, the field and the buttons, inside its panel" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    panel = ui.find("fd") # paints into its own layer (no widget backend): its contents are checked
    grid = ui.find("fd_files").as(CrymbleUI::VirtualMatrix)
    assert_visible_in_parent(grid, panel)
    # Grid cells paint straight into the grid's layer (no backend of their own), so the evidence is the
    # composited window: ink (pixels other than the cell's own background) inside the row's name cell.
    painted = ->(row : Int32) {
      grid.active_cells[{row, 0}]?.try do |cell|
        r = cell.viewport_bounds
        pixels = ui.renderer.backend.get_pixels(r.x.to_i, r.y.to_i, r.width.to_i, r.height.to_i)
        pixels.count(&.!= pixels.first) > 10
      end
    }
    (0..4).each { |row| painted.call(row).should be_truthy, "row #{row} is not painted" } # header + 4 entries
    # the probe can say no: three rows below the last one, the grid is empty
    last = grid.active_cells[{4, 0}].viewport_bounds
    blank = ui.renderer.backend.get_pixels(last.x.to_i, (last.y + 3 * last.height).to_i, last.width.to_i, last.height.to_i)
    blank.count(&.!= blank.first).should eq 0
    {"fd_filename", "fd_all_files", "fd_new_folder", "fd_ok", "fd_cancel"}.each do |id|
      assert_rendered(ui.find(id), id)
      assert_visible_in_parent(ui.find(id), panel)
    end

    ui.type "fd_filename", "typed"
    ui.text("fd_filename").should eq "typed"
    ui.click "fd_all_files"
    grid = ui.find("fd_files").as(CrymbleUI::VirtualMatrix)
    painted.call(5).should be_truthy, "the row 'All files' adds is not painted"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "reads the path as a path: a '/' between the buttons, none doubled after the root" do
    dir = fixture_dir
    ui = CrymbleUI::Testing::Driver.new(DialogApp.new(dir))
    row = ui.find("fd_path_0").parent.not_nil!
    shown = row.children.map { |w| w.is_a?(CrymbleUI::Button) ? w.text : w.as(CrymbleUI::Text).text }
    parts = Path[dir].parts # an absolute path: parts[0] is its anchor, "/" here
    shown.should eq [parts[0], parts[1]] + parts[2..].flat_map { |p| ["/", p] } # no "/" after the anchor
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "repaints when its host's callback raises: the dialog has closed and is no longer shown" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    app.dialog.on_accept = ->(_path : String) { raise "the host refused"; nil }
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.type "fd_filename", "x"
    expect_raises(Exception, "the host refused") { ui.click "fd_ok" }
    ui.settle # the frame the loop renders next
    ui.present?("fd").should be_false
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "reports a path button to a folder that vanished, and stays where it is" do
    dir = fixture_dir
    deep = File.join(dir, "sub", "deep")
    Dir.mkdir_p(deep)
    app = DialogApp.new(deep)
    ui = CrymbleUI::Testing::Driver.new(app)
    sub_index = Path[dir].parts.size # the button naming "sub"
    FileUtils.rm_rf(File.join(dir, "sub"))
    expect_raises(File::Error) { ui.click "fd_path_#{sub_index}" }
    app.dialog.path.should eq Path[deep]
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "repaints after Enter on a folder that vanished: the folder is no longer offered" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.select_file "fd_files", "sub" # highlighted
    FileUtils.rm_rf(File.join(dir, "sub"))
    expect_raises(File::Error) { ui.press "Enter" }
    ui.settle # the frame the loop renders next (a raise ends the Driver's event batch before its frames)
    expect_raises(ArgumentError, /no "sub"/) { ui.select_file "fd_files", "sub" }
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "repaints after a refused second click on a folder that vanished: the folder is no longer offered" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.select_file "fd_files", "sub" # the first click
    FileUtils.rm_rf(File.join(dir, "sub"))
    expect_raises(File::Error) { ui.select_file "fd_files", "sub" } # the second, refused
    expect_raises(ArgumentError, /no "sub"/) { ui.select_file "fd_files", "sub" }
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "counts a refused second click as spent: the next click on the folder only selects it" do
    {% if flag?(:win32) %}
      pending!("Windows has no chmod 000: the folder stays readable") # and LibC has no getuid there
    {% else %}
      pending!("root ignores chmod 000") if LibC.getuid == 0
    {% end %}
    dir = fixture_dir
    locked = File.join(dir, "locked")
    Dir.mkdir_p(locked)
    File.chmod(locked, 0o000)
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.select_file "fd_files", "locked"
    expect_raises(File::Error) { ui.select_file "fd_files", "locked" } # the second click, refused
    ui.select_file "fd_files", "locked" # a first click again: selects, reports nothing
    app.dialog.selected_name.should eq "locked/"
    app.dialog.path.should eq Path[dir]
  ensure
    File.chmod(File.join(dir, "locked"), 0o755) if dir
    FileUtils.rm_rf(dir) if dir
  end

  it "refuses a New folder name that is not one folder, without repeating the name" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.type "fd_filename", "a/b"
    error = expect_raises(File::Error) { ui.click "fd_new_folder" }
    error.message.to_s.should contain "not a single folder name"
    error.message.to_s.should_not contain "a/b"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "opens what 'All files' lists as listed; a typed name gets the extension as before" do
    dir = fixture_dir
    File.write(File.join(dir, "Makefile"), "all:")
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.click "fd_all_files"
    ui.open_file "fd_files", "note.txt"
    app.accepted.last.should eq File.join(dir, "note.txt")
    app.dialog.open
    app.request_rebuild
    ui.settle
    ui.select_file "fd_files", "Makefile" # one click: still the selected row
    ui.click "fd_ok"
    app.accepted.last.should eq File.join(dir, "Makefile")
    {"x" => "x.embrace", "budget v1.5" => "budget v1.5.embrace"}.each do |typed, saved|
      app.dialog.open
      app.request_rebuild
      ui.settle
      ui.press "Ctrl+A", on: "fd_filename" # the re-shown dialog keeps the last name: replaced, as a user does
      ui.type "fd_filename", typed
      ui.click "fd_ok"
      app.accepted.last.should eq File.join(dir, saved)
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "re-opens at the nearest folder that still exists when its own vanished" do
    dir = fixture_dir
    deep = File.join(dir, "sub", "deep")
    Dir.mkdir_p(deep)
    app = DialogApp.new(deep)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.press "Escape"
    FileUtils.rm_rf(File.join(dir, "sub"))
    app.dialog.open
    app.request_rebuild
    ui.settle
    app.dialog.path.should eq Path[dir]
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "accepts what was typed after a file was clicked: typing clears the highlight" do
    dir = fixture_dir
    app = DialogApp.new(dir)
    ui = CrymbleUI::Testing::Driver.new(app)
    ui.select_file "fd_files", "a.embrace"
    ui.press "Ctrl+A", on: "fd_filename"
    ui.type "fd_filename", "b2"
    app.dialog.selected_name.should eq ""
    ui.find("fd_files").as(CrymbleUI::VirtualMatrix).adapter.as(CrymbleUI::Widgets::DirBrowser::MatrixAdapter).selected_name.should eq "" # the grid too
    ui.press "Enter"
    app.accepted.should eq [File.join(dir, "b2.embrace")]
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
