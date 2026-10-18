require "./types"
require "./cached"
require "./assert" # widget.cr uses the assert() macro (auto_copy_reconcile_properties)
require "./scheduler"
require "./cache_policy"
require "./font"
require "./clipboard"
require "../rendering/draw_primitive"
require "../input/shortcut_manager"
require "../input/focus_manager"

module CrymbleUI
    enum MouseButton
        Left
        Right
        Middle
    end

    # Annotation for properties that should be automatically copied during reconciliation
    # Emitted by reactive_property(reconcile: true) and reconcile_property
    # The auto_copy_reconcile_properties method iterates all @[Reconcile] annotated vars
    annotation Reconcile
    end

    # Annotation for properties explicitly excluded from reconciliation.
    # Used with -Daudit_reconcile to ensure every ivar is classified.
    annotation NoReconcile
    end

    # Explicit focus navigation overrides
    # Allows overriding automatic spatial navigation for specific directions
    struct FocusOverride
        property up : String?     # Widget ID for Up arrow navigation
        property down : String?   # Widget ID for Down arrow navigation
        property left : String?   # Widget ID for Left arrow navigation
        property right : String?  # Widget ID for Right arrow navigation

        def initialize(
            @up : String? = nil,
            @down : String? = nil,
            @left : String? = nil,
            @right : String? = nil
        )
        end
    end

    # Widget invalidation state
    # Clean: no changes needed
    # NeedsRender: visual changes only (animations, colors) - selective render
    # NeedsLayout: structural changes (size, position, children) - full layout + render
    enum WidgetState
        Clean
        NeedsRender
        NeedsLayout
    end

    # Abstract base class for all widgets
    abstract class Widget
        # Global scheduler for all widgets
        @@scheduler : Scheduler?

        # Global shortcut manager for all widgets
        @@shortcut_manager : ShortcutManager?

        # Global focus manager for keyboard focus
        @@focus_manager : FocusManager?

        # Global app reference for triggering rebuilds
        @@app : App?

        # Global font for text measurement (set by renderer)
        @@font : Font?

        # Global clipboard (set by renderer; in-memory stub in specs)
        @@clipboard : Clipboard?

        # Render count instrumentation (for testing optimization)
        @@render_count : Int32 = 0
        @@cache_render_count : Int32 = 0

        # Layout count instrumentation (for testing optimization)
        @@layout_count : Int32 = 0

        # Measure count instrumentation (for testing VStack/HStack optimization)
        @@measure_count : Int32 = 0

        # absolute_bounds invocation instrumentation. absolute_bounds is UNCACHED and O(depth) (it
        # re-walks the parent chain on every call), so calling it once per widget over a whole subtree
        # is O(content·depth) — the shape of the resize regression a per-frame grow walk re-introduced
        # (the repaint marking walk). This counter guards the grow path against re-introducing an
        # O(content) absolute_bounds storm: a pure grow must call it O(1) in content size, not O(n).
        # It counts parent-chain STEPS, one per level, in every geometry walk - absolute_bounds (a call
        # per level), viewport_bounds, enclosing_scroll, ancestor_clip - so walks compare by what they cost.
        @@absolute_bounds_count : Int32 = 0

        # mark_needs_render PROPAGATION instrumentation. Each call walks the parent chain to a
        # layer + does a set-insert (propagate_to_layer) — the "method calls, set operations, layer
        # traversals" overhead that regressed live resize historically (be1ffa9) and is INVISIBLE to
        # primitive_count (a mark-storm over culled widgets renders nothing). This counter guards
        # the live-resize policy against re-introducing that propagation wall.
        @@mark_render_count : Int32 = 0

        # HOT-PATH instrumentation (perf audit). Bump via the explicit `Widget.` class qualifier
        # so a bare @@ from an instance method doesn't scatter into each subclass's own copy (see
        # increment_absolute_bounds_count).
        #
        # panel_walk_visits/popup_walk_visits: bumped once per REGISTRY ENTRY checked by
        # WindowPanel.all_in_tree/Popup.all_in_tree (window_panel.cr/popup.cr) — O(#panels)/O(#popups),
        # content-independent. Formerly bumped once per NODE VISITED by an O(total-widget) tree walk
        # (collect_panels_recursive/collect_popups_recursive, deleted); this counter guards against
        # that O(content) walk creeping back onto the per-frame path.
        @@panel_walk_visits : Int32 = 0
        @@popup_walk_visits : Int32 = 0
        # state_sweep_visits: STILL an O(total-widget) tree walk (clear_render_state_recursive, per
        # non-layout frame) — unscoped, unlike the two above. Guards against it regressing further,
        # not a claim it's already O(1). Scoping it is a separate, not-yet-started effort.
        @@state_sweep_visits : Int32 = 0

        # Text-measurement cache (text+size → visual Size). measure_text is a layout HOT PATH: every
        # Button/Text re-measures each layout pass, so a live panel resize fired hundreds of SFML
        # font queries per frame (~40ms, the resize-CPU cost). The result is deterministic per font,
        # so cache it; cleared on font change (font=). Bounded to cap growth from dynamic text.
        @@measure_text_cache = Hash(Tuple(String, Float64), Size).new

        # Control warnings for conflicts (duplicate IDs, duplicate shortcuts, etc.)
        # Can be disabled for tests
        @@enable_warnings : Bool = true

        # bind: STABILITY GUARD — count of fresh-Source-per-build warnings (see note_bind_reconcile).
        # Diagnostic + testable; independent of @@enable_warnings so a spec can assert it silently.
        @@bind_stability_warnings : Int32 = 0

        # SIBLING NO-OVERLAP GUARD state — see self.sibling_overlap_warnings. Counts overlaps the
        # -Dverify_bounds re-layout check reported; always 0 without that flag.
        @@sibling_overlap_warnings : Int32 = 0

        # Set the global scheduler (called by renderer)
        def self.scheduler=(scheduler : Scheduler)
            @@scheduler = scheduler
        end

        # Get the global scheduler
        def self.scheduler : Scheduler
            @@scheduler || raise "Scheduler not initialized"
        end

        # Get the global scheduler if set (nil before the renderer installs it — e.g. early build /
        # tests). Lets callers branch on presence instead of catching the raise above with a blanket
        # rescue (which would also swallow a real error from the scheduler itself).
        def self.scheduler? : Scheduler?
            @@scheduler
        end

        # Set the global shortcut manager (called by renderer)
        def self.shortcut_manager=(manager : ShortcutManager)
            @@shortcut_manager = manager
        end

        # Get the global shortcut manager
        def self.shortcut_manager : ShortcutManager
            @@shortcut_manager || raise "ShortcutManager not initialized"
        end

        # Get the global shortcut manager if set (nil before the renderer installs it). Lets callers
        # branch on presence rather than catch the raise with a blanket rescue.
        def self.shortcut_manager? : ShortcutManager?
            @@shortcut_manager
        end

        # Set the global focus manager (called by renderer)
        def self.focus_manager=(manager : FocusManager)
            @@focus_manager = manager
        end

        # Get the global focus manager
        def self.focus_manager : FocusManager
            @@focus_manager || raise "FocusManager not initialized"
        end

        # Get the global focus manager (optional - may not be set in tests)
        def self.focus_manager? : FocusManager?
            @@focus_manager
        end

        # Set the global app (called by renderer)
        def self.app=(app : App)
            @@app = app
        end

        # Get the global app
        def self.app? : App?
            @@app
        end

        # Set the global font (called by renderer). Nilable, so a caller that installs a font
        # temporarily can put back what it found. The getter has always been `Font?`; with a
        # non-nil-only setter "restore the previous value" was inexpressible, so a spec that
        # swapped the font in could only leak it into every later file sharing the binary.
        def self.font=(font : Font?)
            @@font = font
            @@measure_text_cache.clear # font changed → cached measurements are invalid
        end

        # Get the global font
        def self.font : Font?
            @@font
        end

        # Set the global clipboard (called by renderer)
        def self.clipboard=(clipboard : Clipboard)
            @@clipboard = clipboard
        end

        # Get the global clipboard
        def self.clipboard : Clipboard
            @@clipboard || raise "Clipboard not initialized"
        end

        # Get the global clipboard, or nil when nothing has installed one yet.
        # Present for the same reason as scheduler?/shortcut_manager?: a caller that
        # legitimately runs before a renderer or suite installed one should branch on
        # presence, not wrap the raise above in a blanket rescue.
        def self.clipboard? : Clipboard?
            @@clipboard
        end

        # Enable/disable warnings (duplicate IDs, shortcut conflicts, etc.)
        # Useful for tests
        def self.enable_warnings=(value : Bool)
            @@enable_warnings = value
        end

        # Get current enable_warnings setting
        def self.enable_warnings : Bool
            @@enable_warnings
        end

        # bind: STABILITY GUARD diagnostic — total fresh-Source-per-build warnings this session.
        def self.bind_stability_warnings : Int32
            @@bind_stability_warnings
        end

        def self.reset_bind_stability_warnings : Nil
            @@bind_stability_warnings = 0
        end

        # Increment via an explicit Widget. reference (not a bare @@ from a subclass instance method,
        # which would hit the subclass's shadowed copy — the same trap App.class_var_increment_rebuild_count avoids).
        def self.increment_bind_stability_warnings : Nil
            @@bind_stability_warnings += 1
        end

        # SIBLING NO-OVERLAP diagnostic — overlaps found by the -Dverify_bounds re-layout check
        # (layer_renderer's warn_sibling_overlaps). Zero in an un-flagged build; a spec asserts zero
        # without having to scrape STDERR.
        def self.sibling_overlap_warnings : Int32
            @@sibling_overlap_warnings
        end

        def self.reset_sibling_overlap_warnings : Nil
            @@sibling_overlap_warnings = 0
        end

        def self.increment_sibling_overlap_warnings : Nil
            @@sibling_overlap_warnings += 1
        end

        # CONTAINMENT diagnostic - children found outside their parent by the -Dverify_bounds check in
        # Widget#layout. Zero in an un-flagged build; a spec asserts zero without scraping STDERR.
        @@containment_warnings : Int32 = 0

        def self.containment_warnings : Int32
            @@containment_warnings
        end

        def self.reset_containment_warnings : Nil
            @@containment_warnings = 0
        end

        # Through a class method, as the other counters: a class variable written from an instance method of a
        # SUBCLASS is that subclass's own copy.
        def self.increment_containment_warnings : Nil
            @@containment_warnings += 1
        end

        # Measure text dimensions using global font
        # This is a pure geometry query - no rendering required
        # Can be called during measure() phase
        # Returns the visual size of the text (width/height only, no offsets)
        # Use with draw_text() which automatically compensates for SFML local_bounds offsets
        # How many distinct strings a per-string memo may retain before it is dropped
        # wholesale. Dynamic text (cell values, labels a user types) has no natural bound, so
        # an unbounded memo grows for the life of the process; a full clear rather than an LRU.
        # It must still hold a WHOLE TABLE: auto-size measures every cell, not only the ones on
        # screen, and a table larger than the limit clears the memo in the middle of every pass,
        # so each re-measure measured every cell again - measured on 3000 rows x 11 columns
        # (~33,000 strings), a re-measure took 455 ms at 20,000 and 85 ms at this limit.
        # Shared by every memo keyed on a string — see CrymbleUI::TextLines.
        TEXT_MEMO_LIMIT = 200_000

        def self.measure_text(text : String, size : Float64) : Size
            return Size.new(0.0, 0.0) unless font = @@font

            key = {text, size}
            if cached = @@measure_text_cache[key]?
                return cached
            end
            # Delegate to Font implementation (SFML or headless)
            result = font.measure_text(text, size)
            @@measure_text_cache.clear if @@measure_text_cache.size > TEXT_MEMO_LIMIT
            @@measure_text_cache[key] = result
            result
        end

        # Instance method for convenience
        def measure_text(text : String, size : Float64) : Size
            Widget.measure_text(text, size)
        end

        # Render count instrumentation API (for testing)
        def self.render_count : Int32
            @@render_count
        end

        def self.cache_render_count : Int32
            @@cache_render_count
        end

        def self.reset_render_counts
            @@render_count = 0
            @@cache_render_count = 0
        end

        # Get layout count for testing
        def self.layout_count : Int32
            @@layout_count
        end

        # Reset layout count for testing
        def self.reset_layout_count
            @@layout_count = 0
        end

        # Increment layout count for instrumentation
        def self.increment_layout_count
            @@layout_count += 1
        end

        # Get measure count for testing
        def self.measure_count : Int32
            @@measure_count
        end

        # Reset measure count for testing
        def self.reset_measure_count
            @@measure_count = 0
        end

        # Increment measure count for instrumentation
        def self.increment_measure_count
            @@measure_count += 1
        end

        # Parent-chain steps counted so far (see @@absolute_bounds_count)
        def self.absolute_bounds_count : Int32
            @@absolute_bounds_count
        end

        # Reset absolute_bounds invocation count for testing
        def self.reset_absolute_bounds_count
            @@absolute_bounds_count = 0
        end

        # Increment absolute_bounds count for instrumentation. Called via the explicit `Widget.` class
        # qualifier (NOT a bare `@@` from the instance method): a bare class-var write from an instance
        # method targets the RUNTIME subclass's own copy (Crystal gives each subclass a separate copy),
        # so the counts would scatter across Button/VStack/… and Widget's would stay 0. Same idiom as
        # increment_measure_count.
        def self.increment_absolute_bounds_count
            @@absolute_bounds_count += 1
        end

        def self.mark_render_count : Int32
            @@mark_render_count
        end

        def self.reset_mark_render_count
            @@mark_render_count = 0
        end

        # --- HOT-PATH TREE-WALK counters (perf audit) --------------------------------------------
        # Same subclass-copy caveat as increment_absolute_bounds_count: always bump via `Widget.`.
        def self.panel_walk_visits : Int32
            @@panel_walk_visits
        end

        def self.reset_panel_walk_visits
            @@panel_walk_visits = 0
        end

        def self.increment_panel_walk_visits
            @@panel_walk_visits += 1
        end

        def self.popup_walk_visits : Int32
            @@popup_walk_visits
        end

        def self.reset_popup_walk_visits
            @@popup_walk_visits = 0
        end

        def self.increment_popup_walk_visits
            @@popup_walk_visits += 1
        end

        def self.state_sweep_visits : Int32
            @@state_sweep_visits
        end

        def self.reset_state_sweep_visits
            @@state_sweep_visits = 0
        end

        def self.increment_state_sweep_visits
            @@state_sweep_visits += 1
        end

        def self.increment_render_count
            @@render_count += 1
        end

        def self.increment_cache_render_count
            @@cache_render_count += 1
        end

        # Explicit ID for reconciliation
        # When nil, widgets are matched by position during rebuild (works if structure is stable)
        # Provide explicit IDs for dynamic lists or conditional widgets
        property id : String?

        # Generic user data - can store custom string attributes
        # Useful for attaching metadata (e.g., hover text, tooltips, shortcuts)
        # User can also subclass widgets and add typed properties instead
        property user_data : Hash(Symbol, String) = {} of Symbol => String

        # Parent widget (nil for root)
        property parent : Widget?

        # Children widgets
        getter children : Array(Widget)

        # Whether build() has been called (for auto-build on add_child)
        getter? built : Bool = false

        # Mark widget as built (called by add_child before triggering build)
        protected def mark_built
            @built = true
        end

        # Widget bounds after layout (parent-relative coordinates)
        property bounds : Rect

        # Layer ownership (overridden by widgets with their own layers: Window, WindowPanel, MenuBar, Popup, LayerBox)
        # Most widgets don't have their own layer - they render into parent's layer
        def layer : Layer?
            nil
        end

        # Calculate absolute window coordinates from parent-relative bounds
        # Traverses parent chain to convert relative position to absolute
        # WHERE THIS WIDGET PLACES ITS INK, in its own local frame (origin = its box).
        #
        # `pos`/`size` are the REGION the content names — its line, or a whole span for a compound
        # header, which is NOT the same as the box once that box has been pinned. `band_lo`/
        # `band_hi` are the part of the world on screen. nil is not "no adjustment": it means "my
        # region IS my box, and nothing can move it" - all of it visible, or no taller than one line
        # (`hold`) - so a widget that loses this silently starts placing against a different region.
        # A compound must never be without one. `hold` is one default line's box: the part of the
        # region the band never takes (PrimitiveBuilder#centred_in).
        #
        # `compound` says the region is a GROUP of lines rather than one. THE PLACEMENT RULE DOES
        # NOT READ IT — `centred_in` treats every region identically, and stopped taking the flag
        # at all on 2026-09-11. What reads it is the carrier gate (VirtualMatrix#ink_region_for): a
        # one-line region withdraws when nothing can move it, because the widget's own answer is
        # then the rule's answer, while a compound must keep its region wherever it sits,
        # since its span is not its box and losing it would switch the label to being placed
        # against the box (measured as a 6px jump for 1px of scroll).
        #
        # Set by a scrolling container's per-frame pass; see VirtualMatrix#update_ink_regions.
        # It carried the widget's own height as `box` until 2026-09-11, for two consumers that both
        # went: the rule's own box clamp (redundant with PrimitiveBuilder#confine, which uses the
        # CURRENT box rather than this copy) and the geometric guess at `pinned`, now told.
        # `pinned` is a FACT the matrix knows, not something to infer from these numbers: the
        # cell's box is positioned and CLIPPED by StickyMath.compound_axis (a compound on a sticky
        # column, outside the sticky rows — see sticky_reposition.cr), so the box is held still
        # while the span scrolls and says nothing about where the group is. The rule read it off
        # the geometry until 2026-09-11 (`region reaches outside box`), which is the same answer
        # only by luck: a pinned box whose span happens to fit reads as unpinned.
        record InkRegion, pos : Float64, size : Float64, band_lo : Float64, band_hi : Float64,
          hold : Float64, compound : Bool = false, pinned : Bool = false

        property ink_region : InkRegion? = nil

        def absolute_bounds : Rect
            Widget.increment_absolute_bounds_count
            if parent = @parent
                parent_abs = parent.absolute_bounds
                Rect.new(
                    @bounds.x + parent_abs.x,
                    @bounds.y + parent_abs.y,
                    @bounds.width,
                    @bounds.height
                )
            else
                # Root widget has no parent - bounds are already absolute
                @bounds
            end
        end

        # Where this widget is PAINTED, in window coordinates.
        #
        # `absolute_bounds` sums the parent chain, which is CONTENT space: a widget whose parent
        # scrolls keeps its laid-out position and the pixels move instead (a ScrollView composites
        # its layer shifted; a VirtualMatrix paints its cells shifted). Anything that meets the
        # CURSOR - the drag ghost, the drop highlight, a popup anchored under a control - lives in
        # window space and must convert, or it is displaced by exactly the scroll amount. Mouse
        # handlers get the opposite conversion, done once in App (`to_content`).
        #
        # ONE walk, like `absolute_bounds`: sum the chain and subtract what each parent shifts its
        # child by, so this costs the same as the position it corrects. A parent that SCALES its child
        # (scale_for - a fitted) maps the rect accumulated so far about that child's origin: below a scale,
        # absolute_bounds is in a pre-scale space no ancestor understands, and this is the way out.
        def viewport_bounds : Rect
            Widget.increment_absolute_bounds_count # one per step of the walk, as absolute_bounds counts
            x = @bounds.x
            y = @bounds.y
            w = @bounds.width
            h = @bounds.height
            shifting = !Layer.overlay?(self) # nothing above an overlay shifts it (it places itself in window space)
            node : Widget = self
            current = @parent
            while current
                Widget.increment_absolute_bounds_count
                if shifting && (f = current.scale_for(node)) != 1.0
                    # x, y are relative to `current` here; node.bounds is the scaled child's place in it
                    p = Widget.scale_about(Vec2.new(x, y), node.bounds.position, f)
                    x = p.x
                    y = p.y
                    w *= f
                    h *= f
                end
                x += current.bounds.x
                y += current.bounds.y
                if shifting
                    shift = current.paint_shift_for(node)
                    x -= shift.x
                    y -= shift.y
                    shifting = !Layer.overlay?(current)
                end
                node = current
                current = current.parent
            end
            Rect.new(x, y, w, h)
        end

        # Does this widget rank the layer owners painted into its layers (composite_rank)? Most do not, and the
        # hit test takes its fast path over their children.
        def ranks_children? : Bool
            false
        end

        # Where `owner`, painted into one of this widget's layers, composites among the others painted there:
        # a higher rank comes later (on top). Asked only when ranks_children?.
        def composite_rank(owner : Widget) : Int32
            0
        end

        # The layer this widget is PAINTED into: its own render_layer if it has one (a sticky header cell is
        # painted into the sticky band), else the nearest ancestor's layer, or its render_layer. What the
        # composite order nests this widget's own layers under, and what a drop highlight over it follows.
        def painting_layer : Layer?
            if own = render_layer
                return own
            end
            node = @parent
            while node
                if l = node.layer || node.render_layer
                    return l
                end
                node = node.parent
            end
            nil
        end

        # The part of this widget the compositor SHOWS, in window coordinates, or nil when none of it shows: its
        # viewport_bounds cut by ancestor_clip.
        def visible_bounds : Rect?
            rect = viewport_bounds
            if clip = ancestor_clip
                rect = rect.intersection(clip) || return nil
            end
            rect
        end

        # The window rect `child` is shown within, or nil for no limit. Per CHILD, like paint_shift_for, because
        # one widget clips one child and not another: a ScrollView clips its content, not its own scrollbars. By
        # default a layer owner clips what it contains to its layer.
        def clip_for(child : Widget) : Rect?
            layer.try(&.bounds)
        end

        # Where this widget can show at all, in window space: the intersection of every ancestor's clip_for along
        # the chain, up to the first overlay (a popup is clipped by nothing above it) - or nil for no limit. A
        # clip that excludes everything is an EMPTY rect, never nil. What the compositor clips a layer to (its
        # owner's ancestor_clip) and what visible_bounds cuts by. `memo` shares the walk between the widgets of one
        # phase (a frame's occlusion, its composite): each widget's clip is computed once.
        def ancestor_clip(memo : Hash(Widget, Rect?)? = nil) : Rect?
            return nil if Layer.overlay?(self)
            parent = @parent || return nil
            if m = memo
                return m[self] if m.has_key?(self)
            end
            Widget.increment_absolute_bounds_count
            clip = Widget.intersect_clips(parent.ancestor_clip(memo), parent.clip_for(self))
            memo.try { |m| m[self] = clip }
            clip
        end

        # nil is no limit; an empty intersection is an empty rect (at the first rect's corner), not nil.
        def self.intersect_clips(a : Rect?, b : Rect?) : Rect?
            return b unless a
            return a unless b
            a.intersection(b) || Rect.new(a.x, a.y, 0.0, 0.0)
        end

        # How much THIS widget shifts the given child when painting it. A widget that scrolls its
        # children keeps their laid-out bounds and moves the pixels instead, so a child's painted
        # position is its laid-out position minus this. Default: nothing moves.
        #
        # Per-CHILD, not per-widget, because the same parent shifts one child and not another: a
        # ScrollView's scrollbars stay put while its content scrolls, and a matrix's sticky cells
        # are moved by the matrix itself (their bounds hold the scroll). Only the shifting widget
        # knows which is which.
        def paint_shift_for(child : Widget) : Vec2
            Vec2.zero
        end

        # How much THIS widget SCALES the given child when painting it: the child's subtree is drawn
        # uniformly scaled by this factor about the child's own content origin (a fitted). Default 1.0.
        # Declared per child, like paint_shift_for and clip_for - the only declaration of a scale; the walks
        # below (viewport_bounds, to_window, to_content) apply it without naming a class.
        def scale_for(child : Widget) : Float64
            1.0
        end

        # A point p, scaled by f about c: where p is painted when what holds it is drawn at f about c.
        def self.scale_about(p : Vec2, c : Vec2, f : Float64) : Vec2
            Vec2.new(c.x + (p.x - c.x) * f, c.y + (p.y - c.y) * f)
        end

        # The inverse of scale_about. At f == 0 a collapsed image maps every point to its origin: no NaN or
        # infinity reaches a handler (a captured drag while the window collapses).
        def self.unscale_about(p : Vec2, c : Vec2, f : Float64) : Vec2
            return c if f == 0.0
            Vec2.new(c.x + (p.x - c.x) / f, c.y + (p.y - c.y) / f)
        end

        # The ADDITIVE part of the crossing between this widget's space and the window's: the sum of
        # `paint_shift_for` along the parent chain, up to the first overlay (a popup places itself in window
        # space: nothing above it shifts it). A layer's window position is its content rect minus it.
        #
        # Below a SCALE (scale_for != 1) no additive shift describes the crossing, so this must never be asked
        # there: it asserts so. That is the backstop behind a fitted's refusal of a layer owner inside it - such
        # an owner's Layer#bounds asks this and fails loud instead of compositing silently in the wrong place.
        # Points cross with to_window / to_content, rects with viewport_bounds: those scale.
        def enclosing_scroll : Vec2
            x = 0.0
            y = 0.0
            node : Widget = self
            current = @parent
            while current && !Layer.overlay?(node)
                Widget.increment_absolute_bounds_count
                assert(current.scale_for(node) == 1.0,
                    "enclosing_scroll asked of #{path_id}, below the scale of #{current.class.name.split("::").last}" \
                    "##{current.path_id}: a scaled space has no additive shift (cross with to_window / to_content)")
                shift = current.paint_shift_for(node)
                x += shift.x
                y += shift.y
                node = current
                current = current.parent
            end
            Vec2.new(x, y)
        end

        # A point of MINE, placed on the window. Use it for anything that leaves the widget tree:
        # an overlay, a menu position, a ghost - they are drawn by the window, not by the scroller.
        # Innermost step first: each parent scales its child about the child's origin (scale_for), then
        # shifts it (paint_shift_for).
        def to_window(point : Vec2) : Vec2
            x = point.x
            y = point.y
            node : Widget = self
            current = @parent
            while current && !Layer.overlay?(node)
                Widget.increment_absolute_bounds_count
                if (f = current.scale_for(node)) != 1.0
                    p = Widget.scale_about(Vec2.new(x, y), node.absolute_bounds.position, f)
                    x = p.x
                    y = p.y
                end
                shift = current.paint_shift_for(node)
                x -= shift.x
                y -= shift.y
                node = current
                current = current.parent
            end
            Vec2.new(x, y)
        end

        # A window point, brought into MY space - the space `bounds` and `absolute_bounds` live in.
        # This is what a widget's mouse handlers are given, so `point - absolute_bounds` is correct
        # without anyone having to think about scrolling or scaling. The inverse of to_window: the
        # outermost step first, each undone (the shift added back, then the scale undone).
        def to_content(point : Vec2) : Vec2
            parent = @parent
            return point if parent.nil? || Layer.overlay?(self)
            Widget.increment_absolute_bounds_count
            q = parent.to_content(point)
            shift = parent.paint_shift_for(self)
            q = Vec2.new(q.x + shift.x, q.y + shift.y)
            if (f = parent.scale_for(self)) != 1.0
                q = Widget.unscale_about(q, absolute_bounds.position, f)
            end
            q
        end

        # The render pass in which this widget's pixels were last put INTO its layer's buffer —
        # painted fresh, blitted from its texture, or verified still fresh by the per-slot skip.
        # Compared against `LayerRenderer.pass_id` by `LayerRenderer.pass_covered?`, so a widget
        # that never reached a paint point (culled, dropped, returned early) is distinguishable
        # from one that did, in O(1) and with no per-frame allocation. See invariant (h2).
        property last_covered_pass : UInt64 = 0

        # Widget invalidation state (Clean, NeedsRender, NeedsLayout)
        property state : WidgetState

        # Explicit layer override for propagate_to_layer (set by VirtualMatrix for sticky cells)
        property render_layer : Layer?

        # Cached ancestry bounds validity (nil = uncached).
        # Valid when this widget and all ancestors have positive bounds.
        # Cleared on mark_needs_layout (upward propagation clears entire chain).
        @ancestry_bounds_valid : Bool? = nil

        # Enabled state - disabled widgets render but don't respond to clicks
        @enabled : Bool = true

        def enabled? : Bool
          @enabled
        end

        def enabled=(value : Bool)
          return if @enabled == value
          @enabled = value
          mark_needs_render
        end

        # Children can be positioned outside parent bounds (for Popup, etc.)
        # When true, hit_test will check children even if point is outside parent bounds
        property children_escape_bounds : Bool

        # Focus highlight state (for flashing animation when widget has keyboard focus)
        # Managed by FocusFlashController for the widget holding the keyboard (only one that paints the flash:
        # paints_focus_flash?, as each toggle costs a frame) - and by ComboBoxPopup for its items, which it flashes
        # itself. Widgets should not set this directly
        @focus_highlighted : Bool = false

        # Whether to_primitives draws the keyboard focus flash (FocusFlashController). The flash runs only on a widget
        # that says so - a toggle marks it for render, a frame that paints nothing new on any other
        # (spec/input/focus_flash_painters_spec.cr holds every focusable widget to its answer).
        def paints_focus_flash? : Bool
            false
        end

        def focus_highlighted? : Bool
            @focus_highlighted
        end

        def focus_highlighted=(value : Bool)
            return if @focus_highlighted == value
            @focus_highlighted = value
            mark_needs_render
        end

        # Explicit focus navigation overrides
        # Allows overriding automatic spatial navigation for specific directions
        @focus_override : FocusOverride? = nil
        property focus_override : FocusOverride?

        # Cached primitive list (for primitive-based rendering)
        # Managed by base class - subclasses never touch this. Used by the Static cache policy; the
        # Dynamic policy uses @primitives_node.
        @cached_primitives : Array(DrawPrimitive)?

        # The Dynamic-policy primitive cache as a pull node. Its recompute is
        # to_primitives(@primitives_bounds), which AUTO-CAPTURES theme/zoom (Sources) it reads; content
        # and layout are signalled via touch() from mark_needs_render / mark_needs_layout. Lazily created
        # on first render.
        @primitives_node : Cached(Array(DrawPrimitive))? = nil
        @primitives_bounds : Rect = Rect.new(0.0, 0.0, 0.0, 0.0)

        # Per-widget render backend (for per-widget texture optimization)
        # Each widget maintains its own tiny RenderTexture for fast selective rendering
        # Managed by renderer - subclasses never touch this
        @widget_backend : RenderBackend?

        # Track if widget has rendered to layer at current bounds (for invariant h)
        # Prevents capturing own content as background
        @rendered_to_layer_at_current_bounds : Bool = false

        # Background backend (stores saved background from layer)
        # For SFML: small RenderTexture with layer background (GPU-based, fast)
        # For TestRenderBackend: pixel buffer with Array(Color) (CPU-based)
        # Captured once on first render, restored before each subsequent render
        # Managed by renderer - subclasses never touch this
        @background_backend : RenderBackend?


        # Layer position where widget was last rendered (for auto-detecting stale background).
        # Cleared when widget_backend is disposed (scroll exit, rebuild).
        @last_rendered_layer_position : Tuple(Int32, Int32)? = nil

        # Last constraints used for layout (for incremental layout optimization)
        # If current constraints match and widget is clean, layout can be skipped
        @last_constraints : BoxConstraints?

        # Zoom epoch at last layout (forces re-layout when zoom changes)
        @last_zoom_epoch : UInt64 = 0

        # Per-widget revision axes for the primitive cache.
        # content_rev bumps on mark_needs_render (visual change), layout_rev on mark_needs_layout
        # (size/structure). Summed with the global Theme.theme_rev + FontSizing.zoom_epoch they form
        # the validity key (see primitive_cache_rev) — replacing `needs_render? || nil`, which was
        # blind to theme/zoom swaps that issue no mark_needs_render.
        @content_rev : UInt64 = 0
        @layout_rev : UInt64 = 0

        # Pull/SlotBuffer (sparse, per-cell — no dense structure): the slot key for a
        # viewport_cache buffer = {content version, BUFFER position}. content_version is the cell's
        # primitives_version (the Cached node version for a Dynamic cell — auto-captures theme/zoom;
        # the content_rev+layout_rev residual otherwise). buffer_pos = content_pos − buffer_origin.
        # The buffer SKIPS a cell whose key is unchanged (it already holds its pixels);
        # the soundness invariant is that buffer_pos is moved IN LOCKSTEP with the pixels by every
        # buffer op (scroll blit-shift → shift_slot; reflow/clear → invalidate via disposed backend).
        @slot_rev : UInt64? = nil
        @slot_buffer_pos : Tuple(Int32, Int32)? = nil

        # Skip iff the buffer already holds this cell's current pixels at buffer_pos. The
        # version axis is the cell's node version (primitives_version) — auto-captures theme/zoom, so a
        # theme/zoom swap invalidates every slot. The geometric coherence (buffer_pos +
        # shift_slot/invalidate_slot lockstep) is the separate spatial axis, unchanged.
        def slot_fresh?(buffer_pos : Tuple(Int32, Int32)) : Bool
            @slot_rev == primitives_version && @slot_buffer_pos == buffer_pos
        end

        # Stamp the slot after a (re-)blit into the buffer at buffer_pos.
        def stamp_slot(buffer_pos : Tuple(Int32, Int32)) : Nil
            @slot_rev = primitives_version
            @slot_buffer_pos = buffer_pos
        end

        # Blit-shift lockstep: the cell's pixels were moved by (dx,dy) in the buffer — move its stamp too.
        def shift_slot(dx : Int32, dy : Int32) : Nil
            if bp = @slot_buffer_pos
                @slot_buffer_pos = {bp[0] + dx, bp[1] + dy}
            end
        end

        # Blit-shift: the cell's backend is still VALID but its pixels were NOT copied to the new buffer
        # position — invalidate the slot so it re-blits the cached backend (no re-render needed).
        def invalidate_slot : Nil
            @slot_buffer_pos = nil
        end

        # True iff the cached widget_backend texture still reflects the current version (position aside).
        def slot_rev_matches? : Bool
            @slot_rev == primitives_version
        end

        def initialize(@id : String? = nil)
            @parent = nil
            @children = [] of Widget
            @bounds = Rect.zero
            @state = WidgetState::NeedsLayout
            @children_escape_bounds = false
            @widget_backend = nil
            @background_backend = nil
            @render_layer = nil
        end

        # Path-based ID for hierarchical identification (ImGui-inspired)
        # Example: "window/toolbar/save_button"
        def path_id : String
            if @parent
                parent_path = @parent.not_nil!.path_id
                my_segment = @id || label || self.class.name.split("::").last
                "#{parent_path}/#{my_segment}"
            else
                @id || label || self.class.name.split("::").last
            end
        end

        # Label for display/identification (can be overridden)
        def label : String?
            nil
        end

        # Add child widget
        def add_child(child : Widget)
            # Warn if ID is already used by a sibling (unless warnings disabled)
            if child_id = child.id
                if @children.any? { |sibling| sibling.id == child_id }
                    if Widget.enable_warnings
                        STDERR.puts "WARNING: Duplicate widget ID '#{child_id}' among siblings of #{self.class.name}"
                        STDERR.puts "  This may cause issues with find() and reconciliation."
                    end
                end
            end

            child.parent = self
            @children << child

            # Auto-trigger build for composite widgets (only once)
            unless child.built?
                child.mark_built
                child.build
            end

            mark_needs_layout
        end

        # Remove child widget
        def remove_child(child : Widget)
            @children.delete(child)
            child.parent = nil
            mark_needs_layout
        end

        # Clear all children
        def clear_children
            @children.each { |child| child.parent = nil }
            @children.clear
            mark_needs_layout
        end

        # Mark widget as needing layout (structural change)
        # This implies rendering will also be needed
        def mark_needs_layout
            @state = WidgetState::NeedsLayout
            @layout_rev &+= 1             # bump layout axis
            @primitives_node.try(&.touch) # signal the pull node (layout is an intrinsic change)
            @ancestry_bounds_valid = nil  # Invalidate bounds cache (propagates up via parent chain)

            # Invalidate cached constraints (forces re-layout even if constraints unchanged)
            invalidate_last_constraints

            # Layout changed, so the saved background must be recaptured from the new
            # position (the setter releases the old one).
            self.background_backend = nil

            @parent.try &.mark_needs_layout

            # Propagate to containing layer ONLY if already laid out
            # Skip during initial build phase (bounds not set yet) - massive performance win
            # After first layout, layer propagation keeps rendering in sync with layout changes
            propagate_to_layer unless @bounds.width == 0.0 && @bounds.height == 0.0
        end

        # Mark widget as needing render (visual change only)
        # Does not trigger layout unless already needed
        def mark_needs_render
            @@mark_render_count &+= 1  # instrumentation: count the propagation (see @@mark_render_count)
            @content_rev &+= 1  # bump content axis (any visual change)
            @primitives_node.try(&.touch) # signal the pull node (content is an intrinsic change)
            # Don't downgrade from NeedsLayout to NeedsRender
            @state = WidgetState::NeedsRender if @state == WidgetState::Clean

            # Chrome/content split eliminates need for invalidate_children_backgrounds!
            # Chrome and content have non-overlapping bounds, so chrome re-render
            # cannot overwrite content. Content uses selective rendering (dirty widgets only).
            # This achieves O(1) performance instead of O(children) cascade.

            # Propagate to containing layer (replaces parent propagation for rendering)
            # Layer propagation handles the hierarchy - no need to propagate up parent chain
            propagate_to_layer
        end

        # Propagate state change to containing layer
        # Walks up parent chain to find a widget with a layer and marks it
        private def propagate_to_layer
            # Check explicit render_layer override (e.g., VirtualMatrix sticky cells)
            if rl = @render_layer
                if @state == WidgetState::NeedsLayout
                    rl.mark_needs_layout
                else
                    rl.mark_needs_render(self)
                end
                return
            end

            # First check if THIS widget has its own layer (WindowPanel, MenuBar, Popup, LayerBox)
            if layer = self.layer
                # This widget owns the layer - check if layout or just render is needed
                if @state == WidgetState::NeedsLayout
                    # Layout needed - mark layer for layout (disables viewport culling for new widgets)
                    layer.mark_needs_layout
                else
                    # Just render - mark widget dirty (selective rendering)
                    layer.mark_needs_render(self)
                end
                return
            end

            # Otherwise, walk up parent chain to find a widget with a layer (Window)
            current = self.parent
            while current
                # Check if parent widget has a layer
                if layer = current.layer
                    # Check if this widget needs layout or just render
                    if @state == WidgetState::NeedsLayout
                        # Layout needed - mark layer for layout (disables viewport culling)
                        layer.mark_needs_layout
                    else
                        # Just render - mark widget dirty (selective rendering)
                        layer.mark_needs_render(self)
                    end
                    return
                end
                current = current.parent
            end
        end

        # The node-driven layer-index enqueue. The widget's primitives node calls this
        # (via on_dirty) when it goes value-stale, putting this widget in its layer's selective-render
        # set. Reuses propagate_to_layer so the @state branch (selective render vs full-layout) is
        # honoured exactly as the push path does — they coexist idempotently with the push.
        protected def enqueue_dirty_to_layer : Nil
            propagate_to_layer
        end

        # Invalidate children's background backends recursively
        # Called when parent changes visually - children must re-capture backgrounds
        # This is an O(children) cascade which is correct behavior (uncommon case: ~5-10%)
        # Common case (leaf changes) remains O(1) selective rendering
        protected def invalidate_children_backgrounds
            @children.each do |child|
                # Invalidate child's background (forces re-capture on next render)
                child.background_backend = nil
                # CRITICAL: Mark child as needing render so it actually re-renders!
                # Without this, child keeps old content with invalid background → artifacts
                child.mark_needs_render
                # Recursively invalidate descendants
                child.invalidate_children_backgrounds
            end
        end

        # Widget property macros — two concerns, two macros:
        #
        #   reactive_property  — a reactive VALUE (the workhorse). A tracked Source(T): read it in
        #                        to_primitives and it auto-captures; a change re-renders.
        #   reconcile_property — non-reactive infrastructure that must survive a DSL rebuild (a managed
        #                        Layer/Widget ref). A plain ivar, carried across the rebuild — NOT a value.
        #
        # Usage:
        #   reactive_property text : String                              # render-reactive (read while painting)
        #   reactive_property padding : Float64 = 0.0, layout: true      # change also re-layouts
        #   reactive_property mode : Mode = Mode::None, reconcile: true   # value survives a rebuild
        #   reconcile_property content_layer : Layer?                    # carried object ref, not reactive

        # reactive_property: the unified reactive field. The field is a tracked Source(T) — the getter
        # reads it (so to_primitives AUTO-CAPTURES it → the primitives node depends on it), the setter
        # notifies (→ node stale → the on_dirty callback enqueues this widget). No manual mark: the value
        # edge can't be forgotten, and the equality gate suppresses no-op writes.
        #   layout: true    → the setter ALSO pokes the imperative layout pass (mark_needs_layout) — layout
        #                     is not a pull-node, so a layout-affecting change must trigger it explicitly.
        #   reconcile: true → @[Reconcile] + a PLAIN build-shadow (the @[Reconcile] copy compares it by ==;
        #                     a Source-typed shadow would compare by identity and never reconcile), so the
        #                     value survives a DSL rebuild.
        macro reactive_property(declaration, layout = false, reconcile = false)
            {% if declaration.is_a?(TypeDeclaration) %}
                {% if reconcile %}
                    @[::CrymbleUI::Reconcile]
                {% end %}
                {% if !declaration.value.is_a?(Nop) %}
                    @{{declaration.var}} : ::CrymbleUI::Source({{declaration.type}}) = ::CrymbleUI::Source({{declaration.type}}).new({{declaration.value}})
                    {% if reconcile %}
                        @_build_{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    {% end %}
                {% else %}
                    @{{declaration.var}} : ::CrymbleUI::Source({{declaration.type}})
                {% end %}

                def {{declaration.var}} : {{declaration.type}}
                    @{{declaration.var}}.get
                end

                def {{declaration.var}}=(value : {{declaration.type}})
                    @{{declaration.var}}.set(value)
                    {% if layout %}
                        mark_needs_layout
                    {% end %}
                end
            {% end %}
        end

        # reconcile_property: non-reactive carry-over for infrastructure that must survive a DSL rebuild
        # but is NOT a reactive value — a managed Layer/Widget ref (content_layer, cursor_overlay_widget,
        # proxy_focused_widget). A plain ivar (NOT a Source): Source-wrapping a managed object would be a
        # dishonest abstraction and buys no auto-capture (these are never read in to_primitives). The field
        # is carried from the old widget on rebuild via @[Reconcile] (see auto_copy_reconcile_properties).
        # When a default exists, a @_build_<name> shadow gates the copy (app-wins-if-changed); without a
        # default it is always carried. Reactive VALUES use reactive_property(reconcile: true) instead.
        macro reconcile_property(declaration)
            {% if declaration.is_a?(TypeDeclaration) %}
                @[::CrymbleUI::Reconcile]
                {% if !declaration.value.is_a?(Nop) %}
                    @{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                    @_build_{{declaration.var}} : {{declaration.type}} = {{declaration.value}}
                {% else %}
                    @{{declaration.var}} : {{declaration.type}}
                {% end %}

                def {{declaration.var}} : {{declaration.type}}
                    @{{declaration.var}}
                end

                def {{declaration.var}}=(value : {{declaration.type}})
                    @{{declaration.var}} = value
                end
            {% end %}
        end

        # theme_property: a theme-derived Color that resolves LIVE.
        # Stores nil by default → the getter falls back to Theme.current.<theme_key> at READ time, so
        # a Theme.set recolors the widget immediately (paired with theme_rev invalidating the cache).
        # An explicit value (constructor arg or setter) is stored and WINS. This is the Flutter/ImGui
        # idiom: read the theme role at render, an explicit override takes precedence.
        # IMPORTANT: to_primitives MUST read the getter (`name`), never the `@name` ivar — the ivar is
        # the nullable override store, not the resolved color.
        macro theme_property(name, theme_key)
            # Stores nil (follow theme), a concrete Color (sticky override), or a live ThemeColorRef
            # (a different theme key, resolved at read time — see Theme.ref).
            @{{name.id}} : ThemeColor? = nil

            def {{name.id}} : Color
                v = @{{name.id}}
                case v
                in ThemeColorRef then v.resolve
                in Color         then v
                in Nil           then Theme.current.{{theme_key.id}}
                end
            end

            def {{name.id}}=(value : ThemeColor?)
                @{{name.id}} = value
                mark_needs_render
            end
        end

        # Check if widget needs rendering. For a node-backed (Dynamic, rendered) widget
        # this is NODE-DERIVED — render is needed iff the primitives cache is stale (a Source.set or a
        # touch invalidated it). This is more precise than the @state flag (which a Source-backed setter
        # no longer sets) and is what blit_plan needs: "blit the cached texture, or re-render?". Static /
        # Never / not-yet-rendered widgets fall back to the @state flag.
        def needs_render? : Bool
            if node = @primitives_node
                !node.valid?
            else
                @state >= WidgetState::NeedsRender
            end
        end

        # Check if widget needs layout
        def needs_layout? : Bool
            @state == WidgetState::NeedsLayout
        end

        # Clear state to Clean (for testing purposes only)
        def clear_state_for_test
            @state = WidgetState::Clean
        end

        # Half-pixel slack for the "did I fill?" test below. Erring toward "filled" (< EPS below max ⇒
        # treat as filling ⇒ re-layout) is the SAFE direction: at worst we re-layout a body that would
        # have been stable; the unsafe direction (skipping a fill body) would leave it the wrong size.
        LAYOUT_FILL_EPS = 0.5

        # Does this widget's child arrangement depend on the incoming constraint's AVAILABLE space, beyond
        # just its own resulting size? A wrapping/packing layout (FlowLayout) does — it re-packs rows
        # against max_width, so a width change can change its layout even though its own size stayed a
        # sub-max "widest row". Such a widget must NOT take the can_skip_layout? relaxation branch (which
        # assumes a sub-max body is intrinsic and unaffected by more space); it skips only on identical
        # constraints. Default false. Override → true to opt out of relaxation.
        #
        # Declaring it is NOT enough on its own: the skip that matters happens at an ANCESTOR, which
        # returns before this widget's layout() is ever reached. The closure below is what carries the
        # declaration upward.
        def layout_depends_on_available_space? : Bool
            false
        end

        # The SUBTREE closure of layout_depends_on_available_space? — true iff this widget or any
        # descendant re-arranges against the available space. This, not the own-only predicate, is what
        # can_skip_layout? must consult: a container whose own size is sub-max would otherwise take the
        # relaxation branch and never call the wrapping descendant that needed the re-flow (the filter
        # chip list that stopped re-packing when its panel was widened).
        #
        # Recomputed bottom-up at the end of every non-skip layout(), where children's flags are already
        # fresh. Sound by induction: a child either re-laid-out this pass, or skipped — and a skip means
        # its subtree is unchanged, so its flag still holds. Any structural change marks the whole
        # ancestor chain NeedsLayout (add_child/remove_child/clear_children), which precedes the skip check.
        #
        # Seeded TRUE so the unsafe direction (a stale false ⇒ a wrongly skipped re-flow) is unreachable
        # by construction rather than by audit: a widget that has never completed a layout already fails
        # can_skip_layout? via needs_layout?/@last_constraints, so the conservative seed costs nothing and
        # the first real layout replaces it. zero_bounds! clears it — see there for why that is exact.
        #
        # Scope: the closure is over @children, so a widget that lays out NON-children is outside it and
        # must opt out itself. The known cases are the popup/overlay ones — Menu (which also empties
        # @children into @menu_items during perform_layout), PopupHost, Window's @overlays — and they are
        # safe for a different reason than layer ownership (Menu owns no layer): Window#perform_layout
        # lays out EVERY overlay on every pass, and App#prepare_layout only enters that pass when the
        # root needs layout, so the root never takes a skip branch. A Menu skip could strand the popup's
        # POSITION, never its internal arrangement.
        getter? subtree_layout_depends_on_available_space : Bool = true

        # Re-close the dependency over the CURRENT children. Widget#layout does this for every widget it
        # lays out; this is the escape hatch for containers that populate @children outside
        # add_child/remove_child (VirtualMatrix's virtualized cells), where the bottom-up pass can
        # otherwise miss a child that appeared after the container was laid out.
        protected def refresh_subtree_layout_dependency : Nil
            was = @subtree_layout_depends_on_available_space
            @subtree_layout_depends_on_available_space =
                layout_depends_on_available_space? || @children.any?(&.subtree_layout_depends_on_available_space?)
            return if was || !@subtree_layout_depends_on_available_space
            # A false→true flip OUTSIDE a layout pass — the escape-hatch case, where cells arrive from
            # pre_render_flush after this widget was already laid out — has to reach the ANCESTORS too.
            # Writing the flag locally would leave one of them holding a stale false and skipping the
            # subtree that just became re-flow-dependent: the very defect this closure exists to prevent,
            # moved one level up. Stops at the first ancestor that already knows, so it costs O(depth)
            # once, on the frame the wrapping descendant appears.
            ancestor = @parent
            while ancestor && !ancestor.subtree_layout_depends_on_available_space?
                ancestor.mark_needs_layout
                ancestor = ancestor.parent
            end
        end

        # Check if layout can be skipped (incremental layout optimization).
        # Skips when the widget is clean, zoom is unchanged, and the new constraints can't change its
        # layout — either identical constraints, OR a RELAXATION the widget didn't use (its last size
        # still fits the new constraints and, in each axis whose max grew, it wasn't already filling the
        # old max). The relaxation case is what lets a floored panel's non-fill content skip a resize
        # grow (intrinsic body: size < max ⇒ a bigger max changes nothing); a fill body (size == max)
        # re-lays-out, since it grows into the new space.
        protected def can_skip_layout?(constraints : BoxConstraints) : Bool
            return false if needs_layout?
            return false if @last_zoom_epoch != FontSizing.zoom_epoch
            old = @last_constraints
            return false if old.nil?
            return true if old == constraints
            return false if subtree_layout_depends_on_available_space?

            sz = @bounds.size
            return false unless constraints.min_width <= sz.width <= constraints.max_width
            return false unless constraints.min_height <= sz.height <= constraints.max_height
            return false if constraints.max_width > old.max_width && sz.width >= old.max_width - LAYOUT_FILL_EPS
            return false if constraints.max_height > old.max_height && sz.height >= old.max_height - LAYOUT_FILL_EPS
            true
        end

        # Invalidate cached constraints (forces re-layout on next pass)
        protected def invalidate_last_constraints
            @last_constraints = nil
        end

        # Check if widget is a rendering leaf (draws its own content without relying on children)
        # Used by selective rendering to determine if widget area should be cleared before re-render
        # Default: true if no children (actual leaf)
        # Override in widgets that draw their own content even though they have children
        def rendering_leaf? : Bool
            children.empty?
        end

        # Do this widget's children lie within its bounds? The -Dverify_bounds containment check asks. A
        # widget that draws a child SCALED (a fitted) answers false: its child's laid-out rect may exceed it,
        # but what is painted does not.
        def contains_children? : Bool
            true
        end

        # Override to clip children rendering to a specific rect
        # Used by containers like Popup, WindowPanel that need to prevent children overflow
        # Renderer will automatically push/pop clip around children rendering
        def clip_children : Rect?
            nil  # Default: no clipping
        end

        # Polymorphic rendering control methods
        # These allow widgets to control their rendering behavior without
        # requiring type checks in the renderer

        # Should this widget be skipped entirely during rendering?
        # Used by widgets that can be hidden/closed (e.g., WindowPanel when closed)
        def skip_render? : Bool
            false  # Default: render everything
        end

        # Hook called by layer renderer before collecting widgets for rendering.
        # Override to flush deferred state (e.g., VirtualMatrix defers cell updates
        # during scrollbar drag to avoid running expensive work on every mouse event).
        def pre_render_flush
        end

        # True when an Escape given to this widget now would abort an edit or close something the user sees -
        # each editor answers for its own Escape branch (a container that forwards keys, for what it forwards
        # to). A host that handles Escape BEFORE the focused widget (App#handle_escape) asks the focused
        # widget first. False by default.
        def consumes_escape? : Bool
          false
        end

        # Structural work the next input depends on, applied by App#finish_frame for a widget that
        # registered it (request_frame_before_input / register_input_flush) - whether or not it painted
        # this frame. True when something ran. Nothing by default.
        def flush_before_input : Bool
          false
        end

        # Get menubar child if this widget has one (for direct compositing)
        # Override in containers that have menubars (e.g., Window)
        def menubar_child : Widget?
            nil  # Default: no menubar
        end

        # Build widget tree (declarative approach)
        # Subclasses override this to create their UI
        def build : Widget
            self
        end

        # Measure widget size given constraints
        # Returns the size the widget wants to be
        abstract def measure(constraints : BoxConstraints) : Size

        # Smallest height at which this widget still renders acceptably, at the given width.
        # Its own chain (NOT BoxConstraints-clamped like measure) so an unbounded request can't be
        # turned finite mid-compose. Default = the natural measured height — correct for LEAVES,
        # which can't shrink below their content. A CONTAINER with a shrinkable descendant (e.g. a
        # fill VirtualMatrix) MUST override, composing children's min the way its measure/perform_layout
        # stacks them; otherwise this default measures the greedy fill and the floor is wrong.
        def min_intrinsic_height(width : Float64) : Float64
            h = measure(BoxConstraints.new(min_width: 0.0, max_width: width, min_height: 0.0, max_height: Float64::INFINITY)).height
            {% if flag?(:verify_bounds) %}
                if !@children.empty? && h > 100_000.0
                    STDERR.puts "[min_intrinsic_height] #{self.class.name} fell through to the greedy measure default (#{h.round(0)}) — a container with a shrinkable descendant needs an override"
                end
            {% end %}
            h
        end

        # The WIDTH dual of min_intrinsic_height: smallest width at which this widget still renders
        # acceptably, at the given height. Own chain (NOT BoxConstraints-clamped), default = the natural
        # measured width — correct for LEAVES. A CONTAINER with a width-shrinkable descendant (a fill
        # VirtualMatrix / ScrollView) MUST override, composing children's min the way measure/perform_layout
        # arranges them on the WIDTH axis; otherwise this greedy-measures the fill and the floor is wrong.
        def min_intrinsic_width(height : Float64) : Float64
            w = measure(BoxConstraints.new(min_width: 0.0, max_width: Float64::INFINITY, min_height: 0.0, max_height: height)).width
            {% if flag?(:verify_bounds) %}
                if !@children.empty? && w > 100_000.0
                    STDERR.puts "[min_intrinsic_width] #{self.class.name} fell through to the greedy measure default (#{w.round(0)}) — a container with a width-shrinkable descendant needs an override"
                end
            {% end %}
            w
        end

        # A widget moved within its parent. Its captured background belongs to the OLD spot, and the
        # pixels it left behind belong to nobody: selective rendering repaints a widget where it now is,
        # never where it was. Both layout paths funnel here so they cannot drift apart again.
        private def note_position_change : Nil
            self.background_backend = nil
            mark_needs_render
            # A widget that has never painted vacated nothing — and without this gate a FIRST layout is
            # indistinguishable from a move (@bounds starts at Rect.zero), so every newly created widget
            # would demand a buffer clear. That is not theoretical: VirtualMatrix lays out freshly
            # created cells on the frames a scroll reveals them.
            return if @last_rendered_layer_position.nil?
            if l = containing_layer
                # Layers that own a geometry-repair mechanism opt out, because clearing them here
                # would throw away a pending blit-shift. That used to be spelled `viewport_cache`,
                # which claimed it for every layer of the type: the repair in question is
                # mark_needs_resize_shift, whose only callers are VirtualMatrix's two. A plain
                # ScrollView's content layer is viewport_cache with no repair of its own, so it took
                # the exemption and kept the vacated pixels — the About dialog's ghosted logo. The
                # claim is now opt-IN (Layer#owns_geometry_repair), made by the layer that has it.
                l.mark_needs_clear_and_render unless l.skip_rebuild_clear || l.owns_geometry_repair
            end
        end

        # The layer whose BUFFER holds this widget's pixels — strictly an ancestor's, never its own.
        # This deliberately differs from propagate_to_layer, which answers a different question ("who do
        # I mark dirty?"): for a widget that OWNS a layer, moving means the whole LAYER moved, which the
        # compositor already handles by blitting it elsewhere. Its buffer is not stale; the container it
        # moved WITHIN is the one holding the vacated pixels.
        def containing_layer : Layer?
            current = @parent
            while current
                if l = current.layer
                    return l
                end
                current = current.parent
            end
            nil
        end

        # Layout widget and children at given position
        # Template method: handles skip check, then delegates to perform_layout
        def layout(constraints : BoxConstraints, position : Vec2)
            # Skip layout if constraints unchanged and widget is clean
            if can_skip_layout?(constraints)
                # Just update position, skip full layout
                old_pos = @bounds.position
                @bounds = Rect.new(position, @bounds.size)
                # Position changed → background_backend holds content from old location
                # (Pull-based: layer bounds auto-update via compute_bounds_for_layer.)
                note_position_change if old_pos.x != position.x || old_pos.y != position.y
                return
            end

            # Set state to Clean first (before perform_layout)
            @state = WidgetState::Clean

            # Remember old geometry for change detection
            old_width = @bounds.width
            old_height = @bounds.height
            old_pos = @bounds.position

            # Delegate to subclass implementation
            perform_layout(constraints, position)

            # Invalidate primitive cache when size changes.
            # Cached primitives (e.g., fill_rect) use the old bounds dimensions and would
            # leave unfilled regions on the new, differently-sized widget_backend.
            if old_width != @bounds.width || old_height != @bounds.height
                mark_needs_render
            end

            # …and when it merely MOVED. Compare the resulting bounds, not the `position` argument —
            # self-positioning widgets (WindowPanel::Content) ignore it.
            note_position_change if old_pos.x != @bounds.x || old_pos.y != @bounds.y

            # Verify bounds satisfaction: widget size must respect constraints.
            # Found by Z3 verification: Image, Expanded, TextInput violated this.
            {% if flag?(:verify_bounds) %}
              if constraints.max_width.finite? && @bounds.width > constraints.max_width + 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} width #{@bounds.width.round(1)} > max #{constraints.max_width.round(1)}"
              end
              if constraints.max_height.finite? && @bounds.height > constraints.max_height + 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} height #{@bounds.height.round(1)} > max #{constraints.max_height.round(1)}"
              end
              if @bounds.width < constraints.min_width - 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} width #{@bounds.width.round(1)} < min #{constraints.min_width.round(1)}"
              end
              if @bounds.height < constraints.min_height - 0.5
                STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} height #{@bounds.height.round(1)} < min #{constraints.min_height.round(1)}"
              end
              # Containment, the dual of the sibling no-overlap check. Stacks size themselves from
              # `measure` but advance their cursor by each child's post-layout bounds, so a child whose
              # laid-out extent exceeds its measured one no longer overlaps its sibling — it escapes the
              # PARENT instead, where a siblings-only check cannot see it.
              if contains_children?
                @children.each do |child|
                  if child.bounds.right > @bounds.width + 0.5 || child.bounds.bottom > @bounds.height + 0.5
                    Widget.increment_containment_warnings
                    STDERR.puts "[BOUNDS] #{self.class.name}##{path_id} child " \
                                "#{child.class.name.split("::").last}##{child.path_id} #{child.bounds} " \
                                "overflows parent #{@bounds.size}"
                  end
                end
              end
            {% end %}

            # Save constraints and zoom epoch for next skip check
            @last_constraints = constraints
            @last_zoom_epoch = FontSizing.zoom_epoch

            # Re-close the available-space dependency over the subtree, now that perform_layout has
            # refreshed every child's own flag. Only on this path: a skipped subtree cannot have changed.
            refresh_subtree_layout_dependency
        end

        # Coherent reposition for a blit-shift: translate this widget's bounds by (dx, dy) WITHOUT
        # invalidating its cached primitives or background. The caller (a content-layer resize blit-
        # shift) has already translated the widget's composited pixels in the layer buffer and moved its
        # slot stamp in lockstep (shift_slot), so a re-render/re-blit would be redundant. Contrast
        # layout()'s position-only fast path, which disposes the background + marks needs_render — correct
        # only when NOTHING has moved the pixels for you. Because @bounds is parent-local, this shifts
        # absolute_bounds (and every descendant's) by the same delta.
        def shift_bounds(dx : Float64, dy : Float64) : Nil
            @bounds = Rect.new(Vec2.new(@bounds.x + dx, @bounds.y + dy), @bounds.size)
        end

        # Perform actual layout (implemented by subclasses)
        # Called by layout() after skip check passes
        # Subclasses must set @bounds and layout children
        abstract def perform_layout(constraints : BoxConstraints, position : Vec2)

        # Auto-copy all @[Reconcile] annotated properties from old widget
        # Called by copy_state_from - widgets can override copy_state_from for custom logic
        # Note: reconcile_property always adds @[Reconcile]; reactive_property adds it only with
        # `reconcile: true`. Fields with a @_build_<name> shadow are gated (app-wins-if-changed);
        # fields without one (a no-default reconcile_property object ref) are always carried.
        protected def auto_copy_reconcile_properties(old_widget : Widget)
            {% for ivar in @type.instance_vars %}
                {% if ivar.annotation(::CrymbleUI::Reconcile) %}
                    {% build_var = "_build_#{ivar.name}".id %}
                    {% has_build = @type.instance_vars.any? { |v| v.name == build_var } %}
                    {% if has_build %}
                        # Only reconcile if build value didn't change (app didn't change it)
                        if @{{build_var}} == old_widget.as({{@type}}).@{{build_var}}
                            assert_no_constructor_layer(@{{ivar.name}}, old_widget.as({{@type}}).@{{ivar.name}})
                            @{{ivar.name}} = old_widget.as({{@type}}).@{{ivar.name}}
                            adopt_reconciled_layer(@{{ivar.name}}, old_widget)
                        end
                    {% else %}
                        # No build tracking (manual @[Reconcile]) — always reconcile
                        assert_no_constructor_layer(@{{ivar.name}}, old_widget.as({{@type}}).@{{ivar.name}})
                        @{{ivar.name}} = old_widget.as({{@type}}).@{{ivar.name}}
                        adopt_reconciled_layer(@{{ivar.name}}, old_widget)
                    {% end %}
                {% end %}
            {% end %}
        end

        # A @[Reconcile]-carried Layer keeps the OLD (discarded) widget as its owner_widget.
        # Re-point it to this new instance, or Layer.active_layers' in_tree? walk (owner → root)
        # can't find it → the compositor silently drops the layer AND pull-based bounds go stale.
        # Generic on purpose: fires for EVERY reconciled Layer, so a widget that adds a new layer
        # never has to remember a manual per-layer re-sync (the drag-overlay-invisible-after-rebuild
        # bug this replaces). No-op for non-Layer reconciled properties.
        protected def adopt_reconciled_layer(value, old_widget : Widget) : Nil
            if value.is_a?(::CrymbleUI::Layer) && value.owner_widget == old_widget
                value.owner_widget = self
            end
        end

        # The reconcile-partner of adopt_reconciled_layer, and its INVARIANT guard.
        # A @[Reconcile] Layer must be created LAZILY in perform_layout (@x ||= Layer.new),
        # never in the constructor: a constructor-created layer is immediately displaced by
        # the carried one on the first reconcile and leaks into @@all_layers (its owner is the
        # live new instance, so in_tree? never reaps it). All own-layer widgets create lazily
        # (ScrollView, VirtualMatrix, WindowPanel, LayerBox, Popup) → `current` is nil here on
        # a fresh instance, so this asserts silently. A future widget that regresses to
        # constructor creation trips it LOUD. Called BEFORE the overwrite, so `current` is the
        # new instance's ivar and `incoming` the carried old one.
        # `current.same?(incoming)` keeps it false-positive-safe under the DOUBLE auto_copy of
        # override-then-super widgets (VirtualMatrix): pass 2 sees current == incoming == the
        # already-carried layer (adopt set it in pass 1). No-op for non-Layer properties.
        protected def assert_no_constructor_layer(current, incoming) : Nil
            assert(
                !current.is_a?(::CrymbleUI::Layer) || current.same?(incoming),
                "a @[Reconcile] Layer must be created lazily in perform_layout (@x ||= Layer.new), " \
                "not in the constructor — a constructor-created layer leaks into @@all_layers every reconcile"
            )
        end

        # bind: STABILITY GUARD state. A two-way-bound widget must adopt the SAME app-owned Source each
        # build (a stable ivar), NOT a fresh Source.new(...) per build() — else every reconcile re-adopts
        # a new cell and edits + cross-widget sharing silently break. We can't hard-raise: a legitimate
        # one-time rebind (a detail widget re-bound to the newly-selected row's Source) also changes
        # identity, and sustained legitimate rebinding is indistinguishable at this seam. So we WARN once,
        # only after the bound Source's identity changed on 2 CONSECUTIVE reconciles (skips the one-time
        # swap). Unbound widgets (@bind_source nil) legitimately own a fresh Source each build → exempt.
        # Mirrors the duplicate-widget-ID warning in add_child. We HOLD the adopted Source (not its
        # object_id) so identity is compared on LIVE objects via same? — a stored address is UNSOUND
        # (Boehm can reuse a freed Source's address, aliasing two distinct cells). The hold adds no GC
        # cost: @value/@checked/@selected_index already keep that same object alive. (Extend the union
        # when a new bind: widget type ships, e.g. MultiComboBox Source(Set(Int32)).)
        @bind_source : (Source(String) | Source(Bool) | Source(Int32))? = nil # adopted cell; nil ⇒ unbound
        @bind_swap_streak : Int32 = 0    # consecutive reconciles the bound Source changed identity

        protected def note_bind_reconcile(old_widget : Widget) : Nil
            cur = @bind_source
            return unless cur                     # unbound ⇒ fresh-per-build is legitimate here
            prev = old_widget.@bind_source
            if prev && !cur.same?(prev)           # identity on LIVE objects (both held) — sound
                @bind_swap_streak = old_widget.@bind_swap_streak + 1
                if @bind_swap_streak == 2         # the crossing — warn exactly once per episode
                    Widget.increment_bind_stability_warnings
                    if Widget.enable_warnings
                        STDERR.puts "WARNING: bind: Source changed identity on 2 consecutive rebuilds for " \
                          "#{self.class.name}##{path_id} — pass a STABLE app-owned Source (an ivar re-passed " \
                          "each build), not a fresh Source.new(...) in build(). Edits and cross-widget " \
                          "sharing will silently break. (Ignore if this is a deliberate, sustained rebind.)"
                    end
                end
            else
                @bind_swap_streak = 0             # stable, or a one-time swap that then settled
            end
        end

        # Copy internal state from old widget during reconciliation
        # Override this in subclasses for custom logic (e.g., callback re-wiring)
        # Call auto_copy_reconcile_properties(old_widget) first, then add custom logic
        # Base implementation copies background_backend, constraints, focus, and all @[Reconcile] properties
        def copy_state_from(old_widget : Widget)
            note_bind_reconcile(old_widget) # bind: stability guard (warns on fresh-Source-per-build)
            # CRITICAL: Only preserve background_backend (clean layer background behind widget)
            # Do NOT copy widget_backend - it contains old rendered content!
            # If we copied widget_backend and rendered on top, we'd get double rendering
            # The widget_backend will be recreated fresh during rendering

            # Copy background_backend from old widget (if it exists)
            # Note: We can't check size here because layout hasn't happened yet
            # Size validation happens during rendering (invariant g will catch mismatches)
            # TRANSFER, not copy: the old widget releases its pointer as we take it. While both
            # sides held the same object, a discarded widget's background could never be released
            # (disposing it would have destroyed the live widget's background). After the transfer,
            # a background still present on a discarded widget is provably UNSHARED, which is what
            # lets dispose_subtree release it. Uses the direct seam so it cannot be mistaken for a
            # release of the object itself.
            # A build that returns the SAME instance reconciles a widget with itself: nothing to transfer, and its
            # background stays (going through the release below would leave the field naming a released surface).
            # A twin that already holds a background (a kept instance placed anew) has it superseded: released,
            # then the old one adopted.
            if !old_widget.same?(self) && (old_bg = old_widget.background_backend)
                self.background_backend = nil
                @background_backend = old_bg
                old_widget.relinquish_background_backend
                {% if flag?(:DEBUG_RENDER) %}
                    puts "[COPY_STATE] #{self.class.name.split("::").last}##{path_id} <- adopted background (backend=#{old_bg.object_id}, size=#{old_bg.width}x#{old_bg.height})"
                {% end %}
            end

            # Copy cached constraints (enables layout skipping after rebuild)
            @last_constraints = old_widget.@last_constraints

            # Transfer focus if old widget had it (applies to all focusable widgets)
            # This ensures flash animation continues on the new widget after rebuild
            if old_widget.focused?
                # Carry the flash phase as state, so the transfer's marking setter finds it equal: a render mark on a
                # fresh (NeedsLayout) instance escalates to a layout of its whole layer (docs/ARCHITECTURE.md, "carries
                # state"). Fresh only - a rendered, kept instance needs the mark. old's flag is the controller's phase.
                if cache_policy != CachePolicy::Never && @primitives_node.nil? && @cached_primitives.nil?
                    @focus_highlighted = old_widget.focus_highlighted?
                end
                Widget.focus_manager?.try &.transfer_focus(old_widget, self)
            end

            # Auto-copy all @[Reconcile] annotated properties. This also re-adopts every
            # reconciled Layer (adopt_reconciled_layer) so a carried layer never keeps the
            # old, discarded widget as its owner_widget.
            auto_copy_reconcile_properties(old_widget)

            # Backstop for a `layer` override whose backing field is NOT a @[Reconcile]
            # property (Window returns @root_layer, created fresh per instance). Idempotent
            # for the common case — @internal_layer et al. are already re-adopted above.
            if self.responds_to?(:layer) && (lyr = self.layer)
                lyr.owner_widget = self
            end
        end

        # === PRIMITIVE-BASED RENDERING (New Architecture) ===

        # Cache policy for primitive generation
        # Subclasses override this to declare their caching behavior
        # Default: Dynamic (cache primitives, invalidate on state change)
        def cache_policy : CachePolicy
            CachePolicy::Dynamic
        end

        # Generate primitives describing what to draw
        # Subclasses override this to use primitive rendering
        # Default: empty array (widget uses old render() path)
        # Base class handles all caching via get_primitives()
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            [] of DrawPrimitive
        end

        # The residual primitive-cache validity key: this widget's content_rev (visual changes) +
        # layout_rev (size). Both monotonic, so the wrapping &+ sum is a pure monotonic key (never
        # raising); a bump on either axis forces a regenerate. Theme/zoom are NOT summed here (see the
        # method body): a rendered Dynamic widget captures them via its Cached node version, a zoom bump
        # also moves layout_rev, and a theme switch reaches the residual via rebuild — so the global
        # theme_rev counter was deleted. This AUGMENTS the old `needs_render? || nil` key (blind to
        # theme/zoom swaps, which issue no mark_needs_render).
        def primitive_cache_rev : UInt64
            # The residual version for Static / Never / pre-first-render widgets only
            # (rendered Dynamic widgets use the node version). Theme/zoom dropped here: Dynamic widgets
            # auto-capture them via the Cached node; a zoom change also bumps layout_rev (relayout); and a
            # theme switch reaches the residual via rebuild. The global theme_rev counter is now deleted.
            @content_rev &+ @layout_rev
        end

        # The per-widget version the render-trigger aggregate folds. For a rendered
        # Dynamic widget this is the pull node's version (auto-captured theme/zoom + touch-driven local
        # rev) — so the trigger moves iff this widget's primitives WOULD change, correct-by-construction
        # and more precise than the global rev (only widgets that read theme move on a theme swap). For
        # Static (cached forever — currently unused by any widget), Never (re-rendered every frame,
        # triggered elsewhere — drag ghost, cursor overlay), and a not-yet-rendered Dynamic widget fall
        # back to the hand-rolled primitive_cache_rev — a DECIDED PERMANENT residual (reseating these
        # no-node cases onto Cached nodes is awkward + zero value). version() is CHEAP — re-folds, never recomputes.
        def primitives_version : UInt64
            if cache_policy == CachePolicy::Dynamic && (node = @primitives_node)
                node.version
            else
                primitive_cache_rev
            end
        end

        # Get primitives (may be cached)
        # Renderer calls this method - never call to_primitives directly
        # Base class manages caching based on cache_policy
        def get_primitives(bounds : Rect) : Array(DrawPrimitive)
            case cache_policy
            when CachePolicy::Never
                # Always generate fresh (menus, popups, animations)
                to_primitives(bounds)

            when CachePolicy::Dynamic
                # The cache is a pull node. Its recompute (to_primitives) auto-captures
                # the theme/zoom it reads; content/layout are signalled via touch() from
                # mark_needs_render / mark_needs_layout. The node memoizes and re-derives only on a real
                # change — correct-by-construction (a global edge the widget reads can't be forgotten).
                @primitives_bounds = bounds
                node = @primitives_node
                unless node
                    node = Cached(Array(DrawPrimitive)).new { to_primitives(@primitives_bounds) }
                    # When this node goes value-stale, enqueue THIS widget into its layer's
                    # selective-render index — the pull-side replacement for mark_needs_render's push
                    # (which still COEXISTS). Fires once per clean→stale edge.
                    node.on_dirty = -> { enqueue_dirty_to_layer }
                    @primitives_node = node
                end
                node.get

            when CachePolicy::Static
                # Cache primitives forever (window chrome, static content)
                @cached_primitives ||= to_primitives(bounds)
            else
                # This should never happen (all enum values covered)
                raise "Unknown cache policy: #{cache_policy}"
            end
        end

        # Invalidate primitive cache (called on state changes)
        def invalidate_primitive_cache
            @cached_primitives = nil
            @primitives_node.try(&.touch)
        end

        # Check if widget has valid cached primitives (for scroll optimization)
        # Returns true if primitives were generated and haven't been invalidated
        def has_valid_primitive_cache? : Bool
            if node = @primitives_node
                node.valid? # Dynamic policy: fresh iff the node's memoized value is current
            else
                !@cached_primitives.nil?
            end
        end

        # The pull node backing get_primitives (nil before first render / after dispose). Exposed for
        # tests asserting node IDENTITY survives a rebuild — a wrongfully-disposed live widget would
        # recreate a DIFFERENT node, a regression the disposition oracle can't see (a disposed node
        # self-heals on the next render, so widget_disposition stays non-nil).
        def primitives_node : Cached(Array(DrawPrimitive))?
            @primitives_node
        end

        # === END PRIMITIVE-BASED RENDERING ===

        # === PER-WIDGET TEXTURE BACKEND ===

        # Get widget's render backend (nil if not yet created)
        def widget_backend : RenderBackend?
            @widget_backend
        end

        # Set widget's render backend (managed by renderer). The ONE release point: the backend it replaces -
        # nil included - is released, so no path can drop a surface without freeing it (under SFML a dropped
        # one is a driver texture the collector cannot see). Assigned first, so the field never names a
        # released surface. A different surface bumps `backend_generation`, which a blit plan checks.
        def widget_backend=(backend : RenderBackend?)
            old = @widget_backend
            @widget_backend = backend
            @last_rendered_layer_position = nil if backend.nil?
            unless old.same?(backend)
                @backend_generation &+= 1
                old.try(&.dispose)
            end
        end

        # Moves each time this widget's widget_backend is replaced: a blit plan names the surface it saw by it,
        # without holding the surface itself.
        getter backend_generation : Int32 = 0

        # Get background backend (nil if not yet captured)
        def background_backend : RenderBackend?
            @background_backend
        end

        # Set background backend (managed by renderer). Releases the one it replaces, as widget_backend= does.
        # The one write that must NOT release is reconcile's transfer (copy_state_from), which writes the ivar.
        def background_backend=(backend : RenderBackend?)
            old = @background_backend
            @background_backend = backend
            # When background is invalidated (set to nil), reset the rendered flag
            # This allows re-capturing background at new position/size
            if backend.nil?
                @rendered_to_layer_at_current_bounds = false
            end
            old.try(&.dispose) unless old.same?(backend)
        end

        # Check if widget has rendered to layer at current bounds (for invariant h)
        def rendered_to_layer_at_current_bounds? : Bool
            @rendered_to_layer_at_current_bounds
        end

        # Mark that widget has rendered to layer (called by renderer after blit)
        def mark_rendered_to_layer!
            @rendered_to_layer_at_current_bounds = true
        end

        # Layer position where widget was last rendered (for centralized stale-background detection)
        def last_rendered_layer_position : Tuple(Int32, Int32)?
            @last_rendered_layer_position
        end

        def last_rendered_layer_position=(pos : Tuple(Int32, Int32)?)
            @last_rendered_layer_position = pos
        end

        # Check if this widget and all ancestors have positive bounds (cached).
        # Used by valid_layer_dimensions? to avoid O(depth) walk every frame.
        def ancestry_bounds_valid? : Bool
            if cached = @ancestry_bounds_valid
                return cached
            end
            valid = bounds.width > 0 && bounds.height > 0
            if valid && (p = @parent)
                valid = p.ancestry_bounds_valid?
            end
            @ancestry_bounds_valid = valid
            valid
        end

        # Recursively invalidate ancestry_bounds_valid cache on this widget and all descendants.
        # Called when a parent (e.g., TreeNode) collapses and zeros children bounds —
        # without this, cached `true` values persist and layer compositing continues
        # for child-owned layers (e.g., VirtualMatrix viewport_cache), causing ghost pixels.
        # Check if this widget is reachable from root via parent chain.
        # Used by reconciliation validator to detect orphaned widgets.
        # Zero bounds and invalidate all caches. Called when a widget becomes hidden
        # (e.g., TreeNode collapse). Ensures no stale cached state persists —
        # prevents ghost pixels, stale primitive caches, and stale ancestry_bounds.
        def zero_bounds!
            @bounds = Rect.zero
            invalidate_last_constraints
            @cached_primitives = nil
            @primitives_node.try(&.touch)
            self.background_backend = nil
            self.widget_backend = nil
            @ancestry_bounds_valid = nil
            # A zeroed subtree is not laid out, so it cannot re-arrange against available space: clearing
            # the closure is exact, not merely cheap. It also matters — a collapsed section is never
            # re-laid-out, so a retained `true` here would latch forever and cost every ancestor its
            # relaxation skip for the rest of the session. Safe because the recursion below invalidates
            # every descendant's constraints (nothing inside can skip) and re-expanding marks the whole
            # ancestor chain NeedsLayout, which recomputes the closure before anyone reads it.
            @subtree_layout_depends_on_available_space = false
            # A vacated footprint releases the cached pixels of the WHOLE subtree, not just
            # this node. Otherwise a descendant keeps stale bounds + a cached widget_backend,
            # and a viewport_cache layer's visit-all-visible pass re-blits it next frame as a
            # ghost (it never traverses through this now-zeroed node to discover it's gone).
            # Recursing also frees the hidden subtree's GPU backends — a perf win, not a cost.
            @children.each(&.zero_bounds!)
        end

        def widget_in_tree?(root : Widget) : Bool
            current : Widget? = self
            while current
                return true if current == root
                current = current.parent
            end
            false
        end

        # === END PER-WIDGET TEXTURE BACKEND ===

        # Hit test - check if point is inside widget
        def hit_test(point : Vec2) : Widget?
            # If children can escape bounds, check them first even if point is outside parent
            if @children_escape_bounds
                children_in_hit_order do |child|
                    if hit = child.hit_test(point)
                        return hit
                    end
                end
            end

            # Check if point is in this widget's bounds (use absolute coordinates)
            return nil unless absolute_bounds.contains_point(point)

            # Check children (if we haven't already due to escape_bounds)
            unless @children_escape_bounds
                children_in_hit_order do |child|
                    if hit = child.hit_test(point)
                        return hit
                    end
                end
            end

            # Return self if no child was hit
            self
        end

        # The children front to back - the reverse of the order they composite in (Layer.sibling_key), so a click
        # lands where things are drawn. Every hit_test that walks children walks them through this. Plain
        # reverse order unless one of them is ranked or a boundary (no allocation on the common path).
        def children_in_hit_order(& : Widget ->) : Nil
            if ranks_children? || @children.any? { |child| Layer.boundary?(child) }
                @children.each_with_index.to_a
                    .sort_by! { |(child, i)| Layer.sibling_key(self, child, i) }
                    .reverse_each { |(child, _)| yield child }
            else
                @children.reverse_each { |child| yield child }
            end
        end

        # Trigger click event (for testing)
        def trigger_click
            on_click
        end

        # Click event handler (override in subclasses)
        def on_click
            # Default: do nothing
        end

        # Whether this widget claimed the mouse_down for its own purpose
        # (e.g., resize), suppressing DragManager tracking.
        def suppresses_drag? : Bool
            false
        end

        # Right-click callback (set by caller, dispatched from on_mouse_down)
        property on_right_click_handler : Proc(Vec2, Nil)? = nil

        # Hover text shown in statusbar when mouse is over this widget
        property hover_text : String? = nil

        # Mouse event handlers (override in subclasses for drag support)
        def on_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left)
            # Bring containing panel to front if inside one
            bring_containing_panel_to_front
            # `point` is in MY space; the handler is handed window coordinates (trigger_right_click).
            trigger_right_click(to_window(point)) if button == MouseButton::Right
        end

        # Run the nearest right-click handler at or above this widget, handing it `at` - a WINDOW
        # point: a right-click handler exists to put something on the SCREEN (embrace hangs its
        # context menus off this). on_mouse_down calls it for a real right-click; the test Driver
        # calls it for a right-click by id, at the widget's centre. Returns whether a handler ran.
        def trigger_right_click(at : Vec2 = viewport_bounds.center) : Bool
            current : Widget? = self
            while current
                if handler = current.on_right_click_handler
                    handler.call(at)
                    return true
                end
                current = current.parent
            end
            false
        end

        def on_mouse_move(point : Vec2)
            # Default: do nothing
        end

        def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
            # Default: do nothing
        end

        # Preferred cursor when hovering this widget (override in subclasses)
        # Return nil to use default Arrow cursor
        def preferred_cursor(point : Vec2) : CursorType?
            nil
        end

        def on_mouse_enter
            # Default: do nothing
        end

        def on_mouse_exit
            # Default: do nothing
        end

        # === FOCUS AND KEYBOARD INPUT ===

        # Check if widget can receive keyboard focus
        # Override in focusable widgets (TextInput, etc.)
        def focusable? : Bool
            false
        end

        # Whether a mouse press on this widget moves the keyboard focus to it (App#handle_mouse_down).
        # Focusable widgets do by default; Button and Checkbox can opt out (focus_on_click).
        def takes_focus_on_click? : Bool
            focusable?
        end

        # Whether Enter and Space, with this widget focused, press it - before its panel's shortcuts (a dialog's
        # Enter = Ok). A button, a checkbox, a tab or section header: what Tab reached is what Enter acts on.
        def takes_activation_keys? : Bool
            false
        end

        # Called when widget gains keyboard focus. Scrolling it into view is FocusManager#focus's, not this hook's:
        # a keyboard handed back to a panel must not move what the user left there.
        def on_focus
        end

        # Ask the nearest ScrollView above to bring this widget into view
        def scroll_into_view
            current = @parent
            while current
                if current.responds_to?(:scroll_to_visible)
                    current.scroll_to_visible(self)
                    break
                end
                current = current.parent
            end
        end

        # Called when widget loses keyboard focus
        def on_blur
            # Default: do nothing
        end

        # Handle key down event
        # Returns true if event was handled
        def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
            false  # Not handled
        end

        # Handle text input (printable characters)
        def on_text_input(char : Char)
            # Default: do nothing
        end

        # Request keyboard focus for this widget
        def request_focus
            return unless focusable?
            Widget.focus_manager?.try &.focus(self)
        end

        # Release keyboard focus (if this widget has it)
        def release_focus
            if fm = Widget.focus_manager?
                fm.clear_focus if fm.focused?(self)
            end
        end

        # Check if this widget has keyboard focus
        def focused? : Bool
            Widget.focus_manager?.try(&.focused?(self)) || false
        end

        # === PROXY FOCUS ===
        #
        # Proxy focus lets a parent container (e.g. VirtualMatrix) delegate focus
        # visuals and keyboard events to a child widget without giving it real
        # FocusManager focus. The container stays focused (owns grid navigation)
        # but forwards events to the proxy-focused child.
        #
        # **Widget contract for cells/children:**
        # - `focusable?` → return true so the container knows this widget can
        #   accept proxy focus
        # - `activate_proxy_focus` / `deactivate_proxy_focus` → override for
        #   setup/teardown (e.g. TextInput starts/stops cursor blink)
        # - `effectively_focused?` → returns true when either real-focused or
        #   proxy-focused; use this for rendering decisions (cursor, highlight)
        # - `wants_arrow_keys?` → return true to consume arrow keys (TextInput
        #   FullEdit mode), return false to let the container handle grid nav
        #   (TextInput QuickEntry mode)
        #
        # **Event forwarding rules (in VirtualMatrix):**
        # - Enter, Escape, Backspace, Delete, Home, End → always forwarded
        # - Arrow keys → forwarded only if `wants_arrow_keys?` returns true
        # - Tab → not forwarded; the matrix consumes it to round-robin its cell
        #   cursor (spreadsheet semantics) and stays focused. A focus-scope grid
        #   that consumes Tab is a keyboard focus trap BY DESIGN — Ctrl+Tab
        #   (panel cycling) is the intended escape hatch, so don't "fix" the
        #   missing Tab-order leak.
        #   The complement (overlay cell-editors): a cell editor that opens an
        #   overlay and steals real focus (e.g. ComboBox's dropdown TextInput) is
        #   NOT a proxy, so this forwarding doesn't apply — instead it must commit
        #   and re-dispatch Tab back to its focus-scope ancestor itself (see
        #   ComboBox#wire_popup_tab_callback), so Tab never escapes the matrix.
        # - Text input → always forwarded
        #
        # **Default behavior:** The base Widget implementation works for simple
        # widgets — just sets `@proxy_focused` bool and calls `mark_needs_render`.
        # Only override for special behavior (e.g. TextInput cursor blink).

        # Whether this widget has proxy focus (parent container delegates focus visuals)
        property proxy_focused : Bool = false

        # True if widget has real focus OR proxy focus (use for rendering decisions)
        def effectively_focused? : Bool
          focused? || @proxy_focused
        end

        # True if this widget renders its own text caret when (effectively) focused,
        # so a container's cursor-cell flash would just compete with it. VirtualMatrix
        # suppresses its whole-cell flash on cursor cells that return true.
        def draws_edit_caret? : Bool
          false
        end

        # Called by parent container to activate proxy focus on this widget.
        # Override for setup (e.g. TextInput starts cursor blink).
        def activate_proxy_focus
          @proxy_focused = true
          mark_needs_render
        end

        # Called by parent container to deactivate proxy focus on this widget.
        # Override for teardown (e.g. TextInput stops cursor blink).
        def deactivate_proxy_focus
          @proxy_focused = false
          mark_needs_render
        end

        # Whether this widget defines a focus scope boundary.
        # FocusCycler won't recurse into children of focus scope widgets.
        def is_focus_scope? : Bool
          false
        end

        # Whether this widget currently wants to consume arrow keys.
        # Used by proxy focus containers to decide whether to forward arrows
        # or handle grid navigation.
        def wants_arrow_keys? : Bool
          false
        end

        # === END PROXY FOCUS ===

        # === END FOCUS AND KEYBOARD INPUT ===

        # Find and bring to front any WindowPanel ancestor. Public because a mouse-down does it for
        # every button, and the test Driver does it for every act by id. Starts at the parent, so
        # a WindowPanel does not raise itself here.
        def bring_containing_panel_to_front
            current = @parent
            while current
                if current.is_a?(WindowPanel)
                    current.as(WindowPanel).bring_to_front
                    return
                end
                current = current.parent
            end
        end


        # Schedule a timer callback
        # delay: how long to wait before firing
        # repeating: if true, timer repeats every delay interval
        # Returns timer ID that can be used to cancel
        def schedule_timer(delay : Time::Span, repeating : Bool = false, &block : -> Nil) : Int32
            Widget.scheduler.schedule(delay, repeating, &block)
        end

        # Cancel a scheduled timer
        def cancel_timer(timer_id : Int32)
            Widget.scheduler.cancel(timer_id)
        end

        # Find widget by ID in this subtree
        def find_by_id(target_id : String) : Widget?
            return self if @id == target_id

            @children.each do |child|
                if found = child.find_by_id(target_id)
                    return found
                end
            end

            nil
        end

        # Find widget by path ID in this subtree
        def find_by_path(target_path : String) : Widget?
            return self if path_id == target_path

            @children.each do |child|
                if found = child.find_by_path(target_path)
                    return found
                end
            end

            nil
        end

        # Find all widgets matching predicate
        def find_all(&block : Widget -> Bool) : Array(Widget)
            results = [] of Widget
            results << self if yield self

            @children.each do |child|
                results.concat(child.find_all(&block))
            end

            results
        end

        # Find all WindowPanel widgets reachable from this subtree — an O(#panels × depth)
        # registry scan (WindowPanel.@@all_panels), not a tree walk. `self` is the root argument
        # (widget_in_tree? walks a candidate panel's parent chain looking for `self`).
        def find_all_panels : Array(WindowPanel)
            WindowPanel.all_in_tree(self)
        end

        # The nearest WindowPanel above this widget (itself excluded); nil in the window body or a popup
        def find_panel : WindowPanel?
            current = @parent
            while current
                return current.as(WindowPanel) if current.is_a?(WindowPanel)
                current = current.parent
            end
            nil
        end

        # The children the user sees - what Tab and the arrows walk into. A container that keeps hidden children
        # (a collapsed TreeNode, the inactive pages of Tabs) answers only the shown ones.
        def shown_children : Array(Widget)
            @children
        end

        # Find ancestor Window
        def find_window : Window?
            current = @parent
            while current
                return current.as(Window) if current.is_a?(Window)
                current = current.parent
            end
            nil
        end

        # Find the topmost (highest z_index) non-closed WindowPanel in this subtree
        def find_topmost_panel : WindowPanel?
            panels = find_all_panels.reject(&.closed)
            return nil if panels.empty?
            panels.max_by(&.z_index)
        end

        # Find all Popup widgets reachable from this subtree — an O(#popups × depth) registry
        # scan (Popup.@@all_popups), not a tree walk. Also finds Window overlay popups (added via
        # Window#add_overlay, which sets popup.parent = window directly rather than adding it to
        # @children) since widget_in_tree? follows the parent chain regardless of how it got set.
        def find_all_popups : Array(Popup)
            Popup.all_in_tree(self)
        end

        # === LAYER OWNER NOTIFICATION BROADCASTING ===
        # These methods broadcast notifications to all LayerOwner descendants.
        # Used by WindowPanel to notify ScrollView (and other layer owners) of
        # size changes and raises without direct type coupling.
        # Position changes are handled by pull-based bounds (compute_bounds_for_layer).

        # Tell every LayerOwner descendant its panel was raised
        protected def notify_layer_owners_raised
          @children.each do |child|
            child.on_ancestor_raised if child.responds_to?(:on_ancestor_raised)
            child.notify_layer_owners_raised
          end
        end

        # Clear render state recursively
        def clear_render_state_recursive
            Widget.increment_state_sweep_visits # perf-audit: bump once per node visited
            @state = WidgetState::Clean
            @children.each(&.clear_render_state_recursive)
        end

        # Reset all render-related caches (for graceful degradation recovery)
        # Clears: cached_primitives, widget_backend, background_backend
        # Used when exception occurs mid-frame and caches may be corrupted
        def reset_render_caches_recursive
            @cached_primitives = nil
            @primitives_node.try(&.touch)
            free_own_surfaces
            @children.each(&.reset_render_caches_recursive)
        end

        # Give up the pointer to a background handed to a reconciled twin. Drops the REFERENCE
        # only — the adopting widget now owns the object. Protected so only reconcile can call it.
        protected def relinquish_background_backend : Nil
            @background_backend = nil
        end

        # Dispose the pull-cache node(s) this widget owns — unregistering them from the global Sources
        # (theme/zoom) their recompute captured, and dropping the enqueue closure that held this widget.
        # The OVERRIDE SEAM: the base owns @primitives_node (the sole pull node today); a subclass that
        # owns another (e.g. a future KeyedCached buffer that reads zoom) overrides as `super` + disposes
        # its own. Contract: every pull node a widget owns is released here. Does NOT touch
        # @background_backend (carried into the new tree by copy_state_from) or focus/parent. A widget released
        # this way may be shown again (a grid cell handed back): get_primitives then mints a fresh node.
        def dispose_pull_nodes
            @primitives_node.try(&.dispose)
            @primitives_node = nil
        end

        # Release a whole DISCARDED subtree: its pull nodes, its backend REFERENCES, and its own
        # parent/child links. Called on old_root after a rebuild and on a dropped overlay.
        #
        # Two distinct reasons, both load-bearing:
        #  (1) pull nodes — the immortal global Sources (theme/zoom) stop pinning the dead generation;
        #  (2) links + backend refs — Boehm scans CONSERVATIVELY, so one stale word that merely looks
        #      like a pointer pins one node; and because a generation is a densely-linked graph in
        #      which every rendered widget holds a multi-megabyte backend, that single false positive
        #      would otherwise keep the WHOLE generation resident. Severing the graph makes a false
        #      positive cost ONE node instead of the entire tree. (Measured on embrace, THIS variant:
        #      live backends after closing 16 shapes 1737 -> 331, orphaned-but-alive 1573 -> 167,
        #      per-cycle heap floor climb ~240 MB -> ~150 MB. It is a large term, NOT the whole
        #      report: the remaining climb is a separate defect — see the backlog.)
        #
        # It destroys only what this widget alone OWNS (release_own, below): `copy_state_from`
        # TRANSFERS @background_backend to the reconciled widget rather than sharing it, so what is
        # still held here is this widget's own. Recurse BEFORE clearing @children, or the walk loses
        # its own subtree.
        #
        # @parent is deliberately KEPT. Clearing the DOWNWARD links is what breaks the cascade (a
        # retained node would otherwise pin every descendant and every descendant's backend); an
        # upward chain pins only a bounded ancestor path. Severing it is also actively wrong, but
        # via THIS call site, not the rebuild one: Window#cleanup_orphaned_overlays calls
        # dispose_subtree on a dropped overlay while deliberately KEEPING its parent, because focus
        # and find_window walk that chain. (The rebuild walk at App#rebuild can never reach an
        # overlay at all — overlays live in Window@overlays, never in @children, and
        # Window#copy_state_from re-points a migrated overlay's parent to the NEW window.)
        # Guarded by spec/widgets/combo_box_reconcile_focus_spec.cr.
        def dispose_subtree
            release_own
            @children.each(&.dispose_subtree)
            @children.clear
        end

        # What this widget HOLDS for the tree it was shown in, let go of, its structure left intact: its pull
        # node (the subscription to the global zoom/theme Sources - get_primitives re-creates it lazily), its own
        # surfaces, and its slot stamp in the layer it stood on. A widget shown again - a grid cell an adapter
        # hands back - renders afresh.
        def release_own : Nil
            dispose_pull_nodes
            free_own_surfaces
            invalidate_slot
        end

        # The same for this whole subtree (a grid cell that left).
        def release_subtree : Nil
            release_own
            @children.each(&.release_subtree)
        end

        # Every widget of this subtree releases its surfaces (free_own_surfaces), keeping its pull node and slot:
        # each re-captures its background and re-renders at its next paint (a fitted's factor change).
        def free_subtree_surfaces : Nil
            free_own_surfaces
            @children.each(&.free_subtree_surfaces)
        end

        # This widget's own GPU surfaces, RELEASED, not just unlinked: under SFML the payload is a driver
        # texture the collector cannot see, so dropping the pointer frees nothing at all. Both are unshared
        # by construction, which is what makes releasing them safe: copy_state_from deliberately never
        # carries @widget_backend, and it TRANSFERS @background_backend (adopt + relinquish) rather than
        # copying it - so anything still held here was never adopted and this widget is its only owner.
        # Through the SETTERS, which release them and reset the rendered-at-bounds bookkeeping (invariant h):
        # a widget that is shown again - a grid cell an adapter hands back - renders afresh.
        def free_own_surfaces : Nil
            self.widget_backend = nil
            self.background_backend = nil
        end

        # Every layer of this subtree: the layer each widget owns, the ones it owns besides (a ScrollView's
        # scrollbar layers), and its descendants'.
        def each_layer_in_subtree(&block : Layer ->) : Nil
            layer.try { |owned| block.call(owned) }
            me = self
            me.each_owned_layer { |owned| block.call(owned) } if me.responds_to?(:each_owned_layer)
            @children.each { |child| child.each_layer_in_subtree(&block) }
        end

        # Debug: print widget tree
        def dump_tree(indent : Int32 = 0)
            prefix = "  " * indent
            puts "#{prefix}#{self.class.name} (id: #{@id || "nil"}, path: #{path_id})"
            @children.each { |child| child.dump_tree(indent + 1) }
        end

        # Default inspect for readable spec output (can be overridden by subclasses)
        def inspect(io : IO)
            io << "#{self.class.name}(id=#{@id.inspect}, bounds=#{@bounds})"
        end
    end
end

require "./composite_order" # Layer.sibling_key (children_in_hit_order)
