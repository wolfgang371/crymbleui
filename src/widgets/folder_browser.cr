require "./dir_browser"
require "../dsl/builder"

module CrymbleUI
  # What a file or folder dialog browses: the folder shown, its listing, the highlighted row, and the
  # walking around. Shown by `folder_grid` (a VirtualMatrix over Widgets::DirBrowser::MatrixAdapter).
  #
  # The state lives here, not on the grid's adapter: a click asks for a rebuild, which makes a fresh
  # adapter, so `folder_grid` re-seeds it from this object every build.
  #
  # Rows: "../" (not at the root), then directories ("name/", by name), then - only with a
  # `file_filter` - the files it accepts, in the sort column's order. With no filter it lists
  # directories only.
  #
  # Activation: one click selects a row, a second (or Enter on the grid's cursor) acts - walks into a
  # directory, or calls `activate_file`. Subclasses decide what acting on a file, or on no row at
  # all (`activate_nothing`), means.
  class FolderBrowser
    PARENT = "../"

    # One listed row: its name ("name/" for a folder, "../" for the way up) and what the disk says.
    record Entry, name : String, info : File::Info do
      def directory? : Bool
        info.directory?
      end

      def hidden? : Bool
        name.starts_with?('.') && name != PARENT
      end

      # The row as Widgets::DirBrowser::MatrixAdapter shows it: name, size, date, info.
      def to_row : {String, String, String, File::Info}
        directory? ? {name, "", "", info} : {name, info.size.format.rjust(15), info.modification_time.to_s, info}
      end
    end

    getter path : Path
    # The rows shown: "../", the folders, the files the filter accepts - filtered and sorted from
    # what the folder holds, which is read only by walking and `refresh`.
    getter items = [] of Entry
    # The highlighted row: a name (directories carry their trailing "/"), and its index.
    getter selected_name : String = ""
    getter selected_index : Int32 = -1
    getter sort_column : Int32 = 0
    getter sort_ascending : Bool = true
    getter show_hidden : Bool = true
    # nil: directories only. Otherwise: the files to list (by name).
    getter file_filter : Proc(String, Bool)? = nil
    # The DirBrowser adapter's two-click bookkeeping, carried across the per-click rebuild.
    property last_click_file : String? = nil
    # Set once the grid has taken the keyboard, so a rebuild does not steal it back.
    property focused_once : Bool = false
    # Instrumentation: how often the folder was read from disk.
    getter disk_reads : Int32 = 0

    @@drives : Array(String)? = nil
    @parent : Entry? = nil
    @held = [] of Entry # everything the folder holds, as last read

    def initialize(start : String | Path = ".")
      @path = Path[start].expand
    end

    def show_hidden=(show : Bool)
      @show_hidden = show
      arrange
    end

    def file_filter=(filter : Proc(String, Bool)?)
      @file_filter = filter
      arrange
    end

    # Walk into a listed directory ("../" / "..": up). A folder that cannot be opened leaves the
    # browser where it was, re-read, and RAISES - hosts report it (embrace: status bar).
    def navigate(name : String) : Nil
      here = @path
      @path = (@path / name.rstrip('/')).normalize
      Dir.open(@path).close
      deselect
      refresh
    rescue ex : File::Error
      @path = here.not_nil!
      refresh
      raise ex
    end

    # Jump to the ancestor made of the first `count` path parts (the breadcrumb buttons). A folder that cannot be
    # opened RAISES, and the browser stays where it was - checked before moving, so nothing to restore.
    def navigate_to_part(count : Int32) : Nil
      move_to(Path.new(@path.parts[0...count.clamp(0, @path.parts.size)]))
    end

    def goto(path : String | Path) : Nil
      move_to(Path[path].expand)
    end

    def select_row(name : String) : Nil
      @selected_name = name
      @selected_index = @items.index(&.name.== name) || -1
    end

    # Arrow keys: from nothing selected, Down starts at the top and Up at the bottom.
    def move_selection(delta : Int32) : Nil
      return if @items.empty?
      index = @selected_index < 0 ? (delta > 0 ? 0 : @items.size - 1) : (@selected_index + delta).clamp(0, @items.size - 1)
      select_row(@items[index].name)
    end

    # Enter on a row (an index into `items`; -1 for none).
    def activate_index(index : Int32) : Nil
      # @items[-1]? is the LAST row in Crystal, not nil
      entry = index < 0 ? nil : @items[index]?
      if entry.nil?
        activate_nothing
      elsif entry.directory?
        navigate(entry.name)
      else
        select_row(entry.name)
        activate_file(entry.name)
      end
    end

    def activate_selection : Nil
      activate_index(@selected_index)
    end

    # A file's second click / Enter. Default: nothing.
    def activate_file(name : String) : Nil
    end

    # Enter with no row. Default: nothing.
    def activate_nothing : Nil
    end

    # A column header click: the same column reverses, another one starts ascending.
    def sort_by(column : Int32) : Nil
      if column == @sort_column
        @sort_ascending = !@sort_ascending
      else
        @sort_column = column
        @sort_ascending = true
      end
      arrange
    end

    # Re-read the folder, keeping the order and (if still listed) the selection.
    def refresh : Nil
      read
      arrange
    end

    # Make a folder here (and highlight it). Raises File::Error when it cannot - a name that is not
    # one new folder ("." / ".." / a path), or one the filesystem refuses (a file has that name);
    # hosts report it. An empty name does nothing.
    def create_folder(name : String) : Nil
      return if name.empty?
      parts = Path[name].parts
      if parts.size != 1 || Path[name].absolute? || name == "." || name == ".."
        raise File::Error.new("not a single folder name", file: name) # the caller names the folder
      end
      Dir.mkdir_p(@path / name)
      refresh
      select_row("#{name}/")
    end

    # Drive roots (Windows; empty elsewhere).
    def drives : Array(String)
      @@drives ||= {% if flag?(:win32) %}
                     ("A".."Z").map { |l| "#{l}:/" }.select { |p| Dir.exists?(p) rescue false }
                   {% else %}
                     [] of String
                   {% end %}
    end

    private def move_to(target : Path) : Nil
      Dir.open(target).close unless target.parts.empty? # above the drives (Windows) lists them
      @path = target
      deselect
      refresh
    end

    # Nothing highlighted.
    def deselect : Nil
      @selected_name = ""
      @selected_index = -1
    end

    # The disk part: what the folder holds (folders as "name/"), and the way up.
    private def read : Nil
      @disk_reads += 1
      @held = [] of Entry
      if @path.parts.empty? # above the drives (Windows)
        @parent = nil
        @held = drives.map { |d| Entry.new(d, File.info(d)) }
        return
      end
      begin
        Dir.each_child(@path) do |name|
          info = File.info?(@path / name) # follows links: a link to a folder is a folder
          @held << Entry.new(info.directory? ? "#{name}/" : name, info) if info
        end
      rescue File::Error
        # unreadable: listed empty, the way up stays
      end
      parent = begin
        File.info?(@path / "..")
      rescue File::Error # a folder without search permission: no way up through it
        nil
      end
      @parent = parent && @path.parent != @path ? Entry.new(PARENT, parent) : nil
    end

    # The memory part: filter and sort what was read; keep the highlighted row if still listed
    # (not via select_row: a subclass may act on it).
    private def arrange : Nil
      filter = @file_filter
      shown = @held.select { |e| (@show_hidden || !e.hidden?) && (e.directory? || (filter && filter.call(e.name))) }
      dirs, files = shown.partition(&.directory?)
      dirs.sort! { |a, b| by_name(a, b) }
      files.sort! { |a, b| by_column(a, b) }
      @items = (@parent.try { |p| [p] } || [] of Entry) + dirs + files
      @selected_index = @items.index(&.name.== @selected_name) || -1
      deselect if @selected_index < 0
    end

    private def by_name(a : Entry, b : Entry) : Int32
      {a.name.downcase, a.name} <=> {b.name.downcase, b.name}
    end

    private def by_column(a : Entry, b : Entry) : Int32
      order = case @sort_column
              when 1 then a.info.size <=> b.info.size
              when 2 then a.info.modification_time <=> b.info.modification_time
              else        by_name(a, b)
              end
      order = by_name(a, b) if order == 0
      @sort_ascending ? order : -order
    end
  end

  module DSL
    module BuilderMethods
      # The grid showing `browser`, wired both ways: clicks select / walk / activate, header clicks
      # sort, each asks for the rebuild that shows it. With `focus`, takes the keyboard once per
      # opening (`focused_once`); a host that decides focus itself passes false.
      def folder_grid(browser : FolderBrowser, id : String, focus : Bool = true) : VirtualMatrix
        adapter = Widgets::DirBrowser::MatrixAdapter.new
        adapter.items = browser.items.map(&.to_row)
        adapter.name_only = browser.file_filter.nil?
        adapter.sort_column = browser.sort_column
        adapter.sort_ascending = browser.sort_ascending
        adapter.selected_name = browser.selected_name
        adapter.last_click_file = browser.last_click_file
        # A refused act (a folder that cannot be opened raises) still carries the click state over and repaints
        # the re-read listing.
        carry = ->(act : -> Nil) {
          rebuilding do
            act.call
          ensure
            browser.last_click_file = adapter.last_click_file
          end
        }
        adapter.on_select_dir = ->(name : String) { carry.call(-> { browser.select_row(name) }) }
        adapter.on_select_file = ->(name : String) { carry.call(-> { browser.select_row(name) }) }
        adapter.on_navigate = ->(name : String) { carry.call(-> { browser.navigate(name) }) }
        adapter.on_accept = ->(name : String) { carry.call(-> { browser.select_row(name); browser.activate_file(name) }) }
        adapter.on_sort = ->(col : Int32) { browser.sort_by(col); rebuild_app }
        vm = VirtualMatrix.new(adapter: adapter, id: id)
        vm.show_rulers = false
        widget(vm)
        if focus && !browser.focused_once
          browser.focused_once = true
          vm.request_focus
        end
        vm
      end

      # Enter for a panel holding a `folder_grid`. Enter reaches a panel shortcut BEFORE the focused
      # grid (KeyboardDispatch), while the arrow keys move the grid's OWN cursor - so the row to act
      # on is the one under that cursor when the grid has the focus, else the browser's selection.
      def folder_grid_enter(browser : FolderBrowser, id : String) : Nil
        row = -1
        if (vm = Widget.app?.try(&.find(id))).is_a?(VirtualMatrix) && Widget.focus_manager?.try(&.focused?(vm))
          row = vm.cursor_rc[0] - 1 # row 0 is the header
        end
        rebuilding { row >= 0 ? browser.activate_index(row) : browser.activate_selection }
      end

      # A handler changed what the folder widgets show: the app rebuilds the tree.
      private def rebuild_app : Nil
        Widget.app?.try &.request_rebuild
      end

      # A handler's act, followed by the rebuild that shows it - also when the act is refused (raises): a refusal
      # re-reads the folder, or the dialog closed before its host's callback raised.
      private def rebuilding(&) : Nil
        yield
      ensure
        rebuild_app
      end
    end
  end
end
