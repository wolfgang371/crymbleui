require "../core/widget"
require "./combo_box_popup"

module CrymbleUI
  # Shared focus-sensitive dropdown popup-host machinery for combo-style widgets.
  #
  # Both `ComboBox` and `MultiComboBox` open a `ComboBoxPopup` as a Window overlay,
  # transfer focus into it while guarding against the resulting on_blur, and restore
  # focus to the owning focus-scope (e.g. a VirtualMatrix) on close. That host logic
  # is identical between them; only the popup *construction + callback wiring* differs.
  #
  # The including widget must declare: @current_popup, @popup_open, @was_proxy_focused,
  # @expanding, @explicit_width.
  module PopupHost
    # Walk up to the nearest focus-scope ancestor (e.g. the VirtualMatrix that owns
    # this cell). The popup's arrow/Tab intercepts re-dispatch navigation keys to it,
    # and collapse returns focus to it. Returns nil for a standalone combo.
    private def focus_scope_ancestor : Widget?
      ancestor = @parent
      while ancestor
        return ancestor if ancestor.is_focus_scope?
        ancestor = ancestor.parent
      end
      nil
    end

    # Y-anchored position for `popup`: directly below the combo cell, or flipped ABOVE it
    # when it would extend past the window's bottom edge. Shared by mount_popup (initial
    # open) and the host's perform_layout (re-layout on rebuild) so the two agree --
    # otherwise a rebuild that keeps the popup open (e.g. a MultiComboBox gutter toggle)
    # re-anchors it below and it visibly jumps.
    private def popup_position(abs : Rect, popup_height : Float64) : Vec2
      popup_y = abs.y + abs.height
      if win = find_window
        popup_y = abs.y - popup_height if popup_y + popup_height > win.bounds.height
      end
      Vec2.new(abs.x, popup_y)
    end

    # Mount an already-constructed-and-wired popup: add it to the Window overlays,
    # record open state, measure + position it (below the cell, flipped above if it
    # would run past the window bottom), lay it out, then transfer focus into its
    # TextInput (guarded so the resulting on_blur doesn't immediately collapse).
    #
    # Does NOT call mark_needs_render — callers do that last (after any initial char).
    private def mount_popup(popup : ComboBoxPopup)
      # Add to Window overlays
      window = find_window
      if window
        window.add_overlay(popup)
      end

      @current_popup = popup
      self.popup_open = true # setter — ComboBox's popup_open is a reactive Source (t029)

      # Lay out and position the popup immediately.
      # The overlay system (Window.perform_layout) would lay it out on the
      # next frame, but we need valid bounds NOW so it's visible and interactive.
      abs = absolute_bounds
      min_width = @explicit_width || abs.width
      # Measure unconstrained to get natural width, then ensure at least cell width
      natural_size = popup.measure(BoxConstraints.loose(Size.new(Float64::INFINITY, 200.0)))
      popup_width = {min_width, natural_size.width}.max
      popup.explicit_width = popup_width
      popup_constraints = BoxConstraints.loose(Size.new(popup_width, 200.0))
      popup_size = popup.measure(popup_constraints)

      # Position below the combo, flipped above if it would run past the window bottom.
      popup.layout(popup_constraints, popup_position(abs, popup_size.height))

      # Remember proxy focus state before focus transfer clears it
      @was_proxy_focused = @proxy_focused

      # Focus TextInput inside popup (guard to prevent on_blur from closing)
      @expanding = true
      popup.focus_text_input
      @expanding = false
    end

    # Tear down the current popup: stop its flash timer, remove it from the Window
    # overlays, clear open state, and restore focus to the focus-scope ancestor (if
    # we were proxy-focused when it opened) or to self (standalone usage).
    private def unmount_popup
      if popup = @current_popup
        # Stop flash timer before removing popup
        popup.stop_highlight_flash
        if window = find_window
          window.remove_overlay(popup)
        end
      end
      @current_popup = nil
      self.popup_open = false # setter — ComboBox's popup_open is a reactive Source (t029)

      # Return focus to focus-scope ancestor (VirtualMatrix) if we were proxy-focused
      # when the popup opened, otherwise return focus to self (standalone usage).
      # We check @was_proxy_focused (saved in mount_popup) because by now on_blur →
      # clear_proxy_focus has already reset @proxy_focused to false.
      if @was_proxy_focused
        @was_proxy_focused = false
        if scope = focus_scope_ancestor
          scope.request_focus
        end
      else
        request_focus
      end
      mark_needs_render
    end
  end
end
