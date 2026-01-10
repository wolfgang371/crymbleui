require "../spec_helper"
require "../../src/core/types"
require "../../src/core/widget"
require "../../src/core/app"
require "../../src/widgets/text"
require "../../src/widgets/button"
require "../../src/layout/vstack"
require "../../src/layout/hstack"

class NestedVStackApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        vstack(id: "outer") do
            text("Header")
            vstack(id: "inner") do
                text("Nested")
            end
        end
    end
end

class NestedHStackApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        vstack(id: "container") do
            hstack(id: "row1") do
                text("A")
                text("B")
            end
            hstack(id: "row2") do
                text("C")
                text("D")
            end
        end
    end
end

class TimesBlockApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        vstack(id: "container") do
            3.times do |i|
                hstack(id: "row_#{i}") do
                    2.times do |j|
                        button("#{i},#{j}") { }
                    end
                end
            end
        end
    end
end

class GridApp < CrymbleUI::App
    def build : CrymbleUI::Widget
        vstack do
            3.times do |row|
                hstack do
                    4.times do |col|
                        button("#{row},#{col}") { }
                    end
                end
            end
        end
    end
end

describe CrymbleUI::DSL::BuilderMethods do
    describe "nested containers" do
        it "adds nested vstacks to parent" do
            app = NestedVStackApp.new

            app.build_tree
            root = app.root.not_nil!

            # Should have outer vstack + header text + inner vstack + nested text
            widgets = root.find_all { |w| true }
            widgets.size.should eq(4)

            # Inner vstack should be child of outer
            inner = app.find("inner")
            inner.should_not be_nil
            inner.not_nil!.parent.should eq(root)
        end

        it "adds nested hstacks to parent vstack" do
            app = NestedHStackApp.new

            app.build_tree
            root = app.root.not_nil!

            # vstack + 2 hstacks + 4 texts = 7 widgets
            widgets = root.find_all { |w| true }
            widgets.size.should eq(7)

            # Both hstacks should be children of vstack
            row1 = app.find("row1")
            row2 = app.find("row2")
            row1.not_nil!.parent.should eq(root)
            row2.not_nil!.parent.should eq(root)
        end

        it "works with containers inside .times blocks" do
            app = TimesBlockApp.new

            app.build_tree
            root = app.root.not_nil!

            # vstack + 3 hstacks + 6 buttons = 10 widgets
            widgets = root.find_all { |w| true }
            widgets.size.should eq(10)

            # All hstacks should be children of vstack
            (0..2).each do |i|
                hstack = app.find("row_#{i}")
                hstack.should_not be_nil
                hstack.not_nil!.parent.should eq(root)
                # Each hstack should have 2 button children
                hstack.not_nil!.children.size.should eq(2)
            end
        end

        it "creates grid layout with nested loops" do
            rows = 3
            cols = 4

            app = GridApp.new

            app.build_tree
            root = app.root.not_nil!

            # 1 vstack + 3 hstacks + 12 buttons = 16 widgets
            widgets = root.find_all { |w| true }
            widgets.size.should eq(1 + rows + (rows * cols))

            # Verify structure
            buttons = widgets.select { |w| w.is_a?(CrymbleUI::Button) }
            buttons.size.should eq(rows * cols)
        end
    end
end
