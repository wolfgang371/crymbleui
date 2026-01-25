# CSFML 3.0 Wrapper Module
# Provides an SF:: namespace API similar to CrSFML for easier migration
# Wraps LibCSFML C functions in Crystal classes

require "./lib"

# Add convenience methods to LibCSFML::KeyCode for CrSFML compatibility
enum LibCSFML::KeyCode
  # CrSFML uses `return?` for Enter key
  def return?
    self == Enter
  end

  def enter?
    self == Enter
  end

  def escape?
    self == Escape
  end

  def backspace?
    self == Backspace
  end

  def tab?
    self == Tab
  end

  def delete?
    self == Delete
  end

  def home?
    self == Home
  end

  def end?
    self == End
  end

  def left?
    self == Left
  end

  def right?
    self == Right
  end

  def up?
    self == Up
  end

  def down?
    self == Down
  end

  def space?
    self == Space
  end
end

module SF
  # ============================================================
  # Helper functions (CrSFML compatibility)
  # ============================================================

  def self.vector2i(x : Number, y : Number) : Vector2i
    Vector2i.new(x.to_i32, y.to_i32)
  end

  def self.vector2f(x : Number, y : Number) : Vector2f
    Vector2f.new(x.to_f32, y.to_f32)
  end

  def self.vector2u(x : Number, y : Number) : Vector2u
    Vector2u.new(x.to_u32, y.to_u32)
  end

  def self.int_rect(left : Number, top : Number, width : Number, height : Number) : IntRect
    IntRect.new(left.to_i32, top.to_i32, width.to_i32, height.to_i32)
  end

  def self.float_rect(left : Number, top : Number, width : Number, height : Number) : FloatRect
    FloatRect.new(left.to_f32, top.to_f32, width.to_f32, height.to_f32)
  end

  # ============================================================
  # Basic Types
  # ============================================================

  struct Vector2i
    property x : Int32
    property y : Int32

    def initialize(@x : Int32, @y : Int32)
    end

    def initialize(x : Number, y : Number)
      @x = x.to_i32
      @y = y.to_i32
    end

    def to_csfml_i : LibCSFML::Vector2i
      LibCSFML::Vector2i.new(x: @x, y: @y)
    end
  end

  struct Vector2u
    property x : UInt32
    property y : UInt32

    def initialize(@x : UInt32, @y : UInt32)
    end

    def initialize(x : Number, y : Number)
      @x = x.to_u32
      @y = y.to_u32
    end

    def to_csfml_u : LibCSFML::Vector2u
      LibCSFML::Vector2u.new(x: @x, y: @y)
    end
  end

  struct Vector2f
    property x : Float32
    property y : Float32

    def initialize(@x : Float32, @y : Float32)
    end

    def initialize(x : Number, y : Number)
      @x = x.to_f32
      @y = y.to_f32
    end

    def to_csfml_f : LibCSFML::Vector2f
      LibCSFML::Vector2f.new(x: @x, y: @y)
    end
  end

  struct Color
    property r : UInt8
    property g : UInt8
    property b : UInt8
    property a : UInt8

    def initialize(@r : UInt8, @g : UInt8, @b : UInt8, @a : UInt8 = 255_u8)
    end

    def initialize(r : Int, g : Int, b : Int, a : Int = 255)
      @r = r.to_u8
      @g = g.to_u8
      @b = b.to_u8
      @a = a.to_u8
    end

    def to_csfml : LibCSFML::Color
      LibCSFML::Color.new(r: @r, g: @g, b: @b, a: @a)
    end

    def self.from_csfml(c : LibCSFML::Color) : Color
      Color.new(c.r, c.g, c.b, c.a)
    end

    # Common colors
    Transparent = Color.new(0_u8, 0_u8, 0_u8, 0_u8)
    White       = Color.new(255_u8, 255_u8, 255_u8)
    Black       = Color.new(0_u8, 0_u8, 0_u8)
    Red         = Color.new(255_u8, 0_u8, 0_u8)
    Green       = Color.new(0_u8, 255_u8, 0_u8)
    Blue        = Color.new(0_u8, 0_u8, 255_u8)
    Yellow      = Color.new(255_u8, 255_u8, 0_u8)
    Magenta     = Color.new(255_u8, 0_u8, 255_u8)
    Cyan        = Color.new(0_u8, 255_u8, 255_u8)
  end

  struct IntRect
    property left : Int32
    property top : Int32
    property width : Int32
    property height : Int32

    def initialize(@left : Int32, @top : Int32, @width : Int32, @height : Int32)
    end

    def to_csfml : LibCSFML::IntRect
      LibCSFML::IntRect.new(
        position: LibCSFML::Vector2i.new(x: @left, y: @top),
        size: LibCSFML::Vector2i.new(x: @width, y: @height)
      )
    end

    def self.from_csfml(r : LibCSFML::IntRect) : IntRect
      IntRect.new(r.position.x, r.position.y, r.size.x, r.size.y)
    end

    def contains?(x : Int32, y : Int32) : Bool
      x >= @left && x < @left + @width && y >= @top && y < @top + @height
    end
  end

  struct FloatRect
    property left : Float32
    property top : Float32
    property width : Float32
    property height : Float32

    def initialize(@left : Float32, @top : Float32, @width : Float32, @height : Float32)
    end

    def initialize(left : Number, top : Number, width : Number, height : Number)
      @left = left.to_f32
      @top = top.to_f32
      @width = width.to_f32
      @height = height.to_f32
    end

    def to_csfml : LibCSFML::FloatRect
      LibCSFML::FloatRect.new(
        position: LibCSFML::Vector2f.new(x: @left, y: @top),
        size: LibCSFML::Vector2f.new(x: @width, y: @height)
      )
    end

    def self.from_csfml(r : LibCSFML::FloatRect) : FloatRect
      FloatRect.new(r.position.x, r.position.y, r.size.x, r.size.y)
    end
  end

  # ============================================================
  # Time
  # ============================================================

  struct Time
    @microseconds : Int64

    def initialize(@microseconds : Int64)
    end

    def as_seconds : Float32
      @microseconds.to_f32 / 1_000_000
    end

    def as_milliseconds : Int32
      (@microseconds / 1000).to_i32
    end

    def as_microseconds : Int64
      @microseconds
    end

    def self.zero : Time
      Time.new(0_i64)
    end
  end

  def self.seconds(amount : Float) : Time
    Time.new((amount * 1_000_000).to_i64)
  end

  def self.milliseconds(amount : Int32) : Time
    Time.new(amount.to_i64 * 1000)
  end

  def self.microseconds(amount : Int64) : Time
    Time.new(amount)
  end

  def self.sleep(duration : Time)
    LibCSFML.sfSleep(duration.as_microseconds)
  end

  # ============================================================
  # Keyboard
  # ============================================================

  module Keyboard
    # Type alias for SF::Keyboard::Key (used as type in CrSFML)
    # Allows both `key : SF::Keyboard::Key` and `SF::Keyboard::Key::A`
    alias Key = LibCSFML::KeyCode

    # Key constants - accessible via SF::Keyboard::A, SF::Keyboard::Space, etc.
    {% for key in [:Unknown, :A, :B, :C, :D, :E, :F, :G, :H, :I, :J, :K, :L, :M, :N, :O, :P, :Q, :R, :S, :T, :U, :V, :W, :X, :Y, :Z,
                   :Num0, :Num1, :Num2, :Num3, :Num4, :Num5, :Num6, :Num7, :Num8, :Num9,
                   :Escape, :LControl, :LShift, :LAlt, :LSystem, :RControl, :RShift, :RAlt, :RSystem,
                   :Menu, :LBracket, :RBracket, :Semicolon, :Comma, :Period, :Apostrophe,
                   :Slash, :Backslash, :Grave, :Equal, :Hyphen,
                   :Space, :Enter, :Backspace, :Tab,
                   :PageUp, :PageDown, :End, :Home, :Insert, :Delete,
                   :Add, :Subtract, :Multiply, :Divide,
                   :Left, :Right, :Up, :Down,
                   :Numpad0, :Numpad1, :Numpad2, :Numpad3, :Numpad4, :Numpad5, :Numpad6, :Numpad7, :Numpad8, :Numpad9,
                   :F1, :F2, :F3, :F4, :F5, :F6, :F7, :F8, :F9, :F10, :F11, :F12, :F13, :F14, :F15,
                   :Pause] %}
      {{key.id}} = LibCSFML::KeyCode::{{key.id}}
    {% end %}

    # CrSFML compatibility alias - SFML 3.0 renamed Return to Enter
    Return = Enter

    def self.key_pressed?(key : LibCSFML::KeyCode) : Bool
      LibCSFML.sfKeyboard_isKeyPressed(key)
    end
  end

  # ============================================================
  # Mouse
  # ============================================================

  module Mouse
    Left   = LibCSFML::MouseButton::Left
    Right  = LibCSFML::MouseButton::Right
    Middle = LibCSFML::MouseButton::Middle

    # Mouse wheel enum for compatibility with CrSFML
    module Wheel
      VerticalWheel   = LibCSFML::MouseWheel::Vertical
      HorizontalWheel = LibCSFML::MouseWheel::Horizontal
    end

    def self.button_pressed?(button : LibCSFML::MouseButton) : Bool
      LibCSFML.sfMouse_isButtonPressed(button)
    end

    def self.get_position(relative_to : RenderWindow? = nil) : Vector2i
      if rw = relative_to
        pos = LibCSFML.sfMouse_getPositionRenderWindow(rw.to_unsafe)
      else
        pos = LibCSFML.sfMouse_getPosition(nil)
      end
      Vector2i.new(pos.x, pos.y)
    end
  end

  # ============================================================
  # Clipboard
  # ============================================================

  module Clipboard
    def self.string : String
      String.new(LibCSFML.sfClipboard_getString)
    end

    def self.string=(text : String)
      LibCSFML.sfClipboard_setString(text.to_unsafe)
    end
  end

  # ============================================================
  # Window / VideoMode / ContextSettings
  # ============================================================

  struct VideoMode
    property width : UInt32
    property height : UInt32
    property bits_per_pixel : UInt32

    def initialize(@width : UInt32, @height : UInt32, @bits_per_pixel : UInt32 = 32_u32)
    end

    def self.desktop_mode : VideoMode
      mode = LibCSFML.sfVideoMode_getDesktopMode
      VideoMode.new(mode.size.x, mode.size.y, mode.bits_per_pixel)
    end

    def to_csfml : LibCSFML::VideoMode
      LibCSFML::VideoMode.new(
        size: LibCSFML::Vector2u.new(x: @width, y: @height),
        bits_per_pixel: @bits_per_pixel
      )
    end
  end

  struct ContextSettings
    property depth_bits : UInt32
    property stencil_bits : UInt32
    property antialiasing_level : UInt32
    property major_version : UInt32
    property minor_version : UInt32

    def initialize(
      @depth_bits : UInt32 = 0_u32,
      @stencil_bits : UInt32 = 0_u32,
      @antialiasing_level : UInt32 = 0_u32,
      @major_version : UInt32 = 1_u32,
      @minor_version : UInt32 = 1_u32
    )
    end

    def to_csfml : LibCSFML::ContextSettings
      LibCSFML::ContextSettings.new(
        depth_bits: @depth_bits,
        stencil_bits: @stencil_bits,
        antialiasing_level: @antialiasing_level,
        major_version: @major_version,
        minor_version: @minor_version,
        attribute_flags: 0_u32,
        srgb_capable: false
      )
    end
  end

  # Window styles (flags)
  module Style
    None       = 0_u32
    Titlebar   = 1_u32
    Resize     = 2_u32
    Close      = 4_u32
    Fullscreen = 8_u32
    Default    = Titlebar | Resize | Close
  end

  # ============================================================
  # Event
  # ============================================================

  # Event type constants for compatibility with CrSFML code
  module Event
    Closed              = LibCSFML::EventType::Closed
    Resized             = LibCSFML::EventType::Resized
    FocusLost           = LibCSFML::EventType::FocusLost
    FocusGained         = LibCSFML::EventType::FocusGained
    TextEntered         = LibCSFML::EventType::TextEntered
    KeyPressed          = LibCSFML::EventType::KeyPressed
    KeyReleased         = LibCSFML::EventType::KeyReleased
    MouseWheelScrolled  = LibCSFML::EventType::MouseWheelScrolled
    MouseButtonPressed  = LibCSFML::EventType::MouseButtonPressed
    MouseButtonReleased = LibCSFML::EventType::MouseButtonReleased
    MouseMoved          = LibCSFML::EventType::MouseMoved
    MouseEntered        = LibCSFML::EventType::MouseEntered
    MouseLeft           = LibCSFML::EventType::MouseLeft

    # Type alias for compatibility with CrSFML's SF::Event::KeyEvent
    alias KeyEvent = LibCSFML::KeyEvent

    # KeyPressedEvent is an alias to LibCSFML::KeyEvent for CrSFML compatibility
    # Use KeyPressedEvent.new instead of KeyPressed.new for mock events
    alias KeyPressedEvent = LibCSFML::KeyEvent
  end

  # Event data union for poll_event
  alias EventData = LibCSFML::Event

  # ============================================================
  # Font
  # ============================================================

  class Font
    @handle : LibCSFML::Font

    def initialize(filename : String)
      @handle = LibCSFML.sfFont_createFromFile(filename)
      raise "Failed to load font: #{filename}" if @handle.null?
    end

    def initialize(@handle : LibCSFML::Font)
    end

    # CrSFML compatibility: load font from file
    def self.from_file(filename : String) : Font
      handle = LibCSFML.sfFont_createFromFile(filename)
      raise "Failed to load font: #{filename}" if handle.null?
      new(handle)
    end

    # CrSFML compatibility: load font from memory
    def self.from_memory(data : Slice(UInt8)) : Font
      handle = LibCSFML.sfFont_createFromMemory(data.to_unsafe, data.size)
      raise "Failed to load font from memory" if handle.null?
      new(handle)
    end

    def get_kerning(first : UInt32, second : UInt32, character_size : UInt32) : Float32
      LibCSFML.sfFont_getKerning(@handle, first, second, character_size)
    end

    def get_line_spacing(character_size : UInt32) : Float32
      LibCSFML.sfFont_getLineSpacing(@handle, character_size)
    end

    # Get glyph for a character (used for pre-populating glyph cache)
    # Returns pointer to glyph data (we don't need the actual value, just trigger loading)
    def get_glyph(code_point : UInt32, character_size : UInt32, bold : Bool, outline_thickness : Float32) : LibCSFML::Glyph
      LibCSFML.sfFont_getGlyph(@handle, code_point, character_size, bold, outline_thickness)
    end

    def to_unsafe : LibCSFML::Font
      @handle
    end

    def finalize
      LibCSFML.sfFont_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # Texture
  # ============================================================

  class Texture
    @handle : LibCSFML::Texture
    @owns : Bool

    def initialize(width : Int, height : Int)
      size = LibCSFML::Vector2u.new(x: width.to_u32, y: height.to_u32)
      @handle = LibCSFML.sfTexture_create(size)
      @owns = true
      raise "Failed to create texture" if @handle.null?
    end

    # Wrap an existing texture (e.g., from RenderTexture.texture)
    def initialize(@handle : LibCSFML::Texture, @owns = false)
    end

    def size : Vector2u
      s = LibCSFML.sfTexture_getSize(@handle)
      Vector2u.new(s.x, s.y)
    end

    def smooth=(smooth : Bool)
      LibCSFML.sfTexture_setSmooth(@handle, smooth)
    end

    def smooth? : Bool
      LibCSFML.sfTexture_isSmooth(@handle)
    end

    # Create texture from image (CrSFML compatibility)
    def self.from_image(image : Image, area : IntRect? = nil) : Texture
      if area
        area_csfml = area.to_csfml
        handle = LibCSFML.sfTexture_createFromImage(image.to_unsafe, pointerof(area_csfml))
      else
        handle = LibCSFML.sfTexture_createFromImage(image.to_unsafe, nil)
      end
      raise "Failed to create texture from image" if handle.null?
      new(handle, owns: true)
    end

    # Copy texture contents to a new image (GPU → CPU)
    def copy_to_image : Image
      handle = LibCSFML.sfTexture_copyToImage(@handle)
      raise "Failed to copy texture to image" if handle.null?
      Image.new(handle)
    end

    def to_unsafe : LibCSFML::Texture
      @handle
    end

    def finalize
      LibCSFML.sfTexture_destroy(@handle) if @owns && !@handle.null?
    end
  end

  # ============================================================
  # Sprite
  # ============================================================

  class Sprite
    @handle : LibCSFML::Sprite

    def initialize(texture : Texture)
      @handle = LibCSFML.sfSprite_create(texture.to_unsafe)
      raise "Failed to create sprite" if @handle.null?
    end

    def position=(pos : Vector2f)
      LibCSFML.sfSprite_setPosition(@handle, pos.to_csfml_f)
    end

    def position : Vector2f
      p = LibCSFML.sfSprite_getPosition(@handle)
      Vector2f.new(p.x, p.y)
    end

    def texture_rect=(rect : IntRect)
      LibCSFML.sfSprite_setTextureRect(@handle, rect.to_csfml)
    end

    def texture_rect : IntRect
      IntRect.from_csfml(LibCSFML.sfSprite_getTextureRect(@handle))
    end

    def set_texture(texture : Texture, reset_rect : Bool = false)
      LibCSFML.sfSprite_setTexture(@handle, texture.to_unsafe, reset_rect)
    end

    def scale=(scale : Vector2f)
      LibCSFML.sfSprite_setScale(@handle, scale.to_csfml_f)
    end

    def color=(color : Color)
      LibCSFML.sfSprite_setColor(@handle, color.to_csfml)
    end

    def global_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfSprite_getGlobalBounds(@handle))
    end

    def to_unsafe : LibCSFML::Sprite
      @handle
    end

    def finalize
      LibCSFML.sfSprite_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # Text
  # ============================================================

  class Text
    @handle : LibCSFML::Text
    @font : Font # Keep reference to prevent GC

    def initialize(@font : Font)
      @handle = LibCSFML.sfText_create(@font.to_unsafe)
      raise "Failed to create text" if @handle.null?
    end

    # SFML 2.x constructor compatibility (string, font, size)
    def initialize(string : String, @font : Font, character_size : Int)
      @handle = LibCSFML.sfText_create(@font.to_unsafe)
      raise "Failed to create text" if @handle.null?
      self.string = string
      self.character_size = character_size.to_u32
    end

    def string=(str : String)
      # Use Unicode string for proper UTF-8 support
      # Convert Crystal String (UTF-8) to UTF-32 codepoints for SFML
      codepoints = str.codepoints.map(&.to_u32)
      codepoints << 0_u32  # Null terminator
      LibCSFML.sfText_setUnicodeString(@handle, codepoints.to_unsafe)
    end

    def string : String
      String.new(LibCSFML.sfText_getString(@handle))
    end

    def character_size=(size : UInt32)
      LibCSFML.sfText_setCharacterSize(@handle, size)
    end

    def character_size : UInt32
      LibCSFML.sfText_getCharacterSize(@handle)
    end

    def position=(pos : Vector2f)
      LibCSFML.sfText_setPosition(@handle, pos.to_csfml_f)
    end

    def position : Vector2f
      p = LibCSFML.sfText_getPosition(@handle)
      Vector2f.new(p.x, p.y)
    end

    def fill_color=(color : Color)
      LibCSFML.sfText_setFillColor(@handle, color.to_csfml)
    end

    def outline_color=(color : Color)
      LibCSFML.sfText_setOutlineColor(@handle, color.to_csfml)
    end

    def outline_thickness=(thickness : Float)
      LibCSFML.sfText_setOutlineThickness(@handle, thickness.to_f32)
    end

    def global_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfText_getGlobalBounds(@handle))
    end

    def local_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfText_getLocalBounds(@handle))
    end

    def find_character_pos(index : Int) : Vector2f
      p = LibCSFML.sfText_findCharacterPos(@handle, index.to_u64)
      Vector2f.new(p.x, p.y)
    end

    def to_unsafe : LibCSFML::Text
      @handle
    end

    def finalize
      LibCSFML.sfText_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # RectangleShape
  # ============================================================

  class RectangleShape
    @handle : LibCSFML::RectangleShape

    def initialize(size : Vector2f = Vector2f.new(0, 0))
      @handle = LibCSFML.sfRectangleShape_create
      raise "Failed to create rectangle shape" if @handle.null?
      self.size = size
    end

    def size=(size : Vector2f)
      LibCSFML.sfRectangleShape_setSize(@handle, size.to_csfml_f)
    end

    def size : Vector2f
      s = LibCSFML.sfRectangleShape_getSize(@handle)
      Vector2f.new(s.x, s.y)
    end

    def position=(pos : Vector2f)
      LibCSFML.sfRectangleShape_setPosition(@handle, pos.to_csfml_f)
    end

    def position : Vector2f
      p = LibCSFML.sfRectangleShape_getPosition(@handle)
      Vector2f.new(p.x, p.y)
    end

    def rotation=(angle : Float)
      LibCSFML.sfRectangleShape_setRotation(@handle, angle.to_f32)
    end

    def rotation : Float32
      LibCSFML.sfRectangleShape_getRotation(@handle)
    end

    def fill_color=(color : Color)
      LibCSFML.sfRectangleShape_setFillColor(@handle, color.to_csfml)
    end

    def outline_color=(color : Color)
      LibCSFML.sfRectangleShape_setOutlineColor(@handle, color.to_csfml)
    end

    def outline_thickness=(thickness : Float)
      LibCSFML.sfRectangleShape_setOutlineThickness(@handle, thickness.to_f32)
    end

    def global_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfRectangleShape_getGlobalBounds(@handle))
    end

    def to_unsafe : LibCSFML::RectangleShape
      @handle
    end

    def finalize
      LibCSFML.sfRectangleShape_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # View
  # ============================================================

  class View
    @handle : LibCSFML::View
    @owns : Bool

    def initialize
      @handle = LibCSFML.sfView_create
      @owns = true
      raise "Failed to create view" if @handle.null?
    end

    def initialize(rect : FloatRect)
      @handle = LibCSFML.sfView_createFromRect(rect.to_csfml)
      @owns = true
      raise "Failed to create view" if @handle.null?
    end

    # Wrap an existing view (e.g., from RenderTarget.view)
    def initialize(@handle : LibCSFML::View, @owns = false)
    end

    def center=(center : Vector2f)
      LibCSFML.sfView_setCenter(@handle, center.to_csfml_f)
    end

    def center : Vector2f
      c = LibCSFML.sfView_getCenter(@handle)
      Vector2f.new(c.x, c.y)
    end

    def size=(size : Vector2f)
      LibCSFML.sfView_setSize(@handle, size.to_csfml_f)
    end

    def size : Vector2f
      s = LibCSFML.sfView_getSize(@handle)
      Vector2f.new(s.x, s.y)
    end

    def viewport=(viewport : FloatRect)
      LibCSFML.sfView_setViewport(@handle, viewport.to_csfml)
    end

    def viewport : FloatRect
      FloatRect.from_csfml(LibCSFML.sfView_getViewport(@handle))
    end

    def reset(rect : FloatRect)
      LibCSFML.sfView_reset(@handle, rect.to_csfml)
    end

    def to_unsafe : LibCSFML::View
      @handle
    end

    def finalize
      LibCSFML.sfView_destroy(@handle) if @owns && !@handle.null?
    end
  end

  # ============================================================
  # Image
  # ============================================================

  class Image
    @handle : LibCSFML::Image

    def initialize(width : Int, height : Int, color : Color = Color::Black)
      size = LibCSFML::Vector2u.new(x: width.to_u32, y: height.to_u32)
      @handle = LibCSFML.sfImage_createFromColor(size, color.to_csfml)
      raise "Failed to create image" if @handle.null?
    end

    def initialize(@handle : LibCSFML::Image)
    end

    def size : Vector2u
      s = LibCSFML.sfImage_getSize(@handle)
      Vector2u.new(s.x, s.y)
    end

    def set_pixel(x : Int, y : Int, color : Color)
      coords = LibCSFML::Vector2u.new(x: x.to_u32, y: y.to_u32)
      LibCSFML.sfImage_setPixel(@handle, coords, color.to_csfml)
    end

    def get_pixel(x : Int, y : Int) : Color
      coords = LibCSFML::Vector2u.new(x: x.to_u32, y: y.to_u32)
      Color.from_csfml(LibCSFML.sfImage_getPixel(@handle, coords))
    end

    def pixels_ptr : UInt8*
      LibCSFML.sfImage_getPixelsPtr(@handle)
    end

    def save_to_file(filename : String) : Bool
      LibCSFML.sfImage_saveToFile(@handle, filename)
    end

    def to_unsafe : LibCSFML::Image
      @handle
    end

    def finalize
      LibCSFML.sfImage_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # RenderTexture
  # ============================================================

  class RenderTexture
    @handle : LibCSFML::RenderTexture
    @texture_wrapper : Texture?

    def initialize(width : Int, height : Int, settings : ContextSettings? = nil)
      size = LibCSFML::Vector2u.new(x: width.to_u32, y: height.to_u32)
      if settings
        csfml_settings = settings.to_csfml
        @handle = LibCSFML.sfRenderTexture_create(size, pointerof(csfml_settings))
      else
        @handle = LibCSFML.sfRenderTexture_create(size, nil)
      end
      raise "Failed to create RenderTexture" if @handle.null?
    end

    def size : Vector2u
      s = LibCSFML.sfRenderTexture_getSize(@handle)
      Vector2u.new(s.x, s.y)
    end

    def active=(active : Bool) : Bool
      LibCSFML.sfRenderTexture_setActive(@handle, active)
    end

    def clear(color : Color = Color::Black)
      LibCSFML.sfRenderTexture_clear(@handle, color.to_csfml)
    end

    def display
      LibCSFML.sfRenderTexture_display(@handle)
    end

    def draw(drawable : Sprite, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderTexture_drawSprite(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderTexture_drawSprite(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : Text, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderTexture_drawText(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderTexture_drawText(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : RectangleShape, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderTexture_drawRectangleShape(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderTexture_drawRectangleShape(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : CircleShape, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderTexture_drawCircleShape(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderTexture_drawCircleShape(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : ConvexShape, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderTexture_drawConvexShape(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderTexture_drawConvexShape(@handle, drawable.to_unsafe, nil)
      end
    end

    def texture : Texture
      @texture_wrapper ||= Texture.new(LibCSFML.sfRenderTexture_getTexture(@handle), owns: false)
    end

    def view=(view : View)
      LibCSFML.sfRenderTexture_setView(@handle, view.to_unsafe)
    end

    def view : View
      View.new(LibCSFML.sfRenderTexture_getView(@handle), owns: false)
    end

    def default_view : View
      View.new(LibCSFML.sfRenderTexture_getDefaultView(@handle), owns: false)
    end

    def smooth=(smooth : Bool)
      LibCSFML.sfRenderTexture_setSmooth(@handle, smooth)
    end

    def smooth? : Bool
      LibCSFML.sfRenderTexture_isSmooth(@handle)
    end

    def to_unsafe : LibCSFML::RenderTexture
      @handle
    end

    def finalize
      LibCSFML.sfRenderTexture_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # RenderWindow
  # ============================================================

  class RenderWindow
    @handle : LibCSFML::RenderWindow

    def initialize(mode : VideoMode, title : String, style : UInt32 = Style::Default, settings : ContextSettings? = nil)
      csfml_settings = settings ? settings.to_csfml : ContextSettings.new.to_csfml
      @handle = LibCSFML.sfRenderWindow_create(mode.to_csfml, title, style, pointerof(csfml_settings))
      raise "Failed to create RenderWindow" if @handle.null?
    end

    def open? : Bool
      LibCSFML.sfRenderWindow_isOpen(@handle)
    end

    def close
      LibCSFML.sfRenderWindow_close(@handle)
    end

    def poll_event(event : LibCSFML::Event*) : Bool
      LibCSFML.sfRenderWindow_pollEvent(@handle, event)
    end

    # CrSFML compatibility: poll_event that returns event or nil
    def poll_event : LibCSFML::Event?
      event = LibCSFML::Event.new
      if LibCSFML.sfRenderWindow_pollEvent(@handle, pointerof(event))
        event
      else
        nil
      end
    end

    # CrSFML compatibility: wait_event that blocks and returns event or nil
    # Uses infinite timeout (sfTime_Zero in CSFML 3.0 means infinite wait)
    def wait_event : LibCSFML::Event?
      event = LibCSFML::Event.new
      # CSFML 3.0 waitEvent takes timeout - use 0 for infinite wait
      if LibCSFML.sfRenderWindow_waitEvent(@handle, 0_i64, pointerof(event))
        event
      else
        nil
      end
    end

    def size : Vector2u
      s = LibCSFML.sfRenderWindow_getSize(@handle)
      Vector2u.new(s.x, s.y)
    end

    def size=(size : Vector2u)
      LibCSFML.sfRenderWindow_setSize(@handle, size.to_csfml_u)
    end

    def position : Vector2i
      p = LibCSFML.sfRenderWindow_getPosition(@handle)
      Vector2i.new(p.x, p.y)
    end

    def position=(pos : Vector2i)
      LibCSFML.sfRenderWindow_setPosition(@handle, pos.to_csfml_i)
    end

    def title=(title : String)
      LibCSFML.sfRenderWindow_setTitle(@handle, title)
    end

    def visible=(visible : Bool)
      LibCSFML.sfRenderWindow_setVisible(@handle, visible)
    end

    def vertical_sync_enabled=(enabled : Bool)
      LibCSFML.sfRenderWindow_setVerticalSyncEnabled(@handle, enabled)
    end

    def mouse_cursor_visible=(visible : Bool)
      LibCSFML.sfRenderWindow_setMouseCursorVisible(@handle, visible)
    end

    def key_repeat_enabled=(enabled : Bool)
      LibCSFML.sfRenderWindow_setKeyRepeatEnabled(@handle, enabled)
    end

    def framerate_limit=(limit : Int)
      LibCSFML.sfRenderWindow_setFramerateLimit(@handle, limit.to_u32)
    end

    def active=(active : Bool) : Bool
      LibCSFML.sfRenderWindow_setActive(@handle, active)
    end

    def request_focus
      LibCSFML.sfRenderWindow_requestFocus(@handle)
    end

    def has_focus? : Bool
      LibCSFML.sfRenderWindow_hasFocus(@handle)
    end

    def display
      LibCSFML.sfRenderWindow_display(@handle)
    end

    def clear(color : Color = Color::Black)
      LibCSFML.sfRenderWindow_clear(@handle, color.to_csfml)
    end

    def draw(drawable : Sprite, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderWindow_drawSprite(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderWindow_drawSprite(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : Text, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderWindow_drawText(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderWindow_drawText(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : RectangleShape, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderWindow_drawRectangleShape(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderWindow_drawRectangleShape(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : CircleShape, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderWindow_drawCircleShape(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderWindow_drawCircleShape(@handle, drawable.to_unsafe, nil)
      end
    end

    def draw(drawable : ConvexShape, states : RenderStates? = nil)
      if states
        csfml_states = states.to_csfml
        LibCSFML.sfRenderWindow_drawConvexShape(@handle, drawable.to_unsafe, pointerof(csfml_states))
      else
        LibCSFML.sfRenderWindow_drawConvexShape(@handle, drawable.to_unsafe, nil)
      end
    end

    def mouse_cursor=(cursor : Cursor)
      LibCSFML.sfRenderWindow_setMouseCursor(@handle, cursor.to_unsafe)
    end

    def view=(view : View)
      LibCSFML.sfRenderWindow_setView(@handle, view.to_unsafe)
    end

    def view : View
      View.new(LibCSFML.sfRenderWindow_getView(@handle), owns: false)
    end

    def default_view : View
      View.new(LibCSFML.sfRenderWindow_getDefaultView(@handle), owns: false)
    end

    def to_unsafe : LibCSFML::RenderWindow
      @handle
    end

    def finalize
      LibCSFML.sfRenderWindow_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # RenderTarget
  # ============================================================

  # Type alias for CrSFML compatibility - allows accepting either RenderWindow or RenderTexture
  alias RenderTarget = RenderWindow | RenderTexture

  # ============================================================
  # BlendMode
  # ============================================================

  # BlendMode struct for controlling pixel blending
  struct BlendMode
    property color_src_factor : LibCSFML::BlendFactor
    property color_dst_factor : LibCSFML::BlendFactor
    property color_equation : LibCSFML::BlendEquation
    property alpha_src_factor : LibCSFML::BlendFactor
    property alpha_dst_factor : LibCSFML::BlendFactor
    property alpha_equation : LibCSFML::BlendEquation

    def initialize(
      @color_src_factor : LibCSFML::BlendFactor = LibCSFML::BlendFactor::SrcAlpha,
      @color_dst_factor : LibCSFML::BlendFactor = LibCSFML::BlendFactor::OneMinusSrcAlpha,
      @color_equation : LibCSFML::BlendEquation = LibCSFML::BlendEquation::Add,
      @alpha_src_factor : LibCSFML::BlendFactor = LibCSFML::BlendFactor::One,
      @alpha_dst_factor : LibCSFML::BlendFactor = LibCSFML::BlendFactor::OneMinusSrcAlpha,
      @alpha_equation : LibCSFML::BlendEquation = LibCSFML::BlendEquation::Add
    )
    end

    def to_csfml : LibCSFML::BlendMode
      LibCSFML::BlendMode.new(
        color_src_factor: @color_src_factor,
        color_dst_factor: @color_dst_factor,
        color_equation: @color_equation,
        alpha_src_factor: @alpha_src_factor,
        alpha_dst_factor: @alpha_dst_factor,
        alpha_equation: @alpha_equation
      )
    end
  end

  # Standard blend modes - compatible with SF::BlendAlpha, SF::BlendNone etc
  BlendAlpha = BlendMode.new(
    LibCSFML::BlendFactor::SrcAlpha,
    LibCSFML::BlendFactor::OneMinusSrcAlpha,
    LibCSFML::BlendEquation::Add,
    LibCSFML::BlendFactor::One,
    LibCSFML::BlendFactor::OneMinusSrcAlpha,
    LibCSFML::BlendEquation::Add
  )

  BlendAdd = BlendMode.new(
    LibCSFML::BlendFactor::SrcAlpha,
    LibCSFML::BlendFactor::One,
    LibCSFML::BlendEquation::Add,
    LibCSFML::BlendFactor::One,
    LibCSFML::BlendFactor::One,
    LibCSFML::BlendEquation::Add
  )

  BlendMultiply = BlendMode.new(
    LibCSFML::BlendFactor::DstColor,
    LibCSFML::BlendFactor::Zero,
    LibCSFML::BlendEquation::Add,
    LibCSFML::BlendFactor::DstColor,
    LibCSFML::BlendFactor::Zero,
    LibCSFML::BlendEquation::Add
  )

  # CRITICAL: BlendNone - overwrites destination pixels completely (no blending)
  # Used for widget background restoration where transparent pixels must replace existing content
  BlendNone = BlendMode.new(
    LibCSFML::BlendFactor::One,
    LibCSFML::BlendFactor::Zero,
    LibCSFML::BlendEquation::Add,
    LibCSFML::BlendFactor::One,
    LibCSFML::BlendFactor::Zero,
    LibCSFML::BlendEquation::Add
  )

  # ============================================================
  # RenderStates
  # ============================================================

  class RenderStates
    property blend_mode : BlendMode

    def initialize(@blend_mode : BlendMode = BlendAlpha)
    end

    Default = RenderStates.new(BlendAlpha)

    # Identity transform (3x3 matrix)
    private def identity_transform : LibCSFML::Transform
      # Identity matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1]
      matrix = StaticArray(LibC::Float, 9).new(0_f32)
      matrix[0] = 1_f32  # a00
      matrix[4] = 1_f32  # a11
      matrix[8] = 1_f32  # a22
      LibCSFML::Transform.new(matrix: matrix)
    end

    # Default stencil mode (always pass, keep values)
    private def default_stencil_mode : LibCSFML::StencilMode
      LibCSFML::StencilMode.new(
        stencil_comparison: LibCSFML::StencilComparison::Always,
        stencil_update_operation: LibCSFML::StencilUpdateOperation::Keep,
        stencil_reference: LibCSFML::StencilValue.new(value: 0_u32),
        stencil_mask: LibCSFML::StencilValue.new(value: 0xFFFFFFFF_u32),
        stencil_only: false
      )
    end

    def to_csfml : LibCSFML::RenderStates
      LibCSFML::RenderStates.new(
        blend_mode: @blend_mode.to_csfml,
        stencil_mode: default_stencil_mode,
        transform: identity_transform,
        coordinate_type: 0, # Pixels
        texture: Pointer(Void).null.as(LibCSFML::Texture),
        shader: Pointer(Void).null.as(LibCSFML::Shader)
      )
    end
  end

  # ============================================================
  # CircleShape
  # ============================================================

  class CircleShape
    @handle : LibCSFML::CircleShape

    def initialize(radius : Float32 = 0_f32, point_count : Int = 30)
      @handle = LibCSFML.sfCircleShape_create
      raise "Failed to create circle shape" if @handle.null?
      self.radius = radius
      self.point_count = point_count.to_u64
    end

    def radius=(radius : Float)
      LibCSFML.sfCircleShape_setRadius(@handle, radius.to_f32)
    end

    def radius : Float32
      LibCSFML.sfCircleShape_getRadius(@handle)
    end

    def point_count=(count : UInt64)
      LibCSFML.sfCircleShape_setPointCount(@handle, count)
    end

    def point_count : UInt64
      LibCSFML.sfCircleShape_getPointCount(@handle)
    end

    def position=(pos : Vector2f)
      LibCSFML.sfCircleShape_setPosition(@handle, pos.to_csfml_f)
    end

    def position : Vector2f
      p = LibCSFML.sfCircleShape_getPosition(@handle)
      Vector2f.new(p.x, p.y)
    end

    def fill_color=(color : Color)
      LibCSFML.sfCircleShape_setFillColor(@handle, color.to_csfml)
    end

    def outline_color=(color : Color)
      LibCSFML.sfCircleShape_setOutlineColor(@handle, color.to_csfml)
    end

    def outline_thickness=(thickness : Float)
      LibCSFML.sfCircleShape_setOutlineThickness(@handle, thickness.to_f32)
    end

    def origin=(origin : Vector2f)
      LibCSFML.sfCircleShape_setOrigin(@handle, origin.to_csfml_f)
    end

    def global_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfCircleShape_getGlobalBounds(@handle))
    end

    def local_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfCircleShape_getLocalBounds(@handle))
    end

    def to_unsafe : LibCSFML::CircleShape
      @handle
    end

    def finalize
      LibCSFML.sfCircleShape_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # ConvexShape
  # ============================================================

  class ConvexShape
    @handle : LibCSFML::ConvexShape

    def initialize(point_count : Int = 0)
      @handle = LibCSFML.sfConvexShape_create
      raise "Failed to create convex shape" if @handle.null?
      self.point_count = point_count.to_u64 if point_count > 0
    end

    def point_count=(count : UInt64)
      LibCSFML.sfConvexShape_setPointCount(@handle, count)
    end

    def point_count : UInt64
      LibCSFML.sfConvexShape_getPointCount(@handle)
    end

    def set_point(index : Int, point : Vector2f)
      LibCSFML.sfConvexShape_setPoint(@handle, index.to_u64, point.to_csfml_f)
    end

    def get_point(index : Int) : Vector2f
      p = LibCSFML.sfConvexShape_getPoint(@handle, index.to_u64)
      Vector2f.new(p.x, p.y)
    end

    # CrSFML-compatible API - takes array of points
    def self.new(points : Array(Vector2f))
      shape = new(points.size)
      points.each_with_index do |point, i|
        shape.set_point(i, point)
      end
      shape
    end

    def position=(pos : Vector2f)
      LibCSFML.sfConvexShape_setPosition(@handle, pos.to_csfml_f)
    end

    def position : Vector2f
      p = LibCSFML.sfConvexShape_getPosition(@handle)
      Vector2f.new(p.x, p.y)
    end

    def fill_color=(color : Color)
      LibCSFML.sfConvexShape_setFillColor(@handle, color.to_csfml)
    end

    def outline_color=(color : Color)
      LibCSFML.sfConvexShape_setOutlineColor(@handle, color.to_csfml)
    end

    def outline_thickness=(thickness : Float)
      LibCSFML.sfConvexShape_setOutlineThickness(@handle, thickness.to_f32)
    end

    def origin=(origin : Vector2f)
      LibCSFML.sfConvexShape_setOrigin(@handle, origin.to_csfml_f)
    end

    def global_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfConvexShape_getGlobalBounds(@handle))
    end

    def local_bounds : FloatRect
      FloatRect.from_csfml(LibCSFML.sfConvexShape_getLocalBounds(@handle))
    end

    def to_unsafe : LibCSFML::ConvexShape
      @handle
    end

    def finalize
      LibCSFML.sfConvexShape_destroy(@handle) unless @handle.null?
    end
  end

  # ============================================================
  # Cursor
  # ============================================================

  # CrSFML-compatible cursor class
  # Usage: cursor = SF::Cursor.new; cursor.load_from_system(SF::Cursor::Arrow)
  class Cursor
    @handle : LibCSFML::Cursor

    # Cursor type enum
    enum Type
      Arrow                  =  0
      ArrowWait              =  1
      Wait                   =  2
      Text                   =  3
      Hand                   =  4
      SizeHorizontal         =  5
      SizeVertical           =  6
      SizeTopLeftBottomRight =  7
      SizeBottomLeftTopRight =  8
      SizeLeft               =  9
      SizeRight              = 10
      SizeTop                = 11
      SizeBottom             = 12
      SizeTopLeft            = 13
      SizeBottomRight        = 14
      SizeBottomLeft         = 15
      SizeTopRight           = 16
      SizeAll                = 17
      Cross                  = 18
      Help                   = 19
      NotAllowed             = 20
    end

    # Shorthand constants for CrSFML compatibility (SF::Cursor::Arrow etc.)
    Arrow                  = Type::Arrow
    ArrowWait              = Type::ArrowWait
    Wait                   = Type::Wait
    Text                   = Type::Text
    Hand                   = Type::Hand
    SizeHorizontal         = Type::SizeHorizontal
    SizeVertical           = Type::SizeVertical
    SizeTopLeftBottomRight = Type::SizeTopLeftBottomRight
    SizeBottomLeftTopRight = Type::SizeBottomLeftTopRight
    SizeLeft               = Type::SizeLeft
    SizeRight              = Type::SizeRight
    SizeTop                = Type::SizeTop
    SizeBottom             = Type::SizeBottom
    SizeTopLeft            = Type::SizeTopLeft
    SizeBottomRight        = Type::SizeBottomRight
    SizeBottomLeft         = Type::SizeBottomLeft
    SizeTopRight           = Type::SizeTopRight
    SizeAll                = Type::SizeAll
    Cross                  = Type::Cross
    Help                   = Type::Help
    NotAllowed             = Type::NotAllowed

    def initialize
      @handle = Pointer(Void).null.as(LibCSFML::Cursor)
    end

    def initialize(type : Type)
      @handle = LibCSFML.sfCursor_createFromSystem(type.value)
      raise "Failed to create cursor" if @handle.null?
    end

    # CrSFML compatibility: load_from_system method
    def load_from_system(type : Type) : Bool
      # Destroy existing cursor if any
      LibCSFML.sfCursor_destroy(@handle) unless @handle.null?
      @handle = LibCSFML.sfCursor_createFromSystem(type.value)
      !@handle.null?
    end

    def to_unsafe : LibCSFML::Cursor
      @handle
    end

    def finalize
      LibCSFML.sfCursor_destroy(@handle) unless @handle.null?
    end
  end
end
