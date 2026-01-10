require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/popup"
require "../../src/dsl/builder"

# Test for popup DSL close regression
# Bug: DSL-conditional popups don't disappear when condition becomes false
# because popup() uses add_overlay which persists across rebuilds

module CrymbleUI
  # App that conditionally shows a popup based on state
  class PopupToggleTestApp < App
    state show_popup : Bool = false

    def build : Widget
      window("Test", 400, 300) do
        vstack do
          button("Toggle") { self.show_popup = !show_popup }
        end

        if show_popup
          popup(x: 100.0, y: 100.0, id: "test_popup") do
            button("Close") { self.show_popup = false }
          end
        end
      end
    end
  end
end

describe "Popup DSL close behavior" do
  it "popup disappears when condition becomes false" do
    app = CrymbleUI::PopupToggleTestApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

    # Initial state: no popup
    app.build_tree
    renderer.render_frame(app)
    app.find("test_popup").should be_nil

    # Show popup
    app.show_popup = true
    app.rebuild
    renderer.render_frame(app)
    popup = app.find("test_popup")
    popup.should_not be_nil

    # Hide popup by toggling state
    app.show_popup = false
    app.rebuild
    renderer.render_frame(app)

    # Popup should be gone (no longer persists via overlay migration)
    app.find("test_popup").should be_nil
  end

  it "clicking close button inside popup closes it" do
    app = CrymbleUI::PopupToggleTestApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

    # Show popup
    app.show_popup = true
    app.build_tree
    renderer.render_frame(app)

    popup = app.find("test_popup")
    popup.should_not be_nil

    # Find and click the Close button
    close_button = popup.not_nil!.children.find { |c| c.is_a?(CrymbleUI::Button) }
    close_button.should_not be_nil

    # Simulate click on close button
    button_center = close_button.not_nil!.absolute_bounds.center
    app.handle_mouse_down(button_center)
    app.handle_mouse_up(button_center)

    # After click, show_popup should be false and popup should be gone
    app.show_popup.should be_false
    renderer.render_frame(app)
    app.find("test_popup").should be_nil
  end

  it "popup is positioned at specified x, y coordinates" do
    app = CrymbleUI::PopupToggleTestApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)

    # Show popup at x: 100.0, y: 100.0 (as specified in build)
    app.show_popup = true
    app.build_tree
    renderer.render_frame(app)

    popup = app.find("test_popup")
    popup.should_not be_nil

    # Popup should be positioned at target_x=100, target_y=100
    popup.not_nil!.absolute_bounds.x.should eq 100.0
    popup.not_nil!.absolute_bounds.y.should eq 100.0
  end
end
