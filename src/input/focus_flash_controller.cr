require "../core/widget"
require "../core/scheduler"

module CrymbleUI
  # Controls the 0.6s flashing animation for focused widgets
  # 0.3s normal appearance, 0.3s highlighted (lighter color)
  class FocusFlashController
    FLASH_HALF_MS = 300  # Each phase: 300ms

    @current_widget : Widget? = nil
    @timer_id : Int32? = nil
    @highlighted : Bool = false

    def initialize
    end

    def start_flash(widget : Widget)
      # Stop flash on previous widget if any
      stop_flash(@current_widget) if @current_widget

      @current_widget = widget
      # Start HIGHLIGHTED for immediate visual feedback when focus changes
      # (user reported: "initial flash state of new button is 'off' - bad")
      @highlighted = true
      widget.focus_highlighted = true

      # Schedule repeating timer for flash animation
      @timer_id = Widget.scheduler.schedule(FLASH_HALF_MS.milliseconds, repeating: true) do
        toggle_flash
      end
    end

    def stop_flash(widget : Widget?)
      return unless widget
      return unless @current_widget == widget

      # Cancel timer
      if timer_id = @timer_id
        Widget.scheduler.cancel(timer_id)
        @timer_id = nil
      end

      # Reset widget to normal appearance
      widget.focus_highlighted = false
      @current_widget = nil
      @highlighted = false
    end

    def toggle_flash
      return unless widget = @current_widget
      @highlighted = !@highlighted
      widget.focus_highlighted = @highlighted
    end

    def timer_running? : Bool
      !@timer_id.nil?
    end

    # Transfer flash to new widget without restarting timer
    # Used during reconciliation when widget instances are replaced
    def transfer_widget(old_widget : Widget, new_widget : Widget)
      return unless @current_widget == old_widget
      @current_widget = new_widget
      # Sync the highlighted state to the new widget
      new_widget.focus_highlighted = @highlighted
    end
  end
end
