module CrymbleUI
  # Per-frame work ledger — a low-overhead, self-describing profiler that attributes every unit of
  # frame work to (timing bucket, cause, volume) so double/wasted work is visible OFFLINE from the log
  # alone. Written to disk only when ENV["CRYMBLE_WORKLOG"] is set (a path); otherwise every call is a
  # single nil-check (zero cost). Enable in a release build with no recompile:
  #
  #     CRYMBLE_WORKLOG=/tmp/work.tsv ./your_app
  #
  # Design for "not a bottleneck":
  #  - Reads counters that are ALREADY incremented on the hot path (LayerRenderer.frame_*, Widget.*,
  #    App.rebuild_count, …); it adds no per-widget work of its own.
  #  - One TSV line per RENDERED frame (idle frames the pull-trigger skips leave a gap in t_ms — that
  #    gap IS the reactive win, visible in the log). No per-work-item logging, no per-frame File.open.
  #  - The output File is IO::Buffered (Crystal), so a per-frame `puts` is a memcpy into an 8 KB buffer;
  #    an explicit flush every FLUSH_EVERY frames caps loss-on-crash to that window at ~1 syscall/256
  #    frames. Line built with a single interpolation.
  #
  # Every column is PER-FRAME: LayerRenderer.frame_* are zeroed each frame (raw), the monotonic
  # counters (absolute_bounds, panel/popup/state_sweep, collect_widgets, drop_target, row_cache,
  # rebuilds) are logged as this-frame deltas. Column legend is written at the top of the file.
  class FrameWorkLog
    FLUSH_EVERY = 256

    # Column order — keep in lockstep with the header written in `initialize` and the row in `record`.
    COLUMNS = %w[
      frame t_ms dt_ms total_ms layout_ms render_ms composite_ms display_ms
      cause_layout cause_rebuilds cause_mousedown
      layers_total layers_rendered composites vpcache recollect
      widgets_iter widgets_rendered prims empty_leaf container_skips
      blit_plan blit_shift recenter realloc boundary_inval
      panel_walk popup_walk state_sweep collect_widgets drop_target row_cache
      absolute_bounds mark_render measure
    ]

    @io : IO::FileDescriptor?
    @frame : Int32 = 0
    @start = Time.instant
    @last_t = Time.instant
    # monotonic-counter baselines (previous cumulative value) for per-frame deltas
    @p_rebuild : Int32 = 0
    @p_absb : Int32 = 0
    @p_panel : Int32 = 0
    @p_popup : Int32 = 0
    @p_sweep : Int32 = 0
    @p_collect : Int32 = 0
    @p_drop : Int32 = 0
    @p_rowc : Int32 = 0
    @p_markr : Int32 = 0
    @p_meas : Int32 = 0

    def initialize(path : String? = ENV["CRYMBLE_WORKLOG"]?)
      if path && !path.empty?
        io = File.new(path, "w")
        io.puts "# crymbleui frame work-ledger v1"
        io.puts "# one row per RENDERED frame; gaps in t_ms = idle frames the pull-trigger skipped (zero cost)."
        io.puts "# timing buckets: layout=framework recompute, render=widget painting, composite=layer-blit/texture, display=GPU present."
        io.puts "# cause_*: layout=structural relayout ran, rebuilds=App.rebuild() calls this frame, mousedown=pointer held."
        io.puts "# walks (panel/popup/state_sweep/collect_widgets/drop_target/absolute_bounds) = per-frame FLOOR; should not scale with content."
        io.puts "# all columns are PER-FRAME values (frame_* raw; monotonic counters as this-frame deltas)."
        io.puts COLUMNS.join('\t')
        @io = io
        @start = Time.instant
        @last_t = @start
        seed_baselines
      end
    end

    def enabled? : Bool
      !@io.nil?
    end

    # Called once per rendered frame, BEFORE LayerRenderer.reset_frame_counters. The four phase_ms and
    # the two cause booleans are already computed by the caller; every other value is read here from the
    # always-on counters.
    def record(layout_ms : Float64, render_ms : Float64, composite_ms : Float64, display_ms : Float64,
               did_layout : Bool, mouse_down : Bool) : Nil
      io = @io
      return unless io

      now = Time.instant
      dt = (now - @last_t).total_milliseconds
      t = (now - @start).total_milliseconds
      @last_t = now
      @frame += 1
      total = layout_ms + render_ms + composite_ms + display_ms

      # per-frame deltas for the monotonic counters
      reb = App.rebuild_count; d_reb = reb - @p_rebuild; @p_rebuild = reb
      absb = Widget.absolute_bounds_count; d_absb = absb - @p_absb; @p_absb = absb
      pan = Widget.panel_walk_visits; d_pan = pan - @p_panel; @p_panel = pan
      pop = Widget.popup_walk_visits; d_pop = pop - @p_popup; @p_popup = pop
      swe = Widget.state_sweep_visits; d_swe = swe - @p_sweep; @p_sweep = swe
      col = LayerRenderer.collect_widgets_visits; d_col = col - @p_collect; @p_collect = col
      dro = DragManager.drop_target_visits; d_dro = dro - @p_drop; @p_drop = dro
      row = VirtualMatrix.row_cache_rebuild_rows; d_row = row - @p_rowc; @p_rowc = row
      mkr = Widget.mark_render_count; d_mkr = mkr - @p_markr; @p_markr = mkr
      mea = Widget.measure_count; d_mea = mea - @p_meas; @p_meas = mea

      io.puts String.build { |s|
        s << @frame << '\t' << t.round(2) << '\t' << dt.round(2) << '\t'
        s << total.round(3) << '\t' << layout_ms.round(3) << '\t' << render_ms.round(3) << '\t'
        s << composite_ms.round(3) << '\t' << display_ms.round(3) << '\t'
        s << (did_layout ? 1 : 0) << '\t' << d_reb << '\t' << (mouse_down ? 1 : 0) << '\t'
        s << LayerRenderer.frame_layers_total << '\t' << LayerRenderer.frame_layers_needing_render << '\t'
        s << LayerRenderer.frame_composite_count << '\t' << LayerRenderer.frame_viewport_cache_count << '\t'
        s << LayerRenderer.frame_layer_recollect_count << '\t'
        s << LayerRenderer.frame_widgets_iterated << '\t' << LayerRenderer.frame_widget_count << '\t'
        s << LayerRenderer.frame_primitive_count << '\t' << LayerRenderer.frame_empty_leaf_primitives << '\t'
        s << LayerRenderer.frame_pure_container_skips << '\t'
        s << LayerRenderer.frame_blit_plan_count << '\t' << LayerRenderer.frame_blit_shift_count << '\t'
        s << LayerRenderer.frame_full_recenter_count << '\t' << LayerRenderer.frame_realloc_count << '\t'
        s << LayerRenderer.frame_boundary_cells_invalidated << '\t'
        s << d_pan << '\t' << d_pop << '\t' << d_swe << '\t' << d_col << '\t' << d_dro << '\t' << d_row << '\t'
        s << d_absb << '\t' << d_mkr << '\t' << d_mea
      }

      io.flush if @frame % FLUSH_EVERY == 0
    end

    def close : Nil
      if io = @io
        io.flush
        io.close
        @io = nil
      end
    end

    # Baseline the monotonic counters at construction so the first frame's deltas aren't inflated by
    # whatever accumulated during startup/build.
    private def seed_baselines
      @p_rebuild = App.rebuild_count
      @p_absb = Widget.absolute_bounds_count
      @p_panel = Widget.panel_walk_visits
      @p_popup = Widget.popup_walk_visits
      @p_sweep = Widget.state_sweep_visits
      @p_collect = LayerRenderer.collect_widgets_visits
      @p_drop = DragManager.drop_target_visits
      @p_rowc = VirtualMatrix.row_cache_rebuild_rows
      @p_markr = Widget.mark_render_count
      @p_meas = Widget.measure_count
    end
  end
end
