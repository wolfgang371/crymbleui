require "../spec_helper"
require "../../src/testing/test_renderer"

# Test app for hover state testing
class StatusBarHoverTestApp < CrymbleUI::App
    state clicks : Int32 = 0

    def build : CrymbleUI::Widget
        window("Test", 400, 300) do
            vstack do
                button("Click", id: "test_btn", user_data: {:hover_text => "Test button"}) do
                    self.clicks += 1
                end
                statusbar("Ready", id: "status")
            end
        end
    end
end

describe CrymbleUI::StatusBar do
    describe ".new" do
        it "creates a statusbar with default text" do
            statusbar = CrymbleUI::StatusBar.new
            statusbar.text.should eq("Ready")
        end

        it "creates a statusbar with custom text" do
            statusbar = CrymbleUI::StatusBar.new(text: "Custom Status")
            statusbar.text.should eq("Custom Status")
        end

        it "creates a statusbar with custom height" do
            statusbar = CrymbleUI::StatusBar.new(height: 30.0)
            statusbar.height.should eq(30.0)
        end

        it "creates a statusbar with custom colors" do
            statusbar = CrymbleUI::StatusBar.new(
                text_color: CrymbleUI::Color.red,
                background_color: CrymbleUI::Color.blue
            )
            statusbar.text_color.should eq(CrymbleUI::Color.red)
            statusbar.background_color.should eq(CrymbleUI::Color.blue)
        end
    end

    describe "#text=" do
        it "updates the text and marks for render" do
            statusbar = CrymbleUI::StatusBar.new
            statusbar.text = "New Status"
            statusbar.text.should eq("New Status")
            statusbar.needs_render?.should be_true
        end
    end

    describe "#measure" do
        it "returns fixed height and flexible width" do
            statusbar = CrymbleUI::StatusBar.new(height: 25.0)
            constraints = CrymbleUI::BoxConstraints.new(max_width: 800.0, max_height: 600.0)
            size = statusbar.measure(constraints)
            size.width.should eq(800.0)
            size.height.should eq(25.0)
        end

        it "uses fallback width if constraints are unbounded" do
            statusbar = CrymbleUI::StatusBar.new
            constraints = CrymbleUI::BoxConstraints.new
            size = statusbar.measure(constraints)
            size.width.should eq(400.0)  # Fallback width
            size.height.should eq(24.0)  # Default height
        end
    end

    describe "#layout" do
        it "positions statusbar at given position" do
            statusbar = CrymbleUI::StatusBar.new
            constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(600.0, 400.0))
            position = CrymbleUI::Vec2.new(0.0, 376.0)

            statusbar.layout(constraints, position)

            statusbar.bounds.x.should eq(0.0)
            statusbar.bounds.y.should eq(376.0)
            statusbar.bounds.width.should eq(600.0)
            statusbar.bounds.height.should eq(24.0)
        end
    end

    describe "#label" do
        it "returns 'statusbar' for path_id generation" do
            statusbar = CrymbleUI::StatusBar.new
            statusbar.label.should eq("statusbar")
        end
    end

    describe "property setters" do
        it "marks needs_render when visual properties change" do
            statusbar = CrymbleUI::StatusBar.new
            statusbar.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            statusbar.font_scale = 0  # font_scale changes trigger layout
            statusbar.needs_layout?.should be_true
            statusbar.state = CrymbleUI::WidgetState::Clean

            statusbar.text_color = CrymbleUI::Color.red
            statusbar.needs_render?.should be_true
            statusbar.state = CrymbleUI::WidgetState::Clean

            statusbar.background_color = CrymbleUI::Color.blue
            statusbar.needs_render?.should be_true
            statusbar.state = CrymbleUI::WidgetState::Clean

            statusbar.border_color = CrymbleUI::Color.green
            statusbar.needs_render?.should be_true
        end

        it "marks needs_layout when structural properties change" do
            statusbar = CrymbleUI::StatusBar.new
            statusbar.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            statusbar.height = 30.0
            statusbar.needs_layout?.should be_true
            statusbar.state = CrymbleUI::WidgetState::Clean

            statusbar.padding = 10.0
            statusbar.needs_layout?.should be_true
        end
    end

    describe "hover state after rebuild" do
        it "maintains hover state after rebuild triggered by button click" do
            app = StatusBarHoverTestApp.new
            app.build_tree

            # Layout the tree so widgets have proper bounds for hit testing
            root = app.root.not_nil!
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(400.0, 300.0))
            root.layout(constraints, CrymbleUI::Vec2.zero)

            # Find the button in the tree
            btn = root.find_by_id("test_btn").not_nil!

            # Simulate hover over button center
            btn_center = CrymbleUI::Vec2.new(btn.bounds.x + btn.bounds.width / 2, btn.bounds.y + btn.bounds.height / 2)
            app.update_hover(btn_center)

            # Verify hover is on the button
            app.hovered_widget.should eq(btn)

            # Simulate click (which triggers rebuild via state change)
            app.handle_mouse_down(btn_center)

            # Layout the new tree (in real app, renderer does this before rendering)
            app.root.not_nil!.layout(constraints, CrymbleUI::Vec2.zero)

            # Re-detect hover after layout (uses last known mouse position)
            app.redetect_hover

            # After rebuild, layout, and hover re-detection, should point to button in NEW tree
            new_btn = app.root.not_nil!.find_by_id("test_btn").not_nil!
            app.hovered_widget.should eq(new_btn)
        end
    end

    describe "#to_primitives" do
        it "generates three primitives (background, border, text)" do
            statusbar = CrymbleUI::StatusBar.new("Ready")
            bounds = CrymbleUI::Rect.new(0, 0, 400, 24)

            primitives = statusbar.to_primitives(bounds)

            primitives.size.should eq(3)
            primitives[0].should be_a(CrymbleUI::FillRect)  # Background
            primitives[1].should be_a(CrymbleUI::FillRect)  # Border
            primitives[2].should be_a(CrymbleUI::DrawText)  # Text
        end

        it "background primitive has correct bounds and color" do
            bg_color = CrymbleUI::Color.new(200, 200, 200, 255)
            statusbar = CrymbleUI::StatusBar.new(background_color: bg_color)
            bounds = CrymbleUI::Rect.new(10, 20, 400, 24)

            primitives = statusbar.to_primitives(bounds)
            background = primitives[0].as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            background.bounds.should eq(CrymbleUI::Rect.new(0.0, 0.0, bounds.width, bounds.height))
            background.color.should eq(bg_color)
        end

        it "border primitive has correct bounds and color" do
            border_color = CrymbleUI::Color.new(150, 150, 150, 255)
            statusbar = CrymbleUI::StatusBar.new(border_color: border_color)
            bounds = CrymbleUI::Rect.new(0, 0, 400, 24)

            primitives = statusbar.to_primitives(bounds)
            border = primitives[1].as(CrymbleUI::FillRect)

            # Border is 1px high at top
            border.bounds.x.should eq(0.0)
            border.bounds.y.should eq(0.0)
            border.bounds.width.should eq(400.0)
            border.bounds.height.should eq(1.0)
            border.color.should eq(border_color)
        end

        it "text primitive has correct content and color" do
            text_color = CrymbleUI::Color.new(50, 50, 50, 255)
            statusbar = CrymbleUI::StatusBar.new("Status Message", text_color: text_color)
            bounds = CrymbleUI::Rect.new(0, 0, 400, 24)

            primitives = statusbar.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            text.text.should eq("Status Message")
            text.color.should eq(text_color)
        end

        it "text primitive is positioned with padding" do
            statusbar = CrymbleUI::StatusBar.new("Test", padding: 8.0, height: 24.0, font_scale: -1)
            bounds = CrymbleUI::Rect.new(10, 20, 400, 24)

            primitives = statusbar.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            # Widget-local coordinates: origin is (0,0)
            # Text should be at 0 + padding (StatusBar uses simple padding, not centering)
            # draw_text compensates for SFML local_bounds offsets
            text.position.x.should be_close(8.0, 2.0)  # 0 + 8, with offset tolerance
            expected_y = 0.0 + 8.0  # 0 + padding (widget-local)
            text.position.y.should be_close(expected_y, 10.0)  # top offset varies by font
        end

        it "text primitive has correct font size" do
            statusbar = CrymbleUI::StatusBar.new(font_scale: 0)  # scale 0 = 14pt
            bounds = CrymbleUI::Rect.new(0, 0, 400, 24)

            primitives = statusbar.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            text.size.should eq(14.0)
        end

    end

    describe "hover callback immediate redraw" do
        it "event loop detects dirty layer after hover callback updates statusbar" do
            renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
            app = StatusBarHoverTestApp.new
            app.build_tree

            btn = app.find("test_btn").not_nil!
            btn.hover_text = "Hovering button"

            # Wire hover callback that updates statusbar directly (like EmbraceApp does)
            app.on_hover_change do
                sb = app.find("status").try &.as?(CrymbleUI::StatusBar)
                if sb && (hw = app.hovered_widget) && (ht = hw.hover_text)
                    sb.text = ht
                end
            end

            renderer.settle_rendering(app)

            # Simulate hover to button
            btn_bounds = btn.absolute_bounds
            btn_center = CrymbleUI::Vec2.new(
                btn_bounds.x + btn_bounds.width / 2.0,
                btn_bounds.y + btn_bounds.height / 2.0
            )
            needs_redraw = app.update_hover(btn_center)

            # Callback ran synchronously — statusbar text should be updated
            sb = app.find("status").not_nil!.as(CrymbleUI::StatusBar)
            sb.text.should eq("Hovering button")

            # The SFML event loop timer path uses update_hover's return as
            # its ONLY break condition. It must ALSO check layer dirty state.
            root = app.root.not_nil!
            layer_dirty = CrymbleUI::Layer.any_needs_render?(root)

            # At least one of these must be true for the event loop to render:
            (needs_redraw || layer_dirty).should be_true
        end

        it "event loop detects dirty layer when hovered widget didn't change" do
            renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
            app = StatusBarHoverTestApp.new
            app.build_tree

            btn = app.find("test_btn").not_nil!
            btn.hover_text = "Hovering button"

            app.on_hover_change do
                sb = app.find("status").try &.as?(CrymbleUI::StatusBar)
                if sb && (hw = app.hovered_widget) && (ht = hw.hover_text)
                    sb.text = ht
                end
            end

            renderer.settle_rendering(app)

            # First hover — moves to button (hover_changed=true)
            btn_bounds = btn.absolute_bounds
            btn_center = CrymbleUI::Vec2.new(
                btn_bounds.x + btn_bounds.width / 2.0,
                btn_bounds.y + btn_bounds.height / 2.0
            )
            app.update_hover(btn_center)
            renderer.render_frame(app)

            # Second hover — same widget, different position (hover_changed=false)
            # Callback still fires, but statusbar text is same so no re-mark
            # Change hover_text to simulate position-dependent text change
            btn.hover_text = "Cell (2,3)"
            nearby = CrymbleUI::Vec2.new(btn_center.x + 1.0, btn_center.y)
            needs_redraw = app.update_hover(nearby)

            # update_hover returns false (same widget) — this is the event loop's
            # sole break condition in the timer sleep loop
            needs_redraw.should be_false

            # But the callback dirtied the statusbar layer — event loop must detect this
            root = app.root.not_nil!
            CrymbleUI::Layer.any_needs_render?(root).should be_true
        end
    end

    describe "hover callback after rebuild" do
        it "hover callback updates statusbar after rebuild (no stale cache)" do
            renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
            app = StatusBarHoverTestApp.new
            app.build_tree

            btn = app.find("test_btn").not_nil!
            btn.hover_text = "Hovering button"

            # Use find() each time (not caching) — the correct pattern
            app.on_hover_change do
                sb = app.find("status").try &.as?(CrymbleUI::StatusBar)
                if sb && (hw = app.hovered_widget) && (ht = hw.hover_text)
                    sb.text = ht
                end
            end

            renderer.settle_rendering(app)

            # Hover works initially
            btn_bounds = btn.absolute_bounds
            btn_center = CrymbleUI::Vec2.new(
                btn_bounds.x + btn_bounds.width / 2.0,
                btn_bounds.y + btn_bounds.height / 2.0
            )
            app.update_hover(btn_center)
            app.find("status").not_nil!.as(CrymbleUI::StatusBar).text.should eq("Hovering button")

            # Trigger rebuild (like creating a new shape)
            app.clicks = 1  # state change → request_rebuild
            app.rebuild
            renderer.render_frame(app)

            # Re-find button in new tree and hover
            btn = app.find("test_btn").not_nil!
            btn.hover_text = "After rebuild"
            btn_bounds = btn.absolute_bounds
            btn_center = CrymbleUI::Vec2.new(
                btn_bounds.x + btn_bounds.width / 2.0,
                btn_bounds.y + btn_bounds.height / 2.0
            )
            app.update_hover(btn_center)

            # The VISIBLE statusbar (new instance) should have the hover text
            app.find("status").not_nil!.as(CrymbleUI::StatusBar).text.should eq("After rebuild")
        end
    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            statusbar = CrymbleUI::StatusBar.new("Cached")
            bounds = CrymbleUI::Rect.new(0, 0, 400, 24)

            # First call generates
            primitives1 = statusbar.get_primitives(bounds)
            statusbar.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = statusbar.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates primitives when text changes" do
            statusbar = CrymbleUI::StatusBar.new("Original")
            bounds = CrymbleUI::Rect.new(0, 0, 400, 24)

            primitives1 = statusbar.get_primitives(bounds)
            text1 = primitives1[2].as(CrymbleUI::DrawText)

            # text= calls mark_needs_render
            statusbar.text = "Modified"

            primitives2 = statusbar.get_primitives(bounds)
            text2 = primitives2[2].as(CrymbleUI::DrawText)

            text1.text.should eq("Original")
            text2.text.should eq("Modified")
        end

        it "regenerates primitives when colors change" do
            statusbar = CrymbleUI::StatusBar.new
            bounds = CrymbleUI::Rect.new(0, 0, 400, 24)

            primitives1 = statusbar.get_primitives(bounds)
            bg1 = primitives1[0].as(CrymbleUI::FillRect)

            # background_color= calls mark_needs_render
            new_color = CrymbleUI::Color.new(255, 0, 0, 255)
            statusbar.background_color = new_color

            primitives2 = statusbar.get_primitives(bounds)
            bg2 = primitives2[0].as(CrymbleUI::FillRect)

            bg1.color.should_not eq(new_color)
            bg2.color.should eq(new_color)
        end
    end
end
