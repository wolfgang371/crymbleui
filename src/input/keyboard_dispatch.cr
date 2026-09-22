require "../csfml3/wrapper"
require "../core/app"
require "../core/font_sizing"
require "../core/input_log"
require "../rendering/render_debug"
require "./focus_manager"
require "./shortcut_manager"

module CrymbleUI
  # Routes SFML's keyboard events — KeyPressed, KeyReleased and TextEntered — to zoom, panel
  # cycling, focus and shortcuts. It lives apart from SFMLRenderer so a spec can feed it the SAME
  # LibCSFML::Event values the run loop polls, without opening a window: the helpers in
  # gui_test_helpers call FocusManager directly and so never exercise this translation.
  #
  # MODIFIERS COME FROM THE EVENT STREAM, NEVER FROM THE LIVE KEYBOARD. The loop drains SFML's queue
  # between frames, so under a burst (a script typing, or just a slow frame) the keyboard has moved on
  # by the time a queued event is handled. Asking `SF::Keyboard.key_pressed?` there answered for a
  # LATER keystroke: plain text queued before a Ctrl chord was dropped whole whenever the chord was
  # being held at drain time, while Tab (whose KeyEvent carries its own flags) kept navigating — cells
  # came out empty with the cursor still in step (AutoHotkey into embrace, 2026-09-22).
  class KeyboardDispatch
    # Cost of the most recently rendered frame, stamped by the renderer for InputLog.
    property last_frame_ms : Float64 = 0.0

    # Held modifiers as of the last key event dispatched. Every TextEntered follows the KeyPressed
    # that produced it, so for text this is exactly that keystroke's chord.
    getter? control = false
    getter? alt = false
    getter? shift = false

    def initialize(@focus_manager : FocusManager, @shortcut_manager : ShortcutManager)
    end

    # Returns true if the event requires a redraw.
    def handle(event : LibCSFML::Event, app : App) : Bool
      case event.type
      when SF::Event::KeyPressed
        observe(event.key, down: true)
        key_pressed(event.key, app)
      when SF::Event::KeyReleased
        observe(event.key, down: false)
        false
      when SF::Event::FocusLost
        # Releases that happen while another window has focus never reach us.
        @control = @alt = @shift = false
        false
      when SF::Event::TextEntered
        text_entered(event.text.unicode.chr, app)
      else
        false
      end
    end

    # A key event's flags give the modifier state around it, but for a modifier key's OWN event X11
    # reports the state BEFORE it (Ctrl's press says control=false, its release control=true), so
    # the key itself decides its own flag.
    private def observe(key : SF::Event::KeyEvent, down : Bool) : Nil
      @control = key.control
      @alt = key.alt
      @shift = key.shift
      case key.code
      when SF::Keyboard::LControl, SF::Keyboard::RControl then @control = down
      when SF::Keyboard::LAlt, SF::Keyboard::RAlt         then @alt = down
      when SF::Keyboard::LShift, SF::Keyboard::RShift     then @shift = down
      end
    end

    private def text_entered(char : Char, app : App) : Bool
      # Ctrl+Alt is AltGr on Windows ('@', '{', '€' on a German layout): that is text, not a chord.
      if @control && !@alt
        # Check for Ctrl++ / Ctrl+- for zoom (works on all keyboard layouts)
        case char
        when '+', '='
          FontSizing.zoom_in
          return true
        when '-'
          FontSizing.zoom_out
          return true
        end
        # Filter ALL text when Ctrl is pressed (Ctrl+key combos shouldn't insert text)
        # This prevents Ctrl+0 from inserting '0', Ctrl+S from inserting 's', etc.
        # Traced, because a wrong chord decision is exactly a silent drop.
        if InputLog.enabled?
          InputLog.record("chord", char.ord < 32 ? "^#{(char.ord + 64).chr}" : char.to_s, false,
            @focus_manager.focused_widget, app.needs_rebuild?, @last_frame_ms)
        end
        return true
      end
      # Dispatch text input to focused widget
      # Filter control characters (< 32) except for specific cases
      # Also filter DEL (127)
      if char.ord >= 32 && char.ord != 127
        InputLog.next_in_batch if InputLog.enabled?
        _outcome = @focus_manager.handle_text_input(char)
        if InputLog.enabled?
          InputLog.record("text", char.to_s, _outcome.is_a?(Bool) ? _outcome : nil,
            @focus_manager.focused_widget, app.needs_rebuild?, @last_frame_ms)
        end
      end
      true # Redraw for text input
    end

    private def key_pressed(key : SF::Event::KeyEvent, app : App) : Bool
      if InputLog.enabled?
        InputLog.record("key", key.code.to_s, nil, @focus_manager.focused_widget,
          app.needs_rebuild?, @last_frame_ms)
      end
      # Global zoom shortcuts - numpad +/- and Ctrl+0 for reset
      # Note: Regular keyboard +/- is handled via TextEntered for keyboard layout compatibility
      if key.control
        case key.code
        when SF::Keyboard::Add # numpad +
          FontSizing.zoom_in
          return true
        when SF::Keyboard::Subtract # numpad -
          FontSizing.zoom_out
          return true
        when SF::Keyboard::Num0, SF::Keyboard::Numpad0 # 0 = reset zoom
          FontSizing.reset_zoom
          return true
        when SF::Keyboard::M # Ctrl+M = toggle maximize on topmost panel
          if !key.alt && !key.shift
            if panel = app.root.try(&.find_topmost_panel)
              panel.toggle_maximize
            end
            return true
          end
        when SF::Keyboard::Tab # Ctrl+Tab / Ctrl+Shift+Tab = cycle panels
          if root = app.root
            @focus_manager.cycle_panel(forward: !key.shift, root: root)
          end
          return true
        when SF::Keyboard::D # Ctrl+Shift+D = dump render state (dev diagnostic)
          if key.shift
            if root = app.root
              RenderDebug.dump(root)
              puts "[render dump] /tmp/render_dump/ — #{Layer.active_layers(root).size} layers (PNG per layer + report.txt)"
            end
            return true
          end
        end
      end

      # ESC key: panel shortcuts first (dialog close), then app-level (drags, menus)
      if key.code == SF::Keyboard::Escape
        active_panel = app.root.try(&.find_topmost_panel)
        if active_panel && @shortcut_manager.handle_key_event(key, active_panel)
          return true
        end
        if app.handle_escape
          return true
        end
      end

      # Tab/Shift+Tab: the focused widget gets first dibs (a focus scope like
      # VirtualMatrix round-robins its cell cursor and stays focused); only
      # if it declines do we cycle focus to the next/previous widget.
      if key.code == SF::Keyboard::Tab
        if root = app.root
          @focus_manager.handle_tab_key(key.shift, root)
        end
        return true
      end

      # For Enter/Space, check topmost panel shortcuts first
      # (dialog confirm/cancel takes priority over widget focus)
      if key.code == SF::Keyboard::Enter || key.code == SF::Keyboard::Space
        active_panel = app.root.try(&.find_topmost_panel)
        if active_panel && @shortcut_manager.handle_key_event(key, active_panel)
          return true
        end
      end

      # Route the key through the SHARED dispatcher: focused widget first, then
      # spatial focus navigation on a declined arrow (skipped under Alt). This is
      # the exact same path FocusManager#dispatch_key gives the headless tester,
      # so the two cannot drift (a drift here is what hid the ComboBox arrow
      # focus-escape from the suite).
      root = app.root
      handled = if root
                  @focus_manager.dispatch_key(key.code, key.control, key.shift, key.alt, root)
                else
                  @focus_manager.handle_key_down(key.code, key.control, key.shift, key.alt)
                end

      # Activation keys (Enter/Space) are handled here — dispatch_key only does
      # focus movement (arrows), not activation. Skip when Alt is held.
      unless handled || key.alt
        case key.code
        when SF::Keyboard::Enter, SF::Keyboard::Space
          # Activate focused widget (button click, checkbox toggle)
          key_sym = key.code == SF::Keyboard::Enter ? :enter : :space
          @focus_manager.handle_activation_key(key_sym)
          handled = true
        end
      end

      # If still not handled, try keyboard shortcuts
      unless handled
        active_panel = app.root.try(&.find_topmost_panel)
        @shortcut_manager.handle_key_event(key, active_panel)
      end
      true # Redraw for key events
    end
  end
end
