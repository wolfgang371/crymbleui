require "../core/widget"
require "../core/types"
require "../core/font_sizing"
require "../dsl/primitive_builder"
require "./text_input"
require "./combo_box_popup"
require "./popup_host"

module CrymbleUI
  # MultiComboBox widget — multi-select dropdown via `selected : Set(Int32)`.
  #
  # The Set overload of `combo_box(items, selected: Set{...})` in the DSL
  # builds this widget.  The single-select `ComboBox` is entirely untouched.
  #
  # ## Interaction contract
  # - Clicking a row's ✓ gutter TOGGLES membership and KEEPS the popup open.
  # - Clicking the row body selects-only-that item and CLOSES the popup.
  # - The tristate header selects all / none (over ALL items, not just filtered).
  # - The callback is `(new_selection : Set(Int32)) -> Nil` — handed the COMPLETE new
  #   selection after any change. The app just stores it; there are no per-item deltas
  #   to re-apply (a delta sequence can't round-trip through an app that re-seeds a
  #   default when the selection momentarily empties — the real-world bug this fixes).
  #
  # ## Set-reconcile contract (load-bearing)
  # The constructor does `Source.new(selected.dup)` AND `@_build_selected = selected.dup`
  # (two independent value-snapshots).  This means:
  # - The widget NEVER mutates the app's passed Set.
  # - The build-shadow is a value-copy so `copy_state_from` can detect when the app
  #   actually changed the Set (build value changed) vs when the widget just mutated its
  #   own copy (build value unchanged → preserve widget state via the identity-carried Source).
  #
  class MultiComboBox < Widget
    include PrimitiveBuilder
    include PopupHost

    BORDER_WIDTH = 1.0
    PADDING      = 4.0
    FONT_SCALE   =   0

    @items : Array(String)

    # The selection is a Source(Set(Int32)) CARRIED BY IDENTITY across reconcile: the
    # @[Reconcile] ivar has NO matching @_build_selection shadow (the shadow is named
    # @_build_selected), so auto_copy_reconcile_properties copies the OBJECT
    # unconditionally — the popup items that captured it stay valid across rebuilds.
    # @_build_selected (a plain value-snapshot, NOT reconciled) lets copy_state_from
    # honor build-value-wins: `.set` the carried Source only when the app's build Set
    # actually changed. The widget never mutates the app's Set (both are dups).
    @[::CrymbleUI::Reconcile]
    @selection : Source(Set(Int32))
    @_build_selected : Set(Int32)

    def selected : Set(Int32)
      @selection.get
    end

    def selected=(value : Set(Int32))
      @selection.set(value)
    end

    reconcile_property popup_open : Bool = false

    @explicit_width : Float64?
    @summary : (Set(Int32) -> String)?
    # The host callback: handed the COMPLETE new selection after any change (gutter
    # toggle, select-all, or a body-click select-one). The app just stores it — no
    # per-item deltas to re-apply (which an app with default-seeding can't round-trip).
    @on_change : Proc(Set(Int32), Nil)?

    @current_popup : ComboBoxPopup?
    @expanding : Bool = false
    @was_proxy_focused : Bool = false

    def popup_open? : Bool
      @popup_open
    end

    def current_popup : ComboBoxPopup?
      @current_popup
    end

    def collapsed? : Bool
      !@popup_open
    end

    def focusable? : Bool
      true
    end

    def initialize(
      items : Array(String),
      selected : Set(Int32),
      width : Float64? = nil,
      id : String? = nil,
      summary : (Set(Int32) -> String)? = nil,
      &block : Set(Int32) -> Nil
    )
      super(id: id)
      @items = items
      # Two independent dupes: the Source's live value + the reconcile build-shadow.
      # Neither references the app's Set (the widget never mutates the app's Set).
      @selection = Source(Set(Int32)).new(selected.dup)
      @_build_selected = selected.dup
      @explicit_width = width
      @summary = summary
      @on_change = block
    end

    # No-block twin
    def initialize(
      items : Array(String),
      selected : Set(Int32),
      width : Float64? = nil,
      id : String? = nil,
      summary : (Set(Int32) -> String)? = nil,
    )
      super(id: id)
      @items = items
      @selection = Source(Set(Int32)).new(selected.dup)
      @_build_selected = selected.dup
      @explicit_width = width
      @summary = summary
      @on_change = nil
    end

    def label : String?
      "multi_combo_box"
    end

    # ========== SUMMARY ==========

    # The collapsed-cell label. A custom `summary` proc wins; otherwise the default
    # makes good use of the cell width: nothing → "(none)"; one → just its name; many →
    # "N of M (name, name, …)" with the name list filling `max_width` px (truncated with
    # an ellipsis). `max_width` is the pixel budget for the text (nil in measure, where
    # only the height matters).
    private def summary_text(max_width : Float64? = nil) : String
      if fn = @summary
        return fn.call(selected)
      end
      sel = selected.to_a.sort
      return "(none)" if sel.empty?
      font = FontSizing.calculate_size(FONT_SCALE)
      if sel.size == 1
        name = name_of(sel.first)
        return max_width ? fit_text(name, max_width, font) : name
      end
      base = "#{sel.size} of #{@items.size}"
      return base unless max_width
      budget = max_width - Widget.measure_text("#{base} ()", font).width
      return base if budget <= 0
      "#{base} (#{fit_text(sel.map { |i| name_of(i) }.join(", "), budget, font)})"
    end

    private def name_of(i : Int32) : String
      @items[i]? || "?"
    end

    # `text` if it fits in `budget` px, else trimmed from the end with an ellipsis.
    private def fit_text(text : String, budget : Float64, font_size : Float64) : String
      return text if Widget.measure_text(text, font_size).width <= budget
      s = text
      while !s.empty? && Widget.measure_text("#{s}…", font_size).width > budget
        s = s[0...-1]
      end
      "#{s}…"
    end

    # ========== MEASURE / LAYOUT ==========

    def measure(constraints : BoxConstraints) : Size
      display_text = "»#{summary_text}"
      font_size = FontSizing.calculate_size(FONT_SCALE)
      text_size = Widget.measure_text(display_text, font_size)

      natural_height = text_size.height + (PADDING + BORDER_WIDTH) * 2
      height = natural_height
      max_reasonable = natural_height * 2
      if constraints.min_height == constraints.max_height && constraints.max_height.finite?
        height = Math.min(constraints.max_height, max_reasonable)
      elsif constraints.max_height.finite?
        height = Math.min(height, constraints.max_height)
      end

      width = @explicit_width || constraints.max_width
      width = Math.min(width, constraints.max_width) if constraints.max_width.finite?
      width = 200.0 if !width.finite?

      Size.new(width, height)
    end

    def perform_layout(constraints : BoxConstraints, position : Vec2)
      size = measure(constraints)
      @bounds = Rect.new(position, size)

      if @popup_open && (popup = @current_popup)
        abs = absolute_bounds
        popup_pos = Vec2.new(abs.x, abs.y + abs.height)
        popup.bounds = Rect.new(popup_pos, popup.bounds.size)
      end
    end

    # ========== PRIMITIVES ==========

    def to_primitives(bounds : Rect) : Array(DrawPrimitive)
      font_size = FontSizing.calculate_size(FONT_SCALE)
      # Pixel budget for the summary text: cell width minus padding and the "»" prefix.
      avail = bounds.width - PADDING * 2 - Widget.measure_text("»", font_size).width
      display_text = "»#{summary_text(avail)}"
      local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

      primitives do
        fill_rect(local_bounds, Theme.current.combo_background)
        draw_rect(local_bounds, Theme.current.combo_border)
        content_y = BORDER_WIDTH + PADDING
        content_height = bounds.height - (BORDER_WIDTH + PADDING) * 2
        text_y = content_y + (content_height - font_size) / 2.0
        text_pos = Vec2.new(PADDING, text_y)
        draw_text(display_text, text_pos, Theme.current.combo_text, FONT_SCALE)
      end
    end

    # ========== EVENT HANDLERS ==========

    def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
      expand if collapsed? && button == MouseButton::Left
    end

    def on_blur
      collapse if @popup_open && !@expanding
    end

    def deactivate_proxy_focus
      collapse if @popup_open && !@expanding
      super
    end

    def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
      if collapsed? && (key.return? || key.enter?)
        expand
        return true
      end
      if @popup_open && key == SF::Keyboard::Key::Escape
        collapse
        return true
      end
      false
    end

    # ========== EXPAND / COLLAPSE ==========

    def expand
      return if @popup_open

      popup = ComboBoxPopup.new(
        items: @items,
        selected_index: selected.first? || 0,
        max_height: 200.0
      )

      # Checkable mode: items PULL their checked state from @selection and mutate it on a
      # gutter toggle; the popup signals "changed" and we hand the host the new full set.
      # No push / refresh — the captured rows re-render automatically when @selection changes.
      popup.enable_checkable(@selection, -> { notify_change })

      # Body click selects ONLY that item, then closes.
      popup.on_select = ->(idx : Int32, _val : String) { select_one(idx); collapse }
      popup.on_cancel = -> { collapse }
      popup.on_click_outside_callback = -> { collapse }

      mount_popup(popup)

      mark_needs_render
    end

    # Hand the host the COMPLETE new selection (a defensive dup so it can't alias @selection).
    private def notify_change
      @on_change.try(&.call(selected.dup))
    end

    # Body click: replace the selection with exactly {idx} and notify atomically.
    # (The caller collapses.)
    private def select_one(idx : Int32)
      @selection.set(Set{idx})
      notify_change
    end

    def collapse
      return if collapsed?

      unmount_popup
    end

    # ========== RECONCILE ==========

    def copy_state_from(old_widget : Widget)
      # Carry the @selection Source OBJECT by identity (the @[Reconcile] ivar has no
      # matching @_build_selection shadow → auto_copy copies it unconditionally) +
      # popup_open + background_backend (super).
      auto_copy_reconcile_properties(old_widget)
      super

      return unless old_widget.is_a?(MultiComboBox)
      old = old_widget.as(MultiComboBox)

      # Build-value-wins: if the app changed the build Set, push it onto the SAME
      # (carried) Source — this dirties the popup items that captured it, so they
      # re-render with the new state. No per-item refresh, no provider re-point.
      if @_build_selected != old.@_build_selected
        @selection.set(@_build_selected.dup)
      end

      # Carry the open popup and re-point ONLY the notify/close callbacks to self.
      # Items pull the identity-stable @selection Source — nothing else to re-wire.
      if @popup_open && (popup = old.@current_popup)
        @current_popup = popup
        popup.on_change = -> { notify_change }
        popup.on_select = ->(idx : Int32, _val : String) { select_one(idx); collapse }
        popup.on_cancel = -> { collapse }
        popup.on_click_outside_callback = -> { collapse }
      end
    end
  end
end
