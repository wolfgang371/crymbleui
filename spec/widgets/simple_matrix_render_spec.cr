require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/simple_matrix"

# Render-level specs for the `matrix` DSL sugar. Validates that an embedded
# SimpleMatrixAdapter-driven VirtualMatrix actually fits its intended footprint
# without overflow (no horizontal scrollbar) and without truncating the
# widest content (e.g. a button caption). Drives VM through the real render
# path, then inspects the resulting column widths.

describe "matrix DSL — embedded rendering" do
  it "column widths accommodate the widest cell (button not truncated)" do
    # App with just a matrix inside a vstack, width-bounded by the window.
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 600, 300)

    # Construct matrix adapter inline (mirror what the DSL builds).
    builder = CrymbleUI::SimpleMatrixBuilder.new
    builder.header "", "Table", "+Records"
    builder.row do |r|
      r << CrymbleUI::Checkbox.new(text: "", checked: true).as(CrymbleUI::Widget)
      r.text("Allocations")
      r.text("+15")
    end
    builder.row do |r|
      r << CrymbleUI::Checkbox.new(text: "", checked: true).as(CrymbleUI::Widget)
      r.text("Cities")
      r.text("+12")
    end
    adapter = CrymbleUI::SimpleMatrixAdapter.new(
      rows: builder.rows,
      sticky_row_count: builder.header_count,
      header_row_count: builder.header_count,
    )
    vm = CrymbleUI::VirtualMatrix.new(adapter: adapter, id: "test_matrix")
    vm.shrink_to_content = true
    vm.show_rulers = false
    vm.max_height = 200.0

    vstack = CrymbleUI::VStack.new
    vstack.add_child(vm)
    window.add_child(vstack)
    app.root_widget = window

    renderer = CrymbleUI::Testing::TestRenderer.new(600, 300)
    renderer.render_frame(app)

    # The VM's intrinsic width should fit inside the window (no overflow
    # horizontally → no horizontal scrollbar ever needed).
    vm.bounds.width.should be <= 600.0

    # Text columns: column 1 should be wide enough for "Allocations".
    # Measuring the widest cell text gives us the expected minimum.
    loose = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(Float64::INFINITY, Float64::INFINITY))
    widest_name = CrymbleUI::Text.new("Allocations").measure(loose).width
    # VM stores col widths in frame-height multiples.
    fh = CrymbleUI::VirtualMatrix::FRAME_HEIGHT_BASE * CrymbleUI::FontSizing.zoom_factor
    col1_width_px = vm.@col_widths[1] * fh
    col1_width_px.should be >= widest_name  # column is at least text-wide
  end

  it "includes a button's full width + padding (not clipped)" do
    # Build a row with a text cell and a wide button — verify the button's
    # column is sized to the button's measured width (text + 2*padding).
    builder = CrymbleUI::SimpleMatrixBuilder.new
    builder.header "Table", ""
    builder.row do |r|
      r.text("short")
      r << CrymbleUI::Button.new("→ Shape", padding: 3.0).as(CrymbleUI::Widget)
    end
    adapter = CrymbleUI::SimpleMatrixAdapter.new(
      rows: builder.rows,
      sticky_row_count: 1,
      header_row_count: 1,
    )

    # Expected widths (px) via direct widget.measure.
    loose = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(Float64::INFINITY, Float64::INFINITY))
    button_width = CrymbleUI::Button.new("→ Shape", padding: 3.0).measure(loose).width
    fh = CrymbleUI::VirtualMatrix::FRAME_HEIGHT_BASE * CrymbleUI::FontSizing.zoom_factor

    rows, cols = adapter.get_sizes
    # Column 1 is the button column.
    col1_px = cols[1] * fh
    col1_px.should be >= button_width
  end
end
