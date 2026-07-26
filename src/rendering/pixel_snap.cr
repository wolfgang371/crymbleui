module CrymbleUI
  # Snaps a draw position to a whole device pixel.
  #
  # Text positions are snapped to integers to avoid GPU bilinear blur on the glyph
  # atlas (fractional coords from zoom-centering arithmetic wash text out — 20a683b).
  #
  # REQUIRED INVARIANT — translation invariance: `snap(v + n) == snap(v) + n` for any
  # integer n. A widget's primitives are rasterized either widget-LOCAL (into its own
  # texture, then blitted at an integer offset) or layer-LOCAL (offset added before
  # rasterizing) — the same glyph must land on the same device pixel either way.
  # `Float64#round`'s default ties-to-even BREAKS this: rounding of an exact .5
  # fraction depends on the parity of the integer part, so a vertically-centered text
  # y like 3.5 rounds differently in the two coordinate frames — the cursor-cell
  # "text jitters 1px on click" bug (the click flips the cell's render path).
  module PixelSnap
    # Half-up: floor(v + 0.5). Unlike ties-to-even, this commutes with every integer
    # translation (floor((v+n) + 0.5) == floor(v + 0.5) + n), so both coordinate
    # frames snap a glyph to the same device pixel.
    def self.snap(v : Float64) : Float64
      (v + 0.5).floor
    end

    # Asserting cast for values that are WHOLE BY CONSTRUCTION (e.g. a viewport-cache
    # buffer_origin, quantized at its single writer). Not a rounding: a fractional
    # input is a broken invariant, not a value to fix — tolerance is exact 0.0.
    # Callers gate the call under their debug flag; the raise carries their context.
    def self.whole(v : Float64, context : String = "value") : Int32
      raise "#{context} must be whole-valued (got #{v})" unless v == v.round
      v.to_i32
    end

    # Widget/layer-local ORIGIN: floor, NOT truncate. Floor is translation-invariant
    # over the whole domain — truncation flips direction at zero (trunc(-0.5) = 0 but
    # trunc(0.5) = 0), the same frame-dependence class as the ties-even text bug. For
    # the non-negative coordinates that dominate production, floor == truncate, so the
    # change is confined to negative-fractional layer-local coords (top/left-clipped
    # content at fractional zoom). Feed the DIFFERENCE, never floor terms separately:
    # floor(a - b) != floor(a) - floor(b).
    def self.origin(v : Float64) : Int32
      v.floor.to_i32
    end

    # Backend/texture EXTENT: both edges converted with origin's floor direction, BY
    # CONSTRUCTION (span = origin(start+len) - origin(start)) — so adjacent siblings
    # tile exactly (no gap, no overlap) and the two directions can never drift apart.
    # Fixes the vanishing-widget case: a 1px widget at start -0.5 covers device pixel
    # 0 and now gets span 1 (truncate-both-edges gave 0 and the widget was dropped).
    def self.span(start : Float64, length : Float64) : Int32
      origin(start + length) - origin(start)
    end

    # Culling/visibility BOUND: ceil — conservative, may over-include a widget, never
    # under-include one (cover(len) >= span(start, len) for every placement).
    def self.cover(length : Float64) : Int32
      length.ceil.to_i32
    end
  end
end
