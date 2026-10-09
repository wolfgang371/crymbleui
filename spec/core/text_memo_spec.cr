require "../spec_helper"
require "../../src/testing/test_font"

# Auto-size measures EVERY cell of a table, so the string memo behind Widget.measure_text must hold a
# whole table's cells: with a limit below the working set it was cleared in the middle of each pass
# and a re-measure paid for every cell again (455 ms against 85 on 3000 x 11 cells, real font).
private class CountingFont < CrymbleUI::Testing::TestFont
  getter calls = 0

  def measure_text(text : String, size : Float64) : CrymbleUI::Size
    @calls += 1
    super
  end
end

describe "the text measurement memo" do
  it "holds a large table's cells, so a second pass measures none of them again" do
    previous = CrymbleUI::Widget.font
    font = CountingFont.new
    CrymbleUI::Widget.font = font # a font change clears the memo
    begin
      cells = (0...3000).flat_map { |r| (0...11).map { |c| "value #{r}-#{c}" } }
      cells.each { |s| CrymbleUI::Widget.measure_text(s, 13.0) }
      font.calls.should eq cells.size
      cells.each { |s| CrymbleUI::Widget.measure_text(s, 13.0) }
      font.calls.should eq cells.size # the second pass was all hits
    ensure
      CrymbleUI::Widget.font = previous
    end
  end
end
