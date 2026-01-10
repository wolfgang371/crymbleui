require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# DSL-style App with many items to test scrollbar behavior
class ComboBoxScrollbarFilterApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window = CrymbleUI::Window.new("Test", 400, 400)
    vstack = CrymbleUI::VStack.new

    # 20 items - enough to require scrollbar
    items = (1..20).map { |i| "Item #{i}" }
    combo = CrymbleUI::ComboBox.new(items: items, selected: 0, width: 200.0, id: "combo")

    vstack.children << combo
    combo.parent = vstack
    window.children << vstack
    vstack.parent = window

    window
  end
end

describe "ComboBox scrollbar filter behavior" do
  # BUG: After typing to filter items, the VStack's bounds don't shrink
  # because rebuild_items() uses @vstack.children.clear instead of @vstack.clear_children
  # The .children.clear doesn't call mark_needs_layout, so layout isn't recalculated
  #
  # We detect this by checking that the VStack (found via popup children) gets
  # properly laid out after filtering.
  it "VStack bounds shrink after filtering reduces items" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
    app = ComboBoxScrollbarFilterApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Open the popup by clicking on ComboBox
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    # Get popup
    combo.popup_open?.should be_true
    popup = combo.current_popup.not_nil!

    # Record initial item count and popup bounds
    popup.item_widgets.size.should eq 20
    initial_popup_height = popup.bounds.height

    # Find VStack via popup's children (children[0]=TextInput, children[1]=ScrollView)
    # ScrollView's content is the VStack
    scroll_view = popup.children[1].as(CrymbleUI::ScrollView)
    vstack = scroll_view.children[0].as(CrymbleUI::VStack)

    # Record initial VStack bounds
    initial_vstack_height = vstack.bounds.height
    initial_vstack_height.should be > 0.0  # Sanity check

    # Type "Item 1" to filter - should match "Item 1", "Item 10"-"Item 19" = 11 items
    "Item 1".each_char do |c|
      CrymbleUI::Widget.focus_manager.handle_text_input(c)
    end
    renderer.render_frame(app)

    # Verify filter worked (fewer items)
    popup.item_widgets.size.should eq 11

    # THIS IS THE BUG: VStack bounds should have shrunk because fewer items
    # But with .children.clear, mark_needs_layout wasn't called, so layout
    # didn't recalculate the VStack size
    new_vstack_height = vstack.bounds.height

    # VStack height should be roughly 11/20 of original
    new_vstack_height.should be < initial_vstack_height
  end

  # After filtering, the scrollbar thumb height should decrease
  # (fewer items = smaller content = larger thumb relative to viewport)
  # This verifies the scrollbar_layer is re-rendered with correct proportions
  it "scrollbar thumb height increases after filtering reduces items" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
    app = ComboBoxScrollbarFilterApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Open the popup
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    popup = combo.current_popup.not_nil!
    scroll_view = popup.children[1].as(CrymbleUI::ScrollView)

    # Render to stabilize
    3.times { renderer.render_frame(app) }

    # Record initial content size (20 items)
    initial_content_height = scroll_view.content_size.height
    initial_content_height.should be > 0.0

    # Type to filter - "Item 2" matches only 2 items
    "Item 2".each_char do |c|
      CrymbleUI::Widget.focus_manager.handle_text_input(c)
    end
    renderer.render_frame(app)  # IMPORTANT: render to apply changes

    # Content should be SMALLER now (2 items vs 20 items)
    # This indirectly tests that scrollbar will render correctly
    new_content_height = scroll_view.content_size.height

    # Content height should be much smaller (2/20 = 10%)
    new_content_height.should be < initial_content_height * 0.25
  end

  # This test directly checks the ScrollView's content_size
  # The bug symptom is that content_size doesn't shrink after filtering
  it "ScrollView content_size shrinks after filtering reduces items" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
    app = ComboBoxScrollbarFilterApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Open the popup
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    popup = combo.current_popup.not_nil!
    scroll_view = popup.children[1].as(CrymbleUI::ScrollView)

    # Record initial content_size (20 items)
    initial_content_height = scroll_view.content_size.height
    initial_content_height.should be > 0.0

    # Type to filter - "Item 2" should match "Item 2", "Item 20" = 2 items
    # (filter uses starts_with?, so "Item 2" matches items STARTING with "Item 2")
    "Item 2".each_char do |c|
      CrymbleUI::Widget.focus_manager.handle_text_input(c)
    end
    renderer.render_frame(app)

    # Verify filter worked - "Item 2" and "Item 20" match
    popup.item_widgets.size.should eq 2

    # THE BUG: content_size should shrink proportionally to item count
    # 2/20 items = 0.1, so new height should be roughly 10% of initial
    new_content_height = scroll_view.content_size.height
    new_content_height.should be < initial_content_height * 0.5  # Much smaller
  end

  it "filtered items are all properly laid out with non-zero bounds" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
    app = ComboBoxScrollbarFilterApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Open the popup
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    popup = combo.current_popup.not_nil!

    # Type to filter
    "Item 2".each_char do |c|
      CrymbleUI::Widget.focus_manager.handle_text_input(c)
    end
    renderer.render_frame(app)

    # Should have filtered to 2 items: "Item 2", "Item 20"
    popup.item_widgets.size.should eq 2

    # ALL filtered items should have non-zero bounds (properly laid out)
    popup.item_widgets.each_with_index do |item, idx|
      item.bounds.width.should be > 0.0, "Item #{idx} has zero width"
      item.bounds.height.should be > 0.0, "Item #{idx} has zero height"
    end
  end

  # BUG TEST: After filtering reduces items such that no scrollbar is needed,
  # the scrollbar_layer should be cleared (transparent/empty)
  it "scrollbar pixels are cleared when scrollbar becomes unnecessary" do
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 400)
    app = ComboBoxScrollbarFilterApp.new
    app.build_tree
    renderer.render_frame(app)

    combo = app.find("combo").as(CrymbleUI::ComboBox)

    # Open the popup
    abs = combo.absolute_bounds
    click_pos = CrymbleUI::Vec2.new(abs.x + 10.0, abs.y + 10.0)
    app.handle_mouse_down(click_pos)
    app.handle_mouse_up(click_pos)
    renderer.render_frame(app)

    popup = combo.current_popup.not_nil!
    scroll_view = popup.children[1].as(CrymbleUI::ScrollView)
    scrollbar_layer = scroll_view.scrollbar_layer.not_nil!

    # Initially should have scrollbar (20 items > viewport)
    scroll_view.content_size.height.should be > scroll_view.viewport_size.height

    # Verify scrollbar pixels exist (either track=220 or thumb=150 gray)
    backend = scrollbar_layer.backend.as(CrymbleUI::Testing::TestRenderBackend)
    # Check right edge where scrollbar should be
    scrollbar_x = (scrollbar_layer.bounds.width - 8).to_i  # Middle of scrollbar area
    initial_pixel = backend.get_pixel(scrollbar_x, 50)
    initial_pixel.should_not be_nil, "Expected scrollbar pixel to exist"
    initial_pixel.not_nil!.a.should eq 255_u8  # Should be opaque (scrollbar visible)

    # Type to filter to only 2 items - should NOT need scrollbar
    "Item 2".each_char do |c|
      CrymbleUI::Widget.focus_manager.handle_text_input(c)
    end
    renderer.render_frame(app)

    # Verify no scrollbar needed (2 items fit in viewport)
    scroll_view.content_size.height.should be <= scroll_view.viewport_size.height

    # THE BUG: scrollbar pixels should be CLEARED (transparent)
    # If bug exists, they will still be gray (220)
    post_filter_pixel = backend.get_pixel(scrollbar_x, 50)
    post_filter_pixel.should_not be_nil, "Expected pixel to exist"
    post_filter_pixel.not_nil!.a.should eq 0_u8  # Should be transparent (cleared)
  end
end
