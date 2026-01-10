require "../spec_helper"
require "../../src/widgets/menu"
require "../../src/widgets/menubar"

describe CrymbleUI::Menu do
    describe "#initialize" do
        it "creates menu with label" do
            menu = CrymbleUI::Menu.new("File")
            menu.label_text.should eq("File")
            menu.open?.should be_false
        end

        it "accepts id parameter" do
            menu = CrymbleUI::Menu.new("Edit", id: "edit_menu")
            menu.id.should eq("edit_menu")
        end

        it "accepts custom visual properties" do
            menu = CrymbleUI::Menu.new(
                "View",
                font_scale: 1,
                text_color: CrymbleUI::Color.red,
                padding: 12.0
            )
            menu.font_scale.should eq(1)
            menu.text_color.should eq(CrymbleUI::Color.red)
            menu.padding.should eq(12.0)
        end
    end

    describe "#label" do
        it "returns 'menu' for path_id generation" do
            menu = CrymbleUI::Menu.new("File")
            menu.label.should eq("menu")
        end
    end

    describe "#measure" do
        it "returns width based on label text and padding" do
            menu = CrymbleUI::Menu.new("File")
            constraints = CrymbleUI::BoxConstraints.new
            size = menu.measure(constraints)

            # Should include text width + padding*2
            size.width.should be > 0.0
        end

        it "returns fixed height from constraints" do
            menu = CrymbleUI::Menu.new("File")
            constraints = CrymbleUI::BoxConstraints.new(max_height: 28.0)
            size = menu.measure(constraints)

            size.height.should eq(28.0)
        end

        it "uses fallback height if constraints are unbounded" do
            menu = CrymbleUI::Menu.new("File")
            constraints = CrymbleUI::BoxConstraints.new
            size = menu.measure(constraints)

            size.height.should eq(28.0)  # Fallback height
        end
    end

    describe "#on_mouse_enter and #on_mouse_exit" do
        it "sets hovered state and marks for render" do
            menu = CrymbleUI::Menu.new("File")
            menu.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            menu.on_mouse_enter
            menu.needs_render?.should be_true
        end

        it "clears hovered state on exit" do
            menu = CrymbleUI::Menu.new("File")
            menu.layout(CrymbleUI::BoxConstraints.new, CrymbleUI::Vec2.zero)

            menu.on_mouse_enter
            menu.state = CrymbleUI::WidgetState::Clean

            menu.on_mouse_exit
            menu.needs_render?.should be_true
        end
    end

    describe "#to_primitives" do
        it "generates three primitives (background, border, text)" do
            menu = CrymbleUI::Menu.new("File")
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            primitives = menu.to_primitives(bounds)

            primitives.size.should eq(3)
            primitives[0].should be_a(CrymbleUI::FillRect)  # Background
            primitives[1].should be_a(CrymbleUI::FillRect)  # Border
            primitives[2].should be_a(CrymbleUI::DrawText)  # Text
        end

        it "background primitive has correct bounds and default color" do
            bg_color = CrymbleUI::Color.new(250, 250, 250, 255)
            menu = CrymbleUI::Menu.new("File", background_color: bg_color)
            bounds = CrymbleUI::Rect.new(10, 20, 60, 28)

            primitives = menu.to_primitives(bounds)
            background = primitives[0].as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            # Background should be full bounds minus border height at bottom
            background.bounds.x.should eq(0.0)
            background.bounds.y.should eq(0.0)
            background.bounds.width.should eq(60.0)
            background.bounds.height.should eq(27.0)  # 28 - 1 (BORDER_WIDTH)
            background.color.should eq(bg_color)
        end

        it "background color changes when hovered" do
            bg_color = CrymbleUI::Color.new(250, 250, 250, 255)
            hover_color = CrymbleUI::Color.new(230, 230, 230, 255)
            menu = CrymbleUI::Menu.new("File", background_color: bg_color, hover_color: hover_color)
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            # Not hovered - should use background_color
            primitives1 = menu.to_primitives(bounds)
            bg1 = primitives1[0].as(CrymbleUI::FillRect)

            # Hovered - should use hover_color
            menu.on_mouse_enter
            primitives2 = menu.to_primitives(bounds)
            bg2 = primitives2[0].as(CrymbleUI::FillRect)

            bg1.color.should eq(bg_color)
            bg2.color.should eq(hover_color)
        end

        it "border primitive has correct bounds and color" do
            menu = CrymbleUI::Menu.new("File")
            bounds = CrymbleUI::Rect.new(10, 20, 60, 28)

            primitives = menu.to_primitives(bounds)
            border = primitives[1].as(CrymbleUI::FillRect)

            # Widget-local coordinates: origin is (0,0)
            # Border is 1px high at bottom
            border.bounds.x.should eq(0.0)
            border.bounds.y.should eq(27.0)  # 28 - 1 (widget-local)
            border.bounds.width.should eq(60.0)
            border.bounds.height.should eq(1.0)
            # Default border color
            border.color.should eq(CrymbleUI::Color.new(200, 200, 200, 255))
        end

        it "border color comes from parent MenuBar if available" do
            menubar = CrymbleUI::MenuBar.new(border_color: CrymbleUI::Color.red)
            menu = CrymbleUI::Menu.new("File")
            menubar.add_child(menu)
            menu.parent = menubar
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            primitives = menu.to_primitives(bounds)
            border = primitives[1].as(CrymbleUI::FillRect)

            border.color.should eq(CrymbleUI::Color.red)
        end

        it "text primitive has correct content and color" do
            text_color = CrymbleUI::Color.new(0, 0, 0, 255)
            menu = CrymbleUI::Menu.new("File", text_color: text_color)
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            primitives = menu.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            text.text.should eq("File")
            text.color.should eq(text_color)
        end

        it "text primitive is positioned with padding" do
            menu = CrymbleUI::Menu.new("File", padding: 10.0, font_scale: 0)
            bounds = CrymbleUI::Rect.new(10, 20, 60, 28)

            primitives = menu.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            # Widget-local coordinates: origin is (0,0)
            # Text should be at 0 + padding
            # draw_text compensates for SFML local_bounds offsets
            text.position.x.should be_close(10.0, 2.0)  # 0 + 10, with offset tolerance
            # Text should be vertically centered: 0 + (height - font_size) / 2
            expected_y = 0.0 + (28.0 - 14.0) / 2.0  # font_size = 14 at scale 0
            text.position.y.should be_close(expected_y, 10.0)  # top offset varies by font
        end

        it "text primitive has correct font size" do
            menu = CrymbleUI::Menu.new("File", font_scale: 1)
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            primitives = menu.to_primitives(bounds)
            text = primitives[2].as(CrymbleUI::DrawText)

            text.size.should be_close(15.4, 0.1)  # scale 1 = 14 * 1.1
        end

    end

    describe "primitive caching" do
        it "caches primitives with Dynamic policy (default)" do
            menu = CrymbleUI::Menu.new("Cached")
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            # First call generates
            primitives1 = menu.get_primitives(bounds)
            menu.clear_render_state_recursive  # Mark clean

            # Second call returns cached
            primitives2 = menu.get_primitives(bounds)

            primitives1.should be(primitives2)  # Same object
        end

        it "regenerates when hover state changes" do
            menu = CrymbleUI::Menu.new("Hover")
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            primitives1 = menu.get_primitives(bounds)

            # on_mouse_enter calls mark_needs_render
            menu.on_mouse_enter

            primitives2 = menu.get_primitives(bounds)

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)
        end

        it "regenerates when label changes" do
            menu = CrymbleUI::Menu.new("Original")
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            primitives1 = menu.get_primitives(bounds)

            # label_text= calls mark_needs_render
            menu.label_text = "Modified"

            primitives2 = menu.get_primitives(bounds)

            # Should be different objects (regenerated)
            primitives1.should_not be(primitives2)
        end

        it "regenerates when visual properties change" do
            menu = CrymbleUI::Menu.new("Style")
            bounds = CrymbleUI::Rect.new(0, 0, 60, 28)

            primitives1 = menu.get_primitives(bounds)
            bg1 = primitives1[0].as(CrymbleUI::FillRect)

            # background_color= calls mark_needs_render
            new_color = CrymbleUI::Color.new(255, 0, 0, 255)
            menu.background_color = new_color

            primitives2 = menu.get_primitives(bounds)
            bg2 = primitives2[0].as(CrymbleUI::FillRect)

            bg1.color.should_not eq(new_color)
            bg2.color.should eq(new_color)
        end
    end
end
