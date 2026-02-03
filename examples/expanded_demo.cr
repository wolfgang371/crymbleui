require "../src/crymble-ui"

# Demo application showcasing the Expanded widget for flexible layouts
class ExpandedDemo < CrymbleUI::App
  # Current demo mode
  state demo_mode : Int32 = 0

  DEMO_NAMES = [
    "1. HStack: Single Expanded",
    "2. HStack: Multiple Expanded",
    "3. VStack: Single Expanded",
    "4. VStack: Header/Content/Footer",
    "5. Nested: Sidebar + Content",
    "6. Equal Columns",
    "7. Flex Factors (1:2:1)",
    "8. Spacer Widget",
    "9. Flexible vs Expanded",
  ]

  def build : CrymbleUI::Widget
    window("Expanded Widget Demo", 800, 600) do
      vstack(spacing: 0.0, padding: 0.0) do
        # Header with demo selector
        hstack(spacing: 10.0, padding: 10.0, background_color: color(50, 50, 60)) do
          text("Expanded Demo", font_scale: 3, color: color(255, 255, 255))

          # Spacer pushes navigation to the right
          spacer

          button("< Prev", padding: 8.0) do
            self.demo_mode = (self.demo_mode - 1) % DEMO_NAMES.size
          end

          text(DEMO_NAMES[@demo_mode], font_scale: 1, color: color(200, 200, 200))

          button("Next >", padding: 8.0) do
            self.demo_mode = (self.demo_mode + 1) % DEMO_NAMES.size
          end
        end

        # Main content area - expands to fill remaining space (both axes)
        expanded(fill_area: true) do
          case @demo_mode
          when 0 then demo_hstack_single_expanded
          when 1 then demo_hstack_multiple_expanded
          when 2 then demo_vstack_single_expanded
          when 3 then demo_vstack_header_content_footer
          when 4 then demo_nested_sidebar_content
          when 5 then demo_equal_columns
          when 6 then demo_flex_factors
          when 7 then demo_spacer
          when 8 then demo_flexible_vs_expanded
          else demo_hstack_single_expanded
          end
        end

        # Footer
        hstack(spacing: 0.0, padding: 5.0, background_color: color(40, 40, 50)) do
          text("Use Prev/Next to switch demos. Expanded children fill remaining space.",
               font_scale: -1, color: color(150, 150, 150))
        end
      end
    end
  end

  # Demo 1: HStack with single expanded child
  private def demo_hstack_single_expanded
    vstack(spacing: 10.0, padding: 20.0) do
      text("HStack with Single Expanded", font_scale: 2)
      text("The text input fills all remaining horizontal space", font_scale: 0)

      hstack(spacing: 10.0, padding: 10.0, background_color: color(60, 60, 70)) do
        text("Label:", font_scale: 1)

        expanded do
          # This fills the remaining width
          hstack(background_color: color(80, 120, 80), padding: 5.0) do
            text("[ Expanded Area ]", font_scale: 1, color: color(200, 255, 200))
          end
        end

        button("Submit", padding: 10.0) { }
      end

      text("Fixed | <---- Expanded ----> | Fixed", font_scale: 0, color: color(150, 150, 150))
    end
  end

  # Demo 2: HStack with multiple expanded children
  private def demo_hstack_multiple_expanded
    vstack(spacing: 10.0, padding: 20.0) do
      text("HStack with Multiple Expanded", font_scale: 2)
      text("Two expanded children share the remaining space equally", font_scale: 0)

      hstack(spacing: 10.0, padding: 10.0, background_color: color(60, 60, 70)) do
        text("Start", font_scale: 1)

        expanded do
          hstack(background_color: color(120, 80, 80), padding: 10.0) do
            text("Expanded 1 (50%)", font_scale: 1, color: color(255, 200, 200))
          end
        end

        expanded do
          hstack(background_color: color(80, 80, 120), padding: 10.0) do
            text("Expanded 2 (50%)", font_scale: 1, color: color(200, 200, 255))
          end
        end

        text("End", font_scale: 1)
      end

      text("Fixed | <-- Exp 1 --> | <-- Exp 2 --> | Fixed", font_scale: 0, color: color(150, 150, 150))
    end
  end

  # Demo 3: VStack with single expanded child
  private def demo_vstack_single_expanded
    vstack(spacing: 10.0, padding: 20.0) do
      text("VStack with Single Expanded", font_scale: 2)
      text("The content area fills all remaining vertical space", font_scale: 0)

      # This inner vstack needs to be expanded to fill the outer vstack
      expanded do
        vstack(spacing: 0.0, padding: 0.0, background_color: color(60, 60, 70)) do
          hstack(padding: 10.0, background_color: color(70, 70, 80)) do
            text("Header (fixed height)", font_scale: 1)
          end

          expanded do
            vstack(background_color: color(50, 80, 50), padding: 20.0) do
              text("Content Area", font_scale: 2, color: color(200, 255, 200))
              text("This area expands to fill", font_scale: 1, color: color(180, 220, 180))
              text("all remaining vertical space", font_scale: 1, color: color(180, 220, 180))
            end
          end

          hstack(padding: 10.0, background_color: color(70, 70, 80)) do
            text("Footer (fixed height)", font_scale: 1)
          end
        end
      end
    end
  end

  # Demo 4: Classic header/content/footer layout
  private def demo_vstack_header_content_footer
    vstack(spacing: 0.0, padding: 10.0) do
      # App header
      hstack(padding: 15.0, background_color: color(70, 100, 140)) do
        text("My Application", font_scale: 3, color: color(255, 255, 255))
        expanded { text("") }  # Spacer
        button("Settings", padding: 8.0) { }
        button("Help", padding: 8.0) { }
      end

      # Main content - expands (fill_area: true to fill both axes)
      expanded(fill_area: true) do
        vstack(padding: 20.0, background_color: color(45, 45, 55)) do
          text("Welcome!", font_scale: 4)
          text("This is the main content area.", font_scale: 1)
          text("It automatically fills all available vertical space.", font_scale: 1)
          text("The header and footer remain fixed size.", font_scale: 1)

          vstack(spacing: 5.0, padding: 15.0, background_color: color(55, 55, 65)) do
            text("Features:", font_scale: 2)
            text("- Header stays at top", font_scale: 0)
            text("- Footer stays at bottom", font_scale: 0)
            text("- Content fills the middle", font_scale: 0)
            text("- Resize window to see it adapt!", font_scale: 0)
          end
        end
      end

      # Footer
      hstack(padding: 10.0, background_color: color(50, 50, 60)) do
        text("Status: Ready", font_scale: 0, color: color(150, 200, 150))
        expanded { text("") }
        text("v1.0.0", font_scale: 0, color: color(120, 120, 120))
      end
    end
  end

  # Demo 5: Sidebar + content layout
  private def demo_nested_sidebar_content
    vstack(spacing: 0.0, padding: 10.0) do
      text("Nested Layout: Sidebar + Content", font_scale: 2)

      expanded(fill_area: true) do
        hstack(spacing: 0.0, padding: 0.0) do
          # Fixed-width sidebar
          vstack(spacing: 5.0, padding: 10.0, background_color: color(55, 55, 70)) do
            text("Sidebar", font_scale: 2)
            button("Dashboard", padding: 8.0) { }
            button("Projects", padding: 8.0) { }
            button("Settings", padding: 8.0) { }
            button("Profile", padding: 8.0) { }
          end

          # Expanded content area
          expanded do
            vstack(padding: 20.0, background_color: color(45, 50, 55)) do
              text("Main Content", font_scale: 3)
              text("The sidebar has a fixed width.", font_scale: 1)
              text("This content area expands horizontally.", font_scale: 1)

              expanded do
                vstack(padding: 15.0, background_color: color(50, 60, 65)) do
                  text("Nested expanded!", font_scale: 2)
                  text("This box also expands vertically", font_scale: 0)
                  text("to fill remaining space.", font_scale: 0)
                end
              end
            end
          end
        end
      end
    end
  end

  # Demo 6: Equal columns
  private def demo_equal_columns
    vstack(spacing: 10.0, padding: 20.0) do
      text("Equal Width Columns", font_scale: 2)
      text("Three expanded children = three equal columns", font_scale: 0)

      expanded(fill_area: true) do
        hstack(spacing: 10.0, padding: 0.0) do
          expanded do
            vstack(padding: 15.0, background_color: color(100, 60, 60)) do
              text("Column 1", font_scale: 2, color: color(255, 200, 200))
              text("33% width", font_scale: 1)
              text("Lorem ipsum", font_scale: 0)
              text("dolor sit amet", font_scale: 0)
            end
          end

          expanded do
            vstack(padding: 15.0, background_color: color(60, 100, 60)) do
              text("Column 2", font_scale: 2, color: color(200, 255, 200))
              text("33% width", font_scale: 1)
              text("consectetur", font_scale: 0)
              text("adipiscing elit", font_scale: 0)
            end
          end

          expanded do
            vstack(padding: 15.0, background_color: color(60, 60, 100)) do
              text("Column 3", font_scale: 2, color: color(200, 200, 255))
              text("33% width", font_scale: 1)
              text("sed do eiusmod", font_scale: 0)
              text("tempor", font_scale: 0)
            end
          end
        end
      end
    end
  end

  # Demo 7: Flex factors for proportional distribution
  private def demo_flex_factors
    vstack(spacing: 10.0, padding: 20.0) do
      text("Flex Factors (1:2:1 Ratio)", font_scale: 2)
      text("expanded(flex: N) controls proportional space distribution", font_scale: 0)

      expanded(fill_area: true) do
        hstack(spacing: 10.0, padding: 0.0) do
          # flex:1 = 25% of space
          expanded(flex: 1) do
            vstack(padding: 15.0, background_color: color(100, 60, 60)) do
              text("flex: 1", font_scale: 2, color: color(255, 200, 200))
              text("25%", font_scale: 1)
              text("1/(1+2+1)", font_scale: 0)
            end
          end

          # flex:2 = 50% of space
          expanded(flex: 2) do
            vstack(padding: 15.0, background_color: color(60, 100, 60)) do
              text("flex: 2", font_scale: 2, color: color(200, 255, 200))
              text("50%", font_scale: 1)
              text("2/(1+2+1)", font_scale: 0)
            end
          end

          # flex:1 = 25% of space
          expanded(flex: 1) do
            vstack(padding: 15.0, background_color: color(60, 60, 100)) do
              text("flex: 1", font_scale: 2, color: color(200, 200, 255))
              text("25%", font_scale: 1)
              text("1/(1+2+1)", font_scale: 0)
            end
          end
        end
      end

      text("Total flex = 4. Each gets (flex/4) of remaining space.", font_scale: 0, color: color(150, 150, 150))
    end
  end

  # Demo 8: Spacer widget
  private def demo_spacer
    vstack(spacing: 10.0, padding: 20.0) do
      text("Spacer Widget", font_scale: 2)
      text("spacer is an empty expanded that takes up remaining space", font_scale: 0)

      # Example 1: Push content to edges
      hstack(spacing: 0.0, padding: 10.0, background_color: color(60, 60, 70)) do
        text("Left", font_scale: 1, color: color(255, 200, 200))
        spacer  # Takes all remaining space
        text("Right", font_scale: 1, color: color(200, 200, 255))
      end

      text("spacer pushes content to edges", font_scale: 0, color: color(150, 150, 150))

      # Example 2: Center content
      hstack(spacing: 0.0, padding: 10.0, background_color: color(60, 60, 70)) do
        spacer
        text("Centered", font_scale: 1, color: color(200, 255, 200))
        spacer
      end

      text("Two spacers = centered content", font_scale: 0, color: color(150, 150, 150))

      # Example 3: Spacer with flex
      hstack(spacing: 0.0, padding: 10.0, background_color: color(60, 60, 70)) do
        text("A", font_scale: 1)
        spacer(flex: 1)  # 1/3 of space
        text("B", font_scale: 1)
        spacer(flex: 2)  # 2/3 of space
        text("C", font_scale: 1)
      end

      text("spacer(flex: N) for proportional spacing", font_scale: 0, color: color(150, 150, 150))
    end
  end

  # Demo 9: Flexible vs Expanded
  private def demo_flexible_vs_expanded
    vstack(spacing: 10.0, padding: 20.0) do
      text("Flexible vs Expanded", font_scale: 2)
      text("flexible allocates space but child uses natural size", font_scale: 0)

      # Expanded: child fills allocated space
      hstack(spacing: 0.0, padding: 10.0, background_color: color(60, 60, 70)) do
        text("Fixed", font_scale: 1)
        expanded do
          hstack(background_color: color(100, 60, 60), padding: 10.0) do
            text("expanded: fills space", font_scale: 1, color: color(255, 200, 200))
          end
        end
      end

      text("expanded { child } - child is FORCED to fill", font_scale: 0, color: color(150, 150, 150))

      # Flexible: child stays natural size
      hstack(spacing: 0.0, padding: 10.0, background_color: color(60, 60, 70)) do
        text("Fixed", font_scale: 1)
        flexible do
          hstack(background_color: color(60, 100, 60), padding: 10.0) do
            text("flexible: natural", font_scale: 1, color: color(200, 255, 200))
          end
        end
      end

      text("flexible { child } - child uses NATURAL size", font_scale: 0, color: color(150, 150, 150))

      # Side by side comparison
      hstack(spacing: 10.0, padding: 10.0, background_color: color(50, 50, 60)) do
        expanded do
          vstack(padding: 10.0, background_color: color(70, 50, 50)) do
            text("Expanded", font_scale: 1, color: color(255, 200, 200))
            text("Child fills", font_scale: 0)
          end
        end

        flexible do
          vstack(padding: 10.0, background_color: color(50, 70, 50)) do
            text("Flexible", font_scale: 1, color: color(200, 255, 200))
            text("Natural size", font_scale: 0)
          end
        end
      end

      text("Same flex factor, different fit behavior", font_scale: 0, color: color(150, 150, 150))
    end
  end

  # Helper to create colors
  private def color(r : Int32, g : Int32, b : Int32, a : Int32 = 255) : CrymbleUI::Color
    CrymbleUI::Color.new(r.to_u8, g.to_u8, b.to_u8, a.to_u8)
  end
end

# Run the demo
puts "Expanded Widget Demo"
puts "===================="
puts "Use Prev/Next buttons to switch between demos"
puts "Resize the window to see flexible layouts adapt!"
puts ""

CrymbleUI.run(ExpandedDemo.new)
