# OpenGL bindings for scissor test (rectangular clipping)
#
# Shared by CrSFMLBackend and SFMLPaintContext for widget content clipping
# Note: Requires X11 display - tests using these backends need DISPLAY set
@[Link("GL")]
lib LibGL
  fun enable = glEnable(cap : UInt32)
  fun disable = glDisable(cap : UInt32)
  fun scissor = glScissor(x : Int32, y : Int32, width : Int32, height : Int32)

  GL_SCISSOR_TEST = 0x0C11_u32
end
