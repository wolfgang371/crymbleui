require "./folder_dialog"

module CrymbleUI
  # An open/save dialog: folders, then the files matching `wildcard` ("All files": every file).
  # A file's first click puts its name in the filename field, the second accepts it as listed; Ok / Enter
  # accept the field's name - as listed while it is still the highlighted row's, else as typed, with the
  # wildcard's extension appended when it does not match ("*.embrace": "x" -> "x.embrace"). `on_accept` gets the
  # full path. Ok is greyed while the field is empty; typing in it drops the highlight.
  # Errors (a folder that cannot be opened or made) are raised as File::Error for the host to report.
  #
  #   @save = FileDialog.new("Save file as...", "*.embrace") { |path| save(path) }
  #   ...  file_dialog(@save) if @save.open?
  #
  # For a Load dialog set `focus_list = true`: the keyboard then starts on the list, not the field.
  class FileDialog < FolderDialog
    getter wildcard : String
    getter show_all : Bool = false
    # The filename field's text (bound to "<id>_filename").
    getter filename_source = Source(String).new("")
    property on_accept : Proc(String, Nil)

    def initialize(title : String, @wildcard : String = "*", start : String | Path = ".",
                   id : String = "file_dialog", &@on_accept : String -> Nil)
      super(start, id, title)
      @focus_list = false
      read_filter
      refresh
    end

    # The panel title names the wildcard: "Load file... (*.embrace)".
    def title : String
      "#{super} (#{@wildcard})"
    end

    def filename : String
      @filename_source.get
    end

    def filename=(name : String)
      @filename_source.set(name)
    end

    def show_all=(all : Bool)
      @show_all = all
      read_filter
    end

    # Highlighting a file puts its name in the field; a folder leaves the field alone.
    def select_row(name : String) : Nil
      super
      if (entry = items[selected_index]?) && !entry.directory?
        self.filename = name
      end
    end

    # A file's second click / Enter on it: taken exactly as listed ("All files" opens note.txt as note.txt).
    def activate_file(name : String) : Nil
      accept(as_listed: true)
    end

    # Ok / Enter with no row: the field - as listed while it still holds the highlighted row's name.
    def confirm : Nil
      accept(as_listed: filename == selected_name)
    end

    def can_confirm? : Bool
      !filename.empty?
    end

    def confirm_label : String
      "Ok"
    end

    # "New folder" is named by the filename field.
    def new_folder_name : String
      filename
    end

    # Hands the field's name on, closed first. A TYPED name gets the wildcard's extension unless it matches the
    # wildcard ("x" -> "x.embrace"); one picked from the list (`as_listed`) is taken as listed. An empty name: nothing.
    def accept(as_listed : Bool = false) : Nil
      name = filename
      return if name.empty?
      if !as_listed && !File.match?(@wildcard, name) && @wildcard =~ /^\*(.*)$/
        name += $1
      end
      close
      @on_accept.call((@path / name).to_s)
    end

    private def read_filter : Nil
      wildcard = @wildcard
      self.file_filter = @show_all ? ->(_name : String) { true } : ->(name : String) { File.match?(wildcard, name) }
    end
  end

  module DSL
    module BuilderMethods
      # A panel showing `dialog`: folder_dialog_panel's ids plus "<id>_filename" (also names New
      # folder) and "<id>_all_files".
      def file_dialog(dialog : FileDialog, x : Float64 = 100.0, y : Float64 = 80.0,
                      width : Float64 = 700.0, height : Float64 = 500.0)
        id = dialog.id
        folder_dialog_panel(dialog, x, y, width, height) do
          field : Widget? = nil
          hstack(spacing: 10.0) do
            text("Filename:")
            # Each keystroke: Ok follows whether there is a name (a repaint - found by id, never kept: a rebuild
            # replaces it), and an edited name drops the highlight, so Enter accepts what was typed (one rebuild,
            # when the highlight goes - the grid shows it as seeded at build).
            edited = ->(text : String, event : TextInputEvent) {
              if event.change?
                if !dialog.selected_name.empty? && text != dialog.selected_name
                  dialog.deselect
                  rebuild_app
                end
                Widget.app?.try(&.find("#{id}_ok")).try(&.enabled = !text.empty?)
              end
              nil
            }
            expanded { field = text_input(id: "#{id}_filename", bind: dialog.filename_source, on_event: edited) }
            checkbox("All files", checked: dialog.show_all, id: "#{id}_all_files") do
              dialog.show_all = !dialog.show_all
              rebuild_app
            end
          end
          field
        end
      end
    end
  end
end
