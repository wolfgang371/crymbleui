require "../spec_helper"
require "../../src/testing/test_renderer"

# theme_property is a theme-resolving view over a value: nil follows the live theme
# (Theme.current.<key>, reactive because Theme.current is a Source), a concrete Color is a
# sticky override, and a ThemeColorRef resolves a different key. This pins the behavior the
# macro must preserve — especially that an override re-renders the (node-backed) widget.
describe "theme_property" do
  it "follows the theme by default, overrides win, and clearing follows again — all reactive" do
    CrymbleUI::Theme.set(:light)
    renderer = CrymbleUI::Testing::TestRenderer.new(200, 100)
    app = TestApp.new
    button = CrymbleUI::Button.new("Hi") { }
    app.root_widget = button
    app.build_tree
    renderer.settle_rendering(app)

    # Default (nil): follows the live theme, and is clean after settling.
    button.text_color.should eq CrymbleUI::Theme.current.button_text
    button.needs_render?.should be_false

    # An explicit override re-renders the rendered widget AND wins over the theme.
    override = CrymbleUI::Color.new(1, 2, 3, 255)
    button.text_color = override
    button.needs_render?.should be_true # the reactivity the macro must preserve
    button.text_color.should eq override

    # A theme switch does not move an explicitly-overridden color.
    renderer.settle_rendering(app)
    CrymbleUI::Theme.set(:dark)
    button.text_color.should eq override

    # Clearing the override (nil) re-renders and follows the (now dark) theme again.
    button.text_color = nil
    button.needs_render?.should be_true
    button.text_color.should eq CrymbleUI::Theme.current.button_text

    CrymbleUI::Theme.set(:light) # restore global theme for other specs
  end
end
