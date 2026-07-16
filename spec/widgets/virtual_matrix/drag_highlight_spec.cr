require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# Adapter: every cell has content, single-cell drag bounding boxes.
private class DragProbeAdapter
  include CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("R#{row}C#{col}")
  end

  def cell_has_content?(row : Int32, col : Int32) : Bool
    true
  end

  def cell_move(fr : Int32, fc : Int32, tr : Int32, tc : Int32) : Tuple(Int32, Int32)
    {tr, tc}
  end

  def cell_get_name(row : Int32, col : Int32) : String
    "R#{row}C#{col}"
  end

  def get_scrollorder : {Array(Int32), Array(Int32)}
    {(0...10).to_a, (0...5).to_a}
  end
end

# Opaque salmon — see-through comes from the drag layer's opacity, not fill alpha.
private SALMON = CrymbleUI::Color.new(204_u8, 102_u8, 102_u8, 255_u8)

private def build_probe_matrix
  renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
  app = TestApp.new
  matrix = CrymbleUI::VirtualMatrix.new(adapter: DragProbeAdapter.new, id: "drag_probe")
  app.root_widget = matrix
  app.build_tree
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
  renderer.render_frame(app)
  {renderer, app, matrix}
end

# Salmon fill_rects currently emitted by the DRAG overlay widget.
private def drag_decals(matrix) : Array(CrymbleUI::FillRect)
  layer = matrix.drag_overlay_layer.not_nil!
  widget = layer.widgets.first
  widget.to_primitives(widget.bounds)
    .select(&.is_a?(CrymbleUI::FillRect)).map(&.as(CrymbleUI::FillRect))
    .select { |fr| fr.color == SALMON }
end

describe "VirtualMatrix drag highlight" do
  describe "early-drag suppression (no salmon on a plain click)" do
    it "paints NO drag decal on a plain mouse_down over a content cell" do
      _r, _app, matrix = build_probe_matrix
      matrix.on_mouse_down(CrymbleUI::Vec2.new(80.0, 50.0))
      # Source is set (so DragManager can build the ghost) but PROVISIONAL.
      matrix.@drag_source_cell.should_not be_nil
      matrix.drag_source_provisional?.should be_true
      drag_decals(matrix).size.should eq(0)
    end

    it "paints the source decal once a real drag crosses the threshold" do
      renderer, app, matrix = build_probe_matrix
      renderer.mouse_down(80.0, 50.0)
      drag_decals(matrix).size.should eq(0) # still provisional
      renderer.mouse_move(80.0, 58.0)       # past the 5px threshold → on_drag_start
      app.drag_manager.dragging?.should be_true
      matrix.drag_source_provisional?.should be_false
      drag_decals(matrix).size.should be >= 1
    end

    it "clears the provisional source on a mouse_up without a drag" do
      renderer, _app, matrix = build_probe_matrix
      renderer.mouse_down(80.0, 50.0)
      renderer.mouse_up(80.0, 50.0)
      matrix.@drag_source_cell.should be_nil
      drag_decals(matrix).size.should eq(0)
    end
  end

  describe "cut highlight (external, committed source)" do
    it "paints the decal immediately when an app sets drag_source_cell (a cut)" do
      _r, _app, matrix = build_probe_matrix
      matrix.drag_source_cell = {2, 1} # app-level cut — committed, not provisional
      matrix.drag_source_provisional?.should be_false
      drag_decals(matrix).size.should eq(1)
    end
  end

  describe "survives a rebuild/reconcile (the decal must stay composited)" do
    # Real bug: after copy_state_from (DSL rebuild), the drag layer kept its OLD
    # owner_widget, so Layer.active_layers#in_tree? dropped it → the compositor
    # never drew it → invisible in the running app (which rebuilds constantly),
    # while headless tests that never rebuilt showed it fine. The cursor overlay
    # was re-synced; the drag overlay was not.
    it "re-syncs the drag overlay layer's owner to the new matrix on copy_state_from" do
      _r, _app, old = build_probe_matrix
      old.drag_source_cell = {2, 1} # an armed cut highlight

      new = CrymbleUI::VirtualMatrix.new(adapter: DragProbeAdapter.new, id: "drag_probe")
      new_app = TestApp.new
      new_app.root_widget = new
      new_app.build_tree
      new.copy_state_from(old) # the reconcile hook
      new.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)

      layer = new.drag_overlay_layer.not_nil!
      # Owner must be the NEW matrix, or in_tree? fails and the compositor skips it.
      layer.owner_widget.not_nil!.same?(new).should be_true
      layer.in_tree?(new).should be_true
      # And it must be discoverable by the compositor's layer collection.
      CrymbleUI::Layer.active_layers(new).map(&.id).should contain(layer.id)
      # (paired with the long-standing cursor overlay re-sync)
      new.cursor_overlay_layer.not_nil!.owner_widget.not_nil!.same?(new).should be_true
    end
  end

  describe "salmon survives SFML's two-stage layer compositing in every theme" do
    it "uses Normal blend (cursor band layer flips per-theme; the decal must not)" do
      _r, _app, matrix = build_probe_matrix
      matrix.drag_overlay_layer.not_nil!.blend_mode.should eq(CrymbleUI::BlendMode::Normal)
    end

    it "paints an OPAQUE fill and takes see-through from layer opacity, not fill alpha" do
      renderer, app, matrix = build_probe_matrix
      matrix.drag_source_cell = {2, 1}
      matrix.mark_drag_overlay_dirty
      renderer.settle_rendering(app)
      layer = matrix.drag_overlay_layer.not_nil!
      rect = drag_decals(matrix).first
      lx = (rect.bounds.x + rect.bounds.width / 2).to_i
      ly = (rect.bounds.y + rect.bounds.height / 2).to_i
      # A semi-transparent fill on a Normal-blend RT is the bug: the GPU premultiplies
      # it over transparent-black (salmon → muddy grey), composting to an invisible
      # tint. The RT MUST be opaque; see-through comes from layer.opacity.
      layer.backend.as(CrymbleUI::Testing::TestRenderBackend).get_pixel(lx, ly).not_nil!.a.should eq(255_u8)
      layer.opacity.should be < 1.0
    end

    # Faithful on-screen repro. TestRenderBackend#fill_rect OVERWRITES the layer buffer,
    # so it does NOT model SFML drawing a semi-transparent fill onto a transparent-BLACK
    # RenderTexture (which premultiplies salmon → muddy grey → invisible on a light bg).
    # Reproduce SFML's two stages here from the layer buffer + layer.opacity, so the
    # regression (a semi-transparent fill) is caught HEADLESSLY: it composites to a
    # near-grey (r−g≈25) and fails the "vivid salmon" bar; the opaque+opacity fix passes.
    {% for theme in [:light, :dark] %}
    it "on-screen decal is a vivid salmon (not the muddy grey of the premultiply bug), {{theme.id}} theme" do
      prev = CrymbleUI::Theme.current_name
      begin
        CrymbleUI::Theme.set({{theme}})
        renderer, app, matrix = build_probe_matrix
        matrix.drag_source_cell = {2, 1}
        matrix.mark_drag_overlay_dirty
        renderer.settle_rendering(app)

        layer = matrix.drag_overlay_layer.not_nil!
        rect = drag_decals(matrix).first
        lx = (rect.bounds.x + rect.bounds.width / 2).to_i
        ly = (rect.bounds.y + rect.bounds.height / 2).to_i
        fill = layer.backend.as(CrymbleUI::Testing::TestRenderBackend).get_pixel(lx, ly).not_nil!

        # SFML stage 1 — draw fill onto the transparent-black RT (BlendAlpha):
        # RT.rgb = fill.rgb * fill.a  (premultiplied); RT.a = fill.a.
        af = fill.a / 255.0
        rt_r, rt_g, rt_b = fill.r * af, fill.g * af, fill.b * af
        # SFML stage 2 — composite the RT sprite over a light background, sprite alpha
        # scaled by layer.opacity: out = RT.rgb * srcA + bg * (1 - srcA), srcA = RT.a * opacity.
        src_a = af * layer.opacity
        bg = 255.0 # worst case for a light theme (pure white); the decal must still read salmon
        out_r = rt_r * src_a + bg * (1 - src_a)
        out_g = rt_g * src_a + bg * (1 - src_a)
        out_b = rt_b * src_a + bg * (1 - src_a)

        (out_r - out_g).should be > 40.0 # vivid salmon; the premultiply bug lands at ≈25
        (out_r - out_b).should be > 40.0
      ensure
        CrymbleUI::Theme.set(prev)
      end
    end
    {% end %}
  end
end
