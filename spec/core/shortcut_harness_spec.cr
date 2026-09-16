require "../spec_helper"
require "../../src/crymble-ui"
require "../../src/testing/test_renderer"

class ShortcutPanelApp < CrymbleUI::App
  include CrymbleUI::DSL::BuilderMethods
  property fired = 0

  def build : CrymbleUI::Widget
    window("t", 400, 300) do
      window_panel("Dialog", x: 10.0, y: 10.0, width: 200.0, height: 100.0, id: "dlg") do
        register_shortcut("Escape") { @fired += 1 }
        text("body")
      end
    end
  end
end

# The headless harness must be able to FIRE a shortcut, not merely watch one register.
#
# Until 2026-09-12 TestRenderer installed a stub manager and left Widget.shortcut_manager unset,
# so `register_shortcut` in the DSL returned early and no shortcut in any headless test existed at
# all: a dialog's Escape, a confirm box's Enter, every panel binding. Specs could only assert that
# the code calling register_shortcut had run.
#
# Note the ORDER below, which is the contract: the manager must exist when the tree is BUILT.
# Build first and the registration is skipped, silently, exactly as it was for everyone before.
describe "headless shortcuts" do
  it "fires a panel shortcut registered through the DSL" do
    app = ShortcutPanelApp.new
    renderer = CrymbleUI::Testing::TestRenderer.new(400, 300) # installs the manager
    app.build_tree                                            # ... which must exist by build time
    renderer.settle_rendering(app)

    panel = app.find("dlg").not_nil!
    CrymbleUI::Widget.shortcut_manager.trigger("Escape", panel.path_id).should be_true
    app.fired.should eq(1)
  end
end
