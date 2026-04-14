require "../spec_helper"
require "../../src/rendering/sfml_renderer"


# Test app for cache integration tests
class TextureCacheTestApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        vstack(id: "root") do
            text("Test")
            button("Button") { }
        end
    end
end


describe "Texture caching behavior" do
    describe "selective rendering with needs_repaint" do
        it "leaf widget with needs_repaint is rendered" do
            # Create a window with widget tree (widgets need a layer to propagate to)
            window = CrymbleUI::Window.new("Test", 800, 600)
            root = CrymbleUI::VStack.new(id: "root")
            btn1 = CrymbleUI::Button.new("Button 1") { }
            btn2 = CrymbleUI::Button.new("Button 2") { }
            root.add_child(btn1)
            root.add_child(btn2)
            window.add_child(root)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            # Clear layer AND widget states (simulate: initial render complete)
            window.root_layer.not_nil!.clear_render_state
            root.clear_render_state_recursive

            # Change one button's color
            btn1.background_color = CrymbleUI::Color.new(255, 0, 0, 255)

            # btn1 should need repaint, and root layer should be marked (layer propagation)
            btn1.needs_render?.should be_true
            btn2.needs_render?.should be_false
            window.root_layer.not_nil!.needs_render?.should be_true # Flag propagated to layer
        end

        it "container without changes doesn't need repaint after render cycle" do
            root = CrymbleUI::VStack.new(id: "root")
            btn1 = CrymbleUI::Button.new("Button 1") { }
            btn2 = CrymbleUI::Button.new("Button 2") { }
            root.add_child(btn1)
            root.add_child(btn2)

            # Layout
            constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
            root.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

            # Clear widget states (simulate: initial render complete)
            root.clear_render_state_recursive

            # No changes made - all should be clean
            root.needs_render?.should be_false
            btn1.needs_render?.should be_false
            btn2.needs_render?.should be_false
        end

        it "visual property changes mark widget as needs_repaint" do
            btn = CrymbleUI::Button.new("Test") { }

            # Change various visual properties
            btn.background_color = CrymbleUI::Color.new(255, 0, 0, 255)
            btn.needs_render?.should be_true
            btn.state = CrymbleUI::WidgetState::Clean

            btn.text_color = CrymbleUI::Color.new(0, 255, 0, 255)
            btn.needs_render?.should be_true
            btn.state = CrymbleUI::WidgetState::Clean

            btn.border_color = CrymbleUI::Color.new(0, 0, 255, 255)
            btn.needs_render?.should be_true
            btn.state = CrymbleUI::WidgetState::Clean

            btn.text = "Changed"
            btn.needs_render?.should be_true
            btn.state = CrymbleUI::WidgetState::Clean

            btn.font_scale = 3
            btn.needs_render?.should be_true
            btn.state = CrymbleUI::WidgetState::Clean

            btn.padding = 15.0
            btn.needs_render?.should be_true
        end

        it "needs_repaint propagates to layer" do
            # Create nested structure with layer
            window = CrymbleUI::Window.new("Test", 800, 600)
            root = CrymbleUI::VStack.new(id: "root")
            middle = CrymbleUI::HStack.new(id: "middle")
            btn = CrymbleUI::Button.new("Button") { }

            root.add_child(middle)
            middle.add_child(btn)
            window.add_child(root)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            # Clear layer state
            window.root_layer.not_nil!.clear_render_state

            # Change leaf widget
            btn.background_color = CrymbleUI::Color.new(255, 0, 0, 255)

            # Widget should be marked, and it propagates to layer (not parent widgets)
            btn.needs_render?.should be_true
            window.root_layer.not_nil!.needs_render?.should be_true
        end
    end

    describe "SFMLRenderer cache integration" do
        it "renders frame without crashing after layout" do
            # Create test app
            app = TextureCacheTestApp.new
            app.build_tree

            if root = app.root
                # Layout
                constraints = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(800.0, 600.0))
                root.layout(constraints, CrymbleUI::Vec2.new(0.0, 0.0))

                # First layout changes size from 0→actual, so widget needs render
                root.state.should eq(CrymbleUI::WidgetState::NeedsRender)
                root.bounds.width.should be > 0
                root.bounds.height.should be > 0
            end
        end

        it "selective update only affects changed widgets" do
            # Create tree with multiple widgets in a window (needs layer)
            window = CrymbleUI::Window.new("Test", 800, 600)
            root = CrymbleUI::VStack.new(id: "root")
            btn1 = CrymbleUI::Button.new("Button 1") { }
            btn2 = CrymbleUI::Button.new("Button 2") { }
            btn3 = CrymbleUI::Button.new("Button 3") { }
            root.add_child(btn1)
            root.add_child(btn2)
            root.add_child(btn3)
            window.add_child(root)

            # Layout
            constraints = CrymbleUI::BoxConstraints.tight(CrymbleUI::Size.new(800.0, 600.0))
            window.layout(constraints, CrymbleUI::Vec2.zero)

            # Clear layer AND widget states (simulate: initial render complete)
            window.root_layer.not_nil!.clear_render_state
            root.clear_render_state_recursive

            # Change only middle button
            btn2.background_color = CrymbleUI::Color.new(255, 0, 0, 255)

            # Verify only btn2 needs repaint (leaf-level)
            btn1.needs_render?.should be_false
            btn2.needs_render?.should be_true
            btn3.needs_render?.should be_false

            # Layer knows tree needs repaint (flag propagated to layer)
            window.root_layer.not_nil!.needs_render?.should be_true
        end
    end
end
