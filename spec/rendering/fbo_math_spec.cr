require "spec"
require "../../src/rendering/fbo_math"

# FboMath is the pure Int32/Float32 algebra of the two Y-flip sites that make a
# CrSFMLBackend faithful to the top-down logical coordinate system despite the
# FBO's bottom-up sampled texture:
#   - blit_region_flip: texture_rect Y, scale sign, and draw Y for a partial
#     GPU→GPU region blit (crsfml_backend.cr#blit_region).
#   - scissor_gl_y: the OpenGL scissor origin for a top-down clip band
#     (crsfml_backend.cr#apply_clip).
#
# WHAT THESE SPECS PROVE (and their LIMIT):
#   They prove the flip algebra is SELF-CONSISTENT with the documented
#   surface-orientation convention (see the convention table in
#   src/rendering/fbo_math.cr and LAYER_RENDERING_ARCHITECTURE.md): that feeding
#   the triple back through the FBO-texture and scale(-1) sprite conventions
#   reconstructs a straight top-down copy. They do NOT witness the underlying
#   axiom (that a real SFML RenderTexture is actually bottom-up) — that axiom is
#   witnessed only by the SFML parity sweep. If the convention table is wrong,
#   these specs are still internally consistent; the sweep is the external oracle.
#
# The tests are DISCRIMINATING, not a bare involution: the plausible off-by-one
#   g(y) = H - y - h + 1
# also round-trips as an involution but FAILS the anchored endpoint values and
# the end-to-end identity below.

module FboMathSpecConventions
  # Documented convention A — the source RenderTexture's SAMPLED texture is FBO
  # bottom-up: texture pixel row t shows logical content row (H - 1 - t).
  # (crsfml_backend.cr:205-208/226-234 narration.)
  def self.content_row_at_texture_row(surface_height : Int32, texture_row : Int32) : Int32
    surface_height - 1 - texture_row
  end

  # Documented convention B — a sprite drawn at position draw_y with scale_y = -1
  # places its LOCAL pixel row L at destination content row (draw_y - 1 - L).
  def self.dest_row_for_local_row(draw_y : Int32, local_row : Int32) : Int32
    draw_y - 1 - local_row
  end
end

describe CrymbleUI::FboMath do
  describe ".blit_region_flip" do
    # Anchored endpoints of texture_rect_y = H - src_y - h. A pure involution
    # (round-trips) is NOT enough — these concrete values reject g(y)=H-y-h+1.
    it "maps the top source row (h=1, src_y=0) to the bottom texture row H-1" do
      h = 64
      CrymbleUI::FboMath.blit_region_flip(h, 0, 1, 0).texture_rect_y.should eq(h - 1)
    end

    it "maps the bottom source row (h=1, src_y=H-1) to the top texture row 0" do
      h = 64
      CrymbleUI::FboMath.blit_region_flip(h, h - 1, 1, 0).texture_rect_y.should eq(0)
    end

    it "maps a full-surface region (src_y=0, h=H) to texture row 0" do
      h = 64
      CrymbleUI::FboMath.blit_region_flip(h, 0, h, 0).texture_rect_y.should eq(0)
    end

    it "carries draw_y = dest_y + h and scale_y = -1.0" do
      flip = CrymbleUI::FboMath.blit_region_flip(64, 10, 8, 25)
      flip.draw_y.should eq(25 + 8)
      flip.scale_y.should eq(-1.0_f32)
    end
  end

  describe ".scissor_gl_y" do
    # Anchored endpoints of gl_y = H - (top + h). A top-anchored clip band lands
    # at gl origin H-h; a bottom-anchored band lands at gl origin 0.
    it "maps a top-anchored band (top=0) to gl origin H-h" do
      h = 20
      CrymbleUI::FboMath.scissor_gl_y(100, 0, h).should eq(100 - h)
    end

    it "maps a bottom-anchored band (top=H-h) to gl origin 0" do
      h = 20
      CrymbleUI::FboMath.scissor_gl_y(100, 100 - h, h).should eq(0)
    end

    it "maps a full-height band to gl origin 0" do
      CrymbleUI::FboMath.scissor_gl_y(100, 0, 100).should eq(0)
    end
  end

  # END-TO-END CROSS-BACKEND EQUIVALENCE.
  #
  # Compose the blit_region flip triple back through the two documented
  # conventions (A: FBO bottom-up texture, B: scale(-1) sprite draw). For every
  # logical row of an h-tall region, the sampled SOURCE content row and the
  # DRAWN DEST content row must satisfy the IDENTITY (linear, unit-slope) mapping
  #   dest_content_row - dest_y == src_content_row - src_y
  # i.e. the band [src_y, src_y+h) is copied ORDER-PRESERVING to [dest_y, dest_y+h).
  # That is exactly the mapping TestRenderBackend's linear (top-down) blit_region
  # performs — so this equality IS the cross-backend equivalence invariant the cv
  # instrument relies on (both backends must agree). g(y)=H-y-h+1 breaks it.
  describe "end-to-end source-logical-row -> dest-logical-row identity (the cross-backend equivalence)" do
    it "reconstructs the linear identity copy across a grid of (H, src_y, h, dest_y) incl. edges" do
      surface_heights = [1, 2, 3, 8, 64, 100, 1024]
      surface_heights.each do |h_surface|
        # src_y and region-height h sampled within [0, H); include both edges.
        src_ys = [0, 1, h_surface // 2, h_surface - 1].select { |v| v >= 0 && v < h_surface }.uniq
        src_ys.each do |src_y|
          region_hs = [1, 2, (h_surface - src_y) // 2, h_surface - src_y].select { |v| v >= 1 && src_y + v <= h_surface }.uniq
          region_hs.each do |h|
            # dest_y edges: origin, small, at-surface, past-surface (algebra is placement-independent).
            [0, 1, 5, h_surface, 2 * h_surface].each do |dest_y|
              flip = CrymbleUI::FboMath.blit_region_flip(h_surface, src_y, h, dest_y)
              flip.scale_y.should eq(-1.0_f32)

              sampled_src_rows = [] of Int32
              drawn_dest_rows = [] of Int32
              (0...h).each do |local_row|
                texture_row = flip.texture_rect_y + local_row
                src_content = FboMathSpecConventions.content_row_at_texture_row(h_surface, texture_row)
                dest_content = FboMathSpecConventions.dest_row_for_local_row(flip.draw_y, local_row)

                # The load-bearing equality: dest offset == src offset (unit-slope identity).
                (dest_content - dest_y).should eq(src_content - src_y),
                  "H=#{h_surface} src_y=#{src_y} h=#{h} dest_y=#{dest_y} L=#{local_row}: " \
                  "src_content=#{src_content} dest_content=#{dest_content}"

                sampled_src_rows << src_content
                drawn_dest_rows << dest_content
              end

              # The copied band covers exactly the intended source and dest rows.
              sampled_src_rows.sort.should eq((src_y...(src_y + h)).to_a)
              drawn_dest_rows.sort.should eq((dest_y...(dest_y + h)).to_a)
            end
          end
        end
      end
    end
  end
end
