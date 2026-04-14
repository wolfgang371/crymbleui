require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/combo_box"
require "../../src/widgets/window"
require "../../src/layout/vstack"

# DSL app where app state controls the combo selection
# On each build(), the combo gets `selected: @pick`
class ComboSelectionApp < CrymbleUI::App
    state pick : Int32 = 0

    def build : CrymbleUI::Widget
        window("Test", 400, 300) do
            combo_box(items: ["Alpha", "Bravo", "Charlie"], selected: @pick, id: "combo") do |i|
                self.pick = i
            end
        end
    end
end

describe "ComboBox reconcile_property vs build value" do
    it "uses build value when app programmatically changes selected_index" do
        renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
        app = ComboSelectionApp.new
        app.build_tree
        renderer.settle_rendering(app)

        combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
        combo.selected_index.should eq(0)

        # App changes selection programmatically (not via user click)
        app.pick = 2
        # state setter triggers request_rebuild → rebuild creates NEW combo with selected: 2
        app.rebuild

        combo = app.find("combo").not_nil!.as(CrymbleUI::ComboBox)
        combo.selected_index.should eq(2)
    end
end
