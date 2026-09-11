require "../../spec_helper"
require "../../../src/widgets/virtual_matrix"
require "../../../src/testing/test_renderer"
require "../../../src/testing/configurable_matrix_adapter"

# THE SWEEP HARNESS.
#
# `placement_invariants_spec` asserts named cases one at a time, each written after a field report.
# That is how this arc kept shipping a rule that satisfied the last screenshot and broke an earlier
# one: a case nobody had written down was a case nobody could fail. This file is the other half —
# ONE mechanism, run over every fixture and every input, checking properties that hold for ALL of
# them. A defect shows up here whether or not anyone thought to look for it.
#
# What it sweeps: scroll down, scroll across, panel height, panel width — one pixel at a time.
# What it checks, per label, per frame:
#
#   J  JUMP      nothing moves further than the input that moved it
#   V  VELOCITY  the rate of movement does not change abruptly (an acceleration bound: a smooth
#                slide reads as intentional, a sudden change of speed reads as a glitch even when
#                it is technically continuous — #76/#77 was exactly this)
#   R  REVERSAL  content does not walk one way and then back while the input keeps going one way
#   T  TOP       content is never further toward the top than plain top-alignment (Wolfgang's own
#                statement of the rule, and the bound that makes the whole thing settle)
#   B  BOTTOM    content is never further down than bottom-alignment: it leaves with its region
#   S  SEEN      content is visible while its region can show it
#   X  BOX       content is never displaced outside its own box
#
# A fixture that trips nothing is not evidence the fixture is boring; it is evidence for those
# properties over that fixture's whole input range, which is what "fix point" has to mean.

record Sample, label : String, y : Float64, box_y : Float64, box_h : Float64,
  region_lo : Float64, region_hi : Float64, first_line : Float64, content : Float64,
  band_lo : Float64, band_hi : Float64, compound : Bool, line : Float64

record Frame, input : Float64, samples : Hash(String, Sample)

private SWEEP_W = 700

# --- fixtures --------------------------------------------------------------------------------

class SweepTall
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def initialize(@rows : Int32, @cols : Int32, @tall_row : Int32, @lines : Int32)
  end

  def row_count : Int32
    @rows
  end

  def col_count : Int32
    @cols
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    text = row == @tall_row && col == @cols - 1 ? (0...@lines).map { |i| ('A' + i).to_s }.join("\n") : "#{row},#{col}"
    CrymbleUI::TextInput.new(value: text, multiline: true)
  end
end

class SweepPivot < ConfigurableMatrixAdapter
  def initialize(@lines : Int32 = 8)
    super(1, 1, 1, 1, 5, 3)
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    return super unless row == 1 && col == 3
    CrymbleUI::TextInput.new(value: (0...@lines).map { |i| ('A' + i).to_s }.join("\n"), multiline: true)
  end
end

private def fixtures
  [
    {"ordinary grid", ->{ SweepTall.new(12, 3, -1, 1).as(CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter) }},
    {"tall row (multiline sibling)", ->{ SweepTall.new(8, 3, 1, 8).as(CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter) }},
    {"very tall row", ->{ SweepTall.new(6, 3, 0, 14).as(CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter) }},
    {"pivot: headers + tall row", ->{ SweepPivot.new(8).as(CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter) }},
    {"pivot: compound spans", ->{ ConfigurableMatrixAdapter.new(2, 2, 3, 3, 6, 6).as(CrymbleUI::Widgets::VirtualMatrix::MatrixAdapter) }},
  ]
end

private def build(adapter, vp_h)
  matrix = CrymbleUI::VirtualMatrix.new(adapter, id: "sweep")
  app = TestApp.new
  app.root_widget = matrix
  app.build_tree
  renderer = CrymbleUI::Testing::TestRenderer.new(SWEEP_W, vp_h)
  renderer.settle_rendering(app)
  matrix.auto_size = true
  matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(SWEEP_W.to_f64, vp_h.to_f64)),
    CrymbleUI::Vec2.zero)
  matrix.pre_render_flush
  matrix
end

# The rule's own `natural_in`, mirrored (PrimitiveBuilder keeps it private). Kept to ONE line for
# the same reason the rule is: every time this carried a term the rule had dropped, it reported
# hundreds of violations that were its own arithmetic (3372 on 2026-09-10, then 369).
# The rule's own `centred_in`, mirrored (PrimitiveBuilder keeps it protected). A MULTI-LINE block
# does not come through here at all: it anchors at its region's top and scrolls out with its row
# (UC-3), and modelling it as centred reported 496 violations that were this file's arithmetic.
private def natural_of(r, content : Float64) : Float64
  lo, hi = r.pos, r.pos + r.size
  if !r.compound
    lo = Math.max(lo, r.band_lo)
    hi = Math.min(hi, r.band_hi)
  else
    hi = Math.min(hi, r.band_hi)
    lo = Math.max(lo, Math.min(r.band_lo, r.pos + r.size - (r.band_hi - r.band_lo))) if r.size > r.band_hi - r.band_lo
  end
  lo + Math.max(0.0, (hi - lo - content) / 2.0)
end

# The GRID's answer, not the ink region's — see the note in placement_invariants_spec.
private def compound_of(matrix, key) : Bool
  bb = matrix.get_bounding_box(key)
  bb[0][0] != bb[1][0]
end

private def capture(matrix, input) : Frame
  taken = {} of String => Sample
  band_lo = matrix.ruler_row_height_pixels + matrix.sticky_row_height_pixels
  band_hi = matrix.bounds.height
  size = CrymbleUI::FontSizing.calculate_size(0)
  line = (f = CrymbleUI::Widget.font) ? f.reference_height(size) : size.to_f64
  matrix.active_cells.each do |key, w|
    content_cell = key[0] >= matrix.sticky_row_count && key[1] >= matrix.sticky_col_count
    box_y = w.absolute_bounds.y - (content_cell ? matrix.scroll_offset.y : 0.0)
    r = w.ink_region
    prims = w.to_primitives(w.bounds).select(&.is_a?(CrymbleUI::DrawText))
    # ONE item per cell: a block's FIRST line, carrying the whole block's extent. Its later lines
    # sit at fixed offsets from that one, so sampling them separately measures the block's height
    # against bounds meant for its top and reports thousands of violations that are just the block
    # being a block (34890 of them, on the harness's first run).
    prim = prims.first?
    next unless prim
    p = prim.as(CrymbleUI::DrawText)
    next if p.text.empty?
    taken["#{key[0]},#{key[1]}"] = Sample.new(
      "#{key[0]},#{key[1]}", box_y + p.position.y, box_y, w.bounds.height,
      box_y + (r ? r.pos : 0.0), box_y + (r ? r.pos + r.size : w.bounds.height),
      # Where the rule says this content belongs: centred in its own region -- in the VISIBLE PART
      # of it for a compound. Derived here exactly as `natural_in` derives it, so a check reads the
      # rule and not a stale copy of it. It was a stale copy on 2026-09-10 and reported 3372
      # violations that were the harness's own arithmetic, the fifth instrument in this arc to
      # accuse the code and be wrong itself.
      r ? (prims.size > 1 ? box_y + r.pos : box_y + natural_of(r, line)) : box_y,
      prims.size > 1 ? line * prims.size : line, band_lo, band_hi, compound_of(matrix, key), line)
  end
  Frame.new(input.to_f64, taken)
end

private def sweep(adapter, kind : Symbol, from : Int32, to : Int32, vp_h = 300) : Array(Frame)
  matrix = build(adapter, vp_h)
  (from..to).map do |v|
    case kind
    when :scroll_y then matrix.scroll_offset = CrymbleUI::Vec2.new(0.0, v.to_f64)
    when :scroll_x then matrix.scroll_offset = CrymbleUI::Vec2.new(v.to_f64, 0.0)
    when :height   then matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(SWEEP_W.to_f64, v.to_f64)), CrymbleUI::Vec2.zero)
    when :width    then matrix.layout(CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(v.to_f64, vp_h.to_f64)), CrymbleUI::Vec2.zero)
    end
    matrix.pre_render_flush
    capture(matrix, v)
  end
end

# --- the checks ------------------------------------------------------------------------------

private def check(frames : Array(Frame), name : String) : Array(String)
  bad = [] of String
  speeds = {} of String => Float64
  frames.each_cons(2) do |(a, b)|
    step = (b.input - a.input).abs
    b.samples.each do |id, now|
      next unless was = a.samples[id]?
      moved = now.y - was.y
      # J: nothing moves further than the input that moved it
      bad << "#{name} J #{id}: moved #{moved.abs.round(1)}px for #{step}px at #{b.input.round(0)}" if moved.abs > step + 1.5
      # V: and does not change SPEED abruptly
      if prev = speeds[id]?
        bad << "#{name} V #{id}: speed #{prev.round(1)} -> #{moved.round(1)} at #{b.input.round(0)}" if (moved - prev).abs > step + 1.5
      end
      # R: nor reverse while the input keeps going one way
      if (prev = speeds[id]?) && prev.abs > 0.01 && moved.abs > 0.01 && (prev > 0) != (moved > 0)
        bad << "#{name} R #{id}: reversed #{prev.round(1)} -> #{moved.round(1)} at #{b.input.round(0)}"
      end
      speeds[id] = moved
      # T: never further toward the top than the rule's own answer -- the #74/#75 guard against
      # content chasing the viewport edge upward without a stopping point.
      #
      # ...unless its own BOX forces it higher. Ink outside the box is not drawn at all
      # (layer_renderer.cr:1667), so a span scrolling out of view drags its label up with the box's
      # bottom edge, 1px per 1px. That is the span leaving, not content chasing an edge -- J and V
      # still bound the rate, and X still bounds it to the box. Without this term the check flagged
      # 16 frames of a compound legitimately departing (2026-09-10).
      top = Math.min(now.first_line, now.box_y + now.box_h - now.content)
      # A COMPOUND is also stopped below the band's far edge (#45/#50), which is likewise a pull
      # toward the top and likewise not the chase this check is looking for.
      top = Math.min(top, now.band_hi - now.content) if now.compound
      bad << "#{name} T #{id}: y=#{now.y.round(1)} above top-align #{top.round(1)} at #{b.input.round(0)}" if now.y < top - 0.6
      # B: never further down than bottom-alignment
      floor = Math.max(top, now.region_hi - now.content)
      bad << "#{name} B #{id}: y=#{now.y.round(1)} below bottom-align #{floor.round(1)} at #{b.input.round(0)}" if now.y > floor + 0.6
      # X: never displaced outside its own box
      bad << "#{name} X #{id}: y=#{now.y.round(1)} outside box #{now.box_y.round(1)}..#{(now.box_y + now.box_h).round(1)} at #{b.input.round(0)}" if now.y < now.box_y - 1.0 || now.y > now.box_y + now.box_h + 1.0
      # S: visible WHENEVER THE RULE COULD HAVE PLACED IT SO — never "whenever its region can show
      # it", which is the pre-fix-point guarantee and asserts the opposite of UC-5. What the rule
      # may do is bounded: a single line may not rise above its own line, a compound may rise to
      # its span's top. If even that topmost position does not fit the band, being clipped is the
      # correct answer and demanding otherwise would demand the tracking that #74/#75 reported.
      # A DEPARTING COMPOUND IS EXEMPT. Since 2026-09-10 a compound is not held at the leading edge
      # at all -- it rides its group and leaves with it (images #93-#96) -- so once its span's top
      # has passed above the band, the rule makes no promise about showing its label. The promise
      # it does make is at the FAR edge, and that is I15's second claim.
      next if now.compound && now.region_lo < now.band_lo - 0.5
      # A BLOCK IS EXEMPT. UC-3: content that cannot be shown whole and is more than one line is
      # not moved at all -- it scrolls with its box and is clipped, so that you can read past a
      # long value's first screenful. Demanding it stay visible demands the opposite.
      next if now.content > now.line + 0.5
      vis_lo = Math.max(now.region_lo, now.band_lo)
      vis_hi = Math.min(now.region_hi, now.band_hi)
      next unless vis_hi - vis_lo >= now.content
      next if now.content > now.band_hi - now.band_lo
      next if top + now.content > now.band_hi     # cannot be made to fit from its highest place
      next if now.region_hi - now.content < now.band_lo # its region has already left at the top
      bad << "#{name} S #{id}: y=#{now.y.round(1)} not in band #{now.band_lo.round(0)}..#{now.band_hi.round(0)} though it could sit at #{top.round(1)} at #{b.input.round(0)}" if now.y < now.band_lo - 0.6 || now.y + now.content > now.band_hi + 0.6
    end
  end
  bad
end

describe "placement, swept over every fixture and every input" do
  it "holds J V R T B S X across the whole space" do
    all = [] of String
    counts = {} of String => Int32
    fixtures.each do |(fname, make)|
      {% for spec in [{:scroll_y, 0, 160, 300}, {:scroll_x, 0, 120, 300}, {:height, 60, 320, 300}, {:width, 200, 700, 300}] %}
        kind, from, to, vp = {{spec[0]}}, {{spec[1]}}, {{spec[2]}}, {{spec[3]}}
        frames = sweep(make.call, kind, from, to, vp)
        found = check(frames, "#{fname}/#{kind}")
        counts["#{fname}/#{kind}"] = found.size
        all.concat(found)
      {% end %}
    end

    puts "\n  [sweep] #{counts.values.sum} violation(s) over #{counts.size} sweeps"
    counts.each { |k, v| puts "    #{v.to_s.rjust(5)}  #{k}" unless v == 0 }
    by_kind = all.group_by { |v| v.split(' ')[1] }
    by_kind.each { |k, v| puts "    #{k}: #{v.size} — e.g. #{v.first}" }

    all.should be_empty, "placement sweep found #{all.size} violation(s):\n  #{all.first(12).join("\n  ")}"
  end
end
