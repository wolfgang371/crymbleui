# OpenGL bindings for scissor test (rectangular clipping)
#
# Used by SFMLPaintContext. CrSFMLBackend does NOT use these: it expresses a clip as
# the target view's scissor and lets SFML apply it (LAYER_RENDERING_ARCHITECTURE.md,
# "Clipping"), which is what makes the clip survive render-target re-activation.
# Note: Requires X11 display - tests using these backends need DISPLAY set
{% if flag?(:win32) %}
  @[Link("opengl32")]
{% else %}
  @[Link("GL")]
{% end %}
lib LibGL
  fun enable = glEnable(cap : UInt32)
  fun disable = glDisable(cap : UInt32)
  fun scissor = glScissor(x : Int32, y : Int32, width : Int32, height : Int32)

  GL_SCISSOR_TEST = 0x0C11_u32
end
