require "./types"

module CrymbleUI
    # Timer-based scheduler for animations and delayed actions
    # Manages a priority queue of timers sorted by wake time
    class Scheduler
        # Timer entry in the queue
        private class Timer
            getter id : Int32
            property wake_time : Time::Instant  # Monotonic time
            getter interval : Time::Span?
            getter callback : Proc(Nil)

            def initialize(@id : Int32, @wake_time : Time::Instant, @interval : Time::Span?, @callback : Proc(Nil))
            end

            def repeating?
                !@interval.nil?
            end
        end

        @timers : Array(Timer)
        @next_id : Int32
        @redraw_callback : Proc(Nil)?
        @cancelled_ids : Set(Int32) = Set(Int32).new

        def initialize
            @timers = [] of Timer
            @next_id = 0
        end

        # Set callback to trigger redraw when timers fire
        # This allows animated widgets to automatically trigger redraws
        def on_timer_fired(&block : -> Nil)
            @redraw_callback = block
        end

        # Schedule a timer
        # Returns timer ID that can be used to cancel
        def schedule(delay : Time::Span, repeating : Bool = false, &block : -> Nil) : Int32
            id = @next_id
            @next_id += 1

            wake_time = Time.instant + delay
            interval = repeating ? delay : nil

            timer = Timer.new(id, wake_time, interval, block)
            @timers << timer

            # Keep sorted by wake time
            @timers.sort_by! &.wake_time

            id
        end

        # Cancel a timer by ID
        def cancel(timer_id : Int32)
            @timers.reject! { |t| t.id == timer_id }
            @cancelled_ids.add(timer_id)
        end

        # Get time until next timer fires
        # Returns nil if no timers scheduled
        def next_wake_time : Time::Span?
            return nil if @timers.empty?

            now = Time.instant
            next_timer = @timers.first
            remaining = next_timer.wake_time - now

            # Return 0 if already expired
            remaining > Time::Span.zero ? remaining : Time::Span.zero
        end

        # Run all expired timers
        # Returns number of timers that fired
        def run_expired_timers : Int32
            return 0 if @timers.empty?

            now = Time.instant
            fired_count = 0

            # Find all expired timers
            expired = [] of Timer
            @timers.each do |timer|
                break if timer.wake_time > now
                expired << timer
            end

            # Remove expired timers
            @timers.shift(expired.size)

            # Fire callbacks and reschedule repeating timers
            @cancelled_ids.clear
            expired.each do |timer|
                timer.callback.call
                fired_count += 1

                # Reschedule if repeating — but skip if callback self-cancelled
                if timer.repeating? && timer.interval && !@cancelled_ids.includes?(timer.id)
                    timer.wake_time = Time.instant + timer.interval.not_nil!
                    @timers << timer
                end
            end

            # Re-sort if we rescheduled any timers
            @timers.sort_by! &.wake_time unless expired.select(&.repeating?).empty?

            # Trigger redraw if any timers fired
            if fired_count > 0
                @redraw_callback.try(&.call)
            end

            fired_count
        end

        # Check if any timers are scheduled
        def has_timers? : Bool
            !@timers.empty?
        end

        # Clear all timers
        def clear
            @timers.clear
        end
    end
end
