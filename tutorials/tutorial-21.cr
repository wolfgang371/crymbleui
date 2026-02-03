# Tutorial 21: Custom Widgets
# ============================
# Creating custom widget classes using DSL composition.
#
# Key concepts:
# - Extend a container (VStack, HStack) and override build() to use DSL
# - DSL methods (text, button, etc.) work inside custom widget's build()
# - For custom drawing, create a leaf widget with to_primitives()
# - For BOTH DSL + custom drawing, use DecoratedContainer with draw_background/draw_foreground
# - Use widget() in the app to add custom widgets
#
# Run with: shards build tutorial-21 && ./bin/tutorial-21

require "../src/crymble-ui"

# =============================================================================
# PATTERN 1: DSL-based custom widget (simple containers)
# =============================================================================
# Extend a container and use DSL in build() to compose children.
# This is the main pattern for creating reusable UI components.

class InfoCard < CrymbleUI::VStack
  def initialize(@title : String, @description : String)
    super(spacing: 5.0, padding: 10.0,
          background_color: CrymbleUI::Color.new(60, 60, 80, 255))
  end

  def build
    text(@title, font_scale: 1, color: CrymbleUI::Color.new(255, 220, 100, 255))
    text(@description, font_scale: -1, color: CrymbleUI::Color.new(180, 180, 180, 255))
  end
end

# =============================================================================
# PATTERN 2: Primitive-based custom widget (pure custom drawing)
# =============================================================================
# For widgets that need custom rendering (shapes, charts, etc.)

class ColoredCircle < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  property radius : Float64
  property color : CrymbleUI::Color

  def initialize(@radius = 20.0, @color = CrymbleUI::Color.new(100, 150, 255, 255))
    super()
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    CrymbleUI::Size.new(@radius * 2, @radius * 2)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    @bounds = CrymbleUI::Rect.new(position, measure(constraints))
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      draw_circle(CrymbleUI::Vec2.new(bounds.width / 2, bounds.height / 2), @radius, @color, fill: true)
    end
  end
end

# =============================================================================
# PATTERN 3: DecoratedContainer (DSL + custom drawing combined!)
# =============================================================================
# Use DecoratedContainer to have BOTH:
# - DSL children via build()
# - Custom primitives via draw_background() and draw_foreground()
#
# Rendering order:
# 1. draw_background() renders UNDER children
# 2. Children render on top
# 3. draw_foreground() renders OVER everything

class FancyCard < CrymbleUI::DecoratedContainer
  def initialize(@title : String)
    super(padding: 15.0, spacing: 8.0)
  end

  # Custom background: gradient-like effect with two colors
  def draw_background(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      # Top half: lighter
      fill_rect(CrymbleUI::Rect.new(0, 0, bounds.width, bounds.height / 2),
                CrymbleUI::Color.new(80, 80, 120, 255))
      # Bottom half: darker
      fill_rect(CrymbleUI::Rect.new(0, bounds.height / 2, bounds.width, bounds.height / 2),
                CrymbleUI::Color.new(50, 50, 90, 255))
    end
  end

  # Custom foreground: gold border on top of everything
  def draw_foreground(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      draw_rect(bounds, CrymbleUI::Color.new(255, 200, 100, 255), 2.0)
    end
  end

  # DSL children: text widgets positioned normally
  def build
    text(@title, font_scale: 1, color: CrymbleUI::Color.new(255, 255, 255, 255))
    text("Custom background + foreground!", font_scale: -1, color: CrymbleUI::Color.new(180, 180, 180, 255))
  end
end

# =============================================================================
# App using all three custom widget patterns
# =============================================================================

class CustomWidgetDemo < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Custom Widget Demo", 550, 450) do
      vstack(spacing: 20.0, padding: 20.0) do
        text("Pattern 1: DSL-based (extends VStack):")
        hstack(spacing: 15.0) do
          widget InfoCard.new("Feature A", "Uses DSL internally")
          widget InfoCard.new("Feature B", "Extends VStack")
        end

        text("Pattern 2: Primitive-based (custom drawing):")
        hstack(spacing: 10.0) do
          widget ColoredCircle.new(radius: 15.0, color: CrymbleUI::Color.new(255, 100, 100, 255))
          widget ColoredCircle.new(radius: 20.0, color: CrymbleUI::Color.new(100, 255, 100, 255))
          widget ColoredCircle.new(radius: 25.0, color: CrymbleUI::Color.new(100, 100, 255, 255))
        end

        text("Pattern 3: DecoratedContainer (DSL + custom drawing!):")
        hstack(spacing: 15.0) do
          widget FancyCard.new("Fancy Card A")
          widget FancyCard.new("Fancy Card B")
        end
      end
    end
  end
end

CrymbleUI.run(CustomWidgetDemo.new)
