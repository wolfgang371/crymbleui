require "../src/crymble"

# FlashingButton - Button that flashes when selected
# Demonstrates scheduler-based animations
class FlashingButton < CrymbleUI::Button
  @timer_id : Int32?
  @flash_on : Bool = false
  @base_background_color : CrymbleUI::Color
  @base_border_color : CrymbleUI::Color

  def initialize(
    text : String,
    id : String? = nil,
    font_scale : Int32 = 0,
    text_color : CrymbleUI::Color = CrymbleUI::Color.new(255, 255, 255, 255),
    background_color : CrymbleUI::Color = CrymbleUI::Color.new(0, 120, 215, 255),
    border_color : CrymbleUI::Color = CrymbleUI::Color.new(0, 100, 180, 255),
    padding : Float64 = 10.0,
    &block : -> Nil
  )
    super(text, shortcut: nil, id: id, font_scale: font_scale, text_color: text_color, background_color: background_color, border_color: border_color, padding: padding, on_click: block)
    @base_background_color = background_color
    @base_border_color = border_color
  end

  # Start flashing animation and return timer ID
  def start_flashing : Int32
    return @timer_id.not_nil! if @timer_id # Already flashing

    @flash_on = true
    update_colors

    # Toggle every 400ms
    timer_id = schedule_timer(400.milliseconds, repeating: true) {
      @flash_on = !@flash_on
      update_colors
    }
    @timer_id = timer_id
    timer_id
  end

  # Stop flashing animation
  def stop_flashing
    if timer_id = @timer_id
      cancel_timer(timer_id)
      @timer_id = nil
      @flash_on = false
      update_colors
    end
  end

  # Update colors based on flash state
  private def update_colors
    if @flash_on
      # Highlight - bright orange
      self.background_color = CrymbleUI::Color.new(255, 165, 0, 255)
      self.border_color = CrymbleUI::Color.new(255, 140, 0, 255)
    else
      # Base colors
      self.background_color = @base_background_color
      self.border_color = @base_border_color
    end
  end
end

# Stress Test: 400 buttons (20x20 grid)
# Demonstrates scheduler-based animations with low CPU usage
class StressTest < CrymbleUI::App
  ROWS          = 20
  COLS          = 20
  TOTAL_BUTTONS = ROWS * COLS

  state click_count : Int32 = 0
  state last_clicked : String = "none"

  # Persist flashing state across rebuilds (state changes trigger rebuilds)
  @selected_button_id : String? = nil
  @active_timer_id : Int32? = nil

  def build : CrymbleUI::Widget
    # start_time = Time.monotonic  # Uncomment to measure build time
    window("CrymbleUI Stress Test - #{TOTAL_BUTTONS} Buttons", 1000, 800) do
      vstack(spacing: 5.0) do
        cpu_monitor
        text(
          "Stress Test: #{TOTAL_BUTTONS} Buttons",

          font_scale: 3,
          color: CrymbleUI::Color.new(0, 100, 180, 255)
        )

        text(
          "Clicks: #{@click_count} | Last: #{@last_clicked}",

          font_scale: 0
        )

        # Create 20x20 grid of buttons
        ROWS.times do |row|
          hstack(spacing: 5.0) do
            COLS.times do |col|
              button_label = "#{row},#{col}"
              button_id = "btn_#{row}_#{col}"

              btn = FlashingButton.new(
                button_label,
                font_scale: -3,
                padding: 5.0
              ) {
                # Cancel old timer BEFORE state change to prevent delay
                @active_timer_id.try { |id| CrymbleUI::Widget.scheduler.cancel(id) }
                @active_timer_id = nil

                @selected_button_id = button_id

                self.click_count += 1
                self.last_clicked = button_label
              }

              # Restore flashing after rebuild: cancel old timer, start new one
              # (Each rebuild creates new widget tree, so must restart animation)
              if @selected_button_id == button_id
                @active_timer_id.try { |id| CrymbleUI::Widget.scheduler.cancel(id) }
                @active_timer_id = btn.start_flashing
              end

              current_container.add_child(btn)
            end
          end
        end
      end
    end
  end
end

# Main
puts "Starting stress test with #{StressTest::TOTAL_BUTTONS} buttons..."
puts "This tests widget creation, layout, rendering, and interaction."
puts "Try clicking buttons and resizing the window!"
# Run the stress test - window config is now declarative!
CrymbleUI.run(StressTest.new)
