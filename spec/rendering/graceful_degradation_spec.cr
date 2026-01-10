require "../spec_helper"
require "../../src/testing/test_renderer"

# Tests for graceful degradation (Option A + Option C)
# These tests verify that:
# 1. Exceptions during render don't crash the app
# 2. State is properly reset after exception
# 3. Next frame renders correctly after recovery
# 4. Invalid widgets (zero-size, NaN bounds) are skipped gracefully

# Widget that throws during rendering (for testing exception recovery)
class ExplodingWidget < CrymbleUI::Widget
  property should_explode : Bool = true

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100.0, 50.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 100.0, 50.0)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    if @should_explode
      raise "Intentional explosion for testing graceful degradation"
    end
    # Return a simple rectangle when not exploding
    [CrymbleUI::FillRect.new(bounds, CrymbleUI::Color.new(255_u8, 0_u8, 0_u8, 255_u8))] of CrymbleUI::DrawPrimitive
  end
end

# Widget with zero-size bounds (for testing validation)
class ZeroSizeWidget < CrymbleUI::Widget
  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(0.0, 0.0)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 0.0, 0.0)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    # This should never be called if validation works
    raise "ZeroSizeWidget.to_primitives should not be called"
  end
end

# Widget with NaN bounds at render time (for testing validation)
# Has valid measure() to not break layout math, but sets NaN bounds in perform_layout
class NaNBoundsWidget < CrymbleUI::Widget
  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(50.0, 30.0)  # Valid size for layout
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    # Set invalid bounds AFTER layout math completes
    @bounds = CrymbleUI::Rect.new(position.x, position.y, Float64::NAN, Float64::NAN)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    # This should never be called if validation works
    raise "NaNBoundsWidget.to_primitives should not be called"
  end
end

# Widget with infinite bounds at render time (for testing validation)
# Has valid measure() to not break layout math, but sets infinite bounds in perform_layout
class InfiniteBoundsWidget < CrymbleUI::Widget
  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(50.0, 30.0)  # Valid size for layout
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    # Set invalid bounds AFTER layout math completes
    @bounds = CrymbleUI::Rect.new(position.x, position.y, Float64::INFINITY, Float64::INFINITY)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    # This should never be called if validation works
    raise "InfiniteBoundsWidget.to_primitives should not be called"
  end
end

# No separate app classes needed - tests use TestApp with root_widget=
# (same pattern as passing cache reset tests)

describe "Graceful Degradation" do
  describe "Option A: Frame-Boundary Exception Handling" do
    it "recovers from exception during render and continues" do
      exploding = ExplodingWidget.new
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(exploding)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new

      # First frame - explodes (exception caught by graceful degradation)
      renderer.render_frame(app)
      renderer.exceptions_caught.should eq 1

      # Disable explosion for recovery
      exploding.should_explode = false

      # Second frame should work normally after recovery
      renderer.reset_counters
      renderer.render_frame(app)

      # Should have rendered successfully (render_frame completed)
      renderer.render_frame_count.should eq 1
    end

    it "calls reset_all_caches on exception" do
      exploding = ExplodingWidget.new
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(exploding)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new

      # First render - explodes (exception caught by graceful degradation)
      renderer.render_frame(app)
      renderer.exceptions_caught.should eq 1

      # render_frame completed without crashing
      renderer.render_frame_count.should eq 1

      # mark_needs_layout was called (part of exception handling)
      window.needs_layout?.should be_true
    end

    it "exception handler sets needs_layout for recovery" do
      exploding = ExplodingWidget.new
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(exploding)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new

      # First render - explodes
      renderer.render_frame(app)
      renderer.exceptions_caught.should eq 1

      # After exception handling, root should need layout
      # (handle_frame_exception calls mark_needs_layout)
      window.needs_layout?.should be_true
    end

    it "next frame renders correctly after recovery" do
      exploding = ExplodingWidget.new
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(exploding)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new

      # First frame - explodes
      renderer.render_frame(app)
      renderer.exceptions_caught.should eq 1

      # Disable explosion
      exploding.should_explode = false

      # Mark needs layout to force re-render
      app.root.try(&.mark_needs_layout)

      # Second frame - should render normally
      renderer.reset_counters
      renderer.render_frame(app)

      # Should have rendered (primitive from ExplodingWidget)
      renderer.primitive_count.should be > 0
    end
  end

  describe "Option C: Validation-Before-Render" do
    it "skips widgets with zero-size bounds without crashing" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(ZeroSizeWidget.new)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new

      # Should not crash - zero-size widget silently skipped
      # (ZeroSizeWidget.to_primitives raises if called)
      renderer.render_frame(app)

      # Render completed without crash
      renderer.render_frame_count.should eq 1
    end

    it "skips widgets with NaN bounds without crashing" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(NaNBoundsWidget.new)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new

      # Should not crash - NaN bounds widget silently skipped
      # (NaNBoundsWidget.to_primitives raises if called)
      renderer.render_frame(app)

      # Render completed without crash
      renderer.render_frame_count.should eq 1
    end

    it "skips widgets with infinite bounds without crashing" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      window.add_child(InfiniteBoundsWidget.new)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new

      # Should not crash - infinite bounds widget silently skipped
      # (InfiniteBoundsWidget.to_primitives raises if called)
      renderer.render_frame(app)

      # Render completed without crash
      renderer.render_frame_count.should eq 1
    end
  end

  describe "Cache Reset Methods" do
    it "Widget.reset_render_caches_recursive clears all render caches" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      button = CrymbleUI::Button.new("Test") { }
      window.add_child(button)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new
      renderer.render_frame(app)

      # Verify button has caches after render
      button.widget_backend.should_not be_nil

      # Call reset_render_caches_recursive on root
      window.reset_render_caches_recursive

      # Verify caches are cleared
      button.widget_backend.should be_nil
      button.background_backend.should be_nil
    end

    it "Layer.reset_for_recovery clears layer state" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 150), z_index: 0)
      renderer = CrymbleUI::Testing::TestRenderer.new
      renderer.ensure_layer_backend(layer, 200, 150)

      # Verify layer has backend
      layer.backend.should_not be_nil

      # Reset layer
      layer.reset_for_recovery

      # Verify layer is reset
      layer.backend.should be_nil
      layer.dirty_widgets.empty?.should be_true
    end

    it "App.reset_all_caches clears all state for recovery" do
      app = TestApp.new
      window = CrymbleUI::Window.new("Test", 400, 300)
      button = CrymbleUI::Button.new("Test") { }
      window.add_child(button)
      app.root_widget = window

      renderer = CrymbleUI::Testing::TestRenderer.new
      renderer.render_frame(app)

      # Simulate hover
      app.update_hover(CrymbleUI::Vec2.new(200.0, 150.0))

      # Reset all caches
      app.reset_all_caches

      # Verify all state is cleared
      app.hovered_widget.should be_nil
      button.widget_backend.should be_nil
    end
  end
end
