module CrymbleUI
    # 2D vector for positions and offsets
    struct Vec2
        property x : Float64
        property y : Float64

        def initialize(@x : Float64, @y : Float64)
        end

        def initialize(x : Int32, y : Int32)
            @x = x.to_f64
            @y = y.to_f64
        end

        def +(other : Vec2) : Vec2
            Vec2.new(@x + other.x, @y + other.y)
        end

        def -(other : Vec2) : Vec2
            Vec2.new(@x - other.x, @y - other.y)
        end

        def *(scalar : Float64) : Vec2
            Vec2.new(@x * scalar, @y * scalar)
        end

        def /(scalar : Float64) : Vec2
            Vec2.new(@x / scalar, @y / scalar)
        end

        def ==(other : Vec2) : Bool
            @x == other.x && @y == other.y
        end

        def distance_to(other : Vec2) : Float64
            Math.sqrt((other.x - @x) ** 2 + (other.y - @y) ** 2)
        end

        def to_s(io : IO)
            io << "Vec2(#{@x}, #{@y})"
        end

        def self.zero : Vec2
            Vec2.new(0.0, 0.0)
        end
    end

    # Size with width and height
    struct Size
        property width : Float64
        property height : Float64

        def initialize(@width : Float64, @height : Float64)
        end

        def initialize(width : Int32, height : Int32)
            @width = width.to_f64
            @height = height.to_f64
        end

        def ==(other : Size) : Bool
            @width == other.width && @height == other.height
        end

        def area : Float64
            @width * @height
        end

        def aspect_ratio : Float64
            @width / @height
        end

        def is_empty? : Bool
            @width <= 0.0 || @height <= 0.0
        end

        def contains(other : Size) : Bool
            @width >= other.width && @height >= other.height
        end

        def to_s(io : IO)
            io << "Size(#{@width}, #{@height})"
        end

        def self.zero : Size
            Size.new(0.0, 0.0)
        end

        def self.infinite : Size
            Size.new(Float64::INFINITY, Float64::INFINITY)
        end
    end

    # Rectangle defined by position and size
    struct Rect
        property position : Vec2
        property size : Size

        def initialize(@position : Vec2, @size : Size)
        end

        def initialize(x : Float64, y : Float64, width : Float64, height : Float64)
            @position = Vec2.new(x, y)
            @size = Size.new(width, height)
        end

        def x : Float64
            @position.x
        end

        def y : Float64
            @position.y
        end

        def width : Float64
            @size.width
        end

        def height : Float64
            @size.height
        end

        def left : Float64
            @position.x
        end

        def top : Float64
            @position.y
        end

        def right : Float64
            @position.x + @size.width
        end

        def bottom : Float64
            @position.y + @size.height
        end

        def center : Vec2
            Vec2.new(
                @position.x + @size.width / 2,
                @position.y + @size.height / 2
            )
        end

        def contains_point(point : Vec2) : Bool
            point.x >= left && point.x <= right &&
                point.y >= top && point.y <= bottom
        end

        def intersects(other : Rect) : Bool
            !(right < other.left || left > other.right ||
                bottom < other.top || top > other.bottom)
        end

        def ==(other : Rect) : Bool
            @position == other.position && @size == other.size
        end

        def to_s(io : IO)
            io << "Rect(#{x}, #{y}, #{width}, #{height})"
        end

        def self.zero : Rect
            Rect.new(Vec2.zero, Size.zero)
        end
    end

    # RGBA color
    struct Color
        property r : UInt8
        property g : UInt8
        property b : UInt8
        property a : UInt8

        def initialize(@r : UInt8, @g : UInt8, @b : UInt8, @a : UInt8 = 255_u8)
        end

        def initialize(r : Int32, g : Int32, b : Int32, a : Int32 = 255)
            @r = r.to_u8
            @g = g.to_u8
            @b = b.to_u8
            @a = a.to_u8
        end

        # Create from hex string "#RRGGBB" or "#RRGGBBAA"
        def self.from_hex(hex : String) : Color
            hex = hex.lchop('#')

            r = hex[0..1].to_u8(16)
            g = hex[2..3].to_u8(16)
            b = hex[4..5].to_u8(16)
            a = hex.size == 8 ? hex[6..7].to_u8(16) : 255_u8

            Color.new(r, g, b, a)
        end

        # Create from normalized floats (0.0 - 1.0)
        def self.from_floats(r : Float64, g : Float64, b : Float64, a : Float64 = 1.0) : Color
            Color.new(
                (r * 255).to_u8,
                (g * 255).to_u8,
                (b * 255).to_u8,
                (a * 255).to_u8
            )
        end

        def to_hex : String
            if @a == 255_u8
                "#%02X%02X%02X" % [@r, @g, @b]
            else
                "#%02X%02X%02X%02X" % [@r, @g, @b, @a]
            end
        end

        def with_alpha(alpha : UInt8) : Color
            Color.new(@r, @g, @b, alpha)
        end

        def ==(other : Color) : Bool
            @r == other.r && @g == other.g && @b == other.b && @a == other.a
        end

        def to_s(io : IO)
            io << to_hex
        end

        # Compact inspect for debugging (same as to_s - hex format)
        # Without this, Crystal prints: Color(@r=0, @g=120, @b=215, @a=255)
        # With this, Crystal prints: #0078D7 (90% less output in test failures)
        def inspect(io : IO)
            to_s(io)
        end

        # Common colors
        def self.black : Color
            Color.new(0, 0, 0)
        end

        def self.white : Color
            Color.new(255, 255, 255)
        end

        def self.red : Color
            Color.new(255, 0, 0)
        end

        def self.green : Color
            Color.new(0, 255, 0)
        end

        def self.blue : Color
            Color.new(0, 0, 255)
        end

        def self.transparent : Color
            Color.new(0, 0, 0, 0)
        end

        # Multiply RGB channels by scalar (clamped) - useful for brightness
        def *(scalar : Float64) : Color
            Color.new(
                (r * scalar).to_i.clamp(0, 255),
                (g * scalar).to_i.clamp(0, 255),
                (b * scalar).to_i.clamp(0, 255),
                a
            )
        end

        # Convert to HSV (h: 0-360, s: 0-1, v: 0-1)
        def to_hsv : {h: Float64, s: Float64, v: Float64, a: UInt8}
            r_norm = r / 255.0
            g_norm = g / 255.0
            b_norm = b / 255.0

            max = [r_norm, g_norm, b_norm].max
            min = [r_norm, g_norm, b_norm].min
            delta = max - min

            # Hue calculation
            h = if delta == 0
                0.0
            elsif max == r_norm
                60.0 * (((g_norm - b_norm) / delta) % 6)
            elsif max == g_norm
                60.0 * (((b_norm - r_norm) / delta) + 2)
            else # max == b_norm
                60.0 * (((r_norm - g_norm) / delta) + 4)
            end

            # Saturation
            s = max == 0 ? 0.0 : delta / max

            # Value
            v = max

            {h: h, s: s, v: v, a: a}
        end

        # Create from HSV - tuple form (symmetric with to_hsv)
        def self.from_hsv(hsv : {h: Float64, s: Float64, v: Float64, a: UInt8}) : Color
            from_hsv(hsv[:h], hsv[:s], hsv[:v], hsv[:a])
        end

        # Create from HSV - individual parameters
        def self.from_hsv(h : Float64, s : Float64, v : Float64, a : UInt8 = 255) : Color
            h = h % 360.0 # Wrap hue
            s = s.clamp(0.0, 1.0)
            v = v.clamp(0.0, 1.0)

            c = v * s
            x = c * (1 - ((h / 60.0) % 2 - 1).abs)
            m = v - c

            r_norm, g_norm, b_norm = case h
            when 0...60   then {c, x, 0.0}
            when 60...120 then {x, c, 0.0}
            when 120...180 then {0.0, c, x}
            when 180...240 then {0.0, x, c}
            when 240...300 then {x, 0.0, c}
            else               {c, 0.0, x}
            end

            Color.new(
                ((r_norm + m) * 255).to_i,
                ((g_norm + m) * 255).to_i,
                ((b_norm + m) * 255).to_i,
                a
            )
        end

        # Scale brightness (in HSV space)
        def scale_brightness(factor : Float64) : Color
            hsv = to_hsv
            Color.from_hsv(hsv[:h], hsv[:s], (hsv[:v] * factor).clamp(0.0, 1.0), hsv[:a])
        end

        # Scale saturation
        def scale_saturation(factor : Float64) : Color
            hsv = to_hsv
            Color.from_hsv(hsv[:h], (hsv[:s] * factor).clamp(0.0, 1.0), hsv[:v], hsv[:a])
        end

        # Rotate hue (in degrees)
        def rotate_hue(degrees : Float64) : Color
            hsv = to_hsv
            Color.from_hsv((hsv[:h] + degrees) % 360.0, hsv[:s], hsv[:v], hsv[:a])
        end

        # Lighten (increase value)
        def lighten(amount : Float64 = 0.1) : Color
            scale_brightness(1.0 + amount)
        end

        # Darken (decrease value)
        def darken(amount : Float64 = 0.1) : Color
            scale_brightness(1.0 - amount)
        end

        # Add brightness (additive in HSV V space, works for black)
        def add_brightness(amount : Float64) : Color
            hsv = to_hsv
            Color.from_hsv(hsv[:h], hsv[:s], (hsv[:v] + amount).clamp(0.0, 1.0), hsv[:a])
        end

        # Smart highlight: adds brightness for dark colors, subtracts for bright colors
        # This ensures visible highlighting regardless of the base color's brightness
        def highlight(amount : Float64 = 0.15) : Color
            hsv = to_hsv
            new_v = if hsv[:v] > (1.0 - amount)
                      # Color is too bright to add, subtract instead
                      hsv[:v] - amount
                    else
                      hsv[:v] + amount
                    end
            Color.from_hsv(hsv[:h], hsv[:s], new_v.clamp(0.0, 1.0), hsv[:a])
        end

        # Saturate
        def saturate(amount : Float64 = 0.1) : Color
            scale_saturation(1.0 + amount)
        end

        # Desaturate
        def desaturate(amount : Float64 = 0.1) : Color
            scale_saturation(1.0 - amount)
        end
    end

    # Cursor types (renderer-agnostic)
    enum CursorType
        Arrow
        Text
        SizeHorizontal
        SizeVertical
        SizeNWSE
        SizeNESW
        SizeAll
    end

    # Checkbox states for tristate checkboxes
    enum CheckState
        Unchecked
        Checked
        Indeterminate
    end

    # Blend modes for layer composition
    enum BlendMode
        Normal    # Standard alpha blending (default)
        Additive    # Add colors (for glow effects)
        Subtractive # Subtract colors (for darkening highlight on light bg)
        Multiply    # Multiply colors (for shadows)
    end

    # Alignment positions for layer-based widgets (LayerBox)
    # 9-point grid alignment relative to container bounds
    enum Alignment
        None          # Use explicit x, y (default - backward compatible)
        TopLeft
        TopCenter
        TopRight
        MiddleLeft
        Center
        MiddleRight
        BottomLeft
        BottomCenter
        BottomRight
    end

    # Percentage value for relative sizing (0.0-1.0 internally)
    struct Percent
        property value : Float64

        def initialize(@value : Float64)
        end

        # Factory method: Percent.of(50) → 50% → 0.5 internally
        def self.of(pct : Float64) : Percent
            Percent.new(pct / 100.0)
        end
    end

    # Size specification: pixels (Float64), percentage (Percent), or auto (Nil)
    alias SizeSpec = Float64 | Percent | Nil

    # Box constraints for layout
    struct BoxConstraints
        property min_width : Float64
        property max_width : Float64
        property min_height : Float64
        property max_height : Float64

        def initialize(
            @min_width : Float64 = 0.0,
            @max_width : Float64 = Float64::INFINITY,
            @min_height : Float64 = 0.0,
            @max_height : Float64 = Float64::INFINITY
        )
        end

        def self.tight(size : Size) : BoxConstraints
            BoxConstraints.new(
                min_width: size.width,
                max_width: size.width,
                min_height: size.height,
                max_height: size.height
            )
        end

        def self.loose(size : Size) : BoxConstraints
            BoxConstraints.new(
                min_width: 0.0,
                max_width: size.width,
                min_height: 0.0,
                max_height: size.height
            )
        end

        def self.expand : BoxConstraints
            BoxConstraints.new(
                min_width: Float64::INFINITY,
                max_width: Float64::INFINITY,
                min_height: Float64::INFINITY,
                max_height: Float64::INFINITY
            )
        end

        def is_tight? : Bool
            @min_width == @max_width && @min_height == @max_height
        end

        def is_bounded? : Bool
            @max_width.finite? && @max_height.finite?
        end

        def has_bounded_width? : Bool
            @max_width.finite?
        end

        def has_bounded_height? : Bool
            @max_height.finite?
        end

        def constrain(size : Size) : Size
            Size.new(
                constrain_width(size.width),
                constrain_height(size.height)
            )
        end

        def constrain_width(width : Float64) : Float64
            [[@min_width, width].max, @max_width].min
        end

        def constrain_height(height : Float64) : Float64
            [[@min_height, height].max, @max_height].min
        end

        def enforce(constraints : BoxConstraints) : BoxConstraints
            BoxConstraints.new(
                min_width: constrain_width(constraints.min_width),
                max_width: constrain_width(constraints.max_width),
                min_height: constrain_height(constraints.min_height),
                max_height: constrain_height(constraints.max_height)
            )
        end

        def tighten(width : Float64? = nil, height : Float64? = nil) : BoxConstraints
            BoxConstraints.new(
                min_width: width.nil? ? @min_width : [[width, @min_width].max, @max_width].min,
                max_width: width.nil? ? @max_width : [[width, @min_width].max, @max_width].min,
                min_height: height.nil? ? @min_height : [[height, @min_height].max, @max_height].min,
                max_height: height.nil? ? @max_height : [[height, @min_height].max, @max_height].min
            )
        end

        def loosen : BoxConstraints
            BoxConstraints.new(
                min_width: 0.0,
                max_width: @max_width,
                min_height: 0.0,
                max_height: @max_height
            )
        end

        def ==(other : BoxConstraints) : Bool
            @min_width == other.min_width &&
                @max_width == other.max_width &&
                @min_height == other.min_height &&
                @max_height == other.max_height
        end

        def to_s(io : IO)
            io << "BoxConstraints(w: #{@min_width}..#{@max_width}, h: #{@min_height}..#{@max_height})"
        end
    end
end
