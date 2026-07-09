require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/dsl/builder"

# Direct-to-layer render: on a full rebuild of a viewport_cache content layer, a cell's primitives are
# drawn DIRECTLY into the layer buffer, skipping the per-cell RenderTexture (alloc + background
# capture/restore + blit). The buffer was just cleared to the uniform layer background and top-level
# cells tile without overlap, so the result is pixel-identical to the texture path — for a fraction of
# the cost. This spec proves both halves: the pixels are correct (get_pixel), and no per-cell texture
# was allocated (the cost win).

# A cell that fills its bounds with a solid color — Text does not render in the headless backend, but a
# fill_rect does, so get_pixel can verify it. (Mirrors ColorFillCell in virtual_matrix_blit_shift_spec.)
class DirectRenderColorCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  getter fill_color : CrymbleUI::Color

  def initialize(@fill_color : CrymbleUI::Color, id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), @fill_color)
    end
  end
end

class DirectRenderColorAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  CELL_COLOR = CrymbleUI::Color.new(200, 40, 40, 255)

  def initialize(@rows : Int32 = 40, @cols : Int32 = 8)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    DirectRenderColorCell.new(CELL_COLOR)
  end
end

class DirectRenderApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  getter! adapter : DirectRenderColorAdapter

  def build : CrymbleUI::Widget
    @adapter = DirectRenderColorAdapter.new(rows: 40, cols: 8)
    m = CrymbleUI::VirtualMatrix.new(adapter: @adapter.not_nil!, id: "direct_grid")
    m.show_rulers = false
    window("Test", 800, 600) do
      widget(m)
    end
  end
end

describe "VirtualMatrix direct-to-layer render on full rebuild" do
  it "produces correct cell pixels with no per-cell texture" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = DirectRenderApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("direct_grid").as(CrymbleUI::VirtualMatrix)
    content_layer = matrix.content_layer.not_nil!
    layer_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # CORRECTNESS: the top-left cell's fill color is present in the layer buffer. Sample 5px into
    # row 0 / col 0, in buffer coordinates (content position minus buffer_origin).
    bx = (5 - content_layer.buffer_origin.x).to_i
    by = (5 - content_layer.buffer_origin.y).to_i
    px = layer_backend.get_pixel(bx, by)
    px.should_not be_nil, "no pixel at buffer (#{bx}, #{by}) — cell not painted"
    px.not_nil!.should eq(DirectRenderColorAdapter::CELL_COLOR),
      "cell 0,0 should be #{DirectRenderColorAdapter::CELL_COLOR} but got #{px}"

    # MECHANISM (red before the direct path lands): a full rebuild of a viewport_cache content layer
    # renders each cell direct-to-layer, so no per-cell widget_backend is allocated. Before: every
    # visible cell owns a RenderTexture (the alloc+blit we measured); after: none do.
    cells = matrix.active_cells.values
    cells.should_not be_empty
    backendless = cells.count { |w| w.widget_backend.nil? }
    backendless.should eq(cells.size),
      "expected all #{cells.size} content cells direct-rendered (no widget_backend); " \
      "#{cells.size - backendless} still hold a texture"
  end
end
