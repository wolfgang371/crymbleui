require "../spec_helper"
require "../../src/widgets/tree_node"
require "../../src/widgets/text_input"
require "../../src/widgets/virtual_matrix"
require "../../src/widgets/window"
require "../../src/widgets/window_panel"
require "../../src/widgets/cpu_monitor"
require "../../src/testing/test_renderer"
require "../../src/rendering/layer_renderer"

# DSL app with TreeNode, TextInput, and WindowPanel
class ThemeSwitchTestApp < CrymbleUI::App
  def build : CrymbleUI::Widget
    window("Test", 600, 400) do
      window_panel("Panel", 0.0, 0.0, 580.0, 380.0, id: "panel") do
        tree_node("Section Header", expanded: true, id: "section") do
          text_input(value: "hello", id: "input1")
        end
      end
    end
  end
end

# DSL app with VirtualMatrix
class ThemeSwitchMatrixAdapter
  include CrymbleUI::Widgets::VirtualMatrix::HeaderlessMatrixAdapter

  def row_count : Int32
    5
  end

  def col_count : Int32
    3
  end

  def cell_paint(row : Int32, col : Int32) : CrymbleUI::Widget
    CrymbleUI::TextInput.new(value: "R#{row}C#{col}", id: "cell_#{row}_#{col}",
      mode: CrymbleUI::TextInputMode::QuickEntry)
  end
end

class ThemeSwitchMatrixApp < CrymbleUI::App
  getter adapter : ThemeSwitchMatrixAdapter

  def initialize
    @adapter = ThemeSwitchMatrixAdapter.new
    super()
  end

  def build : CrymbleUI::Widget
    window("Test", 600, 400) do
      window_panel("Panel", 0.0, 0.0, 580.0, 380.0, id: "panel") do
        widget(CrymbleUI::VirtualMatrix.new(@adapter, id: "matrix"))
      end
    end
  end
end

describe "Theme switch widget colors" do
  # Reset to light theme before each test
  before_each do
    CrymbleUI::Theme.set(:light)
  end

  it "TreeNode header text_color updates after theme switch" do
    app = ThemeSwitchTestApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)

    # Light theme: TreeNode text should be dark
    tn = app.find("section").as(CrymbleUI::TreeNode)
    light_text = tn.@header_widget.text_color # getter: resolves live (ivar is now a nullable override store)
    light_text.r.should be < 100  # dark text on light theme

    # Switch to dark
    CrymbleUI::Theme.set(:dark)
    app.request_rebuild
    renderer.render_frame(app)
    renderer.render_frame(app)

    # Dark theme: TreeNode text should be light
    tn = app.find("section").as(CrymbleUI::TreeNode)
    dark_text = tn.@header_widget.text_color # getter: resolves live (ivar is now a nullable override store)
    dark_text.r.should be > 150  # light text on dark theme
  end

  it "TextInput background_color updates after theme switch" do
    app = ThemeSwitchTestApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)

    # Light theme: TextInput bg should be white
    ti = app.find("input1").as(CrymbleUI::TextInput)
    light_bg = ti.background_color
    light_bg.r.should be > 200  # white-ish

    # Switch to dark
    CrymbleUI::Theme.set(:dark)
    app.request_rebuild
    renderer.render_frame(app)
    renderer.render_frame(app)

    # Dark theme: TextInput bg should be dark
    ti = app.find("input1").as(CrymbleUI::TextInput)
    dark_bg = ti.background_color
    dark_bg.r.should be < 100  # dark background
  end

  it "WindowPanel background_color updates after theme switch" do
    app = ThemeSwitchTestApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)

    # Light theme: panel bg should be light
    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    light_bg = panel.background_color
    light_bg.r.should be > 200  # light

    # Switch to dark
    CrymbleUI::Theme.set(:dark)
    app.request_rebuild
    renderer.render_frame(app)
    renderer.render_frame(app)

    # Dark theme: panel bg should be dark
    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    dark_bg = panel.background_color
    dark_bg.r.should be < 100  # dark
  end

  it "VirtualMatrix cell colors update after theme switch" do
    app = ThemeSwitchMatrixApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)

    # Light theme: cell bg should be white
    matrix = app.find("matrix").as(CrymbleUI::VirtualMatrix)
    cell = matrix.active_cells[{0, 0}]?
    cell.should_not be_nil
    light_bg = cell.not_nil!.as(CrymbleUI::TextInput).background_color
    light_bg.r.should be > 200  # white

    # Switch to dark + invalidate cells
    CrymbleUI::Theme.set(:dark)
    app.adapter.invalidate_all!
    app.request_rebuild
    renderer.render_frame(app)
    renderer.render_frame(app)
    renderer.render_frame(app)  # extra for deferred flush

    # Dark theme: cell bg should be dark
    matrix = app.find("matrix").as(CrymbleUI::VirtualMatrix)
    cell = matrix.active_cells[{0, 0}]?
    cell.should_not be_nil
    dark_bg = cell.not_nil!.as(CrymbleUI::TextInput).background_color
    dark_bg.r.should be < 100  # dark
  end
end

# Snapshot-drop, layer-held + remaining widgets. These assert LIVE theming with NO rebuild
# (the stricter contract): after Theme.set the widget/layer reflects the new theme immediately,
# without app.request_rebuild. Layer-held colors (panel/matrix/sticky backgrounds) need the
# pull-based Layer#background_color (mirrors compute_bounds_for_layer).
describe "Live theme without rebuild (snapshot-drop tail)" do
  before_each { CrymbleUI::Theme.set(:light) }
  after_each { CrymbleUI::Theme.set(:light) }

  it "WindowPanel title_bar_color follows Theme.set live (no rebuild)" do
    app = ThemeSwitchTestApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)
    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    CrymbleUI::Theme.set(:dark)
    panel.title_bar_color.should eq CrymbleUI::Theme.current.panel_title_bar # live, no rebuild
  end

  it "WindowPanel panel-layer background follows Theme.set live (pull-based layer bg)" do
    app = ThemeSwitchTestApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)
    panel = app.find("panel").as(CrymbleUI::WindowPanel)
    CrymbleUI::Theme.set(:dark)
    panel.layer.not_nil!.background_color.should eq CrymbleUI::Theme.current.panel_background # pull → live
  end

  it "VirtualMatrix content-layer background follows Theme.set live (pull-based layer bg)" do
    app = ThemeSwitchMatrixApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(600, 400)
    renderer.settle_rendering(app)
    matrix = app.find("matrix").as(CrymbleUI::VirtualMatrix)
    CrymbleUI::Theme.set(:dark)
    matrix.content_layer.not_nil!.background_color.should eq CrymbleUI::Theme.current.grid_content_background
  end

  it "CPUMonitor text_color follows Theme.set live" do
    m = CrymbleUI::CPUMonitor.new
    CrymbleUI::Theme.set(:dark)
    m.text_color.should eq CrymbleUI::Theme.current.text_default
  end
end
