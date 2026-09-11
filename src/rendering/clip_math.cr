require "../core/types"
require "./pixel_snap"

module CrymbleUI
  # The ONE conversion from a clip stack to a device-pixel box.
  #
  # Both backends call it — `CrSFMLBackend` turns the box into the render target view's
  # scissor factors, `TestRenderBackend` compares written pixels against it. They used to
  # derive it separately and DRIFTED: three different stack-collapse semantics across two
  # files, and a rounding rule that clipped one column narrower headless than in
  # production. Sharing the WHOLE derivation — collapse, empty case and rounding — is what
  # makes that unrepresentable instead of merely spec-detected. A helper that shared only
  # the rounding would have left the collapse hand-copied, which is the half that drifted.
  #
  # Policy: docs/LAYER_RENDERING_ARCHITECTURE.md "Float-to-Integer Coordinate Rounding".
  module ClipMath
    # Device-pixel box `{x0, y0, x1, y1}` with x1/y1 EXCLUSIVE, or nil for an empty stack
    # (no clip — which is NOT the same as a zero-sized one).
    #
    # The stack collapses to its INTERSECTION: an inner clip can only ever shrink what an
    # outer one allows, never widen it. Intersect in FLOAT and convert ONCE at the end —
    # rounding each rect first and intersecting afterwards gives a different answer at
    # fractional boundaries.
    #
    # Roles, per the policy table: the origin is an ORIGIN (floor — translation-invariant
    # across zero, unlike truncation) and the extent is a conservative visibility BOUND
    # (cover/ceil — may over-include, never under-include). The extent must NOT round to
    # nearest: that gives 298 where the compositor samples 299 and shaves the rightmost
    # column of every layer, which is the "Historical seam note" defect.
    #
    # KNOWN LIMITATION, inherited deliberately: `cover(far - near)` is the true covering
    # extent only when `near` is whole. At a fractional origin it can under-cover by a
    # pixel (near 0.9, far 1.1 gives [0,1) where the covering box is [0,2)). Keeping it
    # means this change moves no pixel, and the clip that matters — the layer clip — has a
    # whole origin. Pinned by spec/rendering/clip_math_spec.cr so it stays a recorded
    # decision rather than a surprise.
    #
    # A NaN coordinate RAISES (max_of/min_of compare-or-raise). That is deliberate: a NaN
    # rect is a layout bug, and it detonates at push time in both backends alike.
    def self.device_box(stack : Array(Rect)) : Tuple(Int32, Int32, Int32, Int32)?
      return nil if stack.empty?

      left = stack.max_of(&.x)
      top = stack.max_of(&.y)
      right = stack.min_of { |r| r.x + r.width }
      bottom = stack.min_of { |r| r.y + r.height }

      x0 = PixelSnap.origin(left)
      y0 = PixelSnap.origin(top)
      # Extents floor at zero so a disjoint stack collapses to an empty box rather than a
      # negative one: a negative extent reaching glScissor is GL_INVALID_VALUE, which DROPS
      # the call and leaves the previous scissor live — a silent wrong-clip, not a no-op.
      {x0, y0,
       x0 + Math.max(0, PixelSnap.cover(right - left)),
       y0 + Math.max(0, PixelSnap.cover(bottom - top))}
    end
  end
end
