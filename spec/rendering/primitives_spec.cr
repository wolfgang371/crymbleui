require "../spec_helper"
require "../../src/dsl/primitive_builder"

# Test widgets for primitive rendering specs
class TestPrimitiveWidget < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100, 50)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 100, 50)
  end


  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(bounds, CrymbleUI::Color.new(200, 200, 200, 255))
      draw_text("Test", CrymbleUI::Vec2.new(bounds.x + 10, bounds.y + 10), CrymbleUI::Color.new(0, 0, 0, 255), 0)
      draw_line(
        CrymbleUI::Vec2.new(bounds.x, bounds.y),
        CrymbleUI::Vec2.new(bounds.x + bounds.width, bounds.y),
        CrymbleUI::Color.new(255, 0, 0, 255),
        1.0
      )
    end
  end
end

class NeverCacheWidget < CrymbleUI::Widget
  def cache_policy : CrymbleUI::CachePolicy
    CrymbleUI::CachePolicy::Never
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100, 50)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 100, 50)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(bounds, CrymbleUI::Color.new(255, 255, 255, 255))] of CrymbleUI::DrawPrimitive
  end
end

class StaticCacheWidget < CrymbleUI::Widget
  def cache_policy : CrymbleUI::CachePolicy
    CrymbleUI::CachePolicy::Static
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(100, 50)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position.x, position.y, 100, 50)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    [CrymbleUI::FillRect.new(bounds, CrymbleUI::Color.new(255, 255, 255, 255))] of CrymbleUI::DrawPrimitive
  end
end

describe "Primitive Rendering Infrastructure" do
  describe "DrawPrimitive structs" do
    it "creates FillRect primitive" do
      rect = CrymbleUI::Rect.new(10, 20, 100, 50)
      color = CrymbleUI::Color.new(255, 0, 0, 255)
      primitive = CrymbleUI::FillRect.new(rect, color)

      primitive.bounds.should eq(rect)
      primitive.color.should eq(color)
    end

    it "creates DrawText primitive" do
      pos = CrymbleUI::Vec2.new(10, 20)
      color = CrymbleUI::Color.new(0, 0, 0, 255)
      primitive = CrymbleUI::DrawText.new("Hello", pos, color, 16.0)

      primitive.text.should eq("Hello")
      primitive.position.should eq(pos)
      primitive.color.should eq(color)
      primitive.size.should eq(16.0)
    end

    it "creates DrawLine primitive" do
      from = CrymbleUI::Vec2.new(0, 0)
      to = CrymbleUI::Vec2.new(100, 100)
      color = CrymbleUI::Color.new(0, 0, 255, 255)
      primitive = CrymbleUI::DrawLine.new(from, to, color, 2.0)

      primitive.from.should eq(from)
      primitive.to.should eq(to)
      primitive.color.should eq(color)
      primitive.width.should eq(2.0)
    end

    it "creates DrawCircle primitive" do
      center = CrymbleUI::Vec2.new(50, 50)
      color = CrymbleUI::Color.new(0, 255, 0, 255)
      primitive = CrymbleUI::DrawCircle.new(center, 25.0, color, true)

      primitive.center.should eq(center)
      primitive.radius.should eq(25.0)
      primitive.color.should eq(color)
      primitive.fill.should be_true
    end

    it "creates DrawRect primitive" do
      rect = CrymbleUI::Rect.new(10, 20, 100, 50)
      color = CrymbleUI::Color.new(128, 128, 128, 255)
      primitive = CrymbleUI::DrawRect.new(rect, color, 1.0)

      primitive.bounds.should eq(rect)
      primitive.color.should eq(color)
      primitive.width.should eq(1.0)
    end

    it "creates PushClip primitive" do
      rect = CrymbleUI::Rect.new(0, 0, 200, 200)
      primitive = CrymbleUI::PushClip.new(rect)

      primitive.rect.should eq(rect)
    end

    it "creates PopClip primitive" do
      primitive = CrymbleUI::PopClip.new
      primitive.should be_a(CrymbleUI::PopClip)
    end
  end

  describe "PrimitiveBuilder DSL" do
    it "generates primitives using DSL" do
      widget = TestPrimitiveWidget.new
      bounds = CrymbleUI::Rect.new(0, 0, 100, 50)

      primitives = widget.to_primitives(bounds)

      primitives.size.should eq(3)
      primitives[0].should be_a(CrymbleUI::FillRect)
      primitives[1].should be_a(CrymbleUI::DrawText)
      primitives[2].should be_a(CrymbleUI::DrawLine)
    end
  end

  describe "Widget cache policy" do
    it "Never policy always regenerates primitives" do
      widget = NeverCacheWidget.new
      bounds = CrymbleUI::Rect.new(0, 0, 100, 50)

      primitives1 = widget.get_primitives(bounds)
      primitives2 = widget.get_primitives(bounds)

      # Should be different objects (not cached)
      primitives1.should_not be(primitives2)
    end

    it "Dynamic policy caches until marked dirty" do
      widget = TestPrimitiveWidget.new
      bounds = CrymbleUI::Rect.new(0, 0, 100, 50)

      # First call generates
      primitives1 = widget.get_primitives(bounds)
      widget.clear_render_state_recursive  # Mark clean

      # Second call returns cached
      primitives2 = widget.get_primitives(bounds)
      primitives1.should be(primitives2)

      # Mark dirty
      widget.mark_needs_render

      # Third call regenerates
      primitives3 = widget.get_primitives(bounds)
      primitives3.should_not be(primitives1)
    end

    it "Static policy caches forever" do
      widget = StaticCacheWidget.new
      bounds = CrymbleUI::Rect.new(0, 0, 100, 50)

      primitives1 = widget.get_primitives(bounds)
      widget.mark_needs_render  # Try to invalidate
      primitives2 = widget.get_primitives(bounds)

      # Should be same object (cached forever)
      primitives1.should be(primitives2)
    end
  end
end
