require "../spec_helper"
require "../../src/testing/test_renderer"

# TestRenderer installs a TestClipboard only when nothing has installed one, so a
# consumer suite that never installs one (embrace does not) does not trip over
# `Widget.clipboard`'s raise. The install MUST stay conditional: an unconditional
# one would clobber the instance a suite's spec_helper installed and its specs are
# mid-example holding — which is exactly the hazard the neighbouring focus_manager
# install is documented against.
#
# This guard is what stops someone deleting the `unless Widget.clipboard?`: without
# it, that deletion is invisible to the suite (crymbleui always has one installed,
# so the true-branch never runs here).
describe CrymbleUI::Testing::TestRenderer do
    describe "clipboard install" do
        it "never clobbers a clipboard that is already installed" do
            before = CrymbleUI::Widget.clipboard
            before.text = "owned by the suite"

            CrymbleUI::Testing::TestRenderer.new(200, 100)

            CrymbleUI::Widget.clipboard.should be(before)
            CrymbleUI::Widget.clipboard.text.should eq("owned by the suite")
        end
    end
end
