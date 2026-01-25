# Test for the CSFML 3.0 wrapper module
# This tests the SF:: namespace API that wraps LibCSFML

require "../src/csfml3/wrapper"

puts "Testing CSFML 3.0 wrapper..."

# Test basic types
puts "Testing basic types..."
v2i = SF::Vector2i.new(10, 20)
puts "  Vector2i: (#{v2i.x}, #{v2i.y})"

v2f = SF::Vector2f.new(1.5, 2.5)
puts "  Vector2f: (#{v2f.x}, #{v2f.y})"

color = SF::Color.new(255, 128, 64, 255)
puts "  Color: (#{color.r}, #{color.g}, #{color.b}, #{color.a})"

rect = SF::IntRect.new(10, 20, 100, 200)
puts "  IntRect: (#{rect.left}, #{rect.top}, #{rect.width}, #{rect.height})"

# Test VideoMode
puts "Testing VideoMode..."
desktop = SF::VideoMode.desktop_mode
puts "  Desktop: #{desktop.width}x#{desktop.height} @ #{desktop.bits_per_pixel}bpp"

# Test RenderWindow
puts "Testing RenderWindow..."
mode = SF::VideoMode.new(800_u32, 600_u32)
window = SF::RenderWindow.new(mode, "CSFML 3.0 Wrapper Test", SF::Style::Default)
puts "  Window created: #{window.size.x}x#{window.size.y}"

# Test RenderTexture
puts "Testing RenderTexture..."
rt = SF::RenderTexture.new(256, 256)
puts "  RenderTexture created: #{rt.size.x}x#{rt.size.y}"

# Test clearing and display
rt.clear(SF::Color::Blue)
rt.display
puts "  RenderTexture cleared to blue"

# Test Font loading
puts "Testing Font..."
font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
if File.exists?(font_path)
  font = SF::Font.new(font_path)
  puts "  Font loaded"

  # Test Text
  puts "Testing Text..."
  text = SF::Text.new("Hello SFML 3.0!", font, 24)
  text.fill_color = SF::Color::White
  puts "  Text created"

  # Draw text to RenderTexture
  rt.clear(SF::Color.new(40, 40, 60))
  rt.draw(text)
  rt.display
  puts "  Text drawn to RenderTexture"
else
  puts "  Skipping font test (#{font_path} not found)"
end

# Test RectangleShape
puts "Testing RectangleShape..."
rect_shape = SF::RectangleShape.new(SF::Vector2f.new(100, 50))
rect_shape.position = SF::Vector2f.new(10, 10)
rect_shape.fill_color = SF::Color::Green
puts "  RectangleShape created"

rt.draw(rect_shape)
rt.display
puts "  RectangleShape drawn"

# Test getting texture from RenderTexture
puts "Testing RenderTexture.texture..."
texture = rt.texture
puts "  Texture size: #{texture.size.x}x#{texture.size.y}"

# Test Sprite from texture
puts "Testing Sprite..."
sprite = SF::Sprite.new(texture)
sprite.position = SF::Vector2f.new(100, 100)
puts "  Sprite created and positioned"

# Test event polling
puts "Testing event polling (will close after 2 seconds)..."
window.clear(SF::Color.new(30, 30, 50))
window.draw(sprite)
window.display

# Poll events for a short time
start_time = Time.monotonic
event = LibCSFML::Event.new
while (Time.monotonic - start_time).total_seconds < 2.0
  while window.poll_event(pointerof(event))
    case event.type
    when SF::Event::Closed
      puts "  Received Close event"
      window.close
    when SF::Event::KeyPressed
      puts "  Key pressed: #{event.key.code}"
    when SF::Event::MouseMoved
      # Don't spam mouse move events
    else
      puts "  Event type: #{event.type}"
    end
  end
  SF.sleep(SF.milliseconds(16)) # ~60fps
end

window.close
puts "Window closed"

puts "CSFML 3.0 wrapper test PASSED!"
