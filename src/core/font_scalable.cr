require "./font_sizing"

module CrymbleUI
  # Mixin for widgets that support font scaling.
  #
  # Provides:
  # - `font_scale` property (Int32, default 0) with auto layout invalidation
  # - `font_size` method that calculates pixel size from scale
  #
  # ## Usage
  #
  # ```crystal
  # class MyWidget < Widget
  #   include FontScalable
  #   # Now has: font_scale property, font_size method
  # end
  # ```
  #
  # ## Font Scale Values
  #
  # - 0 = base size (FontSizing::BASE_SIZE)
  # - +1, +2, ... = larger (each step × STEP_MULTIPLIER)
  # - -1, -2, ... = smaller (each step ÷ STEP_MULTIPLIER)
  #
  module FontScalable
    macro included
      # Font scale (relative sizing: 0 = base, +1 = larger, -1 = smaller)
      layout_property font_scale : Int32 = 0
    end

    # Calculated font size in pixels (respects global zoom)
    def font_size : Float64
      FontSizing.calculate_size(@font_scale)
    end
  end
end
