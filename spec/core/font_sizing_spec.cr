require "../spec_helper"
require "../../src/core/font_sizing"

describe CrymbleUI::FontSizing do
  # Reset zoom before each test
  before_each do
    CrymbleUI::FontSizing.reset_zoom
  end

  describe "constants" do
    it "has BASE_SIZE of 14.0" do
      CrymbleUI::FontSizing::BASE_SIZE.should eq(14.0)
    end

    it "has STEP_MULTIPLIER of 1.1" do
      CrymbleUI::FontSizing::STEP_MULTIPLIER.should eq(1.1)
    end

    it "has precomputed ZOOM_LEVELS array" do
      CrymbleUI::FontSizing::ZOOM_LEVELS.should be_a(Array(Float64))
      CrymbleUI::FontSizing::ZOOM_LEVELS.size.should be >= 10
    end

    it "ZOOM_LEVELS contains 1.0 (100%)" do
      CrymbleUI::FontSizing::ZOOM_LEVELS.should contain(1.0)
    end

    it "ZOOM_LEVELS minimum is 0.5" do
      CrymbleUI::FontSizing::ZOOM_LEVELS.first.should eq(0.5)
    end

    it "ZOOM_LEVELS maximum is 3.0" do
      CrymbleUI::FontSizing::ZOOM_LEVELS.last.should eq(3.0)
    end

    it "ZOOM_LEVELS are sorted ascending" do
      levels = CrymbleUI::FontSizing::ZOOM_LEVELS
      levels.each_cons(2).all? { |(a, b)| a < b }.should be_true
    end
  end

  describe ".calculate_size" do
    it "returns base size for scale 0" do
      CrymbleUI::FontSizing.calculate_size(0).should eq(14.0)
    end

    it "increases size by 10% per positive scale step" do
      CrymbleUI::FontSizing.calculate_size(1).should be_close(15.4, 0.01)
      CrymbleUI::FontSizing.calculate_size(2).should be_close(16.94, 0.01)
      CrymbleUI::FontSizing.calculate_size(3).should be_close(18.634, 0.01)
    end

    it "decreases size by ~9% per negative scale step" do
      CrymbleUI::FontSizing.calculate_size(-1).should be_close(12.727, 0.01)
      CrymbleUI::FontSizing.calculate_size(-2).should be_close(11.57, 0.01)
    end

    it "applies zoom factor" do
      CrymbleUI::FontSizing.zoom_in  # Go to next level above 1.0
      zoom = CrymbleUI::FontSizing.zoom_factor
      expected = 14.0 * zoom
      CrymbleUI::FontSizing.calculate_size(0).should be_close(expected, 0.01)
    end

    it "combines scale and zoom" do
      # Zoom in twice to get a zoom > 1.0
      CrymbleUI::FontSizing.zoom_in
      CrymbleUI::FontSizing.zoom_in
      zoom = CrymbleUI::FontSizing.zoom_factor
      # scale +1 = 14 * 1.1 = 15.4, then * zoom
      expected = 15.4 * zoom
      CrymbleUI::FontSizing.calculate_size(1).should be_close(expected, 0.01)
    end
  end

  describe ".zoom_index" do
    it "returns current zoom level index" do
      CrymbleUI::FontSizing.zoom_index.should be_a(Int32)
    end

    it "defaults to index of 1.0" do
      default_index = CrymbleUI::FontSizing.zoom_index
      CrymbleUI::FontSizing::ZOOM_LEVELS[default_index].should eq(1.0)
    end
  end

  describe ".zoom_factor" do
    it "defaults to 1.0" do
      CrymbleUI::FontSizing.zoom_factor.should eq(1.0)
    end

    it "returns value from ZOOM_LEVELS at current index" do
      index = CrymbleUI::FontSizing.zoom_index
      CrymbleUI::FontSizing.zoom_factor.should eq(CrymbleUI::FontSizing::ZOOM_LEVELS[index])
    end
  end

  describe ".zoom_in" do
    it "moves to next zoom level" do
      initial_index = CrymbleUI::FontSizing.zoom_index
      CrymbleUI::FontSizing.zoom_in
      CrymbleUI::FontSizing.zoom_index.should eq(initial_index + 1)
    end

    it "increases zoom factor" do
      initial = CrymbleUI::FontSizing.zoom_factor
      CrymbleUI::FontSizing.zoom_in
      CrymbleUI::FontSizing.zoom_factor.should be > initial
    end

    it "can zoom in multiple times" do
      3.times { CrymbleUI::FontSizing.zoom_in }
      CrymbleUI::FontSizing.zoom_factor.should be > 1.0
    end

    it "stops at maximum zoom level" do
      50.times { CrymbleUI::FontSizing.zoom_in }
      CrymbleUI::FontSizing.zoom_factor.should eq(3.0)
      CrymbleUI::FontSizing.zoom_index.should eq(CrymbleUI::FontSizing::ZOOM_LEVELS.size - 1)
    end

    it "returns true when zoom changed" do
      CrymbleUI::FontSizing.zoom_in.should be_true
    end

    it "returns false when already at max" do
      50.times { CrymbleUI::FontSizing.zoom_in }
      CrymbleUI::FontSizing.zoom_in.should be_false
    end
  end

  describe ".zoom_out" do
    it "moves to previous zoom level" do
      initial_index = CrymbleUI::FontSizing.zoom_index
      CrymbleUI::FontSizing.zoom_out
      CrymbleUI::FontSizing.zoom_index.should eq(initial_index - 1)
    end

    it "decreases zoom factor" do
      initial = CrymbleUI::FontSizing.zoom_factor
      CrymbleUI::FontSizing.zoom_out
      CrymbleUI::FontSizing.zoom_factor.should be < initial
    end

    it "can zoom out multiple times" do
      3.times { CrymbleUI::FontSizing.zoom_out }
      CrymbleUI::FontSizing.zoom_factor.should be < 1.0
    end

    it "stops at minimum zoom level" do
      50.times { CrymbleUI::FontSizing.zoom_out }
      CrymbleUI::FontSizing.zoom_factor.should eq(0.5)
      CrymbleUI::FontSizing.zoom_index.should eq(0)
    end

    it "returns true when zoom changed" do
      CrymbleUI::FontSizing.zoom_out.should be_true
    end

    it "returns false when already at min" do
      50.times { CrymbleUI::FontSizing.zoom_out }
      CrymbleUI::FontSizing.zoom_out.should be_false
    end
  end

  describe ".reset_zoom" do
    it "resets zoom to 1.0" do
      5.times { CrymbleUI::FontSizing.zoom_in }
      CrymbleUI::FontSizing.reset_zoom
      CrymbleUI::FontSizing.zoom_factor.should eq(1.0)
    end

    it "resets zoom index to default" do
      5.times { CrymbleUI::FontSizing.zoom_out }
      CrymbleUI::FontSizing.reset_zoom
      CrymbleUI::FontSizing::ZOOM_LEVELS[CrymbleUI::FontSizing.zoom_index].should eq(1.0)
    end
  end

  describe ".zoom_percentage" do
    it "returns zoom as percentage string" do
      CrymbleUI::FontSizing.zoom_percentage.should eq("100%")
    end

    it "updates after zoom in" do
      CrymbleUI::FontSizing.zoom_in
      percentage = CrymbleUI::FontSizing.zoom_percentage
      percentage.should match(/\d+%/)
      percentage.should_not eq("100%")
    end
  end
end
