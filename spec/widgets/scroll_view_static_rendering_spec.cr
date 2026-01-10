require "../spec_helper"
require "../../src/testing/test_renderer"

describe "ScrollView Static Rendering" do
  it "renders content within viewport bounds" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    10.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window

    renderer.render_frame(app)

    # Assert: ScrollView has layer
    scroll_view.layer.should_not be_nil

    # Assert: Layer bounds = viewport minus scrollbar width (content area only)
    layer = scroll_view.layer.not_nil!
    # When vertical scrollbar is visible, layer width is reduced by SCROLLBAR_WIDTH
    expected_width = scroll_view.viewport_size.width - CrymbleUI::ScrollView::SCROLLBAR_WIDTH
    layer.bounds.width.should eq expected_width
    layer.bounds.height.should eq scroll_view.viewport_size.height

    # Assert: Content size is larger than viewport (tall content)
    scroll_view.content_size.height.should be > scroll_view.viewport_size.height
  end

  it "shows vertical scrollbar when content height > viewport height" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    # Add enough buttons to overflow viewport
    10.times { vstack.add_child(CrymbleUI::Button.new("Button") { }) }
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window

    renderer.render_frame(app)

    # Get ScrollView primitives
    primitives = scroll_view.to_primitives(scroll_view.bounds)

    # Assert: At least 4 primitives (track, thumb, up arrow, down arrow)
    # Actually track + thumb = 2 FillRect minimum for now
    primitives.size.should be >= 2

    # Assert: Has FillRect primitives (scrollbar track and thumb)
    fill_rects = primitives.select { |p| p.is_a?(CrymbleUI::FillRect) }
    fill_rects.size.should be >= 2  # At least track and thumb
  end

  it "hides vertical scrollbar when content fits in viewport" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 400, 300)

    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Vertical)
    vstack = CrymbleUI::VStack.new(spacing: 5.0)
    # Add only 1 button (fits in viewport)
    vstack.add_child(CrymbleUI::Button.new("Button") { })
    scroll_view.set_content(vstack)

    window.add_child(scroll_view)
    app.root_widget = window

    renderer.render_frame(app)

    # Assert: Content size should be smaller than viewport
    scroll_view.content_size.height.should be <= scroll_view.viewport_size.height

    # Get ScrollView primitives
    primitives = scroll_view.to_primitives(scroll_view.bounds)

    # Assert: No scrollbar primitives (empty array)
    primitives.size.should eq 0
  end

  it "shows horizontal scrollbar when content width > viewport width" do
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 300)
    app = TestApp.new
    window = CrymbleUI::Window.new("Test", 200, 300)

    # Use horizontal scroll direction
    scroll_view = CrymbleUI::ScrollView.new(direction: CrymbleUI::ScrollDirection::Horizontal)
    hstack = CrymbleUI::HStack.new(spacing: 5.0)
    # Add enough buttons to overflow viewport width
    10.times { hstack.add_child(CrymbleUI::Button.new("Btn") { }) }
    scroll_view.set_content(hstack)

    window.add_child(scroll_view)
    app.root_widget = window

    renderer.render_frame(app)

    # Assert: Content width > viewport width
    scroll_view.content_size.width.should be > scroll_view.viewport_size.width

    # Get ScrollView primitives
    primitives = scroll_view.to_primitives(scroll_view.bounds)

    # Assert: Has scrollbar primitives (horizontal scrollbar)
    primitives.size.should be >= 2  # Track + thumb minimum
  end
end
