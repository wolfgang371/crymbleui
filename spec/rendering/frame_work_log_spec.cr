require "../spec_helper"
require "../../src/crymble-ui"

# Validates the FrameWorkLog INSTRUMENT (not the app): the on-disk log must be self-describing and
# carry every field needed to reconstruct a frame offline — because it is run in --release without a
# live analyst. Feeds known counter values through record() and asserts they round-trip through the
# TSV. (The "no per-frame File.open / one buffered line per frame" low-overhead property is structural;
# see FrameWorkLog — this spec guards completeness + parseability.)
describe "FrameWorkLog" do
  it "writes a self-describing TSV whose every column round-trips a frame's counters" do
    path = File.tempname("worklog", ".tsv")

    # Known per-frame (reset-each-frame) LayerRenderer counters.
    CrymbleUI::LayerRenderer.frame_layers_total = 7
    CrymbleUI::LayerRenderer.frame_layers_needing_render = 2
    CrymbleUI::LayerRenderer.frame_composite_count = 3
    CrymbleUI::LayerRenderer.frame_widgets_iterated = 150
    CrymbleUI::LayerRenderer.frame_widget_count = 4
    CrymbleUI::LayerRenderer.frame_primitive_count = 88
    CrymbleUI::LayerRenderer.frame_blit_shift_count = 1

    # Monotonic counter: baseline at 0 before the ledger seeds, so its deltas are exact.
    CrymbleUI::Widget.reset_absolute_bounds_count

    log = CrymbleUI::FrameWorkLog.new(path)
    log.enabled?.should be_true

    5.times { CrymbleUI::Widget.increment_absolute_bounds_count } # this-frame delta = 5
    log.record(1.0, 2.0, 3.0, 0.5, did_layout: true, mouse_down: false)

    7.times { CrymbleUI::Widget.increment_absolute_bounds_count } # next-frame delta = 7
    log.record(0.1, 0.0, 0.2, 0.1, did_layout: false, mouse_down: true)

    log.close

    lines = File.read_lines(path)
    comments = lines.select(&.starts_with?("#"))
    comments.size.should be > 0 # a human/machine legend is present

    data = lines.reject { |l| l.starts_with?("#") }
    header = data.first.split('\t')
    header.should eq(CrymbleUI::FrameWorkLog::COLUMNS) # header matches the documented column set

    rows = data[1..].map(&.split('\t'))
    rows.size.should eq(2)
    rows.each { |r| r.size.should eq(CrymbleUI::FrameWorkLog::COLUMNS.size) } # no ragged rows

    col = ->(row : Array(String), name : String) { row[CrymbleUI::FrameWorkLog::COLUMNS.index(name).not_nil!] }

    r1 = rows[0]
    col.call(r1, "frame").should eq("1")
    col.call(r1, "total_ms").should eq("6.5")
    col.call(r1, "layout_ms").should eq("1.0")
    col.call(r1, "composite_ms").should eq("3.0")
    col.call(r1, "layers_total").should eq("7")
    col.call(r1, "layers_rendered").should eq("2")
    col.call(r1, "widgets_iter").should eq("150")
    col.call(r1, "prims").should eq("88")
    col.call(r1, "blit_shift").should eq("1")
    col.call(r1, "cause_layout").should eq("1")
    col.call(r1, "cause_mousedown").should eq("0")
    col.call(r1, "cause_rebuilds").should eq("0") # nothing called App.rebuild between records
    col.call(r1, "absolute_bounds").should eq("5") # this-frame delta

    r2 = rows[1]
    col.call(r2, "frame").should eq("2")
    col.call(r2, "cause_layout").should eq("0")
    col.call(r2, "cause_mousedown").should eq("1")
    col.call(r2, "absolute_bounds").should eq("7") # delta, not cumulative

    File.delete(path)
  end

  it "is a zero-cost no-op when no path is configured" do
    log = CrymbleUI::FrameWorkLog.new(nil)
    log.enabled?.should be_false
    # record must not raise or touch disk when disabled
    log.record(9.0, 9.0, 9.0, 9.0, did_layout: true, mouse_down: true)
    log.close
  end
end
