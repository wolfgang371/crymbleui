require "../src/crymble-ui"
require "../src/testing/configurable_matrix_adapter"

class VirtualMatrixDemoApp < CrymbleUI::App
  state num_col_header_levels : Int32 = 2
  state num_row_header_levels : Int32 = 2
  state num_row_header_span : Int32 = 3
  state num_col_header_span : Int32 = 3
  state leaf_row_span : Int32 = 10
  state leaf_col_span : Int32 = 10

  @adapter : ConfigurableMatrixAdapter?
  @last_config : {Int32, Int32, Int32, Int32, Int32, Int32}?

  private def current_config
    {num_row_header_levels, num_col_header_levels,
     num_row_header_span, num_col_header_span,
     leaf_row_span, leaf_col_span}
  end

  private def ensure_adapter : ConfigurableMatrixAdapter
    config = current_config
    if @last_config != config || @adapter.nil?
      @last_config = config
      adapter = ConfigurableMatrixAdapter.new(*config)
      @adapter = adapter
      adapter
    else
      @adapter.not_nil!
    end
  end

  def build : CrymbleUI::Widget
    adapter = ensure_adapter

    window("VirtualMatrix Demo", 1400, 900) do
      aligned_layer(align: CrymbleUI::Alignment::TopRight, margin: 10.0, z_index: 100) do
        cpu_monitor
      end

      vstack(padding: 10.0, spacing: 5.0) do
        text("VirtualMatrix Demo", color: CrymbleUI::Color.new(0, 0, 0, 255), font_scale: 2)

        hstack(spacing: 10.0) do
          config_control("col_hdr_levels", num_col_header_levels) { |v| self.num_col_header_levels = v.clamp(0, 5) }
          config_control("col_hdr_span", num_col_header_span) { |v| self.num_col_header_span = v.clamp(1, 9) }
        end
        hstack(spacing: 10.0) do
          config_control("row_hdr_levels", num_row_header_levels) { |v| self.num_row_header_levels = v.clamp(0, 5) }
          config_control("row_hdr_span", num_row_header_span) { |v| self.num_row_header_span = v.clamp(1, 9) }
        end
        hstack(spacing: 10.0) do
          config_control("leaf_row_span", leaf_row_span) { |v| self.leaf_row_span = v.clamp(1, 99) }
          config_control("leaf_col_span", leaf_col_span) { |v| self.leaf_col_span = v.clamp(1, 99) }
        end

        # Size summary
        text("Size: #{adapter.total_cols}x#{adapter.total_rows} (#{adapter.data_cols} data cols + #{num_row_header_levels} hdr cols, #{adapter.data_rows} data rows + #{num_col_header_levels} hdr rows)")

        # The matrix
        expanded do
          widget(CrymbleUI::VirtualMatrix.new(
            adapter: adapter,
            id: "config_matrix",
            cursor_highlight_delta: -30,
            content_background_color: CrymbleUI::Color.new(230, 230, 230, 255),
          ))
        end

        # Keyboard help
        hstack(spacing: 20.0) do
          text("Arrow keys: Navigate | Type: Direct edit | Enter: Full edit | Esc: Cancel | Scroll: Mouse wheel")
        end
      end
    end
  end

  # Helper: renders "name: value [-] [+]" control group
  private def config_control(name : String, value : Int32, &block : Int32 -> Nil)
    hstack(spacing: 3.0) do
      text("#{name}: #{value}", color: CrymbleUI::Color.new(0, 0, 0, 255))
      button("-", padding: 5.0) { block.call(value - 1) }
      button("+", padding: 5.0) { block.call(value + 1) }
    end
  end
end

# Run the application
CrymbleUI.run(VirtualMatrixDemoApp.new)
