module CrymbleUI
  # Pure Int32/Float32 algebra of the two Y-flip sites in CrSFMLBackend. Extracted
  # so the flip arithmetic is testable in isolation (no GPU, no display) and can
  # never drift out of sync between its two production/instrument call sites.
  #
  # SURFACE-ORIENTATION CONVENTION TABLE (the ground truth these functions encode):
  #
  #   Surface / operation            | Vertical orientation      | Flip needed?
  #   -------------------------------|---------------------------|-------------------
  #   RenderTexture.texture (FBO)    | BOTTOM-UP                  | (it is the source
  #     — the GPU-sampled texture    |  texture row t == content  |  of the asymmetry)
  #                                  |  row (H - 1 - t)           |
  #   Window / on-screen draw        | TOP-DOWN (logical y down)  | —
  #   copy_to_image (GPU->CPU)       | TOP-DOWN (already de-      | none (see
  #                                  |  flipped by SFML on read)  |  LayerCapture)
  #   FULL-sprite blit               | SFML de-flips whole-sprite | NONE — do NOT
  #     (blit, entire texture)       |  draws automatically       |  add a Y-flip
  #   PARTIAL region blit            | samples a sub-rect of the  | YES — texture_rect
  #     (blit_region)                |  bottom-up FBO texture      |  Y invert + scale(-1)
  #   OpenGL scissor (apply_clip)    | GL origin is BOTTOM-LEFT    | YES — gl_y flip
  #
  # (Narration ported from crsfml_backend.cr:205-208 and :226-234: full-texture
  # blit needs NO flip — SFML handles it — but partial texture_rect sampling of the
  # bottom-up FBO texture DOES, and so does the GL scissor whose origin is at the
  # bottom.)
  #
  # LIMIT OF WHAT THIS MODULE + ITS SPECS PROVE: they prove the flip triple is
  # self-consistent with the convention table above (feeding the triple back
  # through the FBO + scale(-1) sprite conventions reconstructs a straight top-down
  # copy — the identity mapping TestRenderBackend's linear blit_region performs,
  # i.e. the cross-backend equivalence invariant). They do NOT witness the axiom
  # that a real SFML RenderTexture is actually bottom-up; that axiom is witnessed
  # ONLY by the SFML parity sweep.
  module FboMath
    # The three coupled outputs of a partial region blit off the bottom-up FBO
    # texture: where to sample (texture_rect_y), where to draw (draw_y), and the
    # vertical scale sign that re-flips the sampled band back to top-down.
    record BlitFlip,
      texture_rect_y : Int32,
      draw_y : Int32,
      scale_y : Float32

    # Partial-region blit off a bottom-up FBO texture of height `surface_height`.
    # To sample logical content rows [src_y, src_y + height), the texture_rect must
    # start at the FBO row H - src_y - height; drawing the (upside-down) sampled
    # band with scale_y = -1 at draw_y = dest_y + height re-flips it to a straight
    # top-down copy landing at logical content rows [dest_y, dest_y + height).
    def self.blit_region_flip(surface_height : Int32, src_y : Int32, height : Int32, dest_y : Int32) : BlitFlip
      BlitFlip.new(
        texture_rect_y: surface_height - src_y - height,
        draw_y: dest_y + height,
        scale_y: -1.0_f32
      )
    end

    # OpenGL scissor origin (bottom-left) for a top-down clip band [top, top+height)
    # on a surface of height `surface_height`. GL's Y origin is at the bottom, so the
    # band's GL origin is its distance from the bottom edge: H - (top + height).
    def self.scissor_gl_y(surface_height : Int32, top : Int32, height : Int32) : Int32
      surface_height - (top + height)
    end
  end
end
