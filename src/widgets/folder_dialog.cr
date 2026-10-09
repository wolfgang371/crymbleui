require "./folder_browser"

module CrymbleUI
  # A FolderBrowser shown as a dialog panel: what DirPicker and FileDialog share - identity,
  # open/close, where the keyboard starts, and the closing row (New folder, Ok, Cancel). Each adds
  # its own rows above that (see folder_dialog_panel) and says what Ok does.
  abstract class FolderDialog < FolderBrowser
    getter id : String
    property title : String
    getter? open : Bool = true
    # Where the keyboard starts: the list (true; what the arrow keys walk) or the dialog's text field.
    property focus_list : Bool = true

    def initialize(start : String | Path, @id : String, @title : String)
      super(start)
    end

    # Ok: hand the result over (and close).
    abstract def confirm : Nil
    # Ok's label.
    abstract def confirm_label : String
    # The name "New folder" makes (from the dialog's text field).
    abstract def new_folder_name : String

    def make_new_folder : Nil
      create_folder(new_folder_name)
    end

    # Whether Ok has something to hand over (FileDialog: a name). Ok is greyed while not.
    def can_confirm? : Bool
      true
    end

    # Enter with no row: Ok.
    def activate_nothing : Nil
      confirm
    end

    # Show it again, re-read, nothing highlighted - at its folder, or, if that has vanished since, at the nearest
    # ancestor that still opens (above the drives, on Windows, when none does). Never reports: the folder is gone.
    def open : Nil
      @open = true
      @last_click_file = nil
      @focused_once = false
      here = @path
      loop do
        move_to(here)
        break
      rescue File::Error
        here = here.parent == here ? Path.new : here.parent
      end
    end

    def close : Nil
      @open = false
    end
  end

  module DSL
    module BuilderMethods
      # The panel every FolderDialog shares. Ids: "<id>" (panel), "<id>_path_<i>" (path buttons),
      # "<id>_drv_<i>" (drives, Windows), "<id>_files" (the grid), "<id>_new_folder", "<id>_ok",
      # "<id>_cancel". Escape closes; Enter acts on the grid's cursor row, else the selection, else
      # Ok (folder_grid_enter).
      #
      # The block builds the dialog's own rows, between the grid and the closing row, and returns
      # the widget to type into, if any: it gets the keyboard on opening unless `focus_list`.
      def folder_dialog_panel(dialog : FolderDialog, x : Float64, y : Float64, width : Float64, height : Float64,
                              &rows : -> Widget?)
        id = dialog.id
        window_panel(dialog.title, x: x, y: y, width: width, height: height, id: id) do
          on_closed { dialog.close; rebuild_app }
          register_shortcut("Escape") { dialog.close; rebuild_app }
          register_shortcut("Enter") { folder_grid_enter(dialog, "#{id}_files") }
          vstack(spacing: 5.0, padding: 8.0) do
            flow(hspacing: 1.0, vspacing: 2.0) do
              parts = dialog.path.parts
              parts.each_with_index do |part, i|
                button(part, padding: 2.0, id: "#{id}_path_#{i}") { rebuilding { dialog.navigate_to_part(i + 1) } }
                # read as a path - but no "/" after the anchor (the root "/", "C:\\"), which ends in a separator
                text("/") unless i == 0 || i == parts.size - 1
              end
            end
            drives = dialog.drives
            unless drives.empty?
              hstack(spacing: 1.0) do
                drives.each_with_index do |drv, i|
                  button(drv, padding: 2.0, id: "#{id}_drv_#{i}") { rebuilding { dialog.goto(drv) } }
                end
              end
            end
            grid : Widget? = nil
            expanded { grid = folder_grid(dialog, "#{id}_files", focus: false) }
            field = rows.call
            hstack(spacing: 10.0) do
              button("New folder", id: "#{id}_new_folder") { rebuilding { dialog.make_new_folder } }
              spacer
              ok = button(dialog.confirm_label, id: "#{id}_ok") { rebuilding { dialog.confirm } }
              ok.enabled = dialog.can_confirm?
              button("Cancel", id: "#{id}_cancel") { dialog.close; rebuild_app }
            end
            unless dialog.focused_once
              dialog.focused_once = true
              (dialog.focus_list || field.nil? ? grid : field).try &.request_focus
            end
          end
        end
      end
    end
  end
end
