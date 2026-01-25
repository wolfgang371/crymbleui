# Simple test to verify CSFML 3.0 bindings work
require "../src/csfml3/lib"

puts "Testing CSFML 3.0 bindings..."

# Test VideoMode
mode = LibCSFML.sfVideoMode_getDesktopMode
puts "Desktop mode: #{mode.size.x}x#{mode.size.y} @ #{mode.bits_per_pixel}bpp"

# Test creating a simple window
settings = LibCSFML::ContextSettings.new
video_mode = LibCSFML::VideoMode.new(
  size: LibCSFML::Vector2u.new(x: 800_u32, y: 600_u32),
  bits_per_pixel: 32_u32
)

# Window style: Close | Titlebar = 4 | 1 = 5
window = LibCSFML.sfRenderWindow_create(video_mode, "CSFML 3.0 Test", 5_u32, pointerof(settings))

if window.null?
  puts "ERROR: Failed to create window!"
  exit 1
end

puts "Window created successfully!"

# Clear to a color
red = LibCSFML::Color.new(r: 100_u8, g: 50_u8, b: 50_u8, a: 255_u8)
LibCSFML.sfRenderWindow_clear(window, red)
LibCSFML.sfRenderWindow_display(window)

puts "Window cleared to red and displayed."

# Test RenderTexture creation (key for ghosting fix)
rt_size = LibCSFML::Vector2u.new(x: 256_u32, y: 256_u32)
render_texture = LibCSFML.sfRenderTexture_create(rt_size, nil)

if render_texture.null?
  puts "ERROR: Failed to create RenderTexture!"
else
  puts "RenderTexture created successfully (256x256)"

  # Test clearing the RenderTexture
  blue = LibCSFML::Color.new(r: 50_u8, g: 50_u8, b: 100_u8, a: 255_u8)
  LibCSFML.sfRenderTexture_clear(render_texture, blue)
  LibCSFML.sfRenderTexture_display(render_texture)
  puts "RenderTexture cleared and displayed."

  # Get the texture
  texture = LibCSFML.sfRenderTexture_getTexture(render_texture)
  if texture.null?
    puts "ERROR: Failed to get texture from RenderTexture!"
  else
    puts "Got texture from RenderTexture successfully."
  end

  LibCSFML.sfRenderTexture_destroy(render_texture)
  puts "RenderTexture destroyed."
end

# Wait a moment then close
puts "Waiting 2 seconds..."
LibCSFML.sfSleep(LibCSFML.sfSeconds(2.0_f32))

LibCSFML.sfRenderWindow_close(window)
LibCSFML.sfRenderWindow_destroy(window)

puts "Window closed and destroyed."
puts "CSFML 3.0 bindings test PASSED!"
