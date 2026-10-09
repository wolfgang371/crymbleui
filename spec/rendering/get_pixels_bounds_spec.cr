require "../spec_helper"
require "../../src/testing/test_render_backend"

# A pixel read must lie inside the buffer. Under SFML a rect past the edge crashed the process in
# sf::Image::getPixel (signal 11) while this headless backend answered transparent, so a spec could
# pass on exactly the read that killed the app. Both backends share the precondition
# (RenderBackend#assert_inside); the SFML half cannot run without a GL context, this one pins it.

private def backend : CrymbleUI::Testing::TestRenderBackend
  CrymbleUI::Testing::TestRenderBackend.new(20, 10)
end

describe "get_pixels bounds" do
  it "reads any rect inside the buffer, the whole buffer and an empty one included" do
    b = backend
    b.get_pixels(0, 0, 20, 10).size.should eq 200
    b.get_pixels(19, 9, 1, 1).size.should eq 1
    b.get_pixels(5, 5, 0, 0).should be_empty
  end

  it "raises on a rect that runs past an edge or starts outside" do
    {
      {15, 0, 6, 1},  # one past the right edge
      {0, 5, 1, 6},   # one past the bottom edge
      {-1, 0, 2, 2},  # starts left of the buffer
      {0, -1, 2, 2},  # starts above it
      {20, 0, 1, 1},  # starts at the edge
      {0, 0, -1, 1},  # a negative size (it used to answer an empty array)
    }.each do |x, y, w, h|
      expect_raises(ArgumentError, /not inside the 20x10 buffer/) { backend.get_pixels(x, y, w, h) }
    end
  end
end
