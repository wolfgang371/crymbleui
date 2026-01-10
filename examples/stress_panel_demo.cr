require "../src/crymble"

# FlashingButton - Button that flashes when selected
class FlashingButton < CrymbleUI::Button
  reconcile_property timer_id : Int32? = nil
  reconcile_property flash_on : Bool = false
  reconcile_property base_background_color : CrymbleUI::Color = CrymbleUI::Color.new(0, 0, 0, 0)
  reconcile_property base_border_color : CrymbleUI::Color = CrymbleUI::Color.new(0, 0, 0, 0)

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

  def start_flashing : Int32
    return @timer_id.not_nil! if @timer_id

    @flash_on = true
    update_colors

    timer_id = schedule_timer(400.milliseconds, repeating: true) {
      @flash_on = !@flash_on
      update_colors
    }
    @timer_id = timer_id
    timer_id
  end

  def stop_flashing
    if timer_id = @timer_id
      cancel_timer(timer_id)
      @timer_id = nil
      @flash_on = false
      update_colors
    end
  end

  private def update_colors
    if @flash_on
      self.background_color = CrymbleUI::Color.new(255, 165, 0, 255)
      self.border_color = CrymbleUI::Color.new(255, 140, 0, 255)
    else
      self.background_color = @base_background_color
      self.border_color = @base_border_color
    end
  end
end

# Stress Panel Demo: 400 buttons in a resizable panel
class StressPanelDemo < CrymbleUI::App
  ROWS          = 20
  COLS          = 20
  TOTAL_BUTTONS = ROWS * COLS

  state click_count : Int32 = 0
  state last_clicked : String = "none"

  @selected_button_id : String? = nil
  @active_timer_id : Int32? = nil

  def build : CrymbleUI::Widget
    window("CrymbleUI - Stress Test in Panel", 1200, 900) do
      # Instructions
      vstack(spacing: 5.0) do
        cpu_monitor
        text(
          "Stress Panel Demo: #{TOTAL_BUTTONS} Buttons in Resizable Panel",

          font_scale: 2,
          color: CrymbleUI::Color.new(0, 100, 180, 255)
        )

        text(
          "• Drag panel by title bar (test event coalescing)",
          font_scale: -1
        )

        text(
          "• Resize panel edges (test clipping)",
          font_scale: -1
        )

        text(
          "• Click buttons inside panel",
          font_scale: -1
        )

        text(
          "Clicks: #{@click_count} | Last: #{@last_clicked}",

          font_scale: -1,
          color: CrymbleUI::Color.new(180, 0, 0, 255)
        )
      end

      # Stress test panel with 400 buttons
      window_panel(
        "Stress Test (#{TOTAL_BUTTONS} buttons)",
        x: 50.0,
        y: 150.0,
        width: 700.0,
        height: 600.0,
      ) do
        vstack(spacing: 2.0) do
          # Create 20x20 grid of buttons
          ROWS.times do |row|
            hstack(spacing: 2.0) do
              COLS.times do |col|
                button_label = "#{row},#{col}"
                button_id = "btn_#{row}_#{col}"

                btn = FlashingButton.new(
                  button_label,
                  font_scale: -5,
                  padding: 3.0
                ) {
                  # Cancel old timer before state change
                  @active_timer_id.try { |id| CrymbleUI::Widget.scheduler.cancel(id) }
                  @active_timer_id = nil

                  @selected_button_id = button_id

                  self.click_count += 1
                  self.last_clicked = button_label
                }

                # Restore flashing after rebuild
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
end

# Run the demo
puts "Starting Stress Panel Demo..."
puts "Features to test:"
puts "  • Drag panel slowly to test event coalescing"
puts "  • Resize panel smaller to test content clipping"
puts "  • Click buttons inside panel to test hit testing"
puts "  • #{StressPanelDemo::TOTAL_BUTTONS} buttons inside a draggable/resizable panel"
puts ""

CrymbleUI.run(StressPanelDemo.new)
