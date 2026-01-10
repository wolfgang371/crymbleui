require "../spec_helper"
require "../../src/core/layer"

describe "Layer viewport_cache buffer support" do
  describe "#scroll_offset" do
    it "defaults to zero" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
      layer.scroll_offset.should eq(CrymbleUI::Vec2.zero)
    end

    it "can be set and read" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
      layer.scroll_offset = CrymbleUI::Vec2.new(50.0, 75.0)
      layer.scroll_offset.x.should eq(50.0)
      layer.scroll_offset.y.should eq(75.0)
    end
  end

  describe "#viewport_cache" do
    it "defaults to false" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
      layer.viewport_cache.should be_false
    end

    it "can be enabled" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
      layer.viewport_cache = true
      layer.viewport_cache.should be_true
    end
  end

  describe "#wrap_coords" do
    context "when not viewport_cache" do
      it "returns coordinates unchanged" do
        layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
        layer.viewport_cache = false

        x, y = layer.wrap_coords(150.0, 250.0, 100, 100)

        x.should eq(150)
        y.should eq(250)
      end
    end

    context "when viewport_cache" do
      it "wraps x coordinate using modulo" do
        layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
        layer.viewport_cache = true

        x, y = layer.wrap_coords(150.0, 50.0, 100, 100)

        x.should eq(50)  # 150 % 100 = 50
        y.should eq(50)
      end

      it "wraps y coordinate using modulo" do
        layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
        layer.viewport_cache = true

        x, y = layer.wrap_coords(30.0, 270.0, 100, 100)

        x.should eq(30)
        y.should eq(70)  # 270 % 100 = 70
      end

      it "wraps both coordinates for 2D scrolling" do
        layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
        layer.viewport_cache = true

        x, y = layer.wrap_coords(350.0, 475.0, 100, 100)

        x.should eq(50)  # 350 % 100 = 50
        y.should eq(75)  # 475 % 100 = 75
      end

      it "handles coordinates at exact texture size boundary" do
        layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
        layer.viewport_cache = true

        x, y = layer.wrap_coords(100.0, 200.0, 100, 100)

        x.should eq(0)   # 100 % 100 = 0
        y.should eq(0)   # 200 % 100 = 0
      end

      it "handles negative coordinates" do
        layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
        layer.viewport_cache = true

        # Crystal modulo handles negatives: -30 % 100 = 70
        x, y = layer.wrap_coords(-30.0, -50.0, 100, 100)

        # Note: Crystal's modulo for negative numbers:
        # -30 % 100 = 70 (wraps correctly)
        x.should eq(70)
        y.should eq(50)
      end

      it "handles coordinates within texture bounds (no wrap needed)" do
        layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 100, 100))
        layer.viewport_cache = true

        x, y = layer.wrap_coords(30.0, 50.0, 100, 100)

        x.should eq(30)  # Already within bounds
        y.should eq(50)
      end
    end
  end

  describe "#viewport_rect" do
    it "returns viewport in content space based on scroll_offset and bounds size" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 150))
      layer.scroll_offset = CrymbleUI::Vec2.new(100.0, 50.0)

      viewport = layer.viewport_rect

      viewport.x.should eq(100.0)
      viewport.y.should eq(50.0)
      viewport.width.should eq(200.0)
      viewport.height.should eq(150.0)
    end

    it "returns viewport at origin when scroll_offset is zero" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 300, 200))

      viewport = layer.viewport_rect

      viewport.x.should eq(0.0)
      viewport.y.should eq(0.0)
      viewport.width.should eq(300.0)
      viewport.height.should eq(200.0)
    end
  end

  describe "#widget_in_viewport?" do
    it "returns true when widget bounds intersect viewport" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      layer.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)

      widget_bounds = CrymbleUI::Rect.new(50, 50, 100, 100)

      layer.widget_in_viewport?(widget_bounds).should be_true
    end

    it "returns false when widget is above viewport" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      layer.scroll_offset = CrymbleUI::Vec2.new(0.0, 300.0)  # Viewport starts at y=300

      widget_bounds = CrymbleUI::Rect.new(50, 50, 100, 100)  # Widget at y=50

      layer.widget_in_viewport?(widget_bounds).should be_false
    end

    it "returns false when widget is below viewport" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      layer.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)  # Viewport is 0-200

      widget_bounds = CrymbleUI::Rect.new(50, 500, 100, 100)  # Widget at y=500

      layer.widget_in_viewport?(widget_bounds).should be_false
    end

    it "returns true when widget partially overlaps viewport" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      layer.scroll_offset = CrymbleUI::Vec2.new(0.0, 100.0)  # Viewport is 100-300

      widget_bounds = CrymbleUI::Rect.new(50, 50, 100, 100)  # Widget is 50-150, overlaps at 100-150

      layer.widget_in_viewport?(widget_bounds).should be_true
    end

    it "returns false when widget is to the left of viewport (horizontal scroll)" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      layer.scroll_offset = CrymbleUI::Vec2.new(500.0, 0.0)  # Viewport starts at x=500

      widget_bounds = CrymbleUI::Rect.new(50, 50, 100, 100)  # Widget at x=50

      layer.widget_in_viewport?(widget_bounds).should be_false
    end
  end

  describe "cache extent for pre-rendering" do
    it "can set and get cache_extent" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      layer.cache_extent = 50.0
      layer.cache_extent.should eq(50.0)
    end

    it "defaults cache_extent to reasonable value" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      # Default like Flutter's 250px or some reasonable buffer
      layer.cache_extent.should be >= 0.0
    end

    it "widget_in_viewport? considers cache_extent when enabled" do
      layer = CrymbleUI::Layer.new("test", CrymbleUI::Rect.new(0, 0, 200, 200))
      layer.scroll_offset = CrymbleUI::Vec2.new(0.0, 0.0)
      layer.cache_extent = 100.0

      # Widget just below viewport (at y=210) but within cache_extent
      widget_bounds = CrymbleUI::Rect.new(50, 210, 100, 50)

      # With cache extent, this should be considered "in viewport" for pre-rendering
      layer.widget_in_viewport?(widget_bounds, include_cache: true).should be_true
      layer.widget_in_viewport?(widget_bounds, include_cache: false).should be_false
    end
  end
end
