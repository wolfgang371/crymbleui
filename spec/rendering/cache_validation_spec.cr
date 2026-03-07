require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/rendering/cache_validation"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/rendering/layer_renderer"
require "../../src/dsl/builder"
require "../../src/testing/configurable_matrix_adapter"

{% if flag?(:cache_validation) %}

# Test widget that can silently change its to_primitives() output without
# invalidating the primitive cache.  Used to verify that the validator detects
# stale-cache bugs (to_primitives returns fresh content, get_primitives returns stale).
class StaleCacheTestWidget < CrymbleUI::Widget
  @stale_mode = false

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100.0, 30.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    size = measure(constraints)
    @bounds = CrymbleUI::Rect.new(position, size)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    color = @stale_mode ? CrymbleUI::Color.new(0, 255, 0, 255) : CrymbleUI::Color.new(255, 0, 0, 255)
    [CrymbleUI::FillRect.new(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), color)] of CrymbleUI::DrawPrimitive
  end

  # Silently change output — does NOT call mark_needs_render or invalidate cache
  def enable_stale_mode!
    @stale_mode = true
  end
end

# Local subclass: use Text (no data hash) for headless spec testing
class CompoundContentValidationAdapter < ConfigurableMatrixAdapter
  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end
end

# DSL-style app matching demo configuration (compound cells + sticky headers).
class CompoundContentValidationTestApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    adapter = CompoundContentValidationAdapter.new(
      nrhl: 2, nchl: 2, rhs: 3, chs: 3, lrs: 10, lcs: 10
    )
    window("Test", 1400, 900) do
      expanded do
        widget(CrymbleUI::VirtualMatrix.new(
          adapter: adapter,
          id: "cv_grid",
        ))
      end
    end
  end
end

describe "Cache Validation" do
  before_each do
    CrymbleUI::CacheValidation.clear_failures!
    CrymbleUI::CacheValidation.enable_all
  end

  after_each do
    CrymbleUI::CacheValidation.disable_all
  end

  describe "CacheValidation module" do
    it "starts with no failures" do
      CrymbleUI::CacheValidation.failures.should be_empty
    end

    it "enables and disables cache levels" do
      CrymbleUI::CacheValidation.disable_all
      CrymbleUI::CacheValidation.enabled?(:immediate_mode).should be_false

      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.enabled?(:immediate_mode).should be_true

      CrymbleUI::CacheValidation.disable(:immediate_mode)
      CrymbleUI::CacheValidation.enabled?(:immediate_mode).should be_false
    end

    it "enable_all enables all levels" do
      CrymbleUI::CacheValidation.disable_all
      CrymbleUI::CacheValidation.enable_all
      CrymbleUI::CacheValidation.enabled?(:immediate_mode).should be_true
      CrymbleUI::CacheValidation.enabled?(:blit_shift).should be_true
    end

    it "compares identical pixel arrays with no mismatches" do
      pixels = [0xFF0000FF_u32, 0x00FF00FF_u32, 0x0000FFFF_u32, 0xFFFFFFFF_u32]
      count, total, first = CrymbleUI::CacheValidation.compare_pixels(pixels, pixels, 2, 2)
      count.should eq 0
      total.should eq 4
      first.should be_nil
    end

    it "detects mismatched pixels" do
      a = [0xFF0000FF_u32, 0x00FF00FF_u32]
      b = [0xFF0000FF_u32, 0x00000000_u32]
      count, total, first = CrymbleUI::CacheValidation.compare_pixels(a, b, 2, 1)
      count.should eq 1
      total.should eq 2
      first.should_not be_nil
      first.not_nil![0].should eq 1 # x=1
      first.not_nil![1].should eq 0 # y=0
    end

    it "respects per-channel tolerance" do
      # Differ by 1 in red channel
      a = [0xFF0000FF_u32]
      b = [0xFE0000FF_u32]
      CrymbleUI::CacheValidation.tolerance = 2
      count, _, _ = CrymbleUI::CacheValidation.compare_pixels(a, b, 1, 1)
      count.should eq 0 # within tolerance

      CrymbleUI::CacheValidation.tolerance = 0
      count, _, _ = CrymbleUI::CacheValidation.compare_pixels(a, b, 1, 1)
      count.should eq 1 # outside tolerance

      CrymbleUI::CacheValidation.tolerance = 2 # restore default
    end

    it "assert_no_failures! passes when no failures" do
      CrymbleUI::CacheValidation.assert_no_failures! # should not raise
    end

    it "assert_no_failures! raises when failures exist" do
      CrymbleUI::CacheValidation.record_failure(
        CrymbleUI::CacheValidation::CacheLevel::ImmediateMode,
        "test_layer", 10, 100, {5, 5, 0xFF0000FF_u32, 0x00FF00FF_u32}
      )
      expect_raises(CrymbleUI::CacheValidation::ValidationError) do
        CrymbleUI::CacheValidation.assert_no_failures!
      end
    end

    it "increments frame counter" do
      CrymbleUI::CacheValidation.clear_failures!
      CrymbleUI::CacheValidation.frame_counter.should eq 0
      CrymbleUI::CacheValidation.increment_frame!
      CrymbleUI::CacheValidation.frame_counter.should eq 1
    end
  end

  describe "capture_region_pixels" do
    it "captures pixels from TestRenderBackend" do
      backend = CrymbleUI::Testing::TestRenderBackend.new(10, 10, CrymbleUI::Color.new(255, 0, 0, 255))
      pixels = backend.capture_region_pixels(0, 0, 2, 2)
      pixels.size.should eq 4
      # Red pixel packed: R=255, G=0, B=0, A=255 → 0xFF0000FF
      pixels[0].should eq 0xFF0000FF_u32
    end

    it "captures mixed colors" do
      backend = CrymbleUI::Testing::TestRenderBackend.new(10, 10, CrymbleUI::Color.new(255, 255, 255, 255))
      # Paint a green pixel at (1,0)
      backend.set_pixel(1, 0, CrymbleUI::Color.new(0, 255, 0, 255))

      pixels = backend.capture_region_pixels(0, 0, 2, 1)
      pixels.size.should eq 2
      pixels[0].should eq 0xFFFFFFFF_u32 # white
      pixels[1].should eq 0x00FF00FF_u32 # green
    end
  end

  describe "immediate mode validation" do
    it "detects stale primitive cache (to_primitives vs get_primitives)" do
      # A widget whose to_primitives() can silently change without invalidating
      # the primitive cache.  Simulates a bug where mark_needs_render is missing.
      stale_widget = StaleCacheTestWidget.new

      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      # Place stale widget in the middle so it stays visible
      5.times { vstack.add_child(CrymbleUI::Button.new("Pad") { }) }
      vstack.add_child(stale_widget)
      15.times { vstack.add_child(CrymbleUI::Button.new("Pad") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render — caches red primitives
      renderer.render_frame(app)

      # Now silently change output color WITHOUT invalidating primitive cache
      stale_widget.enable_stale_mode!

      CrymbleUI::CacheValidation.clear_failures!

      # Dirty the content layer by changing a DIFFERENT widget (not the stale one).
      # ScrollView.on_mouse_wheel only marks scrollbar layer dirty, not content,
      # so we use Button#text= which calls mark_needs_render → content layer render.
      # The stale widget is NOT dirty → its cached RED pixels stay in the buffer.
      # The validator calls to_primitives() on ALL visible widgets → returns GREEN.
      first_button = vstack.children.first.as(CrymbleUI::Button)
      first_button.text = "Changed"
      renderer.render_frame(app)

      # The validator uses to_primitives() (returns GREEN) while the cached
      # pipeline uses get_primitives() (returns stale RED).  Must detect mismatch.
      CrymbleUI::CacheValidation.failures.should_not be_empty
      CrymbleUI::CacheValidation.failures.first.cache_level.should eq(
        CrymbleUI::CacheValidation::CacheLevel::ImmediateMode
      )
    end

    it "validates viewport cache during small vertical scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      20.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      # Initial render
      renderer.render_frame(app)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll and render — validation runs automatically per frame
      3.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end

    it "validates viewport cache after vertical scroll round-trip (down then up)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { |i| vstack.add_child(CrymbleUI::Button.new("Btn #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll down far enough to trigger multiple recenters
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # Scroll back up
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end

    it "validates viewport cache with distinct colored widgets" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)

      red = CrymbleUI::Color.new(255, 0, 0, 255)
      green = CrymbleUI::Color.new(0, 255, 0, 255)
      blue = CrymbleUI::Color.new(0, 0, 255, 255)

      10.times { |i|
        btn = CrymbleUI::Button.new("R#{i}") { }
        btn.background_color = red
        vstack.add_child(btn)
      }
      10.times { |i|
        btn = CrymbleUI::Button.new("G#{i}") { }
        btn.background_color = green
        vstack.add_child(btn)
      }
      10.times { |i|
        btn = CrymbleUI::Button.new("B#{i}") { }
        btn.background_color = blue
        vstack.add_child(btn)
      }

      scroll_view.set_content(vstack)
      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll through color regions
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # Scroll back
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end
  end

  describe "blit-shift validation" do
    it "blit-shift preserves pixels during vertical scroll recenter" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { |i| vstack.add_child(CrymbleUI::Button.new("Item #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll enough to trigger blit-shift (past cache_extent boundary)
      20.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end

    it "blit-shift preserves pixels during scroll round-trip" do
      renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)

      scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
      vstack = CrymbleUI::VStack.new(spacing: 5.0)
      50.times { |i| vstack.add_child(CrymbleUI::Button.new("Item #{i}") { }) }
      scroll_view.set_content(vstack)

      window.add_child(scroll_view)
      app.root_widget = window

      renderer.render_frame(app)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll down
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      # Scroll back up
      15.times do
        scroll_view.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), CrymbleUI::Vec2.new(200.0, 150.0))
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end
  end

  describe "immediate mode with compound cells" do
    it "validates compound cells after vertical scroll" do
      renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
      app = CompoundContentValidationTestApp.new
      app.build_tree
      renderer.settle_rendering(app)

      matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
      center = CrymbleUI::Vec2.new(700.0, 450.0)

      CrymbleUI::CacheValidation.disable_all
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll down 7 wheel events — compound cells with sticky rows
      7.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end

    it "validates compound cells after vertical scroll round-trip through recenter" do
      renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
      app = CompoundContentValidationTestApp.new
      app.build_tree
      renderer.settle_rendering(app)

      matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
      center = CrymbleUI::Vec2.new(700.0, 450.0)

      CrymbleUI::CacheValidation.disable_all
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll down 15 events — triggers recenter with compound cells
      15.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
        renderer.render_frame(app)
      end

      # Scroll back up 15 events
      15.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), center)
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end

    it "validates compound cells after horizontal scroll round-trip" do
      renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
      app = CompoundContentValidationTestApp.new
      app.build_tree
      renderer.settle_rendering(app)

      matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
      center = CrymbleUI::Vec2.new(700.0, 450.0)

      CrymbleUI::CacheValidation.disable_all
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll right 15 events — triggers horizontal recenter with compound cells
      # Bug 2: merged cells not restored after hscroll round-trip (~1030px at 2 hops)
      15.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.0), center)
        renderer.render_frame(app)
      end

      # Scroll back left 15 events
      15.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(1.0, 0.0), center)
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end

    it "validates compound cells after deep horizontal scroll (multiple recenters)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
      app = CompoundContentValidationTestApp.new
      app.build_tree
      renderer.settle_rendering(app)

      matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
      center = CrymbleUI::Vec2.new(700.0, 450.0)

      CrymbleUI::CacheValidation.disable_all
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!

      # Scroll right 35 events — deep enough for 3+ recenters (~1050px)
      # This is the scenario that triggers black pixels from compound cell width bug
      35.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.0), center)
        renderer.render_frame(app)
      end

      # Scroll back left
      35.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(1.0, 0.0), center)
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end

    it "validates compound cells after diagonal scroll (both axes)" do
      renderer = CrymbleUI::Testing::TestRenderer.new(1400, 900)
      app = CompoundContentValidationTestApp.new
      app.build_tree
      renderer.settle_rendering(app)

      matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
      center = CrymbleUI::Vec2.new(700.0, 450.0)

      CrymbleUI::CacheValidation.disable_all
      CrymbleUI::CacheValidation.enable(:immediate_mode)
      CrymbleUI::CacheValidation.clear_failures!

      # Alternate horizontal and vertical scrolling — stresses both axes
      20.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(-1.0, 0.0), center)
        renderer.render_frame(app)
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, -1.0), center)
        renderer.render_frame(app)
      end

      # Return to origin
      20.times do
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(1.0, 0.0), center)
        renderer.render_frame(app)
        matrix = app.find("cv_grid").as(CrymbleUI::VirtualMatrix)
        matrix.on_mouse_wheel(CrymbleUI::Vec2.new(0.0, 1.0), center)
        renderer.render_frame(app)
      end

      CrymbleUI::CacheValidation.assert_no_failures!
    end
  end
end
{% else %}
# Sanity check: without -Dcache_validation flag, CacheValidation module should not exist
describe "Cache Validation (disabled)" do
  it "has zero overhead when compile flag is absent" do
    {% if flag?(:cache_validation) %}
      raise "This should not execute without -Dcache_validation"
    {% end %}
    true.should be_true
  end
end
{% end %}
