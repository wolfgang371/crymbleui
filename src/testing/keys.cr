require "../csfml3/wrapper"

module CrymbleUI
  module Testing
    # Builds the keyboard and mouse events SFML queues, for TestRenderer#deliver: a spec says what was
    # typed or clicked, and gets the event sequence the run loop would poll for it.
    module Keys
      alias Event = LibCSFML::Event

      def self.key(type : LibCSFML::EventType, code : SF::Keyboard::Key,
                   control = false, alt = false, shift = false) : Event
        event = Event.new
        event.key = LibCSFML::KeyEvent.new(type: type, code: code, scancode: 0,
          alt: alt, control: control, shift: shift, system: false)
        event
      end

      def self.text(char : Char) : Event
        event = Event.new
        event.text = LibCSFML::TextEvent.new(type: LibCSFML::EventType::TextEntered, unicode: char.ord.to_u32)
        event
      end

      # Plain typing: each character's press, then the text it produced.
      def self.typed(text : String) : Array(Event)
        text.chars.flat_map { |c| [pressed(SF::Keyboard::Key::Unknown), text(c)] }
      end

      def self.pressed(code : SF::Keyboard::Key, control = false, alt = false, shift = false) : Event
        key(LibCSFML::EventType::KeyPressed, code, control, alt, shift)
      end

      def self.released(code : SF::Keyboard::Key, control = false, alt = false, shift = false) : Event
        key(LibCSFML::EventType::KeyReleased, code, control, alt, shift)
      end

      # A non-text key tapped on its own (Tab, arrows, Enter).
      def self.tap(code : SF::Keyboard::Key, shift = false) : Array(Event)
        [pressed(code, shift: shift)]
      end

      # The mouse as SFML queues it, in window pixels.
      def self.press_at(x : Int32, y : Int32, button = LibCSFML::MouseButton::Left) : Event
        mouse_button(LibCSFML::EventType::MouseButtonPressed, x, y, button)
      end

      def self.release_at(x : Int32, y : Int32, button = LibCSFML::MouseButton::Left) : Event
        mouse_button(LibCSFML::EventType::MouseButtonReleased, x, y, button)
      end

      def self.move_to(x : Int32, y : Int32) : Event
        event = Event.new
        event.mouse_move = LibCSFML::MouseMoveEvent.new(type: LibCSFML::EventType::MouseMoved,
          position: LibCSFML::Vector2i.new(x: x, y: y))
        event
      end

      # A click: the press and the release at one point.
      def self.click_at(x : Int32, y : Int32) : Array(Event)
        [press_at(x, y), release_at(x, y)]
      end

      private def self.mouse_button(type : LibCSFML::EventType, x : Int32, y : Int32, button : LibCSFML::MouseButton) : Event
        event = Event.new
        event.mouse_button = LibCSFML::MouseButtonEvent.new(type: type, button: button,
          position: LibCSFML::Vector2i.new(x: x, y: y))
        event
      end

      # Ctrl+<letter> as queued: Ctrl down, the key, the control character it produces, both up.
      def self.ctrl(code : SF::Keyboard::Key) : Array(Event)
        letter = code.value - SF::Keyboard::Key::A.value
        raise ArgumentError.new("Keys.ctrl takes a letter key, got #{code}") unless (0...26).includes?(letter)
        [pressed(SF::Keyboard::Key::LControl, control: true), pressed(code, control: true),
         text((letter + 1).chr), released(code, control: true),
         released(SF::Keyboard::Key::LControl, control: true)]
      end
    end
  end
end
