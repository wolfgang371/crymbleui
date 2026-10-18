require "../core/widget"
require "./focus_navigator"
require "./focus_cycler"
require "./focus_flash_controller"

module CrymbleUI
  # Manages keyboard focus for widgets. Only one widget can be focused at a time.
  #
  # THE PANEL IN FRONT HOLDS THE KEYBOARD. A panel raised at event time (a press in it or on its title bar,
  # Ctrl+Tab) is entered: the keyboard goes to the widget that last held it there, else the panel's home widget,
  # else its first Tab stop, else nobody - unless it is already inside. Tab, Shift+Tab and the arrows move among the
  # Tab stops of the keyboard's panel; from nobody they enter the front panel. App opens panels and hands the
  # keyboard on when its panel closes (App#settle_keyboard). See docs/LAYER_RENDERING_ARCHITECTURE.md "Keyboard and
  # panels".
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

    # Focus a widget (or clear focus with nil): on_blur on the old one, on_focus on the new one, the flash moves.
    # `reveal` scrolls the new one into view; a keyboard handed back to a panel does not (it must not move what
    # the user left there).
    def focus(widget : Widget?, reveal : Bool = true)
      old = @focused_widget
      return if old == widget

      remember(old, widget)
      @flash_controller.stop_flash(old)
      old.try &.on_blur
      return unless @focused_widget == old # on_blur moved the keyboard itself

      @focused_widget = widget
      if w = widget
        w.on_focus
        w.scroll_into_view if reveal
        @flash_controller.start_flash(w)
      end
    end

    # The keyboard leaves a panel: it records the widget that held it there, for the next time it enters.
    private def remember(old : Widget?, new : Widget?) : Nil
      return unless (o = old) && (panel = o.find_panel)
      return if panel.same?(new.try(&.find_panel))
      panel.last_focus_id = o.id
    end

    # The panel the keyboard moves in: the focused widget's, the front one when nobody holds the keyboard or its
    # holder sits in a closed panel; nil when it is in the window body or a popup.
    def keyboard_panel(root : Widget) : WindowPanel?
      w = @focused_widget
      return root.find_topmost_panel if w.nil? || in_closed_panel?(w) # keyboard_nowhere?, spelled out to narrow w
      w.find_panel
    end

    # Nobody holds the keyboard, or its holder sits in a closed panel - as good as nobody.
    private def keyboard_nowhere? : Bool
      w = @focused_widget
      w.nil? || in_closed_panel?(w)
    end

    private def in_closed_panel?(widget : Widget) : Bool
      panel = widget.find_panel
      while panel
        return true if panel.closed
        panel = panel.find_panel
      end
      false
    end

    # Hand the keyboard to `panel`, unless it is already inside: the widget that last held it there, else the
    # panel's home widget, else its first Tab stop, else nobody. Callers pass live panels (a raised one, the front
    # one) - a replaced instance would hand the keyboard to an orphan.
    def enter(panel : WindowPanel) : Nil
      return if panel.closed
      return if !keyboard_nowhere? && @focused_widget.try(&.widget_in_tree?(panel))
      stops = @cycler.collect_focusable_widgets(panel)
      focus(stop(stops, panel.last_focus_id) || stop(stops, panel.home_focus_id) || stops.first?, reveal: false)
    end

    private def stop(stops : Array(Widget), id : String?) : Widget?
      id.try { |i| stops.find { |w| w.id == i } }
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

    # Reconcile focus after a rebuild. A reconciled widget already had focus
    # carried over by transfer_focus; but a widget that was REMOVED (no
    # counterpart in the new tree — e.g. a closed dialog) leaves @focused_widget
    # dangling on an orphan. An orphan still receives keys (handle_key_down sends
    # to @focused_widget regardless of attachment), so a stale TextInput would
    # swallow Alt+Left and the panel shortcut would never fire until the user
    # clicked back in. Drop focus when the focused widget is no longer in `root`, or sits
    # in a closed panel. True when the dropped keyboard was in a panel: the panel now in
    # front takes it (App#settle_keyboard).
    def reconcile_focus(root : Widget) : Bool
      return false unless w = @focused_widget
      return false if w.widget_in_tree?(root) && !in_closed_panel?(w)
      clear_focus
      !w.find_panel.nil?
    end

    # === FOCUS CYCLING (Tab / Shift+Tab) ===

    # Tab (forward) / Shift+Tab: the next Tab stop of the keyboard's panel - of the window body when the keyboard
    # is there. From nobody, the front panel is entered instead.
    def cycle_focus(forward : Bool, root : Widget)
      return if enter_from_nobody(root)
      focusables = @cycler.collect_focusable_widgets(keyboard_panel(root) || root)
      return if focusables.empty?

      next_widget = @cycler.find_next(
        current: @focused_widget,
        focusables: focusables,
        forward: forward
      )

      focus(next_widget) if next_widget
    end

    # Nobody holds the keyboard (or its holder's panel closed) and a panel is open: enter the front one.
    private def enter_from_nobody(root : Widget) : Bool
      return false unless keyboard_nowhere?
      return false unless front = root.find_topmost_panel
      enter(front)
      true
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

    # Navigate focus in spatial direction, among the Tab stops of the keyboard's panel (or the window body's)
    def navigate(direction : Symbol, root : Widget)
      return if enter_from_nobody(root)
      return unless current = @focused_widget

      focusables = @cycler.collect_focusable_widgets(keyboard_panel(root) || root)

      target = @navigator.find_neighbor(current, focusables, direction)
      focus(target) if target
    end

    # === ACTIVATION (Enter / Space) ===

    # Handle Enter/Space activation of focused widget
    def handle_activation_key(key : Symbol)
      @focused_widget.try &.trigger_click
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

    # One typed character to the widget holding the keyboard, traced as typing (InputLog) - the one text path:
    # real keystrokes (KeyboardDispatch) and text typed from code (type_text) both take it.
    def type_char(char : Char, app : App, frame_ms : Float64 = 0.0) : Nil
      InputLog.next_in_batch if InputLog.enabled?
      outcome = handle_text_input(char)
      if InputLog.enabled?
        InputLog.record("text", char.to_s, outcome.is_a?(Bool) ? outcome : nil, @focused_widget, app.needs_rebuild?, frame_ms)
      end
    end

    # Text typed from code as a user types it (an app's "insert today's date"): each character through type_char.
    # A character whose handling makes input wait for a rebuilt frame (App#input_waits_for_frame?) ends it - real
    # input would wait, then land on a tree the caller never saw; the rest is not typed.
    def type_text(text : String, app : App) : Nil
      text.each_char do |char|
        break if app.input_waits_for_frame?
        type_char(char, app)
      end
    end

    # === PANEL CYCLING (Ctrl+Tab / Ctrl+Shift+Tab) ===

    # Rotate the open panels in z-order; the raised one takes the keyboard (bring_to_front enters it). Forward
    # (Ctrl+Tab) raises the bottom panel; backward (Ctrl+Shift+Tab), the true reverse, sends the front one to the
    # back and raises the one beneath. One open panel is raised - from the window body or from nobody, Ctrl+Tab is
    # the way into it. Returns the raised panel, nil when none is open.
    def cycle_panel(forward : Bool, root : Widget) : WindowPanel?
      panels = root.find_all_panels.reject(&.closed).sort_by(&.z_index)
      return nil if panels.empty?
      target = if forward || panels.size == 1
                 panels.first
               else
                 panels.last.send_to_back
                 panels[-2]
               end
      target.bring_to_front
      target
    end
  end
end
