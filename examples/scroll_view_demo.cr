require "../src/crymble"

class ScrollViewDemoApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("ScrollView Demo", 1000, 600) do
      # CPU monitor overlay in top-right corner
      aligned_layer(align: CrymbleUI::Alignment::TopRight, margin: 10.0, z_index: 100) do
        cpu_monitor
      end

      vstack(padding: 10.0, spacing: 10.0) do
        text("ScrollView Demo - Three Scroll Directions", color: CrymbleUI::Color.new(0, 0, 0, 255), font_scale: 2)

        # Three scroll views horizontally
        expanded do
          hstack(spacing: 10.0) do
            # 1. Vertical scrolling (left)
            expanded do
              vstack(spacing: 5.0) do
                text("Vertical", color: CrymbleUI::Color.new(0, 100, 180, 255), font_scale: 1)
                expanded do
                  scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, spacing: 5.0, padding: 5.0, id: "vertical_scroll") do
                    32.times do |i|
                      button("V-Button #{i + 1}") do
                        puts "Clicked V-Button #{i + 1}"
                      end
                    end
                  end
                end
              end
            end

            # 2. Horizontal scrolling (center)
            expanded do
              vstack(spacing: 5.0) do
                text("Horizontal", color: CrymbleUI::Color.new(0, 100, 180, 255), font_scale: 1)
                expanded do
                  scroll_view(direction: CrymbleUI::ScrollDirection::Horizontal, spacing: 5.0, padding: 5.0, id: "horizontal_scroll") do
                    32.times do |i|
                      button("H-#{i + 1}") do
                        puts "Clicked H-Button #{i + 1}"
                      end
                    end
                  end
                end
              end
            end

            # 3. Both directions (right)
            expanded do
              vstack(spacing: 5.0) do
                text("Both", color: CrymbleUI::Color.new(0, 100, 180, 255), font_scale: 1)
                expanded do
                  scroll_view(direction: CrymbleUI::ScrollDirection::Both, padding: 5.0, id: "both_scroll") do
                    # Grid of buttons (wide and tall content)
                    vstack(spacing: 5.0) do
                      32.times do |row|
                        hstack(spacing: 5.0) do
                          32.times do |col|
                            button("#{row},#{col}") do
                              puts "Clicked (#{row}, #{col})"
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

# Run the application
app = ScrollViewDemoApp.new
CrymbleUI.run(app)
