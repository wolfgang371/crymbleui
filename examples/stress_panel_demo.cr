require "../src/crymble-ui"

# Stress Panel Demo: the SAME 400-button grid in two panels — floored (never clips) vs ScrollView.
#
# The "flashing selected cell" is a LOCALIZED reactive update, the way every flash in crymbleui works
# (text_input cursor, focus highlight, …): one App-owned clock toggles a `@blink_on` phase and re-colours
# ONLY the selected cell(s) via find(id) + the reactive colour setter — a single-widget re-render, NOT an
# app `state` change. A `state`-driven blink would `app.rebuild` every 400ms, and a rebuild blanket-repaints
# all 800 cells (app.cr:372) → ~70% CPU and an unresponsive window. Buttons carry stable ids ("gf::r,c" /
# "gs::r,c") so the clock can reach the current instance after any rebuild; build() derives each cell's
# initial colour from the same (selected, blink_on), so a click-rebuild shows the right colour with no flicker.
class StressPanelDemo < CrymbleUI::App
  ROWS          = 20
  COLS          = 20
  TOTAL_BUTTONS = ROWS * COLS

  ORANGE        = CrymbleUI::Color.new(255, 165, 0, 255)
  ORANGE_BORDER = CrymbleUI::Color.new(255, 140, 0, 255)
  BASE          = CrymbleUI::Color.new(0, 120, 215, 255)
  BASE_BORDER   = CrymbleUI::Color.new(0, 100, 180, 255)

  state click_count : Int32 = 0
  state last_clicked : String = "none"

  # Plain ivars — the flash must NOT go through app `state` (that rebuilds). @selected keys by grid prefix.
  @selected = {} of String => String # "gf" | "gs" => selected label
  @blink_on = false
  @clock : Int32? = nil

  # One repeating clock (started on the first click). Each tick flips the phase and re-colours ONLY the
  # selected cell(s) in place — find(id) + colour setter marks that one widget for re-render, no rebuild.
  private def ensure_clock
    return if @clock
    return unless scheduler_ready?
    @clock = CrymbleUI::Widget.scheduler.schedule(400.milliseconds, repeating: true) do
      @blink_on = !@blink_on
      repaint_selected
    end
  end

  private def scheduler_ready? : Bool
    CrymbleUI::Widget.scheduler
    true
  rescue
    false
  end

  private def lit?(prefix : String, label : String) : Bool
    @blink_on && @selected[prefix]? == label
  end

  private def repaint_selected
    @selected.each do |prefix, label|
      if btn = find("#{prefix}::#{label}").as?(CrymbleUI::Button)
        btn.background_color = lit?(prefix, label) ? ORANGE : BASE
        btn.border_color = lit?(prefix, label) ? ORANGE_BORDER : BASE_BORDER
      end
    end
  end

  private def click(prefix : String, label : String)
    ensure_clock
    @selected[prefix] = label
    @blink_on = true
    # click_count/last_clicked are state → one rebuild (rare) updates the counter text; build() re-derives
    # every cell's colour, so the newly-selected cell is orange immediately.
    self.click_count += 1
    self.last_clicked = label
  end

  private def grid(prefix : String) : CrymbleUI::VStack
    g = CrymbleUI::VStack.new(id: prefix, spacing: 2.0)
    ROWS.times do |row|
      hs = CrymbleUI::HStack.new(spacing: 2.0)
      COLS.times do |col|
        label = "#{row},#{col}"
        hs.add_child(CrymbleUI::Button.new(
          label,
          id: "#{prefix}::#{label}",
          font_scale: -5,
          padding: 3.0,
          background_color: lit?(prefix, label) ? ORANGE : BASE,
          border_color: lit?(prefix, label) ? ORANGE_BORDER : BASE_BORDER,
        ) { click(prefix, label) })
      end
      g.add_child(hs)
    end
    g
  end

  def build : CrymbleUI::Widget
    window("CrymbleUI - Floor vs Scroll", 1400, 950) do
      # Instructions
      vstack(spacing: 5.0) do
        cpu_monitor
        text(
          "The SAME #{TOTAL_BUTTONS}-button grid in two panels — drag each panel's right edge inward:",
          font_scale: 2,
          color: CrymbleUI::Color.new(0, 100, 180, 255)
        )
        text(
          "• LEFT (floored, no ScrollView): the panel FLOORS at the grid's width — it won't shrink past the content, so nothing clips.",
          font_scale: -1
        )
        text(
          "• RIGHT (ScrollView, opt-in): the panel shrinks freely and the ScrollView scrolls the grid.",
          font_scale: -1
        )
        text(
          "Clicks: #{@click_count} | Last: #{@last_clicked}",
          font_scale: -1,
          color: CrymbleUI::Color.new(180, 0, 0, 255)
        )
      end

      # LEFT — grid directly: floors at the grid's content size, never clips.
      window_panel("Floored — never clips", x: 20.0, y: 170.0, width: 700.0, height: 620.0) do
        current_container.add_child(grid("gf"))
      end

      # RIGHT — grid in a ScrollView(Both): opt-in shrink + scroll.
      window_panel("ScrollView(Both) — shrinks + scrolls", x: 750.0, y: 170.0, width: 420.0, height: 620.0) do
        scroll = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Both, id: "scroll")
        scroll.set_content(grid("gs"))
        current_container.add_child(scroll)
      end
    end
  end
end

# Run the demo
puts "Starting Floor-vs-Scroll Demo..."
puts "Both panels hold the SAME #{StressPanelDemo::TOTAL_BUTTONS}-button grid:"
puts "  • LEFT  (floored)    — drag the right edge in: it stops at the grid width (no clip)"
puts "  • RIGHT (ScrollView) — drag the right edge in: it shrinks and scrolls"
puts "  • Click a cell: it flashes orange (localized — one cell re-renders per tick, no rebuild)"
puts ""

CrymbleUI.run(StressPanelDemo.new)
