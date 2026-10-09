require "../spec_helper"
require "../../src/testing/driver"
require "../../src/widgets/folder_browser"

# FolderBrowser with files: what a file dialog builds on (the DirPicker spec covers folders only).

# root/{sub/, b.txt (3 bytes), a.txt (1 byte), c.log}
private def tree : String
  root = File.tempname("folder_browser_spec")
  Dir.mkdir_p("#{root}/sub")
  File.write("#{root}/b.txt", "bbb")
  File.write("#{root}/a.txt", "a")
  File.write("#{root}/c.log", "c")
  root
end

private class OpenFile < CrymbleUI::FolderBrowser
  getter opened = [] of String

  def activate_file(name : String) : Nil
    @opened << (path / name).to_s
  end
end

private class BrowserApp < CrymbleUI::App
  getter browser : OpenFile

  def initialize(root : String)
    super()
    @browser = OpenFile.new(root)
    @browser.file_filter = ->(name : String) { File.match?("*.txt", name) }
    @browser.refresh
  end

  def build : CrymbleUI::Widget
    window("Files", 800, 600) do
      window_panel("Open", 10.0, 10.0, 600.0, 400.0, id: "dlg") do
        register_shortcut("Enter") { folder_grid_enter(@browser, "files") }
        vstack { expanded { folder_grid(@browser, "files") } }
      end
    end
  end
end

private def names(ui) : Array(String)
  ui.find("files").as(CrymbleUI::VirtualMatrix).adapter
    .as(CrymbleUI::Widgets::DirBrowser::MatrixAdapter).items.map(&.[0])
end

describe CrymbleUI::FolderBrowser do
  it "lists the files its filter accepts after the folders, sorted by the clicked column" do
    root = tree
    ui = CrymbleUI::Testing::Driver.new(BrowserApp.new(root), 800, 600)
    names(ui).should eq ["../", "sub/", "a.txt", "b.txt"]

    ui.click_cell "files", 0, 0 # by name again: reverses
    names(ui).should eq ["../", "sub/", "b.txt", "a.txt"]
    ui.click_cell "files", 0, 1 # by size, ascending
    names(ui).should eq ["../", "sub/", "a.txt", "b.txt"]
  end

  it "opens a file with the second click" do
    root = tree
    app = BrowserApp.new(root)
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    ui.select_file "files", "b.txt"
    app.browser.opened.should be_empty
    app.browser.selected_name.should eq "b.txt"
    ui.open_file "files", "b.txt"
    app.browser.opened.should eq ["#{root}/b.txt"]
  end

  it "moves the selection with the arrows and acts on it with Enter" do
    root = tree
    app = BrowserApp.new(root)
    ui = CrymbleUI::Testing::Driver.new(app, 800, 600)
    b = app.browser
    b.move_selection(1)
    b.selected_name.should eq "../"
    b.move_selection(-1) # clamps at the top
    b.selected_name.should eq "../"
    b.move_selection(10)
    b.selected_name.should eq "b.txt"
    b.activate_selection
    b.opened.should eq ["#{root}/b.txt"]

    b.move_selection(-2)
    b.selected_name.should eq "sub/"
    CrymbleUI::Widget.focus_manager.clear_focus
    ui.press "Enter" # no focused grid: the browser's selection
    names(ui).should eq ["../"]
  end

  it "stays put and raises when a folder cannot be opened" do
    root = tree
    b = OpenFile.new(root)
    b.file_filter = ->(name : String) { true }
    b.refresh
    expect_raises(File::Error) { b.navigate("nope") }
    b.path.should eq Path[root]
    b.items.map(&.name).should contain "c.log"
  end

  it "re-sorts and re-filters in memory: only walking and refresh read the disk" do
    root = tree
    b = OpenFile.new(root)
    b.file_filter = ->(name : String) { File.match?("*.txt", name) }
    b.refresh
    reads = b.disk_reads
    b.sort_by(1)
    b.sort_by(1)
    b.show_hidden = false
    b.file_filter = ->(name : String) { true }
    b.items.map(&.name).should eq ["../", "sub/", "b.txt", "c.log", "a.txt"] # size descending; a tie by name, reversed too
    b.disk_reads.should eq reads
    b.navigate("sub")
    b.disk_reads.should eq reads + 1
    b.refresh
    b.disk_reads.should eq reads + 2
  end

  it "orders names case-insensitively, and sizes and dates by value" do
    root = File.tempname("folder_browser_order")
    {"Zeta", "alpha", "Beta"}.each { |d| Dir.mkdir_p("#{root}/#{d}") }
    File.write("#{root}/b.txt", "x" * 1000)
    File.write("#{root}/A.txt", "x" * 50)
    File.write("#{root}/c.txt", "x" * 5)
    File.touch("#{root}/b.txt", Time.utc(2001, 1, 1))
    File.touch("#{root}/A.txt", Time.utc(2020, 1, 1))
    File.touch("#{root}/c.txt", Time.utc(1999, 12, 31))
    b = OpenFile.new(root)
    b.file_filter = ->(name : String) { true }
    b.refresh
    b.items.map(&.name).should eq ["../", "alpha/", "Beta/", "Zeta/", "A.txt", "b.txt", "c.txt"]
    b.sort_by(1)
    b.items.map(&.name).last(3).should eq ["c.txt", "A.txt", "b.txt"]
    b.sort_by(2)
    b.items.map(&.name).last(3).should eq ["c.txt", "b.txt", "A.txt"]
    b.items.find!(&.name.== "A.txt").directory?.should be_false
  end

  it "refuses folder names that are not a single new folder" do
    root = tree
    b = OpenFile.new(root)
    {".", "..", "x/y", "/abs"}.each do |bad|
      expect_raises(File::Error) { b.create_folder(bad) }
    end
    Dir.exists?("#{root}/x").should be_false
    b.create_folder("") # nothing typed: nothing to do
    Dir.children(root).sort.should eq ["a.txt", "b.txt", "c.log", "sub"]
  end
end
