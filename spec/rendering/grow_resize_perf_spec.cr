require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/widgets/window_panel"
require "../../src/widgets/button"
require "../../src/widgets/scroll_view"
require "../../src/layout/vstack"
require "../../src/layout/hstack"

# Build a floored panel holding a rows×cols button grid, settle it, begin a right-edge resize, then
# render ONE grow-frame and return that frame's absolute_bounds + measure counts.
def grow_frame_metrics(rows : Int32, cols : Int32) : {abs: Int32, measure: Int32}
  renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
  app = TestApp.new
  window = CrymbleUI::Window.new("T", 1600, 900)
  # Panel starts WIDER than its content (small buttons) so the grid is a non-fill body sitting inside the
  # floor with slack — the real "floored, content < panel" case. (A grid wider than the panel would floor
  # to exactly the panel width, i.e. it fills, and a fill body legitimately must re-layout on grow.)
  panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, 1100.0, 600.0)
  grid = CrymbleUI::VStack.new(spacing: 2.0)
  rows.times do |r|
    hs = CrymbleUI::HStack.new(spacing: 2.0)
    cols.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}", font_scale: -5, padding: 3.0) { }) }
    grid.add_child(hs)
  end
  panel.add_child(grid)
  window.add_child(panel)
  app.root_widget = window
  renderer.settle_rendering(app)

  right = panel.x + panel.width
  panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 300.0)) # grab the right edge
  renderer.render_frame(app)

  panel.on_mouse_move(CrymbleUI::Vec2.new(right + 40.0, panel.y + 300.0)) # drag it wider
  CrymbleUI::Widget.reset_absolute_bounds_count
  CrymbleUI::Widget.reset_measure_count
  renderer.render_frame(app)
  {abs: CrymbleUI::Widget.absolute_bounds_count, measure: CrymbleUI::Widget.measure_count}
end

# perf budget — a pure GROW of a floored panel must be O(1) in content size.
#
# Two independent O(content·depth) storms fire on a grow-frame if the grow path is naive:
#   1. absolute_bounds: the old repaint marking walk called the UNCACHED, O(depth) `absolute_bounds`
#      over EVERY widget, every grow-frame — pure waste under the floor (a grow only uncovers margin).
#   2. measure: the panel re-lays-out its whole content (`layout_children` → `@content.layout`) every
#      grow-frame with a growing constraint, re-measuring the whole tree even though a non-fill content's
#      layout is invariant under a grow. Fixed by handing content LOOSE constraints so `can_skip_layout?`
#      skips the grow (the content didn't use the slack); fill content (ScrollView) still re-lays-out.
# Both must be content-INDEPENDENT: their per-grow-frame cost must not scale with the number of buttons.
describe "grow-resize is O(1) in content size" do
  it "does not walk the content tree on a grow (absolute_bounds independent of button count)" do
    small = grow_frame_metrics(4, 4)[:abs]   # 16 buttons
    large = grow_frame_metrics(20, 20)[:abs] # 400 buttons
    puts "\n[grow O(1)] absolute_bounds/grow-frame — 16 buttons: #{small}, 400 buttons: #{large}"
    large.should be <= small * 2
  end

  it "does not re-measure the content tree on a grow (measure independent of button count)" do
    small = grow_frame_metrics(4, 4)[:measure]   # 16 buttons
    large = grow_frame_metrics(20, 20)[:measure] # 400 buttons
    puts "[grow O(1)] measure/grow-frame — 16 buttons: #{small}, 400 buttons: #{large}"
    large.should be <= small * 2
  end
end

# A ScrollView's content layer is viewport_cache (a buffer over-allocated to viewport + 2×cache_extent).
# The resize handler used to nil that backend on ANY size change → a fresh buffer + a re-blit of every
# visible cell EVERY grow-frame (the ScrollView panel's ~30% live-resize cost). But a grow that still
# fits the over-allocated buffer needs no new backend — the margin cells are already rendered and the
# per-frame recenter (handle_viewport_cache_scroll) fills any newly-visible ones selectively.
describe "grow-resize keeps the viewport-cache buffer" do
  it "does NOT recreate a ScrollView's backend on a grow that still fits the buffer" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 1600, 900)
    panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, 500.0, 500.0)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
    grid = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |r|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}", font_scale: -5, padding: 3.0) { }) }
      grid.add_child(hs)
    end
    sv.set_content(grid)
    panel.add_child(sv)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    content_layer = sv.content_layer.not_nil!
    right = panel.x + panel.width
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 250.0))
    renderer.render_frame(app)
    backend_before = content_layer.backend.try(&.object_id)

    # A small grow — well within the cache_extent (100px) margin, so the buffer still covers it.
    panel.on_mouse_move(CrymbleUI::Vec2.new(right + 20.0, panel.y + 250.0))
    renderer.render_frame(app)

    content_layer.backend_fits_bounds?.should be_true # precondition: the buffer still covers the viewport
    content_layer.backend.try(&.object_id).should eq(backend_before)
  end

  # Correctness: keeping the buffer must NOT leave the newly-exposed viewport blank (the hazard).
  # Content is wider than the viewport (default-size buttons) so a width grow reveals a previously-clipped
  # column of cells — they must be painted (from the pre-rendered cache_extent margin), not background.
  it "paints the newly-exposed cells on a grow (buffer not left blank)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 1600, 900)
    panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, 500.0, 500.0)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
    grid = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |r|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}") { }) } # default size → grid ≫ viewport
      grid.add_child(hs)
    end
    sv.set_content(grid)
    panel.add_child(sv)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    sv_before = sv.absolute_bounds
    right = panel.x + panel.width
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 250.0))
    renderer.render_frame(app)
    panel.on_mouse_move(CrymbleUI::Vec2.new(right + 60.0, panel.y + 250.0)) # +60px, within the 100px margin
    renderer.render_frame(app)
    sv_after = sv.absolute_bounds

    # Scan the strip that was OUTSIDE the viewport before and INSIDE after — it must contain button fill.
    strip_x0 = (sv_before.x + sv_before.width).to_i
    strip_x1 = (sv_after.x + sv_after.width).to_i
    y0 = sv_after.y.to_i + 4
    y1 = (sv_after.y + sv_after.height).to_i - 4
    found_button = false
    (strip_x0...strip_x1).each do |x|
      (y0...y1).step(2) do |y|
        if px = renderer.backend.get_pixel(x, y)
          found_button = true if px.r == 0 && px.g == 120 && px.b == 215
        end
      end
    end
    found_button.should be_true
  end

  # Keeping the buffer is only safe when the viewport fits at the LIVE buffer_origin, not merely
  # dimensionally: the compositor reads the viewport at (scroll - buffer_origin). At scroll 0 the origin
  # pins a fixed cache_extent leading margin, so once a grow exceeds cache_extent the viewport pokes past
  # the buffer and the composite CLAMPS → content shifts right, the left column goes blank. This grow is
  # LARGER than cache_extent (100px) — the band the two specs above (+20/+60) don't reach.
  it "does not shift content on a grow larger than cache_extent (positional buffer fit)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 1600, 900)
    panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, 500.0, 500.0)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
    grid = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |r|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}") { }) } # default size → grid ≫ viewport
      grid.add_child(hs)
    end
    sv.set_content(grid)
    panel.add_child(sv)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    right = panel.x + panel.width
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 250.0))
    renderer.render_frame(app)
    panel.on_mouse_move(CrymbleUI::Vec2.new(right + 160.0, panel.y + 250.0)) # +160px > cache_extent (100)
    renderer.render_frame(app)
    sv_after = sv.absolute_bounds

    # The viewport's LEADING (left) edge must still show content column 0 — not a blank strip pushed in
    # by a horizontal shift. Scan the leftmost ~20px of the viewport for button fill.
    found_left = false
    ((sv_after.x.to_i + 2)...(sv_after.x.to_i + 22)).each do |x|
      ((sv_after.y.to_i + 4)...((sv_after.y + sv_after.height).to_i - 4)).step(2) do |y|
        if px = renderer.backend.get_pixel(x, y)
          found_left = true if px.r == 0 && px.g == 120 && px.b == 215
        end
      end
    end
    found_left.should be_true
  end

  # Same hazard at a non-zero scroll (the quantized buffer_origin differs, and the leading-side margin can
  # be < cache_extent) — assert the composite does NOT clamp: viewport_sample_origin must equal the raw
  # (scroll - buffer_origin), i.e. the viewport fits the buffer at the live origin. Covers Finding-3/4.
  it "does not clamp the composite on a SCROLLED grow larger than cache_extent" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 1600, 900)
    panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, 500.0, 500.0)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
    grid = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |r|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}") { }) }
      grid.add_child(hs)
    end
    sv.set_content(grid)
    panel.add_child(sv)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(150.0, 90.0)) # scroll to a non-zero quantized origin
    renderer.render_frame(app)
    right = panel.x + panel.width
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 250.0))
    renderer.render_frame(app)
    panel.on_mouse_move(CrymbleUI::Vec2.new(right + 160.0, panel.y + 250.0)) # +160 > cache_extent
    renderer.render_frame(app)

    cl = sv.content_layer.not_nil!
    b = cl.backend.not_nil!
    sample = cl.viewport_sample_origin(b.width, b.height, cl.bounds.width.ceil.to_i, cl.bounds.height.ceil.to_i)
    unclamped = {(cl.scroll_offset.x - cl.buffer_origin.x).to_i, (cl.scroll_offset.y - cl.buffer_origin.y).to_i}
    sample.should eq(unclamped) # no clamp ⇒ viewport fits at the live origin ⇒ no shifted composite
  end

  # buffer_origin must stay WHOLE-valued even when the capacity clamp binds at a FRACTIONAL scroll: the
  # render path subtracts buffer_origin.to_i (truncate-first) while the composite truncates
  # (scroll - buffer_origin) (subtract-first) — they agree only for an integer origin, else a 1px seam
  # (shifted/blank leading column). The un-integerised clamp broke this; the sample-origin assertion above
  # can't see it (it compares the composite to itself).
  it "keeps buffer_origin integer after a clamped grow at fractional scroll (no 1px seam)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
    app = TestApp.new
    window = CrymbleUI::Window.new("T", 1600, 900)
    panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, 500.0, 500.0)
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
    grid = CrymbleUI::VStack.new(spacing: 2.0)
    20.times do |r|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      20.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}") { }) }
      grid.add_child(hs)
    end
    sv.set_content(grid)
    panel.add_child(sv)
    window.add_child(panel)
    app.root_widget = window
    renderer.settle_rendering(app)

    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(150.5, 90.5)) # FRACTIONAL scroll
    renderer.render_frame(app)
    right = panel.x + panel.width
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 250.0))
    renderer.render_frame(app)
    panel.on_mouse_move(CrymbleUI::Vec2.new(right + 160.0, panel.y + 250.0)) # +160 > cache_extent → clamp binds
    renderer.render_frame(app)

    cl = sv.content_layer.not_nil!
    cl.buffer_origin.x.should eq(cl.buffer_origin.x.round)
    cl.buffer_origin.y.should eq(cl.buffer_origin.y.round)
  end
end

# Build a ScrollView (content ≫ viewport) inside a floored panel, settled at 1600×900.
private def make_scrollview_panel(panel_w = 500.0, panel_h = 500.0)
  renderer = CrymbleUI::Testing::TestRenderer.new(1600, 900)
  app = TestApp.new
  window = CrymbleUI::Window.new("T", 1600, 900)
  panel = CrymbleUI::WindowPanel.new("P", 30.0, 60.0, panel_w, panel_h)
  sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both)
  grid = CrymbleUI::VStack.new(spacing: 2.0)
  20.times do |r|
    hs = CrymbleUI::HStack.new(spacing: 2.0)
    20.times { |c| hs.add_child(CrymbleUI::Button.new("#{r},#{c}") { }) }
    grid.add_child(hs)
  end
  sv.set_content(grid)
  panel.add_child(sv)
  window.add_child(panel)
  app.root_widget = window
  renderer.settle_rendering(app)
  {renderer, app, panel, sv}
end

# the recenter gate is now DERIVED from the composite reader (stricter than the old float+eps gate).
# Guard against a recenter-storm — a small within-cache_extent scroll must stay on the fast path and NOT
# recenter at all (neither the expensive full-recenter nor a blit-shift).
describe "viewport-cache scroll fast path is preserved" do
  it "a small within-cache_extent scroll does not recenter (no full-recenter, no blit-shift)" do
    renderer, app, _panel, sv = make_scrollview_panel
    cl = sv.content_layer.not_nil!
    ce = cl.cache_extent
    ce.should be > 0.0 # precondition: there IS a cache margin to stay within

    # Scroll a quarter of the cache margin — the viewport still fits the buffer, so the gate returns "fits".
    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(ce * 0.25, ce * 0.25))
    CrymbleUI::LayerRenderer.frame_full_recenter_count = 0
    CrymbleUI::LayerRenderer.frame_blit_shift_count = 0
    renderer.render_frame(app)

    CrymbleUI::LayerRenderer.frame_full_recenter_count.should eq(0)
    CrymbleUI::LayerRenderer.frame_blit_shift_count.should eq(0)
    # And the composite still doesn't clamp (fast path kept a fitting origin).
    b = cl.backend.not_nil!
    sample = cl.viewport_sample_origin(b.width, b.height, cl.bounds.width.ceil.to_i, cl.bounds.height.ceil.to_i)
    unclamped = {(cl.scroll_offset.x - cl.buffer_origin.x).to_i, (cl.scroll_offset.y - cl.buffer_origin.y).to_i}
    sample.should eq(unclamped)
  end

  # Shrink keeps the over-allocated buffer, leaving a large margin (M) and a now-stale origin; a
  # subsequent grow-back must recenter to a whole, fitting origin — the composite must not clamp.
  it "does not clamp the composite after a shrink-then-grow (stale large-M origin)" do
    renderer, app, panel, sv = make_scrollview_panel
    right = panel.x + panel.width

    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 250.0))
    renderer.render_frame(app)
    panel.on_mouse_move(CrymbleUI::Vec2.new(right - 180.0, panel.y + 250.0)) # shrink ~180px (buffer kept)
    renderer.render_frame(app)
    panel.on_mouse_move(CrymbleUI::Vec2.new(right + 20.0, panel.y + 250.0)) # grow back past the original width
    renderer.render_frame(app)
    panel.on_mouse_up(CrymbleUI::Vec2.new(right + 20.0, panel.y + 250.0))
    renderer.render_frame(app)

    cl = sv.content_layer.not_nil!
    b = cl.backend.not_nil!
    sample = cl.viewport_sample_origin(b.width, b.height, cl.bounds.width.ceil.to_i, cl.bounds.height.ceil.to_i)
    unclamped = {(cl.scroll_offset.x - cl.buffer_origin.x).to_i, (cl.scroll_offset.y - cl.buffer_origin.y).to_i}
    sample.should eq(unclamped) # no clamp ⇒ the recenter re-fit the viewport
    cl.buffer_origin.x.should eq(cl.buffer_origin.x.round)
    cl.buffer_origin.y.should eq(cl.buffer_origin.y.round)
  end
end

# perf gate (measure the delta — comparative, not an absolute time). The recenter gate is now stricter
# (it recenters in the near-capacity band the old float+eps gate skipped), so the risk is a recenter/realloc
# STORM. This asserts the cost stays bounded even at a NEAR-CAPACITY scroll (small margin — the band the new
# gate acts in): a small-grow resize sweep does at most ONE blit-shift per frame (per-frame coalescing),
# ZERO reallocs (keeps the buffer on a fitting grow), and ZERO expensive full-clear recenters. Recenter
# COUNTS are renderer-independent, so this is a valid headless gate; the --release stress_panel_demo eyeball
# covers the wall-clock/visual-stutter side ([[feedback_perf_profile_real_demo]]).
describe "viewport-cache recenter cost is bounded — no storm (perf)" do
  it "a near-capacity small-grow sweep stays O(frames): <=1 blit-shift/frame, 0 realloc, 0 full-recenter" do
    renderer, app, panel, sv = make_scrollview_panel
    cl = sv.content_layer.not_nil!

    # Scroll to the far (bottom-right) corner — the near-capacity, small-margin band where the buffer runs
    # into the data extent, the worst case for the stricter gate.
    max = CrymbleUI::Vec2.new(
      Math.max(0.0, sv.content_size.width - sv.viewport_size.width),
      Math.max(0.0, sv.content_size.height - sv.viewport_size.height)
    )
    max.x.should be > 0.0 # precondition: content overflows horizontally (there IS a far corner)
    sv.set_scroll_offset_for_test(max)
    renderer.render_frame(app)

    right = panel.x + panel.width
    panel.on_mouse_down(CrymbleUI::Vec2.new(right - 3.0, panel.y + 240.0))
    renderer.render_frame(app)

    frames = 0
    total_blit = 0
    total_full = 0
    total_realloc = 0
    8.times do |i|
      CrymbleUI::LayerRenderer.frame_blit_shift_count = 0
      CrymbleUI::LayerRenderer.frame_full_recenter_count = 0
      CrymbleUI::LayerRenderer.frame_realloc_count = 0
      # Small grows (+6px each, 48px total) — well within the kept-buffer margin, so no realloc.
      panel.on_mouse_move(CrymbleUI::Vec2.new(right + (i + 1) * 6.0, panel.y + 240.0))
      renderer.render_frame(app)
      frames += 1
      total_blit += CrymbleUI::LayerRenderer.frame_blit_shift_count
      total_full += CrymbleUI::LayerRenderer.frame_full_recenter_count
      total_realloc += CrymbleUI::LayerRenderer.frame_realloc_count
    end

    total_realloc.should eq(0)     # keep-buffer win preserved — no realloc storm from the new gate
    total_full.should eq(0)        # no expensive clear + full-rerender recenters on small grows
    total_blit.should be <= frames # coalesced: at most one blit-shift per frame → O(frames), not O(pixels)
  end
end
