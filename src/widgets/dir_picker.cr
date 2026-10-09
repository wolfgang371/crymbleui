require "./folder_dialog"

module CrymbleUI
  # A "choose a folder" dialog: folders only (hidden ones on request); hands `on_pick` the SELECTED
  # folder - or the one shown, when none is - and closes. It can also make a folder where it is.
  #
  #   @picker = DirPicker.new(".", title: "Open folder") { |dir| self.folder = dir }
  #   ...
  #   def build
  #     window("App", 800, 600) do
  #       button("Open folder...") { @picker.open; request_rebuild }
  #       dir_picker(@picker) if @picker.open?
  #     end
  #   end
  class DirPicker < FolderDialog
    # The name typed for "New folder" (bound to "<id>_filename").
    getter folder_name_source = Source(String).new("")
    property on_pick : Proc(String, Nil)

    def initialize(start : String | Path = ".", id : String = "dir_picker", title : String = "Choose a folder",
                   &@on_pick : String -> Nil)
      super(start, id, title)
      @show_hidden = false
      refresh
    end

    # What Choose would hand back right now.
    def candidate : Path
      sel = selected_name
      sel.empty? || sel == PARENT ? @path : (@path / sel.rstrip('/')).normalize
    end

    def choose : Nil
      chosen = candidate.to_s
      close
      @on_pick.call(chosen)
    end

    def confirm : Nil
      choose
    end

    def confirm_label : String
      "Choose"
    end

    def new_folder_name : String
      @folder_name_source.get
    end

    def make_new_folder : Nil
      super
      @folder_name_source.set("")
    end
  end

  module DSL
    module BuilderMethods
      # A panel showing `picker`: folder_dialog_panel's ids plus "<id>_current" (what Choose takes),
      # "<id>_filename" (the name for New folder) and "<id>_hidden".
      def dir_picker(picker : DirPicker, x : Float64 = 100.0, y : Float64 = 80.0,
                     width : Float64 = 600.0, height : Float64 = 450.0)
        id = picker.id
        folder_dialog_panel(picker, x, y, width, height) do
          text("Choose: #{picker.candidate}", font_scale: -1, id: "#{id}_current")
          hstack(spacing: 10.0) do
            expanded { text_input(id: "#{id}_filename", placeholder: "new folder name", bind: picker.folder_name_source) }
            checkbox("hidden", checked: picker.show_hidden, id: "#{id}_hidden") do
              picker.show_hidden = !picker.show_hidden
              rebuild_app
            end
          end
          nil # the keyboard starts on the list
        end
      end
    end
  end
end
