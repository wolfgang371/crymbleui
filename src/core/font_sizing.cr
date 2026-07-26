require "./cached"

module CrymbleUI
  # FontSizing provides relative font scaling with global zoom support.
  #
  # Instead of absolute font sizes (16.0, 14.0, etc.), widgets use integer
  # scale values (-2, -1, 0, +1, +2, etc.). The actual pixel size is calculated
  # using a base size and step multiplier.
  #
  # Formula: actual_size = BASE_SIZE × (STEP_MULTIPLIER ^ scale) × zoom_factor
  #
  # Scale reference (at zoom 1.0):
  #   -2 → 11.57pt
  #   -1 → 12.73pt
  #    0 → 14.0pt (base)
  #   +1 → 15.4pt
  #   +2 → 16.94pt
  #   +3 → 18.63pt
  #   +4 → 20.49pt
  #
  # Global zoom uses precomputed discrete levels (Ctrl++/-, Ctrl+MouseWheel):
  #   50%, 60%, 70%, 80%, 90%, 100%, 110%, 125%, 150%, 175%, 200%, 250%, 300%
  module FontSizing
    # Base font size in points (scale 0 = 14pt)
    BASE_SIZE = 14.0

    # Each scale step multiplies by this factor (10% per step)
    STEP_MULTIPLIER = 1.1

    # Precomputed scale multipliers (avoid ** on every call)
    # Range covers typical usage: -5 (tiny) to +10 (huge)
    SCALE_RANGE = -5..10
    SCALE_MULTIPLIERS = SCALE_RANGE.to_a.map { |s| STEP_MULTIPLIER ** s }

    # Precomputed zoom levels (min 50%, max 300%)
    # These are discrete steps for Ctrl++/- and Ctrl+MouseWheel
    ZOOM_LEVELS = [
      0.5,   # 50%
      0.6,   # 60%
      0.7,   # 70%
      0.8,   # 80%
      0.9,   # 90%
      1.0,   # 100% (default)
      1.1,   # 110%
      1.25,  # 125%
      1.5,   # 150%
      1.75,  # 175%
      2.0,   # 200%
      2.5,   # 250%
      3.0,   # 300%
    ]

    # Index of 1.0 (100%) in ZOOM_LEVELS
    DEFAULT_ZOOM_INDEX = 5

    # Current zoom level index, held in a tracked Source so a Cached node that READS zoom (via
    # zoom_factor / calculate_size / measure_text) during its recompute AUTO-CAPTURES the zoom edge
    # Reading it outside a recompute just returns the value — zero behaviour change.
    @@zoom_index_source : Source(Int32) = Source(Int32).new(DEFAULT_ZOOM_INDEX)

    # Zoom epoch counter - increments on every zoom change
    # Used for DEBUG_ZOOM instrumentation to detect stale cached primitives
    @@zoom_epoch : UInt64 = 0

    # Callback invoked when zoom changes (for cache invalidation)
    # Renderers register this to reload fonts and clear cached textures
    @@on_zoom_change : Proc(Nil)? = nil

    def self.on_zoom_change=(callback : Proc(Nil)?)
      @@on_zoom_change = callback
    end

    private def self.notify_zoom_change
      @@on_zoom_change.try(&.call)
    end

    # Get current zoom level index
    def self.zoom_index : Int32
      @@zoom_index_source.get
    end

    # Observability: how many pull nodes currently depend on the zoom Source (see Theme's twin). A leak
    # shows as this growing per rebuild; the dispose-on-rebuild fix keeps it steady.
    def self.zoom_source_dependent_count : Int32
      @@zoom_index_source.dependent_count
    end

    # Get current zoom epoch (increments on every zoom change)
    def self.zoom_epoch : UInt64
      @@zoom_epoch
    end

    # Get current zoom factor (from precomputed levels)
    def self.zoom_factor : Float64
      ZOOM_LEVELS[@@zoom_index_source.get]
    end

    # Calculate actual font size from scale value
    def self.calculate_size(scale : Int32) : Float64
      BASE_SIZE * SCALE_MULTIPLIERS[scale - SCALE_RANGE.begin] * zoom_factor
    end

    # Zoom in by one level
    # Returns true if zoom changed, false if already at max
    def self.zoom_in : Bool
      idx = @@zoom_index_source.get
      if idx < ZOOM_LEVELS.size - 1
        @@zoom_index_source.set(idx + 1) # bumps the Source + marks captured dependents dirty
        @@zoom_epoch += 1                # kept during migration for the hand-rolled cache key
        notify_zoom_change
        true
      else
        false
      end
    end

    # Zoom out by one level
    # Returns true if zoom changed, false if already at min
    def self.zoom_out : Bool
      idx = @@zoom_index_source.get
      if idx > 0
        @@zoom_index_source.set(idx - 1)
        @@zoom_epoch += 1
        notify_zoom_change
        true
      else
        false
      end
    end

    # Reset zoom to 100%
    def self.reset_zoom
      @@zoom_index_source.set(DEFAULT_ZOOM_INDEX)
      @@zoom_epoch += 1
      notify_zoom_change
    end

    # Get current zoom as percentage string (e.g., "100%", "150%")
    def self.zoom_percentage : String
      "#{(zoom_factor * 100).round.to_i}%"
    end
  end
end
