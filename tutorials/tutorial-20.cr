# Tutorial 20: Layers and Alignment
# ==================================
# Floating overlays with automatic positioning.
#
# Key concepts:
# - layer(x:, y:) creates floating overlay at explicit position
# - aligned_layer(align:) uses 9-point grid: TopLeft, Center, BottomRight, etc.
# - Layers auto-size to content, or use width:/height: for explicit size
# - z_index controls layer stacking order (higher = on top)
# - Transparent layers allow click-through to content below
#
# Run with: shards build tutorial-20 && ./bin/tutorial-20

require "../src/crymble-ui"

class LayersDemo < CrymbleUI::App
  state click_count : Int32 = 0

  def build : CrymbleUI::Widget
    window("Layers Demo", 600, 400) do
      # Main content (z_index 0 by default)
      vstack(spacing: 15.0, padding: 20.0) do
        text("Main Content Area", font_scale: 3)
        text("Click the button below - overlays don't block it!")

        button("Click me! (#{click_count})") do
          self.click_count += 1
        end

        text("Layers render on top but transparent areas allow click-through.")
      end

      # =================================================================
      # Example 1: aligned_layer with TopRight (common pattern for HUDs)
      # =================================================================
      aligned_layer(align: CrymbleUI::Alignment::TopRight, margin: 10.0, z_index: 100) do
        hstack(padding: 8.0, background_color: CrymbleUI::Color.new(50, 50, 50, 200)) do
          text("TopRight", font_scale: -1, color: CrymbleUI::Color.new(255, 255, 255, 255))
        end
      end

      # =================================================================
      # Example 2: aligned_layer with BottomLeft
      # =================================================================
      aligned_layer(align: CrymbleUI::Alignment::BottomLeft, margin: 10.0, z_index: 100) do
        hstack(padding: 8.0, background_color: CrymbleUI::Color.new(100, 50, 50, 200)) do
          text("BottomLeft", font_scale: -1, color: CrymbleUI::Color.new(255, 255, 255, 255))
        end
      end

      # =================================================================
      # Example 3: Center-aligned layer (auto-sized to content)
      # =================================================================
      aligned_layer(
        align: CrymbleUI::Alignment::BottomCenter,
        margin: 10.0,
        z_index: 50
      ) do
        hstack(padding: 10.0, background_color: CrymbleUI::Color.new(50, 80, 120, 220)) do
          text("BottomCenter", font_scale: -1, color: CrymbleUI::Color.new(255, 255, 255, 255))
        end
      end

      # =================================================================
      # Example 4: Basic layer() with explicit position
      # =================================================================
      layer(x: 10.0, y: 10.0, z_index: 200) do
        hstack(padding: 8.0, background_color: CrymbleUI::Color.new(50, 100, 50, 200)) do
          text("Explicit x=10, y=10", font_scale: -1, color: CrymbleUI::Color.new(255, 255, 255, 255))
        end
      end
    end
  end
end

CrymbleUI.run(LayersDemo.new)
