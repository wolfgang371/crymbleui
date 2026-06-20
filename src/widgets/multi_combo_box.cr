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
  # - The callback is `(index : Int32, now_on : Bool) -> Nil`.
  #   The app is responsible for producing the new Set and passing it on rebuild.
  #
  # ## Set-reconcile contract (load-bearing)
  # The constructor does `@selected = selected.dup` AND `@_build_selected = selected.dup`
  # (two independent value-snapshots).  This means:
  # - The widget NEVER mutates the app's passed Set.
  # - The build-shadow is a value-copy so `auto_copy_reconcile_properties` can detect
  #   when the app actually changed the Set (build value changed) vs when the widget
  #   just mutated its own copy (build value unchanged → preserve widget state).
  #
  class MultiComboBox < Widget
    include PrimitiveBuilder
    include PopupHost

    BORDER_WIDTH = 1.0
    PADDING      = 4.0
    FONT_SCALE = 0

    @items : Array(String)

    # The reconcile_property macro generates @_build_selected but does NOT dup.
    # We handle the dup manually in initialize + copy_state_from.
    @[::CrymbleUI::Reconcile]
    @selected : Set(Int32)
    @_build_selected : Set(Int32)

    def selected : Set(Int32)
      @selected
    end

    def selected=(value : Set(Int32))
      @selected = value
    end

    reconcile_property popup_open : Bool = false

    @explicit_width : Float64?
    @summary : (Set(Int32) -> String)?
    @on_toggle : Proc(Int32, Bool, Nil)?

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
      &block : Int32, Bool -> Nil
    )
      super(id: id)
      @items = items
      # Two independent dupes: one for the widget's live state, one for the
      # reconcile build-shadow.  Neither references the app's Set.
      @selected = selected.dup
      @_build_selected = selected.dup
      @explicit_width = width
      @summary = summary
      @on_toggle = block
    end

    # No-block twin
    def initialize(
      items : Array(String),
      selected : Set(Int32),
      width : Float64? = nil,
      id : String? = nil,
      summary : (Set(Int32) -> String)? = nil
    )
      super(id: id)
      @items = items
      @selected = selected.dup
      @_build_selected = selected.dup
      @explicit_width = width
      @summary = summary
      @on_toggle = nil
    end

    def label : String?
      "multi_combo_box"
    end

    # ========== SUMMARY ==========

    private def summary_text : String
      if fn = @summary
        fn.call(@selected)
      else
        n = @selected.size
        "#{n} of #{@items.size}"
      end
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
      display_text = "»#{summary_text}"
      local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

      primitives do
        fill_rect(local_bounds, Theme.current.combo_background)
        draw_rect(local_bounds, Theme.current.combo_border)
        font_size = FontSizing.calculate_size(FONT_SCALE)
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
        selected_index: @selected.first? || 0,
        max_height: 200.0
      )

      # Enable checkable mode: provide current checked state
      sel = @selected
      popup.checked_provider = ->(idx : Int32) { sel.includes?(idx) }

      # Toggle (gutter click): update Set + keep popup open
      popup.on_toggle = ->(idx : Int32) {
        was_on = @selected.includes?(idx)
        now_on = !was_on
        if now_on
          @selected = @selected.dup << idx
        else
          @selected = @selected.dup.tap(&.delete(idx))
        end
        @on_toggle.try(&.call(idx, now_on))
        # Refresh popup visuals to show new check state
        popup.checked_provider = ->(i : Int32) { @selected.includes?(i) }
        popup.refresh_checked_states
        mark_needs_render
      }

      # Toggle-all (header click): flip all indices
      popup.on_toggle_all = ->(new_all : Bool) {
        if new_all
          all_set = Set(Int32).new
          @items.each_index { |i| all_set << i }
          @selected = all_set
          @items.each_index { |i| @on_toggle.try(&.call(i, true)) }
        else
          old_sel = @selected.dup
          @selected = Set(Int32).new
          old_sel.each { |i| @on_toggle.try(&.call(i, false)) }
        end
        popup.checked_provider = ->(i : Int32) { @selected.includes?(i) }
        popup.refresh_checked_states
        mark_needs_render
      }

      # Select-one (body click): replace set with single item + close
      popup.on_select = ->(idx : Int32, _val : String) {
        old_sel = @selected.dup
        @selected = Set{idx}
        # Fire toggle-off for every previously-on item (except the new selection)
        old_sel.each do |i|
          @on_toggle.try(&.call(i, false)) unless i == idx
        end
        # Fire toggle-on for the new selection if it wasn't already on
        @on_toggle.try(&.call(idx, true)) unless old_sel.includes?(idx)
        collapse
      }

      popup.on_cancel = -> { collapse }
      popup.on_click_outside_callback = -> { collapse }

      mount_popup(popup)

      mark_needs_render
    end

    def collapse
      return if collapsed?

      unmount_popup
    end

    # ========== RECONCILE ==========

    def copy_state_from(old_widget : Widget)
      # Manually handle the Set reconcile with dup-discipline:
      # Only preserve widget state if the build-time Set didn't change.
      if old_widget.is_a?(MultiComboBox)
        old = old_widget.as(MultiComboBox)

        # Reconcile selected: if the app didn't change the build value, keep widget's live state
        if @_build_selected == old.@_build_selected
          @selected = old.@selected.dup
        end
        # (If they differ, @selected was already set from the new build value in initialize)
      end

      # Let base handle popup_open + other @[Reconcile] props + background_backend
      auto_copy_reconcile_properties(old_widget)
      super

      return unless old_widget.is_a?(MultiComboBox)
      old = old_widget.as(MultiComboBox)

      # Re-wire popup callbacks to THIS instance
      if @popup_open && (popup = old.@current_popup)
        @current_popup = popup

        # Update the provider WITHOUT rebuilding items — items already have valid
        # layout/bounds from when they were built in expand(). The toggle handler
        # already called refresh_checked_states before the rebuild, so item states
        # are current. We only update the closure so future toggles use the new
        # @selected reference.
        popup.update_checked_provider(->(idx : Int32) { @selected.includes?(idx) })

        popup.on_toggle = ->(idx : Int32) {
          was_on = @selected.includes?(idx)
          now_on = !was_on
          if now_on
            @selected = @selected.dup << idx
          else
            @selected = @selected.dup.tap(&.delete(idx))
          end
          @on_toggle.try(&.call(idx, now_on))
          popup.update_checked_provider(->(i : Int32) { @selected.includes?(i) })
          popup.refresh_checked_states
          mark_needs_render
        }

        popup.on_toggle_all = ->(new_all : Bool) {
          if new_all
            all_set2 = Set(Int32).new
            @items.each_index { |i| all_set2 << i }
            @selected = all_set2
            @items.each_index { |i| @on_toggle.try(&.call(i, true)) }
          else
            old_sel = @selected.dup
            @selected = Set(Int32).new
            old_sel.each { |i| @on_toggle.try(&.call(i, false)) }
          end
          popup.update_checked_provider(->(i : Int32) { @selected.includes?(i) })
          popup.refresh_checked_states
          mark_needs_render
        }

        popup.on_select = ->(idx : Int32, _val : String) {
          old_sel = @selected.dup
          @selected = Set{idx}
          old_sel.each do |i|
            @on_toggle.try(&.call(i, false)) unless i == idx
          end
          @on_toggle.try(&.call(idx, true)) unless old_sel.includes?(idx)
          collapse
        }

        popup.on_cancel = -> { collapse }
        popup.on_click_outside_callback = -> { collapse }
      end
    end

  end
end
