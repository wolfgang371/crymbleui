require "../spec_helper"
require "../../src/testing/test_renderer"
require "../../src/widgets/window"
require "../../src/widgets/button"
require "../../src/input/focus_manager"

# Models a dialog that opens (a focusable widget is present) then closes (the
# widget is removed on the next rebuild). The bug: nothing reconciles focus on
# rebuild, so @focused_widget keeps pointing at the orphaned widget — which then
# swallows keys (e.g. a TextInput consumes Alt+Left, so the panel shortcut never
# fires until the user clicks back into the panel).
class FocusDropApp < CrymbleUI::App
  state show : Bool = true

  def build : CrymbleUI::Widget
    window("Test", 400, 300) do
      if @show
        button("dialog field", id: "dlg") { }
      else
        button("other", id: "other") { }
      end
    end
  end
end

describe "FocusManager: focus reconciled on rebuild" do
  it "drops focus when the focused widget is removed from the tree" do
    fm = CrymbleUI::FocusManager.new
    CrymbleUI::Widget.focus_manager = fm
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300)
    CrymbleUI::Widget.focus_manager = fm # re-assert (renderer installs its own)

    app = FocusDropApp.new
    app.build_tree
    renderer.settle_rendering(app)

    dlg = app.find("dlg").not_nil!
    fm.focus(dlg)
    fm.focused_widget.should eq(dlg)

    app.show = false # "close the dialog"
    app.rebuild      # dlg leaves the tree

    # Must be cleared — otherwise the orphaned widget keeps eating key events.
    fm.focused_widget.should be_nil
  end
end
