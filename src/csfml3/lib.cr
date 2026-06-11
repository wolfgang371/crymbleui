# Crystal bindings for CSFML 3.0
# This provides direct FFI bindings to the C library
#
# USAGE: Set LD_LIBRARY_PATH before running:
#   source setup.sh  # Sets LD_LIBRARY_PATH to include locallib/sfml3/lib/linux and locallib/csfml3/lib/linux
#
# Or build with explicit paths using LIBRARY_PATH environment variable.

@[Link("csfml-system")]
@[Link("csfml-window")]
@[Link("csfml-graphics")]
@[Link("sfml-system")]
@[Link("sfml-window")]
@[Link("sfml-graphics")]
{% if flag?(:win32) %}
  @[Link("freetype")]
  @[Link("gdi32")]
  @[Link("winmm")]
  @[Link("user32")]
  @[Link("opengl32")]
  @[Link("advapi32")]
{% end %}
lib LibCSFML
  # ============================================================
  # System Types
  # ============================================================

  struct Vector2i
    x : LibC::Int
    y : LibC::Int
  end

  struct Vector2u
    x : LibC::UInt
    y : LibC::UInt
  end

  struct Vector2f
    x : LibC::Float
    y : LibC::Float
  end

  struct Vector3f
    x : LibC::Float
    y : LibC::Float
    z : LibC::Float
  end

  # Time is represented as microseconds (Int64)
  alias Time = Int64

  # ============================================================
  # Graphics Types
  # ============================================================

  struct Color
    r : UInt8
    g : UInt8
    b : UInt8
    a : UInt8
  end

  struct IntRect
    position : Vector2i
    size : Vector2i
  end

  struct FloatRect
    position : Vector2f
    size : Vector2f
  end

  # Glyph struct - describes a glyph (visual character)
  struct Glyph
    advance : LibC::Float       # Offset to move horizontally to the next character
    bounds : FloatRect          # Bounding rectangle relative to baseline
    texture_rect : IntRect      # Texture coordinates of glyph inside font's image
  end

  # Opaque types
  type RenderWindow = Void*
  type RenderTexture = Void*
  type Texture = Void*
  type Sprite = Void*
  type Font = Void*
  type Text = Void*
  type RectangleShape = Void*
  type CircleShape = Void*
  type ConvexShape = Void*
  type View = Void*
  type Image = Void*
  type Shader = Void*
  type VertexArray = Void*

  # ============================================================
  # Window Types
  # ============================================================

  type Window = Void*
  type Cursor = Void*

  struct ContextSettings
    depth_bits : LibC::UInt
    stencil_bits : LibC::UInt
    antialiasing_level : LibC::UInt
    major_version : LibC::UInt
    minor_version : LibC::UInt
    attribute_flags : UInt32
    srgb_capable : Bool
  end

  struct VideoMode
    size : Vector2u
    bits_per_pixel : LibC::UInt
  end

  # Event types enum
  enum EventType
    Closed
    Resized
    FocusLost
    FocusGained
    TextEntered
    KeyPressed
    KeyReleased
    MouseWheelScrolled
    MouseButtonPressed
    MouseButtonReleased
    MouseMoved
    MouseMovedRaw
    MouseEntered
    MouseLeft
    JoystickButtonPressed
    JoystickButtonReleased
    JoystickMoved
    JoystickConnected
    JoystickDisconnected
    TouchBegan
    TouchMoved
    TouchEnded
    SensorChanged
    Count
  end

  # Keyboard key codes
  enum KeyCode
    Unknown = -1
    A = 0
    B; C; D; E; F; G; H; I; J; K; L; M; N; O; P; Q; R; S; T; U; V; W; X; Y; Z
    Num0; Num1; Num2; Num3; Num4; Num5; Num6; Num7; Num8; Num9
    Escape; LControl; LShift; LAlt; LSystem
    RControl; RShift; RAlt; RSystem
    Menu; LBracket; RBracket; Semicolon; Comma; Period; Apostrophe
    Slash; Backslash; Grave; Equal; Hyphen
    Space; Enter; Backspace; Tab
    PageUp; PageDown; End; Home; Insert; Delete
    Add; Subtract; Multiply; Divide
    Left; Right; Up; Down
    Numpad0; Numpad1; Numpad2; Numpad3; Numpad4
    Numpad5; Numpad6; Numpad7; Numpad8; Numpad9
    F1; F2; F3; F4; F5; F6; F7; F8; F9; F10; F11; F12; F13; F14; F15
    Pause
    KeyCount
  end

  # Mouse buttons
  enum MouseButton
    Left
    Right
    Middle
    Extra1
    Extra2
    ButtonCount
  end

  # Mouse wheel
  enum MouseWheel
    Vertical
    Horizontal
  end

  # Event structs
  struct KeyEvent
    type : EventType
    code : KeyCode
    scancode : LibC::Int
    alt : Bool
    control : Bool
    shift : Bool
    system : Bool
  end

  struct TextEvent
    type : EventType
    unicode : UInt32
  end

  struct MouseMoveEvent
    type : EventType
    position : Vector2i
  end

  struct MouseButtonEvent
    type : EventType
    button : MouseButton
    position : Vector2i
  end

  struct MouseWheelScrollEvent
    type : EventType
    wheel : MouseWheel
    delta : LibC::Float
    position : Vector2i
  end

  struct SizeEvent
    type : EventType
    size : Vector2u
  end

  # Union of all events (we'll use the largest)
  union Event
    type : EventType
    size : SizeEvent
    key : KeyEvent
    text : TextEvent
    mouse_move : MouseMoveEvent
    mouse_button : MouseButtonEvent
    mouse_wheel_scroll : MouseWheelScrollEvent
  end

  # Blend mode
  enum BlendFactor
    Zero
    One
    SrcColor
    OneMinusSrcColor
    DstColor
    OneMinusDstColor
    SrcAlpha
    OneMinusSrcAlpha
    DstAlpha
    OneMinusDstAlpha
  end

  enum BlendEquation
    Add
    Subtract
    ReverseSubtract
    Min
    Max
  end

  struct BlendMode
    color_src_factor : BlendFactor
    color_dst_factor : BlendFactor
    color_equation : BlendEquation
    alpha_src_factor : BlendFactor
    alpha_dst_factor : BlendFactor
    alpha_equation : BlendEquation
  end

  # Transform (3x3 matrix)
  struct Transform
    matrix : StaticArray(LibC::Float, 9)
  end

  # Stencil enums
  enum StencilComparison
    Never
    Less
    LessEqual
    Greater
    GreaterEqual
    Equal
    NotEqual
    Always
  end

  enum StencilUpdateOperation
    Keep
    Zero
    Replace
    Increment
    Decrement
    Invert
  end

  # Stencil value
  struct StencilValue
    value : LibC::UInt
  end

  # Stencil mode
  struct StencilMode
    stencil_comparison : StencilComparison
    stencil_update_operation : StencilUpdateOperation
    stencil_reference : StencilValue
    stencil_mask : StencilValue
    stencil_only : Bool
  end

  # Render states - SFML 3.0 updated struct
  struct RenderStates
    blend_mode : BlendMode
    stencil_mode : StencilMode
    transform : Transform
    coordinate_type : LibC::Int
    texture : Texture
    shader : Shader
  end

  # ============================================================
  # System Functions
  # ============================================================

  fun sfSleep(duration : Time)
  fun sfTime_asSeconds(time : Time) : LibC::Float
  fun sfTime_asMilliseconds(time : Time) : Int32
  fun sfTime_asMicroseconds(time : Time) : Int64
  fun sfSeconds(amount : LibC::Float) : Time
  fun sfMilliseconds(amount : Int32) : Time
  fun sfMicroseconds(amount : Int64) : Time

  # ============================================================
  # Window Functions
  # ============================================================

  fun sfVideoMode_getDesktopMode : VideoMode
  fun sfVideoMode_isValid(mode : VideoMode) : Bool

  fun sfKeyboard_isKeyPressed(key : KeyCode) : Bool
  fun sfMouse_isButtonPressed(button : MouseButton) : Bool
  fun sfMouse_getPosition(relative_to : Window) : Vector2i
  fun sfMouse_setPosition(position : Vector2i, relative_to : Window)
  fun sfMouse_getPositionRenderWindow(relative_to : RenderWindow) : Vector2i
  fun sfMouse_setPositionRenderWindow(position : Vector2i, relative_to : RenderWindow)

  # Clipboard functions
  fun sfClipboard_getString : LibC::Char*
  fun sfClipboard_setString(text : LibC::Char*)

  # ============================================================
  # RenderWindow Functions
  # ============================================================

  # `state` (sfWindowState: 0=windowed, 1=fullscreen) is NEW in CSFML/SFML 3.0 and sits
  # between `style` and `settings` — see CSFML/Graphics/RenderWindow.h. Omitting it shifts
  # `settings` into the wrong register, so the C side dereferences garbage → segfault under
  # any optimization (-O1+). Keep this signature byte-for-byte aligned with the header.
  fun sfRenderWindow_create(mode : VideoMode, title : LibC::Char*, style : UInt32, state : UInt32, settings : ContextSettings*) : RenderWindow
  fun sfRenderWindow_createUnicode(mode : VideoMode, title : UInt32*, style : UInt32, state : UInt32, settings : ContextSettings*) : RenderWindow
  fun sfRenderWindow_destroy(window : RenderWindow)
  fun sfRenderWindow_close(window : RenderWindow)
  fun sfRenderWindow_isOpen(window : RenderWindow) : Bool
  fun sfRenderWindow_getSettings(window : RenderWindow) : ContextSettings
  fun sfRenderWindow_pollEvent(window : RenderWindow, event : Event*) : Bool
  fun sfRenderWindow_waitEvent(window : RenderWindow, timeout : Time, event : Event*) : Bool
  fun sfRenderWindow_getPosition(window : RenderWindow) : Vector2i
  fun sfRenderWindow_setPosition(window : RenderWindow, position : Vector2i)
  fun sfRenderWindow_getSize(window : RenderWindow) : Vector2u
  fun sfRenderWindow_setSize(window : RenderWindow, size : Vector2u)
  fun sfRenderWindow_setTitle(window : RenderWindow, title : LibC::Char*)
  fun sfRenderWindow_setIcon(window : RenderWindow, size : Vector2u, pixels : UInt8*)
  fun sfRenderWindow_setVisible(window : RenderWindow, visible : Bool)
  fun sfRenderWindow_setVerticalSyncEnabled(window : RenderWindow, enabled : Bool)
  fun sfRenderWindow_setMouseCursorVisible(window : RenderWindow, visible : Bool)
  fun sfRenderWindow_setMouseCursorGrabbed(window : RenderWindow, grabbed : Bool)
  fun sfRenderWindow_setMouseCursor(window : RenderWindow, cursor : Cursor)
  fun sfRenderWindow_setKeyRepeatEnabled(window : RenderWindow, enabled : Bool)
  fun sfRenderWindow_setFramerateLimit(window : RenderWindow, limit : LibC::UInt)
  fun sfRenderWindow_setActive(window : RenderWindow, active : Bool) : Bool
  fun sfRenderWindow_requestFocus(window : RenderWindow)
  fun sfRenderWindow_hasFocus(window : RenderWindow) : Bool
  fun sfRenderWindow_display(window : RenderWindow)
  fun sfRenderWindow_clear(window : RenderWindow, color : Color)
  fun sfRenderWindow_setView(window : RenderWindow, view : View)
  fun sfRenderWindow_getView(window : RenderWindow) : View
  fun sfRenderWindow_getDefaultView(window : RenderWindow) : View
  fun sfRenderWindow_mapPixelToCoords(window : RenderWindow, point : Vector2i, view : View) : Vector2f
  fun sfRenderWindow_mapCoordsToPixel(window : RenderWindow, point : Vector2f, view : View) : Vector2i
  fun sfRenderWindow_drawSprite(window : RenderWindow, sprite : Sprite, states : RenderStates*)
  fun sfRenderWindow_drawText(window : RenderWindow, text : Text, states : RenderStates*)
  fun sfRenderWindow_drawShape(window : RenderWindow, shape : Void*, states : RenderStates*)
  fun sfRenderWindow_drawCircleShape(window : RenderWindow, shape : CircleShape, states : RenderStates*)
  fun sfRenderWindow_drawConvexShape(window : RenderWindow, shape : ConvexShape, states : RenderStates*)
  fun sfRenderWindow_drawRectangleShape(window : RenderWindow, shape : RectangleShape, states : RenderStates*)
  fun sfRenderWindow_drawVertexArray(window : RenderWindow, array : VertexArray, states : RenderStates*)

  # ============================================================
  # RenderTexture Functions
  # ============================================================

  fun sfRenderTexture_create(size : Vector2u, settings : ContextSettings*) : RenderTexture
  fun sfRenderTexture_destroy(texture : RenderTexture)
  fun sfRenderTexture_getSize(texture : RenderTexture) : Vector2u
  fun sfRenderTexture_isSrgb(texture : RenderTexture) : Bool
  fun sfRenderTexture_setActive(texture : RenderTexture, active : Bool) : Bool
  fun sfRenderTexture_display(texture : RenderTexture)
  fun sfRenderTexture_clear(texture : RenderTexture, color : Color)
  fun sfRenderTexture_setView(texture : RenderTexture, view : View)
  fun sfRenderTexture_getView(texture : RenderTexture) : View
  fun sfRenderTexture_getDefaultView(texture : RenderTexture) : View
  fun sfRenderTexture_getTexture(texture : RenderTexture) : Texture
  fun sfRenderTexture_setSmooth(texture : RenderTexture, smooth : Bool)
  fun sfRenderTexture_isSmooth(texture : RenderTexture) : Bool
  fun sfRenderTexture_setRepeated(texture : RenderTexture, repeated : Bool)
  fun sfRenderTexture_isRepeated(texture : RenderTexture) : Bool
  fun sfRenderTexture_drawSprite(texture : RenderTexture, sprite : Sprite, states : RenderStates*)
  fun sfRenderTexture_drawText(texture : RenderTexture, text : Text, states : RenderStates*)
  fun sfRenderTexture_drawRectangleShape(texture : RenderTexture, shape : RectangleShape, states : RenderStates*)
  fun sfRenderTexture_drawCircleShape(texture : RenderTexture, shape : CircleShape, states : RenderStates*)
  fun sfRenderTexture_drawConvexShape(texture : RenderTexture, shape : ConvexShape, states : RenderStates*)

  # ============================================================
  # Texture Functions
  # ============================================================

  fun sfTexture_create(size : Vector2u) : Texture
  fun sfTexture_createFromFile(filename : LibC::Char*, area : IntRect*) : Texture
  fun sfTexture_createFromImage(image : Image, area : IntRect*) : Texture
  fun sfTexture_createFromMemory(data : Void*, sizeInBytes : LibC::SizeT, area : IntRect*) : Texture
  fun sfTexture_copy(texture : Texture) : Texture
  fun sfTexture_destroy(texture : Texture)
  fun sfTexture_getSize(texture : Texture) : Vector2u
  fun sfTexture_copyToImage(texture : Texture) : Image
  fun sfTexture_updateFromPixels(texture : Texture, pixels : UInt8*, size : Vector2u, dest : Vector2u)
  fun sfTexture_updateFromImage(texture : Texture, image : Image, dest : Vector2u)
  fun sfTexture_setSmooth(texture : Texture, smooth : Bool)
  fun sfTexture_isSmooth(texture : Texture) : Bool
  fun sfTexture_setRepeated(texture : Texture, repeated : Bool)
  fun sfTexture_isRepeated(texture : Texture) : Bool
  fun sfTexture_bind(texture : Texture, coordinate_type : LibC::Int)
  fun sfTexture_getMaximumSize : LibC::UInt

  # ============================================================
  # Sprite Functions
  # ============================================================

  fun sfSprite_create(texture : Texture) : Sprite
  fun sfSprite_copy(sprite : Sprite) : Sprite
  fun sfSprite_destroy(sprite : Sprite)
  fun sfSprite_setPosition(sprite : Sprite, position : Vector2f)
  fun sfSprite_setRotation(sprite : Sprite, angle : LibC::Float)
  fun sfSprite_setScale(sprite : Sprite, scale : Vector2f)
  fun sfSprite_setOrigin(sprite : Sprite, origin : Vector2f)
  fun sfSprite_getPosition(sprite : Sprite) : Vector2f
  fun sfSprite_getRotation(sprite : Sprite) : LibC::Float
  fun sfSprite_getScale(sprite : Sprite) : Vector2f
  fun sfSprite_getOrigin(sprite : Sprite) : Vector2f
  fun sfSprite_move(sprite : Sprite, offset : Vector2f)
  fun sfSprite_rotate(sprite : Sprite, angle : LibC::Float)
  fun sfSprite_scale(sprite : Sprite, factors : Vector2f)
  fun sfSprite_setTexture(sprite : Sprite, texture : Texture, reset_rect : Bool)
  fun sfSprite_setTextureRect(sprite : Sprite, rect : IntRect)
  fun sfSprite_setColor(sprite : Sprite, color : Color)
  fun sfSprite_getTexture(sprite : Sprite) : Texture
  fun sfSprite_getTextureRect(sprite : Sprite) : IntRect
  fun sfSprite_getColor(sprite : Sprite) : Color
  fun sfSprite_getLocalBounds(sprite : Sprite) : FloatRect
  fun sfSprite_getGlobalBounds(sprite : Sprite) : FloatRect

  # ============================================================
  # Font Functions
  # ============================================================

  fun sfFont_createFromFile(filename : LibC::Char*) : Font
  fun sfFont_createFromMemory(data : Void*, size : LibC::SizeT) : Font
  fun sfFont_copy(font : Font) : Font
  fun sfFont_destroy(font : Font)
  fun sfFont_getInfo(font : Font) : Void*
  fun sfFont_getKerning(font : Font, first : UInt32, second : UInt32, character_size : LibC::UInt) : LibC::Float
  fun sfFont_getLineSpacing(font : Font, character_size : LibC::UInt) : LibC::Float
  fun sfFont_getGlyph(font : Font, code_point : UInt32, character_size : LibC::UInt, bold : Bool, outline_thickness : LibC::Float) : Glyph
  fun sfFont_getTexture(font : Font, character_size : LibC::UInt) : Texture

  # ============================================================
  # Text Functions
  # ============================================================

  fun sfText_create(font : Font) : Text
  fun sfText_copy(text : Text) : Text
  fun sfText_destroy(text : Text)
  fun sfText_setPosition(text : Text, position : Vector2f)
  fun sfText_setRotation(text : Text, angle : LibC::Float)
  fun sfText_setScale(text : Text, scale : Vector2f)
  fun sfText_setOrigin(text : Text, origin : Vector2f)
  fun sfText_getPosition(text : Text) : Vector2f
  fun sfText_getRotation(text : Text) : LibC::Float
  fun sfText_getScale(text : Text) : Vector2f
  fun sfText_getOrigin(text : Text) : Vector2f
  fun sfText_setString(text : Text, string : LibC::Char*)
  fun sfText_setUnicodeString(text : Text, string : UInt32*)
  fun sfText_setFont(text : Text, font : Font)
  fun sfText_setCharacterSize(text : Text, size : LibC::UInt)
  fun sfText_setLineSpacing(text : Text, spacing : LibC::Float)
  fun sfText_setLetterSpacing(text : Text, spacing : LibC::Float)
  fun sfText_setStyle(text : Text, style : UInt32)
  fun sfText_setFillColor(text : Text, color : Color)
  fun sfText_setOutlineColor(text : Text, color : Color)
  fun sfText_setOutlineThickness(text : Text, thickness : LibC::Float)
  fun sfText_getString(text : Text) : LibC::Char*
  fun sfText_getFont(text : Text) : Font
  fun sfText_getCharacterSize(text : Text) : LibC::UInt
  fun sfText_getLetterSpacing(text : Text) : LibC::Float
  fun sfText_getLineSpacing(text : Text) : LibC::Float
  fun sfText_getStyle(text : Text) : UInt32
  fun sfText_getFillColor(text : Text) : Color
  fun sfText_getOutlineColor(text : Text) : Color
  fun sfText_getOutlineThickness(text : Text) : LibC::Float
  fun sfText_findCharacterPos(text : Text, index : LibC::SizeT) : Vector2f
  fun sfText_getLocalBounds(text : Text) : FloatRect
  fun sfText_getGlobalBounds(text : Text) : FloatRect

  # ============================================================
  # RectangleShape Functions
  # ============================================================

  fun sfRectangleShape_create : RectangleShape
  fun sfRectangleShape_copy(shape : RectangleShape) : RectangleShape
  fun sfRectangleShape_destroy(shape : RectangleShape)
  fun sfRectangleShape_setPosition(shape : RectangleShape, position : Vector2f)
  fun sfRectangleShape_setRotation(shape : RectangleShape, angle : LibC::Float)
  fun sfRectangleShape_setScale(shape : RectangleShape, scale : Vector2f)
  fun sfRectangleShape_setOrigin(shape : RectangleShape, origin : Vector2f)
  fun sfRectangleShape_getPosition(shape : RectangleShape) : Vector2f
  fun sfRectangleShape_getRotation(shape : RectangleShape) : LibC::Float
  fun sfRectangleShape_getScale(shape : RectangleShape) : Vector2f
  fun sfRectangleShape_getOrigin(shape : RectangleShape) : Vector2f
  fun sfRectangleShape_move(shape : RectangleShape, offset : Vector2f)
  fun sfRectangleShape_rotate(shape : RectangleShape, angle : LibC::Float)
  fun sfRectangleShape_scale(shape : RectangleShape, factors : Vector2f)
  fun sfRectangleShape_setSize(shape : RectangleShape, size : Vector2f)
  fun sfRectangleShape_getSize(shape : RectangleShape) : Vector2f
  fun sfRectangleShape_setTexture(shape : RectangleShape, texture : Texture, reset_rect : Bool)
  fun sfRectangleShape_setTextureRect(shape : RectangleShape, rect : IntRect)
  fun sfRectangleShape_setFillColor(shape : RectangleShape, color : Color)
  fun sfRectangleShape_setOutlineColor(shape : RectangleShape, color : Color)
  fun sfRectangleShape_setOutlineThickness(shape : RectangleShape, thickness : LibC::Float)
  fun sfRectangleShape_getTexture(shape : RectangleShape) : Texture
  fun sfRectangleShape_getTextureRect(shape : RectangleShape) : IntRect
  fun sfRectangleShape_getFillColor(shape : RectangleShape) : Color
  fun sfRectangleShape_getOutlineColor(shape : RectangleShape) : Color
  fun sfRectangleShape_getOutlineThickness(shape : RectangleShape) : LibC::Float
  fun sfRectangleShape_getPointCount(shape : RectangleShape) : LibC::SizeT
  fun sfRectangleShape_getPoint(shape : RectangleShape, index : LibC::SizeT) : Vector2f
  fun sfRectangleShape_getGeometricCenter(shape : RectangleShape) : Vector2f
  fun sfRectangleShape_getLocalBounds(shape : RectangleShape) : FloatRect
  fun sfRectangleShape_getGlobalBounds(shape : RectangleShape) : FloatRect

  # ============================================================
  # CircleShape Functions
  # ============================================================

  fun sfCircleShape_create : CircleShape
  fun sfCircleShape_copy(shape : CircleShape) : CircleShape
  fun sfCircleShape_destroy(shape : CircleShape)
  fun sfCircleShape_setPosition(shape : CircleShape, position : Vector2f)
  fun sfCircleShape_setRotation(shape : CircleShape, angle : LibC::Float)
  fun sfCircleShape_setScale(shape : CircleShape, scale : Vector2f)
  fun sfCircleShape_setOrigin(shape : CircleShape, origin : Vector2f)
  fun sfCircleShape_getPosition(shape : CircleShape) : Vector2f
  fun sfCircleShape_getRotation(shape : CircleShape) : LibC::Float
  fun sfCircleShape_getScale(shape : CircleShape) : Vector2f
  fun sfCircleShape_getOrigin(shape : CircleShape) : Vector2f
  fun sfCircleShape_move(shape : CircleShape, offset : Vector2f)
  fun sfCircleShape_rotate(shape : CircleShape, angle : LibC::Float)
  fun sfCircleShape_scale(shape : CircleShape, factors : Vector2f)
  fun sfCircleShape_setRadius(shape : CircleShape, radius : LibC::Float)
  fun sfCircleShape_getRadius(shape : CircleShape) : LibC::Float
  fun sfCircleShape_setPointCount(shape : CircleShape, count : LibC::SizeT)
  fun sfCircleShape_getPointCount(shape : CircleShape) : LibC::SizeT
  fun sfCircleShape_getPoint(shape : CircleShape, index : LibC::SizeT) : Vector2f
  fun sfCircleShape_setTexture(shape : CircleShape, texture : Texture, reset_rect : Bool)
  fun sfCircleShape_setTextureRect(shape : CircleShape, rect : IntRect)
  fun sfCircleShape_setFillColor(shape : CircleShape, color : Color)
  fun sfCircleShape_setOutlineColor(shape : CircleShape, color : Color)
  fun sfCircleShape_setOutlineThickness(shape : CircleShape, thickness : LibC::Float)
  fun sfCircleShape_getTexture(shape : CircleShape) : Texture
  fun sfCircleShape_getTextureRect(shape : CircleShape) : IntRect
  fun sfCircleShape_getFillColor(shape : CircleShape) : Color
  fun sfCircleShape_getOutlineColor(shape : CircleShape) : Color
  fun sfCircleShape_getOutlineThickness(shape : CircleShape) : LibC::Float
  fun sfCircleShape_getLocalBounds(shape : CircleShape) : FloatRect
  fun sfCircleShape_getGlobalBounds(shape : CircleShape) : FloatRect

  # ============================================================
  # ConvexShape Functions
  # ============================================================

  fun sfConvexShape_create : ConvexShape
  fun sfConvexShape_copy(shape : ConvexShape) : ConvexShape
  fun sfConvexShape_destroy(shape : ConvexShape)
  fun sfConvexShape_setPosition(shape : ConvexShape, position : Vector2f)
  fun sfConvexShape_setRotation(shape : ConvexShape, angle : LibC::Float)
  fun sfConvexShape_setScale(shape : ConvexShape, scale : Vector2f)
  fun sfConvexShape_setOrigin(shape : ConvexShape, origin : Vector2f)
  fun sfConvexShape_getPosition(shape : ConvexShape) : Vector2f
  fun sfConvexShape_getRotation(shape : ConvexShape) : LibC::Float
  fun sfConvexShape_getScale(shape : ConvexShape) : Vector2f
  fun sfConvexShape_getOrigin(shape : ConvexShape) : Vector2f
  fun sfConvexShape_move(shape : ConvexShape, offset : Vector2f)
  fun sfConvexShape_rotate(shape : ConvexShape, angle : LibC::Float)
  fun sfConvexShape_scale(shape : ConvexShape, factors : Vector2f)
  fun sfConvexShape_setPointCount(shape : ConvexShape, count : LibC::SizeT)
  fun sfConvexShape_getPointCount(shape : ConvexShape) : LibC::SizeT
  fun sfConvexShape_setPoint(shape : ConvexShape, index : LibC::SizeT, point : Vector2f)
  fun sfConvexShape_getPoint(shape : ConvexShape, index : LibC::SizeT) : Vector2f
  fun sfConvexShape_setTexture(shape : ConvexShape, texture : Texture, reset_rect : Bool)
  fun sfConvexShape_setTextureRect(shape : ConvexShape, rect : IntRect)
  fun sfConvexShape_setFillColor(shape : ConvexShape, color : Color)
  fun sfConvexShape_setOutlineColor(shape : ConvexShape, color : Color)
  fun sfConvexShape_setOutlineThickness(shape : ConvexShape, thickness : LibC::Float)
  fun sfConvexShape_getTexture(shape : ConvexShape) : Texture
  fun sfConvexShape_getTextureRect(shape : ConvexShape) : IntRect
  fun sfConvexShape_getFillColor(shape : ConvexShape) : Color
  fun sfConvexShape_getOutlineColor(shape : ConvexShape) : Color
  fun sfConvexShape_getOutlineThickness(shape : ConvexShape) : LibC::Float
  fun sfConvexShape_getLocalBounds(shape : ConvexShape) : FloatRect
  fun sfConvexShape_getGlobalBounds(shape : ConvexShape) : FloatRect

  # ============================================================
  # Image Functions
  # ============================================================

  fun sfImage_create(size : Vector2u) : Image
  fun sfImage_createFromColor(size : Vector2u, color : Color) : Image
  fun sfImage_createFromPixels(size : Vector2u, pixels : UInt8*) : Image
  fun sfImage_createFromFile(filename : LibC::Char*) : Image
  fun sfImage_copy(image : Image) : Image
  fun sfImage_destroy(image : Image)
  fun sfImage_saveToFile(image : Image, filename : LibC::Char*) : Bool
  fun sfImage_getSize(image : Image) : Vector2u
  fun sfImage_createMaskFromColor(image : Image, color : Color, alpha : UInt8)
  fun sfImage_setPixel(image : Image, coords : Vector2u, color : Color)
  fun sfImage_getPixel(image : Image, coords : Vector2u) : Color
  fun sfImage_getPixelsPtr(image : Image) : UInt8*
  fun sfImage_flipHorizontally(image : Image)
  fun sfImage_flipVertically(image : Image)

  # ============================================================
  # View Functions
  # ============================================================

  fun sfView_create : View
  fun sfView_createFromRect(rect : FloatRect) : View
  fun sfView_copy(view : View) : View
  fun sfView_destroy(view : View)
  fun sfView_setCenter(view : View, center : Vector2f)
  fun sfView_setSize(view : View, size : Vector2f)
  fun sfView_setRotation(view : View, angle : LibC::Float)
  fun sfView_setViewport(view : View, viewport : FloatRect)
  fun sfView_reset(view : View, rect : FloatRect)
  fun sfView_getCenter(view : View) : Vector2f
  fun sfView_getSize(view : View) : Vector2f
  fun sfView_getRotation(view : View) : LibC::Float
  fun sfView_getViewport(view : View) : FloatRect
  fun sfView_move(view : View, offset : Vector2f)
  fun sfView_rotate(view : View, angle : LibC::Float)
  fun sfView_zoom(view : View, factor : LibC::Float)

  # ============================================================
  # Cursor Functions
  # ============================================================

  fun sfCursor_createFromPixels(pixels : UInt8*, size : Vector2u, hotspot : Vector2u) : Cursor
  fun sfCursor_createFromSystem(type : LibC::Int) : Cursor
  fun sfCursor_destroy(cursor : Cursor)
end
