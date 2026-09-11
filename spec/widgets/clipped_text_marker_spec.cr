require "../spec_helper"
require "../../src/widgets/text_input"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_item"
require "../../src/widgets/text"
require "../../src/layout/vstack"
require "../../src/testing/test_renderer"

# Where content is cut, a non-interactive marker says so.
#
# PROBE DISCIPLINE. The band is drawn BEHIND the text, so its columns are exactly where cut
# glyphs ink. Every band assertion therefore uses an INK-FREE value: TestRenderBackend#draw_text
# inks a left stripe iff `code & 0x01` and a right stripe iff `code & 0x02`, so characters with
# `code & 0x03 == 0` ('d','h','l','p','t','x') ink nothing while TestFont still measures them at
# full width. The value overflows, inks nothing, and every band pixel is unambiguous. An inking
# value here would make these examples pass or fail on where a stripe happened to land.
MARKER_LONG  = "dddddddddddddddddddd"
MARKER_SHORT = "dd"

# The floor the marker holds against the colour its widget actually paints. Higher than the
# 3:1 WCAG non-text minimum on purpose: embrace composites a cursor-row wash OVER cell content
# from a separate layer, which no widget-local derivation can see, so the budget absorbs it.
MARKER_MIN_RATIO = 4.5

class MarkerApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Marker", 120, 240) do
      vstack(padding: 0.0, spacing: 0.0) do
        text_input(id: "cut", width: 60.0, value: MARKER_LONG)
        text_input(id: "fits", width: 60.0, value: MARKER_SHORT)
        # A caller-supplied background: the marker must derive from THIS, not from the theme
        # token, or a tinted cell gets a band computed against the wrong backdrop.
        text_input(id: "tinted", width: 60.0, value: MARKER_LONG,
          background_color: CrymbleUI::Color.from_hex("#605000"))
        combo_box(items: [MARKER_LONG], selected: 0, id: "combo")
        widget(CrymbleUI::Text.new(MARKER_LONG, id: "label", padding: 6.0,
          background_color: CrymbleUI::Color.from_hex("#303030")))
        # No background of its own: it cannot see what it sits on, so it must not claim a
        # contrast floor against a guess.
        widget(CrymbleUI::Text.new(MARKER_LONG, id: "bare", padding: 6.0))
      end
    end
  end
end

private def pixels_of(widget, color) : Int32
  n = 0
  wb = widget.widget_backend.as?(CrymbleUI::Testing::TestRenderBackend)
  return n unless wb
  (0...wb.width).each do |x|
    (0...wb.height).each { |y| n += 1 if wb.get_pixel(x, y) == color }
  end
  n
end

private def marker_app : CrymbleUI::App
  renderer = CrymbleUI::Testing::TestRenderer.new(120, 240)
  app = MarkerApp.new
  app.build_tree
  renderer.settle_rendering(app)
  app
end

describe "a cut-content marker" do
  it "appears when a TextInput's value is wider than its box" do
    app = marker_app
    input = app.find("cut").not_nil!.as(CrymbleUI::TextInput)
    band = input.background_color.contrasting_neutral(MARKER_MIN_RATIO)
    pixels_of(input, band).should be > 0
  end

  it "stays away when the value fits" do
    app = marker_app
    input = app.find("fits").not_nil!.as(CrymbleUI::TextInput)
    band = input.background_color.contrasting_neutral(MARKER_MIN_RATIO)
    pixels_of(input, band).should eq(0)
  end

  it "derives from the colour the widget actually PAINTS, not a theme token" do
    # The tinted cell's background is nothing like input_background, so a marker derived from
    # the token would sit on a backdrop that is not on screen — and would be certified by a
    # spec that also read the token. Assert against the painted colour, and assert the floor.
    app = marker_app
    input = app.find("tinted").not_nil!.as(CrymbleUI::TextInput)
    painted = input.background_color
    painted.should eq(CrymbleUI::Color.from_hex("#605000"))

    band = painted.contrasting_neutral(MARKER_MIN_RATIO)
    pixels_of(input, band).should be > 0
    band.contrast_ratio(painted).should be >= MARKER_MIN_RATIO
  end

  it "marks a collapsed ComboBox whose value is cut" do
    app = marker_app
    combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
    painted = combo.background_color || CrymbleUI::Theme.current.combo_background
    pixels_of(combo, painted.contrasting_neutral(MARKER_MIN_RATIO)).should be > 0
  end

  it "marks a Text whose label is cut, against the background it paints" do
    app = marker_app
    label = app.find("label").not_nil!.as(CrymbleUI::Text)
    painted = label.background_color.not_nil!
    pixels_of(label, painted.contrasting_neutral(MARKER_MIN_RATIO)).should be > 0
  end

  it "draws NO marker on a Text that paints no background of its own" do
    # It sits on whatever its parent painted and cannot see that colour. Deriving against a
    # theme token would be asserting a backdrop rather than measuring one — embrace puts bare
    # Texts inside DropZoneBoxes filled with field-class colours, none of which is
    # panel.background — so the floor would be computed against a colour never on screen and
    # the band could land below 3:1. A widget that cannot see its backdrop draws no marker.
    app = marker_app
    bare = app.find("bare").not_nil!.as(CrymbleUI::Text)
    bare.background_color.should be_nil
    prims = bare.to_primitives(bare.absolute_bounds)
    prims.count(&.is_a?(CrymbleUI::FillRect)).should eq(0)
  end

  it "marks a ComboBoxItem against its HIGHLIGHTED background, not its base one" do
    # A selected row paints base.highlight(...), not `background_color`. Deriving from the
    # property would put the band on a backdrop that is never rendered — and on embrace's
    # per-row constraint colours that lands near 1:1, i.e. invisible, on the very row that
    # holds the current value.
    item = CrymbleUI::ComboBoxItem.new(MARKER_LONG,
      background_color: CrymbleUI::Color.from_hex("#90D890"))
    item.selected = true
    prims = item.to_primitives(CrymbleUI::Rect.new(0.0, 0.0, 60.0, 24.0))

    painted = prims.select(&.is_a?(CrymbleUI::FillRect))
      .map(&.as(CrymbleUI::FillRect))
      .find { |f| f.bounds.width >= 60.0 }.not_nil!.color
    painted.should_not eq(CrymbleUI::Color.from_hex("#90D890")) # highlight really did apply

    expected = painted.contrasting_neutral(MARKER_MIN_RATIO)
    band = prims.select(&.is_a?(CrymbleUI::FillRect))
      .map(&.as(CrymbleUI::FillRect))
      .find { |f| f.color == expected }
    band.should_not be_nil
    expected.contrast_ratio(painted).should be >= MARKER_MIN_RATIO
  end

  it "is drawn BEHIND the text, so it can never hide what it reports on" do
    # Emission order, which no other example can see: the band must precede the clipped block
    # that draws the glyphs. Drawn after, an opaque 3px fill sits on top of the very sliver
    # the feature exists to report.
    app = marker_app
    input = app.find("cut").not_nil!.as(CrymbleUI::TextInput)
    prims = input.to_primitives(input.absolute_bounds)
    band_color = input.background_color.contrasting_neutral(MARKER_MIN_RATIO)

    band_at = prims.index { |p| p.is_a?(CrymbleUI::FillRect) && p.as(CrymbleUI::FillRect).color == band_color }
    clip_at = prims.index(&.is_a?(CrymbleUI::PushClip))
    band_at.should_not be_nil
    clip_at.should_not be_nil
    band_at.not_nil!.should be < clip_at.not_nil!
  end
end
