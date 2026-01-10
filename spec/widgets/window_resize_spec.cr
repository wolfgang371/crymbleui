require "../spec_helper"

# Test that Window widget respects actual window size from constraints
class WindowResizeTestApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        window("Test", 600, 500) do
            vstack do
                text("Test content")
            end
        end
    end
end

describe CrymbleUI::Window do
    describe "window resize" do
        it "uses actual window size from constraints, not declared size" do
            app = WindowResizeTestApp.new
            app.build_tree
            root = app.root.not_nil!

            # Initial layout at declared size (600x500) - using loose constraints like real app
            constraints_initial = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(600.0, 500.0))
            root.layout(constraints_initial, CrymbleUI::Vec2.zero)

            root.bounds.width.should eq(600.0)
            root.bounds.height.should eq(500.0)

            # Simulate window resize to larger size (600x632) - using loose constraints like real app
            constraints_resized = CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(600.0, 632.0))
            root.layout(constraints_resized, CrymbleUI::Vec2.zero)

            # Window bounds should reflect ACTUAL window size, not declared size
            root.bounds.width.should eq(600.0)
            root.bounds.height.should eq(632.0)  # This should match actual window, not 500.0

            # Children should also get the new size (minus CONTENT_PADDING on all sides)
            vstack = root.children.first
            padding = CrymbleUI::Window::CONTENT_PADDING * 2  # Left+right or top+bottom
            vstack.bounds.width.should eq(600.0 - padding)   # 584.0
            vstack.bounds.height.should eq(632.0 - padding)  # 616.0
        end
    end
end
