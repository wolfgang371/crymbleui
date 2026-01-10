require "../spec_helper"

# Concrete app implementation for app_spec testing
# NOTE: Named AppSpecTestApp to avoid conflict with TestApp in spec_helper.cr
class AppSpecTestApp < CrymbleUI::App
    property build_count : Int32 = 0
    property root_widget_id : String = "root"

    def build : CrymbleUI::Widget
        @build_count += 1
        widget = TestWidget.new(id: @root_widget_id)

        # Add some children for testing
        widget.add_child(TestWidget.new(id: "child1"))
        widget.add_child(TestWidget.new(id: "child2"))

        widget
    end
end

# Test app for state macro batching tests
class BatchingTestApp < CrymbleUI::App
    state click_count : Int32 = 0
    state last_clicked : String = "none"

    def build : CrymbleUI::Widget
        window = CrymbleUI::Window.new("Test", 800, 600)

        # Mimic stress test: button click changes TWO state variables
        button = CrymbleUI::Button.new("Test Button", id: "btn") {
            self.click_count += 1      # State change 1
            self.last_clicked = "btn"  # State change 2
        }

        window.add_child(button)
        window
    end
end

describe CrymbleUI::App do
    describe "#initialize" do
        it "starts with no root widget" do
            app = AppSpecTestApp.new
            app.root.should be_nil
        end
    end

    describe "#build_tree" do
        it "calls build method" do
            app = AppSpecTestApp.new
            app.build_tree

            app.build_count.should eq(1)
        end

        it "sets root widget" do
            app = AppSpecTestApp.new
            app.build_tree

            app.root.should_not be_nil
            app.root.not_nil!.id.should eq("root")
        end

    end

    describe "#find" do
        it "finds widget by ID" do
            app = AppSpecTestApp.new
            app.build_tree

            widget = app.find("child1")
            widget.should_not be_nil
            widget.not_nil!.id.should eq("child1")
        end

        it "returns nil if widget not found" do
            app = AppSpecTestApp.new
            app.build_tree

            widget = app.find("nonexistent")
            widget.should be_nil
        end

        it "returns nil if tree not built yet" do
            app = AppSpecTestApp.new

            widget = app.find("root")
            widget.should be_nil
        end
    end

    describe "#find_by_path" do
        it "finds widget by path ID" do
            app = AppSpecTestApp.new
            app.build_tree

            widget = app.find_by_path("root/child1")
            widget.should_not be_nil
            widget.not_nil!.id.should eq("child1")
        end
    end

    describe "#find_all" do
        it "finds all widgets matching condition" do
            app = AppSpecTestApp.new
            app.build_tree

            children = app.find_all { |w| w.id.try(&.starts_with?("child")) || false }
            children.size.should eq(2)
        end

        it "returns empty array if tree not built" do
            app = AppSpecTestApp.new

            results = app.find_all { |w| true }
            results.should be_empty
        end
    end

    describe "#rebuild" do
        it "calls build_tree again" do
            app = AppSpecTestApp.new
            app.build_tree
            app.build_tree

            app.build_count.should eq(2)
        end

        it "creates new root widget" do
            app = AppSpecTestApp.new
            app.build_tree
            old_root = app.root

            app.root_widget_id = "new_root"
            app.rebuild

            app.root.should_not eq(old_root)
            app.root.not_nil!.id.should eq("new_root")
        end
    end

    describe "state macro batching optimization" do
        it "manually calling rebuild increments counter (sanity check)" do
            app = BatchingTestApp.new
            app.build_tree

            CrymbleUI::App.reset_rebuild_count
            app.rebuild
            CrymbleUI::App.rebuild_count.should eq(1)
        end

        it "batches multiple state changes into single rebuild" do
            # Tests that multiple state changes in one callback are batched:
            # - State changes call mark_needs_layout (don't rebuild immediately)
            # - Event loop checks needs_layout and rebuilds once
            # Result: 2 state changes → 1 rebuild (not 2)

            app = BatchingTestApp.new
            app.build_tree

            CrymbleUI::App.reset_rebuild_count

            # Click button - changes TWO state variables
            button = app.find("btn")
            button.not_nil!.trigger_click

            # Simulate event loop: check needs_layout and rebuild once
            if app.root.not_nil!.needs_layout?
                app.rebuild
            end

            # With batching: 2 state changes mark dirty, event loop rebuilds once
            CrymbleUI::App.rebuild_count.should eq(1)
        end
    end
end
