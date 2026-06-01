require "../spec_helper"
require "../../src/testing/test_renderer"

# Test for ScrollView-in-Panel resize bug
#
# BUG: During panel resize (expansion), ScrollView content items render
# at wrong coordinates - floating outside the panel bounds.
#
# Screenshot /tmp/2026-01-08_19-02.png shows Items 1-10 rendered way to the
# right and below the panel during resize.
#
# This test verifies that content remains WITHIN panel bounds during resize.

# DSL-style app that creates NEW widget instances on every build()
# This reproduces the reconciliation behavior that causes the bug
class ResizeTestDSLApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Test", 800, 600) do
      window_panel(title: "Preview", x: 100.0, y: 100.0,
                   width: 300.0, height: 250.0,
                   resizable: true, id: "panel") do
        vstack(spacing: 5.0, padding: 10.0) do
          text("Items:")
          expanded do
            scroll_view(direction: CrymbleUI::ScrollDirection::Vertical, id: "scroll") do
              vstack(spacing: 5.0) do
                10.times do |i|
                  text("Item #{i + 1}", id: "item_#{i}")
                end
              end
            end
          end
        end
      end
    end
  end
end

describe "WindowPanel resize content bounds" do
  it "DSL app: ScrollView content stays within panel bounds during resize expansion" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ResizeTestDSLApp.new
    app.build_tree

    # Initial render
    renderer.render_frame(app)

    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    scroll = app.find("scroll").as(CrymbleUI::ScrollView)
    item0 = app.find("item_0").as(CrymbleUI::Text)

    # Capture initial state
    initial_panel_bounds = panel.absolute_bounds.dup
    initial_scroll_bounds = scroll.absolute_bounds.dup
    initial_item0_bounds = item0.absolute_bounds.dup

    # Verify initial state is correct
    scroll.absolute_bounds.x.should be >= panel.absolute_bounds.x
    scroll.absolute_bounds.y.should be >= panel.absolute_bounds.y

    # Start resize from bottom-right corner
    resize_x = panel.x + panel.width - 5.0
    resize_y = panel.y + panel.height - 5.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(resize_x, resize_y))
    renderer.render_frame(app)

    # Verify panel is in resize mode
    panel.resizing?.should be_true

    # Drag to EXPAND panel by 100px in both directions
    # This triggers layout_children which may cause rebuild
    new_resize_x = resize_x + 100.0
    new_resize_y = resize_y + 100.0
    app.handle_mouse_move(CrymbleUI::Vec2.new(new_resize_x, new_resize_y))
    renderer.render_frame(app)

    # Re-find widgets after potential rebuild
    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    scroll = app.find("scroll").as(CrymbleUI::ScrollView)
    item0 = app.find("item_0").as(CrymbleUI::Text)

    # KEY ASSERTIONS: Content must be within panel bounds DURING resize

    # Panel bounds should have expanded
    panel.width.should be > initial_panel_bounds.width,
      "Panel should have expanded width"
    panel.height.should be > initial_panel_bounds.height,
      "Panel should have expanded height"

    # ScrollView must be within panel bounds
    scroll_abs = scroll.absolute_bounds
    panel_abs = panel.absolute_bounds

    scroll_abs.x.should be >= panel_abs.x,
      "ScrollView left edge (#{scroll_abs.x}) should be >= panel left (#{panel_abs.x})"

    scroll_abs.y.should be >= panel_abs.y,
      "ScrollView top edge (#{scroll_abs.y}) should be >= panel top (#{panel_abs.y})"

    scroll_right = scroll_abs.x + scroll_abs.width
    panel_right = panel_abs.x + panel_abs.width
    scroll_right.should be <= panel_right,
      "ScrollView right edge (#{scroll_right}) should be <= panel right (#{panel_right})"

    scroll_bottom = scroll_abs.y + scroll_abs.height
    panel_bottom = panel_abs.y + panel_abs.height
    scroll_bottom.should be <= panel_bottom,
      "ScrollView bottom edge (#{scroll_bottom}) should be <= panel bottom (#{panel_bottom})"

    # Check first item is within reasonable bounds
    item0_abs = item0.absolute_bounds

    # The bug shows items floating way outside panel
    # Item should be approximately within panel content area (not 200px offset!)
    item0_abs.x.should be >= panel_abs.x,
      "Item 0 x (#{item0_abs.x}) way outside panel left (#{panel_abs.x})"

    item0_abs.y.should be >= panel_abs.y,
      "Item 0 y (#{item0_abs.y}) way outside panel top (#{panel_abs.y})"

    item0_right = item0_abs.x + item0_abs.width
    item0_right.should be <= panel_right + 20.0,
      "Item 0 right edge (#{item0_right}) way outside panel right (#{panel_right})"

    # Release resize
    app.handle_mouse_up(CrymbleUI::Vec2.new(new_resize_x, new_resize_y))
  end

  it "non-DSL: ScrollView content stays within panel bounds during resize expansion" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    # Panel with ScrollView containing items (matches showcase_demo pattern)
    panel = CrymbleUI::WindowPanel.new("Preview", 100.0, 100.0, 300.0, 250.0)

    vstack = CrymbleUI::VStack.new(spacing: 5.0, padding: 10.0)

    # Label above ScrollView
    label = CrymbleUI::Text.new("Items:")
    vstack.add_child(label)

    # ScrollView with content
    scroll = CrymbleUI::ScrollView.new(id: "scroll", direction: CrymbleUI::ScrollDirection::Vertical)
    scroll_content = CrymbleUI::VStack.new(spacing: 5.0)
    10.times do |i|
      item = CrymbleUI::Text.new("Item #{i + 1}")
      scroll_content.add_child(item)
    end
    scroll.set_content(scroll_content)
    vstack.add_child(scroll)

    panel.add_child(vstack)
    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Capture initial state
    initial_panel_bounds = panel.absolute_bounds.dup
    initial_scroll_bounds = scroll.absolute_bounds.dup

    # Verify initial state is correct
    scroll.absolute_bounds.x.should be >= panel.absolute_bounds.x
    scroll.absolute_bounds.y.should be >= panel.absolute_bounds.y

    # Start resize from bottom-right corner
    resize_x = panel.x + panel.width - 5.0
    resize_y = panel.y + panel.height - 5.0
    renderer.mouse_down(resize_x, resize_y)
    renderer.render_frame(app)

    # Verify panel is in resize mode
    panel.resizing?.should be_true

    # Drag to EXPAND panel by 100px in both directions
    new_resize_x = resize_x + 100.0
    new_resize_y = resize_y + 100.0
    renderer.mouse_move(new_resize_x, new_resize_y)
    renderer.render_frame(app)

    # KEY ASSERTIONS: Content must be within panel bounds DURING resize

    # Panel bounds should have expanded
    panel.width.should be > initial_panel_bounds.width
    panel.height.should be > initial_panel_bounds.height

    # ScrollView must be within panel bounds
    scroll_abs = scroll.absolute_bounds
    panel_abs = panel.absolute_bounds

    scroll_abs.x.should be >= panel_abs.x,
      "ScrollView left edge (#{scroll_abs.x}) should be >= panel left (#{panel_abs.x})"

    scroll_abs.y.should be >= panel_abs.y,
      "ScrollView top edge (#{scroll_abs.y}) should be >= panel top (#{panel_abs.y})"

    scroll_right = scroll_abs.x + scroll_abs.width
    panel_right = panel_abs.x + panel_abs.width
    scroll_right.should be <= panel_right,
      "ScrollView right edge (#{scroll_right}) should be <= panel right (#{panel_right})"

    scroll_bottom = scroll_abs.y + scroll_abs.height
    panel_bottom = panel_abs.y + panel_abs.height
    scroll_bottom.should be <= panel_bottom,
      "ScrollView bottom edge (#{scroll_bottom}) should be <= panel bottom (#{panel_bottom})"

    # Check each content item is within ScrollView bounds
    scroll_content.children.each_with_index do |item, idx|
      item_abs = item.absolute_bounds

      # Item must be within reasonable bounds (not floating way outside)
      # The bug shows items at ~(300, 200) when panel is at (100, 100)
      item_abs.x.should be >= panel_abs.x - 50.0,
        "Item #{idx} x (#{item_abs.x}) way outside panel left (#{panel_abs.x})"

      item_abs.y.should be >= panel_abs.y - 50.0,
        "Item #{idx} y (#{item_abs.y}) way outside panel top (#{panel_abs.y})"

      item_right = item_abs.x + item_abs.width
      item_right.should be <= panel_right + 50.0,
        "Item #{idx} right edge (#{item_right}) way outside panel right (#{panel_right})"
    end

    # Release resize
    renderer.mouse_up(new_resize_x, new_resize_y)
  end

  it "DSL app: content renders within panel during resize (pixel test)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ResizeTestDSLApp.new
    app.build_tree

    # Initial render
    renderer.render_frame(app)

    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    scroll = app.find("scroll").as(CrymbleUI::ScrollView)

    # Capture INITIAL layer bounds for comparison
    initial_panel_layer_bounds = panel.layer.not_nil!.bounds.dup
    initial_scroll_layer_bounds = scroll.content_layer.try(&.bounds.dup)

    # Start resize
    resize_x = panel.x + panel.width - 5.0
    resize_y = panel.y + panel.height - 5.0
    app.handle_mouse_down(CrymbleUI::Vec2.new(resize_x, resize_y))
    renderer.render_frame(app)

    # Expand panel - this triggers layout_children which may mark root dirty
    new_resize_x = resize_x + 100.0
    new_resize_y = resize_y + 100.0
    app.handle_mouse_move(CrymbleUI::Vec2.new(new_resize_x, new_resize_y))

    # EXPLICITLY trigger rebuild if root needs it (matching SFML behavior)
    # This is what SFML does in handle_mouse_move (app.cr:519)
    if root = app.root
      if root.needs_layout? || root.needs_render?
        app.rebuild
      end
    end

    renderer.render_frame(app)

    # Re-find widgets after potential rebuild
    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    scroll = app.find("scroll").as(CrymbleUI::ScrollView)

    # ScrollView has its own layer - check ScrollView content_layer backend
    content_layer = scroll.content_layer.not_nil!
    scroll_backend = content_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)

    # Content should render in ScrollView's layer
    # Sample pixels in ScrollView layer (layer-local coordinates start at 0,0)
    found_content = false
    content_pixels = [] of String

    # Check multiple positions in the ScrollView content area
    10.times do |dx|
      10.times do |dy|
        x = 10 + dx * 30  # Start 10px from left
        y = 10 + dy * 20  # Start 10px from top (content area)
        next if x >= scroll_backend.width || y >= scroll_backend.height

        pixel = scroll_backend.get_pixel(x, y)
        next unless pixel

        # Content includes text (black ~0,0,0), etc.
        # Not background (white or light gray) and NOT transparent
        is_background = pixel.r > 200 && pixel.g > 200 && pixel.b > 200
        is_transparent = pixel.a == 0
        unless is_background || is_transparent
          found_content = true
          content_pixels << "(#{x},#{y}): RGBA(#{pixel.r},#{pixel.g},#{pixel.b},#{pixel.a})"
        end
      end
    end

    found_content.should be_true,
      "No content pixels found in ScrollView layer - content may be rendering at wrong offset."

    app.handle_mouse_up(CrymbleUI::Vec2.new(new_resize_x, new_resize_y))
  end

  it "ScrollView layer bounds match widget bounds during resize" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 800, 600)

    panel = CrymbleUI::WindowPanel.new("Preview", 100.0, 100.0, 300.0, 250.0)

    scroll = CrymbleUI::ScrollView.new(id: "scroll", direction: CrymbleUI::ScrollDirection::Vertical)
    scroll_content = CrymbleUI::VStack.new(spacing: 5.0)
    10.times { |i| scroll_content.add_child(CrymbleUI::Text.new("Item #{i + 1}")) }
    scroll.set_content(scroll_content)
    panel.add_child(scroll)

    window.add_child(panel)
    app.root_widget = window

    # Initial render
    renderer.render_frame(app)

    # Start resize
    resize_x = panel.x + panel.width - 5.0
    resize_y = panel.y + panel.height - 5.0
    renderer.mouse_down(resize_x, resize_y)
    renderer.render_frame(app)

    # Expand panel
    renderer.mouse_move(resize_x + 100.0, resize_y + 100.0)
    renderer.render_frame(app)

    # Layer bounds should match widget absolute_bounds
    if content_layer = scroll.content_layer
      layer_bounds = content_layer.bounds
      widget_abs = scroll.absolute_bounds

      # Layer bounds should be approximately equal to widget absolute bounds
      # (small tolerance for rounding)
      layer_bounds.x.should be_close(widget_abs.x, 5.0),
        "Layer x (#{layer_bounds.x}) doesn't match widget absolute x (#{widget_abs.x})"

      layer_bounds.y.should be_close(widget_abs.y, 5.0),
        "Layer y (#{layer_bounds.y}) doesn't match widget absolute y (#{widget_abs.y})"
    end

    renderer.mouse_up(resize_x + 100.0, resize_y + 100.0)
  end
end
