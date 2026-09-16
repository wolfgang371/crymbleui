require "./virtual_matrix"

module CrymbleUI
  module Widgets
    module DirBrowser
      # VirtualMatrix adapter for file browser table
      # Row 0 = sticky header (Filename, Size, Date)
      # Rows 1..N = file/directory entries
      class MatrixAdapter
        include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

        # Data (set by host before each rebuild)
        property items : Array({String, String, String, File::Info}) = [] of {String, String, String, File::Info}
        property sort_column : Int32 = 0
        property sort_ascending : Bool = true
        # The highlighted row, file OR directory — a directory is selected by one click and
        # entered by the second, so it has to be able to show as selected in between.
        property selected_name : String = ""

        # Callbacks
        property on_navigate : Proc(String, Nil)? = nil
        property on_select_file : Proc(String, Nil)? = nil
        # First click on a directory. The second, inside the double-click window, navigates.
        property on_select_dir : Proc(String, Nil)? = nil
        property on_sort : Proc(Int32, Nil)? = nil
        # Fired by the SECOND click on an already-selected file row. Hosts wire
        # this to "accept the dialog with this file selected".
        property on_accept : Proc(String, Nil)? = nil

        # Which row the previous click landed on — the whole of the activation
        # bookkeeping. Exposed as a property because the host (a dialog/window
        # panel) typically recreates the adapter on every render frame, so the
        # state can't live on the adapter alone. Host pattern:
        #   adapter.last_click_file = dialog.last_click_file
        # and in `on_select_file` / `on_select_dir` / `on_accept`, the host writes
        # the value back to the dialog so the NEXT frame re-seeds correctly.
        #
        # There is deliberately no timestamp beside it. Activation here is a
        # two-step gesture, not a double-click: the second click acts whenever it
        # comes, and clicking a DIFFERENT row moves the selection instead. A wall
        # clock would make the rule depend on how long the host took to draw —
        # which it did, and which no test could reach through a real click.
        property last_click_file : String? = nil

        def get_scrollorder : {Array(Int32), Array(Int32)}
          n = @items.size + 1
          rows = (1...n).to_a + [0]  # Header (row 0) at end → sticky
          cols = (0...3).to_a
          {rows, cols}
        end

        def get_sizes : {Array(Float64), Array(Float64)}
          n = @items.size + 1
          row_heights = Array.new(n, 1.0)
          col_widths = [12.0, 8.0, 14.0]
          {row_heights, col_widths}
        end

        def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
          if row == 0
            paint_header(col)
          else
            paint_item(row - 1, col)
          end
        end

        private def paint_header(col : Int32) : CrymbleUI::Widget
          labels = ["Filename", "Size", "Date"]
          label = labels[col]
          indicator = if @sort_column == col
            @sort_ascending ? " ▲" : " ▼"
          else
            ""
          end
          captured_col = col
          Button.new("#{label}#{indicator}", padding: 1.0,
            text_align: TextAlign::Left,
            id: "dirbrowser_sort_#{col}") do
            @on_sort.try &.call(captured_col)
          end
        end

        private def paint_item(index : Int32, col : Int32) : CrymbleUI::Widget
          return Text.new("") unless item = @items[index]?
          name, size, date, info = item

          case col
          when 0
            selected = @selected_name == name
            # Live theme refs (input_background/text_default), except the selected highlight (a real override).
            btn_bg = selected ? Color.new(60_u8, 100_u8, 180_u8, 255_u8) : Theme.ref(&.input_background)
            captured_name = name
            captured_is_dir = info.directory?
            Button.new(name, padding: 1.0,
              background_color: btn_bg, border_color: Theme.ref(&.input_background),
              text_color: Theme.ref(&.text_default),
              text_align: TextAlign::Left,
              id: "dirbrowser_item_#{index}") do
              # ONE activation rule for both kinds: the first click selects, the second acts.
              # Directories used to navigate on a single click while files needed two, so the same
              # gesture meant different things one row apart.
              second = @last_click_file == captured_name
              if second
                @last_click_file = nil # prevent a triple click from re-firing
                if captured_is_dir
                  @on_navigate.try &.call(captured_name.rstrip('/'))
                else
                  @on_accept.try &.call(captured_name)
                end
              else
                @last_click_file = captured_name
                if captured_is_dir
                  @on_select_dir.try &.call(captured_name)
                else
                  @on_select_file.try &.call(captured_name)
                end
              end
            end
          when 1
            Text.new(info.directory? ? "" : size, font_scale: -1)
          when 2
            Text.new(info.directory? ? "" : date, font_scale: -1)
          else
            Text.new("")
          end
        end
      end
    end
  end
end
