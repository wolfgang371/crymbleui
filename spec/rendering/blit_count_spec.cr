require "../spec_helper"
require "../../src/testing/test_render_backend"

# TestRenderBackend must count blit / blit_region calls so the "exactly one slot re-blits"
# claim is falsifiable (blit_region_count.should eq 1).
describe CrymbleUI::Testing::TestRenderBackend do
  it "counts blit and blit_region calls and resets them" do
    src = CrymbleUI::Testing::TestRenderBackend.new(10, 10)
    dst = CrymbleUI::Testing::TestRenderBackend.new(20, 20)

    dst.blit_count.should eq 0
    dst.blit_region_count.should eq 0

    dst.blit(src, 0, 0)
    dst.blit(src, 5, 5)
    dst.blit_count.should eq 2

    dst.blit_region(src, 0, 0, 5, 5, 0, 0)
    dst.blit_region_count.should eq 1
    dst.blit_count.should eq 2 # blit_region is not a blit

    dst.reset_counters
    dst.blit_count.should eq 0
    dst.blit_region_count.should eq 0
  end
end
