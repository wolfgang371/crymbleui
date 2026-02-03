# CrymbleUI Showcase Demo
# =======================
# A comprehensive demonstration of all CrymbleUI features in one app.
#
# Features demonstrated:
# - Layouts: VStack, HStack, Expanded, ScrollView, RecursiveGrid
# - Widgets: Button, Checkbox, TextInput, ComboBox, Text
# - Panels: WindowPanel (drag, resize, close, maximize)
# - Chrome: MenuBar, StatusBar
# - Interactions: State, focus, shortcuts, drag & drop
# - Custom widgets: DSL-based and primitive-based
#
# Run with: shards build showcase_demo && ./bin/showcase_demo

require "../src/crymble-ui"

# =============================================================================
# Custom Widgets
# =============================================================================

# DSL-based custom widget: A labeled value display
class LabeledValue < CrymbleUI::HStack
  def initialize(@label : String, @value : String)
    super(spacing: 10.0)
  end

  def build
    text(@label, font_scale: -1, color: CrymbleUI::Color.new(150, 150, 150, 255))
    text(@value, font_scale: 0)
  end
end

# Primitive-based custom widget: Status indicator circle
class StatusIndicator < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  property active : Bool
  property size : Float64

  def initialize(@active = false, @size = 12.0)
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@size, @size)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    color = @active ? CrymbleUI::Color.new(100, 255, 100, 255) : CrymbleUI::Color.new(255, 100, 100, 255)
    primitives do
      draw_circle(CrymbleUI::Vec2.new(bounds.width / 2, bounds.height / 2), @size / 2, color, fill: true)
    end
  end
end

# =============================================================================
# Main Showcase App
# =============================================================================

class ShowcaseDemo < CrymbleUI::App
  # State for various widgets
  state status_text : String = "Ready"
  state counter : Int32 = 0
  state check_enabled : Bool = true
  state check_tristate : CrymbleUI::CheckState = CrymbleUI::CheckState::Indeterminate
  state input_value : String = ""
  state combo_index : Int32 = 0
  state show_popup : Bool = false
  state last_drop : String = "(none)"
  state items_count : Int32 = 10

  THEMES = ["Light", "Dark", "Blue", "Green"]

  def build : CrymbleUI::Widget
    window("CrymbleUI Showcase", 950, 780) do
      # MenuBar
      menubar do
        menu("File") do
          menu_item("New", shortcut: "^N") { self.status_text = "New file created" }
          menu_item("Open", shortcut: "^O") { self.status_text = "Open dialog" }
          menu_item("Save", shortcut: "^S") { self.status_text = "File saved" }
          separator
          menu_item("Quit", shortcut: "^Q") { quit }
        end

        menu("Edit") do
          menu_item("Undo", shortcut: "^Z") { self.status_text = "Undo" }
          menu_item("Redo", shortcut: "^Y") { self.status_text = "Redo" }
          separator
          menu_item("Cut", shortcut: "^X") { self.status_text = "Cut" }
          menu_item("Copy", shortcut: "^C") { self.status_text = "Copy" }
          menu_item("Paste", shortcut: "^V") { self.status_text = "Paste" }
        end

        menu("View") do
          menu_item("Zoom In") { self.status_text = "Use Ctrl++ to zoom" }
          menu_item("Zoom Out") { self.status_text = "Use Ctrl+- to zoom" }
          menu_item("Reset Zoom") { self.status_text = "Use Ctrl+0 to reset" }
        end

        menu("Help") do
          menu_item("About") { self.status_text = "CrymbleUI Showcase Demo" }
          menu_item("Shortcuts") { self.status_text = "Ctrl+M maximizes panel" }
        end
      end

      # === Panel: Controls ===
      window_panel(title: "Controls", x: 10.0, y: 10.0, width: 290.0, height: 280.0,
                   resizable: true, closeable: true) do
        vstack(spacing: 12.0, padding: 10.0) do
          text("Input Widgets", font_scale: 1, color: CrymbleUI::Color.new(100, 180, 255, 255))

          # TextInput
          hstack(spacing: 10.0) do
            text("Name:", font_scale: -1)
            expanded do
              text_input(value: input_value, placeholder: "Enter text...") do |val|
                self.input_value = val
              end
            end
          end

          # ComboBox
          hstack(spacing: 10.0) do
            text("Theme:", font_scale: -1)
            combo_box(items: THEMES, selected: combo_index) do |idx, val|
              self.combo_index = idx
              self.status_text = "Theme: #{val}"
            end
          end

          # Checkboxes
          checkbox("Enable feature", checked: check_enabled) do
            self.check_enabled = !check_enabled
            self.status_text = "Feature: #{!check_enabled ? "ON" : "OFF"}"
          end

          checkbox("Tristate option", state: check_tristate) do
            self.check_tristate = case check_tristate
            when CrymbleUI::CheckState::Unchecked     then CrymbleUI::CheckState::Checked
            when CrymbleUI::CheckState::Checked       then CrymbleUI::CheckState::Indeterminate
            when CrymbleUI::CheckState::Indeterminate then CrymbleUI::CheckState::Unchecked
            else CrymbleUI::CheckState::Unchecked
            end
            self.status_text = "Tristate: #{check_tristate}"
          end

          # Counter with buttons
          hstack(spacing: 10.0) do
            button("-") { self.counter -= 1; self.status_text = "Counter: #{counter}" }
            text("#{counter}", font_scale: 1)
            button("+") { self.counter += 1; self.status_text = "Counter: #{counter}" }
            spacer
            button("Reset", shortcut: "^R") { self.counter = 0; self.status_text = "Counter reset" }
          end
        end
      end

      # === Panel: Preview (ScrollView) ===
      window_panel(title: "Preview (ScrollView)", x: 310.0, y: 10.0, width: 290.0, height: 280.0,
                   resizable: true) do
        vstack(spacing: 10.0, padding: 10.0) do
          hstack(spacing: 10.0) do
            text("Items:", font_scale: -1)
            button("Add 5") { self.items_count += 5 }
            button("Remove 5") { self.items_count = {0, items_count - 5}.max }
          end

          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical) do
              vstack(spacing: 5.0) do
                items_count.times do |i|
                  hstack(spacing: 8.0) do
                    widget StatusIndicator.new(active: i.even?, size: 10.0)
                    text("Item #{i + 1}", font_scale: -1)
                  end
                end
              end
            end
          end
        end
      end

      # === Panel: Drag & Drop ===
      window_panel(title: "Drag & Drop", x: 10.0, y: 300.0, width: 290.0, height: 220.0,
                   resizable: true) do
        vstack(spacing: 10.0, padding: 10.0) do
          text("Drag items to zones:", font_scale: -1)

          hstack(spacing: 10.0) do
            draggable(data: CrymbleUI::TextDragData.new("Text A")) do
              hstack(padding: 6.0, background_color: CrymbleUI::Color.new(100, 150, 200, 255)) do
                text("Text", color: CrymbleUI::Color.new(255, 255, 255, 255), font_scale: -1)
              end
            end

            draggable(data: CrymbleUI::WidgetDragData.new(CrymbleUI::Button.new("W"))) do
              hstack(padding: 6.0, background_color: CrymbleUI::Color.new(200, 150, 100, 255)) do
                text("Widget", color: CrymbleUI::Color.new(50, 50, 50, 255), font_scale: -1)
              end
            end
          end

          hstack(spacing: 10.0) do
            drop_zone(accept_types: ["text"], on_drop: ->(data : CrymbleUI::DragData, pos : CrymbleUI::Vec2) {
              self.last_drop = "Text: #{data.display_text}"
              self.status_text = last_drop
            }) do
              vstack(padding: 8.0) do
                text("Text Zone", font_scale: -1)
              end
            end

            drop_zone(accept_types: ["widget"], on_drop: ->(data : CrymbleUI::DragData, pos : CrymbleUI::Vec2) {
              self.last_drop = "Widget dropped"
              self.status_text = last_drop
            }) do
              vstack(padding: 8.0) do
                text("Widget Zone", font_scale: -1)
              end
            end
          end

          text("Last: #{last_drop}", font_scale: -2)
        end
      end

      # === Panel: Grid ===
      window_panel(title: "RecursiveGrid", x: 310.0, y: 300.0, width: 290.0, height: 220.0,
                   resizable: true) do
        vstack(spacing: 10.0, padding: 10.0) do
          text("Auto-spanning grid:", font_scale: -1)

          recursive_grid(spacing: 4.0) do
            [
              [button("A") { self.status_text = "A" },
               recursive_grid(spacing: 2.0) {
                 [[button("B1", font_scale: -1) { self.status_text = "B1" }],
                  [button("B2", font_scale: -1) { self.status_text = "B2" }]]
               }],
              [button("C") { self.status_text = "C" },
               button("D") { self.status_text = "D" }]
            ]
          end
        end
      end

      # === Bottom section: Popup & Custom Widgets ===
      window_panel(title: "Extras", x: 610.0, y: 10.0, width: 330.0, height: 280.0) do
        vstack(spacing: 15.0, padding: 10.0) do
          text("Popup & Custom Widgets", font_scale: 1, color: CrymbleUI::Color.new(100, 180, 255, 255))

          button(show_popup ? "Hide Popup" : "Show Popup") do
            self.show_popup = !show_popup
          end

          text("DSL-based widget:", font_scale: -1)
          widget LabeledValue.new("Status:", check_enabled ? "Active" : "Inactive")

          text("Primitive widgets:", font_scale: -1)
          hstack(spacing: 8.0) do
            widget StatusIndicator.new(active: true, size: 16.0)
            text("Online", font_scale: -1)
            spacer
            widget StatusIndicator.new(active: false, size: 16.0)
            text("Offline", font_scale: -1)
          end
        end
      end

      # Modal dialog popup
      if show_popup
        popup(x: 350.0, y: 280.0, padding: 20.0,
              background_color: CrymbleUI::Color.new(50, 50, 70, 250),
              border_color: CrymbleUI::Color.new(100, 100, 120, 255)) do
          vstack(spacing: 10.0) do
            text("Modal Dialog", font_scale: 1, color: CrymbleUI::Color.new(255, 255, 255, 255))
            text("This is a popup overlay.", font_scale: -1, color: CrymbleUI::Color.new(180, 180, 180, 255))
            button("Close") { self.show_popup = false }
          end
        end
      end

      # StatusBar
      statusbar(text: "#{status_text} | Theme: #{THEMES[combo_index]} | Counter: #{counter}")
    end
  end
end

CrymbleUI.run(ShowcaseDemo.new)
