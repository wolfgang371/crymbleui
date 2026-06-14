require "../core/widget"
require "./focus_navigator"
require "./focus_cycler"
require "./focus_flash_controller"

module CrymbleUI
  # Manages keyboard focus for widgets
  # Only one widget can be focused at a time
  class FocusManager
    # Currently focused widget (nil = no focus)
    @focused_widget : Widget? = nil

    # Navigation components
    @navigator : FocusNavigator
    @cycler : FocusCycler
    @flash_controller : FocusFlashController

    def initialize
      @navigator = FocusNavigator.new
      @cycler = FocusCycler.new
      @flash_controller = FocusFlashController.new
    end

    # Get currently focused widget
    def focused_widget : Widget?
      @focused_widget
    end

    # Focus a widget (or clear focus with nil)
    # Calls on_blur on old widget, on_focus on new widget
    # Also manages flash animation
    def focus(widget : Widget?)
      return if @focused_widget == widget

      # Stop flash on old widget
      @flash_controller.stop_flash(@focused_widget)

      # Blur old widget
      @focused_widget.try &.on_blur

      # Focus new widget
      @focused_widget = widget
      widget.try &.on_focus

      # Start flash on new widget
      widget.try { |w| @flash_controller.start_flash(w) }
    end

    # Check if a specific widget has focus
    def focused?(widget : Widget) : Bool
      @focused_widget == widget
    end

    # Clear focus (blur current widget)
    def clear_focus
      focus(nil)
    end

    # Transfer focus from old widget to new widget without triggering callbacks
    # Used during reconciliation when widget instances are replaced
    # The new widget should already have state copied from old widget
    def transfer_focus(old_widget : Widget, new_widget : Widget)
      return unless @focused_widget == old_widget
      @focused_widget = new_widget
      # Also transfer the flash controller's widget reference
      # so flash toggle continues on the new widget (not the orphaned old one)
      @flash_controller.transfer_widget(old_widget, new_widget)
    end

    # === FOCUS CYCLING (Tab / Shift+Tab) ===

    # Cycle focus through focusable widgets in tab order
    # forward=true for Tab, forward=false for Shift+Tab
    def cycle_focus(forward : Bool, root : Widget)
      focusables = @cycler.collect_focusable_widgets(root)
      return if focusables.empty?

      next_widget = @cycler.find_next(
        current: @focused_widget,
        focusables: focusables,
        forward: forward
      )

      focus(next_widget) if next_widget
    end

    # Tab / Shift+Tab dispatch. The focused widget gets first dibs: a focus
    # scope that owns its own tab semantics (e.g. VirtualMatrix round-robins
    # its cell cursor) consumes Tab and stays focused. Only if the widget
    # declines do we cycle focus to the next/previous widget in tab order.
    # This mirrors the arrow-key dispatch (focused widget first, then a
    # fallback) and is the single source of truth for Tab — both the SFML
    # renderer and the headless tester route Tab through here.
    def handle_tab_key(shift : Bool, root : Widget) : Bool
      if (w = @focused_widget) && w.on_key_down(SF::Keyboard::Key::Tab, false, shift)
        return true
      end
      cycle_focus(forward: !shift, root: root)
      true
    end

    # === SPATIAL NAVIGATION (Arrow keys) ===

    # Shared key dispatch — the SINGLE source of truth for how an arrow key is
    # routed, so the SFML renderer and the headless tester can't drift (the
    # ComboBox arrow focus-escape was invisible to specs precisely because the
    # headless path skipped the navigate-on-decline step the renderer does).
    # Sends the key to the focused widget; if it declines an arrow (and Alt is
    # not held), falls back to spatial focus navigation. Returns whether handled.
    def dispatch_key(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool, root : Widget) : Bool
      handled = handle_key_down(key, control, shift, alt)
      return handled if handled || alt
      dir = case key
            when SF::Keyboard::Key::Up    then :up
            when SF::Keyboard::Key::Down  then :down
            when SF::Keyboard::Key::Left  then :left
            when SF::Keyboard::Key::Right then :right
            end
      if dir
        navigate(dir, root)
        return true
      end
      false
    end

    # Navigate focus in spatial direction
    def navigate(direction : Symbol, root : Widget)
      return unless current = @focused_widget

      focusables = @cycler.collect_focusable_widgets(root)

      target = @navigator.find_neighbor(current, focusables, direction)
      focus(target) if target
    end

    # === ACTIVATION (Enter / Space) ===

    # Handle Enter/Space activation of focused widget
    def handle_activation_key(key : Symbol)
      widget = @focused_widget
      return unless widget

      # Try to trigger click if widget responds to it
      if widget.responds_to?(:trigger_click)
        widget.trigger_click
      end
    end

    # === KEY DISPATCH ===

    # Handle key event - dispatch to focused widget
    # Returns true if event was handled
    def handle_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
      if widget = @focused_widget
        widget.on_key_down(key, control, shift, alt)
      else
        false
      end
    end

    # Handle text input - dispatch to focused widget
    def handle_text_input(char : Char)
      @focused_widget.try &.on_text_input(char)
    end

    # === PANEL CYCLING (Ctrl+Tab / Ctrl+Shift+Tab) ===

    # Cycle through panels (WindowPanels) in z-order
    # forward=true for Ctrl+Tab, forward=false for Ctrl+Shift+Tab
    # Returns the panel that was activated, or nil if no valid target
    def cycle_panel(forward : Bool, root : Widget) : WindowPanel?
      # Get all non-closed panels
      panels = root.find_all_panels.reject(&.closed)
      return nil if panels.size < 2  # Need at least 2 panels to cycle

      # Sort by z_index (ascending: lowest first)
      sorted = panels.sort_by(&.z_index)

      # Find current topmost panel
      current = sorted.last  # Highest z_index is topmost

      # Find index of current panel
      current_index = sorted.index(current)
      return nil unless current_index

      # Calculate target index
      # Panels form a cycle: [z=1, z=2, z=3, ...] with topmost at the end
      # Forward (Ctrl+Tab): cycle to NEXT in order (higher index wraps to 0)
      # Backward (Ctrl+Shift+Tab): cycle to PREVIOUS in order (lower index)
      target_index = if forward
                       # Forward: next in cycle (wrap to beginning)
                       (current_index + 1) % sorted.size
                     else
                       # Backward: previous in cycle (wrap to end)
                       (current_index - 1 + sorted.size) % sorted.size
                     end

      target = sorted[target_index]

      # Bring target panel to front
      target.bring_to_front

      target
    end
  end
end
