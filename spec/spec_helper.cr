require "spec"
require "../src/core/types"
require "../src/core/theme"
require "../src/core/widget"
require "../src/core/app"
require "../src/core/scheduler"
require "../src/core/font_sizing"
require "../src/widgets/text"
require "../src/widgets/button"
require "../src/widgets/scroll_view"
require "../src/widgets/window_panel"
require "../src/widgets/popup"
require "../src/layout/vstack"
require "../src/layout/hstack"
require "../src/testing/widget_tester"
require "../src/testing/test_font"
require "../src/testing/test_clipboard"
require "../src/testing/gui_test_helpers"
require "../src/input/focus_manager"
require "../src/widgets/virtual_matrix/adapter"
{% if flag?(:cache_validation) %}
  require "../src/rendering/cache_validation"
{% end %}

# Include GUI test helpers for all specs
include CrymbleUI::Testing::GUITestHelpers

# Setup headless font for text measurement (no SFML required)
CrymbleUI::Widget.font = CrymbleUI::Testing::TestFont.new

# Setup in-memory clipboard (no SFML/display required)
CrymbleUI::Widget.clipboard = CrymbleUI::Testing::TestClipboard.new

# Setup scheduler for timer-based tests (cursor blink, animations)
CrymbleUI::Widget.scheduler = CrymbleUI::Scheduler.new

# Setup focus manager for keyboard focus tests
CrymbleUI::Widget.focus_manager = CrymbleUI::FocusManager.new

# Reset state before each test to ensure isolation
Spec.before_each do
  CrymbleUI::FontSizing.reset_zoom
  CrymbleUI::Theme.set(:light)  # Ensure tests run with light theme
  CrymbleUI::Widget.focus_manager.clear_focus  # Clear any leftover focus from previous tests
  CrymbleUI::Layer.clear_registry  # Prevent orphaned layers from leaking between tests
  CrymbleUI::WindowPanel.clear_registry  # Prevent orphaned panels from leaking between tests
  CrymbleUI::Popup.clear_registry  # Prevent orphaned popups from leaking between tests
  {% if flag?(:cache_validation) %}
    # Turn the dual renderer into a gate over the WHOLE suite. With
    # -Dcache_validation, every rendered frame compares the cached matrix buffer against
    # a fresh immediate-mode render; the after_each below fails the example on any divergence
    # (the class of cache-divergence bugs that otherwise slip through). Inert in normal (un-flagged) runs.
    CrymbleUI::CacheValidation.suite_gate = true # cv self-tests opt out in their own before_each
    CrymbleUI::CacheValidation.clear_failures!
    CrymbleUI::CacheValidation.enable(:immediate_mode)
  {% end %}
end

{% if flag?(:cache_validation) %}
  Spec.after_each do
    CrymbleUI::CacheValidation.assert_no_failures! if CrymbleUI::CacheValidation.suite_gate
  end
{% end %}

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

# Reusable test adapter with configurable merged regions.
# Use add_merge to register bounding boxes, then pass to VirtualMatrix.new(adapter, ...).
class MergeableTestAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  @row_count : Int32
  @col_count : Int32

  @merges = [] of Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))

  def initialize(@row_count, @col_count)
  end

  def row_count : Int32
    @row_count
  end

  def col_count : Int32
    @col_count
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::Text.new("#{row},#{col}")
  end

  def add_merge(top_left : Tuple(Int32, Int32), bottom_right : Tuple(Int32, Int32))
    @merges << {top_left, bottom_right}
  end

  def cell_get_bounding_box(row : Int32, col : Int32) : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
    @merges.each do |tl, br|
      if row >= tl[0] && row <= br[0] && col >= tl[1] && col <= br[1]
        return {tl, br}
      end
    end
    { {row, col}, {row, col} }
  end
end

# Minimal visible cell for pixel-level testing.
# Emits fill_rect so TestRenderBackend can see it (unlike Text which only emits DrawText).
# Replaces VirtualMatrixCell in tests that need pixel scanning.
class TestVisibleCell < CrymbleUI::Widget
  include CrymbleUI::PrimitiveBuilder

  def initialize(text : String = "", id : String? = nil)
    super(id: id)
  end

  def measure(constraints : CrymbleUI::BoxConstraints) : CrymbleUI::Size
    w = constraints.max_width.finite? ? constraints.max_width : 100.0
    h = constraints.max_height.finite? ? constraints.max_height : 20.0
    CrymbleUI::Size.new(w, h)
  end

  def perform_layout(constraints : CrymbleUI::BoxConstraints, position : CrymbleUI::Vec2)
    size = measure(constraints)
    @bounds = CrymbleUI::Rect.new(position, size)
  end

  def to_primitives(bounds : CrymbleUI::Rect) : Array(CrymbleUI::DrawPrimitive)
    primitives do
      fill_rect(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height), CrymbleUI::Color.new(45, 50, 55, 255))
    end
  end
end
