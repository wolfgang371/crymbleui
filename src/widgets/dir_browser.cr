require "./virtual_matrix"

module CrymbleUI
  module Widgets
    module DirBrowser
      # Mouse-click double-click window. A second click on the SAME file
      # within this many milliseconds fires `on_accept` (auto-close the
      # dialog with that file). Matches the convention used elsewhere in
      # the framework (TextInput::DOUBLE_CLICK_THRESHOLD_MS = 500).
      DOUBLE_CLICK_THRESHOLD_MS = 500

      # VirtualMatrix adapter for file browser table
      # Row 0 = sticky header (Filename, Size, Date)
      # Rows 1..N = file/directory entries
      class MatrixAdapter
        include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

        # Data (set by host before each rebuild)
        property items : Array({String, String, String, File::Info}) = [] of {String, String, String, File::Info}
        property sort_column : Int32 = 0
        property sort_ascending : Bool = true
        property selected_filename : String = ""

        # Callbacks
        property on_navigate : Proc(String, Nil)? = nil
        property on_select_file : Proc(String, Nil)? = nil
        property on_sort : Proc(Int32, Nil)? = nil
        # Fired when the user double-clicks a file row (two clicks on the
        # same file name within DOUBLE_CLICK_THRESHOLD_MS). Hosts wire
        # this to "accept the dialog with this file selected".
        property on_accept : Proc(String, Nil)? = nil

        # Double-click bookkeeping — exposed as properties because the
        # host (a dialog/window panel) typically recreates the adapter on
        # every render frame, so state can't live on the adapter alone.
        # Host pattern:
        #   adapter.last_click_file = dialog.last_click_file
        #   adapter.last_click_time = dialog.last_click_time
        # and in `on_select_file` / `on_accept`, the host writes the
        # values back to the dialog so the NEXT frame re-seeds correctly.
        property last_click_file : String? = nil
        property last_click_time : Time::Instant = Time::Instant.new(0_i64, 0_u32)

        # Test seam: rewind the last-click stamp so the next click is
        # outside the double-click window without sleeping.
        def expire_last_click_for_test! : Nil
          @last_click_time = Time::Instant.new(0_i64, 0_u32)
        end

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
            bg = Theme.current.input_background
            selected = @selected_filename == name && !info.directory?
            btn_bg = selected ? Color.new(60_u8, 100_u8, 180_u8, 255_u8) : bg
            captured_name = name
            captured_is_dir = info.directory?
            Button.new(name, padding: 1.0,
              background_color: btn_bg, border_color: bg,
              text_color: Theme.current.text_default,
              text_align: TextAlign::Left,
              id: "dirbrowser_item_#{index}") do
              if captured_is_dir
                # Directory click is always a navigation, never a double-click
                # accept. Reset the file-side tracker so a stray prior file
                # click can't double-fire after intervening dir navigation.
                @last_click_file = nil
                @on_navigate.try &.call(captured_name.rstrip('/'))
              else
                # File click: check for double-click on the same name.
                now = Time.instant
                if @last_click_file == captured_name &&
                   (now - @last_click_time).total_milliseconds < DOUBLE_CLICK_THRESHOLD_MS
                  @last_click_file = nil  # prevent triple-click → re-fire
                  @on_accept.try &.call(captured_name)
                else
                  @last_click_file = captured_name
                  @last_click_time = now
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
