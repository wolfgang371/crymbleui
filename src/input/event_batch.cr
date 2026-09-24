require "../csfml3/wrapper"
require "../core/app"

module CrymbleUI
  # One frame's worth of input: the run loop dispatches queued events, then renders once. Kept apart
  # from SFMLRenderer so a spec can drive the same batching over events it queues itself.
  #
  # EVERY EVENT IS DISPATCHED AGAINST THE STATE THE EVENTS BEFORE IT PRODUCED. A handler that changes
  # structure only REQUESTS the work - a rebuild, or a matrix's invalidate_all! - and the frame after
  # the batch applies it; an event dispatched in between acts on the state that work replaces. So a
  # batch ENDS at the first event that raises the input barrier (App#input_waits_for_frame?), and the
  # rest stay queued for the next iteration, after the frame. Under a burst (a script typing into embrace, 2026-09-23) Ctrl+R added a record while
  # the two Tabs queued behind it still navigated the old one-row grid, wrapped back to row 0 and
  # typed the next record over the first. Coalescing is untouched where nothing is rebuilt: a drag's
  # mouse moves still share one frame.
  module EventBatch
    # Dispatches events from `poll` until it runs dry or the input barrier is up. Returns how many were
    # dispatched.
    def self.drain(app : App, poll : -> LibCSFML::Event?, & : LibCSFML::Event ->) : Int32
      count = 0
      until app.input_waits_for_frame?
        break unless event = poll.call
        yield event
        count += 1
      end
      count
    end
  end
end
