require "../rendering/draw_primitive"
require "../core/types"
require "../widgets/text_lines" # block geometry has ONE owner; this asks it rather than re-deriving

module CrymbleUI
  # DSL for building primitive lists declaratively
  #
  # Usage:
  #   class MyWidget < Widget
  #     include PrimitiveBuilder
  #
  #     def to_primitives(bounds : Rect) : Array(DrawPrimitive)
  #       primitives do
  #         fill_rect(bounds, color)
  #         draw_text("Hello", pos, color)
  #       end
  #     end
  #   end
  module PrimitiveBuilder
    @primitives : Array(DrawPrimitive)?

    # DSL entry point - execute block and return collected primitives
    def primitives(&block) : Array(DrawPrimitive)
      @primitives = [] of DrawPrimitive
      yield
      @primitives.not_nil!
    end

    # Fill a rectangle with a solid color
    def fill_rect(bounds : Rect, color : Color)
      @primitives.not_nil! << FillRect.new(bounds, color)
    end

    # Fill a widget's ENTIRE background. Use this — not fill_rect(Rect.new(0,0,bounds.width,
    # bounds.height)) — for a full-area background. The widget_backend is pixel-snapped to
    # floor(abs_right)-floor(abs_left), which is up to 1px WIDER than the logical bounds.width when
    # the widget sits on a fractional position (e.g. a half-pixel from an Expanded 50/50 split). A
    # fill of the logical width then leaves that last column transparent — a 1px white "strip" at the
    # widget's right/bottom edge that blinks in at the window widths where the split lands on x.5.
    # ceil covers the snapped backend in every case (ceil(bounds.width) >= widget_width); the fill is
    # clamped to the backend, so it never bleeds onto a sibling.
    def fill_background(bounds : Rect, color : Color)
      @primitives.not_nil! << FillRect.new(Rect.new(0.0, 0.0, bounds.width.ceil, bounds.height.ceil), color)
    end

    # Draw text at a position with automatic SFML offset compensation
    #
    # SFML's sf::Text has internal offsets (local_bounds.left/top) that shift where
    # glyphs actually render. Without compensation, text appears to have unequal padding
    # and can render outside widget bounds.
    #
    # This function compensates by subtracting the offsets, ensuring:
    # 1. Visual glyphs appear exactly at the requested position
    # 2. Text stays within bounds measured by measure_text()
    # 3. Equal visual padding on all sides when centered
    #
    # Research: Based on SFML Game Development Book's centerOrigin() implementation
    # which adds offsets when centering: origin = (left + width/2, top + height/2)
    # We do the inverse: position = requested_pos - (left, top)
    # NOTE: Uses font_scale (Int32) to enforce zoom-aware font sizing
    def draw_text(text : String, position : Vec2, color : Color, font_scale : Int32 = 0)
      size = FontSizing.calculate_size(font_scale)
      # Get the font to measure offsets
      if font = Widget.font
        # Text may have left/top offsets in rendering (SFML-specific)
        # The visual glyphs start at (position.x + left, position.y + top)
        # We compensate by subtracting these offsets so visual glyphs appear at the requested position
        left_offset, top_offset = font.get_text_offsets(text, size)
        adjusted_position = Vec2.new(position.x - left_offset, position.y - top_offset)
        @primitives.not_nil! << DrawText.new(text, adjusted_position, color, size)
      else
        # Fallback if no font loaded (shouldn't happen in practice)
        @primitives.not_nil! << DrawText.new(text, position, color, size)
      end
    end

    # Local y at which to draw a single line of text so it is vertically centered in the
    # band [band_top, band_top + band_height]. draw_text anchors the cap-top, so we centre
    # the font's real visual extent (reference_height) -- NOT the em font_size, which
    # over-reserves the descender slot and makes text sit high. Headless fonts report
    # reference_height == font_size, so this reduces to the previous `(h - font_size)/2`.
    def vcentered_text_y(band_height : Float64, font_scale : Int32 = 0, band_top : Float64 = 0.0) : Float64
      size = FontSizing.calculate_size(font_scale)
      ref_h = (font = Widget.font) ? font.reference_height(size) : size
      anchor = band_top + (band_height - ref_h) / 2.0
      # Asked of the includer rather than defaulted here: widgets include this module DIRECTLY
      # (text.cr:9), which puts it ahead of Widget in the ancestor chain, so a default defined
      # here would SHADOW Widget's property and silently answer nil for every cell. Bound to a
      # local because `responds_to?` narrows a variable, not an implicit self.
      me = self
      if me.responds_to?(:ink_region) && (r = me.ink_region)
        placed = place_ink(r, ref_h, ref_h, false, band_top)
        remember_ink(ref_h, ref_h, false, band_top, placed)
        return placed
      end
      remember_ink(ref_h, ref_h, false, band_top, anchor)
      anchor
    end

    # Where to draw a BLOCK of `line_count` lines.
    #
    # Two regimes, and the boundary between them is a LINE COUNT, not a size — so nothing steps as
    # a row or a band is dragged past a threshold. (An earlier version switched on "does the block
    # fit", and the anchor moved half a line per extra line at the crossing: a three-line cell's
    # text jumped a whole line when a row was dragged one pixel. The guard for that is the
    # continuity sweep, because a spec that checks each regime separately cannot see a step
    # between them.)
    #
    #   one line     -> centred in its region, exactly as `vcentered_text_y` does it
    #   many lines   -> ANCHORED at the region's top; the row's slack falls BELOW the text
    #
    # Why the asymmetry, and it is the only one in the rule: rows quantise to whole frame units, so
    # a row grown to fit a block picks up slack it did not ask for — some 40px, since the block's
    # natural height carries its own leading and padding. Centred, half of that lands ABOVE the
    # text and the row begins visibly further from its top grid line than every other row: 24.5px
    # against 3px, measured both ways on Wolfgang's shape ("more space to the upper grid than other
    # rows", #79). Reading starts at line 1, so the slack belongs after the text.
    #
    # Content taller than the band is not moved at all — see `held_in_region`'s first line (UC-3).
    #
    # Takes a COUNT rather than a measured extent: the value in scope at a widget call site is
    # `measure_text(text).height`, which is the SLOT and not the ink, and passing it would shift
    # every single-line label by half the leading with nothing going red headlessly.
    def vcentered_block_y(band_height : Float64, line_count : Int32, font_scale : Int32 = 0,
                          band_top : Float64 = 0.0) : Float64
      size = FontSizing.calculate_size(font_scale)
      # Asked of TextLines rather than spelled out again: that type declares itself the one
      # owner of block geometry, and a second copy of this formula here is exactly the drift
      # it exists to prevent.
      block_extent = TextLines.block_extent(line_count, size)
      ref_h = TextLines.ref_h(size)
      # The BOX's own answer, for the ~11 callers that live outside a scrolling container.
      anchor = band_top + (line_count > 1 ? 0.0 : Math.max((band_height - block_extent) / 2.0,
        Math.min(0.0, (band_height - ref_h) / 2.0)))
      # The three regimes above answer "where in my box"; the band answers "and where can it be
      # SEEN". Additive on purpose: with no band this is byte-identical to what it always was,
      # so every one of the ~11 callers outside a scrolling container is untouched.
      me = self
      if me.responds_to?(:ink_region) && (r = me.ink_region)
        # The same two regimes as the plain anchor above, against the REGION instead of the box.
        # They must agree: this path runs only where a cell HAS an ink region, so letting the two
        # answer differently puts a step at the frame a region appears — measured as a block
        # reversing direction mid-scroll, -1.0px then +0.5px at scroll 24 (sweep R), when this
        # branch alone was changed.
        placed = place_ink(r, block_extent, ref_h, line_count > 1, band_top)
        remember_ink(block_extent, ref_h, line_count > 1, band_top, placed)
        return placed
      end
      remember_ink(block_extent, ref_h, line_count > 1, band_top, anchor)
      anchor
    end

    # WHERE THIS WIDGET'S INK LANDED LAST TIME, and where it would land under another region.
    #
    # The matrix needs this to decide what to REPAINT. Marking on a changed region is far too
    # coarse: a region is restated against a moving box every frame, so on one scroll frame of a
    # 100-row grid 96 of 126 cells get a different region and place their ink in exactly the same
    # place (their position is clamped, so the change is absorbed). Repainting on the region
    # repaints all 96; skipping by the band misses the 6 whose ink DID move while off-band, whose
    # stale pixels the viewport cache then blits back into view. Only the ink itself is the truth.
    #
    # Every INPUT the placement consumed is remembered, not just the content, because the answer
    # must be REPLAYED exactly rather than approximated. A first version kept only the content and
    # re-derived the rest: it passed the content where the block passes one LINE, and centred a
    # multi-line block that is anchored at its top. Both are invisible on a single-line cell, which
    # is most of a grid, so it measured as a working cache right up to the cells that matter.
    #
    # Recorded on the anchor path as well as the held one. Only the held path recorded at first,
    # and a cell that scrolled through a frame with NO region drew its anchor while the memory
    # still held the last held value — so the next frame compared against ink the cell never drew
    # and skipped the repaint. That is a stale cache produced BY the mechanism meant to prevent it
    # (cell {2,2} at scroll 0 -> 50, ink -83 -> -80, unmarked). The rule is simply: whatever this
    # widget places, it remembers.
    @ink_content : Float64? = nil
    @ink_line : Float64? = nil
    @ink_top_anchored : Bool = false
    @ink_band_top : Float64 = 0.0
    @ink_placed : Float64? = nil

    # WHERE INK GOES WHEN A REGION HOLDS IT -- the only copy of that answer.
    #
    # Both placement methods and the repaint predictor call this one. They used to spell it out
    # separately, and the predictor's spelling drifted: it passed the block's whole extent where
    # the placement passes one LINE, and centred a block the placement anchors at its top. The
    # cost of a second copy here is not a wrong pixel, it is a cell reported as NOT MOVED whose
    # cache is then never rebuilt -- the disagreement is invisible until it shows as a stale
    # rendering on screen, which is the most expensive way to learn of it.
    private def place_ink(region, content : Float64, line : Float64, top_anchored : Bool,
                          band_top : Float64) : Float64
      start = top_anchored ? region.pos + band_top : natural_in(region, content)
      confine(held_in_region(start, region.pos, region.size, content, region.band_lo,
        region.band_hi, line, region.pinned), content)
    end

    private def remember_ink(content : Float64, line : Float64, top_anchored : Bool,
                             band_top : Float64, placed : Float64) : Nil
      @ink_content = content
      @ink_line = line
      @ink_top_anchored = top_anchored
      @ink_band_top = band_top
      @ink_placed = placed
    end

    # nil until the widget has placed ink once, and whenever it has none to place.
    def ink_moves_under?(region) : Bool?
      content = @ink_content
      line = @ink_line
      placed = @ink_placed
      return nil unless content && line && placed
      return nil unless region # the widget's own anchor, which this cannot reproduce here
      # Byte-identical to the held branch of vcentered_text_y / vcentered_block_y, which is the
      # whole contract of this method: a prediction that merely resembles the placement reports a
      # cell as unmoved and leaves its cache showing the old position.
      would = place_ink(region, content, line, @ink_top_anchored, @ink_band_top)
      # A PIXEL is the unit that matters: ink is snapped at draw, so a sub-pixel difference paints
      # the same and a repaint would be waste.
      would.round != placed.round
    end

    # Confine placed ink to the widget's CURRENT box.
    #
    # `InkRegion#box` records the box as it was when the region was derived, and that can already
    # be stale: pre_render_flush derives regions, then auto-size re-fits the row SMALLER in the
    # same frame. The region's own copy then permits a position the box no longer has, which is how
    # a label ended up 37.5px into a 36px box and clipped away (embrace I3, `0,0:a`, constant at
    # y=425.9 while its box shrank beneath it). Ink outside the box is not drawn at all
    # (layer_renderer.cr:1667), so this is where placement has to stop.
    private def confine(y : Float64, content : Float64) : Float64
      me = self
      return y unless me.responds_to?(:bounds)
      h = me.bounds.height
      return y unless h > 0.0
      y.clamp(0.0, Math.max(0.0, h - content))
    end

    # WHERE CONTENT SITS: centred in the PART OF ITS REGION YOU CAN SEE (`centred_in`).
    #
    # A region is the cell's own row for an ordinary cell and for a ruler number, and the whole
    # SPAN for a compound, because a compound's label names a group of lines and belongs in the
    # middle of the group. Every single-line label of one row therefore lands on the same y — they
    # share a region and a content height — which is what Wolfgang asked for on 2026-09-10 after
    # two days of first-line alignment: "seems level, now, finally, but I see no vcentering at all".
    private def natural_in(r, content : Float64) : Float64
      centred_in(r.pos, r.size, content, r.band_lo, r.band_hi)
    end

    # WHERE CONTENT SITS, before the box has its say: CENTRED IN THE PART OF ITS REGION YOU CAN
    # SEE. A region is the cell's own row for an ordinary cell and for a ruler number; the whole
    # SPAN for a compound, because a compound's label names a GROUP of lines and belongs in the
    # middle of the group. Centring in the region is what this library has always done.
    #
    # ONE EXPRESSION, NO CASES. The region is clamped into the band at both ends and the content
    # centred in what is left — the same arithmetic for a row and for a span, for either edge, at
    # any size. Everything the field reports asked for is a CONSEQUENCE of it:
    #
    #   fully visible         the slice IS the region, so content sits at the region's centre
    #   taller than the band  the slice IS the band, so content sits at the band's centre and
    #                         stays there however the row grows (#97/#98)
    #   leaving               the slice shrinks; content moves at half the scroll and never stops,
    #                         landing on the group's last visible row (#93-#96, both halves)
    #   arriving              the mirror of leaving, from the far edge (#45/#50)
    #   either edge           one moving end either way, so the same half-scroll rate (#105-#108)
    #
    # It had three branches between 2026-09-08 and 2026-09-11 — a floor at one edge only, then a
    # threshold on the span's size, then an allowance proportional to the overflow — and every one
    # of them existed to defend a misreading of the oldest report. "Sticky" (#93-#96) was taken to
    # mean "the label's offset inside its span must not change"; it means the label must not STOP.
    # A POSITION clamp stops things. A REGION clamp cannot: both of its ends move continuously, so
    # the content it centres does too. Delete the misreading and the branches have nothing to do.
    #
    # CLAMPING THE REGION AND NOT THE POSITION is also what keeps a line together. Every cell of a
    # line shares its region, so they centre in the same slice and stay level; a bound written in
    # each cell's own glyph height (`band_hi - content`) moves a ruler number and its cell by
    # different amounts and parts them by 4.2px (UC-15, #45).
    #
    # Takes RAW NUMBERS so the RULER can call it too. The ruler had its own copy of this formula
    # until 2026-09-10, and the copy is what let the two drift apart the moment the rule changed.
    protected def centred_in(pos : Float64, size : Float64, content : Float64,
                             band_lo : Float64, band_hi : Float64) : Float64
      hi = Math.min(pos + size, band_hi)
      lo = Math.max(pos, band_lo)
      lo + Math.max(0.0, (hi - lo - content) / 2.0)
    end


    # WHERE THE INK MAY ACTUALLY GO: `natural` (above), kept inside its own REGION.
    #
    # Everything here is a bound; none of it moves content whose natural position already lies in
    # its region, which is the ordinary case — so the centring above survives untouched, and this
    # is not a second placement rule. It matters when the slice degenerates: `centred_in` clamps
    # the region into the band, and when the two barely overlap the midpoint it returns can fall
    # outside the region itself. Measured: it moves a label on 25351 frames across the suites, by
    # up to 50px.
    #
    # THREE STEPS, THREE JOBS, and this is the middle one — `centred_in` decides where content
    # wants to be, this keeps it in its region, `confine` keeps it in its BOX. The box is
    # deliberately not repeated here: `confine` uses the box as it is NOW, where a region carries a
    # copy that auto-size can invalidate within the same frame.
    #
    # NOT MOVED AT ALL when the content cannot be shown whole AND is more than one line: that is a
    # value you scroll through, and pinning it would stop you reading past its first screenful
    # (core doc/08-shapes.md, UC-3). A single line never takes that exit, however thin the band —
    # it has no second screenful to reach, so opting out buys nothing and costs a discontinuity
    # exactly where the band passes one line's height (a compound's label jumped 198.5px for 1px of
    # resize at the frame the band became 14px tall, found by the sweep and by nobody looking).
    def held_in_region(natural : Float64, region_pos : Float64, region_size : Float64,
                       content : Float64, band_lo : Float64, band_hi : Float64,
                       line : Float64 = 0.0, pinned : Bool = false) : Float64
      return natural if content > band_hi - band_lo && content > line + 0.5
      # Inside its own REGION, and that is all. The BOX is `confine`'s job, which runs after this
      # and uses the box as it is NOW rather than as the region recorded it — a distinction that
      # matters, because auto-size can re-fit a row smaller in the same frame the region was
      # derived in. Clamping to the box here as well was redundant: measured 2026-09-11 at 0
      # differing frames across the sweep and every compound suite.
      lo = region_pos
      hi = region_pos + region_size
      # A PINNED clone is floored at the band too: the sticky machinery holds its box still while
      # the group scrolls away, so the region alone lets the label follow the span up and out of
      # the box, where the widget's clip shaves it (measured at 2, then 4, then 6px of overhang,
      # growing with the scroll).
      #
      # `pinned` is TOLD to us by the matrix, which knows it — the cell's Y box comes from
      # StickyMath.compound_axis (sticky_reposition.cr:110). It was inferred here from the geometry
      # until 2026-09-11 (`the region reaches outside the box`), and that inference was wrong about
      # 5861 samples across these suites — always in the same direction, calling a genuinely pinned
      # box unpinned when its span happened to fit. It produced the right placement in every one of
      # them, because the floor is inert exactly where it misclassified, which is the definition of
      # accidentally right.
      floor = pinned ? Math.max(lo, band_lo) : lo
      Math.min(Math.max(natural, floor), Math.max(floor, hi - content))
    end

    # The VERTICAL cut hint: a full-width band along an edge where the block is cut.
    #
    # The exact transposition of the horizontal marker, deliberately: same nominal thickness,
    # same third-of-the-box cap, same backdrop, drawn BEHIND the glyphs. One cue, two axes —
    # a user learns it once.
    #
    # It does NOT try to sit in whatever gap the ink leaves. That was the first attempt, and
    # it degenerates: the last drawn line is usually itself cut, so the "available" space is
    # negative and the band collapses to a 1px hairline in a different colour from its own
    # horizontal twin — which reads as a rendering artifact rather than as a marker. The X
    # band never kept clear of ink either; it is drawn behind the glyphs, which is exactly
    # what makes it legible without hiding what it reports on.
    #
    # The predicate is the caller's, and it must be about whole hidden LINES, never about ink
    # crossing an edge: a single line's glyphs legitimately overhang a tight cell (a 17px row
    # leaves a 7px content box for a 14px font), so an ink test would light a band on every
    # cell in every table. `content_above` / `content_below` mean "a hidden line actually
    # carries something" — a value of nothing but a break has a second line, but nothing to
    # promise.
    #
    # `box` is the widget-local area the band may occupy, bottom-inclusive.
    def clipped_block_bands(box : Rect, content_above : Bool, content_below : Bool) : Tuple(Rect?, Rect?)
      return {nil, nil} unless content_above || content_below
      # Capped at a third of the box so it cannot swallow a short row, floored at 1px so it
      # cannot vanish exactly where the value is most cut — the same two bounds the
      # horizontal band uses, for the same two reasons.
      thickness = Math.max(CLIPPED_MARKER_MIN_THICKNESS,
        Math.min(CLIPPED_MARKER_WIDTH * FontSizing.zoom_factor,
          box.height / CLIPPED_MARKER_MAX_BOX_FRACTION))
      top = content_above ? Rect.new(box.x, box.y, box.width, thickness) : nil
      bottom = content_below ? Rect.new(box.x, box.y + box.height - thickness, box.width, thickness) : nil
      {top, bottom}
    end

    # Draw a line between two points
    def draw_line(from : Vec2, to : Vec2, color : Color, width : Float64 = 1.0)
      @primitives.not_nil! << DrawLine.new(from, to, color, width)
    end

    # Draw a circle (filled or outline)
    def draw_circle(center : Vec2, radius : Float64, color : Color, fill : Bool = true)
      @primitives.not_nil! << DrawCircle.new(center, radius, color, fill)
    end

    # Fill a triangle with 3 vertices
    def fill_triangle(p1 : Vec2, p2 : Vec2, p3 : Vec2, color : Color)
      @primitives.not_nil! << FillTriangle.new(p1, p2, p3, color)
    end

    # Draw a rectangle outline
    def draw_rect(bounds : Rect, color : Color, width : Float64 = 1.0)
      @primitives.not_nil! << DrawRect.new(bounds, color, width)
    end

    # Draw the REAL checkbox glyph (box outline + state mark) into the current
    # primitives block — the shared visual used by Checkbox, the MultiComboBox
    # gutter, and checkable menu items. Geometry only: the caller resolves colors
    # (including any focus highlight) and sizes. `rect` is the square box area;
    # `rect.width` is taken as the box size. Box = 4 edge fill_rects (always);
    # Checked = 2 lines + a junction circle; Indeterminate = 1 dash; Unchecked = box only.
    def draw_check_glyph(state : CheckState, rect : Rect, box_color : Color, check_color : Color,
                         line_thickness : Float64 = 2.0, junction_radius : Float64 = 1.0)
      box_x = rect.x
      box_y = rect.y
      box = rect.width

      # Box border as 4 filled rectangles (pixel-perfect, drawn inside bounds —
      # avoids SFML outline_thickness clipping).
      fill_rect(Rect.new(box_x, box_y, box, 1.0), box_color)             # Top
      fill_rect(Rect.new(box_x, box_y + box - 1.0, box, 1.0), box_color) # Bottom
      fill_rect(Rect.new(box_x, box_y, 1.0, box), box_color)             # Left
      fill_rect(Rect.new(box_x + box - 1.0, box_y, 1.0, box), box_color) # Right

      case state
      when CheckState::Checked
        cx = box_x + box / 2.0
        cy = box_y + box / 2.0
        cs = box * 0.7
        # Short down-left stroke into the junction, then long up-right stroke.
        p1 = Vec2.new(cx - cs * 0.35, cy - cs * 0.1)
        junction = Vec2.new(cx - cs * 0.1, cy + cs * 0.25)
        p4 = Vec2.new(cx + cs * 0.4, cy - cs * 0.4)
        draw_line(p1, junction, check_color, line_thickness)
        draw_line(junction, p4, check_color, line_thickness)
        draw_circle(junction, junction_radius, check_color, fill: true)
      when CheckState::Indeterminate
        pad = box * 0.2
        draw_line(Vec2.new(box_x + pad, box_y + box / 2.0),
          Vec2.new(box_x + box - pad, box_y + box / 2.0), check_color, line_thickness)
      when CheckState::Unchecked
        # Box only.
      end
    end

    # Nominal width of a cut-content marker band, before zoom and before the
    # narrow-box cap. It lives here rather than on a widget because all four text widgets
    # draw the same marker and none of them owns it.
    CLIPPED_MARKER_WIDTH = 3.0

    # Floor and cap for a marker bar, shared by both axes. Never thinner than one device pixel
    # or it vanishes exactly where the value is most cut; never more than this fraction of the
    # box it marks, or it swallows a narrow cell instead of annotating it.
    CLIPPED_MARKER_MIN_THICKNESS    = 1.0
    CLIPPED_MARKER_MAX_BOX_FRACTION = 3.0

    # Contrast floor the marker holds against the colour its widget paints. Deliberately above
    # the 3:1 WCAG non-text minimum: a host app may composite a wash OVER cell content from a
    # separate layer (embrace's cursor row/column and its change flash both do), which no
    # widget-local derivation can see, so the budget absorbs it instead of pretending it away.
    CLIPPED_MARKER_MIN_RATIO = 4.5

    # Where a widget's text is cut, and therefore where to say so: the left and right marker
    # bands for one line of text, or nil per edge when that edge cuts nothing.
    #
    # This is the SINGLE owner of both the predicate and the geometry. The bands are needed in
    # two places — the marker draws them, and a selection highlight must reserve their columns
    # so it cannot bury the hint — and a second derivation would be free to drift from the
    # first.
    #
    # `text_row` is the box ONE line of text may occupy, in widget-local coordinates, and it is
    # the same rect the caller clips that line to. That identity is the point: "is this cut?"
    # and "where do we cut it?" cannot disagree.
    #
    # The predicate is scroll-INDEPENDENT in the sense that matters. Marking "runs past the
    # right edge" would switch the hint OFF once a caret scrolled the start of a long value out
    # of view — precisely when content is still hidden. Per edge, `left` means content is
    # hidden before the view and `right` means content continues past it, so their union is
    # simply "the text is wider than its box" at every scroll position.
    # `band_box` is where the bar is DRAWN; `text_row` stays what the predicate is about. They
    # are the same rect by default, and every single-line caller leaves them so. A widget whose
    # text box is inset from its own edge (by padding, say) passes its inner rect as the band
    # box, so the bar sits on the CELL's edge rather than floating a few pixels inside it —
    # which is what makes the vertical and horizontal bars read as one cue. The predicate must
    # NOT follow: content is cut where the TEXT is cut, not where the bar is painted.
    def clipped_text_bands(text_row : Rect, offset : Float64, text_width : Float64,
                           band_box : Rect = text_row) : Tuple(Rect?, Rect?)
      return {nil, nil} if text_width <= 0.0

      # The width the text is CUT at — the predicate's business, and the text row's alone.
      cut_w = text_row.width.abs

      # A box can arrive with a NEGATIVE width: embrace's narrowest column leaves a cell
      # smaller than the widget's own chrome. Normalise so the edges keep their meaning —
      # that state hides everything, so it is the last one allowed to lose the marker.
      x = band_box.width < 0.0 ? Math.max(0.0, band_box.x + band_box.width) : band_box.x
      w = band_box.width.abs

      # Cap the band at a third of the box so it cannot swallow a narrow cell, but never below
      # 1px or the hint disappears exactly where content is most cut. Written with explicit
      # min/max rather than `clamp`: Crystal's clamp tests max FIRST, so a `clamp(floor, cap)`
      # here returns the sub-pixel cap and silently loses the floor.
      band_w = Math.max(CLIPPED_MARKER_MIN_THICKNESS,
        Math.min(CLIPPED_MARKER_WIDTH * FontSizing.zoom_factor,
          w / CLIPPED_MARKER_MAX_BOX_FRACTION))

      left = offset > 0.0 ? Rect.new(x, band_box.y, band_w, band_box.height) : nil
      right = (text_width - offset > cut_w) ? Rect.new(x + w - band_w, band_box.y, band_w, band_box.height) : nil
      {left, right}
    end

    # Draw the cut-content marker: a band along each edge that actually cuts. Emit this BEFORE
    # the clipped block that draws the line, so the band sits BEHIND the glyphs and can never
    # obscure the sliver it is reporting on — and so the caret, drawn inside that block, stays
    # visible on top of it.
    #
    # Takes the bands ALREADY computed by `clipped_text_bands` rather than deriving them again:
    # a widget that also has to reason about them (reserving their columns from a selection)
    # then has one set of rects, not two that are free to drift.
    #
    # `on` is the colour the widget actually PAINTS — never a theme token. Every text widget
    # here accepts a caller-supplied background and some paint a modified version of it (a
    # highlighted row), so a token-derived band can land on a backdrop that is never rendered.
    # It is passed as a colour rather than a derived one because deriving is not free (four
    # `pow` per call) and the overwhelming majority of cells fit and draw no band at all —
    # so the derivation happens here, after we know there is something to draw.
    # Takes any number of bands — a Tuple of two satisfies `Enumerable(Rect?)`, so the
    # single-line callers are unchanged, while a block can hand over one rect per line.
    def mark_clipped_text(bands : Enumerable(Rect?), on backdrop : Color)
      return unless bands.any? { |b| b }
      color = backdrop.contrasting_neutral(CLIPPED_MARKER_MIN_RATIO)
      bands.each { |b| fill_rect(b, color) if b }
    end

    # Push a clipping rectangle. PRIVATE: use `clipped`, whose ensure makes an unbalanced
    # emission unrepresentable — a guarantee only worth stating if the raw pair cannot be reached.
    private def push_clip(rect : Rect)
      @primitives.not_nil! << PushClip.new(rect)
    end

    # Pop the most recent clipping rectangle. PRIVATE — see push_clip.
    private def pop_clip
      @primitives.not_nil! << PopClip.new
    end

    # Emit a clipped block. Prefer this over raw push_clip/pop_clip at a widget call site:
    # the `ensure` makes an unbalanced EMISSION unrepresentable, so a future early return or
    # conditional branch inside the block cannot leak a clip into the rest of the list. That is a
    # real guarantee rather than a convention because push_clip/pop_clip are private.
    #
    # `rect` is widget-local, and the backend INTERSECTS it with whatever is already on the
    # clip stack (the cell clip on the tiled path, the widget clip on the texture path), so a
    # widget may narrow its own drawing without knowing what encloses it.
    #
    # `within` is the widget's own local bounds. When `rect` covers them the clip is a no-op
    # GIVEN the renderer's own widget-bounds clip (layer_renderer pushes one on all three paths)
    # — not by geometry, since a widget may well draw outside its bounds, which is the very case
    # this marker exists for. So it is not emitted at all: two primitives per render for nothing is a
    # real cost on the commonest widget in a tree (a Text at its default zero padding, where the
    # text box IS the bounds), and it is what the MultiComboBox primitive-count canary exists to
    # notice. The test is purely GEOMETRIC and never looks at the content, so the box the text is
    # measured against and the box it is cut at remain the same rect either way.
    #
    # Note what this does NOT contain: the execution-time push/pop in LayerRenderer has no
    # `ensure` of its own and runs against a backend retained across frames, so a raise there
    # would leak a clip for the life of that texture. That is a separate fix; this guarantees
    # only that the list we hand it is balanced.
    def clipped(rect : Rect, within : Rect, &block)
      return yield if rect.x <= within.x && rect.y <= within.y &&
                      rect.x + rect.width >= within.x + within.width &&
                      rect.y + rect.height >= within.y + within.height
      push_clip(rect)
      begin
        yield
      ensure
        pop_clip
      end
    end
  end
end
