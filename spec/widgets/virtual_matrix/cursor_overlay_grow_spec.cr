require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"

# follow-up: lock the cursor-overlay clear-on-grow behavior that was previously UNTESTED.
# On a grow WITHIN its (over-allocated) backend, the cursor overlay layer must be CLEARED so its
# CachePolicy::Never highlight band repaints over a clean buffer (no stale short band). This is the
# generic Layer#clear_on_grow mechanism; without it the layer is not cleared on such a grow (the
# former per-widget guard in setup_cursor_overlay_layer). Mechanism-level (clear happened), not a
# fragile pixel probe — the additive highlight's pixel appearance is left to a live check.
describe "VirtualMatrix cursor overlay: clear-on-grow" do
  it "clears the cursor overlay layer on a grow within its backend" do
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 600)
    app = TestApp.new
    matrix = CrymbleUI::VirtualMatrix.new(rows: 40, cols: 4, id: "cur")
    app.root_widget = matrix
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0)), CrymbleUI::Vec2.zero)
    renderer.settle_rendering(app)

    overlay = matrix.cursor_overlay_layer.not_nil!
    backend = overlay.backend.as(CrymbleUI::Testing::TestRenderBackend)
    before = backend.clear_count

    # Grow a little — small enough to stay within the over-allocated backend (no recreate), so the
    # ONLY thing that can clear the overlay is clear_on_grow (not the !backend_fits_bounds? branch).
    matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 310.0)), CrymbleUI::Vec2.zero)
    renderer.render_frame(app)

    overlay.backend.should be(backend)            # same backend object → not recreated → the clear is clear_on_grow's
    (backend.clear_count - before).should be >= 1 # …and it was cleared
  end
end
