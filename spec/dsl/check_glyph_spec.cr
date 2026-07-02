require "../spec_helper"
require "../../src/dsl/primitive_builder"
require "../../src/core/types"

# step 1: the shared checkbox-glyph drawer extracted from Checkbox#to_primitives,
# reused by ComboBoxItem's multi-select gutter and menu_item (option B). It draws the
# REAL checkbox visual (box outline + state mark), NOT a text glyph — so its guard is a
# primitive-SHAPE assertion per CheckState, not a rendered string.
#
# Geometry mirror (checkbox.cr): box = 4 fill_rect edges (always); Checked = 2 draw_line
# + 1 draw_circle junction; Indeterminate = 1 draw_line dash; Unchecked = box only.

# Minimal PrimitiveBuilder host so the helper can be exercised in isolation.
private class GlyphProbe
  include CrymbleUI::PrimitiveBuilder

  def render(state : CrymbleUI::CheckState) : Array(CrymbleUI::DrawPrimitive)
    rect = CrymbleUI::Rect.new(0.0, 0.0, 16.0, 16.0)
    black = CrymbleUI::Color.new(0, 0, 0, 255)
    primitives do
      draw_check_glyph(state, rect, box_color: black, check_color: black,
        line_thickness: 2.0, junction_radius: 1.0)
    end
  end
end

private def counts(prims)
  {
    fill:   prims.count(&.is_a?(CrymbleUI::FillRect)),
    line:   prims.count(&.is_a?(CrymbleUI::DrawLine)),
    circle: prims.count(&.is_a?(CrymbleUI::DrawCircle)),
    text:   prims.count(&.is_a?(CrymbleUI::DrawText)),
  }
end

describe "draw_check_glyph (shared checkbox visual)" do
  it "draws ONLY the box (4 edges) when Unchecked — no mark, no text glyph" do
    c = counts(GlyphProbe.new.render(CrymbleUI::CheckState::Unchecked))
    c[:fill].should eq(4) # box outline
    c[:line].should eq(0)
    c[:circle].should eq(0)
    c[:text].should eq(0) # NOT a text glyph
  end

  it "draws the box + a checkmark (2 lines + junction) when Checked" do
    c = counts(GlyphProbe.new.render(CrymbleUI::CheckState::Checked))
    c[:fill].should eq(4)
    c[:line].should eq(2)
    c[:circle].should eq(1)
    c[:text].should eq(0)
  end

  it "draws the box + a single dash when Indeterminate" do
    c = counts(GlyphProbe.new.render(CrymbleUI::CheckState::Indeterminate))
    c[:fill].should eq(4)
    c[:line].should eq(1)
    c[:circle].should eq(0)
    c[:text].should eq(0)
  end
end
