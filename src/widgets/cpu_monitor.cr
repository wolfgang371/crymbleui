require "../core/widget"
require "../core/types"
require "../core/font_scalable"
require "../dsl/primitive_builder"

module CrymbleUI
    # CPU Monitor widget - displays current process CPU usage
    # Updates every ~1 second with filtered average
    class CPUMonitor < Widget
        include PrimitiveBuilder
        include FontScalable

        # Layout constants
        PADDING_H = 4.0   # Horizontal padding (half of total 8.0)
        PADDING_V = 2.0   # Vertical padding (half of total 4.0)

        # Linux process timing constant
        CLOCK_TICKS_PER_SEC = 100.0  # USER_HZ on most Linux systems

        # Class variables to preserve state across rebuilds
        @@last_cpu_time : UInt64 = 0_u64
        @@last_wall_time : Time::Span = Time.monotonic
        @@cpu_percent : Float64 = 0.0
        @@timer_id : Int32? = nil
        @@initialized : Bool = false
        @@current_instance : CPUMonitor? = nil  # Updated on each rebuild

        # Visual properties
        render_property text_color : Color = Color.new(0, 0, 0, 255)
        render_property background_color : Color = Color.new(255, 255, 255, 0)  # Transparent by default (alpha=0) for overlay use

        def initialize(id : String? = nil, font_scale : Int32 = 0, text_color : Color = Color.new(0, 0, 0, 255))
            @font_scale = font_scale
            super(id: id)
            @text_color = text_color

            # Store current instance for timer callback to mark for render
            @@current_instance = self

            # Initialize monitoring on first instance only (survives rebuilds)
            unless @@initialized
                @@last_cpu_time = CPUMonitor.read_cpu_time
                @@last_wall_time = Time.monotonic
                @@initialized = true

                # Update every second (scheduler might not be initialized yet during build)
                begin
                    @@timer_id = schedule_timer(1.second, repeating: true) do
                        CPUMonitor.update_cpu_usage
                    end
                rescue
                    # Scheduler not initialized yet - will retry on next rebuild
                end
            end

            # If we have no timer yet but scheduler is available, start it now
            if @@timer_id.nil?
                begin
                    @@timer_id = schedule_timer(1.second, repeating: true) do
                        CPUMonitor.update_cpu_usage
                    end
                rescue
                    # Scheduler still not ready
                end
            end
        end

        # Read CPU time for current process (Linux /proc/self/stat)
        def self.read_cpu_time : UInt64
            {% if flag?(:linux) %}
                stat = File.read("/proc/self/stat")
                fields = stat.split
                # Fields 14 (utime) and 15 (stime) are CPU time in clock ticks
                utime = fields[13].to_u64
                stime = fields[14].to_u64
                utime + stime
            {% else %}
                # Fallback for non-Linux: return 0 (will show 0% CPU)
                0_u64
            {% end %}
        rescue
            0_u64
        end

        # Class method to update CPU usage (called from timer)
        # Marks current instance for render (updated on each rebuild)
        def self.update_cpu_usage
            current_cpu_time = read_cpu_time
            current_wall_time = Time.monotonic

            # Calculate elapsed times
            cpu_delta = current_cpu_time - @@last_cpu_time
            wall_delta = (current_wall_time - @@last_wall_time).total_seconds

            # CPU time is in clock ticks, convert to seconds
            cpu_seconds = cpu_delta.to_f / CLOCK_TICKS_PER_SEC

            # Calculate percentage
            if wall_delta > 0
                @@cpu_percent = (cpu_seconds / wall_delta) * 100.0
            end

            # Update for next iteration
            @@last_cpu_time = current_cpu_time
            @@last_wall_time = current_wall_time

            # Mark current instance for render
            # Note: Scheduler also marks root, but we need to mark THIS widget for selective rendering
            @@current_instance.try(&.mark_needs_render)
        end

        def measure(constraints : BoxConstraints) : Size
            # Use FIXED width for maximum possible value to prevent size changes
            # This ensures background memorization works correctly (no layout needed on CPU update)
            max_text = "CPU: 100.0%"
            max_text_size = measure_text(max_text, font_size)

            # Add padding
            width = max_text_size.width + PADDING_H * 2
            height = max_text_size.height + PADDING_V * 2

            size = Size.new(width, height)
            constraints.constrain(size)
        end

        def perform_layout(constraints : BoxConstraints, position : Vec2)
            size = measure(constraints)
            @bounds = Rect.new(position, size)
        end

        private def format_text : String
            "CPU: #{"%.1f" % @@cpu_percent}%"
        end

        # Generate primitives for rendering
        # Primitives are in widget-local coordinates (0,0 origin)
        # Renderer will add widget.bounds offset when drawing
        def to_primitives(bounds : Rect) : Array(DrawPrimitive)
            text = format_text

            # Use full widget bounds for background (prevents artifacts when text shrinks)
            # Don't use dynamic text width - when text shrinks, background must still cover old pixels
            local_bounds = Rect.new(0.0, 0.0, bounds.width, bounds.height)

            # Position text with padding (widget-local coordinates)
            text_x = 0.0 + PADDING_H
            text_y = 0.0 + PADDING_V

            primitives do
                # Fully opaque background covering full widget bounds
                fill_rect(local_bounds, @background_color)

                # Text
                draw_text(text, Vec2.new(text_x, text_y), @text_color, @font_scale)
            end
        end

        # CPUMonitor is display-only (not clickable) - pass clicks through to layers below
        def hit_test(point : Vec2) : Widget?
            nil
        end
    end
end
