require "../spec_helper"
require "../../src/core/theme"

# Tests that verify widgets honor Theme.current for their default colors.
# Theme-derived colors are resolved LIVE (no construction snapshot), so an
# existing widget FOLLOWS a later Theme.set; an explicit color override still wins. This reverses the
# earlier snapshot-stability contract (a widget froze its color at construction) — see git history.
describe "Theme widget integration" do
  before_each do
    CrymbleUI::Theme.set(:light)
  end

  after_each do
    CrymbleUI::Theme.set(:light) # don't leak a swapped theme into other spec files
  end

  describe "Button" do
    it "uses theme button_text as default text_color" do
      btn = CrymbleUI::Button.new("Test")
      btn.text_color.should eq CrymbleUI::Theme.current.button_text
    end

    it "uses theme button_background as default background_color" do
      btn = CrymbleUI::Button.new("Test")
      btn.background_color.should eq CrymbleUI::Theme.current.button_background
    end

    it "uses theme button_border as default border_color" do
      btn = CrymbleUI::Button.new("Test")
      btn.border_color.should eq CrymbleUI::Theme.current.button_border
    end

    it "allows explicit color override" do
      custom = CrymbleUI::Color.new(255, 0, 0, 255)
      btn = CrymbleUI::Button.new("Test", text_color: custom)
      btn.text_color.should eq custom
    end
  end

  describe "Text" do
    it "uses theme text_default as default color" do
      t = CrymbleUI::Text.new("Hello")
      t.color.should eq CrymbleUI::Theme.current.text_default
    end
  end

  describe "TextInput" do
    it "uses theme input colors as defaults" do
      ti = CrymbleUI::TextInput.new
      ti.text_color.should eq CrymbleUI::Theme.current.input_text
      ti.background_color.should eq CrymbleUI::Theme.current.input_background
      ti.border_color.should eq CrymbleUI::Theme.current.input_border
      ti.focused_border_color.should eq CrymbleUI::Theme.current.input_border_focused
      ti.placeholder_color.should eq CrymbleUI::Theme.current.input_placeholder
    end
  end

  describe "widgets follow a live theme switch (no construction snapshot)" do
    it "an existing Button's colors follow Theme.current after a later switch" do
      CrymbleUI::Theme.set(:dark)
      btn = CrymbleUI::Button.new("X")
      btn.background_color.should eq CrymbleUI::Theme.current.button_background # dark now
      # Switching the theme must recolor the EXISTING button (live), not freeze its construction color.
      CrymbleUI::Theme.set(:light)
      btn.background_color.should eq CrymbleUI::Theme.current.button_background # follows → light
    end

    it "an existing Text's color follows Theme.current after a later switch" do
      CrymbleUI::Theme.set(:dark)
      t = CrymbleUI::Text.new("X")
      t.color.should eq CrymbleUI::Theme.current.text_default # dark
      CrymbleUI::Theme.set(:light)
      t.color.should eq CrymbleUI::Theme.current.text_default # follows → light
    end

    it "an explicit color override wins and does NOT follow the theme" do
      custom = CrymbleUI::Color.new(255, 0, 0, 255)
      btn = CrymbleUI::Button.new("X", background_color: custom)
      CrymbleUI::Theme.set(:dark)
      btn.background_color.should eq custom # override is sticky; only theme DEFAULTS are live
    end
  end

  describe "Theme.current_name" do
    it "tracks the active theme name across set (for a live theme toggle)" do
      CrymbleUI::Theme.set(:light)
      CrymbleUI::Theme.current_name.should eq :light
      CrymbleUI::Theme.set(:dark)
      CrymbleUI::Theme.current_name.should eq :dark
    end
  end

  # Theme.ref(&.key) = a LIVE theme-color reference a call site can pass when it needs a DIFFERENT
  # theme key than the widget's own default (e.g. ruler labels use ruler_label, not text_default).
  # Unlike a snapshotted Theme.current.<key> arg (a sticky override), a ref follows Theme.set.
  describe "Theme.ref (live custom theme-color reference)" do
    after_each { CrymbleUI::Theme.set(:light) }

    it "a color passed as Theme.ref follows the theme live" do
      CrymbleUI::Theme.set(:light)
      btn = CrymbleUI::Button.new("X", text_color: CrymbleUI::Theme.ref(&.text_default))
      btn.text_color.should eq CrymbleUI::Theme.current.text_default # light
      CrymbleUI::Theme.set(:dark)
      btn.text_color.should eq CrymbleUI::Theme.current.text_default # follows → dark
    end

    it "an explicit Color override still wins over the theme" do
      custom = CrymbleUI::Color.new(1, 2, 3, 255)
      btn = CrymbleUI::Button.new("X", text_color: custom)
      CrymbleUI::Theme.set(:dark)
      btn.text_color.should eq custom
    end
  end
end
