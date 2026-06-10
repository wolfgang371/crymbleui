require "../core/widget"
require "../core/app"
require "../core/types"

module CrymbleUI::Testing
  # GUI Test Helpers - for testing USER-VISIBLE behavior, not internal state
  #
  # These helpers verify that widgets are actually rendered and visible,
  # not just that internal data structures are correct.
  #
  # ## Why This Matters
  #
  # BAD (internal state - tests pass but demo broken):
  # ```crystal
  # popup.item_count.should eq 3      # Just checks array size
  # combo.popup_open?.should be_true  # Just checks boolean
  # ```
  #
  # GOOD (GUI behavior - tests verify what user sees):
  # ```crystal
  # assert_rendered(popup)                    # Verify popup has render backend
  # assert_children_rendered(popup, 3)        # Verify 3 items are actually rendered
  # click_on(app, item)                       # Simulate real user click through App
  # ```
  module GUITestHelpers
    # Verify widget is rendered with non-zero size
    # Checks: bounds.width > 0, bounds.height > 0, widget_backend exists
    def assert_rendered(widget : CrymbleUI::Widget, msg : String = "")
      prefix = msg.empty? ? "" : "#{msg}: "
      bounds = widget.absolute_bounds
      bounds.width.should be > 0, "#{prefix}widget has zero width"
      bounds.height.should be > 0, "#{prefix}widget has zero height"
      widget.widget_backend.should_not be_nil, "#{prefix}widget has no render backend (not rendered)"
    end

    # Verify widget is rendered within parent's visible area
    # Uses bounds intersection to check visibility
    def assert_visible_in_parent(widget : CrymbleUI::Widget, parent : CrymbleUI::Widget)
      parent_bounds = parent.absolute_bounds
      widget_bounds = widget.absolute_bounds
      # Widget should overlap with parent's visible area
      overlap = bounds_intersect?(parent_bounds, widget_bounds)
      overlap.should be_true, "widget not visible within parent bounds (widget: #{widget_bounds}, parent: #{parent_bounds})"
    end

    # Verify N children are rendered (have widget_backend, not just in array)
    def assert_children_rendered(parent : CrymbleUI::Widget, expected_count : Int32)
      rendered = parent.children.count { |c| c.widget_backend != nil }
      rendered.should eq expected_count, "expected #{expected_count} rendered children, got #{rendered}"
    end

    # Verify at least N children are rendered
    def assert_min_children_rendered(parent : CrymbleUI::Widget, min_count : Int32)
      rendered = parent.children.count { |c| c.widget_backend != nil }
      rendered.should be >= min_count, "expected at least #{min_count} rendered children, got #{rendered}"
    end

    # Simulate click at widget center through App (full event path)
    def click_on(app : CrymbleUI::App, widget : CrymbleUI::Widget)
      bounds = widget.absolute_bounds
      center = CrymbleUI::Vec2.new(bounds.x + bounds.width/2, bounds.y + bounds.height/2)
      app.handle_mouse_down(center)
      app.handle_mouse_up(center)
    end

    # Simulate click at arbitrary point through App
    def click_at(app : CrymbleUI::App, point : CrymbleUI::Vec2)
      app.handle_mouse_down(point)
      app.handle_mouse_up(point)
    end

    # Simulate click at x, y coordinates through App
    def click_at(app : CrymbleUI::App, x : Float64, y : Float64)
      point = CrymbleUI::Vec2.new(x, y)
      app.handle_mouse_down(point)
      app.handle_mouse_up(point)
    end

    # Simulate typing a string through FocusManager (character by character)
    def type_text(text : String)
      text.each_char do |char|
        CrymbleUI::Widget.focus_manager.handle_text_input(char)
      end
    end

    # Simulate pressing a key through FocusManager.
    # NOTE: for Tab / Shift+Tab use `press_tab` instead — Tab dispatch is owned
    # by FocusManager#handle_tab_key (focused widget first, then focus cycling),
    # which this method bypasses by calling handle_key_down directly.
    def press_key(key : SF::Keyboard::Key, control : Bool = false, shift : Bool = false)
      CrymbleUI::Widget.focus_manager.handle_key_down(key, control, shift)
    end

    # Simulate pressing Tab / Shift+Tab the way the SFML renderer does:
    # through FocusManager#handle_tab_key (the single source of truth), so
    # headless tests exercise the real Tab dispatch (focused widget first,
    # focus cycling as the fallback).
    def press_tab(app : CrymbleUI::App, shift : Bool = false)
      if root = app.root
        CrymbleUI::Widget.focus_manager.handle_tab_key(shift, root)
      end
    end

    # Get widget at a specific point (for debugging)
    def widget_at(app : CrymbleUI::App, point : CrymbleUI::Vec2) : CrymbleUI::Widget?
      return nil unless root = app.root
      root.hit_test(point)
    end

    # Helper: check if two bounds intersect
    private def bounds_intersect?(a : CrymbleUI::Rect, b : CrymbleUI::Rect) : Bool
      !(a.x + a.width <= b.x ||
        b.x + b.width <= a.x ||
        a.y + a.height <= b.y ||
        b.y + b.height <= a.y)
    end
  end
end
