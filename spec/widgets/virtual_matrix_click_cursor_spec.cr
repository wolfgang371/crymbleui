require "../spec_helper"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/widgets/text_input"
require "../../src/widgets/scroll_view"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"
require "../../src/core/layer"
require "../../src/dsl/builder"

# Regression test: clicking on a VirtualMatrix data cell must set cursor_rc
# to that cell even when VirtualMatrix is inside a scrolled ScrollView.
#
# ROOT CAUSE: Two bugs conspired:
# 1. ScrollView.hit_test_with_offset bypassed widget hit_test overrides,
#    so VirtualMatrix's "return self" was ignored and cell widgets got hits.
# 2. on_mouse_down receives screen-space coordinates from App, but
#    point_to_cell used content-space absolute_bounds to convert.
#    When an outer ScrollView has scrolled, these don't match.

class ClickCursorTestApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 800, 600) do
      widget(CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "click_grid"))
    end
  end
end

# App with VirtualMatrix inside a ScrollView (like embrace's shape panel)
class ScrolledMatrixApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  def build : CrymbleUI::Widget
    window("Test", 800, 600) do
      scroll_view(id: "outer_sv") do
        vstack do
          # Spacer content to push VirtualMatrix down
          20.times do |i|
            text("Filler line #{i}")
          end
          widget(CrymbleUI::VirtualMatrix.new(rows: 10, cols: 5, id: "scrolled_grid"))
        end
      end
    end
  end
end

describe "VirtualMatrix click-to-cursor" do
  it "click on data cell sets cursor_rc (no scroll)" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ClickCursorTestApp.new
    app.build_tree
    renderer.settle_rendering(app)

    matrix = app.find("click_grid").as(CrymbleUI::VirtualMatrix)
    cell = matrix.active_cells[{2, 2}].not_nil!
    abs = matrix.absolute_bounds
    click_x = abs.x + cell.bounds.x + cell.bounds.width / 2
    click_y = abs.y + cell.bounds.y + cell.bounds.height / 2

    renderer.mouse_down(click_x, click_y)
    renderer.mouse_up(click_x, click_y)
    renderer.render_frame(app)

    matrix = app.find("click_grid").as(CrymbleUI::VirtualMatrix)
    matrix.cursor_rc.should eq({2, 2})
  end

  it "click sets cursor_rc when inside a scrolled ScrollView" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ScrolledMatrixApp.new
    app.build_tree
    renderer.settle_rendering(app)

    sv = app.find("outer_sv").as(CrymbleUI::ScrollView)
    matrix = app.find("scrolled_grid").as(CrymbleUI::VirtualMatrix)
    mx_abs = matrix.absolute_bounds
    sv_abs = sv.absolute_bounds

    # Scroll down to bring VirtualMatrix into view
    scroll_y = mx_abs.y - sv_abs.y - 50.0
    scroll_y = {scroll_y, 0.0}.max
    sv.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll_y)
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    matrix = app.find("scrolled_grid").as(CrymbleUI::VirtualMatrix)
    sv = app.find("outer_sv").as(CrymbleUI::ScrollView)
    mx_abs = matrix.absolute_bounds
    sv_scroll = sv.scroll_offset

    cell = matrix.active_cells[{2, 2}].not_nil!

    # Screen position = content position - ancestor scroll offset
    screen_x = mx_abs.x + cell.bounds.x + cell.bounds.width / 2 - sv_scroll.x
    screen_y = mx_abs.y + cell.bounds.y + cell.bounds.height / 2 - sv_scroll.y

    renderer.mouse_down(screen_x, screen_y)
    renderer.mouse_up(screen_x, screen_y)
    renderer.render_frame(app)

    matrix = app.find("scrolled_grid").as(CrymbleUI::VirtualMatrix)
    matrix.cursor_rc.should eq({2, 2})
  end

  it "cursor-down from clicked cell in scrolled ScrollView preserves column" do
    renderer = CrymbleUI::Testing::TestRenderer.new(800, 600)
    app = ScrolledMatrixApp.new
    app.build_tree
    renderer.settle_rendering(app)

    sv = app.find("outer_sv").as(CrymbleUI::ScrollView)
    matrix = app.find("scrolled_grid").as(CrymbleUI::VirtualMatrix)
    mx_abs = matrix.absolute_bounds
    sv_abs = sv.absolute_bounds

    # Scroll down
    scroll_y = mx_abs.y - sv_abs.y - 50.0
    scroll_y = {scroll_y, 0.0}.max
    sv.scroll_offset = CrymbleUI::Vec2.new(0.0, scroll_y)
    renderer.render_frame(app)
    renderer.settle_rendering(app)

    matrix = app.find("scrolled_grid").as(CrymbleUI::VirtualMatrix)
    sv = app.find("outer_sv").as(CrymbleUI::ScrollView)
    mx_abs = matrix.absolute_bounds
    sv_scroll = sv.scroll_offset

    # Click on cell (1, 3)
    cell = matrix.active_cells[{1, 3}].not_nil!
    screen_x = mx_abs.x + cell.bounds.x + cell.bounds.width / 2 - sv_scroll.x
    screen_y = mx_abs.y + cell.bounds.y + cell.bounds.height / 2 - sv_scroll.y

    renderer.mouse_down(screen_x, screen_y)
    renderer.mouse_up(screen_x, screen_y)
    renderer.render_frame(app)

    matrix = app.find("scrolled_grid").as(CrymbleUI::VirtualMatrix)
    matrix.cursor_rc.should eq({1, 3})

    # Cursor-down should preserve column
    press_key(SF::Keyboard::Key::Down)
    renderer.render_frame(app)

    matrix = app.find("scrolled_grid").as(CrymbleUI::VirtualMatrix)
    matrix.cursor_rc.should eq({2, 3})
  end
end
