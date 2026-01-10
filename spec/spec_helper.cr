require "spec"
require "../src/core/types"
require "../src/core/widget"
require "../src/core/app"
require "../src/core/scheduler"
require "../src/core/font_sizing"
require "../src/widgets/text"
require "../src/widgets/button"
require "../src/widgets/scroll_view"
require "../src/layout/vstack"
require "../src/layout/hstack"
require "../src/testing/widget_tester"
require "../src/testing/test_font"
require "../src/testing/gui_test_helpers"
require "../src/input/focus_manager"

# Include GUI test helpers for all specs
include CrymbleUI::Testing::GUITestHelpers

# Setup headless font for text measurement (no SFML required)
CrymbleUI::Widget.font = CrymbleUI::Testing::TestFont.new

# Setup scheduler for timer-based tests (cursor blink, animations)
CrymbleUI::Widget.scheduler = CrymbleUI::Scheduler.new

# Setup focus manager for keyboard focus tests
CrymbleUI::Widget.focus_manager = CrymbleUI::FocusManager.new

# Reset state before each test to ensure isolation
Spec.before_each do
  CrymbleUI::FontSizing.reset_zoom
  CrymbleUI::Widget.focus_manager.clear_focus  # Clear any leftover focus from previous tests
end

# Concrete widget implementation for testing.
# NOTE: Use only as LEAF widget (for controlled sizing). For testing container
# nesting behavior, use real widgets (HStack, VStack, etc.) instead.
class TestWidget < CrymbleUI::Widget
    property measured_size : CrymbleUI::Size?
    property click_count : Int32 = 0

    def initialize(id : String? = nil, label : String? = nil, @measured_size : CrymbleUI::Size? = nil)
        super(id: id)
        @label = label
    end

    def label : String?
        @label
    end

    def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
        @measured_size || CrymbleUI::Size.new(100.0, 50.0)
    end

    def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
        # Respect tight constraints (like real widgets do)
        natural_size = measure(constraints)
        width = constraints.min_width == constraints.max_width ? constraints.max_width : natural_size.width
        height = constraints.min_height == constraints.max_height ? constraints.max_height : natural_size.height
        @bounds = CrymbleUI::Rect.new(position.x, position.y, width, height)

        # Layout children vertically
        y_offset = 0.0
        @children.each do |child|
            child_constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(@bounds.width, Float64::INFINITY))
            child_size = child.measure(child_constraints)
            child.layout(child_constraints, CrymbleUI::Vec2.new(position.x, position.y + y_offset))
            y_offset += child_size.height
        end
    end

    def on_click
        @click_count += 1
    end
end

# Concrete App implementation for testing
class TestApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    # If root was set directly via root_widget=, return it for reconciliation
    # Otherwise return default test widget
    @root || CrymbleUI::Text.new("Test App")
  end

  # Allow tests to set root widget directly
  def root_widget=(widget : CrymbleUI::Widget)
    @root = widget
  end
end
