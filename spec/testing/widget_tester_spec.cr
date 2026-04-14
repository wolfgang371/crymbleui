require "../spec_helper"
require "../../src/testing/widget_tester"

# Test app for WidgetTester specs
class CounterApp < CrymbleUI::App
    property count : Int32 = 0
    property build_count : Int32 = 0

    def build : CrymbleUI::Widget
        @build_count += 1

        vstack = CrymbleUI::VStack.new(id: "container", spacing: 10.0)
        vstack.add_child(CrymbleUI::Text.new("Count: #{@count}", id: "counter_text"))

        button = TestWidget.new(id: "increment_btn")
        vstack.add_child(button)

        vstack
    end
end

describe CrymbleUI::Testing::WidgetTester do
    describe "#initialize" do
        it "creates tester with default window size" do
            tester = CrymbleUI::Testing::WidgetTester.new
            tester.window_size.width.should eq(800.0)
            tester.window_size.height.should eq(600.0)
        end

        it "creates tester with custom window size" do
            tester = CrymbleUI::Testing::WidgetTester.new(
                window_size: CrymbleUI::Size.new(1024.0, 768.0)
            )
            tester.window_size.width.should eq(1024.0)
            tester.window_size.height.should eq(768.0)
        end

        it "starts with no app" do
            tester = CrymbleUI::Testing::WidgetTester.new
            tester.app.should be_nil
        end
    end

    describe "#pump" do
        it "builds the app widget tree" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new

            tester.pump(app)

            app.root.should_not be_nil
            app.build_count.should eq(1)
        end

        it "lays out the widget tree" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new

            tester.pump(app)

            root = app.root.not_nil!
            # Bounds should be set
            root.bounds.width.should be > 0
            root.bounds.height.should be > 0
        end

        it "stores the app" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new

            tester.pump(app)

            tester.app.should eq(app)
        end
    end

    describe "#find" do
        it "finds widget by ID" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            widget = tester.find("counter_text")
            widget.should_not be_nil
            widget.not_nil!.id.should eq("counter_text")
        end

        it "returns nil for non-existent ID" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            widget = tester.find("non_existent")
            widget.should be_nil
        end

        it "returns nil when no app is pumped" do
            tester = CrymbleUI::Testing::WidgetTester.new

            widget = tester.find("anything")
            widget.should be_nil
        end
    end

    describe "#find_by_path" do
        it "finds widget by path ID" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            widget = tester.find_by_path("container/counter_text")
            widget.should_not be_nil
            widget.not_nil!.id.should eq("counter_text")
        end
    end

    describe "#find_all" do
        it "finds all widgets matching condition" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            texts = tester.find_all { |w| w.is_a?(CrymbleUI::Text) }
            texts.size.should eq(1)
        end

        it "returns empty array when no app is pumped" do
            tester = CrymbleUI::Testing::WidgetTester.new

            widgets = tester.find_all { |w| true }
            widgets.should be_empty
        end
    end

    describe "#tap" do
        it "triggers click on widget" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            button = tester.find("increment_btn").as(TestWidget)
            button.click_count.should eq(0)

            tester.tap(button)

            button.click_count.should eq(1)
        end

        it "triggers click by widget ID" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            button = tester.find("increment_btn").as(TestWidget)

            tester.tap("increment_btn")

            button.click_count.should eq(1)
        end

        it "raises error if widget ID not found" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            expect_raises(Exception, /not found/) do
                tester.tap("non_existent")
            end
        end

        it "rebuilds app if rebuild was requested" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            # Trigger rebuild by requesting it explicitly
            app.request_rebuild

            initial_builds = app.build_count

            tester.tap("increment_btn")

            # Should have rebuilt
            app.build_count.should be > initial_builds
        end
    end

    describe "#root" do
        it "returns the root widget" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            root = tester.root
            root.should_not be_nil
            root.not_nil!.id.should eq("container")
        end

        it "returns nil when no app is pumped" do
            tester = CrymbleUI::Testing::WidgetTester.new

            tester.root.should be_nil
        end
    end

    describe "#exists?" do
        it "returns true for existing widget" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            tester.exists?("counter_text").should be_true
        end

        it "returns false for non-existent widget" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            tester.exists?("non_existent").should be_false
        end
    end

    describe "#text" do
        it "gets text content from Text widget" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            text = tester.text("counter_text")
            text.should eq("Count: 0")
        end

        it "returns nil for non-Text widget" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            text = tester.text("increment_btn")
            text.should be_nil
        end

        it "returns nil for non-existent widget" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new
            tester.pump(app)

            text = tester.text("non_existent")
            text.should be_nil
        end
    end

    describe "integration test" do
        it "supports full testing workflow" do
            tester = CrymbleUI::Testing::WidgetTester.new
            app = CounterApp.new

            # Build app
            tester.pump(app)

            # Verify initial state
            tester.exists?("counter_text").should be_true
            tester.text("counter_text").should eq("Count: 0")

            # Find widgets
            container = tester.find("container")
            container.should_not be_nil
            container.not_nil!.children.size.should eq(2)

            # Test widget properties
            button = tester.find("increment_btn").as(TestWidget)
            button.click_count.should eq(0)

            # Trigger interaction
            tester.tap("increment_btn")
            button.click_count.should eq(1)

            # Verify widget tree structure
            root = tester.root.not_nil!
            root.is_a?(CrymbleUI::VStack).should be_true
        end
    end
end
