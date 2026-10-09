require "../csfml3/wrapper"
require "../core/app"

module CrymbleUI
  # Routes SFML's mouse button and move events to the App - the one path both renderers take, so a spec
  # feeding the SAME LibCSFML::Event values (TestRenderer#deliver) meets what the run loop does. (A
  # press's focus is App#handle_mouse_down's, so every path to a press gets it.) The cursor SHAPE is not
  # here: it needs the window, so each renderer updates it where `cursor_point` says.
  class MouseDispatch
    def mouse_event?(event : LibCSFML::Event) : Bool
      event.type.mouse_button_pressed? || event.type.mouse_button_released? || event.type.mouse_moved?
    end

    # Returns true if the event itself asks for a redraw (a hover change); button events leave that to
    # the caller, as the run loop always redraws after them.
    def handle(event : LibCSFML::Event, app : App) : Bool
      case event.type
      when .mouse_button_pressed?
        press(app, point(event.mouse_button.position), button(event.mouse_button.button))
        false
      when .mouse_button_released?
        release(app, point(event.mouse_button.position), button(event.mouse_button.button))
        false
      when .mouse_moved?
        move(app, point(event.mouse_move.position))
      else
        raise ArgumentError.new("MouseDispatch takes mouse button and move events, got #{event.type}")
      end
    end

    def press(app : App, at : Vec2, button : MouseButton = MouseButton::Left) : Nil
      app.handle_mouse_down(at, button)
    end

    def release(app : App, at : Vec2, button : MouseButton = MouseButton::Left) : Nil
      app.handle_mouse_up(at, button)
    end

    # A move drags while a button is down, else updates the hover. True when the hover changed.
    def move(app : App, at : Vec2) : Bool
      return app.handle_mouse_move(at) if app.mouse_down?
      app.update_hover(at)
    end

    # Where the run loop updates the cursor shape after this event, or nil: after every release (a
    # sticky resize cursor otherwise stays), and after a move that did not drag.
    def cursor_point(event : LibCSFML::Event, app : App) : Vec2?
      if event.type.mouse_button_released?
        point(event.mouse_button.position)
      elsif event.type.mouse_moved? && cursor_after_move?(app)
        point(event.mouse_move.position)
      end
    end

    def cursor_after_move?(app : App) : Bool
      !app.mouse_down?
    end

    private def point(position : LibCSFML::Vector2i) : Vec2
      Vec2.new(position.x.to_f64, position.y.to_f64)
    end

    private def button(button : LibCSFML::MouseButton) : MouseButton
      case button
      when LibCSFML::MouseButton::Right  then MouseButton::Right
      when LibCSFML::MouseButton::Middle then MouseButton::Middle
      else                                    MouseButton::Left
      end
    end
  end
end
