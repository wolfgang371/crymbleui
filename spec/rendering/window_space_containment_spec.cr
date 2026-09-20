require "../spec_helper"

# CONTAINMENT TRIPWIRE for the coordinate-space rule (docs/RENDERING_LAWS.md § Coordinate spaces).
#
# A widget inside a ScrollView keeps its laid-out (CONTENT) position; the layer composites
# shifted. `absolute_bounds` is that laid-out position, `viewport_bounds` the painted one. The
# files below deal ONLY with things that meet the cursor — a drag ghost, a drop highlight, a
# popup anchored under a control — which live in window space. Every defect this tripwire guards
# was the same one-word slip, and each was invisible until something draggable or something with
# a dropdown was first placed inside a scrolled panel:
#
#   drag ghost 150px below the cursor, drop highlight on the wrong row (spec/core/drag_scroll_offset_spec)
#   combo popup opening at y=36 instead of 82, flip-above decided at the unscrolled position
#     (spec/widgets/combo_box_in_scroll_view_spec)
#
# The rule is not "never call absolute_bounds" — layout and the renderer are content space and
# must keep using it. It is: in THESE files, the answer is always the painted position.
WINDOW_SPACE_FILES = [
  "src/core/drag_manager.cr",
  "src/widgets/popup_host.cr",
  "src/widgets/menu.cr",
]

private def tripwire_code_lines(path : String) : Array({Int32, String})
  # to_a, not the lazy Iterator: `empty?` consumes it, and the failure message then names no
  # lines at all — caught by mutating drag_manager.cr and reading what the tripwire actually said.
  File.read_lines(path).each_with_index.map do |raw, i|
    s = raw.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"")
    idx = s.index("#")
    {i + 1, idx ? s[0...idx] : s}
  end.to_a
end

describe "window-space containment" do
  it "keeps cursor-facing code off absolute_bounds" do
    WINDOW_SPACE_FILES.each do |path|
      File.exists?(path).should be_true, "#{path} moved — this tripwire now guards nothing"
      offenders = tripwire_code_lines(path).select { |_, code| code.includes?("absolute_bounds") }
      offenders.empty?.should be_true,
        "#{path} uses absolute_bounds at line(s) #{offenders.map(&.[](0)).join(", ")} — " \
        "this file positions things against the CURSOR, which is window space. Use viewport_bounds."
    end
  end

  # The other half of the same rule: viewport_bounds must keep converting, or the files above
  # would pass the text check while being just as wrong.
  it "keeps viewport_bounds converting for an enclosing ScrollView" do
    sv = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    child = TestWidget.new
    sv.set_content(child)
    sv.bounds = CrymbleUI::Rect.new(0.0, 0.0, 100.0, 100.0)
    child.bounds = CrymbleUI::Rect.new(0.0, 300.0, 50.0, 20.0)
    sv.set_scroll_offset_for_test(CrymbleUI::Vec2.new(0.0, 120.0))

    child.absolute_bounds.y.should eq(300.0)
    child.viewport_bounds.y.should eq(180.0)
  end
end
