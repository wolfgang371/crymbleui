require "../csfml3/wrapper"
require "../core/types"
require "../core/widget"
require "./opengl_bindings"

module CrymbleUI
    # SFML-based paint context for clipping and direct rendering
    class SFMLPaintContext
        getter render_target : SF::RenderTarget

        # Clipping stack
        @clip_stack : Array(Rect)
        @default_font : SF::Font?

        def initialize(@render_target : SF::RenderTarget, @default_font : SF::Font? = nil)
            @clip_stack = [] of Rect
        end

        # Draw rectangle outline
        def draw_rect(rect : Rect, color : Color)
            shape = SF::RectangleShape.new(SF.vector2f(rect.width, rect.height))
            shape.position = SF.vector2f(rect.x, rect.y)
            shape.fill_color = SF::Color::Transparent
            shape.outline_color = to_sf_color(color)
            shape.outline_thickness = 1.0

            @render_target.draw(shape)
        end

        # Fill rectangle with solid color
        def fill_rect(rect : Rect, color : Color)
            shape = SF::RectangleShape.new(SF.vector2f(rect.width, rect.height))
            shape.position = SF.vector2f(rect.x, rect.y)
            shape.fill_color = to_sf_color(color)

            @render_target.draw(shape)
        end

        # Draw text
        def draw_text(text : String, position : Vec2, color : Color, size : Float64)
            return unless font = @default_font

            sf_text = SF::Text.new(text, font, size.round.to_u32)
            sf_text.position = SF.vector2f(position.x, position.y)
            sf_text.fill_color = to_sf_color(color)

            @render_target.draw(sf_text)
        end

        # Measure text dimensions (width and height)
        def measure_text(text : String, size : Float64) : Size
            return Size.new(0.0, 0.0) unless font = @default_font

            sf_text = SF::Text.new(text, font, size.round.to_u32)
            bounds = sf_text.global_bounds
            Size.new(bounds.width.to_f64, bounds.height.to_f64)
        end

        # Draw line
        def draw_line(from : Vec2, to : Vec2, color : Color, width : Float64)
            # Calculate line as a rotated rectangle
            dx = to.x - from.x
            dy = to.y - from.y
            length = Math.sqrt(dx * dx + dy * dy)
            angle = Math.atan2(dy, dx) * 180.0 / Math::PI

            # Convert to Float32 for SFML
            shape = SF::RectangleShape.new(SF.vector2f(length.to_f32, width.to_f32))
            shape.position = SF.vector2f(from.x.to_f32, (from.y - width / 2.0).to_f32)
            shape.rotation = angle.to_f32
            shape.fill_color = to_sf_color(color)

            @render_target.draw(shape)
        end

        # Push clipping region onto stack
        def push_clip(rect : Rect)
            @clip_stack << rect
            apply_clip
        end

        # Pop clipping region from stack
        def pop_clip
            @clip_stack.pop
            apply_clip
        end

        # Apply current clipping region using OpenGL scissor test
        private def apply_clip
            if clip = @clip_stack.last?
                # Enable scissor test
                LibGL.enable(LibGL::GL_SCISSOR_TEST)

                # Convert clip rect to OpenGL coordinates
                # OpenGL Y axis is bottom-to-top, SFML/our system is top-to-bottom
                window_height = @render_target.size.y
                gl_x = clip.x.to_i32
                gl_y = (window_height - (clip.y + clip.height)).to_i32  # Flip Y axis
                gl_width = clip.width.to_i32
                gl_height = clip.height.to_i32

                LibGL.scissor(gl_x, gl_y, gl_width, gl_height)
            else
                # No clip - disable scissor test
                LibGL.disable(LibGL::GL_SCISSOR_TEST)
            end
        end

        # Convert CrymbleUI Color to SFML Color
        private def to_sf_color(color : Color) : SF::Color
            SF::Color.new(color.r, color.g, color.b, color.a)
        end
    end
end
