require "../spec_helper"
require "../../src/widgets/combo_box"
require "../../src/widgets/combo_box_popup"
require "../../src/widgets/window"
require "../../src/testing/test_renderer"
require "../../src/dsl/builder"

# Lazy-items ComboBox: the collapsed cell shows a caller-supplied string in O(1); the (potentially
# large) item list + colors + selected index + per-item payloads are produced by a provider only on
# first expand. select_and_close delivers the PAYLOAD (e.g. a reference rank) of the picked item, and
# the payloads ride reconcile so a pick after a rebuild-while-open still resolves correctly.

private class LazyComboApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods

  property provider_calls = 0
  property picked : Int32? = nil
  property display : String = "SEL"

  def build : CrymbleUI::Widget
    window("T", 400, 300) do
      vstack do
        widget(CrymbleUI::ComboBox.new(
          selected_text: display,
          items_provider: -> {
            self.provider_calls += 1
            {items: ["a", "b", "c"], colors: nil.as(Array(CrymbleUI::Color)?), selected: 0, payloads: [10, 20, 30]}
          },
          id: "lazy",
        ) do |payload, _val|
          self.picked = payload
        end)
      end
    end
  end

  # the LIVE combo in the reconciled tree (build_tree/rebuild set @root)
  def combo : CrymbleUI::ComboBox
    find("lazy").not_nil!.as(CrymbleUI::ComboBox)
  end
end

private def click(app, widget)
  b = widget.absolute_bounds
  c = CrymbleUI::Vec2.new(b.x + b.width / 2, b.y + b.height / 2)
  app.handle_mouse_down(c)
  app.handle_mouse_up(c)
end

describe "ComboBox lazy-items" do
  it "does not run the provider until expand; the collapsed cell shows selected_text (O(1))" do
    app = LazyComboApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    renderer.settle_rendering(app)

    app.provider_calls.should eq(0) # never enumerated for the collapsed cell
    combo = app.combo
    combo.selected_value.should eq("SEL")
    combo.measure(CrymbleUI::BoxConstraints.loose(CrymbleUI::Size.new(200.0, 30.0)))
    app.provider_calls.should eq(0) # measure is O(1) too
  end

  it "runs the provider once on expand and delivers the picked item's PAYLOAD, not its index" do
    app = LazyComboApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    renderer.settle_rendering(app)

    combo = app.combo
    click(app, combo) # expand
    renderer.settle_rendering(app)
    app.provider_calls.should eq(1)

    combo = app.combo
    popup = combo.current_popup.not_nil!
    popup.item_widgets.size.should eq(3)
    click(app, popup.item_widgets[1]) # pick "b" (index 1 -> payload 20)
    renderer.settle_rendering(app)

    app.picked.should eq(20) # the payload, not the index (1)
  end

  it "keeps the correct payload on a pick after a rebuild-while-open (payloads ride reconcile)" do
    app = LazyComboApp.new
    app.build_tree
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    renderer.settle_rendering(app)

    combo = app.combo
    click(app, combo) # expand
    renderer.settle_rendering(app)

    # A rebuild WHILE the popup is open reconciles the combo (copy_state_from carries the open popup).
    app.request_rebuild
    renderer.settle_rendering(app)

    combo = app.combo
    combo.popup_open?.should be_true
    popup = combo.current_popup.not_nil!
    click(app, popup.item_widgets[2]) # pick "c" -> payload 30
    renderer.settle_rendering(app)

    app.picked.should eq(30) # payload from the run that built the shown popup, not the index (2)
  end
end
