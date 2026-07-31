module CrymbleUI
  # DIAGNOSTIC (env-gated, zero cost when unset): trace every keyboard event from the moment SFML
  # hands it over to the moment a widget accepts or refuses it.
  #
  # It exists for one user report (2026-07-29): "enter a value in a cell, cursor down, repeat
  # quickly — keys get lost, especially the character". Confirmed present in the shipped build, and
  # confirmed by the reporter to be load-dependent: typing slowly is clean, and one open Shape is
  # clean; it needs several Shapes (a ~200 ms rebuild frame) to appear.
  #
  # THE QUESTION IT ANSWERS FIRST — everything else is secondary:
  #
  #   Does the count of characters SFML delivered match the count a widget accepted?
  #     received > accepted  =>  we drop them, and the per-event columns say exactly where.
  #     received == accepted =>  they never reached us; the loss is upstream in SFML/X11 (or in
  #                              window focus), and no amount of widget-level work will fix it.
  #
  # A headless spec cannot settle this: it fabricates the event stream it then measures. Two
  # hypotheses have already died that way — "reconcile clears focus" and "the proxy is nil between
  # rebuild and layout" — the latter because the run loop polls events at the TOP of an iteration,
  # so a keystroke can never land between a rebuild and its layout. What is left is only observable
  # against real SFML delivery under a real frame load.
  #
  # Usage:  CRYMBLE_INPUTLOG=/tmp/embrace-input.tsv ./bin/embrace
  # One TSV line per keyboard event, buffered, flushed every 64 events and on exit.
  class InputLog
    @@path : String? = ENV["CRYMBLE_INPUTLOG"]?
    @@io : File? = nil
    @@buffer = [] of String
    @@t0 : Time::Span = Time.monotonic
    @@last_event_at : Time::Span? = nil

    # Running totals, printed in the trailer so the headline question is answered without
    # post-processing.
    @@received = 0
    @@accepted = 0
    @@refused = 0
    @@no_focus = 0

    def self.enabled? : Bool
      !@@path.nil?
    end

    # Position within the batch that poll_event is currently draining. The first trace showed
    # refusals arriving 1-3 ms after an accepted character — far faster than a human types, i.e.
    # events QUEUED while the app was busy and delivered together once polling resumed. If every
    # refusal turns out to be "not first in its batch", that is the mechanism, stated exactly.
    @@batch_index = 0

    def self.batch_begin : Nil
      @@batch_index = 0
    end

    def self.next_in_batch : Int32
      @@batch_index += 1
    end

    # Every rendered frame, so a burst can be correlated with the frame that preceded it. The first
    # trace only carried the last frame's cost at event time and showed a flat ~16 ms, which
    # contradicts a ten-Shape rebuild — either the load was not what we assumed or the sample point
    # was wrong. Logging frames outright removes the guess.
    # THE LAG, MEASURED DIRECTLY. `matrix_rendered` says the matrix content layer actually
    # re-rendered this frame; paired with the timestamp of the last commit it gives the only number
    # that matters to the user — how long after typing did the cell get redrawn. Cost is one boolean
    # test per frame. (The previous attempt at this sampled the layer buffer with get_pixels, which
    # does a full GPU->CPU texture copy PER CALL; twenty-four of those per layer per frame made the
    # app unusable. Never read pixels back to answer a timing question.)
    @@last_write_at : Time::Span? = nil
    @@lag_max = 0.0
    @@lag_slow = 0

    def self.record_frame(total_ms : Float64, did_layout : Bool, rebuilt : Bool,
                          matrix_rendered : Bool = false) : Nil
      return if @@path.nil?
      if matrix_rendered && (wrote_at = @@last_write_at)
        @@last_write_at = nil
        lag = (Time.monotonic - wrote_at).total_milliseconds
        @@lag_max = lag if lag > @@lag_max
        @@lag_slow += 1 if lag > 400.0
        @@buffer << ["%.1f" % (Time.monotonic - @@t0).total_milliseconds, "REPAINT", "matrix",
                     lag > 400.0 ? "SLOW" : "ok", "lag=#{lag.round(1)}ms",
                     "frame=#{total_ms.round(1)}ms", "-", "-"].join('\t')
      end
      return if total_ms < 5.0 # idle vsync frames would drown the trace
      @@buffer << ["%.1f" % (Time.monotonic - @@t0).total_milliseconds, "FRAME", "-", "-", "-",
                   (rebuilt ? "rebuilt" : (did_layout ? "laid_out" : "-")),
                   "%.1f" % total_ms, "-"].join('\t')
      flush if @@buffer.size >= 64
    end

    # `outcome` is what the dispatch returned: true = a widget took it, false = a widget refused it
    # (the silent-drop case), nil = there was no focused widget at all.
    def self.record(kind : String, label : String, outcome : Bool?, focused : Widget?,
                    pending_rebuild : Bool, frame_ms : Float64) : Nil
      return if @@path.nil?
      now = Time.monotonic
      gap = @@last_event_at.try { |t| (now - t).total_milliseconds } || 0.0
      @@last_event_at = now

      # Only CHARACTERS feed the headline tally. Key presses (cursor-down) are traced for rhythm,
      # but they report no outcome, and counting them as NO_FOCUS would corrupt the one number the
      # whole trace exists to produce.
      if kind == "text"
        @@received += 1
        case outcome
        when true  then @@accepted += 1
        when false then @@refused += 1
        else            @@no_focus += 1
        end
      end

      @@buffer << [
        (now - @@t0).total_milliseconds.round(1),
        kind,
        label,
        outcome.nil? ? "NO_FOCUS" : (outcome ? "accepted" : "REFUSED"),
        focused.nil? ? "-" : focused.class.name.split("::").last,
        (pending_rebuild ? "rebuild_pending" : "-") + "/batch##{@@batch_index}",
        frame_ms.round(1),      # duration of the most recently rendered frame
        gap.round(1),           # ms since the previous keyboard event
      ].join('\t')

      flush if @@buffer.size >= 64
    end

    # --- commit-vs-paint tracking -------------------------------------------------------------
    # The 2026-07-30 traces showed the pipeline behaving perfectly — 179 frames during a 3.1 s wait,
    # the rebuild frame arriving 161 ms after the keystroke, nothing queued and nothing dropped —
    # while the user still saw no update. So the repaint HAPPENED and drew the wrong content. This
    # pairs each committed value with the value the adapter hands back at the next paint of that
    # cell, which is the difference between "not painted" and "painted stale".
    @@pending_writes = {} of Tuple(Int32, Int32) => String
    @@paint_match = 0
    @@paint_stale = 0

    def self.record_write(row : Int32, col : Int32, value : String) : Nil
      return if @@path.nil?
      @@last_write_at = Time.monotonic
      @@pending_writes[{row, col}] = value
      @@buffer << ["%.1f" % (Time.monotonic - @@t0).total_milliseconds, "WRITE", "#{row},#{col}",
                   value, "-", "-", "-", "-"].join('\t')
      flush if @@buffer.size >= 64
    end

    # Only the FIRST paint after a write is interesting; every other cell paint would drown the file.
    def self.record_paint(row : Int32, col : Int32, value : String) : Nil
      return if @@path.nil?
      expected = @@pending_writes.delete({row, col})
      return if expected.nil?
      ok = value == expected
      ok ? (@@paint_match += 1) : (@@paint_stale += 1)
      @@buffer << ["%.1f" % (Time.monotonic - @@t0).total_milliseconds, "PAINT", "#{row},#{col}",
                   ok ? "match" : "STALE", "wrote=#{expected}", "painted=#{value}", "-", "-"].join('\t')
      flush if @@buffer.size >= 64
    end

    # --- PIXEL WATCH ----------------------------------------------------------------------------
    # Everything measured so far stops one link short of the screen: input arrives, the write lands,
    # the adapter serves fresh data when asked to build the cell widget. Whether those pixels ever
    # reach the matrix's layer buffer has never been observed — and that is the only remaining gap
    # the symptom can live in. This samples the buffer itself, once per rendered frame, and logs the
    # frames where its content actually CHANGES. Correlated with the WRITE lines it answers: after a
    # commit, when (if ever) did the pixels move?
    #
    # get_pixels is a GPU->CPU readback, so this samples a sparse grid rather than the whole surface
    # and only runs when the trace is enabled.
    @@pixel_sig = {} of String => UInt64
    @@pixel_changes = 0

    def self.record_pixels(layer_id : String, sig : UInt64) : Nil
      return if @@path.nil?
      previous = @@pixel_sig[layer_id]?
      return if previous == sig # unchanged: say nothing, or the file drowns
      @@pixel_sig[layer_id] = sig
      return if previous.nil?   # first sight is not a change
      @@pixel_changes += 1
      @@buffer << ["%.1f" % (Time.monotonic - @@t0).total_milliseconds, "PIXELS", "changed", "-",
                   layer_id, "-", "-", "-"].join('\t')
      flush if @@buffer.size >= 64
    end

    def self.flush : Nil
      return if @@buffer.empty?
      if path = @@path
        io = (@@io ||= File.open(path, "w").tap do |f|
          f.puts "# t_ms\tkind\tkey\toutcome\tfocused\tstate\tlast_frame_ms\tgap_ms"
        end)
        @@buffer.each { |line| io.puts line }
        io.flush
        @@buffer.clear
      end
    end

    def self.close : Nil
      return if @@path.nil?
      flush
      if io = @@io
        io.puts "# received=#{@@received} accepted=#{@@accepted} REFUSED=#{@@refused} NO_FOCUS=#{@@no_focus}"
        io.puts "# paints after a commit: match=#{@@paint_match} STALE=#{@@paint_stale} " \
                "never_repainted=#{@@pending_writes.size}"
        io.puts "# pixel changes observed in matrix content buffers: #{@@pixel_changes}"
        io.puts "# commit -> matrix repaint lag: max=#{@@lag_max.round(1)} ms, over 400 ms: #{@@lag_slow}"
        io.puts "# each SLOW line is a commit whose cell went unredrawn that long — the lag, located."
        io.puts "# STALE>0 => the repaint drew pre-commit data. never_repainted>0 => the cell was " \
                "written but never painted again."
        io.puts "# If received == accepted, nothing was dropped in our code — look upstream (SFML/X11)."
        io.close
        @@io = nil
      end
    end
  end
end
