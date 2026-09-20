module CrymbleUI
  # One tab's clickable header.
  #
  # A leaf widget that PULLS the owning Tabs' active index rather than keeping a copy of it,
  # exactly as TreeNodeHeader pulls its TreeNode's `expanded`: reading it in to_primitives
  # auto-captures the Source, so switching tabs re-renders every header with no push and no
  # layout of its own.
  class TabHeader < Widget
    include PrimitiveBuilder
    include FontScalable

    PADDING_X = 12.0
    PADDING_Y = 5.0
    # An inactive tab sits this much lower, so the active one reads as standing proud of it.
    INACTIVE_TOP_INSET = 3.0
    # The accent bar along the active tab's top edge.
    ACCENT_HEIGHT = 3.0
    BORDER = 1.0

    getter index : Int32

    # nil = follow Theme.current, resolved at draw time
    theme_property text_color, text_default

    def initialize(@text : String, @index : Int32, id : String? = nil, font_scale : Int32 = 0)
      @font_scale.set(font_scale)
      super(id: id)
    end

    def label : String?
      @text
    end

    # Headers sit in the strip, so the owner is the strip's parent.
    private def owner : Tabs?
      parent.try(&.parent).as?(Tabs)
    end

    def active? : Bool
      owner.try { |t| t.active == @index } || false
    end

    def measure(constraints : BoxConstraints) : Size
      text_size = measure_text(@text, font_size)
      # + the inset, so an inactive tab keeps its full text height while sitting lower.
      constraints.constrain(Size.new(
        text_size.width + PADDING_X * 2,
        text_size.height + PADDING_Y * 2 + INACTIVE_TOP_INSET
      ))
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, measure(constraints))
    end

    # Three signals, deliberately redundant, because one was not enough — the first version paired
    # a structurally correct idea (the active tab merges into its page) with the loudest colour in
    # the palette for the INACTIVE one, and the result read exactly backwards: a dark blue tab
    # with white text next to a plain grey one says "the blue one is selected", whatever the
    # geometry is doing.
    #
    #   1. the active tab carries the page's own background and is left OPEN along the bottom, so
    #      it is one surface with the page beneath it;
    #   2. an inactive tab is RECESSED — background darkened, sitting INACTIVE_TOP_INSET lower,
    #      closed off by the baseline;
    #   3. the active tab wears an accent bar along its top edge, which is the part you can see
    #      from across the room.
    #
    # Derived from panel_background rather than borrowing a chrome colour, so it stays coherent in
    # light and dark alike: title-bar colours are saturated by design, which is wrong here.
    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      is_active = active?
      top = is_active ? 0.0 : INACTIVE_TOP_INSET
      page = Theme.current.panel_background
      background = is_active ? page : page.darken(0.08)
      border = Theme.current.panel_border
      # width-1 / height-1, NOT width / height: a line at exactly bounds.width sits one pixel
      # OUTSIDE the widget and is clipped away. That is why every right and bottom edge was
      # missing from the strip while the left and top ones drew fine.
      bottom = bounds.height - 1
      right = bounds.width - 1

      primitives do
        fill_rect(Rect.new(0.0, top, bounds.width, bounds.height - top), background)
        if is_active
          fill_rect(Rect.new(0.0, 0.0, bounds.width, ACCENT_HEIGHT), Theme.current.panel_title_bar_active)
        end
        # Edges as thin FILLED RECTS, not lines. A 1px line is centred on its coordinate, so one
        # at x=0 covers x=-0.5..0.5 — half outside the widget, and clipped to nothing: that is
        # why the leftmost vertical was missing while its neighbours drew. A rect covers exactly
        # the pixels it names.
        fill_rect(Rect.new(0.0, top, bounds.width, BORDER), border)                       # top
        fill_rect(Rect.new(0.0, top, BORDER, bounds.height - top), border)                # left
        fill_rect(Rect.new(right, top, BORDER, bounds.height - top), border)              # right
        # No bottom edge while active: the gap is the join to the page.
        fill_rect(Rect.new(0.0, bottom, bounds.width, BORDER), border) unless is_active

        # Both labels read on their own background; panel_title_text is white, which was legible
        # on the old saturated fill and would be invisible on this one.
        label_color = is_active ? text_color : text_color.with_alpha(170)
        draw_text(@text, Vec2.new(PADDING_X, vcentered_text_y(bottom + top, font_scale)), label_color, font_scale)
      end
    end

    def on_click
      owner.try { |t| t.active = @index }
    end

    def focusable? : Bool
      true
    end

    def trigger_click
      on_click
    end
  end

  # A strip of tabs over a set of pages: one page is shown, the rest are BUILT BUT HIDDEN.
  #
  # "Hidden" means kept in the tree with zero bounds, the rule TreeNode already follows for
  # collapsed children — and here it is load-bearing beyond rendering. Shortcuts are registered
  # at BUILD time into the ShortcutManager, scoped to the panel, and dispatch resolves
  # panel -> shortcut -> handler without consulting visibility. Building pages lazily would
  # therefore silently disarm every shortcut the hidden page declared, and would hide its
  # widgets from `find` (and so from every headless test). Both are pinned by tabs_spec.
  #
  # `active` is a reconciling reactive property: embrace rebuilds its whole tree on all sorts of
  # events, and the tab the user is on must survive that.
  # The rest of the strip: the line the tabs stand on, continuing past the last one to the edge.
  # Without it the tabs read as a row of buttons; with it they read as tabs.
  class TabStripBaseline < Widget
    include PrimitiveBuilder

    # As tall as the tabs it continues. It has to ask them: the line is drawn at this widget's
    # OWN bottom edge, so a zero height would put it along the top of the strip and invert the
    # whole effect — the tabs would look as if they hung from a rail instead of standing on one.
    # (Measured: it really did come out 0 high until this asked.)
    def measure(constraints : BoxConstraints) : Size
      strip = parent.try(&.parent)
      height = strip.try(&.children.compact_map(&.as?(TabHeader)).map(&.measure(constraints).height).max?) || 0.0
      constraints.constrain(Size.new(0.0, height))
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, measure(constraints))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      primitives do
        # A rect, for the same reason the tab edges are rects: exact pixel coverage, and at
        # bounds.height it would fall outside the widget entirely.
        fill_rect(Rect.new(0.0, bounds.height - Tabs::BORDER, bounds.width, Tabs::BORDER), Theme.current.panel_border)
      end
    end
  end

  # The page under the strip, and the body the tabs stand on: the page background plus its left,
  # right and bottom edges. The TOP edge is deliberately absent here — it is the strip's baseline,
  # which is broken under the active tab, and that break is what joins tab to page. Without a
  # framed body there is nothing for the active tab to merge INTO, which is why the first version
  # had to lean entirely on colour.
  class TabPage < VStack
    # NO to_primitives, deliberately — a PURE container, the rule TreeNode states and explains:
    # a container that paints its own area over-paints the children a selective re-render did not
    # touch. The body boundary Wolfgang asked for has to come from something that is not the
    # children's own parent; drawing it here was tried and is not it.
  end

  # One edge of the body box: a leaf that fills ITSELF with the border colour, one pixel thick.
  #
  # Thin on purpose, and it is the whole design. Anything that COVERS the body — the page itself,
  # a parent, or a sibling laid over it — blits its full area over any child a selective
  # re-render did not touch, and the toolbar disappears for the length of a resize drag. Measured
  # three times: with a custom to_primitives, with VStack's own supported `background_color`, and
  # with a transparent full-area overlay. An edge covers only the pixels it means to paint, so
  # there is nothing left to over-paint.
  class TabEdge < Widget
    include PrimitiveBuilder

    def measure(constraints : BoxConstraints) : Size
      constraints.constrain(Size.new(constraints.max_width, constraints.max_height))
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      @bounds = Rect.new(position, measure(constraints))
    end

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      primitives do
        fill_rect(Rect.new(0.0, 0.0, bounds.width, bounds.height), Theme.current.panel_border)
      end
    end
  end

  class Tabs < Widget
    # Tabs touch: their own side borders divide them, the way a row of tabs actually looks.
    STRIP_SPACING = 0.0
    BORDER = 1.0

    # Which page is shown. `layout` because swapping pages changes what occupies the box, and
    # `reconcile` because embrace rebuilds its whole tree on all sorts of events and the tab the
    # user is on must survive that (the same reason TreeNode#expanded reconciles).
    reactive_property active : Int32 = 0, layout: true, reconcile: true

    getter strip : HStack
    @baseline : Expanded
    @edges : Tuple(TabEdge, TabEdge, TabEdge)

    def initialize(id : String? = nil, active : Int32 = 0)
      @active = Source(Int32).new(active)
      @_build_active = active
      @strip = HStack.new(spacing: STRIP_SPACING, padding: 0.0)
      # Takes whatever width the tabs leave. Kept LAST by add_tab, so the baseline always runs
      # from the last tab to the edge. Both built BEFORE super, which is where `self` first
      # escapes.
      @baseline = Expanded.new
      @baseline.add_child(TabStripBaseline.new)
      @strip.add_child(@baseline)
      @edges = {TabEdge.new, TabEdge.new, TabEdge.new} # left, right, bottom
      super(id: id)
      add_child(@strip)
      # LAST among the children, so they draw after the page they outline. add_tab keeps them there.
      @edges.each { |e| add_child(e) }
    end

    # The pages, in tab order — every child that is neither the strip nor the body frame.
    def pages : Array(Widget)
      @children.select { |c| !c.same?(@strip) && !@edges.any? { |e| e.same?(c) } }
    end

    def add_tab(text : String, page : Widget) : Nil
      index = pages.size
      # The filler has to stay last, and there is no insert — so lift it, append the tab, put it
      # back. Done HERE rather than in a "seal the strip" call the caller must remember: an
      # invariant a caller can forget is not an invariant.
      @strip.remove_child(@baseline)
      @strip.add_child(TabHeader.new(text, index, id: id ? "#{id}_tab_#{index}" : nil))
      @strip.add_child(@baseline)
      # Page before the edges, so they still draw last.
      @edges.each { |e| remove_child(e) }
      add_child(page)
      @edges.each { |e| add_child(e) }
    end

    private def active_page : Widget?
      pages[active]?
    end

    def measure(constraints : BoxConstraints) : Size
      strip_size = @strip.measure(BoxConstraints.loose(Size.new(constraints.max_width, constraints.max_height)))
      page_constraints = BoxConstraints.loose(Size.new(
        constraints.max_width,
        Math.max(0.0, constraints.max_height - strip_size.height)
      ))
      page_size = active_page.try(&.measure(page_constraints)) || Size.new(0.0, 0.0)
      # Take the WHOLE width when there is a box to fill, the way a tab container should: the
      # strip is a rail the pages hang under, and a rail that stops after the last tab reads as a
      # row of buttons. Falls back to the natural width only when the width is unbounded.
      natural_width = Math.max(strip_size.width, page_size.width)
      width = constraints.max_width.finite? ? Math.max(constraints.max_width, natural_width) : natural_width
      constraints.constrain(Size.new(width, strip_size.height + page_size.height))
    end

    def min_intrinsic_height(width : Float64) : Float64
      sh = @strip.measure(BoxConstraints.loose(Size.new(width, Float64::MAX))).height
      sh + (active_page.try(&.min_intrinsic_height(width)) || 0.0)
    end

    def min_intrinsic_width(height : Float64) : Float64
      Math.max(
        @strip.measure(BoxConstraints.loose(Size.new(Float64::MAX, height))).width,
        active_page.try(&.min_intrinsic_width(height)) || 0.0
      )
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)

      # Width TIGHT, not loose: the strip must span the whole box so its trailing Expanded has
      # room to carry the baseline past the last tab. Laid out loosely it shrank to the tabs and
      # the filler came out zero wide — measured, and the baseline example holds it.
      @strip.layout(
        BoxConstraints.new(min_width: size.width, max_width: size.width, min_height: 0.0, max_height: size.height),
        Vec2.new(0.0, 0.0)
      )
      sh = @strip.bounds.height

      shown = active_page
      body_height = Math.max(0.0, size.height - sh)
      # The page is INSET by the border on its left, right and bottom, so the edges sit BESIDE it
      # rather than over it. Siblings may not overlap — the renderer asserts it
      # (layer_renderer "siblings no-overlap") and a violation degrades the frame — which is what
      # laying the edges across the page did, and what the stray grey boxes in the field list
      # came from.
      inner_x = BORDER
      inner_w = Math.max(0.0, size.width - BORDER * 2)
      inner_h = Math.max(0.0, body_height - BORDER)
      pages.each do |page|
        if page.same?(shown)
          # TIGHT, not loose. The page IS the body: it has to fill the box under the strip.
          # Laid out loosely it shrank to its content — a 52px page in a 380px panel — and three
          # separate artifacts followed: the body frame was drawn around that small box instead
          # of the body, a ScrollView inside got bounds that disagreed with what was painted (ink
          # left behind while scrolling), and widgets were squeezed out mid-resize only to
          # reappear when it settled.
          page.layout(
            BoxConstraints.new(
              min_width: inner_w, max_width: inner_w,
              min_height: inner_h, max_height: inner_h
            ),
            Vec2.new(inner_x, sh)
          )
        else
          # Same rule as a collapsed TreeNode: still in the tree, occupying nothing, so it
          # cannot paint at the coordinates it held while it was forward.
          page.zero_bounds!
        end
      end
      # The body box: left and right down its sides, one along the bottom. The TOP edge is the
      # strip's baseline, broken under the active tab — that break is the join.
      left, right, bottom = @edges
      left.layout(BoxConstraints.tight(Size.new(BORDER, body_height)), Vec2.new(0.0, sh))
      right.layout(BoxConstraints.tight(Size.new(BORDER, body_height)), Vec2.new(size.width - BORDER, sh))
      # Between the two verticals, not across them.
      bottom.layout(BoxConstraints.tight(Size.new(inner_w, BORDER)), Vec2.new(inner_x, sh + body_height - BORDER))
    end
  end
end
